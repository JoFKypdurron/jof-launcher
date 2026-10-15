import 'package:flutter_test/flutter_test.dart';
import 'package:joflauncher/models/asset.dart';
import 'package:joflauncher/models/repository_source.dart';

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

    group('repositoryPath and download URLs', () {
      Asset assetAt(String localFolder, String name) => Asset(
            id: 1,
            name: name,
            size: 1024,
            hash: 'abc123',
            groupId: 10,
            description: 'Test asset',
            targetFolder: 'target',
            localFolder: localFolder,
            lastUpdate: DateTime(2024, 1, 1),
          );

      String originUrl(Asset a) =>
          RepositoryEndpoint.origin.fileUri(a.repositoryPath).toString();
      String mirrorUrl(Asset a) =>
          RepositoryEndpoint.mirror.fileUri(a.repositoryPath).toString();

      test('splits localFolder into segments followed by the name', () {
        expect(assetAt('mods/v1', 'test.zip').repositoryPath,
            ['mods', 'v1', 'test.zip']);
        expect(assetAt('eternaljk/EternalJK', 'jofclient-win-x86.pk3').repositoryPath,
            ['eternaljk', 'EternalJK', 'jofclient-win-x86.pk3']);
      });

      test('ignores empty segments from stray slashes', () {
        expect(assetAt('/assets/', 'a.pk3').repositoryPath, ['assets', 'a.pk3']);
        expect(assetAt('', 'a.pk3').repositoryPath, ['a.pk3']);
      });

      test('builds the origin URL unchanged from before', () {
        expect(
          originUrl(assetAt('mods/v1', 'test.zip')),
          'https://jofhub.eu/apps/cloud/repository/mods/v1/test.zip',
        );
      });

      test('builds the mirror URL under the same relative path', () {
        expect(
          mirrorUrl(assetAt('mods/v1', 'test.zip')),
          'https://cloud.jof.app/cloud/repository/mods/v1/test.zip',
        );
      });

      const awkward = {
        "{JoF}'s-GWing.pk3": "%7BJoF%7D's-GWing.pk3",
        'Shree&Aldro Skin&Hilt.pk3': 'Shree&Aldro%20Skin&Hilt.pk3',
        'senek_2017 .pk3': 'senek_2017%20.pk3',
        'test file.zip': 'test%20file.zip',
      };

      for (final entry in awkward.entries) {
        test('percent-encodes "${entry.key}" on both hosts', () {
          final asset = assetAt('assets', entry.key);
          expect(originUrl(asset),
              'https://jofhub.eu/apps/cloud/repository/assets/${entry.value}');
          expect(mirrorUrl(asset),
              'https://cloud.jof.app/cloud/repository/assets/${entry.value}');
        });
      }

      test('keeps slashes in a nested localFolder as path separators', () {
        final asset = assetAt('eternaljk/EternalJK', 'jofclient-win-x86.pk3');
        expect(mirrorUrl(asset),
            'https://cloud.jof.app/cloud/repository/eternaljk/EternalJK/jofclient-win-x86.pk3');
        expect(originUrl(asset),
            'https://jofhub.eu/apps/cloud/repository/eternaljk/EternalJK/jofclient-win-x86.pk3');
      });

      test('encodes characters that would otherwise end the path', () {
        final asset = assetAt('assets', 'odd #1?%20.pk3');
        expect(mirrorUrl(asset),
            'https://cloud.jof.app/cloud/repository/assets/odd%20%231%3F%2520.pk3');
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
