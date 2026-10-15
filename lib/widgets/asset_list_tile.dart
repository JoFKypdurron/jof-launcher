import 'package:flutter/material.dart';
import '../models/asset.dart';
import '../services/cloud_service.dart';
import '../theme/jof_tokens.dart';
import 'jof/jof_primitives.dart';

class AssetListTile extends StatelessWidget {
  final Asset asset;
  final AssetStatus? status;
  final bool isSelected;
  final bool isDisabled;
  final VoidCallback onToggle;

  const AssetListTile({
    super.key,
    required this.asset,
    required this.status,
    required this.isSelected,
    required this.isDisabled,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    String? statusText;
    Color? statusColor;
    Color? labelColor;
    IconData? statusIcon;

    if (status == AssetStatus.downloaded || status == AssetStatus.needsUpdate) {
      if (!isSelected) {
        statusText = 'To be removed';
        statusColor = JofColors.dangerText;
        labelColor = JofColors.dangerText;
        statusIcon = Icons.delete_outline;
      } else if (status == AssetStatus.downloaded) {
        statusText = 'Downloaded';
        statusColor = JofColors.highlight;
        labelColor = JofColors.textMuted;
        statusIcon = Icons.check;
      } else {
        statusText = 'Needs update';
        statusColor = JofColors.warning;
        statusIcon = Icons.update;
      }
    } else if (status == AssetStatus.stagedDownloaded) {
      statusText = 'Staged';
      statusColor = JofColors.highlight;
      statusIcon = Icons.inventory_2_outlined;
    } else if (status == AssetStatus.stagedForRemoval) {
      statusText = 'Staged for removal';
      statusColor = JofColors.warning;
      statusIcon = Icons.inventory_2_outlined;
    } else if (isSelected &&
        (status == AssetStatus.notDownloaded || status == null)) {
      statusText = 'To be downloaded';
      statusColor = JofColors.highlight;
      statusIcon = Icons.download_for_offline;
    }

    return CheckboxListTile(
      contentPadding: EdgeInsets.zero,
      controlAffinity: ListTileControlAffinity.trailing,
      title: Row(
        children: [
          Expanded(
            child: Text(
              asset.name,
              overflow: TextOverflow.ellipsis,
              style: JofText.bodyMedium,
            ),
          ),
          if (statusText != null) ...[
            const SizedBox(width: JofSpace.md),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 180),
              child: JofStatus(
                icon: statusIcon!,
                iconColor: statusColor!,
                label: statusText,
                labelColor: labelColor,
              ),
            ),
          ],
        ],
      ),
      subtitle: Text(
        asset.description,
        style: JofText.caption.copyWith(color: JofColors.textMuted),
      ),
      value: isSelected,
      onChanged: isDisabled ? null : (_) => onToggle(),
    );
  }
}
