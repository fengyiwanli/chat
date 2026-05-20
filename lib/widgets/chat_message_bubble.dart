import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/chat_message.dart';

class ChatMessageBubble extends StatelessWidget {
  final ChatMessage message;
  final bool isMe;
  final bool isNarration;
  final Color color;
  final String userName;
  final String? avatarPath;
  final bool isAnimating;
  final Widget? statusWidget;
  final VoidCallback onLongPressMessage;
  final VoidCallback? onImageTap;
  final VoidCallback? onImageLongPress;
  final String? timeText; 
  const ChatMessageBubble({
    super.key,
    required this.message,
    required this.isMe,
    required this.isNarration,
    required this.color,
    required this.userName,
    this.avatarPath,
    this.isAnimating = false,
    this.statusWidget,
    required this.onLongPressMessage,
    this.onImageTap,
    this.onImageLongPress,
    this.timeText,    
  });

  String _cleanMessageText(ChatMessage msg) {
    String text = msg.text;
    if (!msg.isUser && msg.sender != '📖 旁白' && msg.sender != '📖 系统') {
      final name = RegExp.escape(msg.sender);
      final pattern = RegExp('^$name[：:]\\s*');
      text = text.replaceFirst(pattern, '');
    }
    return text;
  }

  String _sanitizeText(String input) {
    if (input.isEmpty) return input;
    return input.replaceAllMapped(
      RegExp(r'([\uD800-\uDBFF][\uDC00-\uDFFF])|[\uD800-\uDFFF]'),
      (match) => match.group(1) != null ? match.group(1)! : '',
    );
  }

  @override
  Widget build(BuildContext context) {
    Widget content = Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment:
            isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          if (!isMe) _buildSenderName(),
          Row(
            mainAxisAlignment:
                isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
            children: [
              if (!isMe) _buildAvatar(),
              Flexible(child: _buildBubbleContainer(context)),
              if (isMe) _buildMyAvatar(),
            ],
          ),
        ],
      ),
    );

    final fullMessage = GestureDetector(
      onLongPress: onLongPressMessage,
      child: content,
    );

    if (isAnimating) {
      return TweenAnimationBuilder<double>(
        tween: Tween(begin: 0.0, end: 1.0),
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
        builder: (context, value, child) {
          return Opacity(
            opacity: value,
            child: Transform.translate(
              offset: Offset(0, 20 * (1 - value)),
              child: child,
            ),
          );
        },
        child: fullMessage,
      );
    }

    return fullMessage;
  }

  Widget _buildSenderName() {
    return Padding(
      padding: const EdgeInsets.only(left: 12, bottom: 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            message.sender,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 12,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAvatar() {
    final hasAvatar = avatarPath != null &&
        avatarPath!.isNotEmpty &&
        File(avatarPath!).existsSync();

    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: CircleAvatar(
        radius: 14,
        backgroundColor: hasAvatar ? null : color.withOpacity(0.2),
        // 【关键优化】：使用 ResizeImage 在解码阶段压缩头像内存，防止长列表 OOM
        backgroundImage: hasAvatar ? ResizeImage(FileImage(File(avatarPath!)), width: 100) : null,
        child: hasAvatar
            ? null
            : Text(
                message.sender.isNotEmpty ? message.sender[0] : '?',
                style: TextStyle(color: color, fontWeight: FontWeight.bold),
              ),
      ),
    );
  }
  Widget _buildMyAvatar() {
    return Padding(
      padding: const EdgeInsets.only(left: 8),
      child: CircleAvatar(
        radius: 14,
        backgroundColor: Colors.deepPurple.shade100,
        child: Text(
          userName.isNotEmpty ? userName[0] : '我',
          style: const TextStyle(
            color: Colors.deepPurple,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  Widget _buildBubbleContainer(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: isMe
    ? (Theme.of(context).brightness == Brightness.dark
        ? Colors.grey.shade800      // 深色模式用深灰
        : Theme.of(context).colorScheme.primaryContainer)  // 浅色模式用主题色
    : color.withOpacity(0.1),
        border: Border.all(color: color.withOpacity(0.3)),
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(20),
          topRight: const Radius.circular(20),
          bottomLeft: isMe ? const Radius.circular(20) : Radius.zero,
          bottomRight: isMe ? Radius.zero : const Radius.circular(20),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          SelectableText(
  _sanitizeText(_cleanMessageText(message)),
  style: TextStyle(
    fontSize: 16,
    color: isMe
        ? (Theme.of(context).brightness == Brightness.dark
            ? Colors.white                    // 深色模式：白色文字
            : Theme.of(context).colorScheme.onPrimaryContainer)  // 浅色模式：跟随主题文字色
        : null,                               // 非上帝指令保持默认
  ),
  
),
if (timeText != null)
    Padding(
      padding: const EdgeInsets.only(top: 4.0),
      child: Align(
        alignment: Alignment.centerRight,
        child: Text(
          timeText!,
          style: TextStyle(
            fontSize: 11,
            color: isMe
                ? Colors.white.withOpacity(0.7)
                : Colors.grey.shade600,
          ),
        ),
      ),
    ),
          if (!isMe && !isNarration && message.sender != '系统' && statusWidget != null)
            statusWidget!,
          if (message.imageUrl != null) _buildImageContent(context),
        ],
      ),
    );
  }

  Widget _buildImageContent(BuildContext context) {
    final isNetwork = message.imageUrl!.startsWith('http');
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: GestureDetector(
        onTap: onImageTap,
        onLongPress: onImageLongPress,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: isNetwork
              ? CachedNetworkImage(
                  imageUrl: message.imageUrl!,
                  width: 200,
                  height: 200,
                  fit: BoxFit.cover,
                  // 【关键优化】：限制网络图片的最大缓存像素，防止内存泄漏
                  memCacheWidth: 600, 
                )
              : Image.file(
                  File(message.imageUrl!),
                  width: 200,
                  height: 200,
                  fit: BoxFit.cover,
                  // 【关键优化】：限制本地大图加载到内存的尺寸
                  cacheWidth: 600, 
                ),
        ),
      ),
    );
  }

}