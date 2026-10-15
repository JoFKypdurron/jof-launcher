import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:file_picker/file_picker.dart';
import '../models/client_channel.dart';
import '../models/platform_arch.dart';
import '../models/repository_source.dart';
import '../services/log_service.dart';
import '../services/settings_service.dart';
import '../services/system_arch_service.dart';

class SettingsViewController {
  final SettingsService _settingsService = SettingsService();
  final SystemArchService _systemArch = SystemArchService();

  String? gameDataPath;
  bool autoProcess = false;
  bool autoCloseOnGameLaunch = false;
  bool updateCheckEnabled = true;
  bool enableCloudBackup = false;
  String? cloudBackupId;

  LinuxSystemArch linuxSystemArch = LinuxSystemArch.bit64;
  MacosSystemArch? macosSystemArch;
  bool macosSystemArchNeedsSelection = false;
  ClientChannel clientChannel = ClientChannel.stable;
  RepositorySource repositorySource = RepositorySource.auto;
  String? logFilePath;

  final void Function() onStateChanged;

  SettingsViewController({required this.onStateChanged});

  Future<void> loadSettings() async {
    gameDataPath = await _settingsService.getGameDataPath();
    autoProcess = await _settingsService.getAutoProcess();
    autoCloseOnGameLaunch = await _settingsService.getAutoCloseOnGameLaunch();
    updateCheckEnabled = await _settingsService.getUpdateCheckEnabled();
    enableCloudBackup = await _settingsService.getEnableCloudBackup();
    cloudBackupId = await _settingsService.getCloudBackupId();
    clientChannel = ClientChannelCodec.tryParse(await _settingsService.getClientChannel()) ??
        ClientChannel.stable;
    repositorySource = RepositorySourceCodec.tryParse(
            await _settingsService.getRepositorySource()) ??
        RepositorySource.auto;

    // Publish settings-derived state immediately so the UI (and widget tests) can
    // reflect preferences even if platform detection is slow.
    onStateChanged();

    logFilePath = await LogService.instance.logFilePath();

    if (!kIsWeb && Platform.isLinux) {
      linuxSystemArch = await _systemArch.resolveLinux();
    }

    if (!kIsWeb && Platform.isMacOS) {
      // Resolved through the same service the download and launch use, so the
      // architecture shown here is the one the client is actually installed
      // for. Only an unresolvable machine falls back to asking the user.
      macosSystemArch = await _systemArch.resolveMacos();
      macosSystemArchNeedsSelection = macosSystemArch == null;
    }

    onStateChanged();
  }

  Future<void> setLinuxSystemArch(LinuxSystemArch value) async {
    await _settingsService.setLinuxSystemArch(value.persistedValue);
    linuxSystemArch = value;
    onStateChanged();
  }

  Future<void> setMacosSystemArch(MacosSystemArch value) async {
    await _settingsService.setMacosSystemArch(value.persistedValue);
    macosSystemArch = value;
    macosSystemArchNeedsSelection = false;
    onStateChanged();
  }

  Future<void> setClientChannel(ClientChannel value) async {
    await _settingsService.setClientChannel(value.persistedValue);
    clientChannel = value;
    onStateChanged();
  }

  Future<void> setRepositorySource(RepositorySource value) async {
    await _settingsService.setRepositorySource(value.persistedValue);
    repositorySource = value;
    onStateChanged();
  }

  Future<PickDirectoryResult> pickDirectory() async {
    String? selectedDirectory = await FilePicker.platform.getDirectoryPath();

    if (selectedDirectory != null) {
      final success = await _settingsService.setGameDataPath(selectedDirectory);
      if (success) {
        gameDataPath = selectedDirectory;
        onStateChanged();
        return PickDirectoryResult.success();
      } else {
        String errorMessage = 'Selected directory must contain "GameData" or "Game Data"';
        if (!kIsWeb && !Directory(selectedDirectory).existsSync()) {
          errorMessage = 'Selected directory does not exist';
        }
        return PickDirectoryResult.error(errorMessage);
      }
    }
    return PickDirectoryResult.cancelled();
  }

  String? getGameDataPathError(String? path) {
    if (path == null || path.isEmpty) return 'No location selected';
    final lowerPath = path.toLowerCase();
    final hasGameData = lowerPath.contains('gamedata') || lowerPath.contains('game data');
    if (!hasGameData) return 'Must contain "GameData" or "Game Data"';
    if (!kIsWeb && !Directory(path).existsSync()) return 'Directory does not exist';
    return null;
  }

  Future<void> setGameDataPath(String? path) async {
    await _settingsService.setGameDataPath(path);
    gameDataPath = path;
    onStateChanged();
  }

  Future<void> setAutoProcess(bool value) async {
    await _settingsService.setAutoProcess(value);
    autoProcess = value;
    onStateChanged();
  }

  Future<void> setAutoCloseOnGameLaunch(bool value) async {
    await _settingsService.setAutoCloseOnGameLaunch(value);
    autoCloseOnGameLaunch = value;
    onStateChanged();
  }

  Future<void> setUpdateCheckEnabled(bool value) async {
    await _settingsService.setUpdateCheckEnabled(value);
    updateCheckEnabled = value;
    onStateChanged();
  }

  Future<void> setEnableCloudBackup(bool value) async {
    await _settingsService.setEnableCloudBackup(value);
    enableCloudBackup = value;
    onStateChanged();
  }

  Future<void> changeCloudBackupId(String newId) async {
    await _settingsService.setCloudBackupId(newId);
    cloudBackupId = await _settingsService.getCloudBackupId();
    onStateChanged();
  }

  Future<void> generateNewCloudBackupId() async {
    cloudBackupId = await _settingsService.generateNewCloudBackupId();
    onStateChanged();
  }
}

class PickDirectoryResult {
  final bool isSuccess;
  final bool isCancelled;
  final String? errorMessage;

  PickDirectoryResult.success()
      : isSuccess = true,
        isCancelled = false,
        errorMessage = null;

  PickDirectoryResult.cancelled()
      : isSuccess = false,
        isCancelled = true,
        errorMessage = null;

  PickDirectoryResult.error(this.errorMessage)
      : isSuccess = false,
        isCancelled = false;
}
