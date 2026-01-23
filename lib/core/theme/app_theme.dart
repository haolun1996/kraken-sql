import 'package:flutter/material.dart';

class AppTheme {
  // Colors
  static const Color primaryColor = Color(0xFF000000);
  static const Color secondaryColor = Color(0xFFD4AF37);
  static const Color backgroundColor = Color(0xFF121212); // Deep Dark

  // Glass Effects
  static const double glassBlur = 20.0;
  static const double glassOpacity = 0.15;
  static const double glassBorderOpacity = 0.3;

  static LinearGradient glassGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Colors.white.withOpacity(glassOpacity), Colors.white.withOpacity(glassOpacity * 0.5)],
  );

  static LinearGradient glassBorderGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Colors.white.withOpacity(glassBorderOpacity),
      Colors.white.withOpacity(glassBorderOpacity * 0.1),
    ],
  );

  static ThemeData get darkTheme {
    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: Colors.transparent,
      primaryColor: primaryColor,
      textTheme: ThemeData.dark().textTheme.copyWith(
        bodyLarge: const TextStyle(fontFamily: '.SF NS Text'),
        bodyMedium: const TextStyle(fontFamily: '.SF NS Text'),
      ),
      useMaterial3: true,
      colorScheme: ColorScheme.dark(
        primary: primaryColor,
        secondary: secondaryColor,
        surface: Colors.transparent, // Important for glass layers
      ),
    );
  }
}
