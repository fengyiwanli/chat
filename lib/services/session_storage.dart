import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/character.dart';
import '../models/chat_message.dart';

/// Per-session persistence: messages, participants, events, memory, tokens, summaries, branches.
class SessionStorage {
  static const _messagesPrefix = 'messages_';
  static const _participantsPrefix = 'participants_';
  static const _eventsPrefix = 'events_';
  static const _worldSettingPrefix = 'world_';
  static const _memoryPrefix = 'memory_';
  static const _sessionTokensPrefix = 'session_tokens_';
  static const _longTermMemoryPrefix = 'ltm_';
  static const _branchArchiveKey = 'branch_archives_';
  static const _summaryPrefix = 'summary_';
  static const _summaryIndexPrefix = 'summary_idx_';
  static const _chatNarrationPromptPrefix = 'chat_narration_';
  static const _chatSummaryPromptPrefix = 'chat_summary_';
  static const _sceneCardsKey = 'scene_cards';

  // ── Messages ──
  static Future<List<ChatMessage>> loadMessages(String sessionId) async {
    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString('$_messagesPrefix$sessionId');
    if (json == null || json.isEmpty) return [];
    final list = jsonDecode(json) as List<dynamic>;
    return list.map((e) => ChatMessage.fromJson(e)).toList();
  }

  static Future<void> saveMessages(String sessionId, List<ChatMessage> messages) async {
    final prefs = await SharedPreferences.getInstance();
    final json = jsonEncode(messages.map((m) => m.toJson()).toList());
    await prefs.setString('$_messagesPrefix$sessionId', json);
  }

  // ── Participants ──
  static Future<void> saveParticipants(String sessionId, List<Character> participants) async {
    final prefs = await SharedPreferences.getInstance();
    final json = Character.listToJson(participants);
    await prefs.setString('$_participantsPrefix$sessionId', json);
  }

  static Future<List<Character>> loadParticipants(String sessionId) async {
    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString('$_participantsPrefix$sessionId');
    if (json == null || json.isEmpty) return [];
    return Character.listFromJson(json);
  }

  // ── Event History ──
  static Future<List<String>> loadEventHistory(String sessionId) async {
    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString('$_eventsPrefix$sessionId');
    if (json == null || json.isEmpty) return [];
    return List<String>.from(jsonDecode(json));
  }

  static Future<void> addEventToHistory(String sessionId, String event) async {
    final prefs = await SharedPreferences.getInstance();
    final events = await loadEventHistory(sessionId);
    events.add(event);
    await prefs.setString('$_eventsPrefix$sessionId', jsonEncode(events));
  }

