import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:joflauncher/models/asset.dart';
import 'package:joflauncher/models/repository_source.dart';
import 'package:joflauncher/services/cloud_service.dart';
import 'package:joflauncher/services/connectivity_service.dart';
import 'package:joflauncher/services/log_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

const mirrorHost = 'cloud.jof.app';
const originFileHost = 'jofhub.eu';
const originApiHost = 'api.jofhub.eu';

/// Always online, so network failures count against the mirror's budget.
class OnlineConnectivity extends ConnectivityService {
  @override
  Future<bool> isOnline() async => true;
}

String manifestBody({String status = 'OK'}) => jsonEncode({
      'status': status,
      'data': {
        'assetgroups': [
          {'id': 1, 'name': 'Assets', 'assets': []},
        ],
        'clientgroups': [],
        'modgroups': [],
        'othergroups': [],
      },
    });

const htmlErrorPage = '<!doctype html><html><body>JoF Cloud</body></html>';

/// Routes requests by host and records every one of them. A host without a
/// handler is unreachable.
class FakeServers {
  final Map<String, http.Response Function(http.Request request)> handlers;
  final List<Uri> requests = [];

  FakeServers(this.handlers);

  http.Client client() => MockClient((request) async {
        requests.add(request.url);
        final handler = handlers[request.url.host];
        if (handler == null) {
          throw SocketException('unreachable: ${request.url.host}');
        }
        return handler(request);
      });

  int hits(String host) => requests.where((u) => u.host == host).length;
}

