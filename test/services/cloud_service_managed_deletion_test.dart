import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:joflauncher/models/asset.dart';
import 'package:joflauncher/models/asset_group.dart';
import 'package:joflauncher/services/cloud_service.dart';

void main() {
  Asset _asset({
    required int id,
    required String name,
    required String targetFolder,
  }) {
    return Asset(
      id: id,
      name: name,
      size: 1,
      hash: 'x',
      groupId: 1,
      description: '',
      targetFolder: targetFolder,
      localFolder: '',
      lastUpdate: DateTime(2020, 1, 1),
    );
  }

  test('deleteAsset only deletes launcher-managed files and preserves user files', () async {
    final tempDir = await Directory.systemTemp.createTemp('jof_launcher_test_');
    addTearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    final gameDataPath = tempDir.path;
    final userFilePath = p.join(gameDataPath, 'EternalJK', 'user.cfg');
    final managedFilePath = p.join(gameDataPath, 'EternalJK', 'managed.bin');

    await File(userFilePath).create(recursive: true);
    await File(managedFilePath).create(recursive: true);

    final cloudService = CloudService();
    cloudService.setCachedCloudDataForTests(
      CloudData(
        clientGroups: [],
        modGroups: [],
        assetGroups: [
          AssetGroup(
            id: 1,
            name: 'Test',
            description: '',
            category: 'assetgroups',
            targetFolder: 'EternalJK',
            assets: [
              _asset(id: 1, name: 'managed.bin', targetFolder: 'EternalJK'),
            ],
          ),
        ],
        otherGroups: [],
      ),
    );

    await cloudService.deleteAsset(
      _asset(id: 1, name: 'managed.bin', targetFolder: 'EternalJK'),
      gameDataPath,
    );

    expect(await File(managedFilePath).exists(), isFalse);
    expect(await File(userFilePath).exists(), isTrue);
  });

  test('deleteAsset does not delete files that are not in the cloud manifest', () async {
    final tempDir = await Directory.systemTemp.createTemp('jof_launcher_test_');
    addTearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    final gameDataPath = tempDir.path;
    final userFilePath = p.join(gameDataPath, 'EternalJK', 'user.cfg');
    await File(userFilePath).create(recursive: true);

    final cloudService = CloudService();
    cloudService.setCachedCloudDataForTests(
      CloudData(
        clientGroups: [],
        modGroups: [],
        assetGroups: [
          AssetGroup(
            id: 1,
            name: 'Test',
            description: '',
            category: 'assetgroups',
            targetFolder: 'EternalJK',
            assets: [
              _asset(id: 1, name: 'managed.bin', targetFolder: 'EternalJK'),
            ],
          ),
        ],
        otherGroups: [],
      ),
    );

    await cloudService.deleteAsset(
      _asset(id: 2, name: 'user.cfg', targetFolder: 'EternalJK'),
      gameDataPath,
    );

    expect(await File(userFilePath).exists(), isTrue);
  });

  test('linux static managed allowlist matches expected file set', () {
    expect(CloudService.isStaticManagedLinuxClientRelativePath('eternaljk.x86_64'), isTrue);
    expect(CloudService.isStaticManagedLinuxClientRelativePath('EternalJK/data.db'), isTrue);
    expect(CloudService.isStaticManagedLinuxClientRelativePath('EternalJK/user.cfg'), isFalse);
  });
}
