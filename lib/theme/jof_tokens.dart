import 'package:flutter/painting.dart';

/// Colour tokens from the JoF design system (`project/ds/jof/tokens.json`).
///
/// Names follow the design system so a token can be looked up there for its
/// intended use and contrast ratios.
abstract final class JofColors {
  static const bg = Color(0xFF051720);
  static const surface = Color(0xFF03273C);
  static const surfaceRaised = Color(0xFF003554);
  static const surfaceInput = Color(0xFF021F30);
  static const surfaceDisabled = Color(0x1AFFFFFF);
  static const surfaceButtonDisabled = Color(0x0DFFFFFF);
  static const tintHover = Color(0x1AFFFFFF);
  static const tintSelected = Color(0x33FFFFFF);
  static const shade = Color(0x4D000000);
  static const scrim = Color(0x80000000);
  static const tooltip = Color(0xF2000000);

  static const text = Color(0xFFFFFFFF);
  static const textBody = Color(0xFFE5E5E5);
  static const textMuted = Color(0xFFC8C8C8);
  static const textSubtle = Color(0xFFD3D3D3);
  static const textDisabled = Color(0x54FFFFFF);
  static const textDismiss = Color(0xFF9B9B9B);

  static const highlight = Color(0xFFA5D8FF);
  static const onHighlight = surfaceRaised;
  static const link = highlight;
  static const focusRing = highlight;
  static const border = surfaceRaised;

  static const jofTeal = Color(0xFF00A888);
  static const jofTealBright = Color(0xFF00C8A0);

  static const danger = Color(0xFFDC143C);
  static const dangerText = Color(0xFFF2738C);
  static const onDanger = Color(0xFFFFFFFF);
  static const warning = Color(0xFFFF8C00);
  static const warningStrong = Color(0xFFFF4500);
  static const onWarning = Color(0xFF051720);
  static const success = Color(0xFF008000);
  static const onSuccess = Color(0xFFFFFFFF);
  static const info = Color(0xFF1E90FF);
  static const onInfo = Color(0xFF051720);

  static const dangerSurface = Color(0xBF4C0000);
  static const dangerBorder = Color(0xFFCC0000);
  static const warningSurface = Color(0xBF4C2200);
  static const warningBorder = Color(0xFFCC5C00);
  static const successSurface = Color(0xBF004C00);
  static const successBorder = Color(0xFF00CC00);
  static const infoSurface = Color(0xBF09142A);
  static const infoBorder = Color(0xFF163269);

  /// `rank-member` (palegreen); used as the ring around the online dot.
  static const successRing = Color(0xFF98FB98);
}

/// Spacing scale, in logical pixels.
abstract final class JofSpace {
  static const double xxs = 2;
  static const double xs = 5;
  static const double sm = 10;
  static const double md = 15;
  static const double lg = 20;
  static const double xl = 30;
  static const double xxl = 50;

  /// Minimum edge of anything clickable.
  static const double touchTarget = 44;

  /// Box width on desktop; wider windows centre the content.
  static const double contentWidth = 1140;
}

abstract final class JofRadius {
  /// THE radius: boxes, buttons, inputs, tab bars, toasts, dialogs, tags.
  static const double sm = 4;
  static const double md = 5;
  static const double lg = 6;
  static const double xl = 8;
}

abstract final class JofShadows {
  static const outset = [
    BoxShadow(color: Color(0x4D000000), blurRadius: 10, spreadRadius: 1),
  ];

  /// Flutter has no inset shadow; [JofWell] approximates it with a border.
  static const insetEdge = Color(0x40000000);
}

/// Type scale. Sizes are in the design system's rem (16px).
abstract final class JofText {
  static const headingFamily = 'Rajdhani';
  static const bodyFamily = 'Saira';

  // Saira ships as a variable font; weight has to be set on the axis as well
  // or every weight renders as the default instance.
  static List<FontVariation> _wght(double w) => [FontVariation('wght', w)];

  static TextStyle _heading(double size, double height, FontWeight weight) =>
      TextStyle(
        fontFamily: headingFamily,
        fontSize: size,
        height: height,
        fontWeight: weight,
      );

  static TextStyle _body(double size, double height, double weight) =>
      TextStyle(
        fontFamily: bodyFamily,
        fontSize: size,
        height: height,
        fontWeight: FontWeight.values[(weight ~/ 100) - 1],
        fontVariations: _wght(weight),
      );

  /// App and screen titles in the top bar, box headers, tab labels.
  /// Always uppercase.
  static final boxHeader = _heading(27.2, 1.2, FontWeight.w500);

  /// Stat labels and secondary headings. Uppercase.
  static final statLabel = _heading(20.8, 1.2, FontWeight.w500);

  /// Buttons. Uppercase.
  static final buttonLabel = _heading(19.2, 1.2, FontWeight.w500);

  /// Rare emphasis inside box content.
  static final headingStrong = _heading(20.8, 1.2, FontWeight.w600);

  /// Highlighted notifications, stat values.
  static final bodyLg = _body(17.6, 1.45, 400);

  /// All box content and form fields.
  static final body = _body(16, 1.5, 400);

  /// Names and list item titles.
  static final bodyMedium = _body(16, 1.4, 500);

  /// Timestamps, helper text, tags.
  static final caption = _body(12.8, 1.35, 400);

  /// Fine print.
  static final small = _body(11.2, 1.35, 400);
}
