import 'dart:io';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:path/path.dart' as p;

import '../models/update_manifest.dart';
import 'cloud_service.dart';
import 'install_location_service.dart';

typedef ProcessRunner = Future<ProcessResult> Function(
    String executable, List<String> args);
typedef ProcessSpawner = Future<Process> Function(
    String executable, List<String> args);

class InstallOutcome {
  /// The swap helper is running and waiting for this process to exit. The
  /// caller must quit now; the helper relaunches the new build.
  final bool readyToRelaunch;
  final String? errorMessage;

  const InstallOutcome.ready()
      : readyToRelaunch = true,
        errorMessage = null;
  const InstallOutcome.failed(this.errorMessage) : readyToRelaunch = false;
}

/// Downloads a release and swaps it over the running install.
///
/// The swap itself cannot happen in-process: a program cannot replace the
/// bundle it is executing from. So the work splits in two — this class stages
/// and verifies a complete, known-good copy, then hands a small shell script
/// the job of waiting for us to exit, renaming the new copy into place and
/// relaunching. Everything that can fail is done *before* the running install
/// is touched.
class SelfUpdateInstaller {
  final CloudService _cloudService;
  final ProcessRunner _runProcess;
  final ProcessSpawner _spawnProcess;

  SelfUpdateInstaller({
    CloudService? cloudService,
    ProcessRunner? runProcess,
    ProcessSpawner? spawnProcess,
  })  : _cloudService = cloudService ?? CloudService(),
        _runProcess = runProcess ?? Process.run,
        _spawnProcess = spawnProcess ?? Process.start;

  Future<InstallOutcome> install({
    required UpdateArtifact artifact,
    required String expectedVersion,
    required InstallLocation location,
    void Function(double progress)? onProgress,
    void Function(String status)? onStatus,
    bool Function()? isCancelled,
  }) async {
    if (!location.canSelfUpdate || location.bundlePath == null) {
      return const InstallOutcome.failed('This install cannot update itself.');
    }

    final target = location.bundlePath!;
    final parent = p.dirname(target);

    // Staging sits beside the target so the final move is a same-volume
    // rename: atomic, and it cannot half-copy.
    final staging = Directory(p.join(parent, '.jof-launcher-update-$pid'));
    Directory? tempDir;

    try {
      if (await staging.exists()) await staging.delete(recursive: true);
      await staging.create(recursive: true);

      tempDir = await Directory.systemTemp.createTemp('jof_launcher_update_');
      final archivePath = p.join(tempDir.path, p.basename(artifact.url));

      onStatus?.call('Downloading launcher $expectedVersion');
      await _cloudService.downloadFile(
        url: artifact.url,
        finalPath: archivePath,
        expectedSize: artifact.size > 0 ? artifact.size : null,
        expectedSha256: artifact.sha256,
        onProgress: (value) => onProgress?.call(value * 0.8),
        onStatus: onStatus,
        isCancelled: isCancelled,
      );

      onStatus?.call('Preparing update');
      onProgress?.call(0.85);

      final staged = Platform.isMacOS
          ? await _stageMacos(archivePath, staging.path)
          : await _stageLinux(archivePath, staging.path, p.basename(target));

      if (staged == null) {
        await _cleanup(staging, tempDir);
        return const InstallOutcome.failed('Could not unpack the update.');
      }

      final actualVersion = await _stagedVersion(staged);
      if (actualVersion != null && actualVersion != expectedVersion) {
        // Refusing here is what stops an update loop: installing a build that
        // reports a different version than advertised would leave the launcher
        // offering the same update forever.
        await _cleanup(staging, tempDir);
        return InstallOutcome.failed(
            'Update reported version $actualVersion, expected $expectedVersion.');
      }

      if (!await _stagedLooksRunnable(staged)) {
        await _cleanup(staging, tempDir);
        return const InstallOutcome.failed('The downloaded update is incomplete.');
      }

      onProgress?.call(0.95);

      // The script must not live inside the directory it deletes: sh reads
      // scripts incrementally and can mis-parse a file removed underneath it.
      final scriptPath = p.join(tempDir.path, 'apply-update.sh');
      final script = File(scriptPath);
      await script.writeAsString(
          Platform.isMacOS ? macosSwapScript : linuxSwapScript);
      await _runProcess('chmod', ['0755', scriptPath]);

      onStatus?.call('Restarting to finish update');
      await _spawnProcess('/bin/sh', [
        scriptPath,
        '$pid',
        staged,
        target,
        '$target.bak',
        p.join(tempDir.path, 'update.log'),
      ]);

      return const InstallOutcome.ready();
    } catch (e) {
      await _cleanup(staging, tempDir);
      return InstallOutcome.failed('Update failed: $e');
    }
  }

