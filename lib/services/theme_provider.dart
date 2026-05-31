import 'package:flutter/material.dart';

class ThemeProvider extends ChangeNotifier {
  ThemeData _themeData = ThemeData(
    colorScheme: const ColorScheme(
      brightness: Brightness.light,
      primary: Color(0xFFC7705C),
      onPrimary: Colors.white,
      secondary: Color(0xFFE8A87C),
      onSecondary: Color(0xFF2D2A26),
      surface: Colors.white,
      onSurface: Color(0xFF2D2A26),
      error: Color(0xFFD35E4A),
      onError: Colors.white,
    ),
    scaffoldBackgroundColor: const Color(0xFFFBF8F4),
    useMaterial3: true,
    textTheme: const TextTheme(
      titleLarge: TextStyle(
        fontSize: 22, fontWeight: FontWeight.w700,
        color: Color(0xFF2D2A26), letterSpacing: -0.3,
      ),
      titleMedium: TextStyle(
        fontSize: 18, fontWeight: FontWeight.w600,
        color: Color(0xFF2D2A26), letterSpacing: -0.2,
      ),
      bodyLarge: TextStyle(
        fontSize: 16, height: 1.6, color: Color(0xFF2D2A26),
      ),
      bodyMedium: TextStyle(
        fontSize: 15, height: 1.55, color: Color(0xFF5C5853),
      ),
      labelSmall: TextStyle(
        fontSize: 12, color: Color(0xFF8C8882),
      ),
    ),
    appBarTheme: const AppBarTheme(
      centerTitle: true,
      elevation: 0,
      scrolledUnderElevation: 0.5,
      backgroundColor: Color(0xFFFBF8F4),
      foregroundColor: Color(0xFF2D2A26),
      surfaceTintColor: Colors.transparent,
      titleTextStyle: TextStyle(
        fontSize: 18, fontWeight: FontWeight.w700,
        color: Color(0xFF2D2A26), letterSpacing: -0.2,
      ),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: Colors.white,
      surfaceTintColor: Colors.transparent,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: const Color(0xFF2D2A26).withOpacity(0.06)),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: const Color(0xFFC7705C),
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 13),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        elevation: 0,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: const Color(0xFFC7705C),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: const Color(0xFF2D2A26).withOpacity(0.12)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: const Color(0xFF2D2A26).withOpacity(0.1)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFFC7705C), width: 1.5),
      ),
      filled: true,
      fillColor: const Color(0xFFF5F2ED),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
      hintStyle: const TextStyle(color: Color(0xFFB8B4AD), fontSize: 15),
    ),
    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      backgroundColor: Colors.white,
      selectedItemColor: Color(0xFFC7705C),
      unselectedItemColor: Color(0xFFB8B4AD),
      elevation: 0,
      type: BottomNavigationBarType.fixed,
    ),
  );

  ThemeData get themeData => _themeData;

  void setThemeData(ThemeData themeData) {
    _themeData = themeData;
    notifyListeners();
  }

  void setSeedColor(Color color) {
    _themeData = ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: color, brightness: Brightness.light),
      useMaterial3: true,
      textTheme: _themeData.textTheme,
      appBarTheme: _themeData.appBarTheme,
      cardTheme: _themeData.cardTheme,
      filledButtonTheme: _themeData.filledButtonTheme,
      textButtonTheme: _themeData.textButtonTheme,
      inputDecorationTheme: _themeData.inputDecorationTheme,
      bottomNavigationBarTheme: _themeData.bottomNavigationBarTheme,
    );
    notifyListeners();
  }
}