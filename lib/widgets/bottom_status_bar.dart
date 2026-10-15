import 'package:flutter/material.dart';

import '../theme/jof_tokens.dart';

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
        return JofColors.border;
      case BottomStatusSeverity.warning:
        return JofColors.warningBorder;
      case BottomStatusSeverity.error:
        return JofColors.dangerBorder;
    }
  }

  Color _backgroundColor() {
    switch (severity) {
      case BottomStatusSeverity.info:
        return JofColors.surface;
      case BottomStatusSeverity.warning:
        return JofColors.warningSurface;
      case BottomStatusSeverity.error:
        return JofColors.dangerSurface;
    }
  }

  Color _accentColor() {
    switch (severity) {
      case BottomStatusSeverity.info:
        return JofColors.highlight;
      case BottomStatusSeverity.warning:
        return JofColors.warning;
      case BottomStatusSeverity.error:
        return JofColors.dangerText;
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          JofSpace.sm,
          0,
          JofSpace.sm,
          JofSpace.sm,
        ),
        child: MouseRegion(
          cursor: onTap != null
              ? SystemMouseCursors.click
              : SystemMouseCursors.basic,
          child: GestureDetector(
            onTap: onTap,
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: JofSpace.md,
                vertical: JofSpace.sm,
              ),
              decoration: BoxDecoration(
                color: _backgroundColor(),
                borderRadius: BorderRadius.circular(JofRadius.sm),
                border: Border.all(color: _borderColor(), width: 2),
                boxShadow: JofShadows.outset,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Icon(icon, size: 22, color: _accentColor()),
                      const SizedBox(width: JofSpace.sm),
                      Expanded(
                        child: Text(
                          message,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: JofColors.text),
                        ),
                      ),
                      if (counterText != null) ...[
                        const SizedBox(width: JofSpace.sm),
                        Text(
                          counterText!,
                          style: JofText.caption.copyWith(
                            color: JofColors.textMuted,
                          ),
                        ),
                      ],
                      if (onClose != null)
                        IconButton(
                          icon: const Icon(
                            Icons.close,
                            size: 20,
                            color: JofColors.textDismiss,
                          ),
                          onPressed: onClose,
                          tooltip: 'Dismiss',
                        ),
                    ],
                  ),
                  if (progress != null) ...[
                    const SizedBox(height: JofSpace.sm),
                    LinearProgressIndicator(
                      value: progress,
                      color: _accentColor(),
                      backgroundColor: JofColors.surfaceInput,
                    ),
                  ],
                  if (overallProgress != null) ...[
                    const SizedBox(height: JofSpace.xs),
                    LinearProgressIndicator(
                      value: overallProgress,
                      minHeight: 2,
                      backgroundColor: JofColors.surfaceInput,
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
