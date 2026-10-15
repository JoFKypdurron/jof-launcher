import 'dart:async';
import 'package:flutter/material.dart';
import '../models/asset_group.dart';
import '../services/cloud_service.dart';
import '../services/settings_service.dart';
import '../services/asset_selection_manager.dart';
import '../services/asset_verification_service.dart';
import '../services/sync_manager.dart';
import '../services/game_service.dart';
import '../services/server_tracker_service.dart';
import '../services/backup_service.dart';
import '../services/app_exit_service.dart';
import '../services/sync_status_service.dart';
import '../services/self_update_service.dart';
import '../services/url_opener_service.dart';

class HomeViewController {
  final GameService _gameService = GameService();
  final ServerTrackerService _trackerService = ServerTrackerService();
  final CloudService _cloudService = CloudService();
  final SettingsService _settingsService = SettingsService();
  final AppExitService _appExitService;
  final BackupService _backupService;
  final SelfUpdateService _selfUpdateService;
  final UrlOpenerService _urlOpener;
  late final AssetSelectionManager _selectionManager;
  late final AssetVerificationService _verificationService;
  late final SyncManager _syncManager;

  CloudData? cloudData;
  ServerTrackerData? trackerData;
  Timer? _refreshTimer;
  Timer? _gameStatusTimer;

  bool isLaunching = false;
  bool isGameRunning = false;
  bool connectToPublic = false;

  List<AssetGroup> downloadedClientGroups = [];
  AssetGroup? selectedClientGroup;

  List<AssetGroup> downloadedModGroups = [];
  AssetGroup? selectedModGroup;

  bool isCheckingAssets = false;
  double verificationProgress = 0;
  bool isSyncing = false;
  double syncProgress = 0;
  String syncStatus = '';

  bool isGameDataPathAccessible = true;

  bool _isSyncFlowRunning = false;

  // Starts true so staged changes left over from a previous session get
  // applied on startup once no sync is running.
  bool _pendingStagedApply = true;

  BackupRunResult? lastBackupResult;

  final void Function() onStateChanged;

  HomeViewController({
    required this.onStateChanged,
    BackupService? backupService,
    AppExitService? appExitService,
    SelfUpdateService? selfUpdateService,
    UrlOpenerService? urlOpener,
  })  : _backupService = backupService ?? BackupService(),
        _appExitService = appExitService ?? AppExitService(),
        _selfUpdateService = selfUpdateService ?? SelfUpdateService(),
        _urlOpener = urlOpener ?? UrlOpenerService() {
    _selectionManager = AssetSelectionManager();
    _verificationService = AssetVerificationService(_cloudService);
    _syncManager = SyncManager(_cloudService);
  }

  Future<void> initialize() async {
    isGameDataPathAccessible = await _settingsService.isGameDataPathAccessible();
    onStateChanged();

    await _fetchTrackerData();
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (_) => _fetchTrackerData());

    await _checkGameStatus();
    _gameStatusTimer = Timer.periodic(const Duration(seconds: 5), (_) => _checkGameStatus());

    await _loadConnectToPublicSetting();

    // Unawaited on purpose. This is a small GET that touches no game data,
    // while checkAndSyncAssets() below can run for minutes — waiting on that
    // would mean the notice never appears in a normal session.
    unawaited(checkForLauncherUpdate());

