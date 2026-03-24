import 'package:flutter/material.dart';

class AppTheme {
  static const Color primaryColor = Color(0xFFE7E0D4);
  static const Color secondaryColor = Color(0xFFB08B57);
  static const Color backgroundColor = Color(0xFF090B0D);
  static const Color sidebarColor = Color(0xFF0F1317);
  static const Color surfaceColor = Color(0xFF14191F);
  static const Color elevatedSurfaceColor = Color(0xFF1A2027);
  static const Color borderColor = Color(0xFF262D35);
  static const Color mutedTextColor = Color(0xFF97A0AA);
  static const Color successColor = Color(0xFF7FD1A5);
  static const Color errorColor = Color(0xFFF18A8A);

  static BoxDecoration get appBackgroundDecoration => const BoxDecoration(
    gradient: LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [Color(0xFF0C1014), Color(0xFF090B0D)],
    ),
  );

  static BoxDecoration panelDecoration({
    bool elevated = false,
    bool selected = false,
  }) {
    return BoxDecoration(
      color: selected
          ? const Color(0xFF1D252E)
          : elevated
          ? elevatedSurfaceColor
          : surfaceColor,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(
        color: selected ? secondaryColor : borderColor,
      ),
      boxShadow: const [
        BoxShadow(
          color: Color(0x33000000),
          blurRadius: 20,
          offset: Offset(0, 10),
        ),
      ],
    );
  }

  static ThemeData get darkTheme {
    final base = ThemeData(
      brightness: Brightness.dark,
      useMaterial3: true,
      scaffoldBackgroundColor: backgroundColor,
      primaryColor: primaryColor,
      colorScheme: const ColorScheme.dark(
        primary: primaryColor,
        secondary: secondaryColor,
        surface: surfaceColor,
        error: errorColor,
      ),
    );

    return base.copyWith(
      textTheme: base.textTheme.apply(
        bodyColor: primaryColor,
        displayColor: primaryColor,
      ),
      dividerColor: borderColor,
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: elevatedSurfaceColor,
        hintStyle: const TextStyle(color: mutedTextColor),
        labelStyle: const TextStyle(color: mutedTextColor),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: borderColor),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: borderColor),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: secondaryColor),
        ),
      ),
      dataTableTheme: const DataTableThemeData(
        headingRowColor: WidgetStatePropertyAll(elevatedSurfaceColor),
        dataRowColor: WidgetStatePropertyAll(surfaceColor),
        headingTextStyle: TextStyle(
          color: primaryColor,
          fontWeight: FontWeight.w700,
        ),
        dataTextStyle: TextStyle(color: primaryColor),
        dividerThickness: 0.4,
      ),
    );
  }
}
