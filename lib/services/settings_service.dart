import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:shared_preferences/shared_preferences.dart';

class SettingsService {
  static const String _gameDataPathKey = 'game_data_path';
  static const String _selectedAssetsKey = 'selected_assets';
  static const String _selectedAssetGroupsKey = 'selected_asset_groups';
  static const String _autoProcessKey = 'auto_process';
  static const String _autoCloseOnGameLaunchKey = 'auto_close_on_game_launch';
  static const String _enableCloudBackupKey = 'enable_cloud_backup';
  static const String _cloudBackupIdKey = 'cloud_backup_id';
  static const String _connectToPublicKey = 'connect_to_public';
  static const String _linuxSystemArchKey = 'linux_system_arch';
  static const String _macosSystemArchKey = 'macos_system_arch';
  static const String _clientChannelKey = 'client_channel';
  static const String _repositorySourceKey = 'repository_source';
  static const String _updateCheckEnabledKey = 'update_check_enabled';
  static const String _updateSkippedVersionKey = 'update_skipped_version';
  static const String _updateLastCheckMsKey = 'update_last_check_ms';

  String _generateNewCloudBackupIdHash() {
    final random = Random.secure();
    final values = List<int>.generate(32, (i) => random.nextInt(256));
    return sha256.convert(values).toString();
  }

  Future<bool> setGameDataPath(String? path) async {
    if (path != null && !isValidGameDataPath(path)) {
      return false;
    }
    final prefs = await SharedPreferences.getInstance();
    if (path == null) {
      await prefs.remove(_gameDataPathKey);
    } else {
      await prefs.setString(_gameDataPathKey, path);
    }
    // Access should be fine right after setting, but we can't be 100% sure with sandbox
    // until we actually try to read something, but usually setting via file picker
    // grants immediate access.
    return true;
  }

  bool isValidGameDataPath(String? path) {
    if (path == null) return false;
    final lowerPath = path.toLowerCase();
    final hasGameData = lowerPath.contains('gamedata') || lowerPath.contains('game data');
    if (!hasGameData) return false;

    if (!kIsWeb) {
      return Directory(path).existsSync();
    }
    return true;
  }

  Future<bool> isGameDataPathAccessible() async {
    final path = await getGameDataPath();
    if (path == null) return true; // Not set yet is not "inaccessible" in this context
    if (kIsWeb) return true;
    final dir = Directory(path);
    try {
      return await dir.exists();
    } catch (_) {
      return false;
    }
  }

  Future<String?> getGameDataPath() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_gameDataPathKey);
  }

  Future<void> setSelectedAssets(List<int> assetIds) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_selectedAssetsKey, assetIds.map((id) => id.toString()).toList());
  }

  Future<List<int>?> getSelectedAssets() async {
    final prefs = await SharedPreferences.getInstance();
    final ids = prefs.getStringList(_selectedAssetsKey);
    if (ids == null) return null;
    return ids.map((id) => int.tryParse(id)).whereType<int>().toList();
  }

  Future<void> setSelectedAssetGroups(List<int> groupIds) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_selectedAssetGroupsKey, groupIds.map((id) => id.toString()).toList());
  }

  Future<List<int>?> getSelectedAssetGroups() async {
    final prefs = await SharedPreferences.getInstance();
    final ids = prefs.getStringList(_selectedAssetGroupsKey);
    if (ids == null) return null;
    return ids.map((id) => int.tryParse(id)).whereType<int>().toList();
  }

  Future<void> setAutoProcess(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_autoProcessKey, enabled);
  }

  Future<bool> getAutoProcess() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_autoProcessKey) ?? false;
  }

  Future<void> setAutoCloseOnGameLaunch(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_autoCloseOnGameLaunchKey, enabled);
  }

  Future<bool> getAutoCloseOnGameLaunch() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_autoCloseOnGameLaunchKey) ?? false;
  }

  Future<void> setEnableCloudBackup(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_enableCloudBackupKey, enabled);

    if (enabled) {
      final existingId = prefs.getString(_cloudBackupIdKey);
      if (existingId == null || existingId.isEmpty) {
        final newId = _generateNewCloudBackupIdHash();
        await prefs.setString(_cloudBackupIdKey, newId);
      }
    }
  }

  Future<bool> getEnableCloudBackup() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_enableCloudBackupKey) ?? false;
  }

  Future<void> setCloudBackupId(String id) async {
    final prefs = await SharedPreferences.getInstance();
    // SHA-256 hex string length is 64.
    // If input is already 64 characters long, we assume it's already a hash.
    if (id.length == 64) {
      await prefs.setString(_cloudBackupIdKey, id);
      return;
    }
    final hashedId = sha256.convert(utf8.encode(id)).toString();
    await prefs.setString(_cloudBackupIdKey, hashedId);
  }

  /// Generates and stores a new random backup id hash.
  ///
  /// This rotates the identifier used for cloud backups.
  Future<String> generateNewCloudBackupId() async {
    final prefs = await SharedPreferences.getInstance();
    final newId = _generateNewCloudBackupIdHash();
    await prefs.setString(_cloudBackupIdKey, newId);
    return newId;
  }

  Future<String?> getCloudBackupId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_cloudBackupIdKey);
  }


  Future<void> setConnectToPublic(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_connectToPublicKey, enabled);
  }

  Future<bool> getConnectToPublic() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_connectToPublicKey) ?? false;
  }

  Future<void> setLinuxSystemArch(String persistedValue) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_linuxSystemArchKey, persistedValue);
  }

  Future<String?> getLinuxSystemArch() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_linuxSystemArchKey);
  }

  Future<void> setMacosSystemArch(String persistedValue) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_macosSystemArchKey, persistedValue);
  }

  Future<String?> getMacosSystemArch() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_macosSystemArchKey);
  }

  Future<void> setClientChannel(String persistedValue) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_clientChannelKey, persistedValue);
  }

  Future<String?> getClientChannel() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_clientChannelKey);
  }

  Future<void> setRepositorySource(String persistedValue) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_repositorySourceKey, persistedValue);
  }

  Future<String?> getRepositorySource() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_repositorySourceKey);
  }

  Future<void> setUpdateCheckEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_updateCheckEnabledKey, value);
  }

  /// Defaults to true: users should hear about updates unless they opt out.
  Future<bool> getUpdateCheckEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_updateCheckEnabledKey) ?? true;
  }

  /// Suppresses the notice for one specific version only, so dismissing 1.1.9
  /// does not also hide 1.2.0.
  Future<void> setUpdateSkippedVersion(String? version) async {
    final prefs = await SharedPreferences.getInstance();
    if (version == null) {
      await prefs.remove(_updateSkippedVersionKey);
    } else {
      await prefs.setString(_updateSkippedVersionKey, version);
    }
  }

  Future<String?> getUpdateSkippedVersion() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_updateSkippedVersionKey);
  }

  Future<void> setUpdateLastCheckMs(int millisSinceEpoch) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_updateLastCheckMsKey, millisSinceEpoch);
  }

  Future<int> getUpdateLastCheckMs() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_updateLastCheckMsKey) ?? 0;
  }
}
