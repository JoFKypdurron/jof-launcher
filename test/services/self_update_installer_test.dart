@TestOn('posix')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:joflauncher/services/self_update_installer.dart';

/// Runs a swap script against throwaway directories, standing in for the
/// launcher with a `sleep` process so the script's "wait for the parent to
/// exit" logic is genuinely exercised. Never touches a real install.
Future<int> runSwap({
  required String script,
  required String staged,
  required String target,
  required String backup,
  required String log,
}) async {
  final scriptFile = File(p.join(p.dirname(log), 'swap.sh'));
  await scriptFile.writeAsString(script);
  await Process.run('chmod', ['0755', scriptFile.path]);

  final parent = await Process.start('sleep', ['30']);
  final swap = await Process.start(
    '/bin/sh',
    [scriptFile.path, '${parent.pid}', staged, target, backup, log],
  );

  // Let the script reach its wait loop, then release it.
  await Future<void>.delayed(const Duration(milliseconds: 300));
  parent.kill();
  await parent.exitCode;

  return swap.exitCode.timeout(const Duration(seconds: 30));
}

/// A minimal stand-in for the Linux bundle layout.
Future<void> makeLinuxTree(String dir, String marker, {bool withBinary = true}) async {
  await Directory(p.join(dir, 'data', 'flutter_assets')).create(recursive: true);
  await File(p.join(dir, 'data', 'flutter_assets', 'version.json'))
      .writeAsString('{"version":"$marker"}');
  if (withBinary) {
    final bin = File(p.join(dir, 'jof-launcher'));
    await bin.writeAsString('#!/bin/sh\ntouch "\$(dirname "\$0")/../relaunched-$marker"\n');
    await Process.run('chmod', ['0755', bin.path]);
  }
}

