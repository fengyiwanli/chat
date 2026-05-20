import 'dart:io';
import 'package:flutter/material.dart';
import '../services/storage_service.dart';
import 'package:share_plus/share_plus.dart';
import '../utils/app_dialogs.dart';
import '../utils/app_snackbars.dart';

class GalleryPage extends StatefulWidget {
  const GalleryPage({super.key});

  @override
  State<GalleryPage> createState() => GalleryPageState();
}

class GalleryPageState extends State<GalleryPage> {
  List<String> _imagePaths = [];
  bool _isSelecting = false;
  final Set<String> _selectedPaths = {};

  @override
  void initState() {
    super.initState();
    loadGallery();
  }

  Future<void> loadGallery() async {
    final paths = await StorageService.loadGalleryPaths();
    setState(() => _imagePaths = paths.reversed.toList());
  }

  // 删除单张图片（不再自动刷新列表，由调用方处理）
  // 优化后的代码（单个文件删除失败不影响其他）
Future<void> _deleteImageFile(String path) async {
  try {
    final file = File(path);
    if (await file.exists()) {
      await file.delete();
    }
    await StorageService.removeGalleryPath(path);
  } catch (e) {
    print('删除图片失败: $path, 错误: $e');
    // 单个文件删除失败，继续删除其他的
  }
}

  void _showImageOptions(String path) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.share),
              title: const Text('分享 / 保存'),
              onTap: () {
                Navigator.pop(ctx);
                Share.shareXFiles([XFile(path)]);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete, color: Colors.red),
              title: const Text('删除'),
              // 替换后的代码（加了确认框）
onTap: () async {
  Navigator.pop(ctx);
  final confirm = await AppDialogs.showConfirmDialog(
    context,
    title: '删除图片',
    content: '确定要删除这张图片吗？',
    confirmText: '删除',
    isDestructive: true,
  );
  if (confirm) {
    await _deleteImageFile(path);
    loadGallery();
  }
},
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isSelecting ? '已选择 ${_selectedPaths.length} 张' : '我的图库'),
        centerTitle: true,
        actions: [
          if (_isSelecting) ...[
            IconButton(
              icon: const Icon(Icons.select_all),
              tooltip: '全选',
              onPressed: () {
                setState(() {
                  if (_selectedPaths.length == _imagePaths.length) {
                    _selectedPaths.clear();
                  } else {
                    _selectedPaths.addAll(_imagePaths);
                  }
                });
              },
            ),
            IconButton(
              icon: const Icon(Icons.share),
              tooltip: '分享',
              onPressed: _selectedPaths.isEmpty
                  ? null
                  : () {
                      final files = _selectedPaths
                          .map((p) => XFile(p))
                          .toList();
                      Share.shareXFiles(files);
                    },
            ),
            IconButton(
              icon: const Icon(Icons.delete, color: Colors.red),
              tooltip: '删除',
              onPressed: _selectedPaths.isEmpty
                  ? null
                  : () async {
                      // 替换后的代码
final confirm = await AppDialogs.showConfirmDialog(
  context,
  title: '删除所选图片',
  content: '确定要删除 ${_selectedPaths.length} 张图片吗？',
  confirmText: '删除',
  isDestructive: true, // 删除是危险操作，按钮变红
);
                      
                      
                      if (confirm == true) {
  // 👇👇👇 并行删除所有选中的图片（同时执行，速度快N倍）
  final deleteFutures = _selectedPaths.map((path) => _deleteImageFile(path)).toList();
  await Future.wait(deleteFutures); // 等待所有删除操作同时完成

  setState(() {
    _selectedPaths.clear();
    _isSelecting = false;
  });
  loadGallery(); // 批量删除后统一刷新
}
                    },
            ),
          ] else
            IconButton(
              icon: const Icon(Icons.checklist),
              tooltip: '选择',
              onPressed: () {
                setState(() => _isSelecting = true);
              },
            ),
        ],
      ),
      body: _imagePaths.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.photo_library_outlined,
                    size: 80,
                    color: Colors.grey.shade400,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '图库是空的',
                    style: TextStyle(fontSize: 18, color: Colors.grey.shade600),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '在聊天中生成图片吧！',
                    style: TextStyle(fontSize: 14, color: Colors.grey.shade500),
                  ),
                ],
              ),
            )
          : GridView.builder(
              padding: const EdgeInsets.all(12),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
              ),
              itemCount: _imagePaths.length,
              itemBuilder: (context, index) {
                final path = _imagePaths[index];
                final isSelected = _selectedPaths.contains(path);
                return GestureDetector(
                  onTap: () {
  if (_isSelecting) {
    setState(() {
      if (isSelected) {
        _selectedPaths.remove(path);
        if (_selectedPaths.isEmpty) _isSelecting = false;
      } else {
        _selectedPaths.add(path);
      }
    });
  } else {
    // 非选择模式：点击查看大图
    _showFullScreenImage(context, path);
  }
},
                  onLongPress: () {
                    if (!_isSelecting) {
                      _showImageOptions(path);
                    }
                  },
                  child: Stack(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: // 优化后的代码（只加载200×200像素，足够网格显示）
Image.file(
  File(path),
  fit: BoxFit.cover,
  cacheWidth: 200, // 缓存宽度200像素
  cacheHeight: 200, // 缓存高度200像素
),
                      ),
                      if (_isSelecting)
                        Positioned(
                          top: 8,
                          right: 8,
                          child: Icon(
                            isSelected
                                ? Icons.check_circle
                                : Icons.circle_outlined,
                            color: isSelected
                                ? Colors.deepPurple
                                : Colors.white,
                            size: 28,
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
    );
  }
}
// 查看全屏大图
void _showFullScreenImage(BuildContext context, String imagePath) {
  showDialog(
    context: context,
    barrierColor: Colors.black87,
    builder: (context) => Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: EdgeInsets.zero,
      child: Stack(
        children: [
          InteractiveViewer(
            minScale: 0.5,
            maxScale: 4.0,
            child: Center(
              child: Image.file(
                File(imagePath),
                fit: BoxFit.contain,
                width: double.infinity,
                height: double.infinity,
              ),
            ),
          ),
          Positioned(
            top: 40,
            right: 20,
            child: IconButton(
              icon: const Icon(Icons.close, color: Colors.white, size: 30),
              onPressed: () => Navigator.pop(context),
            ),
          ),
        ],
      ),
    ),
  );
}