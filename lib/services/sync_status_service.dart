import 'dart:async';

import 'package:flutter/foundation.dart';

/// App-wide sync/verification status shared across views so the
/// BottomStatusBar keeps showing ongoing work when the user navigates
/// between views (e.g. HomeView -> AssetsView) while a sync is running.
class SyncStatusService extends ChangeNotifier {
  static final SyncStatusService instance = SyncStatusService._();

  SyncStatusService._();

  bool _isActive = false;
  String _message = '';
  double _progress = 0;
  int _completedItems = 0;
  int _totalItems = 0;

  bool get isActive => _isActive;
  String get message => _message;
  double get progress => _progress;

  /// Items (assets to download/remove, plus the platform client files)
  /// already processed by the running sync, and how many there are in total.
  int get completedItems => _completedItems;
  int get totalItems => _totalItems;
  int get remainingItems {
    final remaining = _totalItems - _completedItems;
    return remaining > 0 ? remaining : 0;
  }

  bool get hasQueue => _totalItems > 0;

  /// Progress across the whole queue, not just the current item. The current
  /// item's own progress is blended in so the bar keeps moving during a long
  /// download instead of only stepping once per asset.
  double? get overallProgress {
    if (_totalItems <= 0) return null;
    final done = _completedItems + _progress.clamp(0.0, 1.0);
    return (done / _totalItems).clamp(0.0, 1.0);
  }

  /// Short label for the queue, e.g. `3 of 12 remaining`. Null when the
  /// running work is not a queue of items (verification, staged apply).
  String? get queueLabel {
    if (!hasQueue) return null;
    return '$remainingItems of $_totalItems remaining';
  }

  void update({required String message, required double progress}) {
    _isActive = true;
    _message = message;
    _progress = progress;
    notifyListeners();
  }

  /// Reports how far the sync has got through its queue of items.
  void updateQueue({required int completed, required int total}) {
    _completedItems = completed;
    _totalItems = total;
    notifyListeners();
  }

  void clear() {
    if (!_isActive) return;
    _isActive = false;
    _message = '';
    _progress = 0;
    _completedItems = 0;
    _totalItems = 0;
    notifyListeners();
  }

  /// Completes once no sync is active. Lets a caller queue its own work
  /// behind a sync that another view started, instead of running a
  /// conflicting sync against the same GameData directory.
  Future<void> waitUntilIdle() async {
    while (_isActive) {
      final completer = Completer<void>();
      void listener() {
        if (!_isActive && !completer.isCompleted) {
          completer.complete();
        }
      }

      addListener(listener);
      try {
        await completer.future;
      } finally {
        removeListener(listener);
      }
    }
  }
}
