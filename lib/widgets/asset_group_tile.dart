import 'package:flutter/material.dart';
import '../models/asset.dart';
import '../models/asset_group.dart';
import '../services/cloud_service.dart';
import '../theme/jof_tokens.dart';
import 'asset_list_tile.dart';
import 'jof/jof_primitives.dart';

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

  /// Whether syncing would change anything on disk for [asset].
  ///
  /// Mirrors the statuses [AssetListTile] shows: downloaded but deselected
  /// (to be removed), needs update, staged, or selected but not downloaded.
  static bool assetHasUnsyncedChange(AssetStatus? status, bool isSelected) {
    if (status == AssetStatus.downloaded || status == AssetStatus.needsUpdate) {
      return !isSelected || status == AssetStatus.needsUpdate;
    }
    if (status == AssetStatus.stagedDownloaded ||
        status == AssetStatus.stagedForRemoval) {
      return true;
    }
    return isSelected &&
        (status == AssetStatus.notDownloaded || status == null);
  }

  /// Number of assets in [group] that a sync would change.
  static int unsyncedChangeCount(
    AssetGroup group,
    Set<Asset> selectedAssets,
    Map<int, AssetStatus> assetStatuses,
  ) {
    return group.assets
        .where(
          (asset) => assetHasUnsyncedChange(
            assetStatuses[asset.id],
            selectedAssets.contains(asset),
          ),
        )
        .length;
  }

  @override
  Widget build(BuildContext context) {
    final isNarrow = MediaQuery.sizeOf(context).width < 600;
    final allSelected = group.assets.every((a) => selectedAssets.contains(a));
    final anySelected = group.assets.any((a) => selectedAssets.contains(a));
    final changes = unsyncedChangeCount(group, selectedAssets, assetStatuses);

    final Widget status;
    if (changes > 0) {
      status = JofStatus(
        icon: Icons.sync_problem,
        iconColor: JofColors.warning,
        label: changes == 1 ? '1 change' : '$changes changes',
      );
    } else if (anySelected) {
      status = const JofStatus(
        icon: Icons.check,
        iconColor: JofColors.highlight,
        label: 'Up to date',
        labelColor: JofColors.textMuted,
      );
    } else {
      status = const Text(
        'Not installed',
        style: TextStyle(color: JofColors.textMuted),
      );
    }

    return ExpansionTile(
      shape: const Border(),
      collapsedShape: const Border(),
      backgroundColor: Colors.transparent,
      collapsedBackgroundColor: Colors.transparent,
      iconColor: JofColors.highlight,
      collapsedIconColor: JofColors.highlight,
      tilePadding: const EdgeInsets.symmetric(horizontal: JofSpace.sm),
      childrenPadding: const EdgeInsets.fromLTRB(
        JofSpace.sm,
        0,
        JofSpace.sm,
        JofSpace.md,
      ),
      title: Row(
        children: [
          Checkbox(
            value: allSelected ? true : (anySelected ? null : false),
            tristate: true,
            onChanged: isRequired
                ? null
                : (_) => onGroupToggle(group, !allSelected),
          ),
          const SizedBox(width: JofSpace.xs),
          Expanded(
            child: Row(
              children: [
                Flexible(
                  child: Text(
                    group.name,
                    overflow: TextOverflow.ellipsis,
                    style: JofText.withWeight(JofText.bodyLg, 500),
                  ),
                ),
                // The tab already says what kind of group this is; on narrow
                // windows the tag would only squeeze the name.
                if (group.category.isNotEmpty && !isNarrow) ...[
                  const SizedBox(width: JofSpace.sm),
                  JofTag(group.category),
                ],
                if (isRequired) ...[
                  const SizedBox(width: JofSpace.xs),
                  const JofTag.danger('Required'),
                ],
              ],
            ),
          ),
          const SizedBox(width: JofSpace.md),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 160),
            child: status,
          ),
        ],
      ),
      children: [
        if (group.assets.isNotEmpty)
          JofWell(
            padding: const EdgeInsets.symmetric(horizontal: JofSpace.md),
            child: Column(
              children: [
                for (var i = 0; i < group.assets.length; i++) ...[
                  if (i > 0) const Divider(),
                  AssetListTile(
                    asset: group.assets[i],
                    status: assetStatuses[group.assets[i].id],
                    isSelected: selectedAssets.contains(group.assets[i]),
                    isDisabled: isDownloading || isRequired,
                    onToggle: () => onAssetToggle(group.assets[i]),
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }
}