  Future<void> _cleanup(Directory staging, Directory? temp) async {
    try {
      if (await staging.exists()) await staging.delete(recursive: true);
    } catch (_) {}
    // The temp dir holds the helper script and log, so it is left in place on
    // success; only remove it when we are abandoning the update.
    try {
      if (temp != null && await temp.exists()) await temp.delete(recursive: true);
    } catch (_) {}
  }

  /// Unpacks the DMG with `ditto`, which preserves the symlinks, extended
  /// attributes and ad-hoc signature inside a .app bundle. Dart's archive
  /// package cannot reconstruct symlinks and would produce a broken bundle.
  Future<String?> _stageMacos(String dmgPath, String stagingPath) async {
    final mountPoint = p.join(stagingPath, 'mnt');
    await Directory(mountPoint).create(recursive: true);

    final attach = await _runProcess('hdiutil',
        ['attach', dmgPath, '-nobrowse', '-readonly', '-mountpoint', mountPoint]);
    if (attach.exitCode != 0) return null;

    try {
      final apps = Directory(mountPoint)
          .listSync()
          .whereType<Directory>()
          .where((d) => p.extension(d.path) == '.app')
          .toList();
      if (apps.length != 1) return null;

      final destination = p.join(stagingPath, p.basename(apps.first.path));
      final copy = await _runProcess('ditto', [apps.first.path, destination]);
      if (copy.exitCode != 0) return null;

      // Files written by this process inherit its quarantine flag, and a
      // quarantined bundle gets relaunched from a randomised read-only copy
      // by Gatekeeper instead of from where we installed it.
      await _runProcess('xattr', ['-dr', 'com.apple.quarantine', destination]);
      return destination;
    } finally {
      await _runProcess('hdiutil', ['detach', mountPoint, '-quiet']);
    }
  }

  /// Unpacks the tarball with system `tar`, which preserves modes so the
  /// launcher binary stays executable.
  Future<String?> _stageLinux(
      String archivePath, String stagingPath, String targetName) async {
    final result = await _runProcess(
        'tar', ['-xzf', archivePath, '-C', stagingPath, '--no-same-owner']);
    if (result.exitCode != 0) return null;

    final extracted = Directory(stagingPath)
        .listSync()
        .whereType<Directory>()
        .where((d) => p.basename(d.path) != 'mnt')
        .toList();
    if (extracted.length != 1) return null;

    // The user may have renamed their install directory; the swap replaces it
    // by path, so the staged directory has to match that name.
    var staged = extracted.first.path;
    if (p.basename(staged) != targetName) {
      final renamed = p.join(stagingPath, targetName);
      await Directory(staged).rename(renamed);
      staged = renamed;
    }
    return staged;
  }

  /// Reads the version out of the staged build, using the same source the
  /// running app will read after the swap.
  Future<String?> _stagedVersion(String stagedPath) async {
    try {
      if (Platform.isMacOS) {
        final result = await _runProcess('plutil', [
          '-extract',
          'CFBundleShortVersionString',
          'raw',
          '-o',
          '-',
          p.join(stagedPath, 'Contents', 'Info.plist'),
        ]);
        if (result.exitCode != 0) return null;
        final value = result.stdout.toString().trim();
        return value.isEmpty ? null : value;
      }

      final versionFile =
          File(p.join(stagedPath, 'data', 'flutter_assets', 'version.json'));
      if (!await versionFile.exists()) return null;
      final match = RegExp(r'"version"\s*:\s*"([^"]+)"')
          .firstMatch(await versionFile.readAsString());
      return match?.group(1);
    } catch (_) {
      return null;
    }
  }

