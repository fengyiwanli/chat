import 'package:flutter/material.dart';

class ThemeProvider extends ChangeNotifier {
  // 默认主题：和你main.dart里的完全一致
  ThemeData _themeData = ThemeData(
    colorScheme: ColorScheme.fromSeed(
      seedColor: const Color(0xFF6366F1),
      brightness: Brightness.light,
      primary: const Color(0xFF6366F1),
      secondary: const Color(0xFF8B5CF6),
      surface: const Color(0xFFFAFAFA),
      background: const Color(0xFFF8FAFC),
      error: const Color(0xFFEF4444),
      onPrimary: Colors.white,
      onSurface: const Color(0xFF1E293B),
      onBackground: const Color(0xFF1E293B),
    ),
    useMaterial3: true,
    textTheme: const TextTheme(
      titleLarge: TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w600,
        color: Color(0xFF1E293B),
      ),
      bodyLarge: TextStyle(
        fontSize: 16,
        height: 1.5,
        color: Color(0xFF1E293B),
      ),
      bodyMedium: TextStyle(
        fontSize: 15,
        height: 1.5,
        color: Color(0xFF475569),
      ),
      labelSmall: TextStyle(
        fontSize: 12,
        color: Color(0xFF94A3B8),
      ),
    ),
    appBarTheme: const AppBarTheme(
      centerTitle: true,
      elevation: 0,
      backgroundColor: Color(0xFFF8FAFC),
      foregroundColor: Color(0xFF1E293B),
      titleTextStyle: TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w600,
        color: Color(0xFF1E293B),
      ),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      shadowColor: Colors.transparent,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      color: Colors.white,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        elevation: 0,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFF6366F1), width: 2),
      ),
      filled: true,
      fillColor: const Color(0xFFF8FAFC),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      hintStyle: const TextStyle(color: Color(0xFF94A3B8)),
    ),
    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      backgroundColor: Colors.white,
      selectedItemColor: Color(0xFF6366F1),
      unselectedItemColor: Color(0xFF94A3B8),
      showSelectedLabels: true,
      showUnselectedLabels: true,
      elevation: 8,
    ),
  );

  ThemeData get themeData => _themeData;

  // 完整主题切换方法（适配你的Material3）
  void setThemeData(ThemeData themeData) {
    _themeData = themeData;
    notifyListeners();
  }

  // 保留原来的纯色切换方法（兼容旧代码）
  void setSeedColor(Color color) {
    _themeData = ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: color,
        brightness: Brightness.light,
      ),
      useMaterial3: true,
      // 继承你所有的全局样式
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