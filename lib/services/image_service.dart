import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import '../services/storage_service.dart';
import 'dart:async'; // 用于轮询定时器

class ImageService {
  static Future<String?> generateImage(String prompt) async {
  // 1. 获取图库目录（只获取一次，避免重复调用）
  final appDir = await getApplicationDocumentsDirectory();
  final galleryDir = Directory('${appDir.path}/gallery');
  
  // 2. 确保图库目录存在
  if (!await galleryDir.exists()) {
    await galleryDir.create(recursive: true);
  }

  // 3. 统一的缓存检查（只做一次）
  final targetHash = '_${prompt.hashCode}';
  final allFiles = await galleryDir.list().toList();
  
  for (final file in allFiles) {
    if (file is File && file.path.contains(targetHash)) {
      print('使用缓存图片: ${file.path}');
      return file.path;
    }
  }

  // 4. 自动清理旧图片（保留最近100张，防止占用过多空间）
  // 你可以把100改成你想要的数量，比如200
  if (allFiles.length > 100) {
    // 按修改时间排序，最旧的排在前面
    allFiles.sort((a, b) => a.statSync().modified.compareTo(b.statSync().modified));
    // 删除最旧的一张
    await allFiles.first.delete();
    print('已自动删除最旧的图片: ${allFiles.first.path}');
  }

  // 5. 加载当前激活的图片API配置（原来的逻辑不变）
  final activeLabel = await StorageService.loadActiveImageApiLabel();
  final configs = await StorageService.loadImageApiConfigs();
  Map<String, String>? config;
  
  if (activeLabel.isNotEmpty) {
    config = configs.cast<Map<String, String>?>().firstWhere(
      (c) => c?['label'] == activeLabel,
      orElse: () => null,
    );
  }

  if (config == null) {
    // 没有配置或标签为空，退回默认 Pollinations
    return _pollinationsGenerate(prompt);
  }

  final url = config['url']!;
  final token = config['token'] ?? '';
  final requestType = config['requestType'] ?? 'get';
  final bodyTemplate = config['bodyTemplate'] ?? '';

  if (requestType == 'post') {
    return _postGenerate(url, token, prompt, bodyTemplate);
  } else {
    return _pollinationsGenerate(prompt); // 或其他 GET 方式
  }
}
  // Pollinations 免费接口（GET）
  static Future<String?> _pollinationsGenerate(String prompt) async {
    try {
      final encoded = Uri.encodeComponent(prompt);
      final url = Uri.parse(
        'https://image.pollinations.ai/prompt/$encoded?width=512&height=512&nologo=true',
      );
      final response = await http.get(url);
      if (response.statusCode == 200 && response.bodyBytes.isNotEmpty) {
        return await _saveImage(response.bodyBytes, prompt: prompt);
      }
    } catch (e) {
      print('Pollinations 生成失败: $e');
    }
    return null;
  }

  // 通用 POST 调用
  // 通用 POST 调用
  // 通用 POST 调用
static Future<String?> _postGenerate(
  String url,
  String token,
  String prompt,
  String bodyTemplate,
) async {
  try {
    Map<String, String> headers = {'Content-Type': 'application/json'};
    if (token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }
    // 对 prompt 进行 JSON 转义，避免破坏 JSON 结构
    final safePrompt = jsonEncode(prompt);
    // 如果模板包含 "{{prompt}}"，先替换；也兼容 {{prompt}} 无引号的情况
    String body = bodyTemplate
        .replaceAll('"{{prompt}}"', safePrompt)
        .replaceAll('{{prompt}}', safePrompt);
    final response = await http.post(
      Uri.parse(url),
      headers: headers,
      body: body,
    );
    if (response.statusCode == 200 || response.statusCode == 201) {
      final data = jsonDecode(response.body);
      // 1. 直接返回图片二进制或 base64 (Perchance 服务等)
      if (data['success'] == true && data['image_base64'] != null) {
        try {
          final bytes = base64Decode(data['image_base64']);
          return await _saveImage(bytes, prompt: prompt); // ✅ 修正
        } catch (e) {
          print('Base64 解码失败: $e');
          return null;
        }
      }
      // 2. StableHorde 异步任务处理 (返回 id)
      if (data['id'] != null) {
        final taskId = data['id'];
        // 轮询直到完成
        String statusUrl =
            'https://stablehorde.net/api/v2/generate/status/$taskId';
        // 最多尝试30次，每次间隔2秒
        for (int i = 0; i < 30; i++) {
          await Future.delayed(const Duration(seconds: 2));
          final statusRes = await http.get(
            Uri.parse(statusUrl),
            headers: headers,
          );
          if (statusRes.statusCode == 200) {
            final statusData = jsonDecode(statusRes.body);
            if (statusData['done'] == true &&
                statusData['generations'] != null &&
                statusData['generations'].isNotEmpty) {
              final imgUrl = statusData['generations'][0]['img'];
              if (imgUrl != null && imgUrl.isNotEmpty) {
                final imgResp = await http.get(Uri.parse(imgUrl));
                if (imgResp.statusCode == 200) {
                  return await _saveImage(imgResp.bodyBytes, prompt: prompt); // ✅ 修正
                }
              }
              break;
            } else if (statusData['faulted'] == true) {
              print('StableHorde 任务失败');
              break;
            }
          }
        }
        return null; // 超时或失败
      }
      // 3. 其他直接返回 generations 的 API（如 StableHorde 的同步终点、某些兼容API）
      if (data['generations'] != null && data['generations'].isNotEmpty) {
        final imgUrl = data['generations'][0]['img'];
        if (imgUrl != null && imgUrl.isNotEmpty) {
          if (imgUrl.startsWith('data:image')) {
            final bytes = base64Decode(imgUrl.split(',').last);
            return await _saveImage(bytes, prompt: prompt); // ✅ 修正
          } else {
            final imgResp = await http.get(Uri.parse(imgUrl));
            if (imgResp.statusCode == 200) {
              return await _saveImage(imgResp.bodyBytes, prompt: prompt); // ✅ 修正
            }
          }
        }
      }
      // 4. DeepAI 等 output_url
      if (data['output_url'] != null) {
        final imgResp = await http.get(Uri.parse(data['output_url']));
        if (imgResp.statusCode == 200) {
          return await _saveImage(imgResp.bodyBytes, prompt: prompt); // ✅ 修正
        }
      }
      print('无法从响应中提取图片: ${response.body}');
    } else {
      print('图片 API 返回错误 ${response.statusCode}: ${response.body}');
    }
  } catch (e) {
    print('POST 图片生成失败: $e');
  }
  return null;
}
  static Future<String?> _saveImage(
    List<int> bytes, {
    String prompt = '',
  }) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final galleryDir = Directory('${dir.path}/gallery');
      if (!await galleryDir.exists()) {
        await galleryDir.create(recursive: true);
      }
      // 文件名包含 prompt 哈希（若没有则用时间戳）
      String hashPart = prompt.isNotEmpty ? '_${prompt.hashCode}' : '';
      final fileName =
          'img$hashPart-${DateTime.now().millisecondsSinceEpoch}.png';
      final file = File('${galleryDir.path}/$fileName');
      await file.writeAsBytes(bytes);
      return file.path;
    } catch (e) {
      print('图片保存失败: $e');
      return null;
    }
  }
}
