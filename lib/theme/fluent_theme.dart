import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// WinUI 3 color tokens. The accent is PocketBot teal, darkened in light mode
/// so white text stays readable.
class FluentColors {
  const FluentColors(this.brightness);

  final Brightness brightness;

  static FluentColors of(BuildContext context) =>
      FluentColors(Theme.of(context).brightness);

  bool get isDark => brightness == Brightness.dark;

  static const double radius = 4;
  static const double overlayRadius = 8;

  Color get background =>
      isDark ? const Color(0xFF202020) : const Color(0xFFF3F3F3);
  Color get chrome =>
      isDark ? const Color(0xFF1C1C1C) : const Color(0xFFF3F3F3);
  Color get card => isDark ? const Color(0xFF2C2C2C) : const Color(0xFFFFFFFF);
  Color get control =>
      isDark ? const Color(0xFF2D2D2D) : const Color(0xFFFFFFFF);
  Color get stroke =>
      isDark ? const Color(0x22FFFFFF) : const Color(0x14000000);
  Color get strokeStrong =>
      isDark ? const Color(0x33FFFFFF) : const Color(0x29000000);
  Color get textPrimary =>
      isDark ? const Color(0xFFFFFFFF) : const Color(0xE4000000);
  Color get textSecondary =>
      isDark ? const Color(0xC5FFFFFF) : const Color(0x9E000000);
  Color get textTertiary =>
      isDark ? const Color(0x87FFFFFF) : const Color(0x72000000);
  Color get accent =>
      isDark ? const Color(0xFF00AEB5) : const Color(0xFF006E75);
  Color get onAccent =>
      isDark ? const Color(0xFF041416) : const Color(0xFFFFFFFF);
  Color get accentSubtle =>
      isDark ? const Color(0x3300AEB5) : const Color(0x1A006E75);
  Color get success =>
      isDark ? const Color(0xFF6CCB5F) : const Color(0xFF0F7B0F);
  Color get danger =>
      isDark ? const Color(0xFFFF99A4) : const Color(0xFFC42B1C);
  Color get dangerSurface =>
      isDark ? const Color(0xFF3B2426) : const Color(0xFFFDE7E9);
  Color get warning =>
      isDark ? const Color(0xFFFCE100) : const Color(0xFF9D5D00);
  Color get warningSurface =>
      isDark ? const Color(0xFF3B3414) : const Color(0xFFFFF4CE);
  Color get info => isDark ? const Color(0xFF60CDFF) : const Color(0xFF005FB8);
  Color get infoSurface =>
      isDark ? const Color(0xFF1A3040) : const Color(0xFFF0F8FE);
}

ThemeData buildFluentTheme(Brightness brightness) {
  final colors = FluentColors(brightness);
  final scheme = ColorScheme(
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
    onError: colors.isDark ? Colors.black : Colors.white,
    errorContainer: colors.dangerSurface,
    onErrorContainer: colors.danger,
    surface: colors.background,
    onSurface: colors.textPrimary,
    onSurfaceVariant: colors.textSecondary,
    outline: colors.strokeStrong,
    outlineVariant: colors.stroke,
    shadow: Colors.black,
    scrim: const Color(0x99000000),
    inverseSurface:
        colors.isDark ? const Color(0xFFF3F3F3) : const Color(0xFF202020),
    onInverseSurface:
        colors.isDark ? const Color(0xE4000000) : const Color(0xFFFFFFFF),
    inversePrimary:
        colors.isDark ? const Color(0xFF006E75) : const Color(0xFF00AEB5),
    surfaceContainerLowest: colors.card,
    surfaceContainerLow: colors.card,
    surfaceContainer: colors.control,
    surfaceContainerHigh: colors.chrome,
    surfaceContainerHighest: colors.control,
  );

  final baseText =
      colors.isDark ? ThemeData.dark().textTheme : ThemeData.light().textTheme;
  final textTheme = GoogleFonts.sourceSans3TextTheme(baseText).apply(
    bodyColor: colors.textPrimary,
    displayColor: colors.textPrimary,
  );
  final controlShape = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(FluentColors.radius),
  );
  final overlayShape = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(FluentColors.overlayRadius),
    side: BorderSide(color: colors.stroke),
  );
  final fieldBorder = OutlineInputBorder(
    borderRadius: BorderRadius.circular(FluentColors.radius),
    borderSide: BorderSide(color: colors.strokeStrong),
  );

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: colors.background,
    canvasColor: colors.background,
    dividerColor: colors.stroke,
    textTheme: textTheme,
    iconTheme: IconThemeData(color: colors.textSecondary),
    appBarTheme: AppBarTheme(
      elevation: 0,
      scrolledUnderElevation: 0,
      backgroundColor: colors.chrome,
      foregroundColor: colors.textPrimary,
      surfaceTintColor: Colors.transparent,
      centerTitle: false,
      titleTextStyle: textTheme.titleLarge?.copyWith(
        fontSize: 20,
        fontWeight: FontWeight.w600,
        color: colors.textPrimary,
      ),
      iconTheme: IconThemeData(color: colors.textPrimary),
    ),
    cardTheme: CardThemeData(
      color: colors.card,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      shape: overlayShape,
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        elevation: 0,
        backgroundColor: colors.accent,
        foregroundColor: colors.onAccent,
        disabledBackgroundColor: colors.stroke,
        disabledForegroundColor: colors.textTertiary,
        shape: controlShape,
        textStyle: textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: colors.accent,
        foregroundColor: colors.onAccent,
        shape: controlShape,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: colors.textPrimary,
        side: BorderSide(color: colors.strokeStrong),
        shape: controlShape,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: colors.accent,
        shape: controlShape,
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        foregroundColor: colors.textPrimary,
        shape: controlShape,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: colors.control,
      hintStyle: TextStyle(color: colors.textTertiary),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      border: fieldBorder,
      enabledBorder: fieldBorder,
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(FluentColors.radius),
        borderSide: BorderSide(color: colors.accent, width: 2),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: colors.card,
      elevation: 8,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(FluentColors.overlayRadius),
      ),
    ),
    dividerTheme: const DividerThemeData(thickness: 1, space: 1),
    listTileTheme: ListTileThemeData(
      iconColor: colors.textSecondary,
      textColor: colors.textPrimary,
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return colors.onAccent;
        return colors.card;
      }),
      trackColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return colors.accent;
        return colors.strokeStrong;
      }),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: colors.accent),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: colors.card,
      contentTextStyle: TextStyle(color: colors.textPrimary),
      behavior: SnackBarBehavior.floating,
      shape: overlayShape,
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: colors.card,
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(8)),
      ),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: colors.accent,
      foregroundColor: colors.onAccent,
      elevation: 0,
      shape: controlShape,
    ),
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return colors.accent;
        return Colors.transparent;
      }),
      checkColor: WidgetStatePropertyAll(colors.onAccent),
      side: BorderSide(color: colors.strokeStrong),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(2)),
    ),
    radioTheme: RadioThemeData(
      fillColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return colors.accent;
        return colors.strokeStrong;
      }),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: colors.card,
      surfaceTintColor: Colors.transparent,
      shape: overlayShape,
    ),
  );
}
