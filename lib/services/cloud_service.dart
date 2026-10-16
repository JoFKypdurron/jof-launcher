import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:io' as io show Directory, File, SecurityContext, Process, FileSystemEntity, FileSystemEntityType, Platform, Request, BadCertificateCallback, IOSink, FileMode, FileSystemException, RandomAccessFile, SocketException, HttpException;
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart' show kIsWeb;
import '../models/asset.dart';
import '../models/asset_group.dart';
import '../models/client_channel.dart';
import '../models/platform_arch.dart';
import '../models/repository_source.dart';
import 'client_release_service.dart';
import 'secure_http_client.dart';
import 'connectivity_service.dart';
import 'log_service.dart';
import 'settings_service.dart';
import 'system_arch_service.dart';
import 'package:path/path.dart' as p;
import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';

import 'package:flutter/foundation.dart' show visibleForTesting;

enum AssetStatus {
  notDownloaded,
  downloaded,
  needsUpdate,
  stagedDownloaded,
  stagedForRemoval,
}

class CloudData {
  final List<AssetGroup> clientGroups;
  final List<AssetGroup> modGroups;
  final List<AssetGroup> assetGroups;
  final List<AssetGroup> otherGroups;

  CloudData({
    required this.clientGroups,
    required this.modGroups,
    required this.assetGroups,
    required this.otherGroups,
  });

  List<AssetGroup> get allGroups => [...clientGroups, ...modGroups, ...assetGroups, ...otherGroups];

  AssetGroup? findGroup(String category, int id) {
    List<AssetGroup> targetList;
    switch (category.toLowerCase()) {
      case 'clientgroups':
        targetList = clientGroups;
        break;
      case 'modgroups':
        targetList = modGroups;
        break;
      case 'assetgroups':
        targetList = assetGroups;
        break;
      case 'othergroups':
        targetList = otherGroups;
        break;
      default:
        targetList = allGroups;
    }

    try {
      return targetList.firstWhere((g) => g.id == id);
    } catch (_) {
      try {
        return allGroups.firstWhere((g) => g.id == id);
      } catch (_) {
        return null;
      }
    }
  }

  Set<AssetGroup> resolveDependencies(AssetGroup group) {
    Set<AssetGroup> resolved = {group};
    _resolveRecursive(group, resolved);
    return resolved;
  }

  void _resolveRecursive(AssetGroup group, Set<AssetGroup> resolved) {
    if (group.dependsOn == null || group.dependsOn!.isEmpty) return;

    // Expected formats: "modgroups 10", "modgroups id 10", or just "10"
    final parts = group.dependsOn!.trim().split(' ');
    
    String category = '';
    int? id;

    if (parts.length >= 2) {
      category = parts[0];
      id = int.tryParse(parts.last);
    } else if (parts.isNotEmpty) {
      id = int.tryParse(parts[0]);
    }

    if (id == null) return;

    final dependentGroup = findGroup(category, id);
    if (dependentGroup != null && !resolved.contains(dependentGroup)) {
      resolved.add(dependentGroup);
      _resolveRecursive(dependentGroup, resolved);
    }
  }
}

/// One EternalJK client build: a release version and the asset for this
/// platform and architecture.
class ClientTarget {
  /// Shown in progress messages, e.g. "Downloading Windows files".
  final String platformName;
  final String version;
  final String assetName;

  /// The digest GitHub publishes for the asset, or null when it could not be
  /// looked up.
  final String? sha256;

  /// False when GitHub could not say which release is current and [version]
  /// is [ClientReleaseService.fallbackVersion]. Such a target only installs a
  /// client where none exists; it never replaces one.
  final bool versionConfirmed;

  const ClientTarget({
    required this.platformName,
    required this.version,
    required this.assetName,
    this.sha256,
    this.versionConfirmed = true,
  });

  String get url => ClientReleaseService.downloadUrl(version, assetName);
}

class CloudService {
  static const Set<String> _linuxStaticManagedRelativePaths = {
    'eternaljk.x86_64',
    'rd-eternaljk_x86_64.so',
    'EternalJK/cgamex86_64.so',
    'EternalJK/data.db',
    'EternalJK/jampgamex86_64.so',
    'EternalJK/uix86_64.so',
  };

  CloudData? _cachedCloudData;

  final ConnectivityService _connectivity;

  /// Test seam: when set, used instead of building a real `IOClient`.
  final http.Client Function()? _httpClientFactory;

  final ClientReleaseService _clientRelease;

  final SystemArchService _systemArch;

  /// Delay before retry [attempt] of a download. Test seam.
  final Duration Function(int attempt) _retryBackoff;

  /// The endpoint that answered the most recent manifest fetch.
  RepositoryEndpoint? _manifestEndpoint;

  /// Set when the mirror has proven unreliable this session: `auto` fetched
  /// the manifest from the origin because the mirror failed, or a file had to
  /// leave the mirror over a network error. Files are still tried on the
  /// mirror, but abandoned quickly. Cleared by the next manifest fetch.
  bool _mirrorDegraded = false;

  /// Files in a row that left the mirror over network errors. At
  /// [_mirrorBreakerThreshold] the mirror is skipped for files until the next
  /// manifest fetch, so a black-holed mirror does not cost a timeout per file.
  int _mirrorNetworkFailureStreak = 0;

  CloudService({
    ConnectivityService? connectivity,
    http.Client Function()? httpClientFactory,
    ClientReleaseService? clientRelease,
    SystemArchService? systemArchService,
    Duration Function(int attempt)? retryBackoff,
  })  : _connectivity = connectivity ?? ConnectivityService(),
        _httpClientFactory = httpClientFactory,
        _clientRelease = clientRelease ??
            ClientReleaseService(httpClientFactory: httpClientFactory),
        _systemArch = systemArchService ?? SystemArchService(),
        _retryBackoff = retryBackoff ?? _defaultRetryBackoff;

  /// Exponential backoff, 2s..30s.
  static Duration _defaultRetryBackoff(int attempt) =>
      Duration(seconds: (1 << attempt.clamp(1, 5)).clamp(2, 30));

