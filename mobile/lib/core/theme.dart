import 'package:flutter/material.dart';

const _seed = Color(0xFF286653);

ThemeData buildTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final scheme = ColorScheme.fromSeed(seedColor: _seed, brightness: brightness)
      .copyWith(
        primary: dark ? const Color(0xFFA4D5BD) : _seed,
        onPrimary: dark ? const Color(0xFF12382C) : Colors.white,
        surface: dark ? const Color(0xFF151B18) : const Color(0xFFF7F8F5),
        surfaceContainerLowest: dark ? const Color(0xFF101612) : Colors.white,
        surfaceContainerLow: dark ? const Color(0xFF1D2420) : Colors.white,
        surfaceContainer: dark
            ? const Color(0xFF242D27)
            : const Color(0xFFEEF1EB),
        onSurface: dark ? const Color(0xFFE6ECE5) : const Color(0xFF202A24),
        onSurfaceVariant: dark
            ? const Color(0xFFB9C5BB)
            : const Color(0xFF59665D),
        outlineVariant: dark
            ? const Color(0xFF3B493F)
            : const Color(0xFFDBE2D9),
      );
  final base = ThemeData(useMaterial3: true, colorScheme: scheme);
  final rounded = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(16),
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: scheme.surface,
    textTheme: base.textTheme.copyWith(
      headlineMedium: base.textTheme.headlineMedium?.copyWith(
        fontSize: 30,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.8,
        height: 1.15,
      ),
      headlineSmall: base.textTheme.headlineSmall?.copyWith(
        fontSize: 25,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.5,
        height: 1.2,
      ),
      titleLarge: base.textTheme.titleLarge?.copyWith(
        fontWeight: FontWeight.w600,
      ),
      titleMedium: base.textTheme.titleMedium?.copyWith(
        fontWeight: FontWeight.w600,
      ),
      bodyMedium: base.textTheme.bodyMedium?.copyWith(height: 1.5),
      bodySmall: base.textTheme.bodySmall?.copyWith(height: 1.45),
    ),
    appBarTheme: AppBarTheme(
      centerTitle: false,
      backgroundColor: scheme.surface,
      scrolledUnderElevation: 0,
      elevation: 0,
      titleSpacing: 20,
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: scheme.surfaceContainerLow,
      surfaceTintColor: Colors.transparent,
      margin: const EdgeInsets.symmetric(vertical: 6),
      shape: rounded,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(48, 52),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(48, 50),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        side: BorderSide(color: scheme.outlineVariant),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
    ),
    inputDecorationTheme: InputDecorationThemeData(
      helperMaxLines: 3,
      errorMaxLines: 3,
      filled: true,
      fillColor: scheme.surfaceContainerLow,
      contentPadding: const EdgeInsets.all(16),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: scheme.outlineVariant),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: scheme.surfaceContainerLow,
      indicatorColor: scheme.primaryContainer,
      elevation: 0,
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => TextStyle(
          fontSize: 11,
          fontWeight: states.contains(WidgetState.selected)
              ? FontWeight.w700
              : FontWeight.w500,
          color: states.contains(WidgetState.selected)
              ? scheme.primary
              : scheme.onSurfaceVariant,
        ),
      ),
    ),
    listTileTheme: const ListTileThemeData(
      contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      minVerticalPadding: 12,
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: scheme.surface,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
    ),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
    dividerTheme: DividerThemeData(color: scheme.outlineVariant, thickness: 1),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      linearTrackColor: scheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(8),
    ),
  );
}
