import 'package:flutter_test/flutter_test.dart';
import 'package:joflauncher/models/asset.dart';
import 'package:joflauncher/models/asset_group.dart';

void main() {
  group('AssetGroup', () {
    test('constructor creates asset group with all properties', () {
      final asset1 = Asset(
        id: 1,
        name: 'asset1.zip',
        size: 1024,
        hash: 'abc123',
        groupId: 10,
        description: 'Asset 1',
        targetFolder: 'target',
        localFolder: 'local',
        lastUpdate: DateTime.now(),
      );

      final asset2 = Asset(
        id: 2,
        name: 'asset2.zip',
        size: 2048,
        hash: 'def456',
        groupId: 10,
        description: 'Asset 2',
        targetFolder: 'target',
        localFolder: 'local',
        lastUpdate: DateTime.now(),
      );

      final group = AssetGroup(
        id: 10,
        name: 'Test Group',
        description: 'Test description',
        category: 'clientgroups',
        targetFolder: 'target',
        assets: [asset1, asset2],
        isRequired: true,
        dependsOn: 'modgroups 5',
      );

      expect(group.id, 10);
      expect(group.name, 'Test Group');
      expect(group.description, 'Test description');
      expect(group.category, 'clientgroups');
      expect(group.targetFolder, 'target');
      expect(group.assets, [asset1, asset2]);
      expect(group.isRequired, true);
      expect(group.dependsOn, 'modgroups 5');
    });

    test('constructor uses default values for optional parameters', () {
      final group = AssetGroup(
        id: 10,
        name: 'Test Group',
        description: 'Test description',
        category: 'clientgroups',
        targetFolder: 'target',
        assets: [],
      );

      expect(group.isRequired, false);
      expect(group.dependsOn, null);
    });

    group('fromJson', () {
      test('creates asset group from valid JSON with all fields', () {
        final json = {
          'id': 10,
          'name': 'Test Group',
          'description': 'Test description',
          'category': 'clientgroups',
          'targetfolder': 'target',
          'type': 'REQUIRED',
          'dependson': 'modgroups 5',
          'assets': [
            {
              'id': 1,
              'name': 'asset1.zip',
              'size': 1024,
              'hash': 'abc123',
              'groupid': 10,
              'description': 'Asset 1',
              'targetfolder': 'target',
              'localfolder': 'local',
              'lastupdate': '2024-01-01T00:00:00.000',
            },
            {
              'id': 2,
              'name': 'asset2.zip',
              'size': 2048,
              'hash': 'def456',
              'groupid': 10,
              'description': 'Asset 2',
              'targetfolder': 'target',
              'localfolder': 'local',
              'lastupdate': '2024-01-01T00:00:00.000',
            },
          ],
        };

        final group = AssetGroup.fromJson(json);

        expect(group.id, 10);
        expect(group.name, 'Test Group');
        expect(group.description, 'Test description');
        expect(group.category, 'clientgroups');
        expect(group.targetFolder, 'target');
        expect(group.isRequired, true);
        expect(group.dependsOn, 'modgroups 5');
        expect(group.paramstring, null);
        expect(group.assets.length, 2);
        expect(group.assets[0].id, 1);
        expect(group.assets[1].id, 2);
      });

      test('creates asset group from valid JSON with paramstring', () {
        final json = {
          'id': 10,
          'name': 'Test Group',
          'description': 'Test description',
          'category': 'modgroups',
          'targetfolder': 'target',
          'paramstring': '+set fs_game mod',
          'assets': [],
        };

        final group = AssetGroup.fromJson(json);

        expect(group.paramstring, '+set fs_game mod');
      });

      test('handles string numbers in JSON', () {
        final json = {
          'id': '10',
          'name': 'Test Group',
          'description': 'Test description',
          'category': 'clientgroups',
          'targetfolder': 'target',
          'assets': [],
        };

        final group = AssetGroup.fromJson(json);

        expect(group.id, 10);
      });

      test('handles missing fields with defaults', () {
        final json = {
          'id': 10,
        };

        final group = AssetGroup.fromJson(json);

        expect(group.id, 10);
        expect(group.name, '');
        expect(group.description, '');
        expect(group.category, '');
        expect(group.targetFolder, '');
        expect(group.isRequired, false);
        expect(group.dependsOn, null);
        expect(group.assets, isEmpty);
      });

      test('handles null values with defaults', () {
        final json = {
          'id': null,
          'name': null,
          'description': null,
          'category': null,
          'targetfolder': null,
          'type': null,
          'dependson': null,
          'assets': null,
        };

        final group = AssetGroup.fromJson(json);

        expect(group.id, 0);
        expect(group.name, '');
        expect(group.description, '');
        expect(group.category, '');
        expect(group.targetFolder, '');
        expect(group.isRequired, false);
        expect(group.dependsOn, null);
        expect(group.assets, isEmpty);
      });

      test('handles invalid number strings with defaults', () {
        final json = {
          'id': 'invalid',
          'name': 'Test Group',
          'description': 'Test description',
          'category': 'clientgroups',
          'targetfolder': 'target',
          'assets': [],
        };

        final group = AssetGroup.fromJson(json);

        expect(group.id, 0);
      });

      test('isRequired is true when type is REQUIRED', () {
        final json = {
          'id': 10,
          'name': 'Test Group',
          'description': 'Test description',
          'category': 'clientgroups',
          'targetfolder': 'target',
          'type': 'REQUIRED',
          'assets': [],
        };

        final group = AssetGroup.fromJson(json);

        expect(group.isRequired, true);
      });

      test('isRequired is false when type is not REQUIRED', () {
        final json = {
          'id': 10,
          'name': 'Test Group',
          'description': 'Test description',
          'category': 'clientgroups',
          'targetfolder': 'target',
          'type': 'OPTIONAL',
          'assets': [],
        };

        final group = AssetGroup.fromJson(json);

        expect(group.isRequired, false);
      });

      test('isRequired is false when type is missing', () {
        final json = {
          'id': 10,
          'name': 'Test Group',
          'description': 'Test description',
          'category': 'clientgroups',
          'targetfolder': 'target',
          'assets': [],
        };

        final group = AssetGroup.fromJson(json);

        expect(group.isRequired, false);
      });

      test('handles empty assets array', () {
        final json = {
          'id': 10,
          'name': 'Test Group',
          'description': 'Test description',
          'category': 'clientgroups',
          'targetfolder': 'target',
          'assets': [],
        };

        final group = AssetGroup.fromJson(json);

        expect(group.assets, isEmpty);
      });

      test('handles dependsOn as null', () {
        final json = {
          'id': 10,
          'name': 'Test Group',
          'description': 'Test description',
          'category': 'clientgroups',
          'targetfolder': 'target',
          'dependson': null,
          'assets': [],
        };

        final group = AssetGroup.fromJson(json);

        expect(group.dependsOn, null);
      });

      test('converts dependsOn to string', () {
        final json = {
          'id': 10,
          'name': 'Test Group',
          'description': 'Test description',
          'category': 'clientgroups',
          'targetfolder': 'target',
          'dependson': 123,
          'assets': [],
        };

        final group = AssetGroup.fromJson(json);

        expect(group.dependsOn, '123');
      });
    });
  });
}
