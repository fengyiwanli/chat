import 'package:flutter/material.dart';

class ChatController extends ChangeNotifier {
  final String sessionId;
  List<String> memoryEvents = [];

  ChatController({required this.sessionId});

  Future<void> addMemoryEvent(String event) async {
    memoryEvents.add(event);
    try {
      debugPrint('RAG 已存入记忆: $event');
    } catch (e) {
      debugPrint('RAG 存入失败: $e');
    }
    notifyListeners();
  }
}
