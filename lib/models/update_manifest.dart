import 'dart:convert';

/// Which release artifact a given install needs.
enum UpdateArtifactKind { macos, linuxTar, linuxDeb }

class UpdateArtifact {
  final String url;
  final String sha256;
  final int size;

  const UpdateArtifact({
    required this.url,
    required this.sha256,
    required this.size,
  });

  static UpdateArtifact? tryParse(Object? json) {
    if (json is! Map) return null;
    final url = json['url']?.toString();
    final sha = json['sha256']?.toString();
    if (url == null || url.isEmpty) return null;
    if (sha == null || sha.isEmpty) return null;
    final size = json['size'];
    return UpdateArtifact(
      url: url,
      sha256: sha,
      size: size is int ? size : int.tryParse(size?.toString() ?? '') ?? 0,
    );
  }
}

/// The `latest.json` update manifest published alongside the release artifacts.
///
/// Parsing is deliberately tolerant: unknown fields are ignored so the manifest
/// can gain fields without breaking installed launchers, and anything
/// malformed yields null rather than throwing. A launcher that cannot read the
/// manifest should carry on silently, not fail to start.
class UpdateManifest {
  /// Highest manifest schema this build understands.
  static const int supportedSchema = 1;

  final int schema;
  final String version;
  final String? tag;
  final String? notesUrl;
  final String? downloadPageUrl;
  final Map<UpdateArtifactKind, UpdateArtifact> artifacts;

  const UpdateManifest({
    required this.schema,
    required this.version,
    required this.artifacts,
    this.tag,
    this.notesUrl,
    this.downloadPageUrl,
  });

  /// False when the manifest was written by a newer release process than this
  /// build knows about. Such a manifest can still advertise that an update
  /// exists, but must not be trusted to drive an install.
  bool get isSupportedSchema => schema <= supportedSchema;

  UpdateArtifact? artifactFor(UpdateArtifactKind kind) => artifacts[kind];

  static const Map<String, UpdateArtifactKind> _kindKeys = {
    'macos': UpdateArtifactKind.macos,
    'linuxTar': UpdateArtifactKind.linuxTar,
    'linuxDeb': UpdateArtifactKind.linuxDeb,
  };

  /// Parses a manifest document, returning null for anything unusable.
  static UpdateManifest? tryParse(String body) {
    Object? decoded;
    try {
      decoded = jsonDecode(body);
    } catch (_) {
      return null;
    }
    if (decoded is! Map) return null;

    final version = decoded['version']?.toString();
    if (version == null || version.isEmpty) return null;

    final schemaValue = decoded['schema'];
    final schema = schemaValue is int
        ? schemaValue
        : int.tryParse(schemaValue?.toString() ?? '') ?? 1;

    final artifacts = <UpdateArtifactKind, UpdateArtifact>{};
    final rawArtifacts = decoded['artifacts'];
    if (rawArtifacts is Map) {
      for (final entry in _kindKeys.entries) {
        final artifact = UpdateArtifact.tryParse(rawArtifacts[entry.key]);
        if (artifact != null) artifacts[entry.value] = artifact;
      }
    }

    return UpdateManifest(
      schema: schema,
      version: version,
      tag: decoded['tag']?.toString(),
      notesUrl: decoded['notesUrl']?.toString(),
      downloadPageUrl: decoded['downloadPageUrl']?.toString(),
      artifacts: artifacts,
    );
  }
}
