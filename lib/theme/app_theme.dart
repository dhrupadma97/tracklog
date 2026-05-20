// THEME LOCK: dark — source: user explicit selection ("Dark mode — great for outdoor/field use")
// Scaffold.backgroundColor = AppTheme.backgroundDark — ALL screens

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  // Primary palette — NATRAX TrackLog
  static const Color primary = Color(0xFF00C896); // teal-green — active/running
  static const Color primaryContainer = Color(0xFF003D2E);
  static const Color secondary = Color(0xFFFF6B4A); // coral-red — cost/alert
  static const Color secondaryContainer = Color(0xFF3D1A10);
  static const Color accent = Color(0xFFFFB547); // amber — warning

  // Dark surfaces
  static const Color backgroundDark = Color(0xFF0A0E1A);
  static const Color surfaceDark = Color(0xFF131929);
  static const Color surfaceVariantDark = Color(0xFF1C2438);
  static const Color cardDark = Color(0xFF1A2236);

  // Semantic
  static const Color success = Color(0xFF00C896);
  static const Color warning = Color(0xFFFFB547);
  static const Color error = Color(0xFFFF4D6A);
  static const Color info = Color(0xFF4A9EFF);

  // Light surfaces (required — app is dark but lightTheme must exist)
  static const Color backgroundLight = Color(0xFFF4F6FA);
  static const Color surfaceLight = Color(0xFFFFFFFF);

  static ThemeData get darkTheme => ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: const ColorScheme.dark(
      primary: primary,
      onPrimary: Color(0xFF001A10),
      primaryContainer: primaryContainer,
      onPrimaryContainer: Color(0xFF80FFD6),
      secondary: secondary,
      onSecondary: Colors.white,
      secondaryContainer: secondaryContainer,
      onSecondaryContainer: Color(0xFFFFCCBB),
      surface: surfaceDark,
      onSurface: Color(0xFFE8EAF0),
      surfaceContainerHighest: surfaceVariantDark,
      onSurfaceVariant: Color(0xFFA8B0C8),
      error: error,
      onError: Colors.white,
      outline: Color(0xFF3A4460),
      outlineVariant: Color(0xFF252E45),
      inverseSurface: Color(0xFFE8EAF0),
      onInverseSurface: Color(0xFF0A0E1A),
      tertiary: accent,
      onTertiary: Color(0xFF1A0D00),
    ),
    scaffoldBackgroundColor: backgroundDark,
    textTheme: GoogleFonts.manropeTextTheme(
      const TextTheme(
        displayLarge: TextStyle(
          fontSize: 48,
          fontWeight: FontWeight.w800,
          color: Color(0xFFE8EAF0),
        ),
        displayMedium: TextStyle(
          fontSize: 36,
          fontWeight: FontWeight.w700,
          color: Color(0xFFE8EAF0),
        ),
        displaySmall: TextStyle(
          fontSize: 28,
          fontWeight: FontWeight.w700,
          color: Color(0xFFE8EAF0),
        ),
        headlineLarge: TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.w700,
          color: Color(0xFFE8EAF0),
        ),
        headlineMedium: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: Color(0xFFE8EAF0),
        ),
        headlineSmall: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: Color(0xFFE8EAF0),
        ),
        titleLarge: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: Color(0xFFE8EAF0),
        ),
        titleMedium: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: Color(0xFFE8EAF0),
        ),
        titleSmall: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w500,
          color: Color(0xFFE8EAF0),
        ),
        bodyLarge: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w400,
          color: Color(0xFFE8EAF0),
        ),
        bodyMedium: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w400,
          color: Color(0xFFCDD0E0),
        ),
        bodySmall: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w400,
          color: Color(0xFFA8B0C8),
        ),
        labelLarge: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.3,
          color: Color(0xFFE8EAF0),
        ),
        labelMedium: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.3,
          color: Color(0xFFA8B0C8),
        ),
        labelSmall: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.5,
          color: Color(0xFFA8B0C8),
        ),
      ),
    ),
    appBarTheme: const AppBarThemeData(
      backgroundColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: true,
      titleTextStyle: TextStyle(
        fontFamily: 'Manrope',
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: Color(0xFFE8EAF0),
      ),
      iconTheme: IconThemeData(color: Color(0xFFE8EAF0)),
    ),
    cardTheme: CardThemeData(
      color: cardDark,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      margin: EdgeInsets.zero,
    ),
    inputDecorationTheme: InputDecorationThemeData(
      filled: true,
      fillColor: surfaceVariantDark,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFF3A4460)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFF3A4460)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: primary, width: 1.5),
      ),
      labelStyle: const TextStyle(color: Color(0xFFA8B0C8), fontSize: 13),
      hintStyle: const TextStyle(color: Color(0xFF6B7490), fontSize: 13),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: surfaceVariantDark,
      selectedColor: primaryContainer,
      labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: primary,
      foregroundColor: Color(0xFF001A10),
      elevation: 8,
    ),
    dividerTheme: const DividerThemeData(
      color: Color(0xFF252E45),
      thickness: 1,
      space: 0,
    ),
    iconTheme: const IconThemeData(color: Color(0xFFA8B0C8)),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected)
            ? primary
            : const Color(0xFF6B7490),
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected)
            ? primaryContainer
            : const Color(0xFF252E45),
      ),
    ),
  );

  static ThemeData get lightTheme => ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    colorScheme: ColorScheme.light(
      primary: primary,
      onPrimary: Colors.white,
      primaryContainer: const Color(0xFFCCF7EC),
      secondary: secondary,
      onSecondary: Colors.white,
      surface: surfaceLight,
      onSurface: const Color(0xFF1A1A2E),
      error: error,
      onError: Colors.white,
    ),
    scaffoldBackgroundColor: backgroundLight,
    textTheme: GoogleFonts.manropeTextTheme(),
  );
}
