import 'package:flutter/material.dart';
import '../../config/design_tokens.dart';

extension ChillTheme on BuildContext {
  bool get isDark => Theme.of(this).brightness == Brightness.dark;

  Color get chillBgPrimary => isDark ? ChillColorsDark.bgPrimary : ChillColorsLight.bgPrimary;
  Color get chillBgElevated => isDark ? ChillColorsDark.bgElevated : ChillColorsLight.bgElevated;
  Color get chillBgSurface => isDark ? ChillColorsDark.bgSurface : ChillColorsLight.bgSurface;
  Color get chillBorder => isDark ? ChillColorsDark.border : ChillColorsLight.border;
  Color get chillBorderSubtle => isDark ? ChillColorsDark.borderSubtle : ChillColorsLight.borderSubtle;
  Color get chillTextPrimary => isDark ? ChillColorsDark.textPrimary : ChillColorsLight.textPrimary;
  Color get chillTextSecondary => isDark ? ChillColorsDark.textSecondary : ChillColorsLight.textSecondary;
  Color get chillTextMuted => isDark ? ChillColorsDark.textMuted : ChillColorsLight.textMuted;
  Color get chillAccent => isDark ? ChillColorsDark.accent : ChillColorsLight.accent;
  Color get chillAccentHover => isDark ? ChillColorsDark.accentHover : ChillColorsLight.accentHover;
  Color get chillAccentGlow => isDark ? ChillColorsDark.accentGlow : ChillColorsLight.accentGlow;
  Color get chillBlue => isDark ? ChillColorsDark.blue : ChillColorsLight.blue;
  Color get chillRed => isDark ? ChillColorsDark.red : ChillColorsLight.red;
  Color get chillGreen => isDark ? ChillColorsDark.green : ChillColorsLight.green;
  Color get chillOrange => isDark ? ChillColorsDark.orange : ChillColorsLight.orange;
}
