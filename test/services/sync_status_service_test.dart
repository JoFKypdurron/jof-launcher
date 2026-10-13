import 'package:flutter_test/flutter_test.dart';
import 'package:joflauncher/services/sync_status_service.dart';

void main() {
  final service = SyncStatusService.instance;

  tearDown(() {
    service.update(message: '', progress: 0);
    service.clear();
  });

  test('has no queue readout before any queue is reported', () {
    service.update(message: 'Verifying assets...', progress: 0.5);

    expect(service.hasQueue, isFalse);
    expect(service.overallProgress, isNull);
    expect(service.queueLabel, isNull);
  });

  test('reports remaining items for the queue', () {
    service.update(message: 'Syncing a.pk3...', progress: 0.5);
    service.updateQueue(completed: 3, total: 12);

    expect(service.completedItems, 3);
    expect(service.totalItems, 12);
    expect(service.remainingItems, 9);
    expect(service.queueLabel, '9 of 12 remaining');
  });

  test('blends the current item progress into the overall progress', () {
    service.update(message: 'Syncing a.pk3...', progress: 0.5);
    service.updateQueue(completed: 1, total: 4);

    // One of four items done, plus half of the second.
    expect(service.overallProgress, closeTo(0.375, 0.0001));
  });

  test('overall progress stays within 0..1 when the last item completes', () {
    service.update(message: 'Syncing a.pk3...', progress: 1.0);
    service.updateQueue(completed: 4, total: 4);

    expect(service.overallProgress, 1.0);
    expect(service.remainingItems, 0);
  });

  test('clear resets the queue', () {
    service.update(message: 'Syncing a.pk3...', progress: 0.5);
    service.updateQueue(completed: 3, total: 12);

    service.clear();

    expect(service.hasQueue, isFalse);
    expect(service.totalItems, 0);
    expect(service.completedItems, 0);
    expect(service.overallProgress, isNull);
  });

  test('notifies listeners when the queue changes', () {
    var notifications = 0;
    void listener() => notifications++;
    service.addListener(listener);
    addTearDown(() => service.removeListener(listener));

    service.updateQueue(completed: 1, total: 2);

    expect(notifications, 1);
  });
}
