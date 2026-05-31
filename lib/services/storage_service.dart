import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/character.dart';
import '../models/chat_message.dart';
import 'session_storage.dart';
import 'config_storage.dart';

/// Unified facade over [SessionStorage] and [ConfigStorage].
/// All existing callers continue to work unchanged.
class StorageService {
  // ---- Character ----
  static Future<List<Character>> loadCharacters() => ConfigStorage.loadCharacters();
  static Future<void> saveCharacters(List<Character> c) => ConfigStorage.saveCharacters(c);

  static Future<void> deleteCharacter(String characterId) async {
    final characters = await ConfigStorage.loadCharacters();
    characters.removeWhere((c) => c.id == characterId);
    await ConfigStorage.saveCharacters(characters);
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('messages_chat_$characterId');
    await prefs.remove('participants_chat_$characterId');
    await prefs.remove('events_chat_$characterId');
    await prefs.remove('world_chat_$characterId');
  }

  // ---- Session persistence ----
  static Future<List<ChatMessage>> loadMessages(String sid) => SessionStorage.loadMessages(sid);
  static Future<void> saveMessages(String sid, List<ChatMessage> m) => SessionStorage.saveMessages(sid, m);
  static Future<void> saveParticipants(String sid, List<Character> p) => SessionStorage.saveParticipants(sid, p);
  static Future<List<Character>> loadParticipants(String sid) => SessionStorage.loadParticipants(sid);
  static Future<List<String>> loadEventHistory(String sid) => SessionStorage.loadEventHistory(sid);
  static Future<void> addEventToHistory(String sid, String e) => SessionStorage.addEventToHistory(sid, e);
  static Future<String> loadWorldSetting(String sid) => SessionStorage.loadWorldSetting(sid);
  static Future<void> saveWorldSetting(String sid, String s) => SessionStorage.saveWorldSetting(sid, s);
  static Future<List<String>> loadMemoryEvents(String sid) => SessionStorage.loadMemoryEvents(sid);
  static Future<void> addMemoryEvent(String sid, String e) => SessionStorage.addMemoryEvent(sid, e);
  static Future<void> removeMemoryEvent(String sid, int i) => SessionStorage.removeMemoryEvent(sid, i);
  static Future<void> saveMemoryEvents(String sid, List<String> e) => SessionStorage.saveMemoryEvents(sid, e);
  static Future<int> loadSessionTokens(String sid) => SessionStorage.loadSessionTokens(sid);
  static Future<void> saveSessionTokens(String sid, int t) => SessionStorage.saveSessionTokens(sid, t);
  static Future<void> addSessionTokens(String sid, int a) => SessionStorage.addSessionTokens(sid, a);
  static Future<List<String>> loadLongTermMemories(String sid) => SessionStorage.loadLongTermMemories(sid);
  static Future<void> addLongTermMemory(String sid, String m) => SessionStorage.addLongTermMemory(sid, m);
  static Future<void> updateLongTermMemory(String sid, int i, String m) => SessionStorage.updateLongTermMemory(sid, i, m);
  static Future<void> deleteLongTermMemory(String sid, int i) => SessionStorage.deleteLongTermMemory(sid, i);
  static Future<List<Map<String, dynamic>>> loadBranchArchives(String sid) => SessionStorage.loadBranchArchives(sid);
  static Future<void> saveBranchArchives(String sid, List<Map<String, dynamic>> b) => SessionStorage.saveBranchArchives(sid, b);
  static Future<String> loadLatestSummary(String sid) => SessionStorage.loadLatestSummary(sid);
  static Future<void> saveLatestSummary(String sid, String s) => SessionStorage.saveLatestSummary(sid, s);
  static Future<int> loadLatestSummaryIndex(String sid) => SessionStorage.loadLatestSummaryIndex(sid);
  static Future<void> saveLatestSummaryIndex(String sid, int i) => SessionStorage.saveLatestSummaryIndex(sid, i);
  static Future<String> loadChatNarrationPrompt(String sid) => SessionStorage.loadChatNarrationPrompt(sid);
  static Future<void> saveChatNarrationPrompt(String sid, String p) => SessionStorage.saveChatNarrationPrompt(sid, p);
  static Future<String> loadChatSummaryPrompt(String sid) => SessionStorage.loadChatSummaryPrompt(sid);
  static Future<void> saveChatSummaryPrompt(String sid, String p) => SessionStorage.saveChatSummaryPrompt(sid, p);
  static Future<bool> loadSmartMemoryEnabled(String sid) => SessionStorage.loadSmartMemoryEnabled(sid);
  static Future<void> saveSmartMemoryEnabled(String sid, bool e) => SessionStorage.saveSmartMemoryEnabled(sid, e);
  static Future<String> loadCurrentStyleId(String sid) => SessionStorage.loadCurrentStyleId(sid);
  static Future<void> saveCurrentStyleId(String sid, String id) => SessionStorage.saveCurrentStyleId(sid, id);
  static Future<String> loadCurrentStatusStyleId(String sid) => SessionStorage.loadCurrentStatusStyleId(sid);
  static Future<void> saveCurrentStatusStyleId(String sid, String id) => SessionStorage.saveCurrentStatusStyleId(sid, id);
  static Future<List<Map<String, String>>> loadSceneCards() => SessionStorage.loadSceneCards();
  static Future<void> saveSceneCards(List<Map<String, String>> c) => SessionStorage.saveSceneCards(c);
  static Future<void> deleteSession(String sid) => SessionStorage.deleteSession(sid);
  static Future<void> cloneSessionTo(String src, String dst) => SessionStorage.cloneSessionTo(src, dst);

