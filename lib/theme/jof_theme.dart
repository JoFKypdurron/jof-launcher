import 'package:flutter/material.dart';

import 'jof_tokens.dart';

/// Material theme mapped onto the JoF design system tokens.
///
/// Stock Material widgets (dialogs, inputs, dropdowns, switches, snack bars)
/// pick their look up from here; the JoF-specific pieces (boxes, stats, the
/// top bar) live in `lib/widgets/jof/`.
ThemeData buildJofTheme() {
  const scheme = ColorScheme(
    brightness: Brightness.dark,
    primary: JofColors.highlight,
    onPrimary: JofColors.onHighlight,
    secondary: JofColors.highlight,
    onSecondary: JofColors.onHighlight,
    error: JofColors.dangerText,
    onError: JofColors.bg,
    surface: JofColors.surface,
    onSurface: JofColors.text,
    onSurfaceVariant: JofColors.textMuted,
    surfaceContainerHighest: JofColors.surfaceRaised,
    surfaceContainerHigh: JofColors.surfaceRaised,
    surfaceContainer: JofColors.surface,
    surfaceContainerLow: JofColors.surface,
    surfaceContainerLowest: JofColors.surfaceInput,
    outline: JofColors.highlight,
    outlineVariant: JofColors.border,
    shadow: Colors.black,
    scrim: JofColors.scrim,
    inverseSurface: JofColors.highlight,
    onInverseSurface: JofColors.onHighlight,
  );

  final base = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: scheme,
    fontFamily: JofText.bodyFamily,
  );

  final textTheme = base.textTheme
      .copyWith(
        headlineSmall: JofText.boxHeader,
        titleLarge: JofText.boxHeader,
        titleMedium: JofText.bodyLg,
        titleSmall: JofText.bodyMedium,
        bodyLarge: JofText.body,
        bodyMedium: JofText.body,
        bodySmall: JofText.caption,
        labelLarge: JofText.buttonLabel,
        labelMedium: JofText.caption,
        labelSmall: JofText.small,
      )
      .apply(bodyColor: JofColors.text, displayColor: JofColors.text);

  const radius = BorderRadius.all(Radius.circular(JofRadius.sm));
  const shape = RoundedRectangleBorder(borderRadius: radius);

  // Primary buttons: raised fill, highlight fill with dark text on hover.
  final buttonStyle = ButtonStyle(
    minimumSize: const WidgetStatePropertyAll(Size(64, JofSpace.touchTarget)),
    padding: const WidgetStatePropertyAll(
      EdgeInsets.symmetric(horizontal: JofSpace.lg),
    ),
    shape: const WidgetStatePropertyAll(shape),
    elevation: const WidgetStatePropertyAll(0),
    textStyle: WidgetStatePropertyAll(JofText.buttonLabel),
    backgroundColor: WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.disabled)) {
        return JofColors.surfaceButtonDisabled;
      }
      if (states.contains(WidgetState.hovered) ||
          states.contains(WidgetState.focused)) {
        return JofColors.highlight;
      }
      return JofColors.surfaceRaised;
    }),
    foregroundColor: WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.disabled)) return JofColors.textDisabled;
      if (states.contains(WidgetState.hovered) ||
          states.contains(WidgetState.focused)) {
        return JofColors.onHighlight;
      }
      return JofColors.text;
    }),
    iconColor: WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.disabled)) return JofColors.textDisabled;
      if (states.contains(WidgetState.hovered) ||
          states.contains(WidgetState.focused)) {
        return JofColors.onHighlight;
      }
      return JofColors.text;
    }),
    overlayColor: const WidgetStatePropertyAll(Colors.transparent),
    animationDuration: const Duration(milliseconds: 100),
  );

  // Secondary and dismiss actions: plain text, `text-dismiss` grey.
  final textButtonStyle = ButtonStyle(
    minimumSize: const WidgetStatePropertyAll(Size(64, JofSpace.touchTarget)),
    padding: const WidgetStatePropertyAll(
      EdgeInsets.symmetric(horizontal: JofSpace.md),
    ),
    shape: const WidgetStatePropertyAll(shape),
    textStyle: WidgetStatePropertyAll(JofText.buttonLabel),
    foregroundColor: WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.disabled)) return JofColors.textDisabled;
      if (states.contains(WidgetState.hovered)) return JofColors.text;
      return JofColors.textDismiss;
    }),
    overlayColor: const WidgetStatePropertyAll(JofColors.tintHover),
  );

  final outlinedButtonStyle = buttonStyle.copyWith(
    side: const WidgetStatePropertyAll(
      BorderSide(color: JofColors.highlight, width: 2),
    ),
  );

  return base.copyWith(
    scaffoldBackgroundColor: JofColors.bg,
    canvasColor: JofColors.surface,
    textTheme: textTheme,
    primaryTextTheme: textTheme,
    dividerColor: JofColors.border,
    hoverColor: JofColors.tintHover,
    focusColor: JofColors.tintHover,
    splashFactory: NoSplash.splashFactory,
    highlightColor: Colors.transparent,
    iconTheme: const IconThemeData(color: JofColors.highlight, size: 24),
    dividerTheme: const DividerThemeData(
      color: JofColors.border,
      thickness: 2,
      space: 2,
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: JofColors.surface,
      foregroundColor: JofColors.text,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      toolbarHeight: 64,
      iconTheme: const IconThemeData(color: JofColors.highlight),
      actionsIconTheme: const IconThemeData(color: JofColors.highlight),
      titleTextStyle: JofText.boxHeader.copyWith(color: JofColors.text),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(style: buttonStyle),
    filledButtonTheme: FilledButtonThemeData(style: buttonStyle),
    outlinedButtonTheme: OutlinedButtonThemeData(style: outlinedButtonStyle),
    textButtonTheme: TextButtonThemeData(style: textButtonStyle),
    iconButtonTheme: IconButtonThemeData(
      style: ButtonStyle(
        minimumSize: const WidgetStatePropertyAll(
          Size(JofSpace.touchTarget, JofSpace.touchTarget),
        ),
        shape: const WidgetStatePropertyAll(shape),
        foregroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) {
            return JofColors.textDisabled;
          }
          return JofColors.highlight;
        }),
        backgroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) return Colors.transparent;
          if (states.contains(WidgetState.hovered) ||
              states.contains(WidgetState.focused)) {
            return JofColors.surfaceRaised;
          }
          return Colors.transparent;
        }),
        overlayColor: const WidgetStatePropertyAll(Colors.transparent),
      ),
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: JofColors.surfaceRaised,
      foregroundColor: JofColors.text,
      hoverColor: JofColors.highlight,
      elevation: 0,
      shape: shape,
    ),
    checkboxTheme: CheckboxThemeData(
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(3)),
      ),
      side: WidgetStateBorderSide.resolveWith((states) {
        if (states.contains(WidgetState.disabled)) {
          return const BorderSide(color: JofColors.textDisabled, width: 2);
        }
        return const BorderSide(color: JofColors.highlight, width: 2);
      }),
      fillColor: WidgetStateProperty.resolveWith((states) {
        final on = states.contains(WidgetState.selected);
        if (states.contains(WidgetState.disabled)) {
          return on ? JofColors.textDisabled : JofColors.surfaceDisabled;
        }
        return on ? JofColors.highlight : JofColors.surfaceInput;
      }),
      checkColor: const WidgetStatePropertyAll(JofColors.onHighlight),
      overlayColor: const WidgetStatePropertyAll(JofColors.tintHover),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.disabled)) {
          return JofColors.textDisabled;
        }
        return states.contains(WidgetState.selected)
            ? JofColors.onHighlight
            : JofColors.highlight;
      }),
      trackColor: WidgetStateProperty.resolveWith((states) {
        return states.contains(WidgetState.selected)
            ? JofColors.highlight
            : JofColors.surfaceInput;
      }),
      trackOutlineColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.disabled)) {
          return JofColors.textDisabled;
        }
        return JofColors.highlight;
      }),
      trackOutlineWidth: const WidgetStatePropertyAll(2),
      thumbIcon: const WidgetStatePropertyAll(null),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: JofColors.surfaceInput,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: JofSpace.sm,
        vertical: 12,
      ),
      isDense: true,
      labelStyle: JofText.body.copyWith(color: JofColors.textMuted),
      floatingLabelStyle: JofText.body.copyWith(color: JofColors.textMuted),
      floatingLabelBehavior: FloatingLabelBehavior.always,
      hintStyle: JofText.body.copyWith(color: JofColors.textDismiss),
      helperStyle: JofText.caption.copyWith(color: JofColors.textMuted),
      helperMaxLines: 4,
      errorStyle: JofText.caption.copyWith(color: JofColors.dangerText),
      errorMaxLines: 4,
      border: const OutlineInputBorder(
        borderRadius: radius,
        borderSide: BorderSide.none,
      ),
      enabledBorder: const OutlineInputBorder(
        borderRadius: radius,
        borderSide: BorderSide.none,
      ),
      focusedBorder: const OutlineInputBorder(
        borderRadius: radius,
        borderSide: BorderSide(color: JofColors.focusRing, width: 2),
      ),
      errorBorder: const OutlineInputBorder(
        borderRadius: radius,
        borderSide: BorderSide(color: JofColors.danger, width: 2),
      ),
      focusedErrorBorder: const OutlineInputBorder(
        borderRadius: radius,
        borderSide: BorderSide(color: JofColors.danger, width: 2),
      ),
      disabledBorder: const OutlineInputBorder(
        borderRadius: radius,
        borderSide: BorderSide.none,
      ),
    ),
    dropdownMenuTheme: const DropdownMenuThemeData(
      menuStyle: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(JofColors.surface),
        shape: WidgetStatePropertyAll(shape),
      ),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: JofColors.surface,
      shape: shape,
      textStyle: JofText.body,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: JofColors.surface,
      surfaceTintColor: Colors.transparent,
      shape: shape,
      titleTextStyle: JofText.boxHeader.copyWith(color: JofColors.text),
      contentTextStyle: JofText.body.copyWith(color: JofColors.text),
      barrierColor: JofColors.scrim,
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: JofColors.surfaceRaised,
      contentTextStyle: JofText.body.copyWith(color: JofColors.text),
      actionTextColor: JofColors.highlight,
      behavior: SnackBarBehavior.floating,
      shape: shape,
      elevation: 0,
      width: 450,
    ),
    tooltipTheme: TooltipThemeData(
      decoration: const BoxDecoration(
        color: JofColors.tooltip,
        borderRadius: BorderRadius.all(Radius.circular(JofRadius.md)),
      ),
      textStyle: JofText.caption.copyWith(color: JofColors.text),
      waitDuration: const Duration(milliseconds: 400),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: JofColors.highlight,
      linearTrackColor: JofColors.surfaceInput,
      circularTrackColor: Colors.transparent,
      linearMinHeight: 4,
    ),
    listTileTheme: ListTileThemeData(
      iconColor: JofColors.highlight,
      textColor: JofColors.text,
      titleTextStyle: JofText.body,
      subtitleTextStyle: JofText.caption.copyWith(color: JofColors.textMuted),
    ),
    textSelectionTheme: const TextSelectionThemeData(
      cursorColor: JofColors.highlight,
      selectionColor: JofColors.tintSelected,
      selectionHandleColor: JofColors.highlight,
    ),
    scrollbarTheme: ScrollbarThemeData(
      thumbColor: WidgetStatePropertyAll(
        JofColors.highlight.withValues(alpha: 0.4),
      ),
      radius: const Radius.circular(JofRadius.sm),
    ),
  );
}
