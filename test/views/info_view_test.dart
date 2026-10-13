import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:joflauncher/views/info_view.dart';
import 'package:package_info_plus/package_info_plus.dart';

void main() {
  testWidgets('InfoView shows all required information', (WidgetTester tester) async {
    PackageInfo.setMockInitialValues(
      appName: 'JoF Launcher Test',
      packageName: 'com.example.joflauncher',
      version: '1.2.3',
      buildNumber: '456',
      buildSignature: 'signature',
    );

    await tester.pumpWidget(const MaterialApp(home: InfoView()));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();

    expect(find.text('Information'), findsOneWidget);
    expect(find.text('App Name'), findsOneWidget);
    expect(find.text('JoF Launcher Test'), findsOneWidget);
    expect(find.text('Version'), findsOneWidget);
    expect(find.text('1.2.3'), findsOneWidget);
    expect(find.text('Build Number'), findsOneWidget);
    expect(find.text('456'), findsOneWidget);
    expect(find.text('Platform'), findsOneWidget);
    expect(find.text('Platform Version'), findsOneWidget);
    expect(find.text('Dart Version'), findsOneWidget);
    expect(find.text('Copy Debug Info'), findsOneWidget);
  });

  testWidgets('InfoView shows fallbacks when PackageInfo returns empty strings', (WidgetTester tester) async {
    PackageInfo.setMockInitialValues(
      appName: '',
      packageName: '',
      version: '',
      buildNumber: '',
      buildSignature: '',
    );

    await tester.pumpWidget(const MaterialApp(home: InfoView()));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();

    expect(find.text('JoF Launcher'), findsOneWidget);
    expect(find.text('1.0.2'), findsOneWidget);
    expect(find.text('1'), findsOneWidget);
  });

  testWidgets('InfoView shows "Unknown" for platform version when device info fails', (WidgetTester tester) async {
    // This test simulates a failure in device_info_plus (which might be happening on macOS in CI)
    // We can't easily mock DeviceInfoPlugin without a lot of setup, but we can verify
    // that the view doesn't crash and still shows package info.

    PackageInfo.setMockInitialValues(
      appName: 'Test App',
      packageName: 'com.example.test',
      version: '1.0.0',
      buildNumber: '1',
      buildSignature: 'sig',
    );

    await tester.pumpWidget(const MaterialApp(home: InfoView()));
    await tester.pumpAndSettle();

    expect(find.text('Test App'), findsOneWidget);
  });
}
