import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:joflauncher/models/asset.dart';
import 'package:joflauncher/services/cloud_service.dart';
import 'package:joflauncher/services/sync_manager.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

/// Downloads that finish only when the test completes them.
class GatedCloudService extends CloudService {
  final gates = <String, Completer<void>>{};
  final started = <String>[];
  final progressCallbacks = <String, Function(double)>{};
  int inFlight = 0;
  int maxInFlight = 0;

  /// Completes the next time a download starts.
  Completer<void> nextStart = Completer<void>();

  @override
  Future<void> syncClientFiles(
    String installRoot, {
    String? currentInstallPath,
    Function(String name, double progress)? onProgress,
    void Function(String status)? onStatus,
    bool Function()? isCancelled,
  }) async {}

  @override
  Future<void> downloadAsset(
    Asset asset,
    String downloadDir, {
    Function(double)? onProgress,
    void Function(String status)? onStatus,
    bool Function()? isCancelled,
  }) async {
    started.add(asset.name);
    progressCallbacks[asset.name] = onProgress ?? (_) {};
    inFlight++;
    if (inFlight > maxInFlight) maxInFlight = inFlight;
    final gate = gates[asset.name] = Completer<void>();
    final start = nextStart;
    nextStart = Completer<void>();
    start.complete();
    try {
      // Polls for cancellation like the real download loop does per chunk.
      while (!gate.isCompleted) {
        if (isCancelled?.call() ?? false) {
          throw Exception('Download cancelled');
        }
        await Future.any([gate.future, Future.delayed(const Duration(milliseconds: 5))]);
      }
      await gate.future;
      onProgress?.call(1.0);
    } finally {
      inFlight--;
    }
  }

  Future<void> waitForStarts(int count) async {
    while (started.length < count) {
      await nextStart.future;
    }
  }
}

Asset _asset(int id, String name, int size) => Asset(
      id: id,
      name: name,
      size: size,
      hash: 'h$id',
      groupId: 1,
      description: '',
      targetFolder: 'Base',
      localFolder: 'lf',
      lastUpdate: DateTime.now(),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Future<String> createGameData() async {
    final tempRoot = await Directory.systemTemp.createTemp('jof_parallel_test_');
    addTearDown(() async {
      try {
        await tempRoot.delete(recursive: true);
      } catch (_) {}
    });
    final gameDataPath = p.join(tempRoot.path, 'GameData');
    await Directory(p.join(gameDataPath, 'Base')).create(recursive: true);
    return gameDataPath;
  }

  test('downloads several assets at once, largest first, up to the limit', () async {
    final gameDataPath = await createGameData();
    final cloud = GatedCloudService();
    final assets = [
      for (var i = 1; i <= 5; i++) _asset(i, 'f$i.pk3', i * 100),
    ];

    final sync = SyncManager(cloud, downloadConcurrency: 3).syncAssets(
      toDownload: assets,
      toDelete: const [],
      gameDataPath: gameDataPath,
      isGameRunning: false,
      onProgress: (_, _) {},
      onStatusUpdate: (_, _) {},
    );

    await cloud.waitForStarts(3);
    expect(cloud.started, ['f5.pk3', 'f4.pk3', 'f3.pk3']);
    expect(cloud.inFlight, 3);

    cloud.gates['f4.pk3']!.complete();
    await cloud.waitForStarts(4);
    expect(cloud.started.last, 'f2.pk3');

    for (final name in ['f5.pk3', 'f3.pk3', 'f2.pk3']) {
      cloud.gates[name]!.complete();
    }
    await cloud.waitForStarts(5);
    cloud.gates['f1.pk3']!.complete();
    await sync;

    expect(cloud.maxInFlight, 3);
  });

  test('a failed download stops the others and is rethrown', () async {
    final gameDataPath = await createGameData();
    final cloud = GatedCloudService();
    final assets = [
      for (var i = 1; i <= 4; i++) _asset(i, 'f$i.pk3', 100),
    ];

    final sync = SyncManager(cloud, downloadConcurrency: 2).syncAssets(
      toDownload: assets,
      toDelete: const [],
      gameDataPath: gameDataPath,
      isGameRunning: false,
      onProgress: (_, _) {},
      onStatusUpdate: (_, _) {},
    );

    await cloud.waitForStarts(2);
    cloud.gates[cloud.started.first]!.completeError(Exception('HTTP 404'));

    await expectLater(sync, throwsA(predicate((e) => e.toString().contains('HTTP 404'))));
    expect(cloud.started, hasLength(2), reason: 'no new download after a failure');
    expect(cloud.inFlight, 0);
  });

  test('reports progress weighted by size across parallel downloads', () async {
    final gameDataPath = await createGameData();
    final cloud = GatedCloudService();
    final reports = <(String, double)>[];

    final sync = SyncManager(cloud, downloadConcurrency: 2).syncAssets(
      toDownload: [_asset(1, 'big.pk3', 300), _asset(2, 'small.pk3', 100)],
      toDelete: const [],
      gameDataPath: gameDataPath,
      isGameRunning: false,
      onProgress: (name, progress) => reports.add((name, progress)),
      onStatusUpdate: (_, _) {},
    );

    await cloud.waitForStarts(2);
    expect(reports.last, ('big.pk3 and 1 more', 0.0));

    cloud.gates['small.pk3']!.complete();
    // Completion is reported without waiting out the throttle interval.
    await Future.doWhile(() async {
      await Future.delayed(const Duration(milliseconds: 1));
      return reports.last.$2 == 0.0;
    });
    expect(reports.last, ('big.pk3', 0.25));

    cloud.gates['big.pk3']!.complete();
    await sync;
    expect(reports.last, ('big.pk3', 1.0));
  });
}