http.Response fileResponse(List<int> bytes, {String? contentType}) {
  return http.Response.bytes(bytes, 200, headers: {
    'content-type': ?contentType,
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late LogService log;

  final content = utf8.encode('the real pk3 contents');
  final hash = md5.convert(content).toString();
  final wrongSameSize = List<int>.filled(content.length, 0x41);

  Asset asset({String name = "{JoF}'s-GWing.pk3", int? size, String? md5Hash}) {
    return Asset(
      id: 1,
      name: name,
      size: size ?? content.length,
      hash: md5Hash ?? hash,
      groupId: 1,
      description: '',
      targetFolder: '',
      localFolder: 'assets',
      lastUpdate: DateTime(2024),
    );
  }

  CloudService service(FakeServers servers) => CloudService(
        connectivity: OnlineConnectivity(),
        httpClientFactory: servers.client,
        retryBackoff: (_) => Duration.zero,
      );

  void useSource(RepositorySource source) {
    SharedPreferences.setMockInitialValues(
        {'repository_source': source.persistedValue});
  }

  Future<List<int>> downloaded(String name) =>
      File('${tempDir.path}/$name').readAsBytes();

  bool logged(String fragment) =>
      log.recentLines.any((line) => line.contains(fragment));

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tempDir = await Directory.systemTemp.createTemp('jof_repo_source_test_');
    log = LogService(resolveDirectory: () async => null);
    LogService.instance = log;
  });

  tearDown(() async {
    await tempDir.delete(recursive: true);
  });

  group('manifest', () {
    test('auto fetches the manifest from the mirror', () async {
      final servers = FakeServers({
        mirrorHost: (r) {
          expect(r.url.path, '/cloud/manifest/getclouddata.json');
          return http.Response(manifestBody(), 200);
        },
        originApiHost: (_) => http.Response(manifestBody(), 200),
      });
      final cloud = service(servers);

      final data = await cloud.fetchCloudData();

      expect(data.assetGroups.single.id, 1);
      expect(cloud.manifestEndpoint, RepositoryEndpoint.mirror);
      expect(servers.hits(originApiHost), 0);
      expect(logged('manifest from mirror'), isTrue);
    });

    test('auto falls back to the origin on a mirror 5xx', () async {
      final servers = FakeServers({
        mirrorHost: (_) => http.Response('oops', 503),
        originApiHost: (_) => http.Response(manifestBody(), 200),
      });
      final cloud = service(servers);

      await cloud.fetchCloudData();

      expect(cloud.manifestEndpoint, RepositoryEndpoint.origin);
      expect(logged('manifest: mirror failed'), isTrue);
      expect(logged('503'), isTrue);
    });

    test('auto falls back to the origin when the mirror returns HTML', () async {
      final servers = FakeServers({
        mirrorHost: (_) => http.Response(htmlErrorPage, 200,
            headers: {'content-type': 'text/html'}),
        originApiHost: (_) => http.Response(manifestBody(), 200),
      });
      final cloud = service(servers);

      await cloud.fetchCloudData();

      expect(cloud.manifestEndpoint, RepositoryEndpoint.origin);
    });

    test('auto falls back to the origin when mirror status is not OK', () async {
      final servers = FakeServers({
        mirrorHost: (_) => http.Response(manifestBody(status: 'ERROR'), 200),
        originApiHost: (_) => http.Response(manifestBody(), 200),
      });
      final cloud = service(servers);

      await cloud.fetchCloudData();

      expect(cloud.manifestEndpoint, RepositoryEndpoint.origin);
    });

    test('auto falls back to the origin when the mirror is unreachable', () async {
      final servers = FakeServers({
        originApiHost: (_) => http.Response(manifestBody(), 200),
      });
      final cloud = service(servers);

      await cloud.fetchCloudData();

      expect(cloud.manifestEndpoint, RepositoryEndpoint.origin);
    });

    test('origin strategy never touches the mirror', () async {
      useSource(RepositorySource.origin);
      final servers = FakeServers({
        mirrorHost: (_) => http.Response(manifestBody(), 200),
        originApiHost: (_) => http.Response(manifestBody(), 200),
      });
      final cloud = service(servers);

      await cloud.fetchCloudData();

      expect(cloud.manifestEndpoint, RepositoryEndpoint.origin);
      expect(servers.hits(mirrorHost), 0);
    });

    test('mirror strategy fails rather than touching the origin', () async {
      useSource(RepositorySource.mirror);
      final servers = FakeServers({
        mirrorHost: (_) => http.Response('oops', 503),
        originApiHost: (_) => http.Response(manifestBody(), 200),
      });
      final cloud = service(servers);

      await expectLater(cloud.fetchCloudData(), throwsException);
      expect(servers.hits(originApiHost), 0);
    });
  });

  group('file download', () {
    test('auto downloads from the mirror with the encoded path', () async {
      final servers = FakeServers({
        mirrorHost: (_) => fileResponse(content,
            contentType: 'application/octet-stream'),
        originFileHost: (_) => fileResponse(content),
      });

      await service(servers).downloadAsset(asset(), tempDir.path);

      expect(await downloaded("{JoF}'s-GWing.pk3"), content);
      expect(servers.requests.single.toString(),
          "https://cloud.jof.app/cloud/repository/assets/%7BJoF%7D's-GWing.pk3");
      expect(servers.hits(originFileHost), 0);
      expect(logged('downloaded from mirror'), isTrue);
    });

    for (final status in [403, 404]) {
      test('mirror $status falls back to the origin for that file', () async {
        final servers = FakeServers({
          mirrorHost: (_) => http.Response(htmlErrorPage, status,
              headers: {'content-type': 'text/html'}),
          originFileHost: (_) => fileResponse(content),
        });

        await service(servers).downloadAsset(asset(), tempDir.path);

        expect(await downloaded("{JoF}'s-GWing.pk3"), content);
        expect(servers.hits(mirrorHost), 1);
        expect(servers.hits(originFileHost), 1);
        expect(logged('mirror failed (HTTP $status)'), isTrue);
        expect(logged('downloaded from origin after fallback'), isTrue);
      });
    }

    test('mirror 200 text/html is never accepted, even at the right size',
        () async {
      final html = utf8.encode(htmlErrorPage);
      final servers = FakeServers({
        mirrorHost: (_) => fileResponse(html, contentType: 'text/html'),
        originFileHost: (_) => fileResponse(html),
      });

      // Manifest size matches the HTML body, and there is no hash to check.
      final a = asset(size: html.length, md5Hash: '');
      await expectLater(
          service(servers).downloadAsset(a, tempDir.path), completes);

      // The HTML from the mirror was rejected; the origin copy (no
      // content-type, like the real jofhub.eu) was used instead.
      expect(servers.hits(mirrorHost), 1);
      expect(servers.hits(originFileHost), 1);
      expect(logged('served text/html'), isTrue);
    });

    test('text/html is rejected on a source without a fallback too', () async {
      useSource(RepositorySource.origin);
      final servers = FakeServers({
        originFileHost: (_) =>
            fileResponse(utf8.encode(htmlErrorPage), contentType: 'text/html'),
      });

      await expectLater(
        service(servers).downloadAsset(asset(), tempDir.path),
        throwsA(predicate((e) => e.toString().contains('verification 3 times'))),
      );
      expect(servers.hits(originFileHost), 3);
      expect(File('${tempDir.path}/${asset().name}').existsSync(), isFalse);
    });

    test('MD5 mismatch on the mirror falls back to the origin', () async {
      final servers = FakeServers({
        mirrorHost: (_) => fileResponse(wrongSameSize),
        originFileHost: (_) => fileResponse(content),
      });

      await service(servers).downloadAsset(asset(), tempDir.path);

      expect(await downloaded("{JoF}'s-GWing.pk3"), content);
      expect(servers.hits(mirrorHost), 1);
      expect(servers.hits(originFileHost), 1);
      expect(logged('mirror failed (MD5 mismatch)'), isTrue);
    });

    test('the integrity budget is shared across sources, not doubled',
        () async {
      final servers = FakeServers({
        mirrorHost: (_) => fileResponse(wrongSameSize),
        originFileHost: (_) => fileResponse(wrongSameSize),
      });

      await expectLater(
        service(servers).downloadAsset(asset(), tempDir.path),
        throwsA(predicate((e) => e.toString().contains('MD5 verification 3 times'))),
      );
      // Three full downloads in total, as before the mirror existed.
      expect(servers.hits(mirrorHost), 1);
      expect(servers.hits(originFileHost), 2);
    });

    test('a stale mirror copy is detected from its size before downloading',
        () async {
      final servers = FakeServers({
        mirrorHost: (_) => fileResponse(utf8.encode('an older, longer version')),
        originFileHost: (_) => fileResponse(content),
      });

      await service(servers).downloadAsset(asset(), tempDir.path);

      expect(await downloaded("{JoF}'s-GWing.pk3"), content);
      expect(servers.hits(mirrorHost), 1);
      expect(logged('manifest says ${content.length}'), isTrue);
    });

    test('a stale file fails after three tries instead of looping forever',
        () async {
      useSource(RepositorySource.mirror);
      final servers = FakeServers({
        mirrorHost: (_) => fileResponse(utf8.encode('short')),
      });

      await expectLater(
          service(servers).downloadAsset(asset(), tempDir.path), throwsException);
      expect(servers.hits(mirrorHost), 3);
    });

    test('mirror network errors fall back after three attempts', () async {
      final servers = FakeServers({
        originFileHost: (_) => fileResponse(content),
      });

      await service(servers).downloadAsset(asset(), tempDir.path);

      expect(await downloaded("{JoF}'s-GWing.pk3"), content);
      expect(servers.hits(mirrorHost), 3);
      expect(logged('network error after 3 attempt(s)'), isTrue);
    });

    test('mirror 5xx falls back and marks the mirror degraded', () async {
      final servers = FakeServers({
        mirrorHost: (_) => http.Response('busy', 503),
        originFileHost: (_) => fileResponse(content),
      });
      final cloud = service(servers);

      await cloud.downloadAsset(asset(name: 'a.pk3'), tempDir.path);
      // Degraded: the next file's mirror attempt is quick, then origin.
      servers.handlers.remove(mirrorHost);
      await cloud.downloadAsset(asset(name: 'b.pk3'), tempDir.path);

      expect(servers.hits(mirrorHost), 2);
      expect(servers.hits(originFileHost), 2);
    });

    test('after a manifest fallback the mirror gets one quick try per file',
        () async {
      final servers = FakeServers({
        originApiHost: (_) => http.Response(manifestBody(), 200),
        originFileHost: (_) => fileResponse(content),
      });
      final cloud = service(servers);

      await cloud.fetchCloudData();
      expect(cloud.manifestEndpoint, RepositoryEndpoint.origin);

      await cloud.downloadAsset(asset(), tempDir.path);

      expect(await downloaded("{JoF}'s-GWing.pk3"), content);
      expect(servers.hits(mirrorHost), 2); // manifest + one file attempt
      expect(servers.hits(originFileHost), 1);
    });

    test('an unreachable mirror is skipped after three files in a row',
        () async {
      final servers = FakeServers({
        originApiHost: (_) => http.Response(manifestBody(), 200),
        originFileHost: (_) => fileResponse(content),
      });
      final cloud = service(servers);
      await cloud.fetchCloudData();
      final afterManifest = servers.hits(mirrorHost);

      for (final name in ['1.pk3', '2.pk3', '3.pk3', '4.pk3', '5.pk3']) {
        await cloud.downloadAsset(asset(name: name), tempDir.path);
      }

      expect(servers.hits(mirrorHost) - afterManifest, 3);
      expect(servers.hits(originFileHost), 5);
      expect(logged('skipping mirror'), isTrue);

      // A fresh manifest from the mirror resets the breaker.
      servers.handlers[mirrorHost] = (r) => r.url.path.contains('manifest')
          ? http.Response(manifestBody(), 200)
          : fileResponse(content);
      await cloud.fetchCloudData();
      await cloud.downloadAsset(asset(name: '6.pk3'), tempDir.path);
      expect(servers.hits(originFileHost), 5);
    });

    test('a 404 does not trip the unreachable-mirror breaker', () async {
      final servers = FakeServers({
        mirrorHost: (_) => http.Response(htmlErrorPage, 404,
            headers: {'content-type': 'text/html'}),
        originFileHost: (_) => fileResponse(content),
      });
      final cloud = service(servers);

      for (final name in ['1.pk3', '2.pk3', '3.pk3', '4.pk3']) {
        await cloud.downloadAsset(asset(name: name), tempDir.path);
      }

      expect(servers.hits(mirrorHost), 4);
    });

    test('origin strategy never touches the mirror', () async {
      useSource(RepositorySource.origin);
      final servers = FakeServers({
        mirrorHost: (_) => fileResponse(content),
        originFileHost: (_) => fileResponse(content),
      });

      await service(servers).downloadAsset(asset(), tempDir.path);

      expect(servers.hits(mirrorHost), 0);
      expect(servers.requests.single.toString(),
          "https://jofhub.eu/apps/cloud/repository/assets/%7BJoF%7D's-GWing.pk3");
    });

    test('mirror strategy never touches the origin, even on a 404', () async {
      useSource(RepositorySource.mirror);
      final servers = FakeServers({
        mirrorHost: (_) => http.Response(htmlErrorPage, 404,
            headers: {'content-type': 'text/html'}),
        originFileHost: (_) => fileResponse(content),
      });

      await expectLater(
          service(servers).downloadAsset(asset(), tempDir.path), throwsException);
      expect(servers.hits(originFileHost), 0);
      expect(logged('mirror failed'), isTrue);
    });
  });
}
