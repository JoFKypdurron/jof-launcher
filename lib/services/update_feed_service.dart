import 'dart:convert';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:http/http.dart' as http;

import '../models/update_manifest.dart';

/// Discovers the latest published launcher release.
///
/// The primary source is a small manifest on our own CDN. The GitHub releases
/// API is kept as a fallback because the manifest is a single mutable object:
/// if a release ever fails to publish it, the fallback keeps update checks
/// working instead of silently stranding every installed launcher.
///
/// Every method swallows its errors and returns null. An update check is
/// best-effort background work and must never surface an error to the user or
/// interfere with startup.
class UpdateFeedService {
  static const String manifestUrl =
      'https://cloud.jof.app/launcher/latest.json';
  static const String repositoryOwner = 'JoFKypdurron';
  static const String repositoryName = 'jof-launcher';

  static const Duration _timeout = Duration(seconds: 15);

  final http.Client Function()? _httpClientFactory;

  UpdateFeedService({http.Client Function()? httpClientFactory})
      : _httpClientFactory = httpClientFactory;

  http.Client _createHttpClient() => _httpClientFactory?.call() ?? http.Client();

  /// The latest release, or null if it cannot be determined.
  Future<UpdateManifest?> fetchLatest() async {
    return await fetchFromManifest() ?? await fetchFromGithubReleases();
  }

  @visibleForTesting
  Future<UpdateManifest?> fetchFromManifest() async {
    final client = _createHttpClient();
    try {
      final response =
          await client.get(Uri.parse(manifestUrl)).timeout(_timeout);
      if (response.statusCode != 200) return null;
      return UpdateManifest.tryParse(response.body);
    } catch (_) {
      return null;
    } finally {
      client.close();
    }
  }

  @visibleForTesting
  static String get githubLatestReleaseUrl => Uri.https(
        'api.github.com',
        '/repos/$repositoryOwner/$repositoryName/releases/latest',
      ).toString();

  /// Reconstructs a manifest from the GitHub release for the latest tag.
  ///
  /// Only used when the manifest is unavailable. Note the unauthenticated
  /// GitHub API allows 60 requests/hour per IP, which is why this is the
  /// fallback rather than the primary source.
  @visibleForTesting
  Future<UpdateManifest?> fetchFromGithubReleases() async {
    final client = _createHttpClient();
    try {
      final response = await client.get(
        Uri.parse(githubLatestReleaseUrl),
        headers: const {
          'Accept': 'application/vnd.github+json',
          'X-GitHub-Api-Version': '2022-11-28',
        },
      ).timeout(_timeout);
      if (response.statusCode != 200) return null;

      final body = jsonDecode(response.body);
      if (body is! Map) return null;

      final tag = body['tag_name']?.toString();
      if (tag == null || tag.isEmpty) return null;

      final assets = body['assets'];
      final artifacts = <UpdateArtifactKind, UpdateArtifact>{};
      if (assets is List) {
        for (final asset in assets) {
          if (asset is! Map) continue;
          final name = asset['name']?.toString() ?? '';
          final kind = _kindForAssetName(name);
          if (kind == null) continue;

          final url = asset['browser_download_url']?.toString();
          if (url == null || url.isEmpty) continue;

          // GitHub reports this as "sha256:<hex>". Without it we cannot verify
          // the download, so the artifact is not offered at all.
          final digest = asset['digest']?.toString();
          const prefix = 'sha256:';
          if (digest == null || !digest.startsWith(prefix)) continue;

          final size = asset['size'];
          artifacts[kind] = UpdateArtifact(
            url: url,
            sha256: digest.substring(prefix.length),
            size: size is int ? size : 0,
          );
        }
      }

      var version = tag;
      if (version.startsWith('v')) version = version.substring(1);
      if (version.endsWith('-launcher')) {
        version = version.substring(0, version.length - '-launcher'.length);
      }

      final notes =
          'https://github.com/$repositoryOwner/$repositoryName/releases/tag/$tag';

      return UpdateManifest(
        schema: UpdateManifest.supportedSchema,
        version: version,
        tag: tag,
        notesUrl: notes,
        downloadPageUrl: notes,
        artifacts: artifacts,
      );
    } catch (_) {
      return null;
    } finally {
      client.close();
    }
  }

  static UpdateArtifactKind? _kindForAssetName(String name) {
    if (name.endsWith('.dmg')) return UpdateArtifactKind.macos;
    if (name.endsWith('.deb')) return UpdateArtifactKind.linuxDeb;
    if (name.startsWith('jof-launcher-linux') && name.endsWith('.tar.gz')) {
      return UpdateArtifactKind.linuxTar;
    }
    return null;
  }
}