  /// The endpoint that answered the most recent manifest fetch, or null before
  /// the first successful one.
  RepositoryEndpoint? get manifestEndpoint => _manifestEndpoint;

  /// Timeout for establishing a connection / receiving response headers.
  static const Duration _connectTimeout = Duration(seconds: 30);

  /// Idle timeout between received chunks. A stalled (half-open) socket trips
  /// this and throws, instead of hanging the download forever.
  static const Duration _idleTimeout = Duration(seconds: 30);

  /// Received bytes are coalesced into writes of this size. The HTTP stream
  /// delivers ~5 KB chunks, and one async file write per chunk measurably
  /// throttles throughput on fast connections.
  static const int _writeBufferSize = 1 << 20;

  /// Minimum interval between progress callbacks. Each callback rebuilds UI
  /// state, so firing it per network chunk (thousands per file) is wasteful.
  static const Duration _progressInterval = Duration(milliseconds: 100);

  /// Manifest timeout for a source that has a fallback behind it. Short, so a
  /// down mirror does not hold up the launcher.
  static const Duration _fallbackManifestTimeout = Duration(seconds: 10);

  /// Network failures (while online) a healthy mirror gets per file before
  /// the file falls back to the origin.
  static const int _mirrorMaxNetworkFailures = 3;

  /// Connect timeout for a degraded mirror, which gets a single attempt.
  static const Duration _degradedMirrorConnectTimeout = Duration(seconds: 5);

  static const int _mirrorBreakerThreshold = 3;

  http.Client _createHttpClient() {
    final factory = _httpClientFactory;
    if (factory != null) {
      return factory();
    }
    return createSecureHttpClient(connectionTimeout: _connectTimeout);
  }

  Future<AssetStatus> getAssetStatus(Asset asset, String downloadDir) async {
    if (kIsWeb) return AssetStatus.notDownloaded;

    final finalDownloadDir = await _getActualTargetDir(downloadDir, asset.targetFolder);
    final filePath = p.join(finalDownloadDir, asset.name);
    final file = io.File(filePath);

    if (!await file.exists()) {
      return AssetStatus.notDownloaded;
    }

    try {
      // Check file size first as a quick check
      final fileSize = await file.length();
      if (fileSize != asset.size) {
        return AssetStatus.needsUpdate;
      }

      // Check last modified time against asset's lastUpdate
      final fileLastModified = await file.lastModified();
      final timestampMismatch = fileLastModified.isBefore(asset.lastUpdate);
      
      // If size matches but timestamp suggests update, verify with hash
      if (timestampMismatch) {
        final fileHash = await _calculateFileHash(file);
        if (fileHash != asset.hash) {
          return AssetStatus.needsUpdate;
        }
      }

      return AssetStatus.downloaded;
    } catch (e) {
      return AssetStatus.notDownloaded;
    }
  }

  /// Calculates MD5 hash of a file, streaming so large game assets don't
  /// have to be fully loaded into memory.
  Future<String> _calculateFileHash(io.File file) async {
    final digest = await md5.bind(file.openRead()).first;
    return digest.toString();
  }

  /// Fetches and parses the cloud manifest from the configured
  /// [RepositorySource]. Under `auto` the mirror is tried first with a short
  /// timeout, and any failure (network, non-2xx, invalid JSON, status not OK)
  /// falls back to the origin.
  Future<CloudData> fetchCloudData() async {
    final source = await _repositorySource();
    final endpoints = source.endpoints;
    Object? lastError;
    StackTrace? lastStack;

    for (var i = 0; i < endpoints.length; i++) {
      final endpoint = endpoints[i];
      final fallback = i + 1 < endpoints.length ? endpoints[i + 1] : null;
      try {
        final body = await _fetchManifestBody(
          endpoint,
          timeout: fallback != null ? _fallbackManifestTimeout : null,
        );
        final cloudData = _parseCloudData(body);

        _manifestEndpoint = endpoint;
        _mirrorDegraded = endpoint != RepositoryEndpoint.mirror &&
            endpoints.contains(RepositoryEndpoint.mirror);
        _mirrorNetworkFailureStreak = 0;
        _log('manifest from ${endpoint.name} (source: ${source.persistedValue})');
        return cloudData;
      } catch (e, st) {
        lastError = e;
        lastStack = st;
        _log(fallback != null
            ? 'manifest: ${endpoint.name} failed (${_describeError(e)}), trying ${fallback.name}'
            : 'manifest: ${endpoint.name} failed (${_describeError(e)})');
      }
    }

    if (kIsWeb && lastError.toString().contains('XMLHttpRequest error')) {
      throw Exception('Fetching cloud data failed. This is likely due to a CORS issue on the server. '
          'The server at ${endpoints.last.manifestUri.host} must be configured to allow requests from this origin.');
    }
    Error.throwWithStackTrace(lastError!, lastStack!);
  }

