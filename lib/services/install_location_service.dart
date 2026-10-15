import 'dart:io';

import 'package:flutter/foundation.dart' show kReleaseMode, visibleForTesting;
import 'package:path/path.dart' as p;

import '../models/update_manifest.dart';

/// How this launcher was installed, which decides whether it can replace itself.
enum InstallKind {
  /// A macOS .app bundle in a normal location.
  macosAppBundle,

  /// Running from Gatekeeper's randomised read-only copy. The bundle is not
  /// where the user thinks it is, so replacing it would do nothing.
  macosTranslocated,

  /// Running straight off a mounted disk image.
  macosOnVolume,

  /// A build tree, not an install.
  macosDevBuild,

  /// The tarball layout, extracted wherever the user chose.
  linuxTarball,

  /// Installed by the .deb into root-owned /opt.
  linuxDeb,

  /// AppImage or Snap — owned by another update mechanism.
  linuxPackagedOther,

  /// Reserved: Windows releases are not currently published.
  windows,

  unknown,
}

class InstallLocation {
  final InstallKind kind;
  final String executablePath;

  /// The thing that would be swapped: the `.app` bundle on macOS, the
  /// extracted directory on Linux. Null when it could not be determined.
  final String? bundlePath;

  /// Whether the *parent* of [bundlePath] is writable. The swap renames within
  /// that parent, so permission inside the bundle is irrelevant.
  final bool parentWritable;

  final String? reason;

  const InstallLocation({
    required this.kind,
    required this.executablePath,
    required this.parentWritable,
    this.bundlePath,
    this.reason,
  });

  bool get canSelfUpdate =>
      parentWritable &&
      bundlePath != null &&
      (kind == InstallKind.macosAppBundle || kind == InstallKind.linuxTarball);

  /// Which release artifact this install would need.
  UpdateArtifactKind? get artifactKind {
    switch (kind) {
      case InstallKind.macosAppBundle:
      case InstallKind.macosTranslocated:
      case InstallKind.macosOnVolume:
      case InstallKind.macosDevBuild:
        return UpdateArtifactKind.macos;
      case InstallKind.linuxTarball:
        return UpdateArtifactKind.linuxTar;
      case InstallKind.linuxDeb:
        return UpdateArtifactKind.linuxDeb;
      case InstallKind.linuxPackagedOther:
      case InstallKind.windows:
      case InstallKind.unknown:
        return null;
    }
  }
}

class InstallLocationService {
  final String? _resolvedExecutableOverride;
  final Map<String, String>? _environmentOverride;
  final Future<bool> Function(String directory)? _writabilityProbe;

  /// Test seam. Under `flutter test` [kReleaseMode] is false, which would
  /// classify every install as a dev build and make the eligibility rules
  /// untestable.
  final bool? _isReleaseModeOverride;

  /// Test seam, so the Linux rules can be exercised from a macOS host and
  /// vice versa. Both sets of rules ship on every platform.
  final String? _osOverride;

  InstallLocationService({
    String? resolvedExecutableOverride,
    Map<String, String>? environmentOverride,
    Future<bool> Function(String directory)? writabilityProbe,
    bool? isReleaseModeOverride,
    String? osOverride,
  })  : _resolvedExecutableOverride = resolvedExecutableOverride,
        _environmentOverride = environmentOverride,
        _writabilityProbe = writabilityProbe,
        _isReleaseModeOverride = isReleaseModeOverride,
        _osOverride = osOverride;

  Future<InstallLocation> detect() async {
    final executable = _resolvedExecutableOverride ?? Platform.resolvedExecutable;
    final env = _environmentOverride ?? Platform.environment;
    final os = _osOverride ?? Platform.operatingSystem;

    final kind = classify(
      resolvedExecutable: executable,
      os: os,
      env: env,
      isReleaseMode: _isReleaseModeOverride ?? kReleaseMode,
    );
    final bundle = bundlePathFor(resolvedExecutable: executable, os: os);

    var writable = false;
    if (bundle != null) {
      writable = await (_writabilityProbe ?? _probeWritable)(p.dirname(bundle));
    }

    return InstallLocation(
      kind: kind,
      executablePath: executable,
      bundlePath: bundle,
      parentWritable: writable,
      reason: _reasonFor(kind, writable),
    );
  }

