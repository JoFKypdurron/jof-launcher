import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:joflauncher/models/asset.dart';
import 'package:joflauncher/services/cloud_service.dart';
import 'package:joflauncher/services/sync_manager.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

class TestCloudService extends CloudService {
  @override
  Future<void> downloadAndExtractLinuxFiles(
    String gameDataPath, {
    Function(String name, double progress)? onProgress,
    void Function(String status)? onStatus,
    bool Function()? isCancelled,
  }) async {
    // No-op for tests: real implementation downloads a zip over HTTP.
  }

  @override
  Future<void> downloadAndExtractMacosFiles(
    String gameDataPath, {
    Function(String name, double progress)? onProgress,
    void Function(String status)? onStatus,
    bool Function()? isCancelled,
  }) async {
    // No-op for tests: real implementation downloads a zip over HTTP.
  }

  @override
  Future<void> downloadAsset(
    Asset asset,
    String downloadDir, {
    Function(double)? onProgress,
    void Function(String status)? onStatus,
    bool Function()? isCancelled,
  }) async {
    final targetDir = Directory(p.join(downloadDir, asset.targetFolder));
    await targetDir.create(recursive: true);
    final file = File(p.join(targetDir.path, asset.name));
    await file.writeAsString('content');
    onProgress?.call(1.0);
  }

  @override
  Future<void> deleteAsset(Asset asset, String downloadDir) async {
    final file = File(p.join(downloadDir, asset.targetFolder, asset.name));
    if (await file.exists()) {
      await file.delete();
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('stages downloads while game is running and applies after close', () async {
    final tempRoot = await Directory.systemTemp.createTemp('jof_sync_test_');
    addTearDown(() async {
      try {
        await tempRoot.delete(recursive: true);
      } catch (_) {}
    });

    final gameDataPath = p.join(tempRoot.path, 'GameData');
    await Directory(gameDataPath).create(recursive: true);
    // Real installs always have either `GameData/base` or `GameData/Base`.
    // Staging should mirror that casing.
    await Directory(p.join(gameDataPath, 'Base')).create(recursive: true);

    final asset = Asset(
      id: 1,
      name: 'file.txt',
      size: 1,
      hash: 'h',
      groupId: 1,
      description: '',
      targetFolder: 'Base',
      localFolder: 'lf',
      lastUpdate: DateTime.now(),
    );

    final syncManager = SyncManager(TestCloudService());

    final statusUpdates = <int, AssetStatus>{};

    await syncManager.syncAssets(
      toDownload: [asset],
      toDelete: const [],
      gameDataPath: gameDataPath,
      isGameRunning: true,
      onProgress: (_, __) {},
      onStatusUpdate: (assetId, status) {
        statusUpdates[assetId] = status;
      },
    );

    expect(statusUpdates[asset.id], AssetStatus.stagedDownloaded);

    // Not written into the live GameData path while the game is running.
    expect(File(p.join(gameDataPath, 'Base', 'file.txt')).existsSync(), isFalse);

    // Written into staging next to GameData.
    final staged = File(p.join(tempRoot.path, '.jof_launcher_staging', 'content', 'Base', 'file.txt'));
    expect(staged.existsSync(), isTrue);

    await syncManager.applyStagedChanges(
      gameDataPath: gameDataPath,
      onProgress: (_, __) {},
    );

    expect(File(p.join(gameDataPath, 'Base', 'file.txt')).existsSync(), isTrue);
    expect(Directory(p.join(tempRoot.path, '.jof_launcher_staging')).existsSync(), isFalse);
  });
}
