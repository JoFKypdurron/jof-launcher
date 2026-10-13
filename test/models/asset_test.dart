import 'package:flutter_test/flutter_test.dart';
import 'package:joflauncher/models/asset.dart';

void main() {
  group('Asset', () {
    test('constructor creates asset with all properties', () {
      final lastUpdate = DateTime(2024, 1, 1);
      final asset = Asset(
        id: 1,
        name: 'test.zip',
        size: 1024,
        hash: 'abc123',
        groupId: 10,
        description: 'Test asset',
        targetFolder: 'target',
        localFolder: 'local',
        lastUpdate: lastUpdate,
      );

      expect(asset.id, 1);
      expect(asset.name, 'test.zip');
      expect(asset.size, 1024);
      expect(asset.hash, 'abc123');
      expect(asset.groupId, 10);
      expect(asset.description, 'Test asset');
      expect(asset.targetFolder, 'target');
      expect(asset.localFolder, 'local');
      expect(asset.lastUpdate, lastUpdate);
    });

    group('fromJson', () {
      test('creates asset from valid JSON with all fields', () {
        final json = {
          'id': 1,
          'name': 'test.zip',
          'size': 1024,
          'hash': 'abc123',
          'groupid': 10,
          'description': 'Test asset',
          'targetfolder': 'target',
          'localfolder': 'local',
          'lastupdate': '2024-01-01T00:00:00.000',
        };

        final asset = Asset.fromJson(json);

        expect(asset.id, 1);
        expect(asset.name, 'test.zip');
        expect(asset.size, 1024);
        expect(asset.hash, 'abc123');
        expect(asset.groupId, 10);
        expect(asset.description, 'Test asset');
        expect(asset.targetFolder, 'target');
        expect(asset.localFolder, 'local');
        expect(asset.lastUpdate, DateTime.parse('2024-01-01T00:00:00.000'));
      });

      test('handles string numbers in JSON', () {
        final json = {
          'id': '1',
          'name': 'test.zip',
          'size': '1024',
          'hash': 'abc123',
          'groupid': '10',
          'description': 'Test asset',
          'targetfolder': 'target',
          'localfolder': 'local',
          'lastupdate': '2024-01-01T00:00:00.000',
        };

        final asset = Asset.fromJson(json);

        expect(asset.id, 1);
        expect(asset.size, 1024);
        expect(asset.groupId, 10);
      });

      test('handles missing fields with defaults', () {
        final json = {
          'id': 1,
        };

        final asset = Asset.fromJson(json);

        expect(asset.id, 1);
        expect(asset.name, '');
        expect(asset.size, 0);
        expect(asset.hash, '');
        expect(asset.groupId, 0);
        expect(asset.description, '');
        expect(asset.targetFolder, '');
        expect(asset.localFolder, '');
        expect(asset.lastUpdate, isA<DateTime>());
      });

      test('handles null values with defaults', () {
        final json = {
          'id': null,
          'name': null,
          'size': null,
          'hash': null,
          'groupid': null,
          'description': null,
          'targetfolder': null,
          'localfolder': null,
          'lastupdate': null,
        };

        final asset = Asset.fromJson(json);

        expect(asset.id, 0);
        expect(asset.name, '');
        expect(asset.size, 0);
        expect(asset.hash, '');
        expect(asset.groupId, 0);
        expect(asset.description, '');
        expect(asset.targetFolder, '');
        expect(asset.localFolder, '');
        expect(asset.lastUpdate, isA<DateTime>());
      });

      test('handles invalid number strings with defaults', () {
        final json = {
          'id': 'invalid',
          'size': 'not-a-number',
          'groupid': 'abc',
          'name': 'test.zip',
          'hash': 'abc123',
          'description': 'Test',
          'targetfolder': 'target',
          'localfolder': 'local',
          'lastupdate': '2024-01-01T00:00:00.000',
        };

        final asset = Asset.fromJson(json);

        expect(asset.id, 0);
        expect(asset.size, 0);
        expect(asset.groupId, 0);
      });
    });

    group('downloadUrl', () {
      test('generates correct download URL', () {
        final asset = Asset(
          id: 1,
          name: 'test.zip',
          size: 1024,
          hash: 'abc123',
          groupId: 10,
          description: 'Test asset',
          targetFolder: 'target',
          localFolder: 'mods/v1',
          lastUpdate: DateTime.now(),
        );

        expect(
          asset.downloadUrl,
          'https://jofhub.eu/apps/cloud/repository/mods/v1/test.zip',
        );
      });

      test('handles special characters in folder and name', () {
        final asset = Asset(
          id: 1,
          name: 'test file.zip',
          size: 1024,
          hash: 'abc123',
          groupId: 10,
          description: 'Test asset',
          targetFolder: 'target',
          localFolder: 'folder/subfolder',
          lastUpdate: DateTime.now(),
        );

        expect(
          asset.downloadUrl,
          contains('folder/subfolder/test%20file.zip'),
        );
      });
    });

    group('equality', () {
      test('assets with same id are equal', () {
        final asset1 = Asset(
          id: 1,
          name: 'test1.zip',
          size: 1024,
          hash: 'abc123',
          groupId: 10,
          description: 'Test 1',
          targetFolder: 'target1',
          localFolder: 'local1',
          lastUpdate: DateTime.now(),
        );

        final asset2 = Asset(
          id: 1,
          name: 'test2.zip',
          size: 2048,
          hash: 'def456',
          groupId: 20,
          description: 'Test 2',
          targetFolder: 'target2',
          localFolder: 'local2',
          lastUpdate: DateTime.now(),
        );

        expect(asset1, equals(asset2));
        expect(asset1.hashCode, equals(asset2.hashCode));
      });

      test('assets with different ids are not equal', () {
        final asset1 = Asset(
          id: 1,
          name: 'test.zip',
          size: 1024,
          hash: 'abc123',
          groupId: 10,
          description: 'Test',
          targetFolder: 'target',
          localFolder: 'local',
          lastUpdate: DateTime.now(),
        );

        final asset2 = Asset(
          id: 2,
          name: 'test.zip',
          size: 1024,
          hash: 'abc123',
          groupId: 10,
          description: 'Test',
          targetFolder: 'target',
          localFolder: 'local',
          lastUpdate: DateTime.now(),
        );

        expect(asset1, isNot(equals(asset2)));
        expect(asset1.hashCode, isNot(equals(asset2.hashCode)));
      });

      test('identical assets are equal', () {
        final asset = Asset(
          id: 1,
          name: 'test.zip',
          size: 1024,
          hash: 'abc123',
          groupId: 10,
          description: 'Test',
          targetFolder: 'target',
          localFolder: 'local',
          lastUpdate: DateTime.now(),
        );

        expect(asset, equals(asset));
      });
    });
  });
}
