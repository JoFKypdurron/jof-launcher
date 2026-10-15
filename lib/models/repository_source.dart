/// Where the launcher fetches the cloud manifest and asset files from.
///
/// The JoF Cloud mirror (`cloud.jof.app`, S3 + CloudFront) is an hourly copy
/// of the original jofhub.eu repository. `auto` prefers the mirror to take load
/// off the origin, and falls back to the origin when the mirror is down or has
/// not caught up with a file yet (see `CloudService`).
enum RepositorySource { auto, mirror, origin }

extension RepositorySourceCodec on RepositorySource {
  String get persistedValue {
    return switch (this) {
      RepositorySource.auto => 'auto',
      RepositorySource.mirror => 'mirror',
      RepositorySource.origin => 'origin',
    };
  }

  /// The endpoints to try, in order.
  List<RepositoryEndpoint> get endpoints {
    return switch (this) {
      RepositorySource.auto => const [
          RepositoryEndpoint.mirror,
          RepositoryEndpoint.origin,
        ],
      RepositorySource.mirror => const [RepositoryEndpoint.mirror],
      RepositorySource.origin => const [RepositoryEndpoint.origin],
    };
  }

  static RepositorySource? tryParse(String? value) {
    return switch (value) {
      'auto' => RepositorySource.auto,
      'mirror' => RepositorySource.mirror,
      'origin' => RepositorySource.origin,
      _ => null,
    };
  }
}

/// One server hosting the asset repository. The only place the repository
/// hosts are spelled out.
class RepositoryEndpoint {
  /// Short name used in logs: `mirror` or `origin`.
  final String name;
  final String manifestUrl;
  final String fileHost;

  /// Path segments in front of an asset's `<localfolder>/<name>`.
  final List<String> filePathPrefix;

  const RepositoryEndpoint._({
    required this.name,
    required this.manifestUrl,
    required this.fileHost,
    required this.filePathPrefix,
  });

  static const RepositoryEndpoint origin = RepositoryEndpoint._(
    name: 'origin',
    manifestUrl: 'https://api.jofhub.eu/cloud/filemanager/getclouddata',
    fileHost: 'jofhub.eu',
    filePathPrefix: ['apps', 'cloud', 'repository'],
  );

  /// A byte-for-byte copy of the origin manifest, refreshed hourly. Files live
  /// under the same relative path as on the origin; only the base differs.
  static const RepositoryEndpoint mirror = RepositoryEndpoint._(
    name: 'mirror',
    manifestUrl: 'https://cloud.jof.app/cloud/manifest/getclouddata.json',
    fileHost: 'cloud.jof.app',
    filePathPrefix: ['cloud', 'repository'],
  );

  Uri get manifestUri => Uri.parse(manifestUrl);

  /// Builds the download URL for an asset's [relativePath] segments. Each
  /// segment is percent-encoded on its own, so names with spaces, `{}`, `&` or
  /// `%` survive intact.
  Uri fileUri(List<String> relativePath) {
    return Uri(
      scheme: 'https',
      host: fileHost,
      pathSegments: [...filePathPrefix, ...relativePath],
    );
  }

  @override
  String toString() => name;
}
