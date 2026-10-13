import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:joflauncher/models/asset.dart';
import 'package:joflauncher/services/cloud_service.dart';
import 'package:joflauncher/services/sync_manager.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

class QueueTestCloudService extends CloudService {
  @override
  Future<void> downloadAndExtractLinuxFiles(
    String gameDataPath, {
    Function(String name, double progress)? onProgress,
    void Function(String status)? onStatus,
    bool Function()? isCancelled,
  }) async {
    // No-op for tests: real implementation downloads an archive over HTTP.
  }

  @override
  Future<void> downloadAndExtractMacosFiles(
    String gameDataPath, {
    Function(String name, double progress)? onProgress,
    void Function(String status)? onStatus,
    bool Function()? isCancelled,
  }) async {
    // No-op for tests: real implementation downloads an archive over HTTP.
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
    await File(p.join(targetDir.path, asset.name)).writeAsString('content');
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

Asset _asset(int id, String name) => Asset(
      id: id,
      name: name,
      size: 1,
      hash: 'h$id',
      groupId: 1,
      description: '',
      targetFolder: 'Base',
      localFolder: 'lf',
      lastUpdate: DateTime.now(),
    );

/// The platform client files are one extra queued step on Linux and macOS.
final int _platformStep = (Platform.isLinux || Platform.isMacOS) ? 1 : 0;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Future<String> createGameData() async {
    final tempRoot = await Directory.systemTemp.createTemp('jof_queue_test_');
    addTearDown(() async {
      try {
        await tempRoot.delete(recursive: true);
      } catch (_) {}
    });
    final gameDataPath = p.join(tempRoot.path, 'GameData');
    await Directory(p.join(gameDataPath, 'Base')).create(recursive: true);
    return gameDataPath;
  }

  test('reports queue position for each downloaded and removed asset', () async {
    final gameDataPath = await createGameData();
    final removed = _asset(1, 'old.pk3');
    await File(p.join(gameDataPath, 'Base', removed.name)).writeAsString('x');

    final queue = <List<int>>[];

    await SyncManager(QueueTestCloudService()).syncAssets(
      toDownload: [_asset(2, 'a.pk3'), _asset(3, 'b.pk3')],
      toDelete: [removed],
      gameDataPath: gameDataPath,
      isGameRunning: false,
      onProgress: (_, __) {},
      onStatusUpdate: (_, __) {},
      onQueueProgress: (completed, total) => queue.add([completed, total]),
    );

    final total = 3 + _platformStep;
    expect(queue.first, [0, total]);
    expect(queue.last, [total, total]);
    // One report per item, plus the initial 0.
    expect(queue, hasLength(total + 1));
    expect(queue.map((e) => e[0]), List.generate(total + 1, (i) => i));
  });

  test('reports queue position while staging for a running game', () async {
    final gameDataPath = await createGameData();

    final queue = <List<int>>[];

    await SyncManager(QueueTestCloudService()).syncAssets(
      toDownload: [_asset(2, 'a.pk3')],
      toDelete: const [],
      gameDataPath: gameDataPath,
      isGameRunning: true,
      onProgress: (_, __) {},
      onStatusUpdate: (_, __) {},
      onQueueProgress: (completed, total) => queue.add([completed, total]),
    );

    final total = 1 + _platformStep;
    expect(queue.first, [0, total]);
    expect(queue.last, [total, total]);
  });
}
