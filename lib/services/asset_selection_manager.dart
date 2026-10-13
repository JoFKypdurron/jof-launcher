import '../models/asset.dart';
import '../models/asset_group.dart';
import 'cloud_service.dart';

class AssetSelectionManager {
  final Set<Asset> selectedAssets = {};
  final Set<AssetGroup> effectiveRequiredGroups = {};
  final Set<int> selectedGroupIds = {};

  void initializeSelections({
    required CloudData data,
    required Map<int, AssetStatus> statuses,
    required List<int>? savedSelections,
    List<int>? savedSelectedGroupIds,
  }) {
    selectedAssets.clear();
    selectedGroupIds
      ..clear()
      ..addAll(savedSelectedGroupIds ?? const []);
    
    // Determine initial selections
    for (var group in data.allGroups) {
      bool isGroupRequired = effectiveRequiredGroups.contains(group);
      final isGroupSelected = selectedGroupIds.contains(group.id);

      for (var asset in group.assets) {
        final status = statuses[asset.id] ?? AssetStatus.notDownloaded;

        if (isGroupRequired || isGroupSelected) {
          selectedAssets.add(asset);
        } else if (savedSelections != null) {
          if (savedSelections.contains(asset.id)) {
            selectedAssets.add(asset);
          }
        } else {
          // First run: auto-select downloaded files
          if (status == AssetStatus.downloaded || status == AssetStatus.needsUpdate || status == AssetStatus.stagedDownloaded) {
            selectedAssets.add(asset);
          }
        }
      }
    }

    // Resolve dependencies for already selected non-required assets
    _resolveDependenciesForSelected(data);
  }

  void calculateEffectiveRequiredGroups(CloudData data) {
    effectiveRequiredGroups.clear();
    for (var group in data.allGroups) {
      if (group.isRequired) {
        effectiveRequiredGroups.addAll(data.resolveDependencies(group));
      }
    }
  }

  void toggleAsset(Asset asset, AssetGroup group, CloudData data) {
    final isSelected = selectedAssets.contains(asset);

    // If group is effectively required, it cannot be deselected
    if (effectiveRequiredGroups.contains(group) && isSelected) {
      return;
    }

    if (isSelected) {
      selectedAssets.remove(asset);

      // If the user previously selected this entire group, deselecting a single
      // asset should break the group selection so it doesn't get re-selected on refresh.
      selectedGroupIds.remove(group.id);
    } else {
      selectedAssets.add(asset);

      // Resolve dependencies
      final deps = data.resolveDependencies(group);
      for (var depGroup in deps) {
        if (depGroup != group) {
          selectedAssets.addAll(depGroup.assets);
        }
      }
    }
  }

  void toggleGroup(AssetGroup group, bool select, CloudData data) {
    final isEffectivelyRequired = effectiveRequiredGroups.contains(group);
    if (isEffectivelyRequired && !select) return;

    if (select) {
      selectedGroupIds.add(group.id);
      selectedAssets.addAll(group.assets);
      final deps = data.resolveDependencies(group);
      for (var depGroup in deps) {
        selectedAssets.addAll(depGroup.assets);
      }
    } else {
      selectedGroupIds.remove(group.id);
      for (var asset in group.assets) {
        selectedAssets.remove(asset);
      }
    }
  }

  List<int> getSelectedGroupIds() {
    return selectedGroupIds.toList();
  }

  ({int downloads, int removals}) getPendingChanges(CloudData data, Map<int, AssetStatus> statuses) {
    int downloads = 0;
    int removals = 0;
    for (var group in data.allGroups) {
      for (var asset in group.assets) {
        final isSelected = selectedAssets.contains(asset);
        final status = statuses[asset.id];
        if (status == null) continue;

        if (isSelected && (status == AssetStatus.notDownloaded || status == AssetStatus.needsUpdate)) {
          downloads++;
        } else if (!isSelected && (status == AssetStatus.downloaded || status == AssetStatus.needsUpdate)) {
          removals++;
        }
      }
    }
    return (downloads: downloads, removals: removals);
  }

  int getPendingChangesCount(CloudData data, Map<int, AssetStatus> statuses) {
    final changes = getPendingChanges(data, statuses);
    return changes.downloads + changes.removals;
  }

  List<int> getSelectedAssetIds() {
    return selectedAssets.map((a) => a.id).toList();
  }

  void _resolveDependenciesForSelected(CloudData data) {
    bool dependenciesAdded;
    do {
      dependenciesAdded = false;
      final currentSelectedAssets = Set<Asset>.from(selectedAssets);
      for (var group in data.allGroups) {
        // If any asset in this group is selected, ensure all dependent groups' assets are selected
        bool anyAssetSelected = group.assets.any((a) => currentSelectedAssets.contains(a));
        if (anyAssetSelected) {
          final deps = data.resolveDependencies(group);
          for (var depGroup in deps) {
            if (depGroup != group) {
              for (var depAsset in depGroup.assets) {
                if (!selectedAssets.contains(depAsset)) {
                  selectedAssets.add(depAsset);
                  dependenciesAdded = true;
                }
              }
            }
          }
        }
      }
    } while (dependenciesAdded);
  }
}
