import 'package:flutter/material.dart';
import '../services/theme_provider.dart';
import 'character_hub_page.dart';
import 'novel_hub_page.dart';
import 'gallery_page.dart';
import 'settings_page.dart';
import 'package:path_provider/path_provider.dart';

class HomePage extends StatefulWidget {
  final ThemeProvider themeProvider;

  const HomePage({super.key, required this.themeProvider});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _currentIndex = 0;
  final GlobalKey<GalleryPageState> galleryKey = GlobalKey();
  final List<Widget> _pages = [];

  @override
  void initState() {
    super.initState();
    _pages.addAll([
      CharacterHubPage(themeProvider: widget.themeProvider),
      const NovelHubPage(),
      GalleryPage(key: galleryKey),
      SettingsPage(themeProvider: widget.themeProvider),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _currentIndex, children: _pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (index) {
          setState(() => _currentIndex = index);
          if (index == 2) galleryKey.currentState?.loadGallery();
        },
        animationDuration: const Duration(milliseconds: 400),
        indicatorColor: const Color(0xFFC7705C).withOpacity(0.12),
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.transparent,
        height: 64,
        destinations: const [
          NavigationDestination(icon: Icon(Icons.chat_bubble_outline), selectedIcon: Icon(Icons.chat_bubble), label: '聊天'),
          NavigationDestination(icon: Icon(Icons.menu_book_outlined), selectedIcon: Icon(Icons.menu_book), label: '小说'),
          NavigationDestination(icon: Icon(Icons.photo_library_outlined), selectedIcon: Icon(Icons.photo_library), label: '图库'),
          NavigationDestination(icon: Icon(Icons.settings_outlined), selectedIcon: Icon(Icons.settings), label: '设置'),
        ],
      ),
    );
  }
}