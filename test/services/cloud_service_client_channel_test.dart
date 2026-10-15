import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:joflauncher/services/client_release_service.dart';
import 'package:joflauncher/services/cloud_service.dart';

String releasesBody() {
  return jsonEncode([
    {'tag_name': '1.6.1', 'draft': false, 'prerelease': false},
    {'tag_name': '1.6.1-alpha.9', 'draft': false, 'prerelease': true},
    {'tag_name': '1.6.1-alpha.59', 'draft': false, 'prerelease': true},
    {'tag_name': '1.6.1-beta.5', 'draft': false, 'prerelease': true},
    {'tag_name': '1.6.1-beta.31', 'draft': false, 'prerelease': true},
  ]);
}

String latestBody({String tag = '1.7.0'}) {
  return jsonEncode({'tag_name': tag, 'draft': false, 'prerelease': false});
}

/// Answers GitHub's `releases/latest` with [latest] and the release list with
/// [releases]. The jofhub manifest is never consulted for the client version,
/// so any request to it fails the test.
CloudService serviceReturning({
  http.Response? latest,
  http.Response? releases,
}) {
  return CloudService(
    httpClientFactory: () => MockClient((request) async {
      if (request.url.host == 'api.jofhub.eu') {
        throw StateError('client version must not come from jofhub');
      }
      if (request.url.path.endsWith('/releases/latest')) {
        return latest ?? http.Response('not found', 404);
      }
      if (request.url.path.endsWith('/releases')) {
        return releases ?? http.Response('not found', 404);
      }
      return http.Response('not found', 404);
    }),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('CloudService.resolveClientVersion channel awareness', () {
    test('alpha channel resolves to the newest alpha tag', () async {
      SharedPreferences.setMockInitialValues({'client_channel': 'alpha'});
      final cloud = serviceReturning(
          releases: http.Response(releasesBody(), 200));

      expect(await cloud.resolveClientVersion(), '1.6.1-alpha.59');
    });

    test('beta channel resolves to the newest beta tag', () async {
      SharedPreferences.setMockInitialValues({'client_channel': 'beta'});
      final cloud = serviceReturning(
          releases: http.Response(releasesBody(), 200));

      expect(await cloud.resolveClientVersion(), '1.6.1-beta.31');
    });

    test('stable channel takes the GitHub release marked Latest', () async {
      SharedPreferences.setMockInitialValues({'client_channel': 'stable'});
      final cloud = serviceReturning(latest: http.Response(latestBody(), 200));

      expect(await cloud.resolveClientVersion(), '1.7.0');
    });

    test('no persisted channel behaves like stable', () async {
      SharedPreferences.setMockInitialValues({});
      final cloud = serviceReturning(latest: http.Response(latestBody(), 200));

      expect(await cloud.resolveClientVersion(), '1.7.0');
    });

    // Callers keep whatever client is installed rather than guessing.
    test('a rate-limited GitHub API resolves to null on every channel',
        () async {
      for (final channel in ['stable', 'beta', 'alpha']) {
        SharedPreferences.setMockInitialValues({'client_channel': channel});
        final cloud = serviceReturning(
          latest: http.Response('rate limited', 403),
          releases: http.Response('rate limited', 403),
        );

        expect(await cloud.resolveClientVersion(), isNull, reason: channel);
      }
    });
  });

  group('CloudService.clientMarkerMatches with an unconfirmed version', () {
    const fallback = ClientTarget(
      platformName: 'Windows',
      version: ClientReleaseService.fallbackVersion,
      assetName: 'JoF-windows-x86_64.zip',
      versionConfirmed: false,
    );

    // Not knowing the latest release must not downgrade a newer stable client
    // or replace an alpha build with the pinned fallback.
    test('keeps any installed version of the same build', () {
      for (final version in ['1.7.0', '1.6.1-alpha.59']) {
        expect(
          CloudService.clientMarkerMatches(
            {'version': version, 'asset': 'JoF-windows-x86_64.zip'},
            fallback,
          ),
          isTrue,
          reason: version,
        );
      }
    });

    test('still installs when the build itself differs', () {
      expect(
        CloudService.clientMarkerMatches(
          {'version': '1.7.0', 'asset': 'JoF-windows-x86.zip'},
          fallback,
        ),
        isFalse,
      );
    });
  });
}