  /// The directory that would be replaced, derived purely from [resolvedExecutable].
  ///
  /// macOS: `…/JoF Launcher.app/Contents/MacOS/JoF Launcher` → the `.app`.
  /// Linux: the directory holding the binary.
  @visibleForTesting
  static String? bundlePathFor({
    required String resolvedExecutable,
    required String os,
  }) {
    // The Linux and macOS rules always parse POSIX paths, also when tests
    // exercise them from a Windows host, whose `p` would rewrite `/` to `\`.
    if (os == 'macos') {
      var dir = p.posix.dirname(resolvedExecutable);
      for (var i = 0; i < 3; i++) {
        if (p.posix.extension(dir) == '.app') return dir;
        final parent = p.posix.dirname(dir);
        if (parent == dir) break;
        dir = parent;
      }
      return null;
    }
    if (os == 'linux') return p.posix.dirname(resolvedExecutable);
    return null;
  }

  /// Pure classification — no filesystem access, so the whole matrix is testable.
  @visibleForTesting
  static InstallKind classify({
    required String resolvedExecutable,
    required String os,
    required Map<String, String> env,
    required bool isReleaseMode,
  }) {
    if (os == 'windows') return InstallKind.windows;

    if (os == 'macos') {
      // Checked before anything else: a translocated path is a copy, so every
      // other signal about it is misleading.
      if (resolvedExecutable.contains('/AppTranslocation/')) {
        return InstallKind.macosTranslocated;
      }
      final bundle =
          bundlePathFor(resolvedExecutable: resolvedExecutable, os: os);
      if (bundle == null) return InstallKind.unknown;
      if (bundle.startsWith('/Volumes/')) return InstallKind.macosOnVolume;
      if (bundle.contains('/build/macos/Build/Products/') || !isReleaseMode) {
        return InstallKind.macosDevBuild;
      }
      return InstallKind.macosAppBundle;
    }

    if (os == 'linux') {
      if (env['APPIMAGE'] != null || env['SNAP'] != null) {
        return InstallKind.linuxPackagedOther;
      }
      final dir = p.posix.normalize(p.posix.dirname(resolvedExecutable));
      if (dir == '/opt/jof-launcher') return InstallKind.linuxDeb;
      if (!isReleaseMode) return InstallKind.unknown;
      return InstallKind.linuxTarball;
    }

    return InstallKind.unknown;
  }

  static String? _reasonFor(InstallKind kind, bool writable) {
    switch (kind) {
      case InstallKind.macosTranslocated:
        return 'Move JoF Launcher to Applications, then reopen it to update.';
      case InstallKind.macosOnVolume:
        return 'Copy JoF Launcher to Applications first.';
      case InstallKind.macosDevBuild:
        return 'Running from a build tree.';
      case InstallKind.linuxDeb:
        return 'Installed from a .deb package.';
      case InstallKind.linuxPackagedOther:
        return 'Managed by the packaging system.';
      case InstallKind.windows:
      case InstallKind.unknown:
        return 'Unrecognised install location.';
      case InstallKind.macosAppBundle:
      case InstallKind.linuxTarball:
        return writable ? null : 'No write access to the install folder.';
    }
  }

  /// Probes by creating and removing a file, since POSIX permission bits alone
  /// do not account for ACLs or a read-only mount.
  static Future<bool> _probeWritable(String directory) async {
    try {
      final dir = Directory(directory);
      if (!await dir.exists()) return false;
      final probe = File(p.join(directory, '.jof-launcher-write-probe-$pid'));
      await probe.writeAsString('');
      await probe.delete();
      return true;
    } catch (_) {
      return false;
    }
  }
}
