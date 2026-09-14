import 'package:flutter/material.dart';

class AppTheme {
  // Brand Colors
  static const Color background = Color(0xFF0E0E10);
  static const Color surface = Color(0xFF18181B);
  static const Color surfaceElevated = Color(0xFF222226);
  static const Color surfaceLight = Color(0xFF2A2A30);
  static const Color border = Color(0xFF2C2C34);
  static const Color borderLight = Color(0xFF383842);

  // Electric Lime & Accents
  static const Color electricLime = Color(0xFFCCFF00);
  static const Color electricLimeDim = Color(0xFF99BF00);
  static const Color electricLimeGlow = Color(0x33CCFF00);

  // Typography Colors
  static const Color textPrimary = Color(0xFFFFFFFF);
  static const Color textSecondary = Color(0xFF9E9EA7);
  static const Color textMuted = Color(0xFF6B6B76);

  // Status & Feedback
  static const Color success = Color(0xFF00E676);
  static const Color warning = Color(0xFFFFAB00);
  static const Color error = Color(0xFFFF5252);
  static const Color gold = Color(0xFFFFD700);

  static ThemeData get darkTheme {
    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: background,
      primaryColor: electricLime,
      colorScheme: const ColorScheme.dark(
        primary: electricLime,
        secondary: electricLimeDim,
        surface: surface,
      ),
      fontFamily: 'Segoe UI',
      cardColor: surface,
      dividerColor: border,
      appBarTheme: const AppBarTheme(
        backgroundColor: background,
        elevation: 0,
        centerTitle: false,
      ),
    );
  }
}
