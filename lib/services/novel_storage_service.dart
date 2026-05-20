import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/novel_project.dart';
import '../models/chat_message.dart';

class NovelStorageService {
  static const _novelProjectsKey = 'novel_projects';
  static const _novelMessagesPrefix = 'novel_messages_';

  // ---------- 项目存取 ----------
  static Future<List<NovelProject>> loadProjects() async {
    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString(_novelProjectsKey);
    if (json == null || json.isEmpty) return [];
    final list = jsonDecode(json) as List;
    return list.map((e) => NovelProject.fromJson(e)).toList();
  }

  static Future<void> saveProjects(List<NovelProject> projects) async {
    final prefs = await SharedPreferences.getInstance();
    final json = jsonEncode(projects.map((p) => p.toJson()).toList());
    await prefs.setString(_novelProjectsKey, json);
  }

  // ---------- 消息历史（每个项目独立） ----------
  static Future<List<ChatMessage>> loadMessages(String projectId) async {
    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString('$_novelMessagesPrefix$projectId');
    if (json == null || json.isEmpty) return [];
    final list = jsonDecode(json) as List<dynamic>;
    return list.map((e) => ChatMessage.fromJson(e)).toList();
  }

  static Future<void> saveMessages(
    String projectId,
    List<ChatMessage> messages,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final json = jsonEncode(messages.map((m) => m.toJson()).toList());
    await prefs.setString('$_novelMessagesPrefix$projectId', json);
  }

  /// 更新单个小说项目（根据 id 找到并替换）
  static Future<void> updateProject(NovelProject project) async {
    final projects = await loadProjects();
    final index = projects.indexWhere((p) => p.id == project.id);
    if (index != -1) {
      projects[index] = project;
      await saveProjects(projects);
    }
  }

  // ---------- 小说记忆事件存取 (用项目ID作为键) ----------
  static const _novelMemoryPrefix = 'novel_memory_';

  static Future<List<String>> loadMemoryEvents(String projectId) async {
    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString('$_novelMemoryPrefix$projectId');
    if (json == null || json.isEmpty) return [];
    return List<String>.from(jsonDecode(json));
  }

  static Future<void> addMemoryEvent(String projectId, String event) async {
    final prefs = await SharedPreferences.getInstance();
    final events = await loadMemoryEvents(projectId);
    events.add(event);
    await prefs.setString('$_novelMemoryPrefix$projectId', jsonEncode(events));
  }

  static Future<void> removeMemoryEvent(String projectId, int index) async {
    final prefs = await SharedPreferences.getInstance();
    final events = await loadMemoryEvents(projectId);
    if (index >= 0 && index < events.length) {
      events.removeAt(index);
      await prefs.setString(
        '$_novelMemoryPrefix$projectId',
        jsonEncode(events),
      );
    }
  }

  // ---------- 小说增量总结索引 ----------
  static const _novelSummaryIndexPrefix = 'novel_summary_idx_';