    await checkAndSyncAssets();
  }

  /// Result of the most recent launcher update check, or null when there is
  /// nothing to show.
  UpdateCheckResult? updateCheckResult;
  bool updateNoticeDismissed = false;

  bool get hasUpdateNotice =>
      updateCheckResult?.updateAvailable == true && !updateNoticeDismissed;

  Future<void> checkForLauncherUpdate({bool force = false}) async {
    final result = await _selfUpdateService.checkForUpdate(force: force);
    updateCheckResult = result;
    if (force) updateNoticeDismissed = false;
    onStateChanged();
  }

  void dismissUpdateNotice() {
    updateNoticeDismissed = true;
    final version = updateCheckResult?.availableVersion;
    if (version != null) {
      // Fire-and-forget: failing to persist the skip only costs one extra
      // notice next launch.
      unawaited(_selfUpdateService.skipVersion(version));
    }
    onStateChanged();
  }

  /// Opens the release page, for installs that cannot replace themselves.
  Future<bool> openUpdateDownloadPage() async {
    final url = updateCheckResult?.downloadPageUrl;
    if (url == null) return false;
    return _urlOpener.open(url);
  }

  bool isApplyingUpdate = false;
  double updateProgress = 0;
  String updateStatus = '';
  String? updateError;

  /// Downloads and installs the update, then quits so the swap helper can
  /// replace this bundle and relaunch it.
  ///
  /// Returns false when the update could not be applied; the caller should
  /// fall back to the download page.
  Future<bool> applyLauncherUpdate() async {
    if (isApplyingUpdate) return false;

    // The banner already holds a fresh result, but the Info screen runs its own
    // check, so this can be called when our copy is absent or predates the
    // release being installed. Refresh rather than refuse.
    var result = updateCheckResult;
    if (result == null || !result.updateAvailable) {
      await checkForLauncherUpdate(force: true);
      result = updateCheckResult;
    }
    if (result == null || !result.selfUpdateEligible) return false;

    // Replacing the launcher kills it, and SyncManager writes straight into
    // GameData when the game is not running. Quitting mid-write would leave a
    // partially synced game, so wait for any sync to finish first.
    if (isGameRunning) {
      updateError = 'Close the game before updating the launcher.';
      onStateChanged();
      return false;
    }
    if (SyncStatusService.instance.isActive || _isSyncFlowRunning) {
      updateStatus = 'Waiting for sync to finish…';
      isApplyingUpdate = true;
      onStateChanged();
      await SyncStatusService.instance.waitUntilIdle();
    }
    if (_isSyncFlowRunning) {
      isApplyingUpdate = false;
      updateError = 'A sync is still running. Try again in a moment.';
      onStateChanged();
      return false;
    }

    isApplyingUpdate = true;
    updateError = null;
    updateProgress = 0;
    updateStatus = 'Starting update…';
    onStateChanged();

    final outcome = await _selfUpdateService.applyUpdate(
      result,
      onProgress: (value) {
        updateProgress = value;
        onStateChanged();
      },
      onStatus: (status) {
        updateStatus = status;
        onStateChanged();
      },
    );

    if (!outcome.readyToRelaunch) {
      isApplyingUpdate = false;
      updateError = outcome.errorMessage ?? 'Update failed.';
      onStateChanged();
      return false;
    }

    // The helper is already waiting on this process. Give the UI one frame to
    // show the final status, then get out of its way.
    updateStatus = 'Restarting…';
    onStateChanged();
    await Future.delayed(const Duration(milliseconds: 400));
    await _appExitService.requestExit();
    return true;
  }

  void dispose() {
    _refreshTimer?.cancel();
    _gameStatusTimer?.cancel();
  }

  Future<void> _loadConnectToPublicSetting() async {
    connectToPublic = await _settingsService.getConnectToPublic();
    onStateChanged();
  }

  Future<void> refreshTrackerData() async {
    await _fetchTrackerData();
  }

  Future<void> _fetchTrackerData() async {
    trackerData = await _trackerService.fetchTrackerData();
    onStateChanged();
  }

  Future<void> _checkGameStatus() async {
    final isRunning = await _gameService.isGameRunning();
    if (isRunning != isGameRunning) {
      isGameRunning = isRunning;
      onStateChanged();

      if (!isGameRunning) {
        _pendingStagedApply = true;
      }
    }

    // Apply any staged changes once the game closes. While another sync is
    // running, hold off; the periodic game status timer retries this after
    // the sync finishes.
    if (_pendingStagedApply &&
        !isGameRunning &&
        !SyncStatusService.instance.isActive) {
      _pendingStagedApply = false;
      final gameDataPath = await _settingsService.getGameDataPath();
      if (gameDataPath != null && await _syncManager.hasStagedChanges(gameDataPath)) {
        isSyncing = true;
        syncProgress = 0;
        syncStatus = 'Applying staged changes...';
        SyncStatusService.instance.update(message: syncStatus, progress: 0);
        onStateChanged();

        try {
          await _syncManager.applyStagedChanges(
            gameDataPath: gameDataPath,
            onProgress: (name, progress) {
              syncStatus = name;
              syncProgress = progress;
              SyncStatusService.instance
                  .update(message: name, progress: progress);
              onStateChanged();
            },
          );
        } catch (e) {
          if (!e.toString().contains('cancelled')) {
            debugPrint('Error applying staged changes: $e');
          }
        } finally {
          isSyncing = false;
          SyncStatusService.instance.clear();
          onStateChanged();
        }
      }
    }
  }

  Future<void> checkAndSyncAssets() async {
    // Re-entrancy guard: this is called after returning from other views
    // while a previous run may still be in flight.
    if (_isSyncFlowRunning) return;
    _isSyncFlowRunning = true;

    // If a sync started elsewhere (e.g. AssetsView) is still running, let it
    // finish instead of running a conflicting sync against the same
    // GameData directory. The sync keeps going while we wait.
    await SyncStatusService.instance.waitUntilIdle();

    isGameDataPathAccessible = await _settingsService.isGameDataPathAccessible();
    if (!isGameDataPathAccessible) {
      _isSyncFlowRunning = false;
      onStateChanged();
      return;
    }

    final autoProcess = await _settingsService.getAutoProcess();

    lastBackupResult = await _backupService.runBackup();
    onStateChanged();

    if (!autoProcess) {
      _isSyncFlowRunning = false;
      return;
    }

    isCheckingAssets = true;
    verificationProgress = 0;
    SyncStatusService.instance.update(message: 'Verifying assets...', progress: 0);
    onStateChanged();

    try {
      final fetchedData = await _cloudService.fetchCloudData();
      cloudData = fetchedData;
      onStateChanged();

      final gameDataPath = await _settingsService.getGameDataPath();
      final savedSelections = await _settingsService.getSelectedAssets();
      final savedGroupSelections = await _settingsService.getSelectedAssetGroups();

      if (gameDataPath == null) {
        isCheckingAssets = false;
        onStateChanged();
        return;
      }

      _selectionManager.calculateEffectiveRequiredGroups(fetchedData);

      final allAssets = fetchedData.allGroups.expand((g) => g.assets).toList();
      final statuses = await _verificationService.verifyAssets(
        allAssets,
        gameDataPath,
        onProgress: (progress) {
          verificationProgress = progress;
          SyncStatusService.instance
              .update(message: 'Verifying assets...', progress: progress);
          onStateChanged();
        },
      );

      _selectionManager.initializeSelections(
        data: fetchedData,
        statuses: statuses,
        savedSelections: savedSelections,
        savedSelectedGroupIds: savedGroupSelections,
      );

      final downloadedClients = fetchedData.clientGroups.where((group) {
        return group.assets.every((asset) => statuses[asset.id] == AssetStatus.downloaded);
      }).toList();

      // Always use the first client
      final selectedClient = downloadedClients.isNotEmpty ? downloadedClients.first : null;

      final downloadedMods = fetchedData.modGroups.where((group) {
        return group.assets.every((asset) => statuses[asset.id] == AssetStatus.downloaded);
      }).toList();

      // Always use the first mod
      final selectedMod = downloadedMods.isNotEmpty ? downloadedMods.first : null;

      isCheckingAssets = false;
      downloadedClientGroups = downloadedClients;
      selectedClientGroup = selectedClient;
      downloadedModGroups = downloadedMods;
      selectedModGroup = selectedMod;
      onStateChanged();

      await _checkGameStatus();

      final assetsToDownload = _selectionManager.selectedAssets.where((asset) {
        return statuses[asset.id] != AssetStatus.downloaded;
      }).toList();

      final assetsToDelete = allAssets.where((asset) {
        final status = statuses[asset.id];
        return !_selectionManager.selectedAssets.contains(asset) &&
            (status == AssetStatus.downloaded || status == AssetStatus.needsUpdate);
      }).toList();

      // A new client release has to be installed even when no asset changed.
      final clientOutdated = _cloudService.supportsClientFiles &&
          !await _cloudService.isClientUpToDate(gameDataPath);

      if (assetsToDownload.isNotEmpty ||
          assetsToDelete.isNotEmpty ||
          clientOutdated) {
        isSyncing = true;
        syncProgress = 0;
        syncStatus = 'Starting sync...';
        SyncStatusService.instance.update(message: syncStatus, progress: 0);
        onStateChanged();

        await _syncManager.syncAssets(
          toDownload: assetsToDownload,
          toDelete: assetsToDelete,
          gameDataPath: gameDataPath,
          isGameRunning: isGameRunning,
          onProgress: (name, progress) {
            syncStatus = 'Syncing $name...';
            syncProgress = progress;
            SyncStatusService.instance
                .update(message: syncStatus, progress: progress);
            onStateChanged();
          },
          onStatusUpdate: (assetId, status) {
            // Status update happens during sync
          },
          onStatus: (msg) {
            SyncStatusService.instance
                .update(message: msg, progress: syncProgress);
            onStateChanged();
          },
          onQueueProgress: (completed, total) {
            SyncStatusService.instance
                .updateQueue(completed: completed, total: total);
            onStateChanged();
          },
        );
      }
    } catch (e) {
      if (!e.toString().contains('cancelled')) {
        debugPrint('Error during auto-sync: $e');
      }
    } finally {
      isCheckingAssets = false;
      isSyncing = false;
      _isSyncFlowRunning = false;
      SyncStatusService.instance.clear();
      onStateChanged();
    }
  }

  Future<void> launchGame(BuildContext context) async {
    isLaunching = true;
    onStateChanged();

    try {
      await _gameService.launchGame(
        selectedMod: selectedModGroup,
        connectToPublic: connectToPublic,
      );

      final shouldClose = await _settingsService.getAutoCloseOnGameLaunch();
      if (shouldClose) {
        await _appExitService.requestExit();
      }

      await Future.delayed(const Duration(seconds: 10));
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to launch game: $e')),
        );
      }
    } finally {
      isLaunching = false;
      onStateChanged();
      await _checkGameStatus();
    }
  }


  Future<void> setConnectToPublic(bool value) async {
    await _settingsService.setConnectToPublic(value);
    connectToPublic = value;
    onStateChanged();
  }
}
