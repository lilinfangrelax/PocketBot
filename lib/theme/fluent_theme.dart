import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/material.dart' as material;

/// PocketBot colors.
///
/// When a [FluentTheme] is in the tree, these come from that theme's WinUI
/// resources. Tests that only mount a Material app fall back to the same
/// solid tokens.
class FluentColors {
  const FluentColors({
    required this.brightness,
    required this.background,
    required this.chrome,
    required this.card,
    required this.control,
    required this.stroke,
    required this.strokeStrong,
    required this.textPrimary,
    required this.textSecondary,
    required this.textTertiary,
    required this.accent,
    required this.onAccent,
    required this.accentSubtle,
    required this.success,
    required this.danger,
    required this.dangerSurface,
    required this.warning,
    required this.warningSurface,
    required this.info,
    required this.infoSurface,
  });

  final Brightness brightness;
  final Color background;
  final Color chrome;
  final Color card;
  final Color control;
  final Color stroke;
  final Color strokeStrong;
  final Color textPrimary;
  final Color textSecondary;
  final Color textTertiary;
  final Color accent;
  final Color onAccent;
  final Color accentSubtle;
  final Color success;
  final Color danger;
  final Color dangerSurface;
  final Color warning;
  final Color warningSurface;
  final Color info;
  final Color infoSurface;

  static const double radius = 4;
  static const double overlayRadius = 8;

  bool get isDark => brightness == Brightness.dark;

  static FluentColors of(BuildContext context) {
    final theme = FluentTheme.maybeOf(context);
    if (theme != null) return FluentColors.fromTheme(theme);
    return FluentColors.fallback(material.Theme.of(context).brightness);
  }

  factory FluentColors.fromTheme(FluentThemeData theme) {
    final resources = theme.resources;
    final isDark = theme.brightness == Brightness.dark;
    return FluentColors(
      brightness: theme.brightness,
      background: theme.scaffoldBackgroundColor,
      chrome: theme.micaBackgroundColor,
      card: theme.cardColor,
      control: resources.controlFillColorInputActive,
      stroke: resources.cardStrokeColorDefault,
      strokeStrong: resources.controlStrokeColorSecondary,
      textPrimary: resources.textFillColorPrimary,
      textSecondary: resources.textFillColorSecondary,
      textTertiary: resources.textFillColorTertiary,
      accent: theme.accentColor,
      onAccent: resources.textOnAccentFillColorPrimary,
      accentSubtle: theme.accentColor.withValues(alpha: isDark ? 0.28 : 0.14),
      success: resources.systemFillColorSuccess,
      danger: resources.systemFillColorCritical,
      dangerSurface: resources.systemFillColorCriticalBackground,
      warning: resources.systemFillColorCaution,
      warningSurface: resources.systemFillColorCautionBackground,
      info: isDark ? const Color(0xFF60CDFF) : Colors.blue.dark,
      infoSurface: resources.systemFillColorAttentionBackground,
    );
  }

  factory FluentColors.fallback(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    return FluentColors(
      brightness: brightness,
      background: isDark ? const Color(0xFF202020) : const Color(0xFFF3F3F3),
      chrome: isDark ? const Color(0xFF1C1C1C) : const Color(0xFFFBFBFB),
      card: isDark ? const Color(0xFF2B2B2B) : const Color(0xFFFFFFFF),
      control: isDark ? const Color(0xFF2D2D2D) : const Color(0xFFFFFFFF),
      stroke: isDark ? const Color(0x22FFFFFF) : const Color(0x14000000),
      strokeStrong: isDark ? const Color(0x33FFFFFF) : const Color(0x29000000),
      textPrimary: isDark ? const Color(0xFFFFFFFF) : const Color(0xE4000000),
      textSecondary: isDark ? const Color(0xC5FFFFFF) : const Color(0x9E000000),
      textTertiary: isDark ? const Color(0x87FFFFFF) : const Color(0x72000000),
      accent: isDark ? const Color(0xFF00B294) : const Color(0xFF007C67),
      onAccent: isDark ? const Color(0xFF000000) : const Color(0xFFFFFFFF),
      accentSubtle: isDark ? const Color(0x4700B294) : const Color(0x24007C67),
      success: isDark ? const Color(0xFF6CCB5F) : const Color(0xFF0F7B0F),
      danger: isDark ? const Color(0xFFFF99A4) : const Color(0xFFC42B1C),
      dangerSurface: isDark ? const Color(0xFF3B2426) : const Color(0xFFFDE7E9),
      warning: isDark ? const Color(0xFFFCE100) : const Color(0xFF9D5D00),
      warningSurface:
          isDark ? const Color(0xFF3B3414) : const Color(0xFFFFF4CE),
      info: isDark ? const Color(0xFF60CDFF) : const Color(0xFF005FB8),
      infoSurface: isDark ? const Color(0xFF1A3040) : const Color(0xFFF0F8FE),
    );
  }
}

