import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:path/path.dart' as p;

import '../services/backup_service.dart';
import '../services/settings_service.dart';

class BackupRestoreViewController {
  final SettingsService _settingsService;
  final BackupService _backupService;

  final void Function() onStateChanged;

  bool isLoading = false;
  String? errorMessage;

  String? gameDataPath;
  String? cloudBackupId;

  List<RemoteBackupFile> remoteFiles = const [];
  final Set<String> selectedFilenames = {};

  BackupRestoreViewController({
    required this.onStateChanged,
    SettingsService? settingsService,
    BackupService? backupService,
  })  : _settingsService = settingsService ?? SettingsService(),
        _backupService = backupService ?? BackupService();

  Future<void> load() async {
    if (kIsWeb) {
      errorMessage = 'Restoring backups is not supported on web.';
      onStateChanged();
      return;
    }

    isLoading = true;
    errorMessage = null;
    onStateChanged();

    try {
      gameDataPath = await _settingsService.getGameDataPath();
      cloudBackupId = await _settingsService.getCloudBackupId();

      if (gameDataPath == null || gameDataPath!.isEmpty) {
        errorMessage = 'GameData location is not configured.';
        remoteFiles = const [];
        selectedFilenames.clear();
        return;
      }
      if (cloudBackupId == null || cloudBackupId!.isEmpty) {
        errorMessage = 'Cloud Backup ID is not configured.';
        remoteFiles = const [];
        selectedFilenames.clear();
        return;
      }

      remoteFiles = await _backupService.listRemoteBackupFileEntries(backupId: cloudBackupId!);

      // Keep selection only for files that still exist.
      final available = remoteFiles.map((e) => e.filename).toSet();
      selectedFilenames.removeWhere((f) => !available.contains(f));
    } catch (e) {
      errorMessage = 'Failed to load remote backups: $e';
      remoteFiles = const [];
      selectedFilenames.clear();
    } finally {
      isLoading = false;
      onStateChanged();
    }
  }

  void toggleSelected(String filename, bool selected) {
    if (selected) {
      selectedFilenames.add(filename);
    } else {
      selectedFilenames.remove(filename);
    }
    onStateChanged();
  }

  void selectAll() {
    selectedFilenames
      ..clear()
      ..addAll(remoteFiles.map((e) => e.filename));
    onStateChanged();
  }

  void selectNone() {
    selectedFilenames.clear();
    onStateChanged();
  }

  Future<RestoreResult> restoreSelected() async {
    if (kIsWeb) return const RestoreResult.error('Restoring backups is not supported on web.');
    if (selectedFilenames.isEmpty) return const RestoreResult.error('No files selected.');

    final gd = gameDataPath ?? await _settingsService.getGameDataPath();
    final id = cloudBackupId ?? await _settingsService.getCloudBackupId();
    if (gd == null || id == null) {
      return const RestoreResult.error('Missing GameData path or Backup ID.');
    }

    final eternalJKDir = Directory(p.join(gd, 'EternalJK'));
    if (!await eternalJKDir.exists()) {
      return RestoreResult.error('Folder not found: ${eternalJKDir.path}');
    }

    final restored = <String, String>{};
    final failures = <String, Object>{};

    for (final filename in selectedFilenames) {
      try {
        final destination = BackupService.resolveRestoreDestination(
          eternalJKDirectory: eternalJKDir,
          filename: filename,
        );
        await _backupService.restoreRemoteBackupFile(
          backupId: id,
          filename: filename,
          destinationFile: destination,
        );
        restored[filename] = p.basename(destination.path);
      } catch (e) {
        failures[filename] = e;
      }
    }

    return RestoreResult(
      restored: restored,
      failures: failures,
    );
  }
}

class RestoreResult {
  final Map<String, String> restored;
  final Map<String, Object> failures;
  final String? errorMessage;

  const RestoreResult({
    required this.restored,
    required this.failures,
    this.errorMessage,
  });

  const RestoreResult.error(this.errorMessage)
      : restored = const {},
        failures = const {};

  bool get isOk => errorMessage == null;
}
