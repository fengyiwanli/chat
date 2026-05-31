import 'package:flutter/material.dart';

class SceneCardManager extends StatefulWidget {
  final List<Map<String, String>> cards;
  final ValueChanged<List<Map<String, String>>> onUpdated;

  const SceneCardManager({super.key, required this.cards, required this.onUpdated});

  @override
  State<SceneCardManager> createState() => _SceneCardManagerState();
}

class _SceneCardManagerState extends State<SceneCardManager> {
  late List<Map<String, String>> _cards;

  @override
  void initState() {
    super.initState();
    _cards = List.from(widget.cards);
  }

  void _addCard() {
    final titleCtrl = TextEditingController();
    final eventCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('添加场景卡'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: titleCtrl,
              decoration: const InputDecoration(labelText: '标题', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: eventCtrl,
              decoration: const InputDecoration(labelText: '事件描述', border: OutlineInputBorder()),
              maxLines: 3,
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(
            onPressed: () {
              if (titleCtrl.text.isNotEmpty && eventCtrl.text.isNotEmpty) {
                _cards.add({'title': titleCtrl.text, 'event': eventCtrl.text});
                setState(() {});
                widget.onUpdated(_cards);
                Navigator.pop(ctx);
              }
            },
            child: const Text('添加'),
          ),
        ],
      ),
    );
  }

  void _deleteCard(int index) {
    _cards.removeAt(index);
    setState(() {});
    widget.onUpdated(_cards);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('管理场景卡'),
      content: SizedBox(
        width: double.maxFinite,
        height: 400,
        child: _cards.isEmpty
            ? const Center(child: Text('暂无场景卡'))
            : ListView.builder(
                itemCount: _cards.length,
                itemBuilder: (_, i) => ListTile(
                  title: Text(_cards[i]['title']!),
                  subtitle: Text(_cards[i]['event']!, maxLines: 1, overflow: TextOverflow.ellipsis),
                  trailing: IconButton(icon: const Icon(Icons.delete), onPressed: () => _deleteCard(i)),
                ),
              ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('关闭')),
        ElevatedButton.icon(icon: const Icon(Icons.add), label: const Text('新场景卡'), onPressed: _addCard),
      ],
    );
  }
}
