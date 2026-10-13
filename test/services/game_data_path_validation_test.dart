import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:joflauncher/services/settings_service.dart';

void main() {
  group('SettingsService GameData Path Validation', () {
    late SettingsService settingsService;
    late String tempPath;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      settingsService = SettingsService();
      tempPath = Directory.systemTemp.createTempSync('jof_test').path;
    });

    tearDown(() {
      final dir = Directory(tempPath);
      if (dir.existsSync()) {
        dir.deleteSync(recursive: true);
      }
    });

    test('accepts path with GameData and exists', () async {
      final path = '$tempPath/GameData';
      Directory(path).createSync();
      await settingsService.setGameDataPath(path);
      expect(await settingsService.getGameDataPath(), path);
    });

    test('accepts path with Game Data and exists', () async {
      final path = '$tempPath/Game Data';
      Directory(path).createSync();
      await settingsService.setGameDataPath(path);
      expect(await settingsService.getGameDataPath(), path);
    });

    test('accepts path with lowercase gamedata and exists', () async {
      final path = '$tempPath/gamedata';
      Directory(path).createSync();
      await settingsService.setGameDataPath(path);
      expect(await settingsService.getGameDataPath(), path);
    });

    test('rejects path without GameData or Game Data even if exists', () async {
      final path = '$tempPath/WrongFolder';
      Directory(path).createSync();
      await settingsService.setGameDataPath(path);
      expect(await settingsService.getGameDataPath(), isNull);
    });

    test('rejects path that does not exist even if contains GameData', () async {
      final path = '$tempPath/NonExistentGameData';
      // Do not create directory
      await settingsService.setGameDataPath(path);
      expect(await settingsService.getGameDataPath(), isNull);
    });
  });
}
