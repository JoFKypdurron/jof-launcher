import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:joflauncher/models/update_manifest.dart';
import 'package:joflauncher/services/cloud_service.dart';
import 'package:joflauncher/services/install_location_service.dart';
import 'package:joflauncher/services/self_update_installer.dart';

/// Stands in for the download: writes a placeholder where the installer
/// would land and records what was asked for.
class _FakeCloudService extends CloudService {
  String? downloadedTo;
  String? expectedSha256;

  @override
  Future<void> downloadFile({
    required String url,
    required String finalPath,
    int? expectedSize,
    String? expectedSha256,
    void Function(double progress)? onProgress,
    void Function(String status)? onStatus,
    bool Function()? isCancelled,
  }) async {
    downloadedTo = finalPath;
    this.expectedSha256 = expectedSha256;
    await File(finalPath).writeAsString('installer');
  }
}

String _decode(String encoded) {
  final bytes = base64Decode(encoded);
  final units = <int>[];
  for (var i = 0; i < bytes.length; i += 2) {
    units.add(bytes[i] | (bytes[i + 1] << 8));
  }
  return String.fromCharCodes(units);
}

const _artifact = UpdateArtifact(
  url: 'https://cloud.jof.app/launcher/jof-launcher-windows-setup-1.2.0.exe',
  sha256: 'abc123',
  size: 0,
);

const _installed = InstallLocation(
  kind: InstallKind.windowsInstalled,
  executablePath:
      r'C:\Users\me\AppData\Local\Programs\JoF Launcher\jof-launcher.exe',
  bundlePath: r'C:\Users\me\AppData\Local\Programs\JoF Launcher',
  parentWritable: true,
);

void main() {
  group('SelfUpdateInstaller.windowsUpdateScript', () {
    final script = SelfUpdateInstaller.windowsUpdateScript(
      parentPid: 4242,
      installerPath: r"C:\Users\O'Brien\AppData\Local\Temp\x\setup.exe",
      logPath: r"C:\Users\O'Brien\AppData\Local\Temp\x\update.log",
    );

    // The installer cannot replace a running exe, so it must not start first.
    test('waits for the launcher before running the installer', () {
      expect(script.indexOf('Wait-Process -Id 4242'),
          lessThan(script.indexOf('Start-Process')));
      expect(script, contains('Get-Process -Id 4242'));
    });

    test('runs the installer silently and asks it to relaunch', () {
      for (final arg in [
        "'/VERYSILENT'",
        "'/SUPPRESSMSGBOXES'",
        "'/NORESTART'",
        "'/relaunch=1'",
      ]) {
        expect(script, contains(arg));
      }
    });

    // A single quote in a user name must not end the PowerShell string.
    test('escapes single quotes in paths', () {
      expect(script,
          contains(r"-FilePath 'C:\Users\O''Brien\AppData\Local\Temp\x\setup.exe'"));
      expect(script,
          contains(r"$log = 'C:\Users\O''Brien\AppData\Local\Temp\x\update.log'"));
    });
  });

  test('encodePowerShellCommand is base64 of UTF-16LE', () {
    expect(SelfUpdateInstaller.encodePowerShellCommand('ab'),
        base64Encode([0x61, 0, 0x62, 0]));
  });

  test('installs by handing the verified installer to the helper', () async {
    final cloud = _FakeCloudService();
    List<String>? spawned;
    final installer = SelfUpdateInstaller(
      cloudService: cloud,
      spawnDetached: (executable, args) async {
        spawned = [executable, ...args];
        return Process.start(Platform.resolvedExecutable, ['--version']);
      },
    );

    final outcome = await installer.install(
      artifact: _artifact,
      expectedVersion: '1.2.0',
      location: _installed,
    );

    expect(outcome.readyToRelaunch, isTrue, reason: outcome.errorMessage);
    expect(cloud.expectedSha256, 'abc123');
    expect(cloud.downloadedTo, endsWith('jof-launcher-windows-setup-1.2.0.exe'));

    expect(spawned!.first, 'powershell.exe');
    expect(spawned, contains('-EncodedCommand'));
    final script = _decode(spawned!.last);
    expect(script, contains('Wait-Process -Id $pid'));
    expect(script, contains(cloud.downloadedTo!.replaceAll("'", "''")));

    await File(cloud.downloadedTo!).parent.delete(recursive: true);
  });

  test('a failed download is reported and nothing is started', () async {
    final installer = SelfUpdateInstaller(
      cloudService: _ThrowingCloudService(),
      spawnDetached: (_, _) async => fail('must not start the helper'),
    );

    final outcome = await installer.install(
      artifact: _artifact,
      expectedVersion: '1.2.0',
      location: _installed,
    );

    expect(outcome.readyToRelaunch, isFalse);
    expect(outcome.errorMessage, contains('checksum'));
  });
}

class _ThrowingCloudService extends CloudService {
  @override
  Future<void> downloadFile({
    required String url,
    required String finalPath,
    int? expectedSize,
    String? expectedSha256,
    void Function(double progress)? onProgress,
    void Function(String status)? onStatus,
    bool Function()? isCancelled,
  }) async {
    throw Exception('checksum mismatch');
  }
}
