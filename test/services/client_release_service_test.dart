import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:joflauncher/models/client_channel.dart';
import 'package:joflauncher/models/platform_arch.dart';
import 'package:joflauncher/services/client_release_service.dart';

void main() {
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
      expect(ClientReleaseService.windowsAssetName(WindowsSystemArch.bit32),
          'JoF-windows-x86.zip');
      expect(ClientReleaseService.windowsAssetName(WindowsSystemArch.bit64),
          'JoF-windows-x86_64.zip');
    });

    test('release API URL targets the tagged release', () {
      expect(
        ClientReleaseService.releaseApiUrl('1.6.1'),
        'https://api.github.com/repos/JediofFreedom/JoF_EJK/releases/tags/1.6.1',
      );
    });

    test('latest release API URL targets the release marked Latest', () {
      expect(
        ClientReleaseService.latestReleaseApiUrl(),
        'https://api.github.com/repos/JediofFreedom/JoF_EJK/releases/latest',
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

    test('stable takes the release GitHub marks as Latest', () async {
      final service = ClientReleaseService(
        httpClientFactory: () => MockClient((request) async {
          expect(request.url.toString(),
              ClientReleaseService.latestReleaseApiUrl());
          return http.Response(
              jsonEncode({'tag_name': '1.7.0', 'prerelease': false}), 200);
        }),
      );

      expect(await service.fetchLatestTag(ClientChannel.stable), '1.7.0');
    });

    test('stable returns null when no release is marked Latest', () async {
      final service = ClientReleaseService(
        httpClientFactory: () =>
            MockClient((request) async => http.Response('not found', 404)),
      );

      expect(await service.fetchLatestTag(ClientChannel.stable), isNull);
    });

    // One request serves both the tag and the digest, so a sync spends one
    // call of the 60/hour budget rather than two.
    test('digests from the tag lookup answer fetchAssetSha256', () async {
      var calls = 0;
      final service = ClientReleaseService(
        httpClientFactory: () => MockClient((request) async {
          calls++;
          return http.Response(
            jsonEncode({
              'tag_name': '1.7.0',
              'assets': [
                {
                  'name': 'JoF-windows-x86_64.zip',
                  'digest': 'sha256:abc123',
                },
              ],
            }),
            200,
          );
        }),
      );

      expect(await service.fetchLatestTag(ClientChannel.stable), '1.7.0');
      expect(await service.fetchAssetSha256('1.7.0', 'JoF-windows-x86_64.zip'),
          'abc123');
      expect(calls, 1);
    });

    test('reuses a resolved tag within the TTL and refetches after it',
        () async {
      var now = DateTime(2026, 10, 15, 12);
      var calls = 0;
      final service = ClientReleaseService(
        now: () => now,
        httpClientFactory: () => MockClient((request) async {
          calls++;
          return http.Response(jsonEncode({'tag_name': '1.7.$calls'}), 200);
        }),
      );

      expect(await service.fetchLatestTag(ClientChannel.stable), '1.7.1');
      now = now.add(const Duration(minutes: 4));
      expect(await service.fetchLatestTag(ClientChannel.stable), '1.7.1');
      now = now.add(ClientReleaseService.latestTagTtl);
      expect(await service.fetchLatestTag(ClientChannel.stable), '1.7.2');
      expect(calls, 2);
    });

    test('a failed lookup is not cached', () async {
      var fail = true;
      final service = ClientReleaseService(
        httpClientFactory: () => MockClient((request) async => fail
            ? http.Response('rate limited', 403)
            : http.Response(jsonEncode({'tag_name': '1.7.0'}), 200)),
      );

      expect(await service.fetchLatestTag(ClientChannel.stable), isNull);
      fail = false;
      expect(await service.fetchLatestTag(ClientChannel.stable), '1.7.0');
    });
  });
}
