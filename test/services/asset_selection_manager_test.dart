import 'package:flutter_test/flutter_test.dart';
import 'package:joflauncher/models/asset.dart';
import 'package:joflauncher/models/asset_group.dart';
import 'package:joflauncher/services/asset_selection_manager.dart';
import 'package:joflauncher/services/cloud_service.dart';

void main() {
  group('AssetSelectionManager', () {
    late AssetSelectionManager manager;
    late Asset asset1;
    late Asset asset2;
    late Asset asset3;
    late AssetGroup group1;
    late AssetGroup group2;
    late AssetGroup requiredGroup;
    late CloudData cloudData;

    setUp(() {
      manager = AssetSelectionManager();

      asset1 = Asset(
        id: 1,
        name: 'asset1.zip',
        size: 1024,
        hash: 'abc123',
        groupId: 1,
        description: 'Asset 1',
        targetFolder: 'target',
        localFolder: 'local',
        lastUpdate: DateTime.now(),
      );

      asset2 = Asset(
        id: 2,
        name: 'asset2.zip',
        size: 2048,
        hash: 'def456',
        groupId: 2,
        description: 'Asset 2',
        targetFolder: 'target',
        localFolder: 'local',
        lastUpdate: DateTime.now(),
      );

      asset3 = Asset(
        id: 3,
        name: 'asset3.zip',
        size: 3072,
        hash: 'ghi789',
        groupId: 3,
        description: 'Asset 3',
        targetFolder: 'target',
        localFolder: 'local',
        lastUpdate: DateTime.now(),
      );

      group1 = AssetGroup(
        id: 1,
        name: 'Group 1',
        description: 'Group 1',
        category: 'modgroups',
        targetFolder: 'target',
        assets: [asset1],
      );

      group2 = AssetGroup(
        id: 2,
        name: 'Group 2',
        description: 'Group 2',
        category: 'modgroups',
        targetFolder: 'target',
        assets: [asset2],
        dependsOn: 'modgroups 1',
      );

      requiredGroup = AssetGroup(
        id: 3,
        name: 'Required Group',
        description: 'Required',
        category: 'clientgroups',
        targetFolder: 'target',
        assets: [asset3],
        isRequired: true,
      );

      cloudData = CloudData(
        clientGroups: [requiredGroup],
        modGroups: [group1, group2],
        assetGroups: [],
        otherGroups: [],
      );
    });

    test('initial state has empty selections', () {
      expect(manager.selectedAssets, isEmpty);
      expect(manager.effectiveRequiredGroups, isEmpty);
    });

    group('calculateEffectiveRequiredGroups', () {
      test('adds required groups to effectiveRequiredGroups', () {
        manager.calculateEffectiveRequiredGroups(cloudData);

        expect(manager.effectiveRequiredGroups, contains(requiredGroup));
      });

      test('includes dependencies of required groups', () {
        final requiredWithDep = AssetGroup(
          id: 4,
          name: 'Required with Dep',
          description: 'Required with dependency',
          category: 'clientgroups',
          targetFolder: 'target',
          assets: [],
          isRequired: true,
          dependsOn: 'modgroups 1',
        );

        final data = CloudData(
          clientGroups: [requiredWithDep],
          modGroups: [group1],
          assetGroups: [],
          otherGroups: [],
        );

        manager.calculateEffectiveRequiredGroups(data);

        expect(manager.effectiveRequiredGroups, contains(requiredWithDep));
        expect(manager.effectiveRequiredGroups, contains(group1));
      });

      test('clears previous effective required groups', () {
        manager.calculateEffectiveRequiredGroups(cloudData);
        expect(manager.effectiveRequiredGroups, isNotEmpty);

        final emptyData = CloudData(
          clientGroups: [],
          modGroups: [],
          assetGroups: [],
          otherGroups: [],
        );

        manager.calculateEffectiveRequiredGroups(emptyData);
        expect(manager.effectiveRequiredGroups, isEmpty);
      });
    });

    group('initializeSelections', () {
      test('selects all assets from required groups', () {
        manager.calculateEffectiveRequiredGroups(cloudData);
        manager.initializeSelections(
          data: cloudData,
          statuses: {
            1: AssetStatus.notDownloaded,
            2: AssetStatus.notDownloaded,
            3: AssetStatus.notDownloaded,
          },
          savedSelections: null,
        );

        expect(manager.selectedAssets, contains(asset3));
      });

      test('uses saved selections when provided', () {
        manager.calculateEffectiveRequiredGroups(cloudData);
        manager.initializeSelections(
          data: cloudData,
          statuses: {
            1: AssetStatus.notDownloaded,
            2: AssetStatus.notDownloaded,
            3: AssetStatus.notDownloaded,
          },
          savedSelections: [1, 2],
        );

        expect(manager.selectedAssets, contains(asset1));
        expect(manager.selectedAssets, contains(asset2));
        expect(manager.selectedAssets, contains(asset3)); // required
      });

      test('auto-selects downloaded files on first run', () {
        manager.calculateEffectiveRequiredGroups(cloudData);
        manager.initializeSelections(
          data: cloudData,
          statuses: {
            1: AssetStatus.downloaded,
            2: AssetStatus.needsUpdate,
            3: AssetStatus.notDownloaded,
          },
          savedSelections: null,
        );

        expect(manager.selectedAssets, contains(asset1));
        expect(manager.selectedAssets, contains(asset2));
        expect(manager.selectedAssets, contains(asset3)); // required
      });

      test('resolves dependencies for selected assets', () {
        manager.calculateEffectiveRequiredGroups(cloudData);
        manager.initializeSelections(
          data: cloudData,
          statuses: {
            1: AssetStatus.notDownloaded,
            2: AssetStatus.notDownloaded,
            3: AssetStatus.notDownloaded,
          },
          savedSelections: [2], // group2 depends on group1
        );

        expect(manager.selectedAssets, contains(asset1)); // dependency
        expect(manager.selectedAssets, contains(asset2));
        expect(manager.selectedAssets, contains(asset3)); // required
      });

      test('clears previous selections', () {
        manager.selectedAssets.add(asset1);
        manager.calculateEffectiveRequiredGroups(cloudData);
        manager.initializeSelections(
          data: cloudData,
          statuses: {3: AssetStatus.notDownloaded},
          savedSelections: null,
        );

        expect(manager.selectedAssets, contains(asset3));
        expect(manager.selectedAssets.length, 1);
      });

      test('selects all assets from saved selected groups (including newly added assets)', () {
        manager.calculateEffectiveRequiredGroups(cloudData);

        final newAssetInGroup1 = Asset(
          id: 10,
          name: 'asset10.zip',
          size: 1024,
          hash: 'zzz999',
          groupId: 1,
          description: 'New Asset in Group 1',
          targetFolder: 'target',
          localFolder: 'local',
          lastUpdate: DateTime.now(),
        );

        final updatedGroup1 = AssetGroup(
          id: 1,
          name: 'Group 1',
          description: 'Group 1',
          category: 'modgroups',
          targetFolder: 'target',
          assets: [asset1, newAssetInGroup1],
        );

        final updatedCloudData = CloudData(
          clientGroups: [requiredGroup],
          modGroups: [updatedGroup1, group2],
          assetGroups: [],
          otherGroups: [],
        );

        manager.initializeSelections(
          data: updatedCloudData,
          statuses: {
            1: AssetStatus.notDownloaded,
            2: AssetStatus.notDownloaded,
            3: AssetStatus.notDownloaded,
            10: AssetStatus.notDownloaded,
          },
          savedSelections: const [],
          savedSelectedGroupIds: [1],
        );

        expect(manager.selectedAssets, contains(asset1));
        expect(manager.selectedAssets, contains(newAssetInGroup1));
        expect(manager.selectedAssets, contains(asset3)); // required
        expect(manager.selectedGroupIds, contains(1));
      });
    });

    group('toggleAsset', () {
      setUp(() {
        manager.calculateEffectiveRequiredGroups(cloudData);
      });

      test('adds asset when not selected', () {
        manager.toggleAsset(asset1, group1, cloudData);

        expect(manager.selectedAssets, contains(asset1));
      });

      test('removes asset when selected', () {
        manager.selectedAssets.add(asset1);
        manager.toggleAsset(asset1, group1, cloudData);

        expect(manager.selectedAssets, isNot(contains(asset1)));
      });

      test('adds dependencies when selecting asset', () {
        manager.toggleAsset(asset2, group2, cloudData);

        expect(manager.selectedAssets, contains(asset2));
        expect(manager.selectedAssets, contains(asset1)); // dependency
      });

      test('cannot deselect asset from required group', () {
        manager.selectedAssets.add(asset3);
        manager.toggleAsset(asset3, requiredGroup, cloudData);

        expect(manager.selectedAssets, contains(asset3));
      });

      test('can select asset from required group', () {
        manager.toggleAsset(asset3, requiredGroup, cloudData);

        expect(manager.selectedAssets, contains(asset3));
      });

      test('deselecting an asset breaks saved group selection', () {
        manager.selectedGroupIds.add(group1.id);
        manager.selectedAssets.add(asset1);

        manager.toggleAsset(asset1, group1, cloudData);

        expect(manager.selectedAssets, isNot(contains(asset1)));
        expect(manager.selectedGroupIds, isNot(contains(group1.id)));
      });
    });

    group('toggleGroup', () {
      setUp(() {
        manager.calculateEffectiveRequiredGroups(cloudData);
      });

      test('selects all assets in group when select is true', () {
        manager.toggleGroup(group1, true, cloudData);

        expect(manager.selectedAssets, contains(asset1));
      });

      test('deselects all assets in group when select is false', () {
        manager.selectedAssets.add(asset1);
        manager.toggleGroup(group1, false, cloudData);

        expect(manager.selectedAssets, isNot(contains(asset1)));
      });

      test('adds dependencies when selecting group', () {
        manager.toggleGroup(group2, true, cloudData);

        expect(manager.selectedAssets, contains(asset2));
        expect(manager.selectedAssets, contains(asset1)); // dependency
      });

      test('cannot deselect required group', () {
        manager.selectedAssets.add(asset3);
        manager.toggleGroup(requiredGroup, false, cloudData);

        expect(manager.selectedAssets, contains(asset3));
      });

      test('can select required group', () {
        manager.toggleGroup(requiredGroup, true, cloudData);

        expect(manager.selectedAssets, contains(asset3));
      });
    });

    group('getPendingChanges', () {
      setUp(() {
        manager.calculateEffectiveRequiredGroups(cloudData);
      });

      test('returns 0 for both when no changes needed', () {
        manager.selectedAssets.add(asset1);
        final statuses = {
          1: AssetStatus.downloaded,
          2: AssetStatus.notDownloaded,
          3: AssetStatus.notDownloaded,
        };

        final changes = manager.getPendingChanges(cloudData, statuses);

        expect(changes.downloads, 0);
        expect(changes.removals, 0);
      });

      test('separates downloads and removals', () {
        manager.selectedAssets.add(asset1);
        final statuses = {
          1: AssetStatus.notDownloaded, // needs download
          2: AssetStatus.downloaded, // needs delete
          3: AssetStatus.notDownloaded,
        };

        final changes = manager.getPendingChanges(cloudData, statuses);

        expect(changes.downloads, 1);
        expect(changes.removals, 1);
      });

      test('does not count staged downloads/removals as pending changes', () {
        manager.selectedAssets.add(asset1);
        final statuses = {
          1: AssetStatus.stagedDownloaded,
          2: AssetStatus.stagedForRemoval,
          3: AssetStatus.notDownloaded,
        };

        final changes = manager.getPendingChanges(cloudData, statuses);

        expect(changes.downloads, 0);
        expect(changes.removals, 0);
      });
    });

    group('getPendingChangesCount', () {
      setUp(() {
        manager.calculateEffectiveRequiredGroups(cloudData);
      });

      test('returns 0 when no changes needed', () {
        manager.selectedAssets.add(asset1);
        final statuses = {
          1: AssetStatus.downloaded,
          2: AssetStatus.notDownloaded,
          3: AssetStatus.notDownloaded,
        };

        final count = manager.getPendingChangesCount(cloudData, statuses);

        expect(count, 0);
      });

      test('counts assets to download', () {
        manager.selectedAssets.add(asset1);
        manager.selectedAssets.add(asset2);
        final statuses = {
          1: AssetStatus.notDownloaded,
          2: AssetStatus.needsUpdate,
          3: AssetStatus.notDownloaded,
        };

        final count = manager.getPendingChangesCount(cloudData, statuses);

        expect(count, 2);
      });

      test('counts assets to delete', () {
        final statuses = {
          1: AssetStatus.downloaded,
          2: AssetStatus.downloaded,
          3: AssetStatus.notDownloaded,
        };

        final count = manager.getPendingChangesCount(cloudData, statuses);

        expect(count, 2);
      });

      test('counts both downloads and deletes', () {
        manager.selectedAssets.add(asset1);
        final statuses = {
          1: AssetStatus.notDownloaded, // needs download
          2: AssetStatus.downloaded, // needs delete
          3: AssetStatus.notDownloaded,
        };

        final count = manager.getPendingChangesCount(cloudData, statuses);

        expect(count, 2);
      });

      test('ignores assets with null status', () {
        manager.selectedAssets.add(asset1);
        final statuses = <int, AssetStatus>{
          2: AssetStatus.downloaded,
        };

        final count = manager.getPendingChangesCount(cloudData, statuses);

        expect(count, 1); // only asset2 needs delete
      });
    });

    group('getSelectedAssetIds', () {
      test('returns empty list when no selections', () {
        final ids = manager.getSelectedAssetIds();

        expect(ids, isEmpty);
      });

      test('returns list of selected asset ids', () {
        manager.selectedAssets.add(asset1);
        manager.selectedAssets.add(asset2);

        final ids = manager.getSelectedAssetIds();

        expect(ids, containsAll([1, 2]));
        expect(ids.length, 2);
      });

      test('returns ids in consistent order', () {
        manager.selectedAssets.add(asset1);
        manager.selectedAssets.add(asset2);
        manager.selectedAssets.add(asset3);

        final ids = manager.getSelectedAssetIds();

        expect(ids.length, 3);
        expect(ids, contains(1));
        expect(ids, contains(2));
        expect(ids, contains(3));
      });
    });

    group('complex dependency scenarios', () {
      test('resolves transitive dependencies on initialization', () {
        final asset4 = Asset(
          id: 4,
          name: 'asset4.zip',
          size: 4096,
          hash: 'jkl012',
          groupId: 4,
          description: 'Asset 4',
          targetFolder: 'target',
          localFolder: 'local',
          lastUpdate: DateTime.now(),
        );

        final group3 = AssetGroup(
          id: 4,
          name: 'Group 3',
          description: 'Group 3',
          category: 'modgroups',
          targetFolder: 'target',
          assets: [asset4],
          dependsOn: 'modgroups 2', // depends on group2, which depends on group1
        );

        final data = CloudData(
          clientGroups: [],
          modGroups: [group1, group2, group3],
          assetGroups: [],
          otherGroups: [],
        );

        manager.calculateEffectiveRequiredGroups(data);
        manager.initializeSelections(
          data: data,
          statuses: {
            1: AssetStatus.notDownloaded,
            2: AssetStatus.notDownloaded,
            4: AssetStatus.notDownloaded,
          },
          savedSelections: [4], // select group3
        );

        expect(manager.selectedAssets, contains(asset4));
        expect(manager.selectedAssets, contains(asset2)); // group2
        expect(manager.selectedAssets, contains(asset1)); // group1
      });

      test('handles multiple groups with same dependency', () {
        final asset4 = Asset(
          id: 4,
          name: 'asset4.zip',
          size: 4096,
          hash: 'jkl012',
          groupId: 4,
          description: 'Asset 4',
          targetFolder: 'target',
          localFolder: 'local',
          lastUpdate: DateTime.now(),
        );

        final group3 = AssetGroup(
          id: 4,
          name: 'Group 3',
          description: 'Group 3',
          category: 'modgroups',
          targetFolder: 'target',
          assets: [asset4],
          dependsOn: 'modgroups 1', // also depends on group1
        );

        final data = CloudData(
          clientGroups: [],
          modGroups: [group1, group2, group3],
          assetGroups: [],
          otherGroups: [],
        );

        manager.calculateEffectiveRequiredGroups(data);
        manager.initializeSelections(
          data: data,
          statuses: {
            1: AssetStatus.notDownloaded,
            2: AssetStatus.notDownloaded,
            4: AssetStatus.notDownloaded,
          },
          savedSelections: [2, 4], // select both group2 and group3
        );

        expect(manager.selectedAssets, contains(asset1)); // shared dependency
        expect(manager.selectedAssets, contains(asset2));
        expect(manager.selectedAssets, contains(asset4));
        expect(manager.selectedAssets.length, 3);
      });
    });
  });
}
