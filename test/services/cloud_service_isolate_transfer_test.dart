import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:joflauncher/services/cloud_service.dart';
import 'package:joflauncher/services/connectivity_service.dart';
import 'package:path/path.dart' as p;

/// Always online, so a dropped connection is retried straight away.
class _OnlineConnectivity extends ConnectivityService {
  @override
  Future<bool> isOnline() async => true;
}

/// These tests leave the HTTP client factory unset, so the transfer runs in a
/// background isolate against a real local server, as it does in the app.
void main() {
  final body = Uint8List.fromList(
      List.generate(3 * 1024 * 1024, (i) => (i * 31 + 7) & 0xff));
  final bodySha256 = sha256.convert(body).toString();

  late HttpServer server;
  late Directory tempDir;
  late Future<void> Function(HttpRequest request) handler;

  setUp(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) => handler(request));
    tempDir = await Directory.systemTemp.createTemp('jof_isolate_transfer_');
  });

  tearDown(() async {
    await server.close(force: true);
    await tempDir.delete(recursive: true);
  });

  String url() => 'http://127.0.0.1:${server.port}/file.pk3';

  CloudService service() => CloudService(
        connectivity: _OnlineConnectivity(),
        retryBackoff: (_) => Duration.zero,
      );

  Future<void> serve(HttpRequest request, {int? dropAfter}) async {
    final range = request.headers.value('range');
    final start =
        range == null ? 0 : int.parse(range.substring(6, range.indexOf('-')));
    final response = request.response;
    if (start > 0) {
      response.statusCode = 206;
      response.headers
          .set('content-range', 'bytes $start-${body.length - 1}/${body.length}');
    }
    response.contentLength = body.length - start;
    if (dropAfter != null && start == 0) {
      // Send the headers and part of the body, then drop the connection.
      final socket = await response.detachSocket();
      socket.add(body.sublist(0, dropAfter));
      await socket.flush();
      socket.destroy();
      return;
    }
    response.add(body.sublist(start));
    await response.close();
  }

  test('downloads and verifies a file in a background isolate', () async {
    handler = (request) => serve(request);
    final finalPath = p.join(tempDir.path, 'file.pk3');
    final progress = <double>[];

    await service().downloadFile(
      url: url(),
      finalPath: finalPath,
      expectedSize: body.length,
      expectedSha256: bodySha256,
      onProgress: progress.add,
    );

    expect(await File(finalPath).readAsBytes(), body);
    expect(File('$finalPath.part').existsSync(), isFalse);
    expect(progress.last, 1.0);
  });

  test('resumes from the bytes on disk after the connection drops', () async {
    final ranges = <String?>[];
    handler = (request) {
      ranges.add(request.headers.value('range'));
      return serve(request, dropAfter: 1024 * 1024);
    };
    final finalPath = p.join(tempDir.path, 'file.pk3');

    await service().downloadFile(
      url: url(),
      finalPath: finalPath,
      expectedSize: body.length,
      expectedSha256: bodySha256,
    );

    expect(await File(finalPath).readAsBytes(), body);
    expect(ranges, hasLength(2));
    expect(ranges.first, isNull);
    expect(ranges.last, startsWith('bytes='));
    expect(int.parse(ranges.last!.substring(6, ranges.last!.length - 1)),
        greaterThan(0));
  });

  test('stops a running transfer when cancelled', () async {
    final stalled = Completer<void>();
    handler = (request) async {
      final response = request.response;
      response.contentLength = body.length;
      response.add(body.sublist(0, 64 * 1024));
      await response.flush();
      stalled.complete();
      // Never finishes; only cancellation ends the download.
      await Future<void>.delayed(const Duration(seconds: 20));
    };
    final finalPath = p.join(tempDir.path, 'file.pk3');
    var cancelled = false;

    final download = service().downloadFile(
      url: url(),
      finalPath: finalPath,
      expectedSize: body.length,
      isCancelled: () => cancelled,
    );
    await stalled.future;
    cancelled = true;

    await expectLater(
        download.timeout(const Duration(seconds: 5)),
        throwsA(predicate((e) => e.toString().contains('cancelled'))));
    expect(File('$finalPath.part').existsSync(), isFalse);
    expect(File(finalPath).existsSync(), isFalse);
  });

  test('reports an HTTP error from the isolate without retrying', () async {
    var requests = 0;
    handler = (request) async {
      requests++;
      request.response.statusCode = 404;
      await request.response.close();
    };

    await expectLater(
      service().downloadFile(
          url: url(), finalPath: p.join(tempDir.path, 'file.pk3')),
      throwsA(predicate((e) => e.toString().contains('404'))),
    );
    expect(requests, 1);
  });
}
