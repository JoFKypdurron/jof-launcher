import 'package:flutter/material.dart';

import '../../theme/jof_tokens.dart';

/// A titled panel: the design system's "box".
///
/// Surface-coloured body under a diagonally striped header holding an
/// uppercase title and optional trailing actions.
class JofBox extends StatelessWidget {
  final String title;
  final Widget child;
  final List<Widget> actions;

  /// Pads the body with the box's default content inset.
  final bool padded;

  /// Stretches the body to fill the box's height; needs a bounded height.
  final bool expand;

  const JofBox({
    super.key,
    required this.title,
    required this.child,
    this.actions = const [],
    this.padded = true,
    this.expand = false,
  });

  @override
  Widget build(BuildContext context) {
    Widget body = padded
        ? Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: JofSpace.sm,
              vertical: JofSpace.md,
            ),
            child: child,
          )
        : child;
    if (expand) body = Expanded(child: body);

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: const BoxDecoration(
        color: JofColors.surface,
        borderRadius: BorderRadius.all(Radius.circular(JofRadius.sm)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
        children: [
          JofStripedHeader(title: title, actions: actions),
          body,
        ],
      ),
    );
  }
}

/// The striped title strip at the top of a [JofBox].
class JofStripedHeader extends StatelessWidget {
  final String title;
  final List<Widget> actions;

  const JofStripedHeader({
    super.key,
    required this.title,
    this.actions = const [],
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: const _StripePainter(),
      child: Padding(
        padding: EdgeInsets.only(
          left: JofSpace.sm,
          right: actions.isEmpty ? JofSpace.sm : 0,
        ),
        child: Row(
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: JofSpace.xs),
                child: Semantics(
                  header: true,
                  child: Text(
                    title.toUpperCase(),
                    style: JofText.boxHeader.copyWith(color: JofColors.text),
                  ),
                ),
              ),
            ),
            ...actions,
          ],
        ),
      ),
    );
  }
}

/// `repeating-linear-gradient(45deg, surface 0 2.5px, surface-raised 2.5px 5px)`.
class _StripePainter extends CustomPainter {
  const _StripePainter();

  static const double _band = 2.5;
  // Distance between stripe starts measured along the x axis for 45°.
  static const double _step = _band * 2 * 1.41421356;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(rect, Paint()..color = JofColors.surface);
    canvas.save();
    canvas.clipRect(rect);
    final paint = Paint()
      ..color = JofColors.surfaceRaised
      ..strokeWidth = _band
      ..isAntiAlias = true;
    for (double x = -size.height; x < size.width + size.height; x += _step) {
      canvas.drawLine(
        Offset(x, size.height),
        Offset(x + size.height, 0),
        paint,
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
