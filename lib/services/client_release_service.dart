import 'dart:convert';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:http/http.dart' as http;

import '../models/client_channel.dart';
import '../models/platform_arch.dart';

/// Resolves which EternalJK client build to install, and where to fetch it.
///
/// The client tarballs live as release assets on the public
/// `JediofFreedom/JoF_EJK` GitHub repository. Which release to install is
/// decided remotely rather than baked into the launcher: the jofhub cloud
/// manifest carries the version inside the description of the `jofclient-*`
/// assets (e.g. `"JoF EJK Client 1.6.1 (64 Bit)"`), so publishing a new client
/// is a manifest edit, not a launcher release.
///
/// That description is free-form prose rather than a dedicated field, so
/// parsing is deliberately forgiving and always falls back to
/// [fallbackVersion] instead of failing the sync.
class ClientReleaseService {
  static const String repositoryOwner = 'JediofFreedom';
  static const String repositoryName = 'JoF_EJK';

  /// Used when no version can be parsed out of the cloud manifest. A reworded
  /// description must not leave users unable to download a client at all.
  static const String fallbackVersion = '1.6.1';

  /// Matches the first dotted version in a string, e.g. the `1.6.1` in
  /// `"JoF EJK Client 1.6.1 (64 Bit)"`.
  static final RegExp _versionPattern = RegExp(r'\b(\d+(?:\.\d+)+)\b');

  final http.Client Function()? _httpClientFactory;

  ClientReleaseService({http.Client Function()? httpClientFactory})
      : _httpClientFactory = httpClientFactory;

  http.Client _createHttpClient() =>
      _httpClientFactory?.call() ?? http.Client();

  /// Extracts the client version from the raw `clientgroups` list of the cloud
  /// manifest, or null when nothing version-shaped is present.
  ///
  /// Takes the raw decoded JSON rather than parsed `AssetGroup`s because
  /// `CloudService` replaces `clientgroups` with a synthetic placeholder on
  /// Linux and macOS, discarding the descriptions this reads.
  static String? parseVersion(List<dynamic>? clientGroupsJson) {
    if (clientGroupsJson == null) return null;

    for (final group in clientGroupsJson) {
      if (group is! Map) continue;
      final assets = group['assets'];
      if (assets is! List) continue;

      for (final asset in assets) {
        if (asset is! Map) continue;
        // Only the jofclient payload carries the client version; other assets
        // in the group (SDL2.dll, steam_api.dll, ...) have their own versions.
        final name = asset['name']?.toString() ?? '';
        if (!name.startsWith('jofclient-')) continue;

        final match =
            _versionPattern.firstMatch(asset['description']?.toString() ?? '');
        if (match != null) return match.group(1);
      }
    }

    return null;
  }

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
  /// mocking HTTP. Stable has no prerelease tag shape to select — callers
  /// keep using the manifest-driven version for that channel — so this
  /// always returns null for it.
  @visibleForTesting
  static String? selectLatestTag(
      List<dynamic> releasesJson, ClientChannel channel) {
    final segment = channel.prereleaseTagSegment;
    if (segment == null) return null;

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
        bestTag = tag;
        bestBase = base;
        bestBuild = build;
      }
    }

    return bestTag;
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
        return digest.substring(prefix.length);
      }

      return null;
    } catch (_) {
      return null;
    } finally {
      client.close();
    }
  }

  /// The newest published tag on [channel], or null for [ClientChannel.stable]
  /// (which has no such tag shape) and whenever the lookup fails.
  ///
  /// Degrades to null rather than throwing for the same reason as
  /// [fetchAssetSha256]: the unauthenticated GitHub API allows only 60
  /// requests/hour, and a rate limit must not fail the sync. Callers fall
  /// back to the stable version resolution in that case.
  Future<String?> fetchLatestTag(ClientChannel channel) async {
    if (channel.prereleaseTagSegment == null) return null;

    final client = _createHttpClient();
    try {
      final response = await client.get(
        Uri.parse(releasesApiUrl()),
        headers: const {
          'Accept': 'application/vnd.github+json',
          'X-GitHub-Api-Version': '2022-11-28',
        },
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode != 200) return null;

      final body = jsonDecode(response.body);
      if (body is! List) return null;

      return selectLatestTag(body, channel);
    } catch (_) {
      return null;
    } finally {
      client.close();
    }
  }
}
