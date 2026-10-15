import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:joflauncher/services/cloud_service.dart';
import 'package:path/path.dart' as p;

const _target = ClientTarget(
  platformName: 'Windows',
  version: '1.6.1',
  assetName: 'JoF-windows-x86_64.zip',
  sha256: 'abc123',
);

void main() {
  group('CloudService.archiveWrapperPrefix', () {
    // The published Windows zips wrap everything in a build-named folder.
    test('strips the folder the Windows zips are wrapped in', () {
      expect(
        CloudService.archiveWrapperPrefix([
          'JoF-master-windows-x86_64/',
          'JoF-master-windows-x86_64/GameData/',
          'JoF-master-windows-x86_64/GameData/eternaljk.x86_64.exe',
          'JoF-master-windows-x86_64/GameData/EternalJK/jofclient-assets.pk3',
        ]),
        'JoF-master-windows-x86_64/',
      );
    });

    // The Linux tarballs start directly at the install layout.
    test('leaves an archive with root-level files alone', () {
      expect(
        CloudService.archiveWrapperPrefix([
          'EternalJK/',
          'EternalJK/cgamex86_64.so',
          'eternaljk.x86_64',
        ]),
        '',
      );
    });

    test('never strips a folder that is part of the install layout', () {
      expect(
        CloudService.archiveWrapperPrefix(
            ['EternalJK/', 'EternalJK/cgamex86_64.so']),
        '',
      );
      expect(
        CloudService.archiveWrapperPrefix(['GameData/', 'GameData/a.exe']),
        '',
      );
    });

    test('leaves an archive with several top-level folders alone', () {
      expect(
        CloudService.archiveWrapperPrefix(['a/x', 'b/y']),
        '',
      );
    });
  });

  group('CloudService.clientMarkerMatches', () {
    Map<String, Object?> marker({
      String version = '1.6.1',
      String asset = 'JoF-windows-x86_64.zip',
      String? sha256 = 'abc123',
    }) =>
        {'version': version, 'asset': asset, 'sha256': sha256};

    test('matches the release it was written for', () {
      expect(CloudService.clientMarkerMatches(marker(), _target), isTrue);
    });

    test('a new version is out of date', () {
      expect(
          CloudService.clientMarkerMatches(marker(version: '1.6.0'), _target),
          isFalse);
    });

    // Switching architecture swaps the asset, e.g. x86 to x86_64.
    test('a different asset is out of date', () {
      expect(
          CloudService.clientMarkerMatches(
              marker(asset: 'JoF-windows-x86.zip'), _target),
          isFalse);
    });

    // A release re-uploaded under the same tag keeps the version but not the
    // digest.
    test('a changed digest is out of date', () {
      expect(CloudService.clientMarkerMatches(marker(sha256: 'def456'), _target),
          isFalse);
    });

    test('digest comparison ignores case', () {
      expect(CloudService.clientMarkerMatches(marker(sha256: 'ABC123'), _target),
          isTrue);
    });

    // A rate-limited GitHub API must not force a re-download.
    test('falls back to version and asset when a digest is missing', () {
      const noDigest = ClientTarget(
        platformName: 'Windows',
        version: '1.6.1',
        assetName: 'JoF-windows-x86_64.zip',
      );
      expect(CloudService.clientMarkerMatches(marker(), noDigest), isTrue);
      expect(CloudService.clientMarkerMatches(marker(sha256: null), _target),
          isTrue);
    });
  });

  group('CloudService.isClientUpToDate', () {
    late Directory root;

    setUp(() async {
      root = await Directory.systemTemp.createTemp('jof_client_marker_test_');
    });

    tearDown(() async {
      try {
        await root.delete(recursive: true);
      } catch (_) {}
    });

    Future<void> install(List<String> files, {List<String>? listed}) async {
      for (final file in files) {
        await File(p.join(root.path, file)).create(recursive: true);
      }
      await File(p.join(root.path, CloudService.clientMarkerFileName))
          .writeAsString(jsonEncode({
        'version': _target.version,
        'asset': _target.assetName,
        'sha256': _target.sha256,
        'files': listed ?? files,
      }));
    }

    final exe = 'eternaljk.x86_64.exe';
    final pk3 = p.join('EternalJK', 'jofclient-win-x86_64.pk3');

    test('is up to date when the marker matches and every file exists',
        () async {
      await install([exe, pk3]);
      expect(await CloudService().isClientUpToDate(root.path, _target), isTrue);
    });

    test('is out of date without a marker', () async {
      await File(p.join(root.path, exe)).create();
      expect(
          await CloudService().isClientUpToDate(root.path, _target), isFalse);
    });

    // E.g. an antivirus quarantined the exe.
    test('is out of date when an installed file has gone missing', () async {
      await install([pk3], listed: [exe, pk3]);
      expect(
          await CloudService().isClientUpToDate(root.path, _target), isFalse);
    });

    test('is out of date when the marker is corrupt', () async {
      await File(p.join(root.path, CloudService.clientMarkerFileName))
          .writeAsString('{not json');
      expect(
          await CloudService().isClientUpToDate(root.path, _target), isFalse);
    });
  });
}
