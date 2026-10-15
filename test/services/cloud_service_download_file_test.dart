import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:joflauncher/services/cloud_service.dart';
import 'package:joflauncher/services/connectivity_service.dart';

/// Always online, so failures are retried immediately rather than waiting.
class OnlineConnectivity extends ConnectivityService {
  @override
  Future<bool> isOnline() async => true;
}

/// More requests than any bounded download needs; past it the server throws
/// a non-retryable error so a regression fails the test instead of hanging.
const requestCeiling = 20;

void main() {
  late Directory tempDir;

  final update = utf8.encode('the launcher update archive');
  final sha256Hex = sha256.convert(update).toString();
  const url = 'https://updates.example/jof-launcher-linux.tar.gz';

  CloudService service(http.Client Function() client) => CloudService(
        connectivity: OnlineConnectivity(),
        httpClientFactory: client,
        retryBackoff: (_) => Duration.zero,
      );

  /// Serves [respond] for every request, counting them.
  ({List<http.BaseRequest> requests, http.Client Function() client}) server(
      Future<http.StreamedResponse> Function(http.BaseRequest request)
          respond) {
    final requests = <http.BaseRequest>[];
    return (
      requests: requests,
      client: () => MockClient.streaming((request, _) async {
            requests.add(request);
            if (requests.length > requestCeiling) {
              throw StateError('download is looping');
            }
            return respond(request);
          }),
    );
  }

  http.StreamedResponse body(List<int> bytes,
          {int statusCode = 200, bool declareLength = true}) =>
      http.StreamedResponse(Stream.value(bytes), statusCode,
          contentLength: declareLength ? bytes.length : null);

  Future<void> download(http.Client Function() client) =>
      service(client).downloadFile(
        url: url,
        finalPath: '${tempDir.path}/update.tar.gz',
        expectedSize: update.length,
        expectedSha256: sha256Hex,
      );

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('jof_download_file_test_');
  });

  tearDown(() async {
    await tempDir.delete(recursive: true);
  });

  test('downloads and verifies the expected file', () async {
    final s = server((_) async => body(update));

    await download(s.client);

    expect(await File('${tempDir.path}/update.tar.gz').readAsBytes(), update);
    expect(s.requests, hasLength(1));
  });

  group('a server that keeps serving the wrong size fails after 3 attempts',
      () {
    test('shorter file', () async {
      final s = server((_) async => body(utf8.encode('stale')));

      await expectLater(download(s.client),
          throwsA(isA<Exception>().having((e) => '$e', 'message',
              contains('3 times'))));
      expect(s.requests, hasLength(3));
      expect(File('${tempDir.path}/update.tar.gz.part').existsSync(), isFalse);
    });

    test('longer file', () async {
      final s = server(
          (_) async => body(utf8.encode('an older, much longer launcher build')));

      await expectLater(download(s.client), throwsException);
      expect(s.requests, hasLength(3));
    });

    test('wrong size without a declared Content-Length', () async {
      final s = server(
          (_) async => body(utf8.encode('stale'), declareLength: false));

      await expectLater(download(s.client), throwsException);
      expect(s.requests, hasLength(3));
    });

    test('206 resume whose Content-Range total is wrong', () async {
      // First a truncated body at the right declared size, then every resume
      // reports a different total for the file.
      final s = server((request) async {
        if (request.headers['Range'] == null) {
          return http.StreamedResponse(
              Stream.value(update.sublist(0, 5)), 200,
              contentLength: update.length);
        }
        return http.StreamedResponse(Stream.value(update.sublist(5)), 206,
            headers: {'content-range': 'bytes 5-99/100'});
      });

      await expectLater(download(s.client), throwsException);
      // Truncated 200, rejected 206, three times over.
      expect(s.requests, hasLength(6));
    });
  });

  test('a 416 to a request without Range fails instead of spinning', () async {
    final s = server((_) async => body(const [], statusCode: 416));

    await expectLater(download(s.client), throwsException);
    expect(s.requests, hasLength(1));
  });
}