  // ── World Setting ──
  static Future<String> loadWorldSetting(String sessionId) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('$_worldSettingPrefix$sessionId') ?? '';
  }

  static Future<void> saveWorldSetting(String sessionId, String setting) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('$_worldSettingPrefix$sessionId', setting);
  }

  // ── Memory Events ──
  static Future<List<String>> loadMemoryEvents(String sessionId) async {
    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString('$_memoryPrefix$sessionId');
    if (json == null || json.isEmpty) return [];
    return List<String>.from(jsonDecode(json));
  }

  static Future<void> addMemoryEvent(String sessionId, String event) async {
    final prefs = await SharedPreferences.getInstance();
    final events = await loadMemoryEvents(sessionId);
    events.add(event);
    await prefs.setString('$_memoryPrefix$sessionId', jsonEncode(events));
  }

  static Future<void> removeMemoryEvent(String sessionId, int index) async {
    final prefs = await SharedPreferences.getInstance();
    final events = await loadMemoryEvents(sessionId);
    if (index >= 0 && index < events.length) {
      events.removeAt(index);
      await prefs.setString('$_memoryPrefix$sessionId', jsonEncode(events));
    }
  }

  static Future<void> saveMemoryEvents(String sessionId, List<String> events) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('$_memoryPrefix$sessionId', jsonEncode(events));
  }

  // ── Session Tokens ──
  static Future<int> loadSessionTokens(String sessionId) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt('$_sessionTokensPrefix$sessionId') ?? 0;
  }

  static Future<void> saveSessionTokens(String sessionId, int tokens) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('$_sessionTokensPrefix$sessionId', tokens);
  }

  static Future<void> addSessionTokens(String sessionId, int amount) async {
    final current = await loadSessionTokens(sessionId);
    await saveSessionTokens(sessionId, current + amount);
  }

  // ── Long-Term Memory ──
  static Future<List<String>> loadLongTermMemories(String sessionId) async {
    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString('$_longTermMemoryPrefix$sessionId');
    if (json == null || json.isEmpty) return [];
    return List<String>.from(jsonDecode(json));
  }

  static Future<void> addLongTermMemory(String sessionId, String memory) async {
    final prefs = await SharedPreferences.getInstance();
    final memories = await loadLongTermMemories(sessionId);
    memories.add(memory);
    while (memories.length > 50) {
      memories.removeAt(0);
    }
    await prefs.setString('$_longTermMemoryPrefix$sessionId', jsonEncode(memories));
  }

  static Future<void> updateLongTermMemory(String sessionId, int index, String memory) async {
    final prefs = await SharedPreferences.getInstance();
    final memories = await loadLongTermMemories(sessionId);
    if (index >= 0 && index < memories.length) {
      memories[index] = memory;
      await prefs.setString('$_longTermMemoryPrefix$sessionId', jsonEncode(memories));
    }
  }

  static Future<void> deleteLongTermMemory(String sessionId, int index) async {
    final prefs = await SharedPreferences.getInstance();
    final memories = await loadLongTermMemories(sessionId);
    if (index >= 0 && index < memories.length) {
      memories.removeAt(index);
      await prefs.setString('$_longTermMemoryPrefix$sessionId', jsonEncode(memories));
    }
  }

  // ── Branch Archives ──
  static Future<List<Map<String, dynamic>>> loadBranchArchives(String parentSessionId) async {
    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString('$_branchArchiveKey$parentSessionId');
    if (json == null || json.isEmpty) return [];
    final list = jsonDecode(json) as List<dynamic>;
    return list.map((e) => Map<String, dynamic>.from(e)).toList();
  }

  static Future<void> saveBranchArchives(String parentSessionId, List<Map<String, dynamic>> branches) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('$_branchArchiveKey$parentSessionId', jsonEncode(branches));
  }

  // ── Summary ──
  static Future<String> loadLatestSummary(String sessionId) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('$_summaryPrefix$sessionId') ?? '';
  }

  static Future<void> saveLatestSummary(String sessionId, String summary) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('$_summaryPrefix$sessionId', summary);
  }

  static Future<int> loadLatestSummaryIndex(String sessionId) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt('$_summaryIndexPrefix$sessionId') ?? 0;
  }

  static Future<void> saveLatestSummaryIndex(String sessionId, int index) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('$_summaryIndexPrefix$sessionId', index);
  }

  // ── Per-Session Prompts ──
  static Future<String> loadChatNarrationPrompt(String sessionId) async {
    final prefs = await SharedPreferences.getInstance();
    final key = '$_chatNarrationPromptPrefix$sessionId';
    return prefs.getString(key) ?? '';
  }

  static Future<void> saveChatNarrationPrompt(String sessionId, String prompt) async {
    final prefs = await SharedPreferences.getInstance();
    final key = '$_chatNarrationPromptPrefix$sessionId';
    if (prompt.isEmpty) {
      await prefs.remove(key);
    } else {
      await prefs.setString(key, prompt);
    }
  }

  static Future<String> loadChatSummaryPrompt(String sessionId) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('$_chatSummaryPromptPrefix$sessionId') ?? '';
  }

  static Future<void> saveChatSummaryPrompt(String sessionId, String prompt) async {
    final prefs = await SharedPreferences.getInstance();
    if (prompt.isEmpty) {
      await prefs.remove('$_chatSummaryPromptPrefix$sessionId');
    } else {
      await prefs.setString('$_chatSummaryPromptPrefix$sessionId', prompt);
    }
  }

  // ── Smart Memory ──
  static Future<bool> loadSmartMemoryEnabled(String sessionId) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('smart_memory_$sessionId') ?? true;
  }

  static Future<void> saveSmartMemoryEnabled(String sessionId, bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('smart_memory_$sessionId', enabled);
  }

  // ── Current Style / Status IDs ──
  static Future<String> loadCurrentStyleId(String sessionId) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('current_style_id_$sessionId') ?? 'normal';
  }

  static Future<void> saveCurrentStyleId(String sessionId, String id) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('current_style_id_$sessionId', id);
  }

  static Future<String> loadCurrentStatusStyleId(String sessionId) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('current_status_style_id_$sessionId') ?? 'default';
  }

  static Future<void> saveCurrentStatusStyleId(String sessionId, String id) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('current_status_style_id_$sessionId', id);
  }

  // ── Scene Cards ──
  static Future<List<Map<String, String>>> loadSceneCards() async {
    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString(_sceneCardsKey);
    if (json == null || json.isEmpty) return [];
    final list = jsonDecode(json) as List<dynamic>;
    return list.map((e) => Map<String, String>.from(e)).toList();
  }

  static Future<void> saveSceneCards(List<Map<String, String>> cards) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_sceneCardsKey, jsonEncode(cards));
  }

  // ── Session Lifecycle ──
  static Future<void> deleteSession(String sessionId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('$_messagesPrefix$sessionId');
    await prefs.remove('$_participantsPrefix$sessionId');
    await prefs.remove('$_eventsPrefix$sessionId');
    await prefs.remove('$_worldSettingPrefix$sessionId');
    await prefs.remove('$_memoryPrefix$sessionId');
    await prefs.remove('$_sessionTokensPrefix$sessionId');
  }

  static Future<void> cloneSessionTo(String sourceSessionId, String targetSessionId) async {
    final messages = await loadMessages(sourceSessionId);
    await saveMessages(targetSessionId, messages);
    final participants = await loadParticipants(sourceSessionId);
    await saveParticipants(targetSessionId, participants);
    final events = await loadEventHistory(sourceSessionId);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('$_eventsPrefix$targetSessionId', jsonEncode(events));
    final world = await loadWorldSetting(sourceSessionId);
    await saveWorldSetting(targetSessionId, world);
    final memories = await loadMemoryEvents(sourceSessionId);
    await prefs.setString('$_memoryPrefix$targetSessionId', jsonEncode(memories));
  }
}