  Future<bool> _stagedLooksRunnable(String stagedPath) async {
    if (Platform.isMacOS) {
      final macosDir = Directory(p.join(stagedPath, 'Contents', 'MacOS'));
      if (!await macosDir.exists()) return false;
      return macosDir.listSync().whereType<File>().isNotEmpty;
    }
    return File(p.join(stagedPath, 'jof-launcher')).exists();
  }

  /// Waits for the launcher to exit, swaps the bundle and relaunches.
  ///
  /// Every path is a same-volume rename, and the backup is only removed once
  /// the new bundle is in place and looks runnable, so a failure at any point
  /// restores what was there before.
  @visibleForTesting
  static const String macosSwapScript = r'''
#!/bin/sh
# $1 parent pid  $2 staged .app  $3 target .app  $4 backup path  $5 log
set -u
PARENT="$1"; STAGED="$2"; TARGET="$3"; BACKUP="$4"; LOG="$5"
exec >>"$LOG" 2>&1
echo "=== jof-launcher update target=$TARGET"

i=0
while kill -0 "$PARENT" 2>/dev/null; do
  i=$((i+1))
  if [ "$i" -ge 150 ]; then echo "parent still running after 30s; aborting"; exit 1; fi
  sleep 0.2
done

rm -rf "$BACKUP"
if [ -e "$TARGET" ] && ! mv "$TARGET" "$BACKUP"; then
  echo "could not move the old bundle aside"; exit 1
fi
if ! mv "$STAGED" "$TARGET"; then
  echo "could not move the new bundle in; rolling back"
  [ -e "$BACKUP" ] && mv "$BACKUP" "$TARGET"
  exit 1
fi

BIN_DIR="$TARGET/Contents/MacOS"
if [ ! -d "$BIN_DIR" ]; then
  echo "new bundle has no executable; rolling back"
  rm -rf "$TARGET"; [ -e "$BACKUP" ] && mv "$BACKUP" "$TARGET"
  exit 1
fi

xattr -dr com.apple.quarantine "$TARGET" 2>/dev/null || true
rm -rf "$BACKUP"
rm -rf "$(dirname "$STAGED")"
echo "update applied; relaunching"
open "$TARGET"
exit 0
''';

  @visibleForTesting
  static const String linuxSwapScript = r'''
#!/bin/sh
# $1 parent pid  $2 staged dir  $3 target dir  $4 backup path  $5 log
set -u
PARENT="$1"; STAGED="$2"; TARGET="$3"; BACKUP="$4"; LOG="$5"
exec >>"$LOG" 2>&1
echo "=== jof-launcher update target=$TARGET"

i=0
while kill -0 "$PARENT" 2>/dev/null; do
  i=$((i+1))
  if [ "$i" -ge 150 ]; then echo "parent still running after 30s; aborting"; exit 1; fi
  sleep 0.2
done

rm -rf "$BACKUP"
if [ -e "$TARGET" ] && ! mv "$TARGET" "$BACKUP"; then
  echo "could not move the old install aside"; exit 1
fi
if ! mv "$STAGED" "$TARGET"; then
  echo "could not move the new install in; rolling back"
  [ -e "$BACKUP" ] && mv "$BACKUP" "$TARGET"
  exit 1
fi

BIN="$TARGET/jof-launcher"
if [ ! -f "$BIN" ]; then
  echo "new install has no binary; rolling back"
  rm -rf "$TARGET"; [ -e "$BACKUP" ] && mv "$BACKUP" "$TARGET"
  exit 1
fi
chmod 0755 "$BIN" 2>/dev/null || true

rm -rf "$BACKUP"
rm -rf "$(dirname "$STAGED")"
echo "update applied; relaunching"
( cd "$TARGET" && exec "$BIN" ) &
exit 0
''';
}
