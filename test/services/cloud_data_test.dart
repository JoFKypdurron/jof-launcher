import 'package:flutter_test/flutter_test.dart';
import 'package:joflauncher/models/asset.dart';
import 'package:joflauncher/models/asset_group.dart';
import 'package:joflauncher/services/cloud_service.dart';

void main() {
  group('CloudData', () {
    late Asset asset1;
    late Asset asset2;
    late Asset asset3;
    late AssetGroup clientGroup;
    late AssetGroup modGroup;
    late AssetGroup assetGroup;
    late AssetGroup otherGroup;

    setUp(() {
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

      clientGroup = AssetGroup(
        id: 1,
        name: 'Client Group',
        description: 'Client',
        category: 'clientgroups',
        targetFolder: 'target',
        assets: [asset1],
      );

      modGroup = AssetGroup(
        id: 2,
        name: 'Mod Group',
        description: 'Mod',
        category: 'modgroups',
        targetFolder: 'target',
        assets: [asset2],
      );

      assetGroup = AssetGroup(
        id: 3,
        name: 'Asset Group',
        description: 'Asset',
        category: 'assetgroups',
        targetFolder: 'target',
        assets: [asset3],
      );

      otherGroup = AssetGroup(
        id: 4,
        name: 'Other Group',
        description: 'Other',
        category: 'othergroups',
        targetFolder: 'target',
        assets: [],
      );
    });

    test('constructor creates CloudData with all group types', () {
      final cloudData = CloudData(
        clientGroups: [clientGroup],
        modGroups: [modGroup],
        assetGroups: [assetGroup],
        otherGroups: [otherGroup],
      );

      expect(cloudData.clientGroups, [clientGroup]);
      expect(cloudData.modGroups, [modGroup]);
      expect(cloudData.assetGroups, [assetGroup]);
      expect(cloudData.otherGroups, [otherGroup]);
    });

    test('allGroups returns all groups in correct order', () {
      final cloudData = CloudData(
        clientGroups: [clientGroup],
        modGroups: [modGroup],
        assetGroups: [assetGroup],
        otherGroups: [otherGroup],
      );

      final allGroups = cloudData.allGroups;

      expect(allGroups.length, 4);
      expect(allGroups[0], clientGroup);
      expect(allGroups[1], modGroup);
      expect(allGroups[2], assetGroup);
      expect(allGroups[3], otherGroup);
    });

    test('allGroups handles empty lists', () {
      final cloudData = CloudData(
        clientGroups: [],
        modGroups: [],
        assetGroups: [],
        otherGroups: [],
      );

      expect(cloudData.allGroups, isEmpty);
    });

    group('findGroup', () {
      late CloudData cloudData;

      setUp(() {
        cloudData = CloudData(
          clientGroups: [clientGroup],
          modGroups: [modGroup],
          assetGroups: [assetGroup],
          otherGroups: [otherGroup],
        );
      });

      test('finds group in clientgroups by category and id', () {
        final found = cloudData.findGroup('clientgroups', 1);
        expect(found, clientGroup);
      });

      test('finds group in modgroups by category and id', () {
        final found = cloudData.findGroup('modgroups', 2);
        expect(found, modGroup);
      });

      test('finds group in assetgroups by category and id', () {
        final found = cloudData.findGroup('assetgroups', 3);
        expect(found, assetGroup);
      });

      test('finds group in othergroups by category and id', () {
        final found = cloudData.findGroup('othergroups', 4);
        expect(found, otherGroup);
      });

      test('handles case-insensitive category names', () {
        final found = cloudData.findGroup('CLIENTGROUPS', 1);
        expect(found, clientGroup);
      });

      test('falls back to searching all groups if not found in category', () {
        final found = cloudData.findGroup('modgroups', 1);
        expect(found, clientGroup);
      });

      test('returns null if group not found', () {
        final found = cloudData.findGroup('clientgroups', 999);
        expect(found, null);
      });

      test('searches all groups when category is unknown', () {
        final found = cloudData.findGroup('unknown', 2);
        expect(found, modGroup);
      });

      test('returns null when searching unknown category and id not found', () {
        final found = cloudData.findGroup('unknown', 999);
        expect(found, null);
      });
    });

    group('resolveDependencies', () {
      test('returns only the group when no dependencies', () {
        final cloudData = CloudData(
          clientGroups: [clientGroup],
          modGroups: [],
          assetGroups: [],
          otherGroups: [],
        );

        final resolved = cloudData.resolveDependencies(clientGroup);

        expect(resolved, {clientGroup});
      });

      test('resolves single dependency with category and id', () {
        final dependentGroup = AssetGroup(
          id: 5,
          name: 'Dependent Group',
          description: 'Depends on mod group',
          category: 'clientgroups',
          targetFolder: 'target',
          assets: [],
          dependsOn: 'modgroups 2',
        );

        final cloudData = CloudData(
          clientGroups: [dependentGroup],
          modGroups: [modGroup],
          assetGroups: [],
          otherGroups: [],
        );

        final resolved = cloudData.resolveDependencies(dependentGroup);

        expect(resolved, {dependentGroup, modGroup});
      });

      test('resolves dependency with just id', () {
        final dependentGroup = AssetGroup(
          id: 5,
          name: 'Dependent Group',
          description: 'Depends on mod group',
          category: 'clientgroups',
          targetFolder: 'target',
          assets: [],
          dependsOn: '2',
        );

        final cloudData = CloudData(
          clientGroups: [dependentGroup],
          modGroups: [modGroup],
          assetGroups: [],
          otherGroups: [],
        );

        final resolved = cloudData.resolveDependencies(dependentGroup);

        expect(resolved, {dependentGroup, modGroup});
      });

      test('resolves dependency with category id format', () {
        final dependentGroup = AssetGroup(
          id: 5,
          name: 'Dependent Group',
          description: 'Depends on mod group',
          category: 'clientgroups',
          targetFolder: 'target',
          assets: [],
          dependsOn: 'modgroups id 2',
        );

        final cloudData = CloudData(
          clientGroups: [dependentGroup],
          modGroups: [modGroup],
          assetGroups: [],
          otherGroups: [],
        );

        final resolved = cloudData.resolveDependencies(dependentGroup);

        expect(resolved, {dependentGroup, modGroup});
      });

      test('resolves chain of dependencies', () {
        final group1 = AssetGroup(
          id: 1,
          name: 'Group 1',
          description: 'Base group',
          category: 'modgroups',
          targetFolder: 'target',
          assets: [],
        );

        final group2 = AssetGroup(
          id: 2,
          name: 'Group 2',
          description: 'Depends on Group 1',
          category: 'modgroups',
          targetFolder: 'target',
          assets: [],
          dependsOn: 'modgroups 1',
        );

        final group3 = AssetGroup(
          id: 3,
          name: 'Group 3',
          description: 'Depends on Group 2',
          category: 'clientgroups',
          targetFolder: 'target',
          assets: [],
          dependsOn: 'modgroups 2',
        );

        final cloudData = CloudData(
          clientGroups: [group3],
          modGroups: [group1, group2],
          assetGroups: [],
          otherGroups: [],
        );

        final resolved = cloudData.resolveDependencies(group3);

        expect(resolved, {group3, group2, group1});
      });

      test('handles circular dependencies without infinite loop', () {
        final group1 = AssetGroup(
          id: 1,
          name: 'Group 1',
          description: 'Depends on Group 2',
          category: 'modgroups',
          targetFolder: 'target',
          assets: [],
          dependsOn: 'modgroups 2',
        );

        final group2 = AssetGroup(
          id: 2,
          name: 'Group 2',
          description: 'Depends on Group 1',
          category: 'modgroups',
          targetFolder: 'target',
          assets: [],
          dependsOn: 'modgroups 1',
        );

        final cloudData = CloudData(
          clientGroups: [],
          modGroups: [group1, group2],
          assetGroups: [],
          otherGroups: [],
        );

        final resolved = cloudData.resolveDependencies(group1);

        expect(resolved, {group1, group2});
      });

      test('handles missing dependency gracefully', () {
        final dependentGroup = AssetGroup(
          id: 5,
          name: 'Dependent Group',
          description: 'Depends on non-existent group',
          category: 'clientgroups',
          targetFolder: 'target',
          assets: [],
          dependsOn: 'modgroups 999',
        );

        final cloudData = CloudData(
          clientGroups: [dependentGroup],
          modGroups: [],
          assetGroups: [],
          otherGroups: [],
        );

        final resolved = cloudData.resolveDependencies(dependentGroup);

        expect(resolved, {dependentGroup});
      });

      test('handles empty dependsOn string', () {
        final dependentGroup = AssetGroup(
          id: 5,
          name: 'Dependent Group',
          description: 'Empty dependency',
          category: 'clientgroups',
          targetFolder: 'target',
          assets: [],
          dependsOn: '',
        );

        final cloudData = CloudData(
          clientGroups: [dependentGroup],
          modGroups: [],
          assetGroups: [],
          otherGroups: [],
        );

        final resolved = cloudData.resolveDependencies(dependentGroup);

        expect(resolved, {dependentGroup});
      });

      test('handles invalid dependency format', () {
        final dependentGroup = AssetGroup(
          id: 5,
          name: 'Dependent Group',
          description: 'Invalid dependency',
          category: 'clientgroups',
          targetFolder: 'target',
          assets: [],
          dependsOn: 'invalid format',
        );

        final cloudData = CloudData(
          clientGroups: [dependentGroup],
          modGroups: [],
          assetGroups: [],
          otherGroups: [],
        );

        final resolved = cloudData.resolveDependencies(dependentGroup);

        expect(resolved, {dependentGroup});
      });
    });
  });
}
