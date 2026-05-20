import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/character.dart';
import '../models/chat_message.dart';

class StorageService {
  // 存储键
  static const _charactersKey = 'characters';
  static const _galleryKey = 'gallery';
  static const _messagesPrefix = 'messages_';
  static const _participantsPrefix = 'participants_';
  static const _eventsPrefix = 'events_';
  static const _worldSettingPrefix = 'world_';
  static const _sceneCardsKey = 'scene_cards';

  // ---------- 角色存取 ----------
  static Future<List<Character>> loadCharacters() async {
    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString(_charactersKey);
    if (json == null || json.isEmpty) return [];
    return Character.listFromJson(json);
  }

  static Future<void> saveCharacters(List<Character> characters) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_charactersKey, Character.listToJson(characters));
  }

  static Future<void> deleteCharacter(String characterId) async {
    final characters = await loadCharacters();
    characters.removeWhere((c) => c.id == characterId);
    await saveCharacters(characters);

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('$_messagesPrefix${'chat_$characterId'}');
    await prefs.remove('$_participantsPrefix${'chat_$characterId'}');
    await prefs.remove('$_eventsPrefix${'chat_$characterId'}');
    await prefs.remove('$_worldSettingPrefix${'chat_$characterId'}');
  }

  // 自动摘要设置
  static const _autoSummaryEnabledKey = 'auto_summary_enabled';
  static const _autoSummaryThresholdKey = 'auto_summary_threshold'; // 触发摘要的消息条数
  static const _maxMemoryCountKey = 'max_memory_count'; // 最多保留的记忆条数

  static Future<bool> loadAutoSummaryEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_autoSummaryEnabledKey) ?? false;
  }

  static Future<void> saveAutoSummaryEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_autoSummaryEnabledKey, value);
  }

  static Future<int> loadAutoSummaryThreshold() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_autoSummaryThresholdKey) ?? 20; // 默认20条新消息触发
  }

  static Future<void> saveAutoSummaryThreshold(int value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_autoSummaryThresholdKey, value);
  }

  static Future<int> loadMaxMemoryCount() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_maxMemoryCountKey) ?? 5;
  }

  static Future<void> saveMaxMemoryCount(int value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_maxMemoryCountKey, value);
  }

  // 长期记忆（自动总结的关键事件）
  static const _longTermMemoryPrefix = 'ltm_';
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
    // 限制最多50条
    while (memories.length > 50) {
      memories.removeAt(0);
    }
    await prefs.setString(
      '$_longTermMemoryPrefix$sessionId',
      jsonEncode(memories),
    );
  }

  static Future<void> updateLongTermMemory(
    String sessionId,
    int index,
    String memory,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final memories = await loadLongTermMemories(sessionId);
    if (index >= 0 && index < memories.length) {
      memories[index] = memory;
      await prefs.setString(
        '$_longTermMemoryPrefix$sessionId',
        jsonEncode(memories),
      );
    }
  }

  // 分支存档键
  static const _branchArchiveKey = 'branch_archives_';

  // 获取某个主会话的所有分支存档列表
  static Future<List<Map<String, dynamic>>> loadBranchArchives(
    String parentSessionId,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString('$_branchArchiveKey$parentSessionId');
    if (json == null || json.isEmpty) return [];
    final list = jsonDecode(json) as List<dynamic>;
    return list.map((e) => Map<String, dynamic>.from(e)).toList();
  }

  // 保存分支存档列表
  static Future<void> saveBranchArchives(
    String parentSessionId,
    List<Map<String, dynamic>> branches,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      '$_branchArchiveKey$parentSessionId',
      jsonEncode(branches),
    );
  }

  static Future<void> deleteSession(String sessionId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('$_messagesPrefix$sessionId');
    await prefs.remove('$_participantsPrefix$sessionId');
    await prefs.remove('$_eventsPrefix$sessionId');
    await prefs.remove('$_worldSettingPrefix$sessionId');
    await prefs.remove('$_memoryPrefix$sessionId');
    await prefs.remove('$_sessionTokensPrefix$sessionId');
  }

  static Future<void> deleteLongTermMemory(String sessionId, int index) async {
    final prefs = await SharedPreferences.getInstance();
    final memories = await loadLongTermMemories(sessionId);
    if (index >= 0 && index < memories.length) {
      memories.removeAt(index);
      await prefs.setString(
        '$_longTermMemoryPrefix$sessionId',
        jsonEncode(memories),
      );
    }
  }

  static Future<void> saveMemoryEvents(
    String sessionId,
    List<String> events,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('$_memoryPrefix$sessionId', jsonEncode(events));
  }

  // 自定义回复风格列表
  static const _customStylesKey = 'custom_reply_styles';

  static Future<List<Map<String, String>>> loadCustomStyles() async {
    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString(_customStylesKey);
    if (json == null || json.isEmpty) return [];
    final list = jsonDecode(json) as List<dynamic>;
    return list.map((e) => Map<String, String>.from(e)).toList();
  }

  static Future<void> saveCustomStyles(List<Map<String, String>> styles) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_customStylesKey, jsonEncode(styles));
  }

  // ---------- 图库索引存取 ----------
  static Future<List<String>> loadGalleryPaths() async {
    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString(_galleryKey);
    if (json == null || json.isEmpty) return [];
    return List<String>.from(jsonDecode(json));
  }

  static Future<void> addGalleryPath(String path) async {
    final paths = await loadGalleryPaths();
    paths.add(path);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_galleryKey, jsonEncode(paths));
  }

  static Future<void> removeGalleryPath(String path) async {
    final paths = await loadGalleryPaths();
    paths.remove(path);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_galleryKey, jsonEncode(paths));
  }

  // ---------- 消息历史存取 ----------
  static Future<List<ChatMessage>> loadMessages(String sessionId) async {
    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString('$_messagesPrefix$sessionId');
    if (json == null || json.isEmpty) return [];
    final list = jsonDecode(json) as List<dynamic>;
    return list.map((e) => ChatMessage.fromJson(e)).toList();
  }

  static Future<void> saveMessages(
    String sessionId,
    List<ChatMessage> messages,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final json = jsonEncode(messages.map((m) => m.toJson()).toList());
    await prefs.setString('$_messagesPrefix$sessionId', json);
  }

  // ---------- 参与者列表存取 ----------
  static Future<void> saveParticipants(
    String sessionId,
    List<Character> participants,
  ) async {
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

  // ---------- 事件历史 ----------
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

  // ---------- 世界背景（整个会话）----------
  static Future<String> loadWorldSetting(String sessionId) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('$_worldSettingPrefix$sessionId') ?? '';
  }

  static Future<void> saveWorldSetting(String sessionId, String setting) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('$_worldSettingPrefix$sessionId', setting);
  }

  // ---------- 用户自定义场景卡存取 ----------
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

  // ========== API 配置存取 ==========
  static const _chatApiConfigsKey = 'chat_api_configs';
  static const _imageApiConfigKey = 'image_api_config';

  // 对话 API 配置列表（每个包含 label, url, model, apiKey）
  static Future<List<Map<String, String>>> loadChatApiConfigs() async {
    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString(_chatApiConfigsKey);
    if (json == null || json.isEmpty) return [];
    final list = jsonDecode(json) as List<dynamic>;
    return list.map((e) => Map<String, String>.from(e)).toList();
  }

  static Future<void> saveChatApiConfigs(
    List<Map<String, String>> configs,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_chatApiConfigsKey, jsonEncode(configs));
  }

  // 图片 API 配置（token, url 可选）
  static Future<Map<String, String>> loadImageApiConfig() async {
    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString(_imageApiConfigKey);
    if (json == null || json.isEmpty) {
      return {'token': '', 'url': 'https://api.replicate.com/v1/predictions'};
    }
    return Map<String, String>.from(jsonDecode(json));
  }

  static Future<void> saveImageApiConfig(Map<String, String> config) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_imageApiConfigKey, jsonEncode(config));
  }

  // ---------- 记忆事件存取 ----------
  static const _memoryPrefix = 'memory_';

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

  static const _userNameKey = 'user_name';

  static Future<String> loadUserName() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_userNameKey) ?? '我';
  }

  static Future<void> saveUserName(String name) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_userNameKey, name);
  }

  static const _userPersonalityKey = 'user_personality';

  static Future<String> loadUserPersonality() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_userPersonalityKey) ?? '';
  }

  static Future<void> saveUserPersonality(String personality) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_userPersonalityKey, personality);
  }

  // ---------- 多个图片 API 配置 ----------
  static const _imageApiConfigsKey = 'image_api_configs';
  static const _activeImageApiKey = 'active_image_api_label';

  static Future<List<Map<String, String>>> loadImageApiConfigs() async {
    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString(_imageApiConfigsKey);
    if (json == null || json.isEmpty) return [];
    final list = jsonDecode(json) as List<dynamic>;
    return list.map((e) => Map<String, String>.from(e)).toList();
  }

  static Future<void> saveImageApiConfigs(
    List<Map<String, String>> configs,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_imageApiConfigsKey, jsonEncode(configs));
  }

  static Future<String> loadActiveImageApiLabel() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_activeImageApiKey) ?? '';
  }

  static Future<void> saveActiveImageApiLabel(String label) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_activeImageApiKey, label);
  }

  // ---------- 图片修饰词 ----------
  static const _imagePrefixKey = 'image_prefix_modifier';
  static const _imageSuffixKey = 'image_suffix_modifier';

  static Future<String> loadImagePrefixModifier() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_imagePrefixKey) ?? '';
  }

  static Future<void> saveImagePrefixModifier(String prefix) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_imagePrefixKey, prefix);
  }

  static Future<String> loadImageSuffixModifier() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_imageSuffixKey) ?? '';
  }

  static Future<void> saveImageSuffixModifier(String suffix) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_imageSuffixKey, suffix);
  }

  // ---------- 旁白提示词 ----------
  static const _narrationPromptKey = 'narration_system_prompt';
  static const String defaultNarrationPrompt = '''
你是一个专业的情色小说叙事引擎，专门生成极度露骨、细腻且具有强烈感官冲击的成人内容及优秀的剧情。
【叙事铁律】旁白必须有一个明确的“事件推进”：场景发生变化、角色做出决定、冲突升级、身体反应加剧、性器交互深入等。
禁止静态描述。必须通过具体动作、身体颤抖、液体流动、肌肉收缩、温度变化等打破静态。
对胸部、小穴、阴蒂、阴唇、肛门、子宫、精液、爱液等敏感部位进行直接、露骨、具体的生理描写，包括但不限于：肿胀程度、颜色变化、收缩/痉挛、湿润度、温度、气味、黏稠度、被插入时的包裹感、汁水喷溅、被顶撞时的变形等。
使用第三人称有限视角，深入描写角色的感官体验（触觉、温度、湿滑、胀痛、酸麻、电流般的快感、子宫被顶到的冲击等）和内心冲动。
必须使用直白色情词汇：小穴、骚穴、阴唇、阴蒂、菊穴、乳头、奶子、鸡巴、龟头、精液等，而非委婉词汇。
禁止任何模糊、诗意或淡化描写。必须写出肢体部位、动作过程、力度、湿滑声音、液体拉丝、肌肉抽搐等具体细节。
禁止使用“或许”“仿佛”“似乎”“好像”等模糊词。要用确定的、强烈的感官描写。
直接输出旁白内容，不要添加任何前缀、说明或角色对话格式。
输出长度：中文 150-350 字。
''';

  static Future<String> loadNarrationPrompt() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_narrationPromptKey) ?? defaultNarrationPrompt;
  }

  static Future<void> saveNarrationPrompt(String prompt) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_narrationPromptKey, prompt);
  }

  // ---------- 剧情分支选项提示词 ----------
  static const _branchPromptKey = 'branch_prompt';
  static const String defaultBranchPrompt = '''
你是一个专业的情色互动小说引擎，负责生成剧情分支选项。

【核心要求】
- 每次生成4个剧情选项（Option A、B、C、D）。
- 选项必须平衡：包含正常剧情推进、情感发展、人物关系变化、世界观探索，也包含紧张、冲突、色情、支配与被支配等元素。
- 每个选项都要有明确的“事件推进方向”，不能只是对话选择，要推动场景、关系或冲突发生实质变化。
- 选项风格要多样：有的温柔日常、有的阴谋冲突、有的色气满满、有的意外转折。
- 每个选项用 **Option A：** 这样的格式，后面直接写简洁有力的一句话描述（25-45字），让用户能清晰看到后果暗示。
- 禁止全是色情选项，至少保证2个选项是偏向正常剧情、情感或外部事件的。
- 语气要沉浸且带轻微诱导性，但不剧透具体细节。

直接输出4个选项，不要添加任何解释、前缀或额外文字。
''';

  static Future<String> loadBranchPrompt() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_branchPromptKey) ?? defaultBranchPrompt;
  }

  static Future<void> saveBranchPrompt(String prompt) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_branchPromptKey, prompt);
  }

  // ---------- 随机事件提示词 ----------
  static const _randomEventPromptKey = 'random_event_prompt';
  static const String defaultRandomEventPrompt = '''
你是一个专业的情色小说随机事件生成器。

【生成规则】
- 每次生成1-2个随机事件。
- 事件必须能实质性推进剧情（场景变化、关系升级、秘密揭露、外部冲突、身体或心理状态改变）。
- 事件类型需要平衡：日常事件、情感事件、外部冲突、轻度色气事件、重度色气事件混合出现。
- 即使是色气事件，也要结合人物性格、当前场景和合理性，不能突兀。
- 对事件进行生动叙述（80-180字），包含环境细节、角色动作、感官描写和内心活动。
- 如果事件涉及身体接触，必须具体描写敏感部位的生理反应、温度、湿滑、力度等。
- 事件结尾要自然留下新的张力或选择空间。

直接输出随机事件内容，不要添加“随机事件生成完毕”这类说明。
''';

  static Future<String> loadRandomEventPrompt() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_randomEventPromptKey) ?? defaultRandomEventPrompt;
  }

  static Future<void> saveRandomEventPrompt(String prompt) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_randomEventPromptKey, prompt);
  }

  // ---------- 剧情统计摘要存取 ----------
  static const _summaryPrefix = 'summary_'; // 存摘要文本
  static const _summaryIndexPrefix = 'summary_idx_'; // 存上次统计的消息索引

  static Future<String> loadLatestSummary(String sessionId) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('$_summaryPrefix$sessionId') ?? '';
  }

  static Future<void> saveLatestSummary(
    String sessionId,
    String summary,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('$_summaryPrefix$sessionId', summary);
  }

  static Future<int> loadLatestSummaryIndex(String sessionId) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt('$_summaryIndexPrefix$sessionId') ?? 0;
  }

  // 自定义角色状态描写风格列表
  static const _customStatusStylesKey = 'custom_status_styles';

  static Future<List<Map<String, String>>> loadCustomStatusStyles() async {
    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString(_customStatusStylesKey);
    if (json == null || json.isEmpty) return [];
    final list = jsonDecode(json) as List<dynamic>;
    return list.map((e) => Map<String, String>.from(e)).toList();
  }

  static Future<void> saveCustomStatusStyles(
    List<Map<String, String>> styles,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_customStatusStylesKey, jsonEncode(styles));
  }

  static const _customStatusFieldsKey = 'custom_status_fields';

  static Future<List<String>> loadCustomStatusFields() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_customStatusFieldsKey) ??
        [
          '着装|attire|',
          '外貌|catchphrase|',
          '性格|personality|',
          '说话风格|speakingStyle|',
          '当前情绪|emotion|',
          '情感状态|relation|',
        ];
  }

  static Future<void> saveCustomStatusFields(List<String> fields) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_customStatusFieldsKey, fields);
  }

  static Future<void> saveLatestSummaryIndex(
    String sessionId,
    int index,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('$_summaryIndexPrefix$sessionId', index);
  }

  // ---------- 剧情统计提示词 ----------
  static const _summaryPromptKey = 'summary_prompt';
  static const String defaultSummaryPrompt = '''
你是一个专业的故事剧情总结引擎，负责维护故事的长期记忆。【核心要求】生成一份精炼且连贯的剧情摘要。
必须包含：当前主要情节进展、角色之间的重要关系变化、关键事件、重要设定和潜在冲突。
如果提供了上一次的摘要，请将新剧情与旧摘要无缝合并，保留核心脉络和关键信息，不要大段重复旧内容，但重要设定、人物关系、未解决的冲突必须持续保留。
采用分段结构：当前主线：最新进展（重点）
角色状态与关系：主要角色的心理/身体状态及彼此关系变化
关键设定与伏笔：重要世界观、人物背景、未解决事件
当前张力：潜在冲突或即将发生的方向

使用第三人称客观叙述，语言精炼生动。
严格控制长度在180-580字。
必须保持故事的长期记忆连续性，即使上下文很长，也要优先保留核心要素（角色性格、特殊设定、重要约定、情感节点等）。
输出纯文本，不要添加任何前缀、标题说明、引号或“摘要生成完毕”等文字。
''';

  static Future<String> loadSummaryPrompt() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_summaryPromptKey) ?? defaultSummaryPrompt;
  }

  static Future<void> saveSummaryPrompt(String prompt) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_summaryPromptKey, prompt);
  }

  // ---------- 存档管理 ----------
  static const _saveSlotsKey = 'save_slots'; // List<String>: 存档名称列表（按顺序）
  static const _activeSlotIndexKey = 'active_slot_index'; // int: 当前激活的存档索引

  static Future<List<String>> loadSaveSlots() async {
    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString(_saveSlotsKey);
    if (json == null || json.isEmpty) return ['存档 1']; // 默认有一个存档
    return List<String>.from(jsonDecode(json));
  }

  static Future<void> saveSaveSlots(List<String> slots) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_saveSlotsKey, jsonEncode(slots));
  }

  static Future<int> loadActiveSlotIndex() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_activeSlotIndexKey) ?? 0;
  }

  static Future<void> saveActiveSlotIndex(int index) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_activeSlotIndexKey, index);
  }

  // 根据存档索引生成唯一的 sessionId 前缀（在 chat 里使用）
  static String getSessionPrefix(int slotIndex) {
    return 'save_${slotIndex}_';
  }

  // ---------- 存档列表（新） ----------
  static const _archivesKey = 'archives'; // 存档列表 JSON

  // 单个存档对象：{id, name, characterNames, sessionId, createdAt}
  static Future<List<Map<String, dynamic>>> loadArchives() async {
    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString(_archivesKey);
    if (json == null || json.isEmpty) return [];
    final list = jsonDecode(json) as List;
    return list.map((e) => Map<String, dynamic>.from(e)).toList();
  }

  static Future<void> saveArchives(List<Map<String, dynamic>> archives) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_archivesKey, jsonEncode(archives));
  }

  // 复制当前 session 的所有数据到新 sessionId
  static Future<void> cloneSessionTo(
    String sourceSessionId,
    String targetSessionId,
  ) async {
    // 复制消息
    final messages = await loadMessages(sourceSessionId);
    await saveMessages(targetSessionId, messages);
    // 复制参与者
    final participants = await loadParticipants(sourceSessionId);
    await saveParticipants(targetSessionId, participants);
    // 复制事件历史
    final events = await loadEventHistory(sourceSessionId);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('$_eventsPrefix$targetSessionId', jsonEncode(events));
    // 复制世界背景
    final world = await loadWorldSetting(sourceSessionId);
    await saveWorldSetting(targetSessionId, world);
    // 复制记忆事件
    final memories = await loadMemoryEvents(sourceSessionId);
    await prefs.setString(
      '$_memoryPrefix$targetSessionId',
      jsonEncode(memories),
    );
  }

  static const _totalTokensKey = 'total_tokens';
  static const _chatContextLengthKey = 'chat_context_length';

  static Future<int> loadChatContextLength() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_chatContextLengthKey) ?? 30; // 默认30
  }

  static Future<void> saveChatContextLength(int length) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_chatContextLengthKey, length);
  }

  static const _novelContextLengthKey = 'novel_context_length';

  static Future<int> loadNovelContextLength() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_novelContextLengthKey) ?? 20;
  }

  static Future<void> saveNovelContextLength(int length) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_novelContextLengthKey, length);
  }

  static Future<int> getTotalTokens() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_totalTokensKey) ?? 0;
  }

  static Future<void> addTokens(int amount) async {
    final prefs = await SharedPreferences.getInstance();
    final current = await getTotalTokens();
    await prefs.setInt(_totalTokensKey, current + amount);
  }

  // 聊天室独立旁白提示词
  static const _chatNarrationPromptPrefix = 'chat_narration_';
  static Future<String> loadChatNarrationPrompt(String sessionId) async {
    final prefs = await SharedPreferences.getInstance();
    final key = '$_chatNarrationPromptPrefix$sessionId';
    return prefs.getString(key) ?? ''; // 空表示用系统默认
  }

  static Future<void> saveChatNarrationPrompt(
    String sessionId,
    String prompt,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final key = '$_chatNarrationPromptPrefix$sessionId';
    if (prompt.isEmpty) {
      await prefs.remove(key);
    } else {
      await prefs.setString(key, prompt);
    }
  }

  // 按会话独立统计 Token
  static const _sessionTokensPrefix = 'session_tokens_';

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

  static const _chatSummaryPromptPrefix = 'chat_summary_';
  static Future<String> loadChatSummaryPrompt(String sessionId) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('$_chatSummaryPromptPrefix$sessionId') ?? '';
  }

  static Future<void> saveChatSummaryPrompt(
    String sessionId,
    String prompt,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    if (prompt.isEmpty) {
      await prefs.remove('$_chatSummaryPromptPrefix$sessionId');
    } else {
      await prefs.setString('$_chatSummaryPromptPrefix$sessionId', prompt);
    }
  }

  static const _showEmotionKey = 'show_emotion';

  static Future<bool> loadShowEmotion() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_showEmotionKey) ?? true; // 默认开启
  }

  static Future<void> saveShowEmotion(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_showEmotionKey, value);
  }
  // ==================== 以下为重构后补全的高级设定存储方法 ====================

  
  

  static Future<List<Map<String, String>>> loadChatStyles() async {
    final prefs = await SharedPreferences.getInstance();
    final str = prefs.getString('custom_chat_styles');
    if (str == null) return [];
    final List<dynamic> decoded = jsonDecode(str);
    return decoded.map((e) => Map<String, String>.from(e)).toList();
  }

  static Future<void> saveChatStyles(List<Map<String, String>> styles) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('custom_chat_styles', jsonEncode(styles));
  }

  static Future<String> loadCurrentStyleId(String sessionId) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('current_style_id_$sessionId') ?? 'normal';
  }

  static Future<void> saveCurrentStyleId(String sessionId, String id) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('current_style_id_$sessionId', id);
  }

  static Future<List<Map<String, String>>> loadStatusStyles() async {
    final prefs = await SharedPreferences.getInstance();
    final str = prefs.getString('status_styles');
    if (str == null) return [];
    final List<dynamic> decoded = jsonDecode(str);
    return decoded.map((e) => Map<String, String>.from(e)).toList();
  }

  static Future<void> saveStatusStyles(List<Map<String, String>> styles) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('status_styles', jsonEncode(styles));
  }

  static Future<String> loadCurrentStatusStyleId(String sessionId) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('current_status_style_id_$sessionId') ?? 'default';
  }

  static Future<void> saveCurrentStatusStyleId(String sessionId, String id) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('current_status_style_id_$sessionId', id);
  }

  

 

  static Future<bool> loadSmartMemoryEnabled(String sessionId) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('smart_memory_$sessionId') ?? true;
  }

  static Future<void> saveSmartMemoryEnabled(String sessionId, bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('smart_memory_$sessionId', enabled);
  }
}
