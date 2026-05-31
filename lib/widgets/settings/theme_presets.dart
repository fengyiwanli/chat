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
    name: '深海蓝',
    primary: Color(0xFF1976D2),
    secondary: Color(0xFF42A5F5),
    background: Color(0xFFFAFAFA),
    surface: Color(0xFFFFFFFF),
    textPrimary: Color(0xFF212121),
    textSecondary: Color(0xFF757575),
    brightness: Brightness.light,
  ),
  AppTheme(
    name: '森林绿',
    primary: Color(0xFF2E7D32),
    secondary: Color(0xFF66BB6A),
    background: Color(0xFFFAFAFA),
    surface: Color(0xFFFFFFFF),
    textPrimary: Color(0xFF212121),
    textSecondary: Color(0xFF757575),
    brightness: Brightness.light,
  ),
  AppTheme(
    name: '日落橙',
    primary: Color(0xFFE64A19),
    secondary: Color(0xFFFF7043),
    background: Color(0xFFFAFAFA),
    surface: Color(0xFFFFFFFF),
    textPrimary: Color(0xFF212121),
    textSecondary: Color(0xFF757575),
    brightness: Brightness.light,
  ),
  AppTheme(
    name: '薄荷青',
    primary: Color(0xFF00897B),
    secondary: Color(0xFF26A69A),
    background: Color(0xFFFAFAFA),
    surface: Color(0xFFFFFFFF),
    textPrimary: Color(0xFF212121),
    textSecondary: Color(0xFF757575),
    brightness: Brightness.light,
  ),
  AppTheme(
    name: '暗夜黑',
    primary: Color(0xFF90CAF9),
    secondary: Color(0xFF42A5F5),
    background: Color(0xFF121212),
    surface: Color(0xFF1E1E1E),
    textPrimary: Color(0xFFFFFFFF),
    textSecondary: Color(0xFFB0B0B0),
    brightness: Brightness.dark,
  ),
  AppTheme(
    name: '墨绿黑',
    primary: Color(0xFFA5D6A7),
    secondary: Color(0xFF66BB6A),
    background: Color(0xFF121212),
    surface: Color(0xFF1E1E1E),
    textPrimary: Color(0xFFFFFFFF),
    textSecondary: Color(0xFFB0B0B0),
    brightness: Brightness.dark,
  ),
  AppTheme(
    name: '紫夜',
    primary: Color(0xFFCE93D8),
    secondary: Color(0xFFAB47BC),
    background: Color(0xFF121212),
    surface: Color(0xFF1E1E1E),
    textPrimary: Color(0xFFFFFFFF),
    textSecondary: Color(0xFFB0B0B0),
    brightness: Brightness.dark,
  ),
  AppTheme(
    name: '琥珀夜',
    primary: Color(0xFFFFCC80),
    secondary: Color(0xFFFFB74D),
    background: Color(0xFF121212),
    surface: Color(0xFF1E1E1E),
    textPrimary: Color(0xFFFFFFFF),
    textSecondary: Color(0xFFB0B0B0),
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