  static Future<int> loadSummaryIndex(String projectId) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt('$_novelSummaryIndexPrefix$projectId') ?? 0;
  }

  static Future<void> saveSummaryIndex(String projectId, int index) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('$_novelSummaryIndexPrefix$projectId', index);
  }

  // ---------- 小说存档 ----------
  static const _novelSavesPrefix = 'novel_saves_'; // 存储存档ID列表
  static const _novelSaveDataPrefix = 'novel_save_data_'; // 每个存档的消息数据

  // 获取某个小说的所有存档ID
  static Future<List<String>> loadSaveIds(String projectId) async {
    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString('$_novelSavesPrefix$projectId');
    if (json == null || json.isEmpty) return [];
    return List<String>.from(jsonDecode(json));
  }

  // 保存存档ID列表
  static Future<void> saveSaveIds(String projectId, List<String> ids) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('$_novelSavesPrefix$projectId', jsonEncode(ids));
  }

  // 保存一份存档（复制当前消息）
  static Future<String> createSave(
    String projectId,
    String saveName,
    List<ChatMessage> messages,
    List<String> memoryEvents,
    int totalTokens,
  ) async {
    final saveId = 'save_${DateTime.now().millisecondsSinceEpoch}';
    final saveData = {
      'name': saveName,
      'messages': messages.map((m) => m.toJson()).toList(),
      'memoryEvents': memoryEvents, // 注意这里用的是 memoryEvents
      'totalTokens': totalTokens,
    };
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('$_novelSaveDataPrefix$saveId', jsonEncode(saveData));

    final ids = await loadSaveIds(projectId);
    ids.add(saveId);
    await saveSaveIds(projectId, ids);
    return saveId;
  }

  // 加载某份存档的消息
  static Future<Map<String, dynamic>> loadSaveData(String saveId) async {
    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString('$_novelSaveDataPrefix$saveId');
    if (json == null || json.isEmpty) {
      return {'messages': [], 'memoryEvents': [], 'totalTokens': 0};
    }
    final data = jsonDecode(json);
    final messages = (data['messages'] as List)
        .map((e) => ChatMessage.fromJson(e))
        .toList();
    final memoryEvents = (data['memoryEvents'] as List?)?.cast<String>() ?? [];
    final totalTokens = data['totalTokens'] ?? 0;
    return {
      'messages': messages,
      'memoryEvents': memoryEvents,
      'totalTokens': totalTokens,
    };
  }

  // 删除某份存档
  static Future<void> deleteSave(String projectId, String saveId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('$_novelSaveDataPrefix$saveId');
    final ids = await loadSaveIds(projectId);
    ids.remove(saveId);
    await saveSaveIds(projectId, ids);
  }

  // 获取某个小说的所有存档简要信息 (id + name)
  static Future<List<Map<String, String>>> loadSaveInfos(
    String projectId,
  ) async {
    final ids = await loadSaveIds(projectId);
    final prefs = await SharedPreferences.getInstance();
    final infos = <Map<String, String>>[];
    for (final id in ids) {
      final dataStr = prefs.getString('$_novelSaveDataPrefix$id');
      if (dataStr != null) {
        final data = jsonDecode(dataStr);
        infos.add({'id': id, 'name': data['name'] ?? '未命名'});
      }
    }
    return infos;
  }

  static const _novelProjectTokensKey = 'novel_project_tokens_';

  static Future<int> loadProjectTokens(String projectId) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt('$_novelProjectTokensKey$projectId') ?? 0;
  }

  static Future<void> saveProjectTokens(String projectId, int tokens) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('$_novelProjectTokensKey$projectId', tokens);
  }

  // ---------- 项目独立总结提示词 ----------
  static const _novelSummaryPromptKey = 'novel_summary_prompt_';

  /// 读取项目自己的总结提示词，没有则返回空字符串
  static Future<String> loadSummaryPrompt(String projectId) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('$_novelSummaryPromptKey$projectId') ?? '';
  }

  /// 保存项目自己的总结提示词，如果为空则删除对应键（表示用默认）
  static Future<void> saveSummaryPrompt(String projectId, String prompt) async {
    final prefs = await SharedPreferences.getInstance();
    if (prompt.isEmpty) {
      await prefs.remove('$_novelSummaryPromptKey$projectId');
    } else {
      await prefs.setString('$_novelSummaryPromptKey$projectId', prompt);
    }
  }

  /// 将存档 saveId 从原项目迁移到新项目 ID 下
  static Future<void> moveSaveToProject(
    String saveId,
    String newProjectId,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    // 1. 从原项目的存档列表中移除
    // 需要遍历所有项目，找到包含该 saveId 的项目，移除它
    final projects = await loadProjects();
    for (final p in projects) {
      final ids = await loadSaveIds(p.id);
      if (ids.contains(saveId)) {
        ids.remove(saveId);
        await saveSaveIds(p.id, ids);
        break;
      }
    }
    // 2. 把 saveId 添加到新项目的存档列表
    final newIds = await loadSaveIds(newProjectId);
    newIds.add(saveId);
    await saveSaveIds(newProjectId, newIds);
    // 存档数据本身（novel_save_data_saveId）不需要动，只改变归属
  }

  /// 将存档 saveId 的所有数据迁移为项目 newProjectId 的本体数据
  static Future<void> migrateSaveToProject(
    String saveId,
    String newProjectId,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final dataStr = prefs.getString('$_novelSaveDataPrefix$saveId');
    if (dataStr == null) return;
    final data = jsonDecode(dataStr);
    // 提取数据
    final List<dynamic> messagesJson = data['messages'] ?? [];
    final List<dynamic> memoryEventsJson = data['memoryEvents'] ?? [];
    final int totalTokens = data['totalTokens'] ?? 0;

    // 转换为对应的模型列表
    final messages = messagesJson.map((e) => ChatMessage.fromJson(e)).toList();
    final memoryEvents = memoryEventsJson.cast<String>();

    // 保存为本体数据
    await saveMessages(newProjectId, messages);
    await prefs.setString(
      '$_novelMemoryPrefix$newProjectId',
      jsonEncode(memoryEvents),
    );
    await saveProjectTokens(newProjectId, totalTokens);

    // 删除原存档数据
    await prefs.remove('$_novelSaveDataPrefix$saveId');
  }

  /// 删除项目时，同时清理该项目的相关数据（消息、记忆、token、总结索引、存档列表等）
  static Future<void> deleteProjectData(String projectId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('$_novelMessagesPrefix$projectId');
    await prefs.remove('$_novelMemoryPrefix$projectId');
    await prefs.remove('$_novelProjectTokensKey$projectId');
    await prefs.remove('$_novelSummaryIndexPrefix$projectId');
    await prefs.remove('$_novelSavesPrefix$projectId');
  }

  // 自动摘要设置（小说专用）
  static const _novelAutoSummaryEnabledKey = 'novel_auto_summary_enabled_';
  static const _novelAutoSummaryThresholdKey = 'novel_auto_summary_threshold_';
  static const _novelMaxMemoryCountKey = 'novel_max_memory_count_';

  static Future<bool> loadAutoSummaryEnabled(String projectId) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('$_novelAutoSummaryEnabledKey$projectId') ?? false;
  }

  static Future<void> saveAutoSummaryEnabled(
    String projectId,
    bool value,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('$_novelAutoSummaryEnabledKey$projectId', value);
  }

  static Future<int> loadAutoSummaryThreshold(String projectId) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt('$_novelAutoSummaryThresholdKey$projectId') ?? 20;
  }

  static Future<void> saveAutoSummaryThreshold(
    String projectId,
    int value,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('$_novelAutoSummaryThresholdKey$projectId', value);
  }

  static Future<int> loadMaxMemoryCount(String projectId) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt('$_novelMaxMemoryCountKey$projectId') ?? 5;
  }

  static Future<void> saveMaxMemoryCount(String projectId, int value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('$_novelMaxMemoryCountKey$projectId', value);
  }

  // 保存记忆事件列表（用于修剪）
  static Future<void> saveMemoryEvents(
    String projectId,
    List<String> events,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('$_novelMemoryPrefix$projectId', jsonEncode(events));
  }
}
