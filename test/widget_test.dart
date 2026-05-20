import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/main.dart';
// 👉 导入你的ThemeProvider（路径和main.dart里的保持一致）
import 'package:flutter_application_1/services/theme_provider.dart';

void main() {
  testWidgets('App启动测试', (WidgetTester tester) async {
    // 先创建ThemeProvider实例
    final themeProvider = ThemeProvider();
    
    // 传递给MyApp
    await tester.pumpWidget(MyApp(themeProvider: themeProvider));

    // 验证应用能正常启动（原来的计数器测试已经不适用了）
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}