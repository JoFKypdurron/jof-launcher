import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:joflauncher/services/connectivity_service.dart';

class FakeConnectivity extends Fake implements Connectivity {
  List<ConnectivityResult> current;
  final StreamController<List<ConnectivityResult>> _controller =
      StreamController<List<ConnectivityResult>>.broadcast();

  FakeConnectivity(this.current);

  @override
  Future<List<ConnectivityResult>> checkConnectivity() async => current;

  @override
  Stream<List<ConnectivityResult>> get onConnectivityChanged =>
      _controller.stream;

  void emit(List<ConnectivityResult> results) {
    current = results;
    _controller.add(results);
  }

  Future<void> dispose() => _controller.close();
}

void main() {
  group('ConnectivityService', () {
    test('isOnline reflects the current interface state', () async {
      final online = ConnectivityService(
          connectivity: FakeConnectivity([ConnectivityResult.wifi]));
      final offline = ConnectivityService(
          connectivity: FakeConnectivity([ConnectivityResult.none]));

      expect(await online.isOnline(), isTrue);
      expect(await offline.isOnline(), isFalse);
    });

    test('waitForConnection returns immediately when already online', () async {
      final service = ConnectivityService(
          connectivity: FakeConnectivity([ConnectivityResult.ethernet]));

      await service
          .waitForConnection(isCancelled: () => false)
          .timeout(const Duration(seconds: 1));
    });

    test('waitForConnection completes when connectivity returns', () async {
      final fake = FakeConnectivity([ConnectivityResult.none]);
      final service = ConnectivityService(connectivity: fake);

      final future = service.waitForConnection(isCancelled: () => false);

      // Let the service subscribe, then bring the network back.
      await Future<void>.delayed(const Duration(milliseconds: 20));
      fake.emit([ConnectivityResult.wifi]);

      await future.timeout(const Duration(seconds: 1));
      await fake.dispose();
    });

    test('waitForConnection returns when cancelled while offline', () async {
      final fake = FakeConnectivity([ConnectivityResult.none]);
      final service = ConnectivityService(connectivity: fake);

      var cancelled = false;
      final future = service.waitForConnection(
        isCancelled: () => cancelled,
        pollInterval: const Duration(milliseconds: 20),
      );

      cancelled = true;
      await future.timeout(const Duration(seconds: 1));
      await fake.dispose();
    });
  });
}
