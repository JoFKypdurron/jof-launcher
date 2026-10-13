import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../models/asset.dart';
import 'cloud_service.dart';

class SyncManager {
  final CloudService cloudService;
  bool _isCancelled = false;

  static const String _stagingDirName = '.jof_launcher_staging';
  static const String _stagingContentDirName = 'content';
  static const String _stagingManifestFileName = 'manifest.json';

  SyncManager(this.cloudService);

  Future<String?> _detectExistingBaseFolderName(String gameDataPath) async {
    final lower = Directory(p.join(gameDataPath, 'base'));
    if (await lower.exists()) return 'base';
    final upper = Directory(p.join(gameDataPath, 'Base'));
    if (await upper.exists()) return 'Base';
    return null;
  }

  void cancel() {
    _isCancelled = true;
  }

  String _stagingRoot(String gameDataPath) {
    return p.join(p.dirname(gameDataPath), _stagingDirName);
  }

  String _stagingContentRoot(String gameDataPath) {
    return p.join(_stagingRoot(gameDataPath), _stagingContentDirName);
  }

  String _stagingManifestPath(String gameDataPath) {
    return p.join(_stagingRoot(gameDataPath), _stagingManifestFileName);
  }

  Future<bool> hasStagedChanges(String gameDataPath) async {
    return File(_stagingManifestPath(gameDataPath)).exists();
  }

