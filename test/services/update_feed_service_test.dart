import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:joflauncher/models/update_manifest.dart';
import 'package:joflauncher/services/update_feed_service.dart';

String manifestJson({
  String version = '1.1.9',
  int schema = 1,
  bool withArtifacts = true,
}) {
  return jsonEncode({
    'schema': schema,
    'version': version,
    'tag': 'v$version-launcher',
    'notesUrl': 'https://example.invalid/notes',
    'downloadPageUrl': 'https://example.invalid/download',
    // A field this build has never heard of: must be ignored, not fatal.
    'rolloutPercent': 25,
    if (withArtifacts)
      'artifacts': {
        'macos': {
          'url': 'https://cloud.jof.app/launcher/jof-launcher-macos-$version.dmg',
          'sha256': 'a' * 64,
          'size': 26648612,
        },
        'linuxTar': {
          'url':
              'https://cloud.jof.app/launcher/jof-launcher-linux-$version.tar.gz',
          'sha256': 'b' * 64,
          'size': 11103881,
        },
        'windows': {
          'url':
              'https://cloud.jof.app/launcher/jof-launcher-windows-setup-$version.exe',
          'sha256': 'c' * 64,
          'size': 15000000,
        },
      },
  });
}

UpdateFeedService serviceReturning(
  Map<String, http.Response> byHost, {
  List<Uri>? requested,
}) {
  return UpdateFeedService(
    httpClientFactory: () => MockClient((request) async {
      requested?.add(request.url);
      final response = byHost[request.url.host];
      return response ?? http.Response('not found', 404);
    }),
  );
}

void main() {
  group('UpdateManifest.tryParse', () {
    test('parses a well-formed manifest and ignores unknown fields', () {
      final m = UpdateManifest.tryParse(manifestJson())!;
      expect(m.version, '1.1.9');
      expect(m.tag, 'v1.1.9-launcher');
      expect(m.isSupportedSchema, isTrue);
      expect(m.artifactFor(UpdateArtifactKind.macos)!.sha256, 'a' * 64);
      expect(m.artifactFor(UpdateArtifactKind.linuxTar)!.size, 11103881);
      expect(m.artifactFor(UpdateArtifactKind.windows)!.sha256, 'c' * 64);
      // Not published in this manifest.
      expect(m.artifactFor(UpdateArtifactKind.linuxDeb), isNull);
    });

    test('returns null rather than throwing on unusable input', () {
      expect(UpdateManifest.tryParse('not json'), isNull);
      expect(UpdateManifest.tryParse('[]'), isNull);
      expect(UpdateManifest.tryParse('{}'), isNull);
      expect(UpdateManifest.tryParse('{"version": ""}'), isNull);
    });

    test('flags a manifest written by a newer release process', () {
      final m = UpdateManifest.tryParse(manifestJson(schema: 2))!;
      expect(m.version, '1.1.9');
      expect(m.isSupportedSchema, isFalse);
    });

    test('drops artifacts missing a digest, keeping the rest usable', () {
      final m = UpdateManifest.tryParse(jsonEncode({
        'schema': 1,
        'version': '1.1.9',
        'artifacts': {
          'macos': {'url': 'https://x.invalid/a.dmg'},
          'linuxTar': {'url': 'https://x.invalid/a.tgz', 'sha256': 'c' * 64},
        },
      }))!;
      expect(m.artifactFor(UpdateArtifactKind.macos), isNull);
      expect(m.artifactFor(UpdateArtifactKind.linuxTar), isNotNull);
    });
  });

  group('fetchLatest', () {
    test('uses the manifest when it is available', () async {
      final requested = <Uri>[];
      final svc = serviceReturning(
        {'cloud.jof.app': http.Response(manifestJson(), 200)},
        requested: requested,
      );

      final m = await svc.fetchLatest();
      expect(m!.version, '1.1.9');
      // The GitHub fallback must not be touched when the manifest works.
      expect(requested.map((u) => u.host), ['cloud.jof.app']);
    });

    test('falls back to GitHub releases when the manifest is missing',
        () async {
      final githubBody = jsonEncode({
        'tag_name': 'v1.2.0-launcher',
        'assets': [
          {
            'name': 'jof-launcher-macos.dmg',
            'browser_download_url': 'https://github.invalid/a.dmg',
            'digest': 'sha256:${'d' * 64}',
            'size': 123,
          },
          {
            'name': 'jof-launcher-linux.tar.gz',
            'browser_download_url': 'https://github.invalid/a.tgz',
            'digest': 'sha256:${'e' * 64}',
            'size': 456,
          },
          {
            'name': 'jof-launcher-windows-setup.exe',
            'browser_download_url': 'https://github.invalid/setup.exe',
            'digest': 'sha256:${'f' * 64}',
            'size': 321,
          },
          {
            // The portable zip cannot update an install; never offered.
            'name': 'jof-launcher-windows.zip',
            'browser_download_url': 'https://github.invalid/a.zip',
            'digest': 'sha256:${'0' * 64}',
            'size': 654,
          },
          {
            // No digest: unverifiable, so it must not be offered.
            'name': 'jof-launcher_1.2.0_amd64.deb',
            'browser_download_url': 'https://github.invalid/a.deb',
            'size': 789,
          },
        ],
      });

      final svc = serviceReturning({
        'cloud.jof.app': http.Response('nope', 404),
        'api.github.com': http.Response(githubBody, 200),
      });

      final m = await svc.fetchLatest();
      expect(m!.version, '1.2.0', reason: 'tag decoration should be stripped');
      expect(m.tag, 'v1.2.0-launcher');
      expect(m.artifactFor(UpdateArtifactKind.macos)!.sha256, 'd' * 64);
      expect(m.artifactFor(UpdateArtifactKind.windows)!.url,
          'https://github.invalid/setup.exe');
      expect(m.artifactFor(UpdateArtifactKind.linuxDeb), isNull);
    });

    test('returns null when both sources fail', () async {
      final svc = serviceReturning({
        'cloud.jof.app': http.Response('nope', 404),
        'api.github.com': http.Response('rate limited', 403),
      });
      expect(await svc.fetchLatest(), isNull);
    });

    test('a malformed manifest falls through to the fallback', () async {
      final svc = serviceReturning({
        'cloud.jof.app': http.Response('<html>oops</html>', 200),
        'api.github.com': http.Response(
          jsonEncode({'tag_name': 'v1.3.0-launcher', 'assets': []}),
          200,
        ),
      });
      final m = await svc.fetchLatest();
      expect(m!.version, '1.3.0');
    });

    test('never throws when the network blows up', () async {
      final svc = UpdateFeedService(
        httpClientFactory: () =>
            MockClient((_) async => throw const SocketExceptionStub()),
      );
      expect(await svc.fetchLatest(), isNull);
    });
  });
}

class SocketExceptionStub implements Exception {
  const SocketExceptionStub();
}
