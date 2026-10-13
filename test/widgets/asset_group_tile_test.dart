import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:joflauncher/models/asset.dart';
import 'package:joflauncher/models/asset_group.dart';
import 'package:joflauncher/services/cloud_service.dart';
import 'package:joflauncher/widgets/asset_group_tile.dart';

void main() {
  group('AssetGroupTile', () {
    late AssetGroup testGroup;
    late Asset asset1;
    late Asset asset2;

    setUp(() {
      asset1 = Asset(
        id: 1,
        name: 'asset1.zip',
        size: 1024,
        hash: 'abc123',
        groupId: 1,
        description: 'Asset 1',
        targetFolder: 'target',
        localFolder: 'local',
        lastUpdate: DateTime.now(),
      );

      asset2 = Asset(
        id: 2,
        name: 'asset2.zip',
        size: 2048,
        hash: 'def456',
        groupId: 1,
        description: 'Asset 2',
        targetFolder: 'target',
        localFolder: 'local',
        lastUpdate: DateTime.now(),
      );

      testGroup = AssetGroup(
        id: 1,
        name: 'Test Group',
        description: 'Test Description',
        category: 'modgroups',
        targetFolder: 'target',
        assets: [asset1, asset2],
      );
    });

    Widget createWidget({
      required AssetGroup group,
      required bool isRequired,
      required Set<Asset> selectedAssets,
      required Map<int, AssetStatus> assetStatuses,
      required Function(AssetGroup, bool) onGroupToggle,
      required Function(Asset) onAssetToggle,
      required bool isDownloading,
    }) {
      return MaterialApp(
        home: Scaffold(
          body: AssetGroupTile(
            group: group,
            isRequired: isRequired,
            selectedAssets: selectedAssets,
            assetStatuses: assetStatuses,
            onGroupToggle: onGroupToggle,
            onAssetToggle: onAssetToggle,
            isDownloading: isDownloading,
          ),
        ),
      );
    }

    testWidgets('displays group name', (WidgetTester tester) async {
      await tester.pumpWidget(
        createWidget(
          group: testGroup,
          isRequired: false,
          selectedAssets: {},
          assetStatuses: {},
          onGroupToggle: (_, __) {},
          onAssetToggle: (_) {},
          isDownloading: false,
        ),
      );

      expect(find.text('Test Group'), findsOneWidget);
    });

    testWidgets('displays group category as subtitle', (WidgetTester tester) async {
      await tester.pumpWidget(
        createWidget(
          group: testGroup,
          isRequired: false,
          selectedAssets: {},
          assetStatuses: {},
          onGroupToggle: (_, __) {},
          onAssetToggle: (_) {},
          isDownloading: false,
        ),
      );

      expect(find.text('modgroups'), findsOneWidget);
    });

    testWidgets('shows REQUIRED badge when group is required', (WidgetTester tester) async {
      await tester.pumpWidget(
        createWidget(
          group: testGroup,
          isRequired: true,
          selectedAssets: {},
          assetStatuses: {},
          onGroupToggle: (_, __) {},
          onAssetToggle: (_) {},
          isDownloading: false,
        ),
      );

      expect(find.text('REQUIRED'), findsOneWidget);
    });

    testWidgets('does not show REQUIRED badge when group is not required', (WidgetTester tester) async {
      await tester.pumpWidget(
        createWidget(
          group: testGroup,
          isRequired: false,
          selectedAssets: {},
          assetStatuses: {},
          onGroupToggle: (_, __) {},
          onAssetToggle: (_) {},
          isDownloading: false,
        ),
      );

      expect(find.text('REQUIRED'), findsNothing);
    });

    testWidgets('checkbox is checked when all assets selected', (WidgetTester tester) async {
      await tester.pumpWidget(
        createWidget(
          group: testGroup,
          isRequired: false,
          selectedAssets: {asset1, asset2},
          assetStatuses: {},
          onGroupToggle: (_, __) {},
          onAssetToggle: (_) {},
          isDownloading: false,
        ),
      );

      final checkbox = tester.widget<Checkbox>(find.byType(Checkbox));
      expect(checkbox.value, true);
    });

    testWidgets('checkbox is unchecked when no assets selected', (WidgetTester tester) async {
      await tester.pumpWidget(
        createWidget(
          group: testGroup,
          isRequired: false,
          selectedAssets: {},
          assetStatuses: {},
          onGroupToggle: (_, __) {},
          onAssetToggle: (_) {},
          isDownloading: false,
        ),
      );

      final checkbox = tester.widget<Checkbox>(find.byType(Checkbox));
      expect(checkbox.value, false);
    });

    testWidgets('checkbox is null (indeterminate) when some assets selected', (WidgetTester tester) async {
      await tester.pumpWidget(
        createWidget(
          group: testGroup,
          isRequired: false,
          selectedAssets: {asset1}, // only one of two
          assetStatuses: {},
          onGroupToggle: (_, __) {},
          onAssetToggle: (_) {},
          isDownloading: false,
        ),
      );

      final checkbox = tester.widget<Checkbox>(find.byType(Checkbox));
      expect(checkbox.value, null);
      expect(checkbox.tristate, true);
    });

    testWidgets('checkbox is disabled when group is required', (WidgetTester tester) async {
      await tester.pumpWidget(
        createWidget(
          group: testGroup,
          isRequired: true,
          selectedAssets: {asset1, asset2},
          assetStatuses: {},
          onGroupToggle: (_, __) {},
          onAssetToggle: (_) {},
          isDownloading: false,
        ),
      );

      final checkbox = tester.widget<Checkbox>(find.byType(Checkbox));
      expect(checkbox.onChanged, null);
    });

    testWidgets('checkbox is enabled when group is not required', (WidgetTester tester) async {
      await tester.pumpWidget(
        createWidget(
          group: testGroup,
          isRequired: false,
          selectedAssets: {},
          assetStatuses: {},
          onGroupToggle: (_, __) {},
          onAssetToggle: (_) {},
          isDownloading: false,
        ),
      );

      final checkbox = tester.widget<Checkbox>(find.byType(Checkbox));
      expect(checkbox.onChanged, isNotNull);
    });

    testWidgets('calls onGroupToggle when checkbox tapped', (WidgetTester tester) async {
      AssetGroup? toggledGroup;
      bool? toggledValue;

      await tester.pumpWidget(
        createWidget(
          group: testGroup,
          isRequired: false,
          selectedAssets: {},
          assetStatuses: {},
          onGroupToggle: (group, value) {
            toggledGroup = group;
            toggledValue = value;
          },
          onAssetToggle: (_) {},
          isDownloading: false,
        ),
      );

      await tester.tap(find.byType(Checkbox));
      await tester.pump();

      expect(toggledGroup, testGroup);
      expect(toggledValue, true); // !allSelected
    });

    testWidgets('expands to show child assets', (WidgetTester tester) async {
      await tester.pumpWidget(
        createWidget(
          group: testGroup,
          isRequired: false,
          selectedAssets: {},
          assetStatuses: {
            1: AssetStatus.notDownloaded,
            2: AssetStatus.notDownloaded,
          },
          onGroupToggle: (_, __) {},
          onAssetToggle: (_) {},
          isDownloading: false,
        ),
      );

      // Initially collapsed, assets not visible
      expect(find.text('asset1.zip'), findsNothing);
      expect(find.text('asset2.zip'), findsNothing);

      // Tap to expand
      await tester.tap(find.byType(ExpansionTile));
      await tester.pumpAndSettle();

      // Now assets should be visible
      expect(find.text('asset1.zip'), findsOneWidget);
      expect(find.text('asset2.zip'), findsOneWidget);
    });

    testWidgets('passes correct props to AssetListTile children', (WidgetTester tester) async {
      await tester.pumpWidget(
        createWidget(
          group: testGroup,
          isRequired: false,
          selectedAssets: {asset1},
          assetStatuses: {
            1: AssetStatus.downloaded,
            2: AssetStatus.notDownloaded,
          },
          onGroupToggle: (_, __) {},
          onAssetToggle: (_) {},
          isDownloading: false,
        ),
      );

      // Expand to see children
      await tester.tap(find.byType(ExpansionTile));
      await tester.pumpAndSettle();

      // Check that AssetListTile widgets are created
      expect(find.byType(CheckboxListTile), findsNWidgets(2));
    });

    testWidgets('disables asset tiles when isDownloading is true', (WidgetTester tester) async {
      await tester.pumpWidget(
        createWidget(
          group: testGroup,
          isRequired: false,
          selectedAssets: {},
          assetStatuses: {
            1: AssetStatus.notDownloaded,
            2: AssetStatus.notDownloaded,
          },
          onGroupToggle: (_, __) {},
          onAssetToggle: (_) {},
          isDownloading: true,
        ),
      );

      // Expand to see children
      await tester.tap(find.byType(ExpansionTile));
      await tester.pumpAndSettle();

      // All checkboxes should be disabled
      final checkboxes = tester.widgetList<CheckboxListTile>(
        find.byType(CheckboxListTile),
      );
      for (final checkbox in checkboxes) {
        expect(checkbox.onChanged, null);
      }
    });

    testWidgets('disables asset tiles when group is required', (WidgetTester tester) async {
      await tester.pumpWidget(
        createWidget(
          group: testGroup,
          isRequired: true,
          selectedAssets: {asset1, asset2},
          assetStatuses: {
            1: AssetStatus.notDownloaded,
            2: AssetStatus.notDownloaded,
          },
          onGroupToggle: (_, __) {},
          onAssetToggle: (_) {},
          isDownloading: false,
        ),
      );

      // Expand to see children
      await tester.tap(find.byType(ExpansionTile));
      await tester.pumpAndSettle();

      // All checkboxes should be disabled
      final checkboxes = tester.widgetList<CheckboxListTile>(
        find.byType(CheckboxListTile),
      );
      for (final checkbox in checkboxes) {
        expect(checkbox.onChanged, null);
      }
    });

    testWidgets('calls onAssetToggle when asset is tapped', (WidgetTester tester) async {
      Asset? toggledAsset;

      await tester.pumpWidget(
        createWidget(
          group: testGroup,
          isRequired: false,
          selectedAssets: {},
          assetStatuses: {
            1: AssetStatus.notDownloaded,
            2: AssetStatus.notDownloaded,
          },
          onGroupToggle: (_, __) {},
          onAssetToggle: (asset) {
            toggledAsset = asset;
          },
          isDownloading: false,
        ),
      );

      // Expand to see children
      await tester.tap(find.byType(ExpansionTile));
      await tester.pumpAndSettle();

      // Tap first asset
      await tester.tap(find.text('asset1.zip'));
      await tester.pump();

      expect(toggledAsset, asset1);
    });

    testWidgets('handles empty asset list', (WidgetTester tester) async {
      final emptyGroup = AssetGroup(
        id: 1,
        name: 'Empty Group',
        description: 'No assets',
        category: 'modgroups',
        targetFolder: 'target',
        assets: [],
      );

      await tester.pumpWidget(
        createWidget(
          group: emptyGroup,
          isRequired: false,
          selectedAssets: {},
          assetStatuses: {},
          onGroupToggle: (_, __) {},
          onAssetToggle: (_) {},
          isDownloading: false,
        ),
      );

      expect(find.text('Empty Group'), findsOneWidget);

      // Expand
      await tester.tap(find.byType(ExpansionTile));
      await tester.pumpAndSettle();

      // No asset tiles should be present
      expect(find.byType(CheckboxListTile), findsNothing);
    });

    testWidgets('checkbox reflects all selected state correctly', (WidgetTester tester) async {
      await tester.pumpWidget(
        createWidget(
          group: testGroup,
          isRequired: false,
          selectedAssets: {asset1, asset2},
          assetStatuses: {},
          onGroupToggle: (_, __) {},
          onAssetToggle: (_) {},
          isDownloading: false,
        ),
      );

      final checkbox = tester.widget<Checkbox>(find.byType(Checkbox));
      expect(checkbox.value, true);
    });

    testWidgets('toggles from all selected to none selected', (WidgetTester tester) async {
      bool? lastToggleValue;

      await tester.pumpWidget(
        createWidget(
          group: testGroup,
          isRequired: false,
          selectedAssets: {asset1, asset2}, // all selected
          assetStatuses: {},
          onGroupToggle: (_, value) {
            lastToggleValue = value;
          },
          onAssetToggle: (_) {},
          isDownloading: false,
        ),
      );

      await tester.tap(find.byType(Checkbox));
      await tester.pump();

      expect(lastToggleValue, false); // should deselect
    });

    testWidgets('shows To be Removed for downloaded but unselected assets', (WidgetTester tester) async {
      await tester.pumpWidget(
        createWidget(
          group: testGroup,
          isRequired: false,
          selectedAssets: {}, // None selected
          assetStatuses: {
            1: AssetStatus.downloaded,
          },
          onGroupToggle: (_, __) {},
          onAssetToggle: (_) {},
          isDownloading: false,
        ),
      );

      // Expand to see children
      await tester.tap(find.byType(ExpansionTile));
      await tester.pumpAndSettle();

      expect(find.text('To be Removed'), findsOneWidget);
      expect(find.byIcon(Icons.delete_outline), findsOneWidget);
    });

    testWidgets('shows To be Downloaded for selected but not downloaded assets', (WidgetTester tester) async {
      await tester.pumpWidget(
        createWidget(
          group: testGroup,
          isRequired: false,
          selectedAssets: {asset1}, // Selected
          assetStatuses: {
            1: AssetStatus.notDownloaded,
          },
          onGroupToggle: (_, __) {},
          onAssetToggle: (_) {},
          isDownloading: false,
        ),
      );

      // Expand to see children
      await tester.tap(find.byType(ExpansionTile));
      await tester.pumpAndSettle();

      expect(find.text('To be Downloaded'), findsOneWidget);
      expect(find.byIcon(Icons.download_for_offline), findsOneWidget);
    });

    testWidgets('shows sync problem icon when group has unsynced changes', (WidgetTester tester) async {
      // 1. Needs update
      await tester.pumpWidget(
        createWidget(
          group: testGroup,
          isRequired: false,
          selectedAssets: {asset1},
          assetStatuses: {
            1: AssetStatus.needsUpdate,
          },
          onGroupToggle: (_, __) {},
          onAssetToggle: (_) {},
          isDownloading: false,
        ),
      );
      expect(find.byIcon(Icons.sync_problem), findsOneWidget);

      // 2. To be downloaded
      await tester.pumpWidget(
        createWidget(
          group: testGroup,
          isRequired: false,
          selectedAssets: {asset2},
          assetStatuses: {
            2: AssetStatus.notDownloaded,
          },
          onGroupToggle: (_, __) {},
          onAssetToggle: (_) {},
          isDownloading: false,
        ),
      );
      expect(find.byIcon(Icons.sync_problem), findsOneWidget);

      // 3. To be removed
      await tester.pumpWidget(
        createWidget(
          group: testGroup,
          isRequired: false,
          selectedAssets: {},
          assetStatuses: {
            1: AssetStatus.downloaded,
          },
          onGroupToggle: (_, __) {},
          onAssetToggle: (_) {},
          isDownloading: false,
        ),
      );
      expect(find.byIcon(Icons.sync_problem), findsOneWidget);
    });

    testWidgets('does not show sync problem icon when all assets synced', (WidgetTester tester) async {
      await tester.pumpWidget(
        createWidget(
          group: testGroup,
          isRequired: false,
          selectedAssets: {asset1},
          assetStatuses: {
            1: AssetStatus.downloaded,
          },
          onGroupToggle: (_, __) {},
          onAssetToggle: (_) {},
          isDownloading: false,
        ),
      );
      expect(find.byIcon(Icons.sync_problem), findsNothing);
    });

  });
}
