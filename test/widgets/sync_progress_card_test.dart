import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:joflauncher/widgets/sync_progress_card.dart';

void main() {
  group('SyncProgressCard', () {
    Widget createWidget({
      required String assetName,
      required double progress,
    }) {
      return MaterialApp(
        home: Scaffold(
          body: SyncProgressCard(
            assetName: assetName,
            progress: progress,
          ),
        ),
      );
    }

    testWidgets('displays syncing message for regular asset', (WidgetTester tester) async {
      await tester.pumpWidget(
        createWidget(
          assetName: 'test.zip',
          progress: 0.5,
        ),
      );

      expect(find.text('Syncing test.zip...'), findsOneWidget);
    });

    testWidgets('displays removing message when asset name starts with Removing', (WidgetTester tester) async {
      await tester.pumpWidget(
        createWidget(
          assetName: 'Removing test.zip',
          progress: 0.0,
        ),
      );

      expect(find.text('Removing test.zip...'), findsOneWidget);
    });

    testWidgets('shows progress indicator', (WidgetTester tester) async {
      await tester.pumpWidget(
        createWidget(
          assetName: 'test.zip',
          progress: 0.5,
        ),
      );

      expect(find.byType(LinearProgressIndicator), findsOneWidget);
    });

    testWidgets('progress indicator has correct value', (WidgetTester tester) async {
      await tester.pumpWidget(
        createWidget(
          assetName: 'test.zip',
          progress: 0.75,
        ),
      );

      final progressIndicator = tester.widget<LinearProgressIndicator>(
        find.byType(LinearProgressIndicator),
      );
      expect(progressIndicator.value, 0.75);
    });

    testWidgets('handles 0% progress', (WidgetTester tester) async {
      await tester.pumpWidget(
        createWidget(
          assetName: 'test.zip',
          progress: 0.0,
        ),
      );

      final progressIndicator = tester.widget<LinearProgressIndicator>(
        find.byType(LinearProgressIndicator),
      );
      expect(progressIndicator.value, 0.0);
    });

    testWidgets('handles 100% progress', (WidgetTester tester) async {
      await tester.pumpWidget(
        createWidget(
          assetName: 'test.zip',
          progress: 1.0,
        ),
      );

      final progressIndicator = tester.widget<LinearProgressIndicator>(
        find.byType(LinearProgressIndicator),
      );
      expect(progressIndicator.value, 1.0);
    });

    testWidgets('displays card with padding', (WidgetTester tester) async {
      await tester.pumpWidget(
        createWidget(
          assetName: 'test.zip',
          progress: 0.5,
        ),
      );

      expect(find.byType(Card), findsOneWidget);
      expect(find.byType(Padding), findsWidgets);
    });

    testWidgets('handles long asset names', (WidgetTester tester) async {
      await tester.pumpWidget(
        createWidget(
          assetName: 'very_long_asset_name_that_might_overflow_the_widget.zip',
          progress: 0.5,
        ),
      );

      expect(find.text('Syncing very_long_asset_name_that_might_overflow_the_widget.zip...'), findsOneWidget);
    });

    testWidgets('handles asset name with special characters', (WidgetTester tester) async {
      await tester.pumpWidget(
        createWidget(
          assetName: 'test-file_v1.2.3.zip',
          progress: 0.5,
        ),
      );

      expect(find.text('Syncing test-file_v1.2.3.zip...'), findsOneWidget);
    });

    testWidgets('displays correct message for removing with path', (WidgetTester tester) async {
      await tester.pumpWidget(
        createWidget(
          assetName: 'Removing /path/to/file.zip',
          progress: 0.0,
        ),
      );

      expect(find.text('Removing /path/to/file.zip...'), findsOneWidget);
    });

    testWidgets('handles empty asset name', (WidgetTester tester) async {
      await tester.pumpWidget(
        createWidget(
          assetName: '',
          progress: 0.5,
        ),
      );

      expect(find.text('Syncing ...'), findsOneWidget);
    });

    testWidgets('progress indicator is visible', (WidgetTester tester) async {
      await tester.pumpWidget(
        createWidget(
          assetName: 'test.zip',
          progress: 0.5,
        ),
      );

      final progressIndicator = find.byType(LinearProgressIndicator);
      expect(progressIndicator, findsOneWidget);
      
      final widget = tester.widget<LinearProgressIndicator>(progressIndicator);
      expect(widget.value, isNotNull);
    });

    testWidgets('has proper spacing between text and progress bar', (WidgetTester tester) async {
      await tester.pumpWidget(
        createWidget(
          assetName: 'test.zip',
          progress: 0.5,
        ),
      );

      expect(find.byType(SizedBox), findsWidgets);
    });

    testWidgets('displays all components together', (WidgetTester tester) async {
      await tester.pumpWidget(
        createWidget(
          assetName: 'test.zip',
          progress: 0.5,
        ),
      );

      expect(find.byType(Card), findsOneWidget);
      expect(find.text('Syncing test.zip...'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      expect(find.byType(Column), findsWidgets);
    });

    testWidgets('handles progress values between 0 and 1', (WidgetTester tester) async {
      final progressValues = [0.0, 0.25, 0.5, 0.75, 1.0];

      for (final progress in progressValues) {
        await tester.pumpWidget(
          createWidget(
            assetName: 'test.zip',
            progress: progress,
          ),
        );

        final progressIndicator = tester.widget<LinearProgressIndicator>(
          find.byType(LinearProgressIndicator),
        );
        expect(progressIndicator.value, progress);
      }
    });

    testWidgets('card has proper structure', (WidgetTester tester) async {
      await tester.pumpWidget(
        createWidget(
          assetName: 'test.zip',
          progress: 0.5,
        ),
      );

      // Check hierarchy: Padding -> Card -> Padding -> Column
      final outerPadding = find.ancestor(
        of: find.byType(Card),
        matching: find.byType(Padding),
      );
      expect(outerPadding, findsOneWidget);

      final innerPadding = find.descendant(
        of: find.byType(Card),
        matching: find.byType(Padding),
      );
      expect(innerPadding, findsWidgets); // Multiple Padding widgets inside Card

      final column = find.descendant(
        of: find.byType(Card),
        matching: find.byType(Column),
      );
      expect(column, findsOneWidget);
    });
  });
}
