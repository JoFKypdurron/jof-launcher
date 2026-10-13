import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:joflauncher/services/backup_service.dart';
import 'package:joflauncher/controllers/home_view_controller.dart';
import 'package:joflauncher/views/home_view.dart';

void main() {
  testWidgets('HomeView has Launch Game button', (WidgetTester tester) async {
    // We might need to mock services because HomeView fetches data on initState
    // But let's see if it at least pumps without crashing
    final controller = HomeViewController(onStateChanged: () {});
    await tester.pumpWidget(MaterialApp(home: HomeView(controller: controller, initializeOnStart: false)));
    
    // It might be loading initially, so we might need to wait or just check if it's there
    // In HomeView, the button is shown when !_isLoading && !_isDownloading
    // Or in the first Scaffold when _isSettingsMissing && !_isLoading
    
    expect(find.text('Launch Game'), findsOneWidget);
    
    // Verify it's an ElevatedButton with the correct icon
    expect(find.byIcon(Icons.play_arrow), findsOneWidget);
  });

  testWidgets('HomeView shows a warning when the last backup had failures', (WidgetTester tester) async {
    final controller = HomeViewController(onStateChanged: () {});
    controller.lastBackupResult = const BackupRunResult(
      attemptedFiles: 2,
      uploadedFiles: 1,
      skipped: false,
      failures: [
        BackupFailure(filePath: '/tmp/fail.cfg', error: 'boom'),
      ],
    );

    await tester.pumpWidget(MaterialApp(home: HomeView(controller: controller, initializeOnStart: false)));

    expect(find.textContaining('Cloud backup failed'), findsOneWidget);
  });
}