/// Light mode uses the darker teal shade so white control text stays readable.
/// Dark mode uses [Colors.teal]; WinUI paints black text on that accent.
FluentThemeData buildFluentTheme(Brightness brightness) {
  final isLight = brightness == Brightness.light;
  final accent =
      isLight ? const Color(0xFF007C67).toAccentColor() : Colors.teal;
  return FluentThemeData(
    brightness: brightness,
    accentColor: accent,
    scaffoldBackgroundColor:
        isLight ? const Color(0xFFF3F3F3) : const Color(0xFF202020),
    micaBackgroundColor:
        isLight ? const Color(0xFFFBFBFB) : const Color(0xFF1C1C1C),
    cardColor: isLight ? const Color(0xFFFFFFFF) : const Color(0xFF2B2B2B),
    acrylicBackgroundColor:
        isLight ? const Color(0xFFF9F9F9) : const Color(0xFF2C2C2C),
    buttonTheme: const ButtonThemeData(
      // Phone touch targets: 18px glyph with 10px padding is a 38px hit box.
      iconButtonStyle: ButtonStyle(
        iconSize: WidgetStatePropertyAll(18),
        padding: WidgetStatePropertyAll(EdgeInsetsDirectional.all(10)),
      ),
    ),
  );
}

/// Material theme for screens that still use Material widgets such as chat
/// bubbles, markdown, and text fields. Fluent controls read [buildFluentTheme].
material.ThemeData buildMaterialTheme(Brightness brightness) {
  final colors = FluentColors.fallback(brightness);
  final scheme = material.ColorScheme(
    brightness: brightness,
    primary: colors.accent,
    onPrimary: colors.onAccent,
    primaryContainer: colors.accentSubtle,
    onPrimaryContainer: colors.accent,
    secondary: colors.accent,
    onSecondary: colors.onAccent,
    secondaryContainer: colors.accentSubtle,
    onSecondaryContainer: colors.textPrimary,
    error: colors.danger,
    onError: colors.isDark ? material.Colors.black : material.Colors.white,
    errorContainer: colors.dangerSurface,
    onErrorContainer: colors.danger,
    surface: colors.background,
    onSurface: colors.textPrimary,
    onSurfaceVariant: colors.textSecondary,
    outline: colors.strokeStrong,
    outlineVariant: colors.stroke,
    shadow: material.Colors.black,
    scrim: const Color(0x99000000),
    inverseSurface:
        colors.isDark ? const Color(0xFFF3F3F3) : const Color(0xFF202020),
    onInverseSurface:
        colors.isDark ? const Color(0xE4000000) : const Color(0xFFFFFFFF),
    inversePrimary:
        colors.isDark ? const Color(0xFF007C67) : const Color(0xFF00B294),
    surfaceContainerLowest: colors.card,
    surfaceContainerLow: colors.card,
    surfaceContainer: colors.control,
    surfaceContainerHigh: colors.chrome,
    surfaceContainerHighest: colors.control,
  );

  final baseText = colors.isDark
      ? material.ThemeData.dark().textTheme
      : material.ThemeData.light().textTheme;
  final textTheme = baseText.apply(
    bodyColor: colors.textPrimary,
    displayColor: colors.textPrimary,
  );
  final controlShape = material.RoundedRectangleBorder(
    borderRadius: material.BorderRadius.circular(FluentColors.radius),
  );
  final overlayShape = material.RoundedRectangleBorder(
    borderRadius: material.BorderRadius.circular(FluentColors.overlayRadius),
    side: material.BorderSide(color: colors.stroke),
  );
  final fieldBorder = material.OutlineInputBorder(
    borderRadius: material.BorderRadius.circular(FluentColors.radius),
    borderSide: material.BorderSide(color: colors.strokeStrong),
  );

  return material.ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: colors.background,
    canvasColor: colors.background,
    dividerColor: colors.stroke,
    textTheme: textTheme,
    iconTheme: material.IconThemeData(color: colors.textSecondary),
    appBarTheme: material.AppBarTheme(
      elevation: 0,
      scrolledUnderElevation: 0,
      backgroundColor: colors.chrome,
      foregroundColor: colors.textPrimary,
      surfaceTintColor: material.Colors.transparent,
      centerTitle: false,
      titleTextStyle: textTheme.titleLarge?.copyWith(
        fontSize: 20,
        fontWeight: FontWeight.w600,
        color: colors.textPrimary,
      ),
      iconTheme: material.IconThemeData(color: colors.textPrimary),
    ),
    cardTheme: material.CardThemeData(
      color: colors.card,
      elevation: 0,
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      surfaceTintColor: material.Colors.transparent,
      shape: overlayShape,
    ),
    elevatedButtonTheme: material.ElevatedButtonThemeData(
      style: material.ElevatedButton.styleFrom(
        elevation: 0,
        backgroundColor: colors.accent,
        foregroundColor: colors.onAccent,
        disabledBackgroundColor: colors.stroke,
        disabledForegroundColor: colors.textTertiary,
        shape: controlShape,
        textStyle: textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600),
      ),
    ),
    filledButtonTheme: material.FilledButtonThemeData(
      style: material.FilledButton.styleFrom(
        backgroundColor: colors.accent,
        foregroundColor: colors.onAccent,
        shape: controlShape,
      ),
    ),
    outlinedButtonTheme: material.OutlinedButtonThemeData(
      style: material.OutlinedButton.styleFrom(
        foregroundColor: colors.textPrimary,
        side: material.BorderSide(color: colors.strokeStrong),
        shape: controlShape,
      ),
    ),
    textButtonTheme: material.TextButtonThemeData(
      style: material.TextButton.styleFrom(
        foregroundColor: colors.accent,
        shape: controlShape,
      ),
    ),
    iconButtonTheme: material.IconButtonThemeData(
      style: material.IconButton.styleFrom(
        foregroundColor: colors.textPrimary,
        shape: controlShape,
      ),
    ),
    inputDecorationTheme: material.InputDecorationTheme(
      filled: true,
      fillColor: colors.control,
      hintStyle: material.TextStyle(color: colors.textTertiary),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      border: fieldBorder,
      enabledBorder: fieldBorder,
      focusedBorder: material.OutlineInputBorder(
        borderRadius: material.BorderRadius.circular(FluentColors.radius),
        borderSide: material.BorderSide(color: colors.accent, width: 2),
      ),
    ),
    dialogTheme: material.DialogThemeData(
      backgroundColor: colors.card,
      elevation: 8,
      surfaceTintColor: material.Colors.transparent,
      shape: material.RoundedRectangleBorder(
        borderRadius:
            material.BorderRadius.circular(FluentColors.overlayRadius),
      ),
    ),
    dividerTheme: material.DividerThemeData(
      color: colors.stroke,
      thickness: 1,
      space: 1,
    ),
    listTileTheme: material.ListTileThemeData(
      iconColor: colors.textSecondary,
      textColor: colors.textPrimary,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      horizontalTitleGap: 14,
      minLeadingWidth: 24,
      minVerticalPadding: 10,
      titleTextStyle: textTheme.bodyLarge?.copyWith(
        fontSize: 15,
        height: 1.35,
        color: colors.textPrimary,
      ),
      subtitleTextStyle: textTheme.bodyMedium?.copyWith(
        fontSize: 13,
        height: 1.35,
        color: colors.textSecondary,
      ),
      leadingAndTrailingTextStyle: textTheme.bodyMedium?.copyWith(
        fontSize: 13,
        color: colors.textSecondary,
      ),
    ),
    chipTheme: material.ChipThemeData(
      backgroundColor: colors.control,
      side: material.BorderSide(color: colors.stroke),
      labelStyle: textTheme.labelMedium?.copyWith(color: colors.textSecondary),
      padding: const EdgeInsets.symmetric(horizontal: 4),
      shape: material.RoundedRectangleBorder(
        borderRadius: material.BorderRadius.circular(FluentColors.radius),
      ),
    ),
    switchTheme: material.SwitchThemeData(
      thumbColor: material.WidgetStateProperty.resolveWith((states) {
        if (states.contains(material.WidgetState.selected)) {
          return colors.onAccent;
        }
        return colors.card;
      }),
      trackColor: material.WidgetStateProperty.resolveWith((states) {
        if (states.contains(material.WidgetState.selected))
          return colors.accent;
        return colors.strokeStrong;
      }),
    ),
    progressIndicatorTheme:
        material.ProgressIndicatorThemeData(color: colors.accent),
    snackBarTheme: material.SnackBarThemeData(
      backgroundColor: colors.card,
      contentTextStyle: material.TextStyle(color: colors.textPrimary),
      behavior: material.SnackBarBehavior.floating,
      shape: overlayShape,
    ),
    bottomSheetTheme: material.BottomSheetThemeData(
      backgroundColor: colors.card,
      surfaceTintColor: material.Colors.transparent,
      shape: const material.RoundedRectangleBorder(
        borderRadius: material.BorderRadius.vertical(top: Radius.circular(8)),
      ),
    ),
    floatingActionButtonTheme: material.FloatingActionButtonThemeData(
      backgroundColor: colors.accent,
      foregroundColor: colors.onAccent,
      elevation: 0,
      shape: controlShape,
    ),
    checkboxTheme: material.CheckboxThemeData(
      fillColor: material.WidgetStateProperty.resolveWith((states) {
        if (states.contains(material.WidgetState.selected))
          return colors.accent;
        return material.Colors.transparent;
      }),
      checkColor: material.WidgetStatePropertyAll(colors.onAccent),
      side: material.BorderSide(color: colors.strokeStrong),
      shape: material.RoundedRectangleBorder(
        borderRadius: material.BorderRadius.circular(2),
      ),
    ),
    radioTheme: material.RadioThemeData(
      fillColor: material.WidgetStateProperty.resolveWith((states) {
        if (states.contains(material.WidgetState.selected))
          return colors.accent;
        return colors.strokeStrong;
      }),
    ),
    popupMenuTheme: material.PopupMenuThemeData(
      color: colors.card,
      surfaceTintColor: material.Colors.transparent,
      shape: overlayShape,
    ),
  );
}

void showAppNotice(BuildContext context, String message) {
  displayInfoBar(
    context,
    builder: (context, close) {
      return InfoBar(
        title: Text(message),
        onClose: close,
      );
    },
  );
}
