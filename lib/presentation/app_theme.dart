import 'package:flutter/material.dart';

class KronosPalette {
  static const darkBackground = Color(0xFF0D0D0D);
  static const darkSurface = Color(0xFF373438);
  static const brand = Color(0xFF2C6581);
  static const brightAccent = Color(0xFF05F2DB);
  static const subtleAccent = Color(0xFF4EABBF);
}

ThemeData buildLightTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: KronosPalette.brand,
    brightness: Brightness.light,
  );
  return ThemeData(
    colorScheme: scheme,
    scaffoldBackgroundColor: const Color(0xFFF6F7F5),
    useMaterial3: true,
    appBarTheme: const AppBarTheme(
      backgroundColor: Color(0xFFF6F7F5),
      surfaceTintColor: Colors.transparent,
    ),
    cardTheme: CardThemeData(
      color: Colors.white,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    ),
  );
}

ThemeData buildDarkTheme() {
  final scheme =
      ColorScheme.fromSeed(
        seedColor: KronosPalette.brand,
        brightness: Brightness.dark,
      ).copyWith(
        primary: KronosPalette.brand,
        secondary: KronosPalette.brightAccent,
        tertiary: KronosPalette.subtleAccent,
        surface: KronosPalette.darkSurface,
        onSurface: Colors.white,
        onPrimary: Colors.white,
        onSecondary: KronosPalette.darkBackground,
        onTertiary: KronosPalette.darkBackground,
      );
  return ThemeData(
    colorScheme: scheme,
    scaffoldBackgroundColor: KronosPalette.darkBackground,
    useMaterial3: true,
    appBarTheme: const AppBarTheme(
      backgroundColor: KronosPalette.darkBackground,
      foregroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
    ),
    cardTheme: CardThemeData(
      color: KronosPalette.darkSurface,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    ),
    dividerColor: Colors.white.withValues(alpha: 0.12),
  );
}
