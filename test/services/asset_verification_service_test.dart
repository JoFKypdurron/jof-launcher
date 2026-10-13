import 'package:flutter_test/flutter_test.dart';
import 'package:joflauncher/models/asset.dart';
import 'package:joflauncher/services/asset_verification_service.dart';
import 'package:joflauncher/services/cloud_service.dart';

class MockCloudService extends Fake implements CloudService {
  final Map<int, AssetStatus> responses;
  int callCount = 0;
  final Duration? delay;

  MockCloudService(this.responses, {this.delay});

  @override
  Future<AssetStatus> getAssetStatus(Asset asset, String downloadDir) async {
    callCount++;
    if (delay != null) {
      await Future.delayed(delay!);
    }
    return responses[asset.id] ?? AssetStatus.notDownloaded;
  }
}

void main() {
  group('AssetVerificationService', () {
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

    test('verifyAssets should return statuses and report progress based on size', () async {
      final mockCloudService = MockCloudService({
        1: AssetStatus.downloaded,
        2: AssetStatus.needsUpdate,
      });
      final service = AssetVerificationService(mockCloudService);

      final progressValues = <double>[];
      final statuses = await service.verifyAssets(
        assets,
        '/path',
        onProgress: (p) => progressValues.add(p),
      );

      expect(statuses[1], AssetStatus.downloaded);
      expect(statuses[2], AssetStatus.needsUpdate);
      expect(mockCloudService.callCount, 2);
      
      // Total size = 3000. 
      // Since it sorts by size descending, asset2 (size 2000) is processed first.
      // Progress 1: 2000/3000 = 0.666...
      // Progress 2: 3000/3000 = 1.0
      expect(progressValues.length, 2);
      expect(progressValues[0], closeTo(0.666, 0.001));
      expect(progressValues[1], 1.0);
    });

    test('verifyAssets should handle duplicate assets', () async {
      final mockCloudService = MockCloudService({
        1: AssetStatus.downloaded,
      });
      final service = AssetVerificationService(mockCloudService);

      final progressValues = <double>[];
      final assetsWithDuplicates = [asset1, asset1, asset1];
      final statuses = await service.verifyAssets(
        assetsWithDuplicates,
        '/path',
        onProgress: (p) => progressValues.add(p),
      );

      expect(statuses[1], AssetStatus.downloaded);
      expect(mockCloudService.callCount, 1); // Should only call once for ID 1
      expect(progressValues.length, 1);
      expect(progressValues.last, 1.0);
    });

    test('verifyAssets should handle empty asset list', () async {
      final mockCloudService = MockCloudService({});
      final service = AssetVerificationService(mockCloudService);

      final progressValues = <double>[];
      final statuses = await service.verifyAssets(
        [],
        '/path',
        onProgress: (p) => progressValues.add(p),
      );

      expect(statuses, isEmpty);
      expect(progressValues, isEmpty);
    });
  });
}