  Future<Map<String, dynamic>> _readStagingManifest(String gameDataPath) async {
    final file = File(_stagingManifestPath(gameDataPath));
    if (!await file.exists()) {
      return <String, dynamic>{
        'version': 1,
        'downloads': <dynamic>[],
        'deletes': <dynamic>[],
      };
    }
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is Map<String, dynamic>) return decoded;
    } catch (_) {
      // Ignore corrupt manifest; will be overwritten.
    }
    return <String, dynamic>{
      'version': 1,
      'downloads': <dynamic>[],
      'deletes': <dynamic>[],
    };
  }

  Future<void> _writeStagingManifest(String gameDataPath, Map<String, dynamic> manifest) async {
    final root = Directory(_stagingRoot(gameDataPath));
    await root.create(recursive: true);
    final file = File(_stagingManifestPath(gameDataPath));
    await file.writeAsString(jsonEncode(manifest));
  }

  List<Map<String, dynamic>> _dedupeByAssetId(List<dynamic> entries) {
    final byId = <int, Map<String, dynamic>>{};
    for (final entry in entries) {
      if (entry is! Map) continue;
      final id = entry['id'];
      if (id is int) {
        byId[id] = Map<String, dynamic>.from(entry as Map);
      }
    }
    return byId.values.toList();
  }

  /// Number of items a sync will work through: every asset it downloads or
  /// removes, plus the single platform client-files step on Linux/macOS.
  int _queueTotal(List<Asset> toDownload, List<Asset> toDelete) {
    final platformStep = (Platform.isLinux || Platform.isMacOS) ? 1 : 0;
    return toDownload.length + toDelete.length + platformStep;
  }

  Future<void> _stageChanges({
    required List<Asset> toDownload,
    required List<Asset> toDelete,
    required String gameDataPath,
    required Function(String name, double progress) onProgress,
    required Function(int assetId, AssetStatus status) onStatusUpdate,
    void Function(String status)? onStatus,
    void Function(int completed, int total)? onQueueProgress,
  }) async {
    final total = _queueTotal(toDownload, toDelete);
    var completed = 0;
    onQueueProgress?.call(completed, total);

    final stagingContentRoot = _stagingContentRoot(gameDataPath);
    await Directory(stagingContentRoot).create(recursive: true);

    // `CloudService.downloadAsset()` has a special guard for `Base` which assumes the
    // folder already exists. For staging we must mirror the real install’s casing
    // (`base` vs `Base`) so downloads land under the correct relative path.
    final needsBase = toDownload.any((a) => a.targetFolder == 'Base');
    if (needsBase) {
      final baseFolderName = await _detectExistingBaseFolderName(gameDataPath);
      if (baseFolderName == null) {
        throw Exception('Target folder "Base" or "base" is missing. Please ensure it exists.');
      }
      await Directory(p.join(stagingContentRoot, baseFolderName)).create(recursive: true);
    }

    final manifest = await _readStagingManifest(gameDataPath);
    final downloads = List<dynamic>.from((manifest['downloads'] as List?) ?? const []);
    final deletes = List<dynamic>.from((manifest['deletes'] as List?) ?? const []);

    for (final asset in toDownload) {
      if (_isCancelled) break;
      onProgress('Staging ${asset.name}', 0);
      await cloudService.downloadAsset(
        asset,
        stagingContentRoot,
        onProgress: (progress) => onProgress('Staging ${asset.name}', progress),
        onStatus: onStatus,
        isCancelled: () => _isCancelled,
      );
      downloads.add({'id': asset.id, 'name': asset.name, 'targetFolder': asset.targetFolder});
      onStatusUpdate(asset.id, AssetStatus.stagedDownloaded);
      onQueueProgress?.call(++completed, total);
    }

    for (final asset in toDelete) {
      if (_isCancelled) break;
      deletes.add({
        'id': asset.id,
        'name': asset.name,
        'size': asset.size,
        'hash': asset.hash,
        'groupId': asset.groupId,
        'description': asset.description,
        'targetFolder': asset.targetFolder,
        'localFolder': asset.localFolder,
        'lastUpdate': asset.lastUpdate.toIso8601String(),
      });
      onStatusUpdate(asset.id, AssetStatus.stagedForRemoval);
      onQueueProgress?.call(++completed, total);
    }

    // Stage platform-specific files too.
    if (!_isCancelled) {
      if (Platform.isLinux) {
        await cloudService.downloadAndExtractLinuxFiles(
          stagingContentRoot,
          onProgress: onProgress,
          onStatus: onStatus,
          isCancelled: () => _isCancelled,
        );
        onQueueProgress?.call(++completed, total);
      } else if (Platform.isMacOS) {
        await cloudService.downloadAndExtractMacosFiles(
          stagingContentRoot,
          onProgress: onProgress,
          onStatus: onStatus,
          isCancelled: () => _isCancelled,
        );
        onQueueProgress?.call(++completed, total);
      }
    }

    manifest['version'] = 1;
    manifest['updatedAt'] = DateTime.now().toIso8601String();
    manifest['downloads'] = _dedupeByAssetId(downloads);
    manifest['deletes'] = _dedupeByAssetId(deletes);

    await _writeStagingManifest(gameDataPath, manifest);
  }

  Future<void> applyStagedChanges({
    required String gameDataPath,
    required Function(String name, double progress) onProgress,
  }) async {
    final root = _stagingRoot(gameDataPath);
    final contentRoot = _stagingContentRoot(gameDataPath);
    final contentDir = Directory(contentRoot);
    if (!await contentDir.exists()) return;

    onProgress('Applying staged changes', 0);

    final manifest = await _readStagingManifest(gameDataPath);
    final deletes = (manifest['deletes'] as List?) ?? const [];

    // Move/copy all staged files into the real gameDataPath.
    final entities = contentDir.list(recursive: true, followLinks: false);
    int processed = 0;
    final all = await entities.toList();
    // Skip leftover `.part` files from a download that was interrupted mid-sync
    // (e.g. an app crash) — they are incomplete and must not be moved into place.
    final files = all.whereType<File>().where((f) => !f.path.endsWith('.part')).toList();

    for (final sourceFile in files) {
      if (_isCancelled) break;
      final relative = p.relative(sourceFile.path, from: contentRoot);
      final destPath = p.join(gameDataPath, relative);
      await _moveFileReplacing(sourceFile, destPath);
      processed++;
      if (files.isNotEmpty) {
        onProgress('Applying staged changes', processed / files.length * 0.9);
      }
    }

    // Apply deletions after staged writes.
    int deleteProcessed = 0;
    for (final entry in deletes) {
      if (_isCancelled) break;
      if (entry is! Map) continue;
      final id = entry['id'];
      final name = entry['name'];
      final size = entry['size'];
      final hash = entry['hash'];
      final groupId = entry['groupId'];
      final description = entry['description'];
      final targetFolder = entry['targetFolder'];
      final localFolder = entry['localFolder'];
      final lastUpdateRaw = entry['lastUpdate'];

      if (id is! int ||
          name is! String ||
          size is! int ||
          hash is! String ||
          groupId is! int ||
          description is! String ||
          targetFolder is! String ||
          localFolder is! String ||
          lastUpdateRaw is! String) {
        continue;
      }

      DateTime lastUpdate;
      try {
        lastUpdate = DateTime.parse(lastUpdateRaw);
      } catch (_) {
        lastUpdate = DateTime.fromMillisecondsSinceEpoch(0);
      }

      final asset = Asset(
        id: id,
        name: name,
        size: size,
        hash: hash,
        groupId: groupId,
        description: description,
        targetFolder: targetFolder,
        localFolder: localFolder,
        lastUpdate: lastUpdate,
      );
      await cloudService.deleteAsset(asset, gameDataPath);
      deleteProcessed++;
      if (deletes.isNotEmpty) {
        onProgress('Applying staged changes', 0.9 + (deleteProcessed / deletes.length * 0.1));
      }
    }

    if (_isCancelled) {
      throw Exception('Sync cancelled');
    }

    // Cleanup staging directory.
    try {
      await Directory(root).delete(recursive: true);
    } catch (_) {
      // Ignore cleanup errors.
    }
    onProgress('Applying staged changes', 1.0);
  }

  Future<void> _moveFileReplacing(File source, String destPath) async {
    final destFile = File(destPath);
    await destFile.parent.create(recursive: true);
    if (await destFile.exists()) {
      await destFile.delete();
    }

    try {
      await source.rename(destPath);
    } on FileSystemException {
      // Likely cross-device rename; fall back to copy+delete.
      await source.copy(destPath);
      try {
        await source.delete();
      } catch (_) {
        // Ignore.
      }
    }
  }

  Future<void> syncAssets({
    required List<Asset> toDownload,
    required List<Asset> toDelete,
    required String gameDataPath,
    required bool isGameRunning,
    required Function(String name, double progress) onProgress,
    required Function(int assetId, AssetStatus status) onStatusUpdate,
    void Function(String status)? onStatus,
    void Function(int completed, int total)? onQueueProgress,
  }) async {
    _isCancelled = false;

    // If the game is running, do not touch the live gameDataPath. Stage changes next to it.
    if (isGameRunning) {
      await _stageChanges(
        toDownload: toDownload,
        toDelete: toDelete,
        gameDataPath: gameDataPath,
        onProgress: onProgress,
        onStatusUpdate: onStatusUpdate,
        onStatus: onStatus,
        onQueueProgress: onQueueProgress,
      );
      return;
    }

    final total = _queueTotal(toDownload, toDelete);
    var completed = 0;
    onQueueProgress?.call(completed, total);

    // If there are staged changes from earlier, apply them first now that the game is closed.
    if (await hasStagedChanges(gameDataPath)) {
      await applyStagedChanges(
        gameDataPath: gameDataPath,
        onProgress: onProgress,
      );
    }

    // 1. Delete assets that are no longer selected
    for (var asset in toDelete) {
      if (_isCancelled) break;
      onProgress('Removing ${asset.name}', 0);
      await cloudService.deleteAsset(asset, gameDataPath);
      onStatusUpdate(asset.id, AssetStatus.notDownloaded);
      onQueueProgress?.call(++completed, total);
    }

    // 2. Download assets that are selected and missing/outdated
    for (var asset in toDownload) {
      if (_isCancelled) break;
      onProgress(asset.name, 0);
      
      await cloudService.downloadAsset(
        asset,
        gameDataPath,
        onProgress: (progress) {
          onProgress(asset.name, progress);
        },
        onStatus: onStatus,
        isCancelled: () => _isCancelled,
      );

      onStatusUpdate(asset.id, AssetStatus.downloaded);
      onQueueProgress?.call(++completed, total);
    }

    // 3. Download and extract Linux or MacOS-specific files
    if (!_isCancelled) {
      if (Platform.isLinux) {
        await cloudService.downloadAndExtractLinuxFiles(
          gameDataPath,
          onProgress: onProgress,
          onStatus: onStatus,
          isCancelled: () => _isCancelled,
        );
        onQueueProgress?.call(++completed, total);
      } else if (Platform.isMacOS) {
        await cloudService.downloadAndExtractMacosFiles(
          gameDataPath,
          onProgress: onProgress,
          onStatus: onStatus,
          isCancelled: () => _isCancelled,
        );
        onQueueProgress?.call(++completed, total);
      }
    }

    if (_isCancelled) {
      throw Exception('Sync cancelled');
    }
  }
}
