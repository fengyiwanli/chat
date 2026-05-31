import 'package:flutter/material.dart';

class AppTheme {
  final String name;
  final Color primary;
  final Color secondary;
  final Color background;
  final Color surface;
  final Color textPrimary;
  final Color textSecondary;
  final Brightness brightness;

  AppTheme({
    required this.name,
    required this.primary,
    required this.secondary,
    required this.background,
    required this.surface,
    required this.textPrimary,
    required this.textSecondary,
    required this.brightness,
  });
}

final List<AppTheme> presetThemes = [
  AppTheme(
    name: '暖陶',
    primary: Color(0xFFC7705C),
    secondary: Color(0xFFE8A87C),
    background: Color(0xFFFBF8F4),
    surface: Color(0xFFFFFFFF),
    textPrimary: Color(0xFF2D2A26),
    textSecondary: Color(0xFF8C8882),
    brightness: Brightness.light,
  ),
  AppTheme(
    name: '松烟',
    primary: Color(0xFF5B7B6F),
    secondary: Color(0xFF8FBF9F),
    background: Color(0xFFF5F3EF),
    surface: Color(0xFFFFFFFF),
    textPrimary: Color(0xFF2D2A26),
    textSecondary: Color(0xFF7A7670),
    brightness: Brightness.light,
  ),
  AppTheme(
    name: '暮橙',
    primary: Color(0xFFD4845A),
    secondary: Color(0xFFF0C4A0),
    background: Color(0xFFFBF7F3),
    surface: Color(0xFFFFFFFF),
    textPrimary: Color(0xFF2D2A26),
    textSecondary: Color(0xFF8A8580),
    brightness: Brightness.light,
  ),
  AppTheme(
    name: '青瓷',
    primary: Color(0xFF6B9E8A),
    secondary: Color(0xFFB5D8C7),
    background: Color(0xFFF5F7F3),
    surface: Color(0xFFFFFFFF),
    textPrimary: Color(0xFF2D2A26),
    textSecondary: Color(0xFF7C7A73),
    brightness: Brightness.light,
  ),
  AppTheme(
    name: '墨夜',
    primary: Color(0xFF8FA4B8),
    secondary: Color(0xFFBCCFDE),
    background: Color(0xFF1C1B1F),
    surface: Color(0xFF252429),
    textPrimary: Color(0xFFFFFFFF),
    textSecondary: Color(0xFFB0ADB8),
    brightness: Brightness.dark,
  ),
  AppTheme(
    name: '黛青夜',
    primary: Color(0xFF8CB5A0),
    secondary: Color(0xFFB8D8C8),
    background: Color(0xFF1A1C1A),
    surface: Color(0xFF232623),
    textPrimary: Color(0xFFFFFFFF),
    textSecondary: Color(0xFFB0BAB3),
    brightness: Brightness.dark,
  ),
  AppTheme(
    name: '紫夜',
    primary: Color(0xFFB8A0C8),
    secondary: Color(0xFFD4C4DE),
    background: Color(0xFF1E1B20),
    surface: Color(0xFF272329),
    textPrimary: Color(0xFFFFFFFF),
    textSecondary: Color(0xFFB8B0C0),
    brightness: Brightness.dark,
  ),
  AppTheme(
    name: '暖金夜',
    primary: Color(0xFFD4B896),
    secondary: Color(0xFFE8D5B8),
    background: Color(0xFF1F1D18),
    surface: Color(0xFF282620),
    textPrimary: Color(0xFFFFFFFF),
    textSecondary: Color(0xFFB8B0A0),
    brightness: Brightness.dark,
  ),
];

class ThemePreviewCard extends StatelessWidget {
  final AppTheme theme;
  final bool isSelected;
  final VoidCallback onTap;

  const ThemePreviewCard({super.key, required this.theme, required this.isSelected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: theme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? theme.primary : Colors.grey.shade300,
            width: isSelected ? 2 : 1,
          ),
        ),
        padding: const EdgeInsets.all(10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: double.infinity,
              height: 32,
              decoration: BoxDecoration(
                color: theme.primary,
                borderRadius: BorderRadius.circular(6),
              ),
              child: theme.brightness == Brightness.dark
                  ? Center(child: Icon(Icons.dark_mode, size: 14, color: theme.background))
                  : Center(child: Icon(Icons.light_mode, size: 14, color: theme.background)),
            ),
            const SizedBox(height: 4),
            Text(theme.name, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: theme.textPrimary)),
          ],
        ),
      ),
    );
  }
}