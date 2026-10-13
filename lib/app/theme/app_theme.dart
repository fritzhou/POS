import 'package:flutter/material.dart';

import '../config/app_brand.dart';

abstract final class AppTheme {
  static ThemeData get light {
    final colors = ColorScheme.fromSeed(
      seedColor: AppBrand.primaryColor,
      secondary: AppBrand.secondaryColor,
      brightness: Brightness.light,
      surface: Colors.white,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: colors,
      scaffoldBackgroundColor: const Color(0xfff4f7fb),
      visualDensity: VisualDensity.standard,
      textTheme: ThemeData.light().textTheme.apply(
        bodyColor: AppBrand.navyColor,
        displayColor: AppBrand.navyColor,
      ),
      cardTheme: CardThemeData(
        color: Colors.white,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0xffe6ebf2)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xfff8fafc),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xffdce4ee)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xffdce4ee)),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(48, 48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      navigationBarTheme: const NavigationBarThemeData(
        backgroundColor: Colors.white,
        indicatorColor: Color(0xffdbeafe),
      ),
      dividerTheme: const DividerThemeData(color: Color(0xffe6ebf2)),
    );
  }
}
