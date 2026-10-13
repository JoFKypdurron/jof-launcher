import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:joflauncher/models/asset.dart';
import 'package:joflauncher/services/cloud_service.dart';
import 'package:joflauncher/widgets/asset_list_tile.dart';

void main() {
  group('AssetListTile', () {
    late Asset testAsset;

    setUp(() {
      testAsset = Asset(
        id: 1,
        name: 'test.zip',
        size: 1024,
        hash: 'abc123',
        groupId: 1,
        description: 'Test asset description',
        targetFolder: 'target',
        localFolder: 'local',
        lastUpdate: DateTime.now(),
      );
    });

    Widget createWidget({
      required Asset asset,
      AssetStatus? status,
      required bool isSelected,
      required bool isDisabled,
      required VoidCallback onToggle,
    }) {
      return MaterialApp(
        home: Scaffold(
          body: AssetListTile(
            asset: asset,
            status: status,
            isSelected: isSelected,
            isDisabled: isDisabled,
            onToggle: onToggle,
          ),
        ),
      );
    }

    testWidgets('displays asset name', (WidgetTester tester) async {
      await tester.pumpWidget(
        createWidget(
          asset: testAsset,
          status: null,
          isSelected: false,
          isDisabled: false,
          onToggle: () {},
        ),
      );

      expect(find.text('test.zip'), findsOneWidget);
    });

    testWidgets('displays asset description', (WidgetTester tester) async {
      await tester.pumpWidget(
        createWidget(
          asset: testAsset,
          status: null,
          isSelected: false,
          isDisabled: false,
          onToggle: () {},
        ),
      );

      expect(find.text('Test asset description'), findsOneWidget);
    });

    testWidgets('shows downloaded status with icon and text', (WidgetTester tester) async {
      await tester.pumpWidget(
        createWidget(
          asset: testAsset,
          status: AssetStatus.downloaded,
          isSelected: true,
          isDisabled: false,
          onToggle: () {},
        ),
      );

      expect(find.text('Downloaded'), findsOneWidget);
      expect(find.byIcon(Icons.check_circle), findsOneWidget);
    });

    testWidgets('shows needs update status with icon and text', (WidgetTester tester) async {
      await tester.pumpWidget(
        createWidget(
          asset: testAsset,
          status: AssetStatus.needsUpdate,
          isSelected: true,
          isDisabled: false,
          onToggle: () {},
        ),
      );

      expect(find.text('Needs update'), findsOneWidget);
      expect(find.byIcon(Icons.update), findsOneWidget);
    });

    testWidgets('does not show status when notDownloaded', (WidgetTester tester) async {
      await tester.pumpWidget(
        createWidget(
          asset: testAsset,
          status: AssetStatus.notDownloaded,
          isSelected: false,
          isDisabled: false,
          onToggle: () {},
        ),
      );

      expect(find.text('Downloaded'), findsNothing);
      expect(find.text('Needs update'), findsNothing);
      expect(find.byIcon(Icons.check_circle), findsNothing);
      expect(find.byIcon(Icons.update), findsNothing);
    });

    testWidgets('does not show status when null', (WidgetTester tester) async {
      await tester.pumpWidget(
        createWidget(
          asset: testAsset,
          status: null,
          isSelected: false,
          isDisabled: false,
          onToggle: () {},
        ),
      );

      expect(find.text('Downloaded'), findsNothing);
      expect(find.text('Needs update'), findsNothing);
    });

    testWidgets('checkbox is checked when selected', (WidgetTester tester) async {
      await tester.pumpWidget(
        createWidget(
          asset: testAsset,
          status: null,
          isSelected: true,
          isDisabled: false,
          onToggle: () {},
        ),
      );

      final checkbox = tester.widget<CheckboxListTile>(
        find.byType(CheckboxListTile),
      );
      expect(checkbox.value, true);
    });

    testWidgets('checkbox is unchecked when not selected', (WidgetTester tester) async {
      await tester.pumpWidget(
        createWidget(
          asset: testAsset,
          status: null,
          isSelected: false,
          isDisabled: false,
          onToggle: () {},
        ),
      );

      final checkbox = tester.widget<CheckboxListTile>(
        find.byType(CheckboxListTile),
      );
      expect(checkbox.value, false);
    });

    testWidgets('calls onToggle when tapped and not disabled', (WidgetTester tester) async {
      bool toggled = false;

      await tester.pumpWidget(
        createWidget(
          asset: testAsset,
          status: null,
          isSelected: false,
          isDisabled: false,
          onToggle: () {
            toggled = true;
          },
        ),
      );

      await tester.tap(find.byType(CheckboxListTile));
      await tester.pump();

      expect(toggled, true);
    });

    testWidgets('does not call onToggle when disabled', (WidgetTester tester) async {
      bool toggled = false;

      await tester.pumpWidget(
        createWidget(
          asset: testAsset,
          status: null,
          isSelected: false,
          isDisabled: true,
          onToggle: () {
            toggled = true;
          },
        ),
      );

      // When disabled, onChanged is null, so tapping won't trigger anything
      final checkbox = tester.widget<CheckboxListTile>(
        find.byType(CheckboxListTile),
      );
      expect(checkbox.onChanged, null);
      expect(toggled, false);
    });

    testWidgets('checkbox is enabled when not disabled', (WidgetTester tester) async {
      await tester.pumpWidget(
        createWidget(
          asset: testAsset,
          status: null,
          isSelected: false,
          isDisabled: false,
          onToggle: () {},
        ),
      );

      final checkbox = tester.widget<CheckboxListTile>(
        find.byType(CheckboxListTile),
      );
      expect(checkbox.onChanged, isNotNull);
    });

    testWidgets('checkbox is disabled when isDisabled is true', (WidgetTester tester) async {
      await tester.pumpWidget(
        createWidget(
          asset: testAsset,
          status: null,
          isSelected: false,
          isDisabled: true,
          onToggle: () {},
        ),
      );

      final checkbox = tester.widget<CheckboxListTile>(
        find.byType(CheckboxListTile),
      );
      expect(checkbox.onChanged, null);
    });

    testWidgets('displays all elements together correctly', (WidgetTester tester) async {
      await tester.pumpWidget(
        createWidget(
          asset: testAsset,
          status: AssetStatus.downloaded,
          isSelected: true,
          isDisabled: false,
          onToggle: () {},
        ),
      );

      expect(find.text('test.zip'), findsOneWidget);
      expect(find.text('Test asset description'), findsOneWidget);
      expect(find.text('Downloaded'), findsOneWidget);
      expect(find.byIcon(Icons.check_circle), findsOneWidget);

      final checkbox = tester.widget<CheckboxListTile>(
        find.byType(CheckboxListTile),
      );
      expect(checkbox.value, true);
      expect(checkbox.onChanged, isNotNull);
    });

    testWidgets('shows To be Removed status when downloaded but not selected', (WidgetTester tester) async {
      await tester.pumpWidget(
        createWidget(
          asset: testAsset,
          status: AssetStatus.downloaded,
          isSelected: false,
          isDisabled: false,
          onToggle: () {},
        ),
      );

      expect(find.text('To be Removed'), findsOneWidget);
      expect(find.byIcon(Icons.delete_outline), findsOneWidget);
    });

    testWidgets('shows To be Removed status when needs update but not selected', (WidgetTester tester) async {
      await tester.pumpWidget(
        createWidget(
          asset: testAsset,
          status: AssetStatus.needsUpdate,
          isSelected: false,
          isDisabled: false,
          onToggle: () {},
        ),
      );

      expect(find.text('To be Removed'), findsOneWidget);
      expect(find.byIcon(Icons.delete_outline), findsOneWidget);
    });

    testWidgets('shows To be Downloaded status when selected but not downloaded', (WidgetTester tester) async {
      await tester.pumpWidget(
        createWidget(
          asset: testAsset,
          status: AssetStatus.notDownloaded,
          isSelected: true,
          isDisabled: false,
          onToggle: () {},
        ),
      );

      expect(find.text('To be Downloaded'), findsOneWidget);
      expect(find.byIcon(Icons.download_for_offline), findsOneWidget);
    });

    testWidgets('shows To be Downloaded status when status is null but selected', (WidgetTester tester) async {
      await tester.pumpWidget(
        createWidget(
          asset: testAsset,
          status: null,
          isSelected: true,
          isDisabled: false,
          onToggle: () {},
        ),
      );

      expect(find.text('To be Downloaded'), findsOneWidget);
      expect(find.byIcon(Icons.download_for_offline), findsOneWidget);
    });

  });
}
