import 'dart:convert';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:http/http.dart' as http;

import '../models/client_channel.dart';
import '../models/platform_arch.dart';

/// Resolves which EternalJK client build to install, and where to fetch it.
///
/// The client archives live as release assets on the public
/// `JediofFreedom/JoF_EJK` GitHub repository, and GitHub alone decides which
/// release to install: the release marked "Latest" for the stable channel,
/// the newest `X.Y.Z-alpha.N` / `X.Y.Z-beta.N` prerelease for the test
/// channels. Publishing or rolling back a client is a GitHub release edit, not
/// a launcher release.
class ClientReleaseService {
  static const String repositoryOwner = 'JediofFreedom';
  static const String repositoryName = 'JoF_EJK';

  /// Installed when GitHub cannot be asked which release is current and no
  /// client is installed yet. An unreachable or rate-limited API must not
  /// leave a fresh install without a client at all.
  static const String fallbackVersion = '1.6.1';

  /// How long a resolved latest tag is reused. Long enough that the
  /// up-to-date check and the install that follows it in the same sync share
  /// one request of the 60/hour unauthenticated budget; short enough that a
  /// newly published release is picked up by the next sync.
  static const Duration latestTagTtl = Duration(minutes: 5);

  final http.Client Function()? _httpClientFactory;

  /// Published digests by `version/assetName`. A release asset never changes
  /// once published, so a digest is good for the life of the process; caching
  /// it means the up-to-date check and the install that follows it spend one
  /// request of the 60/hour unauthenticated budget, not two.
  final Map<String, String> _sha256Cache = {};

  final Map<ClientChannel, ({String tag, DateTime at})> _latestTagCache = {};

  final DateTime Function() _now;

  ClientReleaseService({
    http.Client Function()? httpClientFactory,
    DateTime Function()? now,
  })  : _httpClientFactory = httpClientFactory,
        _now = now ?? DateTime.now;

  http.Client _createHttpClient() =>
      _httpClientFactory?.call() ?? http.Client();

  /// The release asset filename for a Linux [arch].
  static String linuxAssetName(LinuxSystemArch arch) {
    return switch (arch) {
      LinuxSystemArch.bit32 => 'JoF-linux-x86.tar.gz',
      LinuxSystemArch.bit64 => 'JoF-linux-x86_64.tar.gz',
    };
  }

  /// The release asset filename for a macOS [arch].
  static String macosAssetName(MacosSystemArch arch) {
    return switch (arch) {
      MacosSystemArch.amd => 'JoF-macos-x86_64.tar.gz',
      MacosSystemArch.arm => 'JoF-macos-arm64.tar.gz',
    };
  }

  /// The release asset filename for a Windows [arch].
  static String windowsAssetName(WindowsSystemArch arch) {
    return switch (arch) {
      WindowsSystemArch.bit32 => 'JoF-windows-x86.zip',
      WindowsSystemArch.bit64 => 'JoF-windows-x86_64.zip',
    };
  }

  /// Direct download URL for [assetName] on release [version].
  ///
  /// GitHub answers this with a 302 to a short-lived signed URL on
  /// `release-assets.githubusercontent.com`. Because the redirect is followed
  /// per request, a resumed download re-signs rather than reusing an expired
  /// link.
  static String downloadUrl(String version, String assetName) {
    return Uri.https(
      'github.com',
      '/$repositoryOwner/$repositoryName/releases/download/$version/$assetName',
    ).toString();
  }

  @visibleForTesting
  static String releaseApiUrl(String version) {
    return Uri.https(
      'api.github.com',
      '/repos/$repositoryOwner/$repositoryName/releases/tags/$version',
    ).toString();
  }

  @visibleForTesting
  static String latestReleaseApiUrl() {
    return Uri.https(
      'api.github.com',
      '/repos/$repositoryOwner/$repositoryName/releases/latest',
    ).toString();
  }

  @visibleForTesting
  static String releasesApiUrl() {
    return Uri.https(
      'api.github.com',
      '/repos/$repositoryOwner/$repositoryName/releases',
      const {'per_page': '100'},
    ).toString();
  }

  /// Matches prerelease tags of the shape `1.6.1-alpha.59`: a dotted base
  /// version, the channel, and a monotonically increasing build number.
  static final RegExp _prereleaseTagPattern =
      RegExp(r'^(\d+(?:\.\d+)*)-(alpha|beta)\.(\d+)$');

  /// Picks the newest tag on [channel] out of a decoded
  /// `GET .../releases` response, or null when nothing matches.
  ///
  /// Pure and synchronous so channel-selection logic is testable without
  /// mocking HTTP. Stable has no prerelease tag shape to select (it uses the
  /// release GitHub marks as latest instead), so this always returns null for
  /// it.
  @visibleForTesting
  static String? selectLatestTag(
          List<dynamic> releasesJson, ClientChannel channel) =>
      _selectLatestRelease(releasesJson, channel)?['tag_name']?.toString();

