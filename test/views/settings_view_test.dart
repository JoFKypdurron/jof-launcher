import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:joflauncher/services/backup_service.dart';
import 'package:joflauncher/views/settings_view.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    BackupService.featureEnabled = true;
  });

  tearDown(() {
    BackupService.featureEnabled = false;
  });

  testWidgets('SettingsView hides the Cloud Backup section while the feature is off', (WidgetTester tester) async {
    BackupService.featureEnabled = false;
    SharedPreferences.setMockInitialValues({'enable_cloud_backup': true, 'cloud_backup_id': 'test-id-123'});

    await tester.pumpWidget(const MaterialApp(home: SettingsView()));
    await tester.pumpAndSettle();

    expect(find.text('Cloud Backup'), findsNothing);
    expect(find.text('Enable encrypted cloud backup'), findsNothing);
    expect(find.text('Current Backup ID:'), findsNothing);
  });

  testWidgets('SettingsView shows Automation section and auto process toggle', (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: SettingsView()));
    await tester.pumpAndSettle();

    expect(find.text('Automation'), findsOneWidget);
    expect(find.text('Automatically process assets on start'), findsOneWidget);
    expect(find.widgetWithText(SwitchListTile, 'Automatically process assets on start'), findsOneWidget);
  });

  testWidgets('SettingsView shows Cloud Backup section and enable toggle', (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: SettingsView()));
    await tester.pumpAndSettle();

    expect(find.text('Cloud Backup'), findsOneWidget);
    expect(find.text('Enable encrypted cloud backup'), findsOneWidget);
    expect(find.widgetWithText(SwitchListTile, 'Enable encrypted cloud backup'), findsOneWidget);
    expect(find.text('Backup .cfg files to Cloud, end to end encrypted'), findsOneWidget);
  });

  testWidgets('SettingsView shows Backup ID and CHANGE button when cloud backup enabled', (WidgetTester tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('enable_cloud_backup', true);
      await prefs.setString('cloud_backup_id', 'test-id-123');

      await tester.pumpWidget(const MaterialApp(home: SettingsView()));
      await tester.pumpAndSettle();

      expect(find.text('Current Backup ID:'), findsOneWidget);
      expect(find.text('test-id-123'), findsOneWidget);
      expect(find.text('CHANGE'), findsNWidgets(2)); // One for GameData, one for Backup ID
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('clicking CHANGE Backup ID button shows dialog', (WidgetTester tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('enable_cloud_backup', true);
      await prefs.setString('cloud_backup_id', 'test-id-123');

      await tester.pumpWidget(const MaterialApp(home: SettingsView()));
      await tester.pumpAndSettle();

      final changeButton = find.byKey(SettingsView.cloudBackupChangeButtonKey);
      await tester.ensureVisible(changeButton);
      await tester.tap(changeButton);
      await tester.pumpAndSettle();

      expect(find.text('Change Backup ID'), findsOneWidget);
      expect(find.text('Enter a new Backup Key. This will be hashed to create your unique Backup ID.'), findsOneWidget);
      expect(find.descendant(of: find.byType(AlertDialog), matching: find.byType(TextField)), findsOneWidget);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('typing in download path TextField updates settings', (WidgetTester tester) async {
    final tempPath = Directory.systemTemp.createTempSync('jof_view_test').path;
    final testPath = '$tempPath/GameData';
    Directory(testPath).createSync();

    await tester.pumpWidget(const MaterialApp(home: SettingsView()));
    await tester.pumpAndSettle();

    final textField = find.byType(TextField).first;
    await tester.enterText(textField, testPath);
    await tester.pumpAndSettle();

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('game_data_path'), testPath);

    Directory(tempPath).deleteSync(recursive: true);
  });

  testWidgets('invalid download path shows error message', (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: SettingsView()));
    await tester.pumpAndSettle();

    final textField = find.byType(TextField).first;
    await tester.enterText(textField, '/invalid/path');
    await tester.pumpAndSettle();

    expect(find.text('Must contain "GameData" or "Game Data"'), findsOneWidget);
  });


  testWidgets(
    'SettingsView shows the client channel dropdown and persists a Beta pick',
    (WidgetTester tester) async {
      await tester.pumpWidget(const MaterialApp(home: SettingsView()));
      await tester.pumpAndSettle();

      final dropdown = find.byKey(SettingsView.clientChannelDropdownKey);
      expect(dropdown, findsOneWidget);
      expect(find.text('Latest stable'), findsOneWidget);

      await tester.tap(dropdown);
      await tester.pumpAndSettle();

      // Two matches once the menu is open: the closed field and the menu item.
      await tester.tap(find.text('Beta (test build)').last);
      await tester.pumpAndSettle();

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('client_channel'), 'beta');
    },
    skip: !Platform.isLinux && !Platform.isMacOS && !Platform.isWindows,
  );

  testWidgets('SettingsView persists the download source pick', (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: SettingsView()));
    await tester.pumpAndSettle();

    final dropdown = find.byKey(SettingsView.repositorySourceDropdownKey);
    expect(dropdown, findsOneWidget);
    expect(find.text('Auto (JoF Cloud, fall back to jofhub.eu)'), findsOneWidget);

    await tester.ensureVisible(dropdown);
    await tester.tap(dropdown);
    await tester.pumpAndSettle();

    await tester.tap(find.text('jofhub.eu only').last);
    await tester.pumpAndSettle();

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('repository_source'), 'origin');
  });

  testWidgets('clearing download path TextField removes it from settings', (WidgetTester tester) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('game_data_path', '/old/path');

    await tester.pumpWidget(const MaterialApp(home: SettingsView()));
    await tester.pumpAndSettle();

    final textField = find.byType(TextField).first;
    await tester.enterText(textField, '');
    await tester.pumpAndSettle();

    expect(prefs.getString('game_data_path'), isNull);
  });
}
