import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:joflauncher/models/client_channel.dart';
import 'package:joflauncher/models/platform_arch.dart';
import 'package:joflauncher/services/client_release_service.dart';

/// Shaped after the real api.jofhub.eu `clientgroups` payload: the version
/// lives in the description of the jofclient pk3, alongside assets that carry
/// unrelated versions of their own.
List<dynamic> manifestClientGroups({
  String description = 'JoF EJK Client 1.6.1 (64 Bit)',
  String assetName = 'jofclient-win-x86_64.pk3',
}) {
  return [
    {
      'id': 16,
      'name': 'JoF EternalJK 64bit',
      'executable': 'eternaljk.x86_64.exe',
      'assets': [
        {
          'name': 'SDL2.x86_64.dll',
          'description': 'SDL 2.0.14 runtime',
        },
        {
          'name': assetName,
          'description': description,
        },
      ],
    },
  ];
}

void main() {
  group('ClientReleaseService.parseVersion', () {
    test('reads the version out of the jofclient asset description', () {
      expect(ClientReleaseService.parseVersion(manifestClientGroups()), '1.6.1');
    });

    test('ignores versions on non-jofclient assets in the same group', () {
      // SDL2's "2.0.14" must not win over the client's own version.
      final groups = manifestClientGroups(description: 'JoF EJK Client 1.6.1');
      expect(ClientReleaseService.parseVersion(groups), '1.6.1');
    });

    // The live 32-bit group lists a versionless `jofclient-assets.pk3` ahead of
    // the versioned client pk3; the scan must keep going rather than give up on
    // the first jofclient asset it meets.
    test('skips a versionless jofclient asset listed first', () {
      expect(
        ClientReleaseService.parseVersion([
          {
            'name': 'JoF EternalJK 32bit',
            'assets': [
              {
                'name': 'jofclient-assets.pk3',
                'description': 'JoF Client Assets',
              },
              {
                'name': 'jofclient-win-x86.pk3',
                'description': 'JoF EJK Client 1.6.1 (32 Bit)',
              },
            ],
          },
        ]),
        '1.6.1',
      );
    });

    test('returns null when no jofclient asset is present', () {
      final groups = manifestClientGroups(assetName: 'steam_api.dll');
      expect(ClientReleaseService.parseVersion(groups), isNull);
    });

    test('returns null when the description carries no version', () {
      final groups =
          manifestClientGroups(description: 'JoF EternalJK client payload');
      expect(ClientReleaseService.parseVersion(groups), isNull);
    });

    test('returns null on null or empty clientgroups', () {
      expect(ClientReleaseService.parseVersion(null), isNull);
      expect(ClientReleaseService.parseVersion([]), isNull);
    });

    test('tolerates malformed entries rather than throwing', () {
      expect(
        ClientReleaseService.parseVersion([
          'not a map',
          {'assets': 'not a list'},
          {'assets': [null, 42]},
        ]),
        isNull,
      );
    });

    test('handles two- and four-part versions', () {
      expect(
        ClientReleaseService.parseVersion(
            manifestClientGroups(description: 'JoF EJK Client 2.0 (64 Bit)')),
        '2.0',
      );
      expect(
        ClientReleaseService.parseVersion(manifestClientGroups(
            description: 'JoF EJK Client 1.6.1.2 (64 Bit)')),
        '1.6.1.2',
      );
    });
  });

  group('ClientReleaseService URLs', () {
    test('builds GitHub release download URLs', () {
      expect(
        ClientReleaseService.downloadUrl('1.6.1', 'JoF-macos-arm64.tar.gz'),
        'https://github.com/JediofFreedom/JoF_EJK/releases/download/1.6.1/JoF-macos-arm64.tar.gz',
      );
    });

    test('maps arch to the published asset names', () {
      expect(ClientReleaseService.linuxAssetName(LinuxSystemArch.bit32),
          'JoF-linux-x86.tar.gz');
      expect(ClientReleaseService.linuxAssetName(LinuxSystemArch.bit64),
          'JoF-linux-x86_64.tar.gz');
      expect(ClientReleaseService.macosAssetName(MacosSystemArch.amd),
          'JoF-macos-x86_64.tar.gz');
      expect(ClientReleaseService.macosAssetName(MacosSystemArch.arm),
          'JoF-macos-arm64.tar.gz');
    });

    test('release API URL targets the tagged release', () {
      expect(
        ClientReleaseService.releaseApiUrl('1.6.1'),
        'https://api.github.com/repos/JediofFreedom/JoF_EJK/releases/tags/1.6.1',
      );
    });

    test('releases API URL lists all releases newest-first', () {
      expect(
        ClientReleaseService.releasesApiUrl(),
        'https://api.github.com/repos/JediofFreedom/JoF_EJK/releases?per_page=100',
      );
    });
  });

  test('fallback version is pinned to a release that exists', () {
    expect(ClientReleaseService.fallbackVersion, '1.6.1');
  });

  group('ClientReleaseService.selectLatestTag', () {
    List<dynamic> releases(List<Map<String, dynamic>> entries) => entries;

    Map<String, dynamic> release(String tag, {bool draft = false}) => {
          'tag_name': tag,
          'draft': draft,
          'prerelease': true,
        };

    test('always returns null for the stable channel', () {
      expect(
        ClientReleaseService.selectLatestTag(
          releases([release('1.6.1-alpha.59')]),
          ClientChannel.stable,
        ),
        isNull,
      );
    });

    test('returns null for an empty list', () {
      expect(
        ClientReleaseService.selectLatestTag([], ClientChannel.alpha),
        isNull,
      );
    });

    test('picks the newest alpha tag', () {
      final result = ClientReleaseService.selectLatestTag(
        releases([
          release('1.6.1-alpha.9'),
          release('1.6.1-alpha.59'),
          release('1.6.1-alpha.30'),
        ]),
        ClientChannel.alpha,
      );
      expect(result, '1.6.1-alpha.59');
    });

    test('orders build numbers numerically, not lexicographically', () {
      // Lexicographic comparison would put "9" above "59".
      final result = ClientReleaseService.selectLatestTag(
        releases([release('1.6.1-alpha.59'), release('1.6.1-alpha.9')]),
        ClientChannel.alpha,
      );
      expect(result, '1.6.1-alpha.59');
    });

    test('a higher base version wins even with a lower build number', () {
      final result = ClientReleaseService.selectLatestTag(
        releases([release('1.6.1-alpha.59'), release('1.6.2-alpha.1')]),
        ClientChannel.alpha,
      );
      expect(result, '1.6.2-alpha.1');
    });

    test('ignores beta and stable entries when asking for alpha', () {
      final result = ClientReleaseService.selectLatestTag(
        releases([
          release('1.6.1'),
          release('1.6.1-beta.99'),
          release('1.6.1-alpha.5'),
        ]),
        ClientChannel.alpha,
      );
      expect(result, '1.6.1-alpha.5');
    });

    test('ignores alpha and stable entries when asking for beta', () {
      final result = ClientReleaseService.selectLatestTag(
        releases([
          release('1.6.1'),
          release('1.6.1-alpha.99'),
          release('1.6.1-beta.5'),
        ]),
        ClientChannel.beta,
      );
      expect(result, '1.6.1-beta.5');
    });

    test('skips draft releases', () {
      final result = ClientReleaseService.selectLatestTag(
        releases([
          release('1.6.1-alpha.99', draft: true),
          release('1.6.1-alpha.5'),
        ]),
        ClientChannel.alpha,
      );
      expect(result, '1.6.1-alpha.5');
    });

    test('returns null when nothing matches the requested channel', () {
      final result = ClientReleaseService.selectLatestTag(
        releases([release('1.6.1'), release('1.6.1-beta.5')]),
        ClientChannel.alpha,
      );
      expect(result, isNull);
    });

    test('tolerates junk entries rather than throwing', () {
      final result = ClientReleaseService.selectLatestTag([
        'not a map',
        {'tag_name': null},
        {'tag_name': 'not-a-version-tag'},
        {'tag_name': '1.6.1-alpha.5'},
      ], ClientChannel.alpha);
      expect(result, '1.6.1-alpha.5');
    });
  });

  group('ClientReleaseService.fetchLatestTag', () {
    test('happy path returns the newest matching tag', () async {
      final service = ClientReleaseService(
        httpClientFactory: () => MockClient((request) async {
          expect(request.url.toString(), ClientReleaseService.releasesApiUrl());
          return http.Response(
            jsonEncode([
              {'tag_name': '1.6.1-alpha.9', 'draft': false},
              {'tag_name': '1.6.1-alpha.59', 'draft': false},
            ]),
            200,
          );
        }),
      );

      expect(await service.fetchLatestTag(ClientChannel.alpha), '1.6.1-alpha.59');
    });

    test('non-200 response returns null', () async {
      final service = ClientReleaseService(
        httpClientFactory: () =>
            MockClient((request) async => http.Response('rate limited', 403)),
      );

      expect(await service.fetchLatestTag(ClientChannel.alpha), isNull);
    });

    test('malformed JSON returns null rather than throwing', () async {
      final service = ClientReleaseService(
        httpClientFactory: () =>
            MockClient((request) async => http.Response('not json', 200)),
      );

      expect(await service.fetchLatestTag(ClientChannel.alpha), isNull);
    });

    test('returns null immediately for the stable channel', () async {
      final service = ClientReleaseService(
        httpClientFactory: () =>
            MockClient((request) async => throw Exception('must not be called')),
      );

      expect(await service.fetchLatestTag(ClientChannel.stable), isNull);
    });
  });
}
