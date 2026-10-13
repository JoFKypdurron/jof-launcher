import 'package:flutter_test/flutter_test.dart';
import 'package:joflauncher/models/asset.dart';
import 'package:joflauncher/services/asset_verification_service.dart';
import 'package:joflauncher/services/cloud_service.dart';
import 'package:joflauncher/services/sync_manager.dart';

class MockCloudService extends Fake implements CloudService {
  final Map<int, AssetStatus>? verificationResponses;
  int verificationCallCount = 0;
  int downloadCallCount = 0;
  int deleteCallCount = 0;
  final Duration? delay;

  MockCloudService({this.verificationResponses, this.delay});

  @override
  Future<AssetStatus> getAssetStatus(Asset asset, String downloadDir) async {
    verificationCallCount++;
    if (delay != null) {
      await Future.delayed(delay!);
    }
    return verificationResponses?[asset.id] ?? AssetStatus.notDownloaded;
  }

  @override
  Future<void> downloadAsset(
    Asset asset,
    String downloadDir, {
    Function(double)? onProgress,
    void Function(String status)? onStatus,
    bool Function()? isCancelled,
  }) async {
    downloadCallCount++;
    if (delay != null) {
      final steps = 5;
      for (int i = 0; i < steps; i++) {
        await Future.delayed(delay! ~/ steps);
        if (isCancelled != null && isCancelled()) {
          throw Exception('Download cancelled');
        }
        if (onProgress != null) onProgress((i + 1) / steps);
      }
    }
  }

  @override
  Future<void> deleteAsset(Asset asset, String downloadDir) async {
    deleteCallCount++;
    if (delay != null) {
      await Future.delayed(delay!);
    }
  }
}

void main() {
  late Asset asset1;
  late Asset asset2;
  late List<Asset> assets;

  setUp(() {
    asset1 = Asset(
      id: 1,
      name: 'asset1.zip',
      size: 1000,
      hash: 'hash1',
      groupId: 1,
      description: '',
      targetFolder: '',
      localFolder: '',
      lastUpdate: DateTime.now(),
    );
    asset2 = Asset(
      id: 2,
      name: 'asset2.zip',
      size: 2000,
      hash: 'hash2',
      groupId: 1,
      description: '',
      targetFolder: '',
      localFolder: '',
      lastUpdate: DateTime.now(),
    );
    assets = [asset1, asset2];
  });

  group('AssetVerificationService Cancellation', () {
    test('should stop and throw exception when cancelled', () async {
      final mockCloudService = MockCloudService(
        verificationResponses: {1: AssetStatus.downloaded, 2: AssetStatus.downloaded},
        delay: const Duration(milliseconds: 100),
      );
      final service = AssetVerificationService(mockCloudService);

      final verificationFuture = service.verifyAssets(assets, '/path');

      // Cancel after a short delay
      await Future.delayed(const Duration(milliseconds: 50));
      service.cancel();

      expect(verificationFuture, throwsA(predicate((e) => e.toString().contains('Verification cancelled'))));
    });
  });

  group('SyncManager Cancellation', () {
    test('should stop and throw exception when cancelled during delete', () async {
      final mockCloudService = MockCloudService(
        delay: const Duration(milliseconds: 100),
      );
      final syncManager = SyncManager(mockCloudService);

      final syncFuture = syncManager.syncAssets(
        toDownload: [asset1],
        toDelete: [asset2],
        gameDataPath: '/path',
        isGameRunning: false,
        onProgress: (_, __) {},
        onStatusUpdate: (_, __) {},
      );

      // Cancel during delete (first step)
      await Future.delayed(const Duration(milliseconds: 50));
      syncManager.cancel();

      expect(syncFuture, throwsA(predicate((e) => e.toString().contains('Sync cancelled'))));
      expect(mockCloudService.downloadCallCount, 0); // Should not have started download
    });

    test('should stop and throw exception when cancelled during download', () async {
      final mockCloudService = MockCloudService(
        delay: const Duration(milliseconds: 100),
      );
      final syncManager = SyncManager(mockCloudService);

      final syncFuture = syncManager.syncAssets(
        toDownload: [asset1],
        toDelete: [],
        gameDataPath: '/path',
        isGameRunning: false,
        onProgress: (_, __) {},
        onStatusUpdate: (_, __) {},
      );

      // Cancel during download
      await Future.delayed(const Duration(milliseconds: 50));
      syncManager.cancel();

      expect(syncFuture, throwsA(predicate((e) => e.toString().contains('Download cancelled'))));
    });
  });
}
