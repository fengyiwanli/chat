import 'dart:convert'; // 用于 jsonDecod

class ChatMessage {
  final String text;
  final bool isUser;
  final String sender;
  final DateTime timestamp;
  String? imageUrl;
  bool isGeneratingImage;
  Map<String, String>? statusSnapshot;
  ChatMessage({
    required String text, // 注意这里改为无默认值
    required this.isUser,
    this.imageUrl,
    this.isGeneratingImage = false,
    required this.sender,
    this.statusSnapshot,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now(),
        text = _sanitizeText(text); // 在初始化列表中清洗

  static String _sanitizeText(String input) {
    if (input.isEmpty) return input;
    // 移除无效的UTF-16代理对
    return input.replaceAllMapped(
      RegExp(r'([\uD800-\uDBFF][\uDC00-\uDFFF])|[\uD800-\uDFFF]'),
      (match) {
        // 保留合法的代理对，删除孤立的代理
        if (match.group(1) != null) {
          return match.group(1)!; // 是完整的代理对，保留
        }
        return ''; // 是孤立的代理半区，删除
      },
    );
  }

  // 保存时忽略图片链接（不持久化图片）
  Map<String, dynamic> toJson() => {
  'text': text,
  'isUser': isUser,
  'sender': sender,
  'timestamp': timestamp.toIso8601String(), // timestamp永远不会为null
  'imageUrl': imageUrl,
  'isGeneratingImage': isGeneratingImage,
  // 只有statusSnapshot不为null时才保存
  if (statusSnapshot != null) 'statusSnapshot': jsonEncode(statusSnapshot),
};

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
  return ChatMessage(
    text: json['text'] as String? ?? '', // 加默认值，防止text为null
    isUser: json['isUser'] as bool? ?? false, // 加默认值
    sender: json['sender'] as String? ?? '未知', // 加默认值
    // ✅ 核心修复：如果timestamp为null，使用当前时间作为默认值
    timestamp: json['timestamp'] != null 
        ? DateTime.parse(json['timestamp'] as String) 
        : DateTime.now(),
    imageUrl: json['imageUrl'] as String?,
    isGeneratingImage: json['isGeneratingImage'] as bool? ?? false,
    // 恢复状态快照
    statusSnapshot: json['statusSnapshot'] != null
        ? Map<String, String>.from(jsonDecode(json['statusSnapshot'] as String))
        : null,
  );
}
}
