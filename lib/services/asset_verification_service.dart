import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import '../models/asset.dart';
import 'cloud_service.dart';

class AssetVerificationService {
  final CloudService cloudService;
  static int get defaultConcurrency => 4;

  Future<Map<int, AssetStatus>>? _activeVerification;
  List<Asset>? _lastAssets;
  String? _lastGameDataPath;
  bool _isCancelled = false;

  AssetVerificationService(this.cloudService);

  void cancel() {
    _isCancelled = true;
  }

  Future<Map<int, AssetStatus>> verifyAssets(
    List<Asset> assets,
    String gameDataPath, {
    Function(double)? onProgress,
    int? concurrency,
  }) async {
    final effectiveConcurrency = concurrency ?? defaultConcurrency;

    // If the same verification is already in progress, return its future
    if (_activeVerification != null &&
        _lastGameDataPath == gameDataPath &&
        _lastAssets != null &&
        _lastAssets!.length == assets.length) {
      // Basic check for asset equality (could be more thorough if needed)
      return _activeVerification!;
    }

    _isCancelled = false;
    _lastAssets = assets;
    _lastGameDataPath = gameDataPath;
    _activeVerification = _verifyAssetsInternal(
      assets,
      gameDataPath,
      onProgress: onProgress,
      concurrency: effectiveConcurrency,
    );

    try {
      return await _activeVerification!;
    } finally {
      _activeVerification = null;
    }
  }

  Future<Map<int, AssetStatus>> _verifyAssetsInternal(
    List<Asset> assets,
    String gameDataPath, {
    Function(double)? onProgress,
    required int concurrency,
  }) async {
    final Map<int, AssetStatus> statuses = {};
    
    // Use unique assets to avoid redundant work
    final uniqueAssets = assets.toSet().toList();
    if (uniqueAssets.isEmpty) return {};

    // Sort by size descending to process larger files first (better concurrency and smoother progress)
    uniqueAssets.sort((a, b) => b.size.compareTo(a.size));

    // Use byte-based progress for smoother updates
    final int totalSize = uniqueAssets.fold(0, (sum, asset) => sum + asset.size);
    int processedSize = 0;
    int processedCount = 0;
    int nextAssetIndex = 0;

    // Verify assets in parallel (limit to specified concurrent files)
    Future<void> verifyWorker() async {
      while (nextAssetIndex < uniqueAssets.length) {
        if (_isCancelled) break;

        final asset = uniqueAssets[nextAssetIndex++];
        try {
          statuses[asset.id] = await cloudService.getAssetStatus(asset, gameDataPath);
        } finally {
          processedCount++;
          processedSize += asset.size;
          if (onProgress != null && !_isCancelled) {
            if (totalSize > 0) {
              onProgress(processedSize / totalSize);
            } else {
              onProgress(processedCount / uniqueAssets.length);
            }
          }
        }
      }
    }

    final workers = <Future<void>>[];
    for (int i = 0; i < concurrency && i < uniqueAssets.length; i++) {
      workers.add(verifyWorker());
    }
    await Future.wait(workers);

    if (_isCancelled) {
      throw Exception('Verification cancelled');
    }

    return statuses;
  }
}