  /// Downloads one manifest and checks it is a well-formed, `OK` response.
  Future<Map<String, dynamic>> _fetchManifestBody(
    RepositoryEndpoint endpoint, {
    Duration? timeout,
  }) async {
    final client = _createHttpClient();
    try {
      var request = client.get(endpoint.manifestUri);
      if (timeout != null) request = request.timeout(timeout);
      final response = await request;

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception('Failed to load cloud data: ${response.statusCode}');
      }
      final body = jsonDecode(response.body);
      if (body is! Map<String, dynamic>) {
        throw const FormatException('Cloud data is not a JSON object');
      }
      if (body['status'] != 'OK') {
        throw Exception('API returned status ${body['status']}');
      }
      return body;
    } finally {
      client.close();
    }
  }

  CloudData _parseCloudData(Map<String, dynamic> body) {
    final data = body['data'] as Map<String, dynamic>?;
    if (data == null) {
      return CloudData(clientGroups: [], modGroups: [], assetGroups: [], otherGroups: []);
    }

    List<AssetGroup> clientGroups = [];
    List<AssetGroup> modGroups = [];
    List<AssetGroup> assetGroups = [];
    List<AssetGroup> otherGroups = [];

    if (data['clientgroups'] != null) {
      clientGroups = (data['clientgroups'] as List).map((g) => AssetGroup.fromJson(g)).toList();
    }

    // The client itself comes from GitHub releases (see [syncClientFiles]),
    // so the jofhub client files are never synced; only this placeholder
    // represents the client in the asset list.
    if (supportsClientFiles) {
      clientGroups = [
        AssetGroup(
          id: -1,
          name: 'JoF EternalJK',
          description: 'Required game client',
          category: 'CLIENT',
          targetFolder: '',
          assets: [],
          isRequired: true,
        )
      ];
    }
    if (data['modgroups'] != null) {
      modGroups = (data['modgroups'] as List).map((g) => AssetGroup.fromJson(g)).toList();
    }
    if (data['assetgroups'] != null) {
      assetGroups = (data['assetgroups'] as List).map((g) => AssetGroup.fromJson(g)).toList();
    }
    if (data['othergroups'] != null) {
      otherGroups = (data['othergroups'] as List).map((g) => AssetGroup.fromJson(g)).toList();
    }

    final cloudData = CloudData(
      clientGroups: clientGroups,
      modGroups: modGroups,
      assetGroups: assetGroups,
      otherGroups: otherGroups,
    );

    _cachedCloudData = cloudData;
    return cloudData;
  }

  Future<RepositorySource> _repositorySource() async {
    try {
      return RepositorySourceCodec.tryParse(
              await SettingsService().getRepositorySource()) ??
          RepositorySource.auto;
    } catch (_) {
      // Preferences unavailable: use the default rather than fail the sync.
      return RepositorySource.auto;
    }
  }

  void _log(String message) => LogService.instance.log('repo', message);

  static String _describeError(Object e) {
    final text = e.toString().replaceAll(RegExp(r'\s+'), ' ');
    return text.length > 200 ? '${text.substring(0, 200)}…' : text;
  }

  /// Downloads [asset] into [downloadDir] from the configured
  /// [RepositorySource].
  ///
  /// Under `auto` the file comes from the mirror and falls back to the origin
  /// for this file when the mirror does not have it (403/404/5xx), serves the
  /// wrong content (HTML, or a size or MD5 that does not match the manifest,
  /// typically a file the hourly sync has not copied yet), or stays
  /// unreachable. Both sources share one integrity-failure budget, so a
  /// fallback never raises the number of full downloads above
  /// [_maxIntegrityFailures].
  Future<void> downloadAsset(
    Asset asset,
    String downloadDir, {
    Function(double)? onProgress,
    void Function(String status)? onStatus,
    bool Function()? isCancelled,
  }) async {
    if (kIsWeb) {
      throw Exception('Asset downloading is not supported on the web version.');
    }

    final finalDownloadDir = await _getActualTargetDir(downloadDir, asset.targetFolder);
    final savePath = p.join(finalDownloadDir, asset.name);

    // Ensure the directory exists
    final dir = io.Directory(finalDownloadDir);
    if (!await dir.exists()) {
      if (asset.targetFolder == 'Base') {
        throw Exception('Target folder "Base" or "base" is missing. Please ensure it exists.');
      }
      await dir.create(recursive: true);
    }

    final source = await _repositorySource();
    final endpoints = source.endpoints;
    final integrity = _IntegrityBudget();

    for (var i = 0; i < endpoints.length; i++) {
      final endpoint = endpoints[i];
      final fallback = i + 1 < endpoints.length ? endpoints[i + 1] : null;
      final isMirror = endpoint == RepositoryEndpoint.mirror;

      if (fallback != null &&
          isMirror &&
          _mirrorNetworkFailureStreak >= _mirrorBreakerThreshold) {
        _log('${asset.name}: skipping mirror (unreachable for '
            '$_mirrorNetworkFailureStreak files in a row), using ${fallback.name}');
        continue;
      }

      final url = endpoint.fileUri(asset.repositoryPath).toString();
      final quickMirror = fallback != null && isMirror && _mirrorDegraded;
      try {
        await _downloadToFileWithResume(
          url: url,
          finalPath: savePath,
          expectedSize: asset.size > 0 ? asset.size : null,
          expectedHash: asset.hash.isNotEmpty ? asset.hash : null,
          onProgress: onProgress,
          onStatus: onStatus,
          isCancelled: isCancelled,
          source: _SourceAttempt(
            integrity: integrity,
            canFallBack: fallback != null,
            maxNetworkFailures: fallback == null
                ? null
                : quickMirror
                    ? 1
                    : _mirrorMaxNetworkFailures,
            connectTimeout:
                quickMirror ? _degradedMirrorConnectTimeout : _connectTimeout,
          ),
        );
      } on _SourceUnusableException catch (e) {
        if (isMirror && e.sourceDown) {
          _mirrorDegraded = true;
          _mirrorNetworkFailureStreak++;
        }
        _log('${asset.name}: ${endpoint.name} failed (${e.reason}), '
            'trying ${fallback!.name} [$url]');
        onStatus?.call('Downloading ${asset.name} from ${fallback.fileHost}…');
        continue;
      } catch (e) {
        if (!_isCancellation(e)) {
          _log('${asset.name}: ${endpoint.name} failed (${_describeError(e)}) [$url]');
        }
        rethrow;
      }

      if (isMirror) _mirrorNetworkFailureStreak = 0;
      _log('${asset.name}: downloaded from ${endpoint.name}'
          '${i > 0 ? ' after fallback' : ''} (source: ${source.persistedValue})');
      return;
    }
  }

  /// Downloads a single verified file, for callers outside asset syncing.
  ///
  /// Shares one implementation with asset downloads so the launcher updater
  /// inherits the same resume, retry, connectivity-wait and integrity
  /// behaviour rather than growing a second, less tested copy of it. As the
  /// only source for the file, a server that keeps serving the wrong file
  /// (say a stale CDN copy of a different size) fails after
  /// [_maxIntegrityFailures] instead of being re-downloaded forever.
  Future<void> downloadFile({
    required String url,
    required String finalPath,
    int? expectedSize,
    String? expectedSha256,
    void Function(double progress)? onProgress,
    void Function(String status)? onStatus,
    bool Function()? isCancelled,
  }) {
    return _downloadToFileWithResume(
      url: url,
      finalPath: finalPath,
      expectedSize: expectedSize,
      expectedSha256: expectedSha256,
      onProgress: onProgress,
      onStatus: onStatus,
      isCancelled: isCancelled,
      source: _SourceAttempt.only(_connectTimeout),
    );
  }

  /// Downloads [url] to [finalPath], resuming across transient network changes.
  ///
  /// Bytes stream to `<finalPath>.part`; on a stall (idle timeout) or network
  /// error the download retries, sending a `Range` header to continue from the
  /// bytes already on disk (server permitting). While the connection is down it
  /// waits for connectivity to return (retrying until success or cancel). On
  /// completion the file is verified (size, and hash when known) and atomically
  /// renamed into place.
  Future<void> _downloadToFileWithResume({
    required String url,
    required String finalPath,
    int? expectedSize,
    String? expectedHash,
    String? expectedSha256,
    Function(double progress)? onProgress,
    void Function(String status)? onStatus,
    bool Function()? isCancelled,
    required _SourceAttempt source,
  }) async {
    bool cancelled() => isCancelled?.call() ?? false;

    final partFile = io.File('$finalPath.part');

    // Within-sync resume only: start from a clean slate, discarding any stale
    // partial left over from a previous session.
    if (await partFile.exists()) {
      await partFile.delete();
    }

    var attempt = 0;
    // A checksum mismatch is retried (it is usually a corrupted transfer), but
    // the retry loop below is otherwise unbounded. Without a ceiling, a file
    // whose published checksum simply never matches would re-download forever.
    // An asset download shares this budget across its sources.
    final integrity = source.integrity;
    // Retryable failures while online. Only bounded for a source with a
    // fallback; otherwise the loop keeps retrying as before.
    var networkFailures = 0;

    while (true) {
      if (cancelled()) {
        throw Exception('Download cancelled');
      }

      var offset = await partFile.exists() ? await partFile.length() : 0;

      http.Client? client;
      io.RandomAccessFile? sink;
      final buffer = BytesBuilder(copy: false);
      try {
        client = _createHttpClient();
        final request = http.Request('GET', Uri.parse(url));
        if (offset > 0) {
          request.headers['Range'] = 'bytes=$offset-';
        }

        final response = await client
            .send(request)
            .timeout(source.connectTimeout);

        int total;
        bool append;
        if (response.statusCode == 206) {
          append = true;
          total = _totalFromContentRange(response) ??
              expectedSize ??
              ((response.contentLength ?? 0) + offset);
        } else if (response.statusCode == 200) {
          // Server ignored the Range request (or this is a fresh download):
          // restart from the beginning.
          append = false;
          offset = 0;
          total = expectedSize ?? response.contentLength ?? 0;
        } else if (response.statusCode == 416 && offset > 0) {
          // Our partial is stale/too big for the current file: restart clean.
          if (await partFile.exists()) await partFile.delete();
          client.close();
          continue;
        } else {
          // A real HTTP error (404/5xx/...) is not a connectivity problem;
          // fail fast rather than retrying forever.
          if (source.canFallBack) {
            throw _SourceUnusableException('HTTP ${response.statusCode}',
                sourceDown: response.statusCode >= 500);
          }
          throw Exception('Failed to download asset: ${response.statusCode}');
        }

        // The size of the whole file as the server declares it.
        final declaredTotal = response.statusCode == 206
            ? _totalFromContentRange(response)
            : response.contentLength;
        final mismatch =
            _contentMismatch(response, declaredTotal, expectedSize, finalPath);
        if (mismatch != null) {
          if (await partFile.exists()) await partFile.delete();
          _rejectContent(source, mismatch, url, bodyDownloaded: false);
        }

        // Digests are computed as the bytes arrive, so a finished file is not
        // read back from disk to verify it. A resumed download first feeds
        // the bytes already on disk.
        final hashers = _StreamingHashers(
          md5: expectedHash != null && expectedHash.isNotEmpty,
          sha256: expectedSha256 != null && expectedSha256.isNotEmpty,
        );
        if (append && hashers.isNotEmpty) {
          await partFile.openRead().forEach(hashers.add);
        }

        sink = await partFile.open(
          mode: append ? io.FileMode.append : io.FileMode.write,
        );
        var received = offset;
        final sinceProgress = Stopwatch()..start();

        await for (final chunk in response.stream.timeout(_idleTimeout)) {
          if (cancelled()) {
            throw Exception('Download cancelled');
          }
          hashers.add(chunk);
          buffer.add(chunk);
          received += chunk.length;
          if (buffer.length >= _writeBufferSize) {
            await sink.writeFrom(buffer.takeBytes());
          }
          if (total > 0 && sinceProgress.elapsed >= _progressInterval) {
            sinceProgress.reset();
            onProgress?.call((received / total).clamp(0.0, 1.0));
          }
        }

        if (buffer.isNotEmpty) {
          await sink.writeFrom(buffer.takeBytes());
        }
        await sink.close();
        if (total > 0) {
          onProgress?.call((received / total).clamp(0.0, 1.0));
        }
        sink = null;
        client.close();
        client = null;

        // Verify what landed on disk before committing it.
        final checkSize = expectedSize ?? (total > 0 ? total : null);
        final finalLength = await partFile.length();
        if (checkSize != null && finalLength != checkSize) {
          if (declaredTotal == null && expectedSize != null) {
            // The body ended cleanly without a declared size, so this is the
            // whole of a wrong file rather than a truncated transfer.
            await partFile.delete();
            _rejectContent(
                source, 'size $finalLength, manifest says $expectedSize', url,
                bodyDownloaded: true);
          }
          if (finalLength > checkSize) {
            // Overran the expected size (corrupt) — restart from scratch.
            await partFile.delete();
          }
          throw const _RetryableDownloadException('incomplete download');
        }
        hashers.close();
        if (expectedHash != null && expectedHash.isNotEmpty) {
          final actualHash = hashers.md5Digest.toString();
          if (actualHash != expectedHash) {
            await partFile.delete();
            integrity.failures++;
            _failFastOnRepeatedCorruption(integrity.failures, 'MD5', url);
            if (source.canFallBack) {
              throw const _SourceUnusableException('MD5 mismatch');
            }
            throw const _RetryableDownloadException('hash mismatch');
          }
        }
        if (expectedSha256 != null && expectedSha256.isNotEmpty) {
          final actualSha256 = hashers.sha256Digest.toString();
          if (actualSha256.toLowerCase() != expectedSha256.toLowerCase()) {
            await partFile.delete();
            integrity.failures++;
            _failFastOnRepeatedCorruption(integrity.failures, 'SHA-256', url);
            throw const _RetryableDownloadException('sha256 mismatch');
          }
        }

        await _movePartIntoPlace(partFile, finalPath);
        return;
      } catch (e) {
        try {
          // Persist bytes already received so the resume continues from them.
          if (sink != null && buffer.isNotEmpty) {
            await sink.writeFrom(buffer.takeBytes());
          }
          await sink?.close();
        } catch (_) {}
        client?.close();

        if (_isCancellation(e)) {
          try {
            if (await partFile.exists()) await partFile.delete();
          } catch (_) {}
          rethrow;
        }

        if (!_isRetryable(e)) {
          try {
            if (await partFile.exists()) await partFile.delete();
          } catch (_) {}
          rethrow;
        }

        // Transient network/timeout error: wait for connectivity (or back off)
        // and resume from the bytes already written.
        attempt++;
        if (!await _connectivity.isOnline()) {
          onStatus?.call('Network lost — waiting to resume…');
          await _connectivity.waitForConnection(isCancelled: cancelled);
        } else {
          networkFailures++;
          final limit = source.maxNetworkFailures;
          if (source.canFallBack &&
              limit != null &&
              networkFailures >= limit) {
            // Never resume these bytes from another source: the copies
            // can differ while the mirror is catching up.
            try {
              if (await partFile.exists()) await partFile.delete();
            } catch (_) {}
            throw _SourceUnusableException(
                'network error after $networkFailures attempt(s): ${_describeError(e)}',
                sourceDown: true);
          }
          onStatus?.call('Connection interrupted — retrying…');
          await _cancellableBackoff(attempt, cancelled);
        }
      }
    }
  }

  /// Parses the total size out of a `Content-Range: bytes start-end/total`
  /// header, or null if unavailable.
  int? _totalFromContentRange(http.StreamedResponse response) {
    final header = response.headers['content-range'];
    if (header == null) return null;
    final slash = header.lastIndexOf('/');
    if (slash < 0) return null;
    return int.tryParse(header.substring(slash + 1).trim());
  }

  /// Why a response cannot be the expected file, judged from its headers
  /// alone, or null if it may be. Catches the HTML error page CloudFront
  /// serves for a missing file, and a stale copy of a file the manifest has
  /// since updated.
  static String? _contentMismatch(
    http.StreamedResponse response,
    int? declaredTotal,
    int? expectedSize,
    String finalPath,
  ) {
    final contentType = response.headers['content-type']?.toLowerCase() ?? '';
    final extension = p.extension(finalPath).toLowerCase();
    if (contentType.startsWith('text/html') &&
        extension != '.html' &&
        extension != '.htm') {
      return 'served $contentType';
    }
    if (expectedSize != null &&
        declaredTotal != null &&
        declaredTotal != expectedSize) {
      return 'size $declaredTotal, manifest says $expectedSize';
    }
    return null;
  }

  /// Rejects content that is not the expected file. With a fallback the file
  /// moves on to the next source, and only a mismatch that cost a full
  /// download uses the integrity budget. Without one every mismatch counts,
  /// so a source that keeps serving the wrong file fails after
  /// [_maxIntegrityFailures] instead of retrying forever.
  Never _rejectContent(
    _SourceAttempt source,
    String reason,
    String url, {
    required bool bodyDownloaded,
  }) {
    if (bodyDownloaded || !source.canFallBack) {
      source.integrity.failures++;
      _failFastOnRepeatedCorruption(source.integrity.failures, 'size/type', url);
    }
    if (source.canFallBack) throw _SourceUnusableException(reason);
    throw _RetryableDownloadException(reason);
  }

  /// Atomically moves the completed `.part` file onto [finalPath].
  Future<void> _movePartIntoPlace(io.File partFile, String finalPath) async {
    final dest = io.File(finalPath);
    if (await dest.exists()) {
      await dest.delete();
    }
    try {
      await partFile.rename(finalPath);
    } on io.FileSystemException {
      // Cross-device rename can fail; fall back to copy + delete.
      await partFile.copy(finalPath);
      try {
        await partFile.delete();
      } catch (_) {}
    }
  }

  bool _isCancellation(Object e) => e.toString().contains('cancelled');

  /// Number of checksum mismatches tolerated before a download is treated as
  /// permanently broken rather than a transient corruption.
  static const int _maxIntegrityFailures = 3;

  /// Throws a non-retryable error once [failures] reaches
  /// [_maxIntegrityFailures], ending the retry loop.
  void _failFastOnRepeatedCorruption(int failures, String algorithm, String url) {
    if (failures < _maxIntegrityFailures) return;
    throw Exception(
        'Download failed $algorithm verification $failures times: $url. '
        'The file being served does not match the published manifest.');
  }

  bool _isRetryable(Object e) {
    return e is TimeoutException ||
        e is io.SocketException ||
        e is io.HttpException ||
        e is http.ClientException ||
        e is _RetryableDownloadException;
  }

  /// Sleeps with exponential backoff (2s..30s), returning early if cancelled.
  Future<void> _cancellableBackoff(int attempt, bool Function() cancelled) async {
    var remaining = _retryBackoff(attempt);
    const step = Duration(milliseconds: 250);
    while (remaining > Duration.zero) {
      if (cancelled()) return;
      final wait = remaining < step ? remaining : step;
      await Future.delayed(wait);
      remaining -= wait;
    }
  }

  @visibleForTesting
  void setCachedCloudDataForTests(CloudData data) {
    _cachedCloudData = data;
  }

  @visibleForTesting
  void clearCachedCloudDataForTests() {
    _cachedCloudData = null;
  }

  Future<CloudData> _getCloudDataForDeletion() async {
    // Best-effort cache: controllers typically call `fetchCloudData()` before syncing.
    // If cache is missing, fetch it so deletion protection is still enforced.
    return _cachedCloudData ?? await fetchCloudData();
  }

  bool _isAssetInCloudManifest(Asset asset, CloudData cloudData) {
    // Only delete files that correspond to an asset in the current cloud manifest.
    for (final group in cloudData.allGroups) {
      for (final a in group.assets) {
        if (a.id == asset.id && a.name == asset.name && a.targetFolder == asset.targetFolder) {
          return true;
        }
      }
    }
    return false;
  }

  Future<void> deleteAsset(Asset asset, String downloadDir) async {
    if (kIsWeb) return;

    final cloudData = await _getCloudDataForDeletion();
    if (!_isAssetInCloudManifest(asset, cloudData)) {
      return;
    }

    final finalDownloadDir = await _getActualTargetDir(downloadDir, asset.targetFolder);
    final filePath = p.normalize(p.join(finalDownloadDir, asset.name));

    // Guardrail: never allow deleting anything outside the resolved target directory.
    final normalizedTargetDir = p.normalize(finalDownloadDir);
    if (!(filePath == normalizedTargetDir || filePath.startsWith('$normalizedTargetDir${p.separator}'))) {
      return;
    }

    final entityType = await io.FileSystemEntity.type(filePath);
    if (entityType != io.FileSystemEntityType.file) {
      return;
    }

    final file = io.File(filePath);
    if (await file.exists()) {
      await file.delete();
    }
  }

  Future<String> _getActualTargetDir(String downloadDir, String targetFolder) async {
    final defaultPath = p.join(downloadDir, targetFolder);
    if (targetFolder == 'Base') {
      final baseLowerPath = p.join(downloadDir, 'base');
      if (await io.Directory(baseLowerPath).exists()) {
        return baseLowerPath;
      }
      final baseUpperPath = p.join(downloadDir, 'Base');
      if (await io.Directory(baseUpperPath).exists()) {
        return baseUpperPath;
      }
    }
    return defaultPath;
  }

  /// Name of the file, at the root of an install, recording which client
  /// release was extracted there.
  static const String clientMarkerFileName = '.jof-client.json';

  /// Whether this platform installs the EternalJK client from GitHub releases.
  bool get supportsClientFiles =>
      !kIsWeb &&
      (io.Platform.isLinux || io.Platform.isMacOS || io.Platform.isWindows);

  /// The client release this machine should have installed: the version for
  /// the selected channel, in the build for this platform and architecture.
  ///
  /// [ClientTarget.sha256] is null when the GitHub API could not be reached;
  /// see [ClientReleaseService.fetchAssetSha256].
  Future<ClientTarget> resolveClientTarget() async {
    final String platformName;
    final String assetName;
    if (io.Platform.isLinux) {
      platformName = 'Linux';
      assetName = ClientReleaseService.linuxAssetName(
          await _systemArch.resolveLinux());
    } else if (io.Platform.isMacOS) {
      final arch = await _systemArch.resolveMacos();
      if (arch == null) {
        throw Exception('Could not auto-detect macOS CPU architecture. Please select it in Settings.');
      }
      platformName = 'MacOS';
      assetName = ClientReleaseService.macosAssetName(arch);
    } else if (io.Platform.isWindows) {
      platformName = 'Windows';
      assetName =
          ClientReleaseService.windowsAssetName(_systemArch.resolveWindows());
    } else {
      throw UnsupportedError(
          'No EternalJK client build for ${io.Platform.operatingSystem}.');
    }

    final latest = await resolveClientVersion();
    final version = latest ?? ClientReleaseService.fallbackVersion;
    return ClientTarget(
      platformName: platformName,
      version: version,
      assetName: assetName,
      sha256: await _clientRelease.fetchAssetSha256(version, assetName),
      versionConfirmed: latest != null,
    );
  }

  /// Whether [installRoot] already holds [target] (resolved when omitted), so
  /// a sync can skip downloading a client archive it already has.
  ///
  /// Never throws: anything unreadable or unresolvable counts as out of date,
  /// which costs at worst one redundant download.
  Future<bool> isClientUpToDate(String installRoot,
      [ClientTarget? target]) async {
    try {
      final marker = io.File(p.join(installRoot, clientMarkerFileName));
      if (!await marker.exists()) return false;
      final decoded = jsonDecode(await marker.readAsString());
      if (decoded is! Map) return false;

      target ??= await resolveClientTarget();
      if (!clientMarkerMatches(decoded, target)) return false;

      // The marker says what was extracted; a file deleted since (by the
      // user, or an antivirus quarantining the exe) still needs reinstalling.
      final files = decoded['files'];
      if (files is! List || files.isEmpty) return false;
      for (final relative in files) {
        if (relative is! String) return false;
        if (!await io.File(p.join(installRoot, relative)).exists()) {
          return false;
        }
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Whether a decoded install marker describes [target].
  ///
  /// The published sha256 is the authority when both sides have one, so a
  /// release re-uploaded under the same tag is still picked up. Without it
  /// (the GitHub API was unreachable or rate-limited, now or at install time)
  /// the version and asset name have to do.
  ///
  /// An unconfirmed target matches any installed version: not knowing the
  /// current release is no reason to replace the client with the pinned
  /// fallback, which would downgrade it, or swap an alpha build for stable.
  @visibleForTesting
  static bool clientMarkerMatches(Map<dynamic, dynamic> marker, ClientTarget target) {
    if (marker['asset'] != target.assetName) return false;
    if (!target.versionConfirmed) return true;
    if (marker['version'] != target.version) return false;
    final installedSha = marker['sha256'];
    if (target.sha256 != null && installedSha is String) {
      return installedSha.toLowerCase() == target.sha256!.toLowerCase();
    }
    return true;
  }

  /// Installs the EternalJK client into [installRoot], unless it, or
  /// [currentInstallPath] when given, already holds the current release.
  ///
  /// [currentInstallPath] is for staging while the game runs: the live install
  /// may already be current even though the staging directory is empty.
  Future<void> syncClientFiles(
    String installRoot, {
    String? currentInstallPath,
    Function(String name, double progress)? onProgress,
    void Function(String status)? onStatus,
    bool Function()? isCancelled,
  }) async {
    if (kIsWeb) {
      throw Exception('Client file downloading is not supported on the web version.');
    }

    final target = await resolveClientTarget();
    for (final root in {installRoot, ?currentInstallPath}) {
      if (await isClientUpToDate(root, target)) {
        onProgress?.call('${target.platformName} client is up to date', 1.0);
        return;
      }
    }

    await _downloadAndExtractClient(
      target,
      installRoot,
      onProgress: onProgress,
      onStatus: onStatus,
      isCancelled: isCancelled,
    );
  }

  @visibleForTesting
  static String linuxClientTarGzUrl(String version, LinuxSystemArch arch) {
    return ClientReleaseService.downloadUrl(
        version, ClientReleaseService.linuxAssetName(arch));
  }

  @visibleForTesting
  static String macosClientTarGzUrl(String version, MacosSystemArch arch) {
    return ClientReleaseService.downloadUrl(
        version, ClientReleaseService.macosAssetName(arch));
  }

  @visibleForTesting
  static String windowsClientZipUrl(String version, WindowsSystemArch arch) {
    return ClientReleaseService.downloadUrl(
        version, ClientReleaseService.windowsAssetName(arch));
  }

  /// The EternalJK release to install for the selected [ClientChannel], or
  /// null when GitHub cannot be asked (unreachable or rate-limited).
  ///
  /// See [ClientReleaseService.fetchLatestTag] for how each channel picks its
  /// release.
  @visibleForTesting
  Future<String?> resolveClientVersion() async {
    final channel = ClientChannelCodec.tryParse(
            await SettingsService().getClientChannel()) ??
        ClientChannel.stable;
    return _clientRelease.fetchLatestTag(channel);
  }

  Future<void> _downloadAndExtractClient(
    ClientTarget target,
    String installRoot, {
    Function(String name, double progress)? onProgress,
    void Function(String status)? onStatus,
    bool Function()? isCancelled,
  }) async {
    final platformName = target.platformName;
    final tempDir = await io.Directory.systemTemp.createTemp('jof_client_');
    final archivePath = p.join(tempDir.path, target.assetName);

    try {
      onProgress?.call('Downloading $platformName files', 0);

      await _downloadToFileWithResume(
        url: target.url,
        finalPath: archivePath,
        expectedSha256: target.sha256,
        onProgress: (p) =>
            onProgress?.call('Downloading $platformName files', p * 0.5),
        onStatus: onStatus,
        isCancelled: isCancelled,
        source: _SourceAttempt.only(_connectTimeout),
      );

      onProgress?.call('Extracting $platformName files', 0.5);

      // Dropped before overwriting anything, so an extraction that fails or
      // is cancelled halfway can never be mistaken for a complete install.
      final marker = io.File(p.join(installRoot, clientMarkerFileName));
      if (await marker.exists()) await marker.delete();

      final bytes = await io.File(archivePath).readAsBytes();
      final archive = target.assetName.endsWith('.zip')
          ? ZipDecoder().decodeBytes(bytes)
          : TarDecoder().decodeBytes(GZipDecoder().decodeBytes(bytes));

      final wrapper = archiveWrapperPrefix(archive.map((f) => f.name));

      int filesProcessed = 0;
      final totalFiles = archive.length;
      final extractedFiles = <String>[];

      final baseFolderName = await _detectExistingBaseFolderNameForExtraction(installRoot);

      for (final file in archive) {
        if (isCancelled != null && isCancelled()) {
          throw Exception('Extraction cancelled');
        }

        final filename = file.name.substring(wrapper.length);
        if (filename.isEmpty) {
          filesProcessed++;
          continue;
        }

        final targetPath = resolveExtractTargetPath(
          gameDataPath: installRoot,
          filename: filename,
          baseFolderName: baseFolderName,
        );

        if (file.isFile) {
          final outFile = io.File(targetPath);
          await outFile.create(recursive: true);
          await outFile.writeAsBytes(file.content as List<int>);
          extractedFiles.add(p.relative(targetPath, from: installRoot));

          // Apply unix permissions from tar if available
          if (io.Platform.isLinux || io.Platform.isMacOS) {
            if (file.mode != null) {
              // Converting tar mode to octal chmod
              final modeString = file.mode!.toRadixString(8);
              await io.Process.run('chmod', [modeString, targetPath]);
            } else {
              // Fallback for legacy support if mode is missing
              if (filename.endsWith('.x86_64') ||
                  filename.endsWith('.i686') ||
                  filename.endsWith('.app') ||
                  (filename.contains('eternaljk') && !filename.contains('.'))) {
                await io.Process.run('chmod', ['+x', targetPath]);
              }
            }
          }
        } else {
          final dir = io.Directory(targetPath);
          await dir.create(recursive: true);
        }

        filesProcessed++;
        if (onProgress != null) {
          final extractProgress = 0.5 + (filesProcessed / totalFiles * 0.5);
          onProgress('Extracting $platformName files', extractProgress);
        }
      }

      // Written last: its presence means every file above is in place.
      await marker.writeAsString(jsonEncode({
        'version': target.version,
        'asset': target.assetName,
        'sha256': target.sha256,
        'files': extractedFiles,
      }));

      onProgress?.call('$platformName files extracted', 1.0);
    } finally {
      // Clean up temp directory
      try {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      } catch (_) {}
    }
  }

  /// The single top-level folder every entry of an archive sits in, with its
  /// trailing slash, or an empty string when there is none.
  ///
  /// The Windows client zips wrap their contents in a folder named after the
  /// build (`JoF-master-windows-x86_64/GameData/...`), while the Linux and
  /// macOS tarballs start directly at the install layout. A top-level folder
  /// that is itself part of that layout is never stripped.
  @visibleForTesting
  static String archiveWrapperPrefix(Iterable<String> entryNames) {
    String? top;
    for (final name in entryNames) {
      final slash = name.indexOf('/');
      // A file at the archive root means there is no wrapper.
      if (slash <= 0) return '';
      final first = name.substring(0, slash);
      if (top != null && top != first) return '';
      top = first;
    }
    if (top == null) return '';
    const layoutFolders = {'GameData', 'EternalJK', 'base', 'Base'};
    if (layoutFolders.contains(top)) return '';
    return '$top/';
  }

  Future<String> _detectExistingBaseFolderNameForExtraction(String gameDataPath) async {
    final lower = io.Directory(p.join(gameDataPath, 'base'));
    if (await lower.exists()) return 'base';
    final upper = io.Directory(p.join(gameDataPath, 'Base'));
    if (await upper.exists()) return 'Base';
    // Default to lower-case when base folder is not yet present.
    return 'base';
  }

  @visibleForTesting
  static String resolveExtractTargetPath({
    required String gameDataPath,
    required String filename,
    String baseFolderName = 'base',
  }) {
    // Determine target path based on folder structure.
    final String targetPath;
    if (filename.startsWith('EternalJK/')) {
      // Files in EternalJK folder go to gameDataPath/EternalJK
      final relativePath = filename.substring('EternalJK/'.length);
      targetPath = p.join(gameDataPath, 'EternalJK', relativePath);
    } else if (filename.startsWith('GameData/')) {
      // Files in GameData folder go to gameDataPath
      final relativePath = filename.substring('GameData/'.length);
      targetPath = p.join(gameDataPath, relativePath);
    } else if (filename.startsWith('base/') || filename.startsWith('Base/')) {
      // If the entry already has a base folder prefix, normalize it to the existing
      // install folder casing.
      final relativePath = filename.substring(filename.indexOf('/') + 1);
      targetPath = p.join(gameDataPath, baseFolderName, relativePath);
    } else {
      // Other files go directly to gameDataPath.
      targetPath = p.join(gameDataPath, filename);
    }

    // Guard against zip-slip / path traversal: reject any entry whose resolved
    // path escapes gameDataPath (e.g. via `..` segments in the archive entry name).
    final normalizedTarget = p.normalize(targetPath);
    final normalizedGameDataPath = p.normalize(gameDataPath);
    if (!(normalizedTarget == normalizedGameDataPath ||
        normalizedTarget.startsWith('$normalizedGameDataPath${p.separator}'))) {
      throw FormatException('Archive entry escapes target directory: $filename');
    }

    return targetPath;
  }

  /// Returns `true` if a file relative path is a launcher-managed static Linux client file.
  ///
  /// macOS client is packaged as `.app` and is not handled via an allowlist.
  @visibleForTesting
  static bool isStaticManagedLinuxClientRelativePath(String relativePath) {
    // Linux paths, so always POSIX-normalized, also on a Windows host whose
    // `p` would rewrite `/` to `\`.
    return _linuxStaticManagedRelativePaths
        .contains(p.posix.normalize(relativePath));
  }
}

/// Signals a completed-but-invalid download (short bytes or hash mismatch) that
/// should be retried/resumed rather than surfaced as a fatal error.
class _RetryableDownloadException implements Exception {
  final String message;
  const _RetryableDownloadException(this.message);

  @override
  String toString() => 'RetryableDownloadException: $message';
}

/// A source served something other than the expected file, or could not be
/// reached, and the download should move on to the next source.
class _SourceUnusableException implements Exception {
  final String reason;

  /// The source itself looks down (network error or 5xx), as opposed to
  /// missing or lagging on this one file.
  final bool sourceDown;

  const _SourceUnusableException(this.reason, {this.sourceDown = false});

  @override
  String toString() => 'SourceUnusableException: $reason';
}

/// MD5 and/or SHA-256 of a download, fed chunk by chunk.
class _StreamingHashers {
  final _DigestSink? _md5Out;
  final _DigestSink? _sha256Out;
  final ByteConversionSink? _md5In;
  final ByteConversionSink? _sha256In;

  factory _StreamingHashers({required bool md5, required bool sha256}) {
    final md5Out = md5 ? _DigestSink() : null;
    final sha256Out = sha256 ? _DigestSink() : null;
    return _StreamingHashers._(md5Out, sha256Out);
  }

  _StreamingHashers._(this._md5Out, this._sha256Out)
      : _md5In = _md5Out == null ? null : md5.startChunkedConversion(_md5Out),
        _sha256In = _sha256Out == null
            ? null
            : sha256.startChunkedConversion(_sha256Out);

  bool get isNotEmpty => _md5In != null || _sha256In != null;

  void add(List<int> chunk) {
    _md5In?.add(chunk);
    _sha256In?.add(chunk);
  }

  void close() {
    _md5In?.close();
    _sha256In?.close();
  }

  Digest get md5Digest => _md5Out!.value!;
  Digest get sha256Digest => _sha256Out!.value!;
}

class _DigestSink implements Sink<Digest> {
  Digest? value;

  @override
  void add(Digest data) => value = data;

  @override
  void close() {}
}

/// Integrity failures for one file, shared across the sources it is tried on.
class _IntegrityBudget {
  int failures = 0;
}

/// How a download treats the source it is currently using.
class _SourceAttempt {
  final _IntegrityBudget integrity;

  /// Another source follows. When true, source problems throw
  /// [_SourceUnusableException] instead of failing or retrying here.
  final bool canFallBack;

  /// Retryable failures while online before giving up on this source. Null
  /// keeps retrying.
  final int? maxNetworkFailures;

  final Duration connectTimeout;

  const _SourceAttempt({
    required this.integrity,
    required this.canFallBack,
    required this.maxNetworkFailures,
    required this.connectTimeout,
  });

  /// The only source for a file: network errors keep retrying, and content
  /// that is not the expected file uses up a fresh integrity budget.
  _SourceAttempt.only(this.connectTimeout)
      : integrity = _IntegrityBudget(),
        canFallBack = false,
        maxNetworkFailures = null;
}
