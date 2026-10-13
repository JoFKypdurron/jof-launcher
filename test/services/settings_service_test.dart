import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:joflauncher/services/settings_service.dart';

void main() {
  group('SettingsService', () {
    late SettingsService settingsService;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      settingsService = SettingsService();
    });

    test('getGameDataPath returns null when not set', () async {
      final path = await settingsService.getGameDataPath();
      expect(path, isNull);
    });

    test('setGameDataPath and getGameDataPath work correctly', () async {
      final tempPath = Directory.systemTemp.createTempSync('jof_test').path;
      final testPath = '$tempPath/GameData';
      Directory(testPath).createSync();
      
      await settingsService.setGameDataPath(testPath);
      final path = await settingsService.getGameDataPath();
      expect(path, testPath);
      
      Directory(tempPath).deleteSync(recursive: true);
    });

    test('setSelectedAssets and getSelectedAssets work correctly', () async {
      final testIds = [1, 2, 3];
      await settingsService.setSelectedAssets(testIds);
      final ids = await settingsService.getSelectedAssets();
      expect(ids, testIds);
    });

    test('getSelectedAssets returns null when not set', () async {
      final ids = await settingsService.getSelectedAssets();
      expect(ids, isNull);
    });

    test('setSelectedAssetGroups and getSelectedAssetGroups work correctly', () async {
      final testIds = [10, 20, 30];
      await settingsService.setSelectedAssetGroups(testIds);
      final ids = await settingsService.getSelectedAssetGroups();
      expect(ids, testIds);
    });

    test('getSelectedAssetGroups returns null when not set', () async {
      final ids = await settingsService.getSelectedAssetGroups();
      expect(ids, isNull);
    });

    test('getAutoProcess returns false by default', () async {
      final autoProcess = await settingsService.getAutoProcess();
      expect(autoProcess, isFalse);
    });

    test('setAutoProcess and getAutoProcess work correctly', () async {
      await settingsService.setAutoProcess(true);
      expect(await settingsService.getAutoProcess(), isTrue);
      
      await settingsService.setAutoProcess(false);
      expect(await settingsService.getAutoProcess(), isFalse);
    });

    test('getAutoCloseOnGameLaunch returns false by default', () async {
      final autoClose = await settingsService.getAutoCloseOnGameLaunch();
      expect(autoClose, isFalse);
    });

    test('setAutoCloseOnGameLaunch and getAutoCloseOnGameLaunch work correctly', () async {
      await settingsService.setAutoCloseOnGameLaunch(true);
      expect(await settingsService.getAutoCloseOnGameLaunch(), isTrue);

      await settingsService.setAutoCloseOnGameLaunch(false);
      expect(await settingsService.getAutoCloseOnGameLaunch(), isFalse);
    });

    test('enableCloudBackup and cloudBackupId work correctly', () async {
      // Initially disabled
      expect(await settingsService.getEnableCloudBackup(), isFalse);
      expect(await settingsService.getCloudBackupId(), isNull);

      // Enabling generates an ID
      await settingsService.setEnableCloudBackup(true);
      expect(await settingsService.getEnableCloudBackup(), isTrue);
      final id1 = await settingsService.getCloudBackupId();
      expect(id1, isNotNull);
      expect(id1, isNotEmpty);

      // Disabling keeps the ID
      await settingsService.setEnableCloudBackup(false);
      expect(await settingsService.getEnableCloudBackup(), isFalse);
      expect(await settingsService.getCloudBackupId(), id1);

      // Re-enabling keeps the same ID
      await settingsService.setEnableCloudBackup(true);
      expect(await settingsService.getCloudBackupId(), id1);
    });

    test('setCloudBackupId hashes the input if it is not already a hash', () async {
      const testKey = 'my-secret-key';
      final expectedHash = sha256.convert(utf8.encode(testKey)).toString();
      
      await settingsService.setCloudBackupId(testKey);
      final id = await settingsService.getCloudBackupId();
      
      expect(id, expectedHash);
      expect(id, isNot(testKey));
    });

    test('setCloudBackupId does not re-hash if input is already a hash', () async {
      final existingHash = 'a' * 64; // SHA-256 hex string length
      
      await settingsService.setCloudBackupId(existingHash);
      final id = await settingsService.getCloudBackupId();
      
      expect(id, existingHash);
    });

    test('getClientChannel returns null when not set', () async {
      expect(await settingsService.getClientChannel(), isNull);
    });

    test('setClientChannel and getClientChannel round-trip', () async {
      await settingsService.setClientChannel('alpha');
      expect(await settingsService.getClientChannel(), 'alpha');

      await settingsService.setClientChannel('beta');
      expect(await settingsService.getClientChannel(), 'beta');
    });

    test('generateNewCloudBackupId rotates the stored id', () async {
      await settingsService.setEnableCloudBackup(true);
      final id1 = await settingsService.getCloudBackupId();
      expect(id1, isNotNull);

      final id2 = await settingsService.generateNewCloudBackupId();
      expect(id2, isNotEmpty);
      expect(id2, isNot(id1));

      // Persists the new value
      expect(await settingsService.getCloudBackupId(), id2);
    });
  });
}
