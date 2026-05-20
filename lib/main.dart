import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'screens/home_page.dart'; // 👉 确认这是你首页的正确路径
import 'services/theme_provider.dart'; // 👉 导入你的ThemeProvider
import 'package:provider/provider.dart';
import 'providers/chat_provider.dart';
void main() {
  // 先初始化Flutter绑定（解决Binding错误）
  WidgetsFlutterBinding.ensureInitialized();

  // 全局图片缓存限制（防止内存溢出）
  PaintingBinding.instance.imageCache.maximumSize = 100;
  PaintingBinding.instance.imageCache.maximumSizeBytes = 100 << 20;

  // 设置状态栏样式（沉浸式）
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
    ),
  );

  // 创建ThemeProvider实例（解决缺少参数的错误）
  final themeProvider = ThemeProvider();

  runApp(MyApp(themeProvider: themeProvider));
}

class MyApp extends StatelessWidget {
  final ThemeProvider themeProvider;
  const MyApp({super.key, required this.themeProvider});

  @override
  Widget build(BuildContext context) {
    // 👇 只加这一行：监听themeProvider变化
    return ListenableBuilder(
      listenable: themeProvider,
      builder: (context, child) {
        return MaterialApp(
          title: 'AI聊天助手',
          debugShowCheckedModeBanner: false,
          // 👇 把硬编码的theme改成这个
          theme: themeProvider.themeData,
          home: HomePage(themeProvider: themeProvider),
        );
      },
    );
  }
}


//