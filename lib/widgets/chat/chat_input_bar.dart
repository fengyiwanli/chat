import 'package:flutter/material.dart';

class ChatInputBar extends StatelessWidget {
  final TextEditingController textController;
  final FocusNode focusNode;
  final bool isExpanded;
  final VoidCallback onSend;
  final VoidCallback onToggleExpand;
  final VoidCallback onMention;
  final VoidCallback onGenerateImage;
  final Color primaryColor;
  final String text;
  final ValueChanged<String> onTextChanged;

  const ChatInputBar({
    Key? key,
    required this.textController,
    required this.focusNode,
    required this.isExpanded,
    required this.onSend,
    required this.onToggleExpand,
    required this.onMention,
    required this.onGenerateImage,
    required this.primaryColor,
    required this.text,
    required this.onTextChanged,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final maxLines = isExpanded ? 6 : 1;
    final isEmpty = text.trim().isEmpty;

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 10),
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        border: Border(
          top: BorderSide(color: Theme.of(context).dividerColor.withOpacity(0.3)),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Container(
              constraints: const BoxConstraints(maxHeight: 160),
              decoration: BoxDecoration(
                color: Theme.of(context).brightness == Brightness.dark
                    ? const Color(0xFF2A2A2E)
                    : const Color(0xFFF5F2ED),
                borderRadius: BorderRadius.circular(22),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: TextField(
                controller: textController,
                focusNode: focusNode,
                minLines: 1,
                maxLines: maxLines,
                textInputAction: TextInputAction.send,
                style: TextStyle(fontSize: 15, color: Theme.of(context).colorScheme.onSurface),
                decoration: const InputDecoration(
                  hintText: '输入消息...',
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(vertical: 8),
                ),
                onSubmitted: (_) => onSend(),
                onChanged: (_) => onTextChanged(textController.text),
              ),
            ),
          ),
          const SizedBox(width: 4),
          PopupMenuButton<String>(
            icon: Icon(Icons.add_circle_outline, color: primaryColor, size: 26),
            tooltip: '更多',
            onSelected: (value) {
              switch (value) {
                case 'mention': onMention();
                case 'image': onGenerateImage();
                case 'expand': onToggleExpand();
              }
            },
            itemBuilder: (ctx) => [
              const PopupMenuItem(value: 'mention', child: ListTile(leading: Icon(Icons.alternate_email), title: Text('提及角色'))),
              const PopupMenuItem(value: 'image', child: ListTile(leading: Icon(Icons.photo_library_outlined), title: Text('生成图片'))),
              PopupMenuItem(value: 'expand', child: ListTile(
                leading: Icon(isExpanded ? Icons.expand_less : Icons.expand_more),
                title: Text(isExpanded ? '收起输入框' : '展开输入框'),
              )),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.send_rounded),
            color: isEmpty ? Theme.of(context).colorScheme.onSurface.withOpacity(0.2) : primaryColor,
            onPressed: isEmpty ? null : onSend,
          ),
        ],
      ),
    );
  }
}