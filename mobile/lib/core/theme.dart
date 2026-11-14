import 'package:flutter/material.dart';

ThemeData buildTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;

  // Refined Obsidian Dark & Clean Modern Light color schemes
  final scheme = dark
      ? const ColorScheme(
          brightness: Brightness.dark,
          primary: Color(0xFF818CF8), // Vibrant Indigo 400
          onPrimary: Color(0xFF1E1B4B),
          primaryContainer: Color(0xFF312E81),
          onPrimaryContainer: Color(0xFFE0E7FF),
          secondary: Color(0xFF94A3B8), // Slate 400
          onSecondary: Color(0xFF0F172A),
          secondaryContainer: Color(0xFF1E293B),
          onSecondaryContainer: Color(0xFFF1F5F9),
          tertiary: Color(0xFF38BDF8), // Sky 400
          onTertiary: Color(0xFF082F49),
          tertiaryContainer: Color(0xFF075985),
          onTertiaryContainer: Color(0xFFE0F2FE),
          error: Color(0xFFF87171),
          onError: Color(0xFF450A0A),
          surface: Color(0xFF0C0E12), // Deep Carbon/Obsidian
          onSurface: Color(0xFFF3F4F6),
          surfaceContainerLowest: Color(0xFF08090C),
          surfaceContainerLow: Color(0xFF14171D), // Crisp card elevation
          surfaceContainer: Color(0xFF1B1F27),
          surfaceContainerHigh: Color(0xFF232832),
          surfaceContainerHighest: Color(0xFF2C3340),
          onSurfaceVariant: Color(0xFF9CA3AF),
          outline: Color(0xFF4B5563),
          outlineVariant: Color(0xFF242A36),
          shadow: Colors.black,
        )
      : const ColorScheme(
          brightness: Brightness.light,
          primary: Color(0xFF4F46E5), // Indigo 600
          onPrimary: Colors.white,
          primaryContainer: Color(0xFFEEF2FF),
          onPrimaryContainer: Color(0xFF312E81),
          secondary: Color(0xFF475569), // Slate 600
          onSecondary: Colors.white,
          secondaryContainer: Color(0xFFF1F5F9),
          onSecondaryContainer: Color(0xFF0F172A),
          tertiary: Color(0xFF0284C7), // Sky 600
          onTertiary: Colors.white,
          tertiaryContainer: Color(0xFFE0F2FE),
          onTertiaryContainer: Color(0xFF0369A1),
          error: Color(0xFFDC2626),
          onError: Colors.white,
          surface: Color(0xFFF8F9FA), // Crisp off-white
          onSurface: Color(0xFF111827),
          surfaceContainerLowest: Colors.white,
          surfaceContainerLow: Colors.white,
          surfaceContainer: Color(0xFFF1F3F5),
          surfaceContainerHigh: Color(0xFFE5E7EB),
          surfaceContainerHighest: Color(0xFFD1D5DB),
          onSurfaceVariant: Color(0xFF4B5563),
          outline: Color(0xFF9CA3AF),
          outlineVariant: Color(0xFFE5E7EB),
          shadow: Colors.black12,
        );

  final base = ThemeData(useMaterial3: true, colorScheme: scheme);
  final roundedCard = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(16),
    side: BorderSide(
      color: scheme.outlineVariant.withValues(alpha: dark ? 0.5 : 0.7),
      width: 0.8,
    ),
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: scheme.surface,
    textTheme: base.textTheme.copyWith(
      headlineMedium: base.textTheme.headlineMedium?.copyWith(
        fontSize: 26,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.6,
        height: 1.2,
      ),
      headlineSmall: base.textTheme.headlineSmall?.copyWith(
        fontSize: 20,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.4,
        height: 1.25,
      ),
      titleLarge: base.textTheme.titleLarge?.copyWith(
        fontSize: 17,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.2,
      ),
      titleMedium: base.textTheme.titleMedium?.copyWith(
        fontSize: 15,
        fontWeight: FontWeight.w600,
      ),
      titleSmall: base.textTheme.titleSmall?.copyWith(
        fontSize: 13,
        fontWeight: FontWeight.w600,
      ),
      bodyLarge: base.textTheme.bodyLarge?.copyWith(
        fontSize: 15,
        height: 1.5,
      ),
      bodyMedium: base.textTheme.bodyMedium?.copyWith(
        fontSize: 13.5,
        height: 1.45,
      ),
      bodySmall: base.textTheme.bodySmall?.copyWith(
        fontSize: 12,
        height: 1.4,
      ),
      labelLarge: base.textTheme.labelLarge?.copyWith(
        fontSize: 13.5,
        fontWeight: FontWeight.w600,
      ),
    ),
    appBarTheme: AppBarTheme(
      centerTitle: false,
      backgroundColor: scheme.surface,
      foregroundColor: scheme.onSurface,
      scrolledUnderElevation: 0,
      elevation: 0,
      titleSpacing: 20,
      titleTextStyle: TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.3,
        color: scheme.onSurface,
      ),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: scheme.surfaceContainerLow,
      surfaceTintColor: Colors.transparent,
      margin: const EdgeInsets.symmetric(vertical: 6),
      shape: roundedCard,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(44, 48),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        elevation: 0,
        textStyle: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.1,
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(44, 48),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        side: BorderSide(color: scheme.outlineVariant, width: 1.0),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        foregroundColor: scheme.onSurface,
        textStyle: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.1,
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        minimumSize: const Size(40, 44),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        textStyle: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
    chipTheme: ChipThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      side: BorderSide(color: scheme.outlineVariant, width: 0.8),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      labelStyle: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w500,
        color: scheme.onSurface,
      ),
      backgroundColor: scheme.surfaceContainerLow,
      selectedColor: scheme.primary.withValues(alpha: dark ? 0.2 : 0.12),
    ),
    inputDecorationTheme: InputDecorationThemeData(
      helperMaxLines: 3,
      errorMaxLines: 3,
      filled: true,
      fillColor: scheme.surfaceContainer,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: scheme.outlineVariant),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: scheme.outlineVariant),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: scheme.primary, width: 1.5),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: scheme.surface,
      indicatorColor: scheme.primary.withValues(alpha: dark ? 0.18 : 0.12),
      elevation: 0,
      height: 64,
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => IconThemeData(
          size: 24,
          color: states.contains(WidgetState.selected)
              ? scheme.primary
              : scheme.onSurfaceVariant,
        ),
      ),
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => TextStyle(
          fontSize: 12,
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
      minVerticalPadding: 10,
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: scheme.surfaceContainerLow,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
      dragHandleColor: scheme.outlineVariant,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: scheme.surfaceContainerLow,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      backgroundColor: dark ? const Color(0xFF1E232B) : const Color(0xFF1F2937),
    ),
    dividerTheme: DividerThemeData(
      color: scheme.outlineVariant,
      thickness: 0.8,
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      linearTrackColor: scheme.surfaceContainerHighest,
      color: scheme.primary,
      borderRadius: BorderRadius.circular(8),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        shape: WidgetStateProperty.all(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        side: WidgetStateProperty.all(
          BorderSide(
            color: scheme.outlineVariant.withValues(alpha: 0.8),
            width: 0.8,
          ),
        ),
        backgroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return scheme.primary.withValues(alpha: dark ? 0.22 : 0.14);
          }
          return null;
        }),
        foregroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return scheme.primary;
          }
          return scheme.onSurfaceVariant;
        }),
        textStyle: WidgetStateProperty.all(
          const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        ),
      ),
    ),
  );
}
