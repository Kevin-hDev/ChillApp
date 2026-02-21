import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'design_tokens.dart';

ThemeData chillDarkTheme() {
  return ThemeData(
    brightness: Brightness.dark,
    scaffoldBackgroundColor: ChillColorsDark.bgPrimary,
    colorScheme: const ColorScheme.dark(
      primary: ChillColorsDark.accent,
      secondary: ChillColorsDark.accentHover,
      surface: ChillColorsDark.bgElevated,
      error: ChillColorsDark.red,
      onPrimary: ChillColorsDark.textPrimary,
      onSecondary: ChillColorsDark.textPrimary,
      onSurface: ChillColorsDark.textPrimary,
      onError: ChillColorsDark.textPrimary,
    ),
    textTheme: _buildTextTheme(
      ChillColorsDark.textPrimary,
      ChillColorsDark.textSecondary,
    ),
    cardTheme: CardThemeData(
      color: ChillColorsDark.bgElevated,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(ChillRadius.xl),
        side: const BorderSide(color: ChillColorsDark.border),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: ChillColorsDark.accent,
        foregroundColor: ChillColorsDark.textPrimary,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(ChillRadius.lg),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
      ),
    ),
    dividerTheme: const DividerThemeData(color: ChillColorsDark.border),
  );
}

ThemeData chillLightTheme() {
  return ThemeData(
    brightness: Brightness.light,
    scaffoldBackgroundColor: ChillColorsLight.bgPrimary,
    colorScheme: const ColorScheme.light(
      primary: ChillColorsLight.accent,
      secondary: ChillColorsLight.accentHover,
      surface: ChillColorsLight.bgElevated,
      error: ChillColorsLight.red,
      onPrimary: Colors.white,
      onSecondary: Colors.white,
      onSurface: ChillColorsLight.textPrimary,
      onError: Colors.white,
    ),
    textTheme: _buildTextTheme(
      ChillColorsLight.textPrimary,
      ChillColorsLight.textSecondary,
    ),
    cardTheme: CardThemeData(
      color: ChillColorsLight.bgElevated,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(ChillRadius.xl),
        side: const BorderSide(color: ChillColorsLight.border),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: ChillColorsLight.accent,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(ChillRadius.lg),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
      ),
    ),
    dividerTheme: const DividerThemeData(color: ChillColorsLight.border),
  );
}

TextTheme _buildTextTheme(Color primary, Color secondary) {
  return TextTheme(
    headlineLarge: GoogleFonts.jetBrainsMono(
      fontSize: 32,
      fontWeight: FontWeight.w700,
      color: primary,
      letterSpacing: -1.0,
    ),
    headlineMedium: GoogleFonts.jetBrainsMono(
      fontSize: 24,
      fontWeight: FontWeight.w700,
      color: primary,
      letterSpacing: -0.5,
    ),
    headlineSmall: GoogleFonts.jetBrainsMono(
      fontSize: 20,
      fontWeight: FontWeight.w700,
      color: primary,
    ),
    titleLarge: GoogleFonts.plusJakartaSans(
      fontSize: 18,
      fontWeight: FontWeight.w600,
      color: primary,
    ),
    titleMedium: GoogleFonts.plusJakartaSans(
      fontSize: 16,
      fontWeight: FontWeight.w600,
      color: primary,
    ),
    bodyLarge: GoogleFonts.plusJakartaSans(
      fontSize: 17,
      fontWeight: FontWeight.w400,
      color: primary,
    ),
    bodyMedium: GoogleFonts.plusJakartaSans(
      fontSize: 15,
      fontWeight: FontWeight.w400,
      color: secondary,
    ),
    bodySmall: GoogleFonts.plusJakartaSans(
      fontSize: 13,
      fontWeight: FontWeight.w400,
      color: secondary,
    ),
    labelLarge: GoogleFonts.plusJakartaSans(
      fontSize: 14,
      fontWeight: FontWeight.w600,
      color: primary,
    ),
  );
}
