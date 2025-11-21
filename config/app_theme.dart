import 'package:flutter/material.dart';

class AppTheme {
  // Color Palette
  static const Color primary = Color(0xFFED4C5C);
  static const Color secondary = Color(0xFF2A9D8F);
  static const Color warning = Color(0xFFF4A261);
  static const Color success = Color(0xFF2A9D8F);
  static const Color headerDark = Color(0xFF264653);
  static const Color backgroundLight = Color(0xFFF7F7F7);
  static const Color textDark = Color(0xFF264653);
  static const Color textLight = Color(0xFFFFFFFF);

  static ThemeData get lightTheme {
    return ThemeData(
      primaryColor: primary,
      scaffoldBackgroundColor: backgroundLight,
      colorScheme: ColorScheme.light(
        primary: primary,
        secondary: secondary,
        error: primary,
        surface: Colors.white,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: headerDark,
        foregroundColor: textLight,
        elevation: 0,
        centerTitle: true,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: textLight,
          padding: EdgeInsets.symmetric(horizontal: 32, vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            fontFamily: 'Roboto',
          ),
        ),
      ),
      textTheme: TextTheme(
        displayLarge: TextStyle(
          fontSize: 32,
          fontWeight: FontWeight.bold,
          color: headerDark,
          fontFamily: 'Roboto',
        ),
        displayMedium: TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.w600,
          color: headerDark,
          fontFamily: 'Roboto',
        ),
        bodyLarge: TextStyle(
          fontSize: 16,
          color: textDark,
          fontFamily: 'Roboto',
        ),
        bodyMedium: TextStyle(
          fontSize: 14,
          color: textDark,
          fontFamily: 'Roboto',
        ),
        labelLarge: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: textDark,
          fontFamily: 'Roboto Condensed',
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        color: Colors.white,
      ),
    );
  }

  // Gradient for urgent states
  static const LinearGradient urgentGradient = LinearGradient(
    colors: [primary, warning],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  // Spacing constants
  static const double spacingXS = 4.0;
  static const double spacingS = 8.0;
  static const double spacingM = 16.0;
  static const double spacingL = 24.0;
  static const double spacingXL = 32.0;

  // Button sizes
  static const double buttonHeightRegular = 48.0;
  static const double buttonHeightLarge = 56.0;
  static const double buttonHeightSmall = 36.0;
}
