import 'package:flutter/material.dart';

class ChatInputBar extends StatelessWidget {
  // 需要从 ChatPage 传进来的东西
  final TextEditingController textController;
  final FocusNode focusNode;
  final bool isExpanded;
  final VoidCallback onSend;                // 点击发送按钮
  final VoidCallback onToggleExpand;       // 切换输入框高度
  final VoidCallback onMention;            // 提及角色
  final VoidCallback onGenerateImage;      // 生成图片
  final Color primaryColor;
  final String text;                       // 用于判断发送按钮是否可用
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
    required this.onTextChanged
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // 控制输入框的最大行数
    final maxLines = isExpanded ? 6 : 1;
    final isEmpty = text.trim().isEmpty;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        // 跟随主题切换
        color: Theme.of(context).brightness == Brightness.dark
            ? const Color(0xFF1E1E1E)
            : Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.grey.shade300,
            offset: const Offset(0, -1),
            blurRadius: 4,
          ),
        ],
      ),
      child: Row(
        children: [
          // 输入框（占据剩余空间）
          Expanded(
            child: TextField(
              controller: textController,
              focusNode: focusNode,
              minLines: 1,
              maxLines: maxLines,
              textInputAction: TextInputAction.send,
              decoration: const InputDecoration(
                hintText: '输入消息...',
                border: InputBorder.none,
              ),
              onSubmitted: (_) => onSend(),
              onChanged: (_) {
                // 让父组件知道文本变化（用于刷新发送按钮状态）
                // 注意：ChatInputBar 自己是 StatelessWidget，
                // 所以文本变化需要通过父组件 setState 传递进来。
                // 我们暂时不在这里处理，因为父组件会在 onChanged 里自己调用 setState。
                onTextChanged(textController.text);
              },
              
            ),
          ),

          // 更多操作菜单
          PopupMenuButton<String>(
            icon: Icon(Icons.add_circle_outline, color: primaryColor),
            tooltip: '更多',
            onSelected: (value) {
              switch (value) {
                case 'mention':
                  onMention();
                  break;
                case 'image':
                  onGenerateImage();
                  break;
                case 'expand':
                  onToggleExpand();
                  break;
              }
            },
            itemBuilder: (ctx) => [
              const PopupMenuItem(
                value: 'mention',
                child: ListTile(
                  leading: Icon(Icons.alternate_email),
                  title: Text('提及角色'),
                ),
              ),
              const PopupMenuItem(
                value: 'image',
                child: ListTile(
                  leading: Icon(Icons.photo_library_outlined),
                  title: Text('生成图片'),
                ),
              ),
              PopupMenuItem(
                value: 'expand',
                child: ListTile(
                  leading: Icon(
                    isExpanded ? Icons.expand_less : Icons.expand_more,
                  ),
                  title: Text(isExpanded ? '收起输入框' : '展开输入框'),
                ),
              ),
            ],
          ),

          // 发送按钮（空输入时禁用）
          IconButton(
            icon: const Icon(Icons.send),
            color: isEmpty
                ? const Color.fromARGB(255, 26, 3, 233) // 禁用色（你自己定）
                : primaryColor,
            onPressed: isEmpty ? null : onSend,
          ),
        ],
      ),
    );
  }
}