  static Map<dynamic, dynamic>? _selectLatestRelease(
      List<dynamic> releasesJson, ClientChannel channel) {
    final segment = channel.prereleaseTagSegment;
    if (segment == null) return null;

    Map<dynamic, dynamic>? best;
    String? bestTag;
    List<int>? bestBase;
    int? bestBuild;

    for (final release in releasesJson) {
      if (release is! Map) continue;
      if (release['draft'] == true) continue;

      final tag = release['tag_name']?.toString();
      if (tag == null) continue;

      final match = _prereleaseTagPattern.firstMatch(tag);
      if (match == null) continue;
      if (match.group(2) != segment) continue;

      final base = match.group(1)!.split('.').map(int.parse).toList();
      final build = int.parse(match.group(3)!);

      if (bestTag == null ||
          _compareVersionParts(base, bestBase!) > 0 ||
          (_compareVersionParts(base, bestBase) == 0 && build > bestBuild!)) {
        best = release;
        bestTag = tag;
        bestBase = base;
        bestBuild = build;
      }
    }

    return best;
  }

  /// Compares two dotted version part lists component by component,
  /// numerically. A shorter list is padded with zeros rather than treated as
  /// smaller outright, so `1.6` compares equal to `1.6.0`.
  static int _compareVersionParts(List<int> a, List<int> b) {
    final length = a.length > b.length ? a.length : b.length;
    for (var i = 0; i < length; i++) {
      final partA = i < a.length ? a[i] : 0;
      final partB = i < b.length ? b[i] : 0;
      if (partA != partB) return partA.compareTo(partB);
    }
    return 0;
  }

  /// Looks up the published sha256 of [assetName] on release [version].
  ///
  /// Returns null when the digest cannot be determined — an unreachable or
  /// rate-limited GitHub API (60 requests/hour for unauthenticated callers)
  /// must not block an otherwise healthy download, so the caller simply skips
  /// verification in that case.
  Future<String?> fetchAssetSha256(String version, String assetName) async {
    final cacheKey = '$version/$assetName';
    final cached = _sha256Cache[cacheKey];
    if (cached != null) return cached;

    final client = _createHttpClient();
    try {
      final response = await client.get(
        Uri.parse(releaseApiUrl(version)),
        headers: const {
          'Accept': 'application/vnd.github+json',
          'X-GitHub-Api-Version': '2022-11-28',
        },
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode != 200) return null;

      final body = jsonDecode(response.body);
      if (body is! Map) return null;
      final assets = body['assets'];
      if (assets is! List) return null;

      for (final asset in assets) {
        if (asset is! Map) continue;
        if (asset['name']?.toString() != assetName) continue;

        // Reported as "sha256:<hex>".
        final digest = asset['digest']?.toString();
        if (digest == null) return null;
        const prefix = 'sha256:';
        if (!digest.startsWith(prefix)) return null;
        return _sha256Cache[cacheKey] = digest.substring(prefix.length);
      }

      return null;
    } catch (_) {
      return null;
    } finally {
      client.close();
    }
  }

  /// Remembers the digests of every asset on [release], so the
  /// [fetchAssetSha256] that follows a tag lookup needs no request of its own.
  void _cacheDigests(String tag, Map<dynamic, dynamic> release) {
    final assets = release['assets'];
    if (assets is! List) return;
    for (final asset in assets) {
      if (asset is! Map) continue;
      final name = asset['name']?.toString();
      final digest = asset['digest']?.toString();
      const prefix = 'sha256:';
      if (name == null || digest == null || !digest.startsWith(prefix)) continue;
      _sha256Cache['$tag/$name'] = digest.substring(prefix.length);
    }
  }

  /// The tag of the release to install on [channel], or null when GitHub
  /// cannot be asked.
  ///
  /// Stable takes the release GitHub marks as "Latest", which is never a
  /// draft or prerelease and which maintainers can move back to roll a bad
  /// release back. Alpha and beta pick the newest matching prerelease tag.
  ///
  /// Degrades to null rather than throwing for the same reason as
  /// [fetchAssetSha256]: the unauthenticated GitHub API allows only 60
  /// requests/hour, and a rate limit must not fail the sync.
  Future<String?> fetchLatestTag(ClientChannel channel) async {
    final cached = _latestTagCache[channel];
    if (cached != null && _now().difference(cached.at) < latestTagTtl) {
      return cached.tag;
    }

    final isStable = channel.prereleaseTagSegment == null;
    final client = _createHttpClient();
    try {
      final response = await client.get(
        Uri.parse(isStable ? latestReleaseApiUrl() : releasesApiUrl()),
        headers: const {
          'Accept': 'application/vnd.github+json',
          'X-GitHub-Api-Version': '2022-11-28',
        },
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode != 200) return null;

      final body = jsonDecode(response.body);
      final release = isStable
          ? (body is Map ? body : null)
          : (body is List ? _selectLatestRelease(body, channel) : null);
      final tag = release?['tag_name']?.toString();
      if (release == null || tag == null || tag.isEmpty) return null;

      _cacheDigests(tag, release);
      _latestTagCache[channel] = (tag: tag, at: _now());
      return tag;
    } catch (_) {
      return null;
    } finally {
      client.close();
    }
  }
}
