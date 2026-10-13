import '../models/asset.dart';
import '../models/asset_group.dart';
import '../services/cloud_service.dart';
import '../services/settings_service.dart';
import '../services/asset_selection_manager.dart';
import '../services/asset_verification_service.dart';
import '../services/sync_manager.dart';
import '../services/game_service.dart';
import '../services/sync_status_service.dart';

class AssetsViewController {
  final CloudService _cloudService = CloudService();
  final SettingsService _settingsService = SettingsService();
  final GameService _gameService = GameService();
  late final AssetSelectionManager _selectionManager;
  late final AssetVerificationService _verificationService;
  late final SyncManager _syncManager;

  CloudData? data;
  Map<int, AssetStatus> assetStatuses = {};
  String? gameDataPath;
  bool isLoading = true;
  bool _isFetching = false;
  bool isSettingsMissing = false;
  String? errorMessage;
  bool isDownloading = false;
  double downloadProgress = 0;
  String downloadingAssetName = '';
  double verificationProgress = 0;

  final void Function() onStateChanged;

  AssetsViewController({required this.onStateChanged}) {
    _selectionManager = AssetSelectionManager();
    _verificationService = AssetVerificationService(_cloudService);
    _syncManager = SyncManager(_cloudService);
  }

  AssetSelectionManager get selectionManager => _selectionManager;

  Future<void> fetchData({bool forceVerify = false}) async {
    if (_isFetching) return;
    _isFetching = true;

    isLoading = true;
    errorMessage = null;
    verificationProgress = 0;
    onStateChanged();

    try {
      final fetchedData = await _cloudService.fetchCloudData();
      final fetchedGameDataPath = await _settingsService.getGameDataPath();
      final savedSelections = await _settingsService.getSelectedAssets();
      final savedGroupSelections = await _settingsService.getSelectedAssetGroups();

      final pathChanged = fetchedGameDataPath != gameDataPath;
      Map<int, AssetStatus> statuses = pathChanged ? {} : assetStatuses;
      bool settingsMissing = fetchedGameDataPath == null;

      if (fetchedGameDataPath != null) {
        _selectionManager.calculateEffectiveRequiredGroups(fetchedData);

        if (forceVerify || statuses.isEmpty) {
          final allAssets = fetchedData.allGroups.expand((g) => g.assets).toList();
          statuses = await _verificationService.verifyAssets(
            allAssets,
            fetchedGameDataPath,
            onProgress: (progress) {
              verificationProgress = progress;
              onStateChanged();
            },
          );
        }

        _selectionManager.initializeSelections(
          data: fetchedData,
          statuses: statuses,
          savedSelections: savedSelections,
          savedSelectedGroupIds: savedGroupSelections,
        );
      }

      data = fetchedData;
      assetStatuses = statuses;
      gameDataPath = fetchedGameDataPath;
      isSettingsMissing = settingsMissing;
      isLoading = false;
      onStateChanged();

      if (!settingsMissing) {
        await _settingsService.setSelectedAssets(_selectionManager.getSelectedAssetIds());
        await _settingsService.setSelectedAssetGroups(_selectionManager.getSelectedGroupIds());
      }
    } catch (e) {
      if (e.toString().contains('cancelled')) {
        isLoading = false;
        onStateChanged();
        return;
      }
      errorMessage = e.toString();
      isLoading = false;
      onStateChanged();
    } finally {
      _isFetching = false;
    }
  }

  Future<void> toggleAssetSelection(Asset asset) async {
    if (isSettingsMissing) return;
    final group = data?.allGroups.firstWhere((g) => g.assets.contains(asset));
    if (group == null || data == null) return;

    _selectionManager.toggleAsset(asset, group, data!);
    onStateChanged();

    await _settingsService.setSelectedAssets(_selectionManager.getSelectedAssetIds());
    await _settingsService.setSelectedAssetGroups(_selectionManager.getSelectedGroupIds());
  }

  Future<void> toggleGroupSelection(AssetGroup group, bool select) async {
    if (isSettingsMissing || data == null) return;

    _selectionManager.toggleGroup(group, select, data!);
    onStateChanged();

    await _settingsService.setSelectedAssets(_selectionManager.getSelectedAssetIds());
    await _settingsService.setSelectedAssetGroups(_selectionManager.getSelectedGroupIds());
  }

  int get pendingChangesCount {
    if (data == null) return 0;
    return _selectionManager.getPendingChangesCount(data!, assetStatuses);
  }

  String get pendingChangesText {
    if (data == null) return '0';
    final changes = _selectionManager.getPendingChanges(data!, assetStatuses);
    return '+${changes.downloads} / -${changes.removals}';
  }

  Future<SyncResult> startSync() async {
    if (SyncStatusService.instance.isActive) {
      return const SyncResult(
          SyncResultType.error, 'Another sync is already in progress');
    }

    final fetchedGameDataPath = await _settingsService.getGameDataPath();
    if (fetchedGameDataPath == null) {
      return SyncResult(SyncResultType.settingsMissing);
    }

    final allAssets = data?.allGroups.expand((g) => g.assets).toList() ?? [];
    final assetsToDownload = _selectionManager.selectedAssets.where((asset) {
      return assetStatuses[asset.id] != AssetStatus.downloaded;
    }).toList();
    final assetsToDelete = allAssets.where((asset) {
      final status = assetStatuses[asset.id];
      return !_selectionManager.selectedAssets.contains(asset) &&
          (status == AssetStatus.downloaded || status == AssetStatus.needsUpdate);
    }).toList();

    if (assetsToDownload.isEmpty && assetsToDelete.isEmpty) {
      return SyncResult(SyncResultType.alreadyInSync);
    }

    isDownloading = true;
    SyncStatusService.instance.update(message: 'Starting sync...', progress: 0);
    onStateChanged();

    try {
      final isGameRunning = await _gameService.isGameRunning();
      await _syncManager.syncAssets(
        toDownload: assetsToDownload,
        toDelete: assetsToDelete,
        gameDataPath: fetchedGameDataPath,
        isGameRunning: isGameRunning,
        onProgress: (name, progress) {
          downloadingAssetName = name;
          downloadProgress = progress;
          SyncStatusService.instance.update(
            message: name.startsWith('Removing')
                ? '$name...'
                : 'Syncing $name...',
            progress: progress,
          );
          onStateChanged();
        },
        onStatusUpdate: (assetId, status) {
          assetStatuses[assetId] = status;
          onStateChanged();
        },
        onStatus: (msg) {
          SyncStatusService.instance
              .update(message: msg, progress: downloadProgress);
          onStateChanged();
        },
        onQueueProgress: (completed, total) {
          SyncStatusService.instance
              .updateQueue(completed: completed, total: total);
          onStateChanged();
        },
      );

      return SyncResult(SyncResultType.success);
    } catch (e) {
      if (e.toString().contains('cancelled')) {
        return SyncResult(SyncResultType.cancelled);
      }
      return SyncResult(SyncResultType.error, e.toString());
    } finally {
      isDownloading = false;
      downloadingAssetName = '';
      downloadProgress = 0;
      SyncStatusService.instance.clear();
      onStateChanged();
    }
  }
}

enum SyncResultType {
  success,
  settingsMissing,
  alreadyInSync,
  cancelled,
  error,
}

class SyncResult {
  final SyncResultType type;
  final String? errorMessage;

  const SyncResult(this.type, [this.errorMessage]);
}
