import 'package:flutter/material.dart';

class SyncProgressCard extends StatelessWidget {
  final String assetName;
  final double progress;
  final VoidCallback? onCancel;

  const SyncProgressCard({
    super.key,
    required this.assetName,
    required this.progress,
    this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      assetName.startsWith('Removing')
                          ? '$assetName...'
                          : 'Syncing $assetName...',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (onCancel != null)
                    IconButton(
                      icon: const Icon(
                        Icons.cancel,
                        color: Colors.redAccent,
                        size: 20,
                      ),
                      onPressed: onCancel,
                      tooltip: 'Cancel sync',
                      constraints: const BoxConstraints(),
                      padding: EdgeInsets.zero,
                    ),
                ],
              ),
              const SizedBox(height: 8),
              LinearProgressIndicator(value: progress),
            ],
          ),
        ),
      ),
    );
  }
}
