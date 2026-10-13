import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';

/// Thin wrapper around `connectivity_plus` used by the download layer to wait
/// for the network to come back before resuming an interrupted download.
///
/// `connectivity_plus` reports interface state (wifi/ethernet/none), not actual
/// internet reachability, so this is only a *hint* used to retry sooner. The
/// real safety net against a half-open socket is the download stream's idle
/// timeout in [CloudService].
///
/// The public methods are overridable and a [Connectivity] instance can be
/// injected, so tests can supply a fake instead of touching the platform.
class ConnectivityService {
  final Connectivity _connectivity;

  ConnectivityService({Connectivity? connectivity})
      : _connectivity = connectivity ?? Connectivity();

  static bool _isConnected(List<ConnectivityResult> results) {
    return results.any((r) => r != ConnectivityResult.none);
  }

  /// Whether any network interface currently looks connected. On error we
  /// assume online so the caller still attempts a retry rather than waiting
  /// forever.
  Future<bool> isOnline() async {
    try {
      final results = await _connectivity.checkConnectivity();
      return _isConnected(results);
    } catch (_) {
      return true;
    }
  }

  /// Completes once a connected interface is available, or as soon as
  /// [isCancelled] returns true. Listens for connectivity changes and also
  /// polls on [pollInterval] as a backstop in case no event fires.
  Future<void> waitForConnection({
    required bool Function() isCancelled,
    Duration pollInterval = const Duration(seconds: 5),
  }) async {
    if (isCancelled() || await isOnline()) return;

    final completer = Completer<void>();
    StreamSubscription<List<ConnectivityResult>>? sub;
    Timer? poll;

    void finish() {
      if (completer.isCompleted) return;
      sub?.cancel();
      poll?.cancel();
      completer.complete();
    }

    sub = _connectivity.onConnectivityChanged.listen((results) {
      if (isCancelled() || _isConnected(results)) finish();
    }, onError: (_) {});

    poll = Timer.periodic(pollInterval, (_) async {
      if (isCancelled() || await isOnline()) finish();
    });

    return completer.future;
  }
}