void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('jof_swap_test_');
  });
  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  group('linux swap script', () {
    test('replaces the install, clears the backup and relaunches', () async {
      final staging = p.join(root.path, '.staging');
      final staged = p.join(staging, 'jof-launcher');
      final target = p.join(root.path, 'jof-launcher');

      await Directory(staging).create(recursive: true);
      await makeLinuxTree(staged, 'new');
      await makeLinuxTree(target, 'old');

      final exit = await runSwap(
        script: SelfUpdateInstaller.linuxSwapScript,
        staged: staged,
        target: target,
        backup: '$target.bak',
        log: p.join(root.path, 'update.log'),
      );

      expect(exit, 0, reason: await File(p.join(root.path, 'update.log')).readAsString());

      // The new tree is now the install...
      final version =
          await File(p.join(target, 'data', 'flutter_assets', 'version.json'))
              .readAsString();
      expect(version, contains('"new"'));

      // ...the backup is gone, and so is the staging directory.
      expect(await Directory('$target.bak').exists(), isFalse);
      expect(await Directory(staging).exists(), isFalse);

      // The relaunch actually fired. Polled rather than slept on: the
      // relaunched process is detached, so its timing is not ours to predict.
      final sentinel = File(p.join(root.path, 'relaunched-new'));
      var waited = Duration.zero;
      const step = Duration(milliseconds: 100);
      while (!await sentinel.exists() && waited < const Duration(seconds: 10)) {
        await Future<void>.delayed(step);
        waited += step;
      }
      expect(await sentinel.exists(), isTrue,
          reason: 'the swap script should have relaunched the new build');
    });

    test('restores the old install when the new one cannot be moved in',
        () async {
      final staging = p.join(root.path, '.staging');
      final staged = p.join(staging, 'jof-launcher');
      final target = p.join(root.path, 'jof-launcher');

      await Directory(staging).create(recursive: true);
      await makeLinuxTree(target, 'old');
      // Staged path deliberately absent: the move must fail.

      final exit = await runSwap(
        script: SelfUpdateInstaller.linuxSwapScript,
        staged: staged,
        target: target,
        backup: '$target.bak',
        log: p.join(root.path, 'update.log'),
      );

      expect(exit, isNot(0));
      // The critical property: the user still has a working install.
      expect(await Directory(target).exists(), isTrue);
      final version =
          await File(p.join(target, 'data', 'flutter_assets', 'version.json'))
              .readAsString();
      expect(version, contains('"old"'));
    });

    test('rolls back when the new install has no binary', () async {
      final staging = p.join(root.path, '.staging');
      final staged = p.join(staging, 'jof-launcher');
      final target = p.join(root.path, 'jof-launcher');

      await Directory(staging).create(recursive: true);
      await makeLinuxTree(staged, 'broken', withBinary: false);
      await makeLinuxTree(target, 'old');

      final exit = await runSwap(
        script: SelfUpdateInstaller.linuxSwapScript,
        staged: staged,
        target: target,
        backup: '$target.bak',
        log: p.join(root.path, 'update.log'),
      );

      expect(exit, isNot(0));
      expect(await Directory(target).exists(), isTrue);
      final version =
          await File(p.join(target, 'data', 'flutter_assets', 'version.json'))
              .readAsString();
      expect(version, contains('"old"'),
          reason: 'a structurally broken update must not replace a good install');
    });
  });

  group('macos swap script', () {
    // Only the rollback paths are exercised here: the success path ends in
    // `open`, which would hand a fake bundle to LaunchServices.
    test('restores the old bundle when the new one cannot be moved in',
        () async {
      final staging = p.join(root.path, '.staging');
      final staged = p.join(staging, 'JoF Launcher.app');
      final target = p.join(root.path, 'JoF Launcher.app');

      await Directory(staging).create(recursive: true);
      await Directory(p.join(target, 'Contents', 'MacOS')).create(recursive: true);
      await File(p.join(target, 'Contents', 'MacOS', 'marker')).writeAsString('old');

      final exit = await runSwap(
        script: SelfUpdateInstaller.macosSwapScript,
        staged: staged,
        target: target,
        backup: '$target.bak',
        log: p.join(root.path, 'update.log'),
      );

      expect(exit, isNot(0));
      expect(
        await File(p.join(target, 'Contents', 'MacOS', 'marker')).readAsString(),
        'old',
      );
    });

    test('rolls back a bundle with no Contents/MacOS', () async {
      final staging = p.join(root.path, '.staging');
      final staged = p.join(staging, 'JoF Launcher.app');
      final target = p.join(root.path, 'JoF Launcher.app');

      // Staged bundle is structurally wrong: no Contents/MacOS at all.
      await Directory(staged).create(recursive: true);
      await Directory(p.join(target, 'Contents', 'MacOS')).create(recursive: true);
      await File(p.join(target, 'Contents', 'MacOS', 'marker')).writeAsString('old');

      final exit = await runSwap(
        script: SelfUpdateInstaller.macosSwapScript,
        staged: staged,
        target: target,
        backup: '$target.bak',
        log: p.join(root.path, 'update.log'),
      );

      expect(exit, isNot(0));
      expect(
        await File(p.join(target, 'Contents', 'MacOS', 'marker')).readAsString(),
        'old',
        reason: 'the original bundle must survive a broken download',
      );
    });
  });

  group('script safety properties', () {
    for (final entry in {
      'macos': SelfUpdateInstaller.macosSwapScript,
      'linux': SelfUpdateInstaller.linuxSwapScript,
    }.entries) {
      test('${entry.key} script waits for the parent and bounds that wait', () {
        expect(entry.value, contains('kill -0 "\$PARENT"'));
        // Without a ceiling a wedged launcher would spin forever.
        expect(entry.value, contains('-ge 150'));
      });

      test('${entry.key} script never deletes the target before the swap', () {
        final swapIndex = entry.value.indexOf('mv "\$STAGED" "\$TARGET"');
        final firstTargetDelete = entry.value.indexOf('rm -rf "\$TARGET"');
        expect(swapIndex, greaterThan(0));
        expect(firstTargetDelete, greaterThan(swapIndex),
            reason: 'the only rm of the target belongs to the rollback path');
      });
    }

    test('macos script clears quarantine so Gatekeeper does not translocate',
        () {
      expect(SelfUpdateInstaller.macosSwapScript,
          contains('xattr -dr com.apple.quarantine'));
    });
  });
}
