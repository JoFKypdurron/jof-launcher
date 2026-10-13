import 'package:flutter/material.dart';
import '../models/asset.dart';
import '../services/cloud_service.dart';

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
    IconData? statusIcon;

    if (status == AssetStatus.downloaded || status == AssetStatus.needsUpdate) {
      if (!isSelected) {
        statusText = 'To be Removed';
        statusColor = Colors.red;
        statusIcon = Icons.delete_outline;
      } else if (status == AssetStatus.downloaded) {
        statusText = 'Downloaded';
        statusColor = Colors.green;
        statusIcon = Icons.check_circle;
      } else {
        statusText = 'Needs update';
        statusColor = Colors.orange;
        statusIcon = Icons.update;
      }
    } else if (status == AssetStatus.stagedDownloaded) {
      statusText = 'Staged';
      statusColor = Colors.purple;
      statusIcon = Icons.inventory_2_outlined;
    } else if (status == AssetStatus.stagedForRemoval) {
      statusText = 'Staged for removal';
      statusColor = Colors.deepOrange;
      statusIcon = Icons.inventory_2_outlined;
    } else if (isSelected && (status == AssetStatus.notDownloaded || status == null)) {
      statusText = 'To be Downloaded';
      statusColor = Colors.blue;
      statusIcon = Icons.download_for_offline;
    }

    final bool isNarrow = MediaQuery.of(context).size.width < 800;

    return CheckboxListTile(
      visualDensity: isNarrow ? VisualDensity(horizontal: -4, vertical: -2) : null,
      contentPadding: isNarrow 
          ? const EdgeInsets.symmetric(horizontal: 8, vertical: 0)
          : null,
      dense: isNarrow,
      title: Row(
        children: [
          Text(asset.name),
          if (statusText != null) ...[
            const SizedBox(width: 8),
            Icon(statusIcon, size: 16, color: statusColor),
            const SizedBox(width: 4),
            Text(
              statusText,
              style: TextStyle(
                fontSize: 12,
                color: statusColor,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ],
      ),
      subtitle: Text(asset.description),
      value: isSelected,
      onChanged: isDisabled ? null : (_) => onToggle(),
    );
  }
}
