import 'package:flutter/material.dart';

/// 通用弹窗工具类
/// 所有确认框、提示框都通过这里调用，统一样式和行为
class AppDialogs {
  /// 通用确认对话框
  /// [isDestructive] 设为true时，确认按钮会变成红色（用于删除等危险操作）
  static Future<bool> showConfirmDialog(
    BuildContext context, {
    required String title,
    required String content,
    String confirmText = '确定',
    String cancelText = '取消',
    bool isDestructive = false,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(content),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20), // 和你原来的弹窗圆角保持一致
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(cancelText),
          ),
          FilledButton(
            style: isDestructive
                ? FilledButton.styleFrom(backgroundColor: Colors.red)
                : null,
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(confirmText),
          ),
        ],
      ),
    );
    // 如果用户点击空白处关闭弹窗，返回false
    return result ?? false;
  }

  /// 通用输入对话框
  static Future<String?> showInputDialog(
    BuildContext context, {
    required String title,
    String hintText = '',
    String initialValue = '',
    String confirmText = '确定',
    String cancelText = '取消',
    int maxLines = 1,
  }) async {
    final controller = TextEditingController(text: initialValue);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        content: TextField(
          controller: controller,
          maxLines: maxLines,
          decoration: InputDecoration(
            hintText: hintText,
            // 👇 这里去掉了错误的const
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, null),
            child: Text(cancelText),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: Text(confirmText),
          ),
        ],
      ),
    );
    return result;
  }
}