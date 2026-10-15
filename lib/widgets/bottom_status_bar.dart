import 'package:flutter/material.dart';

enum BottomStatusSeverity { info, warning, error }

class BottomStatusBar extends StatelessWidget {
  final IconData icon;
  final String message;
  final BottomStatusSeverity severity;
  final double? progress;

  /// Progress across all queued work, shown as a slimmer bar under [progress].
  final double? overallProgress;

  /// Short queue readout (e.g. `3 of 12 remaining`) shown next to [message].
  final String? counterText;
  final VoidCallback? onClose;
  final VoidCallback? onTap;

  const BottomStatusBar({
    super.key,
    required this.icon,
    required this.message,
    this.severity = BottomStatusSeverity.info,
    this.progress,
    this.overallProgress,
    this.counterText,
    this.onClose,
    this.onTap,
  });

  Color _borderColor() {
    switch (severity) {
      case BottomStatusSeverity.info:
        return Colors.white24;
      case BottomStatusSeverity.warning:
        return Colors.amber.withValues(alpha: 0.5);
      case BottomStatusSeverity.error:
        return Colors.redAccent.withValues(alpha: 0.6);
    }
  }

  Color _backgroundColor() {
    switch (severity) {
      case BottomStatusSeverity.info:
        return const Color(0xFF03273C);
      case BottomStatusSeverity.warning:
        return Colors.amber.withValues(alpha: 0.12);
      case BottomStatusSeverity.error:
        return Colors.red.withValues(alpha: 0.12);
    }
  }

  Color _accentColor() {
    switch (severity) {
      case BottomStatusSeverity.info:
        return const Color(0xFFA5D8FF);
      case BottomStatusSeverity.warning:
        return Colors.amberAccent;
      case BottomStatusSeverity.error:
        return Colors.redAccent;
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: MouseRegion(
          cursor: onTap != null
              ? SystemMouseCursors.click
              : SystemMouseCursors.basic,
          child: GestureDetector(
            onTap: onTap,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: _backgroundColor(),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: _borderColor()),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Icon(icon, size: 18, color: _accentColor()),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          message,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: severity == BottomStatusSeverity.info
                                ? Colors.white70
                                : _accentColor(),
                          ),
                        ),
                      ),
                      if (counterText != null) ...[
                        const SizedBox(width: 8),
                        Text(
                          counterText!,
                          style: const TextStyle(
                            color: Colors.white54,
                            fontSize: 12,
                          ),
                        ),
                      ],
                      if (onClose != null)
                        IconButton(
                          icon: const Icon(
                            Icons.close,
                            size: 18,
                            color: Colors.white54,
                          ),
                          onPressed: onClose,
                          tooltip: 'Dismiss',
                          constraints: const BoxConstraints(),
                          padding: EdgeInsets.zero,
                        ),
                    ],
                  ),
                  if (progress != null) ...[
                    const SizedBox(height: 8),
                    LinearProgressIndicator(
                      value: progress,
                      backgroundColor: Colors.white10,
                    ),
                  ],
                  if (overallProgress != null) ...[
                    const SizedBox(height: 4),
                    LinearProgressIndicator(
                      value: overallProgress,
                      minHeight: 2,
                      backgroundColor: Colors.white10,
                      color: _accentColor().withValues(alpha: 0.6),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
