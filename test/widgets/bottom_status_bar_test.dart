import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:joflauncher/widgets/bottom_status_bar.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  testWidgets('shows only the current progress bar without a queue',
      (WidgetTester tester) async {
    await tester.pumpWidget(wrap(const BottomStatusBar(
      icon: Icons.sync,
      message: 'Syncing a.pk3...',
      progress: 0.4,
    )));

    expect(find.byType(LinearProgressIndicator), findsOneWidget);
  });

  testWidgets('shows the remaining count and an overall bar for a queue',
      (WidgetTester tester) async {
    await tester.pumpWidget(wrap(const BottomStatusBar(
      icon: Icons.sync,
      message: 'Syncing a.pk3...',
      progress: 0.4,
      overallProgress: 0.28,
      counterText: '9 of 12 remaining',
    )));

    expect(find.text('9 of 12 remaining'), findsOneWidget);

    final bars = tester
        .widgetList<LinearProgressIndicator>(find.byType(LinearProgressIndicator))
        .toList();
    expect(bars, hasLength(2));
    expect(bars[0].value, 0.4);
    expect(bars[1].value, 0.28);
  });
}
