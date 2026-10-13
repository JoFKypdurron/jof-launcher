import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:joflauncher/services/client_release_service.dart';
import 'package:joflauncher/services/cloud_service.dart';

/// A minimal, well-formed `getclouddata` body carrying a manifest client
/// version, shaped like the real api.jofhub.eu response.
String manifestBody({String version = '1.6.1'}) {
  return jsonEncode({
    'status': 'OK',
    'data': {
      'clientgroups': [
        {
          'id': 16,
          'assets': [
            {
              'name': 'jofclient-win-x86_64.pk3',
              'description': 'JoF EJK Client $version (64 Bit)',
            },
          ],
        },
      ],
    },
  });
}

String releasesBody() {
  return jsonEncode([
    {'tag_name': '1.6.1', 'draft': false, 'prerelease': false},
    {'tag_name': '1.6.1-alpha.9', 'draft': false, 'prerelease': true},
    {'tag_name': '1.6.1-alpha.59', 'draft': false, 'prerelease': true},
    {'tag_name': '1.6.1-beta.5', 'draft': false, 'prerelease': true},
    {'tag_name': '1.6.1-beta.31', 'draft': false, 'prerelease': true},
  ]);
}

CloudService serviceReturning(Map<String, http.Response> byHost) {
  return CloudService(
    httpClientFactory: () => MockClient((request) async {
      final response = byHost[request.url.host];
      return response ?? http.Response('not found', 404);
    }),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('CloudService.resolveClientVersion channel awareness', () {
    test('alpha channel resolves to the newest alpha tag', () async {
      SharedPreferences.setMockInitialValues({'client_channel': 'alpha'});
      final cloud = serviceReturning({
        'api.jofhub.eu': http.Response(manifestBody(), 200),
        'api.github.com': http.Response(releasesBody(), 200),
      });

      expect(await cloud.resolveClientVersion(), '1.6.1-alpha.59');
    });

    test('beta channel resolves to the newest beta tag', () async {
      SharedPreferences.setMockInitialValues({'client_channel': 'beta'});
      final cloud = serviceReturning({
        'api.jofhub.eu': http.Response(manifestBody(), 200),
        'api.github.com': http.Response(releasesBody(), 200),
      });

      expect(await cloud.resolveClientVersion(), '1.6.1-beta.31');
    });

    test('stable channel keeps the manifest version', () async {
      SharedPreferences.setMockInitialValues({'client_channel': 'stable'});
      final cloud = serviceReturning({
        'api.jofhub.eu': http.Response(manifestBody(version: '1.7.0'), 200),
        'api.github.com': http.Response(releasesBody(), 200),
      });

      expect(await cloud.resolveClientVersion(), '1.7.0');
    });

    test('no persisted channel behaves like stable', () async {
      SharedPreferences.setMockInitialValues({});
      final cloud = serviceReturning({
        'api.jofhub.eu': http.Response(manifestBody(version: '1.7.0'), 200),
        'api.github.com': http.Response(releasesBody(), 200),
      });

      expect(await cloud.resolveClientVersion(), '1.7.0');
    });

    test(
        'a rate-limited GitHub releases call on the alpha channel degrades to the manifest version',
        () async {
      SharedPreferences.setMockInitialValues({'client_channel': 'alpha'});
      final cloud = serviceReturning({
        'api.jofhub.eu': http.Response(manifestBody(version: '1.7.0'), 200),
        'api.github.com': http.Response('rate limited', 403),
      });

      expect(await cloud.resolveClientVersion(), '1.7.0');
    });

    test(
        'a rate-limited GitHub releases call on the alpha channel degrades to the fallback version when the manifest is also unavailable',
        () async {
      SharedPreferences.setMockInitialValues({'client_channel': 'alpha'});
      final cloud = serviceReturning({
        'api.jofhub.eu': http.Response('nope', 500),
        'api.github.com': http.Response('rate limited', 403),
      });

      expect(
          await cloud.resolveClientVersion(), ClientReleaseService.fallbackVersion);
    });
  });
}
