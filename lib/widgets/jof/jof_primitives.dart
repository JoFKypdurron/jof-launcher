import 'package:flutter/material.dart';

import '../../theme/jof_tokens.dart';

/// A labelled value with the highlight divider on its left.
class JofStat extends StatelessWidget {
  final String label;
  final Widget value;

  const JofStat({super.key, required this.label, required this.value});

  JofStat.text({super.key, required this.label, required String value})
    : value = Text(value);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.only(left: JofSpace.md),
      decoration: const BoxDecoration(
        border: Border(
          left: BorderSide(color: JofColors.highlight, width: JofSpace.xxs),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label.toUpperCase(),
            style: JofText.statLabel.copyWith(color: JofColors.textMuted),
          ),
          DefaultTextStyle.merge(
            style: JofText.bodyLg.copyWith(color: JofColors.text),
            child: value,
          ),
        ],
      ),
    );
  }
}

/// A recessed area inside a box (`shade` with the inset shadow).
class JofWell extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;

  const JofWell({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.symmetric(
      horizontal: JofSpace.md,
      vertical: JofSpace.sm,
    ),
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: JofColors.shade,
        borderRadius: BorderRadius.circular(JofRadius.sm),
        border: Border.all(color: JofShadows.insetEdge),
      ),
      child: child,
    );
  }
}

/// A small uppercase label such as `MOD` or `REQUIRED`.
class JofTag extends StatelessWidget {
  final String label;
  final Color background;
  final Color foreground;

  const JofTag(
    this.label, {
    super.key,
    this.background = JofColors.surfaceRaised,
    this.foreground = JofColors.textMuted,
  });

  const JofTag.danger(this.label, {super.key})
    : background = JofColors.danger,
      foreground = JofColors.onDanger;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: JofSpace.xs),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(JofRadius.sm),
      ),
      child: Text(
        label.toUpperCase(),
        style: JofText.caption.copyWith(color: foreground, height: 1.6),
      ),
    );
  }
}

/// An icon followed by a short status phrase, e.g. "Needs update".
class JofStatus extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label;
  final Color? labelColor;

  const JofStatus({
    super.key,
    required this.icon,
    required this.iconColor,
    required this.label,
    this.labelColor,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 20, color: iconColor),
        const SizedBox(width: JofSpace.xs),
        Flexible(
          child: Text(
            label,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: labelColor),
          ),
        ),
      ],
    );
  }
}

/// The screen header: surface bar with an uppercase title and icon actions.
class JofTopBar extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final Widget? leading;
  final List<Widget> actions;

  const JofTopBar({
    super.key,
    required this.title,
    this.leading,
    this.actions = const [],
  });

  @override
  Size get preferredSize => const Size.fromHeight(64);

  @override
  Widget build(BuildContext context) {
    final canPop = ModalRoute.of(context)?.canPop ?? false;
    final lead =
        leading ??
        (canPop
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                tooltip: 'Back',
                onPressed: () => Navigator.of(context).maybePop(),
              )
            : null);

    return Container(
      decoration: const BoxDecoration(
        color: JofColors.surface,
        boxShadow: JofShadows.outset,
      ),
      child: SafeArea(
        bottom: false,
        child: SizedBox(
          height: 64,
          child: Padding(
            padding: EdgeInsets.only(
              left: lead == null ? JofSpace.lg : JofSpace.sm,
              right: actions.isEmpty ? JofSpace.lg : JofSpace.sm,
            ),
            child: Row(
              children: [
                if (lead != null) ...[lead, const SizedBox(width: JofSpace.sm)],
                Expanded(
                  child: Semantics(
                    header: true,
                    child: Text(
                      title.toUpperCase(),
                      overflow: TextOverflow.ellipsis,
                      style: JofText.boxHeader.copyWith(color: JofColors.text),
                    ),
                  ),
                ),
                for (final action in actions) ...[
                  const SizedBox(width: JofSpace.xs),
                  action,
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Centres page content at the design system's content width.
class JofContent extends StatelessWidget {
  final Widget child;
  final double maxWidth;

  const JofContent({
    super.key,
    required this.child,
    this.maxWidth = JofSpace.contentWidth,
  });

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Padding(
          padding: const EdgeInsets.all(JofSpace.lg),
          child: child,
        ),
      ),
    );
  }
}

/// Segmented tab strip: raised segments, the selected one filled with
/// highlight. Drives the surrounding [DefaultTabController].
class JofTabBar extends StatelessWidget {
  final List<String> labels;

  const JofTabBar({super.key, required this.labels});

  @override
  Widget build(BuildContext context) {
    final controller = DefaultTabController.of(context);
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        return ClipRRect(
          borderRadius: BorderRadius.circular(JofRadius.sm),
          child: Row(
            children: [
              for (var i = 0; i < labels.length; i++) ...[
                if (i > 0) const SizedBox(width: JofSpace.xxs),
                Expanded(
                  child: _JofTab(
                    label: labels[i],
                    selected: controller.index == i,
                    onTap: () => controller.animateTo(i),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _JofTab extends StatefulWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _JofTab({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  State<_JofTab> createState() => _JofTabState();
}

class _JofTabState extends State<_JofTab> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final selected = widget.selected;
    return Semantics(
      selected: selected,
      button: true,
      child: Material(
        color: selected ? JofColors.highlight : JofColors.surfaceRaised,
        child: InkWell(
          onTap: widget.onTap,
          onHover: (h) => setState(() => _hovered = h),
          child: Container(
            height: 48,
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: JofSpace.xs),
            child: Stack(
              alignment: Alignment.bottomCenter,
              children: [
                Center(
                  child: Text(
                    widget.label.toUpperCase(),
                    overflow: TextOverflow.ellipsis,
                    style: JofText.statLabel.copyWith(
                      color: selected ? JofColors.onHighlight : JofColors.text,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                    ),
                  ),
                ),
                if (_hovered && !selected)
                  const FractionallySizedBox(
                    widthFactor: 0.5,
                    child: SizedBox(
                      height: 2,
                      child: ColoredBox(color: JofColors.highlight),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
