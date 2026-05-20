// lib/services/ai_service.dart
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'storage_service.dart';

/// API 响应封装
class AiResponse {
  final String content;
  final int promptTokens;
  final int completionTokens;
  final int totalTokens;

  AiResponse({
    required this.content,
    required this.promptTokens,
    required this.completionTokens,
    required this.totalTokens,
  });
}

class AiService {
  // 根据角色设置的 aiModel 标签，从存储中查找对应的 API 配置并调用
  static Future<AiResponse> callChatApi({
    required String modelLabel, // 对应 Character 的 aiModel 字段
    required List<Map<String, dynamic>> messages,
  }) async {
    // 1. 获取保存的 API 配置列表
    final configs = await StorageService.loadChatApiConfigs();
    // 2. 找到 label 匹配的配置
    final config = configs.cast<Map<String, String>?>().firstWhere(
      (c) => c!['label'] == modelLabel,
      orElse: () => null,
    );

    if (config == null) {
      // 配置缺失时返回空内容，token 为 0
      return AiResponse(
        content: '错误：未找到 AI 配置 "$modelLabel"，请先在设置里添加。',
        promptTokens: 0,
        completionTokens: 0,
        totalTokens: 0,
      );
    }

    final url = config['url']!;
    final model = config['model']!;
    final apiKey = config['apiKey']!;

    try {
      final response = await http.post(
        Uri.parse(url),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $apiKey',
        },
        body: jsonEncode({
          'model': model,
          'messages': messages,
          'temperature': 0.9,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        // 兼容 OpenAI 格式（DeepSeek / Gemini 兼容接口都支持）
        final content = data['choices'][0]['message']['content'] ?? '';

        // 提取 usage
        final usage = data['usage'] ?? {};
        final promptTokens = usage['prompt_tokens'] ?? 0;
        final completionTokens = usage['completion_tokens'] ?? 0;
        final totalTokens = usage['total_tokens'] ?? 0;

        return AiResponse(
          content: content,
          promptTokens: promptTokens,
          completionTokens: completionTokens,
          totalTokens: totalTokens,
        );
      } else {
        return AiResponse(
          content: '请求失败 (${response.statusCode})：${response.body}',
          promptTokens: 0,
          completionTokens: 0,
          totalTokens: 0,
        );
      }
    } catch (e) {
      return AiResponse(
        content: '网络错误：$e',
        promptTokens: 0,
        completionTokens: 0,
        totalTokens: 0,
      );
    }
  }

  static Future<Map<String, String>?> parseCharacterText(
    String text, {
    String modelLabel = '', // 可传空，内部尝试获取
  }) async {
    final systemPrompt =
        '你是一个角色设定解析器。请从输入文本中提取角色属性，并输出JSON，键名：name,personality,attire,background,catchphrase,likes,dislikes,speakingStyle。缺失属性留空字符串。只输出JSON。';
    try {
      final response = await callChatApi(
        modelLabel: modelLabel.isNotEmpty ? modelLabel : 'deepseek',
        messages: [
          {'role': 'system', 'content': systemPrompt},
          {'role': 'user', 'content': '解析：$text'},
        ],
      );
      final map = Map<String, String>.from(jsonDecode(response.content.trim()));
      return map;
    } catch (e) {
      print('解析角色失败: $e');
      return null;
    }
  }
}