  // ---- Global config ----
  static Future<List<Map<String, String>>> loadChatApiConfigs() => ConfigStorage.loadChatApiConfigs();
  static Future<void> saveChatApiConfigs(List<Map<String, String>> c) => ConfigStorage.saveChatApiConfigs(c);
  static Future<Map<String, String>> loadImageApiConfig() => ConfigStorage.loadImageApiConfig();
  static Future<void> saveImageApiConfig(Map<String, String> c) => ConfigStorage.saveImageApiConfig(c);
  static Future<List<Map<String, String>>> loadImageApiConfigs() => ConfigStorage.loadImageApiConfigs();
  static Future<void> saveImageApiConfigs(List<Map<String, String>> c) => ConfigStorage.saveImageApiConfigs(c);
  static Future<String> loadActiveImageApiLabel() => ConfigStorage.loadActiveImageApiLabel();
  static Future<void> saveActiveImageApiLabel(String l) => ConfigStorage.saveActiveImageApiLabel(l);
  static String get defaultNarrationPrompt => ConfigStorage.defaultNarrationPrompt;
  static Future<String> loadNarrationPrompt() => ConfigStorage.loadNarrationPrompt();
  static Future<void> saveNarrationPrompt(String p) => ConfigStorage.saveNarrationPrompt(p);
  static String get defaultBranchPrompt => ConfigStorage.defaultBranchPrompt;
  static Future<String> loadBranchPrompt() => ConfigStorage.loadBranchPrompt();
  static Future<void> saveBranchPrompt(String p) => ConfigStorage.saveBranchPrompt(p);
  static String get defaultRandomEventPrompt => ConfigStorage.defaultRandomEventPrompt;
  static Future<String> loadRandomEventPrompt() => ConfigStorage.loadRandomEventPrompt();
  static Future<void> saveRandomEventPrompt(String p) => ConfigStorage.saveRandomEventPrompt(p);
  static String get defaultSummaryPrompt => ConfigStorage.defaultSummaryPrompt;
  static Future<String> loadSummaryPrompt() => ConfigStorage.loadSummaryPrompt();
  static Future<void> saveSummaryPrompt(String p) => ConfigStorage.saveSummaryPrompt(p);
  static Future<List<Map<String, String>>> loadCustomStyles() => ConfigStorage.loadCustomStyles();
  static Future<void> saveCustomStyles(List<Map<String, String>> s) => ConfigStorage.saveCustomStyles(s);
  static Future<List<Map<String, String>>> loadCustomStatusStyles() => ConfigStorage.loadCustomStatusStyles();
  static Future<void> saveCustomStatusStyles(List<Map<String, String>> s) => ConfigStorage.saveCustomStatusStyles(s);
  static Future<List<String>> loadCustomStatusFields() => ConfigStorage.loadCustomStatusFields();
  static Future<void> saveCustomStatusFields(List<String> f) => ConfigStorage.saveCustomStatusFields(f);
  static Future<List<Map<String, String>>> loadChatStyles() => ConfigStorage.loadChatStyles();
  static Future<void> saveChatStyles(List<Map<String, String>> s) => ConfigStorage.saveChatStyles(s);
  static Future<List<Map<String, String>>> loadStatusStyles() => ConfigStorage.loadStatusStyles();
  static Future<void> saveStatusStyles(List<Map<String, String>> s) => ConfigStorage.saveStatusStyles(s);
  static Future<String> loadUserName() => ConfigStorage.loadUserName();
  static Future<void> saveUserName(String n) => ConfigStorage.saveUserName(n);
  static Future<String> loadUserPersonality() => ConfigStorage.loadUserPersonality();
  static Future<void> saveUserPersonality(String p) => ConfigStorage.saveUserPersonality(p);
  static Future<bool> loadShowEmotion() => ConfigStorage.loadShowEmotion();
  static Future<void> saveShowEmotion(bool v) => ConfigStorage.saveShowEmotion(v);
  static Future<String> loadImagePrefixModifier() => ConfigStorage.loadImagePrefixModifier();
  static Future<void> saveImagePrefixModifier(String p) => ConfigStorage.saveImagePrefixModifier(p);
  static Future<String> loadImageSuffixModifier() => ConfigStorage.loadImageSuffixModifier();
  static Future<void> saveImageSuffixModifier(String s) => ConfigStorage.saveImageSuffixModifier(s);
  static Future<bool> loadAutoSummaryEnabled() => ConfigStorage.loadAutoSummaryEnabled();
  static Future<void> saveAutoSummaryEnabled(bool v) => ConfigStorage.saveAutoSummaryEnabled(v);
  static Future<int> loadAutoSummaryThreshold() => ConfigStorage.loadAutoSummaryThreshold();
  static Future<void> saveAutoSummaryThreshold(int v) => ConfigStorage.saveAutoSummaryThreshold(v);
  static Future<int> loadMaxMemoryCount() => ConfigStorage.loadMaxMemoryCount();
  static Future<void> saveMaxMemoryCount(int v) => ConfigStorage.saveMaxMemoryCount(v);
  static Future<List<String>> loadSaveSlots() => ConfigStorage.loadSaveSlots();
  static Future<void> saveSaveSlots(List<String> s) => ConfigStorage.saveSaveSlots(s);
  static Future<int> loadActiveSlotIndex() => ConfigStorage.loadActiveSlotIndex();
  static Future<void> saveActiveSlotIndex(int i) => ConfigStorage.saveActiveSlotIndex(i);
  static String getSessionPrefix(int i) => ConfigStorage.getSessionPrefix(i);
  static Future<List<Map<String, dynamic>>> loadArchives() => ConfigStorage.loadArchives();
  static Future<void> saveArchives(List<Map<String, dynamic>> a) => ConfigStorage.saveArchives(a);
  static Future<int> loadChatContextLength() => ConfigStorage.loadChatContextLength();
  static Future<void> saveChatContextLength(int l) => ConfigStorage.saveChatContextLength(l);
  static Future<int> loadNovelContextLength() => ConfigStorage.loadNovelContextLength();
  static Future<void> saveNovelContextLength(int l) => ConfigStorage.saveNovelContextLength(l);
  static Future<int> getTotalTokens() => ConfigStorage.getTotalTokens();
  static Future<void> addTokens(int a) => ConfigStorage.addTokens(a);
  static Future<List<String>> loadGalleryPaths() => ConfigStorage.loadGalleryPaths();
  static Future<void> addGalleryPath(String p) => ConfigStorage.addGalleryPath(p);
  static Future<void> removeGalleryPath(String p) => ConfigStorage.removeGalleryPath(p);
}
