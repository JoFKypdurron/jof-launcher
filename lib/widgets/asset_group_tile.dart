import 'package:flutter/material.dart';
import '../models/asset.dart';
import '../models/asset_group.dart';
import '../services/cloud_service.dart';
import 'asset_list_tile.dart';

class AssetGroupTile extends StatelessWidget {
  final AssetGroup group;
  final bool isRequired;
  final Set<Asset> selectedAssets;
  final Map<int, AssetStatus> assetStatuses;
  final Function(AssetGroup, bool) onGroupToggle;
  final Function(Asset) onAssetToggle;
  final bool isDownloading;

  const AssetGroupTile({
    super.key,
    required this.group,
    required this.isRequired,
    required this.selectedAssets,
    required this.assetStatuses,
    required this.onGroupToggle,
    required this.onAssetToggle,
    required this.isDownloading,
  });

  @override
  Widget build(BuildContext context) {
    final bool isNarrow = MediaQuery.of(context).size.width < 800;
    final allSelected = group.assets.every((a) => selectedAssets.contains(a));
    final anySelected = group.assets.any((a) => selectedAssets.contains(a));

    final hasUnsyncedChanges = group.assets.any((asset) {
      final status = assetStatuses[asset.id];
      final isSelected = selectedAssets.contains(asset);

      // Same logic as AssetListTile for showing status:
      // 1. Downloaded but not selected (to be removed)
      // 2. Needs update
      // 3. Selected but not downloaded
      if (status == AssetStatus.downloaded || status == AssetStatus.needsUpdate) {
        if (!isSelected) return true;
        if (status == AssetStatus.needsUpdate) return true;
      } else if (status == AssetStatus.stagedDownloaded || status == AssetStatus.stagedForRemoval) {
        return true;
      } else if (isSelected && (status == AssetStatus.notDownloaded || status == null)) {
        return true;
      }
      return false;
    });

    return ExpansionTile(
      visualDensity: isNarrow ? VisualDensity(horizontal: -4, vertical: -2) : null,
      tilePadding: isNarrow
          ? const EdgeInsets.symmetric(horizontal: 8, vertical: 0)
          : null,
      dense: isNarrow,
      title: Row(
        children: [
          Checkbox(
            value: allSelected ? true : (anySelected ? null : false),
            tristate: true,
            onChanged: isRequired
                ? null
                : (_) => onGroupToggle(group, !allSelected),
          ),
          Text(group.name),
          if (hasUnsyncedChanges) ...[
            const SizedBox(width: 8),
            const Icon(
              Icons.sync_problem,
              size: 20,
              color: Colors.orange,
            ),
          ],
          if (isRequired) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.red.shade700,
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text(
                'REQUIRED',
                style: TextStyle(
                  fontSize: 10,
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ],
      ),
      subtitle: Text(group.category),
      children: group.assets.map((asset) {
        final status = assetStatuses[asset.id];
        final isSelected = selectedAssets.contains(asset);
        final isDisabled = isDownloading || isRequired;

        return AssetListTile(
          asset: asset,
          status: status,
          isSelected: isSelected,
          isDisabled: isDisabled,
          onToggle: () => onAssetToggle(asset),
        );
      }).toList(),
    );
  }
}
