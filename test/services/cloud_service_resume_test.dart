import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:joflauncher/models/asset.dart';
import 'package:joflauncher/services/cloud_service.dart';
import 'package:joflauncher/services/connectivity_service.dart';

/// Makes retries instant: reports offline (so the resume path is exercised)
/// but never actually waits for a connectivity event.
class InstantOfflineConnectivity extends ConnectivityService {
  @override
  Future<bool> isOnline() async => false;

  @override
  Future<void> waitForConnection({
    required bool Function() isCancelled,
    Duration pollInterval = const Duration(seconds: 5),
  }) async {}
}

void main() {
  test('resumes an interrupted download from the byte it stopped at', () async {
    final content = List<int>.generate(20, (i) => i);
    final expectedHash = md5.convert(content).toString();

    final tempDir = await Directory.systemTemp.createTemp('jof_resume_test_');
    addTearDown(() => tempDir.delete(recursive: true));

    final asset = Asset(
      id: 1,
      name: 'file.bin',
      size: content.length,
      hash: expectedHash,
      groupId: 1,
      description: '',
      targetFolder: '',
      localFolder: 'repo',
      lastUpdate: DateTime.now(),
    );

    var callCount = 0;
    String? secondRangeHeader;

    final client = MockClient.streaming((request, bodyStream) async {
      callCount++;
      if (callCount == 1) {
        // First attempt: no Range header, deliver half then "drop".
        Stream<List<int>> dropStream() async* {
          yield content.sublist(0, 10);
          throw const SocketException('network changed');
        }

        return http.StreamedResponse(dropStream(), 200,
            contentLength: content.length);
      }

      // Second attempt: must ask for the remainder via Range.
      secondRangeHeader = request.headers['range'];
      final remaining = content.sublist(10);
      return http.StreamedResponse(
        Stream<List<int>>.value(remaining),
        206,
        contentLength: remaining.length,
        headers: {'content-range': 'bytes 10-19/20'},
      );
    });

    final cloud = CloudService(
      connectivity: InstantOfflineConnectivity(),
      httpClientFactory: () => client,
    );

    await cloud.downloadAsset(asset, tempDir.path);

    // Two HTTP attempts: the initial one and the resumed one.
    expect(callCount, 2);
    expect(secondRangeHeader, 'bytes=10-');

    // Final file is complete and correct, with no leftover .part.
    final outFile = File('${tempDir.path}/file.bin');
    expect(await outFile.exists(), isTrue);
    expect(await outFile.readAsBytes(), content);
    expect(await File('${tempDir.path}/file.bin.part').exists(), isFalse);
  });

  test('restarts cleanly when the server ignores Range (200)', () async {
    final content = List<int>.generate(16, (i) => i * 2);
    final expectedHash = md5.convert(content).toString();

    final tempDir = await Directory.systemTemp.createTemp('jof_resume_test2_');
    addTearDown(() => tempDir.delete(recursive: true));

    final asset = Asset(
      id: 2,
      name: 'file2.bin',
      size: content.length,
      hash: expectedHash,
      groupId: 1,
      description: '',
      targetFolder: '',
      localFolder: 'repo',
      lastUpdate: DateTime.now(),
    );

    var callCount = 0;
    final client = MockClient.streaming((request, bodyStream) async {
      callCount++;
      if (callCount == 1) {
        Stream<List<int>> dropStream() async* {
          yield content.sublist(0, 8);
          throw const SocketException('network changed');
        }

        return http.StreamedResponse(dropStream(), 200,
            contentLength: content.length);
      }

      // Server ignores the Range header and returns the whole file again.
      return http.StreamedResponse(
        Stream<List<int>>.value(content),
        200,
        contentLength: content.length,
      );
    });

    final cloud = CloudService(
      connectivity: InstantOfflineConnectivity(),
      httpClientFactory: () => client,
    );

    await cloud.downloadAsset(asset, tempDir.path);

    expect(callCount, 2);
    final outFile = File('${tempDir.path}/file2.bin');
    expect(await outFile.readAsBytes(), content);
  });
}
