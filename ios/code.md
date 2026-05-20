character.dart
import 'dart:convert';

class Character {
  final String id;

  String name;
  String personality;
  String attire;
  String aiModel;
  String worldSetting;
  Map<String, String> relations;
  String background; // 背景故事
  String catchphrase; // 口头禅
  String likes; // 喜好
  String dislikes; // 厌恶
  bool isUser; // 新增：标识是否为主角用户
  String avatarPath; // 本地头像路径

  Character({
    String? id,
    required this.name,
    required this.personality,
    required this.attire,
    this.aiModel = 'deepseek',
    this.worldSetting = '',
    Map<String, String>? relations,
    this.avatarPath = '',
    this.isUser = false,
    this.background = '',
    this.catchphrase = '',
    this.likes = '',
    this.dislikes = '',
  }) : id = id ?? DateTime.now().millisecondsSinceEpoch.toString(),
       relations = relations ?? {};
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'personality': personality,
    'attire': attire,
    'aiModel': aiModel,
    'worldSetting': worldSetting,
    'relations': relations,
    'background': background,
    'catchphrase': catchphrase,
    'likes': likes,
    'dislikes': dislikes,
    'isUser': isUser, // 新增
    'avatarPath': avatarPath,
  };

  factory Character.fromJson(Map<String, dynamic> json) => Character(
    id: json['id'],
    name: json['name'],
    personality: json['personality'],
    attire: json['attire'],
    aiModel: json['aiModel'] ?? 'deepseek',
    worldSetting: json['worldSetting'] ?? '',
    relations: json['relations'] != null
        ? Map<String, String>.from(json['relations'])
        : {},
    background: json['background'] ?? '',
    catchphrase: json['catchphrase'] ?? '',
    likes: json['likes'] ?? '',
    dislikes: json['dislikes'] ?? '',
    isUser: json['isUser'] ?? false, // 新增
    avatarPath: json['avatarPath'] ?? '',
  );

  // listFromJson / listToJson 不变

  static List<Character> listFromJson(String jsonString) {
    final list = jsonDecode(jsonString) as List<dynamic>;
    return list.map((e) => Character.fromJson(e)).toList();
  }

  static String listToJson(List<Character> characters) {
    return jsonEncode(characters.map((e) => e.toJson()).toList());
  }
}

/////////////////////////////////////
chat_message.dart

class ChatMessage {
  final String text;
  final bool isUser;
  final String sender;
  String? imageUrl;
  bool isGeneratingImage;

  ChatMessage({
    required this.text,
    required this.isUser,
    this.imageUrl,
    this.isGeneratingImage = false,
    required this.sender,
  });

  // 保存时忽略图片链接（不持久化图片）
  Map<String, dynamic> toJson() => {
    'text': text,
    'isUser': isUser,
    'sender': sender,
    // imageUrl 故意不保存
  };

  factory ChatMessage.fromJson(Map<String, dynamic> json) => ChatMessage(
    text: json['text'],
    isUser: json['isUser'],
    sender: json['sender'],
    // 加载时 imageUrl 永远为 null
    isGeneratingImage: false,
  );
}

//////////////////////////////////
chat_page.dart

import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/chat_message.dart';
import '../models/character.dart';
import '../services/ai_service.dart';
import '../services/image_service.dart';
import '../services/storage_service.dart';
import 'dart:io';
import '../widgets/adaptive_text_field.dart';

class ChatPage extends StatefulWidget {
  final List<Character> characters;
  final String sessionId;

  const ChatPage({
    super.key,
    required this.characters,
    required this.sessionId,
  });

  @override
  State<ChatPage> createState() => _ChatPageState();
}

// 文件：lib/screens/chat_page.dart
// 在 _ChatPageState 类中添加此方法

class _ChatPageState extends State<ChatPage> {
  Character? _getUserCharacter() {
    for (final c in _participants) {
      if (c.isUser) return c;
    }
    return null;
  }

  Widget _buildSmallButton({
    required IconData icon,
    required String label,
    required Color color,
    VoidCallback? onPressed,
  }) {
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: onPressed != null ? color : Colors.grey.shade400,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: Colors.white),
            const SizedBox(width: 4),
            Text(
              label,
              style: const TextStyle(color: Colors.white, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  // 文件：lib/screens/chat_page.dart
  void _generateImageForIndex(int index) async {
    final message = _messages[index];
    if (message.isUser || message.imageUrl != null || message.isGeneratingImage)
      return;

    setState(() => message.isGeneratingImage = true);

    try {
      // 1. AI 生成英文提示词
      final englishPrompt = await _generateImagePrompt(message.text);
      if (englishPrompt == null) throw Exception('AI生成提示词失败');

      // 2. 拼接修饰词（直接使用类变量，已加载）
      String finalPrompt = englishPrompt;
      if (_imagePrefixModifier.isNotEmpty) {
        finalPrompt = '$_imagePrefixModifier, $finalPrompt';
      }
      if (_imageSuffixModifier.isNotEmpty) {
        finalPrompt = '$finalPrompt, $_imageSuffixModifier';
      }

      print('最终提示词: $finalPrompt'); // 控制台查看

      // 3. 调用绘画 API
      final localPath = await ImageService.generateImage(finalPrompt);
      if (localPath != null) {
        setState(() {
          message.isGeneratingImage = false;
          message.imageUrl = localPath;
        });
        StorageService.addGalleryPath(localPath);
        _saveHistory();
      } else {
        throw Exception('图片生成返回空结果');
      }
    } catch (e) {
      setState(() => message.isGeneratingImage = false);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('图片生成失败: $e')));
      }
    }
  }

  Future<void> _saveAsArchive() async {
    final nameController = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('保存存档'),
        content: TextField(
          controller: nameController,
          decoration: const InputDecoration(
            hintText: '输入存档名称（如：第一次相遇）',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, nameController.text.trim()),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;

    // 生成新存档 ID
    final archiveId = 'archive_${DateTime.now().millisecondsSinceEpoch}';
    // 复制当前会话
    await StorageService.cloneSessionTo(widget.sessionId, archiveId);

    // 读取现有存档列表，追加新存档
    final archives = await StorageService.loadArchives();
    archives.add({
      'id': archiveId,
      'name': name,
      'characterNames': _participants.map((c) => c.name).join(', '),
      'sessionId': archiveId,
      'createdAt': DateTime.now().toString().substring(0, 19),
    });
    await StorageService.saveArchives(archives);

    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('存档已保存，返回主页可查看')));
    }
  }

  Future<String?> _generateImagePrompt(String chinesePrompt) async {
    final systemPrompt = '''
You are an expert AI image prompt generator. Convert the user's description into a highly detailed, visual-only English prompt for an AI image generator.

CRITICAL RULES:
- The image must contain NO text, NO words, NO letters, NO dialogue bubbles, NO subtitles. Absolutely no textual elements.
- Describe purely visual aspects: lighting, composition, color palette, mood, style, subject, setting, details.
- If the input contains speech or words, translate them into concrete visual actions, expressions, or scene descriptions instead (e.g., "says 'hello'" becomes "lips parted as if speaking, gentle smile").
- Output ONLY the English prompt. No explanations, no introductory text, no quotes.
- Make it detailed and sensorially rich.
''';

    try {
      final prompt = await AiService.callChatApi(
        modelLabel: _activeCharacter.aiModel,
        messages: [
          {'role': 'system', 'content': systemPrompt},
          {'role': 'user', 'content': chinesePrompt},
        ],
      );
      return prompt.trim();
    } catch (e) {
      print('生成提示词失败: $e');
      return null;
    }
  }

  String _userPersonality = '';
  int _contextLength = 30; // 传给 AI 的最近消息条数
  List<String> _memoryEvents = []; // 记忆事件列表
  String _userName = '我'; // 主角名称，可从设置读取
  final List<ChatMessage> _messages = [];
  final TextEditingController _textController = TextEditingController();
  bool _isLoading = false;
  bool _isAutoConversation = false;
  String _imagePrefixModifier = '';
  String _imageSuffixModifier = '';
  String _prePrompt = 'anime style, soft lighting';
  String _postPrompt = 'high quality, detailed';

  late List<Character> _participants;
  late Character _activeCharacter;
  String _worldSetting = '';
  List<String> _eventHistory = [];
  String _activeMood = '';

  int _visibleStartIndex = 0;
  List<Map<String, String>> _sceneCards = [];

  final Map<String, Color> _characterColors = {};
  final List<Color> _colorPool = [
    Colors.blue,
    Colors.green,
    Colors.orange,
    Colors.purple,
    Colors.teal,
    Colors.pink,
    Colors.indigo,
  ];
  int _colorIndex = 0;

  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    // 先从传入参数构建参与者列表
    _participants = widget.characters.isNotEmpty
        ? List.from(widget.characters)
        : [];
    // 立即给 _activeCharacter 一个初始值，防止 late 未初始化错误
    if (_participants.isNotEmpty) {
      _activeCharacter = _participants.first;
    } else {
      // 如果列表为空（例如从存档进入），临时创建一个默认用户角色
      _activeCharacter = Character(
        id: 'default_temp_user',
        name: _userName,
        personality: _userPersonality,
        attire: '',
        aiModel: 'deepseek',
        isUser: true,
      );
    }
    _assignColors();
    _loadAllData(); // 异步加载完成后会更新 _participants 和 _activeCharacter
  }

  void _showMessageContextMenu(int index) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.memory),
              title: const Text('加入记忆事件'),
              onTap: () {
                Navigator.pop(ctx);
                _addToMemory(index);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete, color: Colors.red),
              title: const Text('删除消息'),
              onTap: () {
                Navigator.pop(ctx);
                _deleteMessage(index);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _addToMemory(int index) async {
    final text = _messages[index].text;
    await StorageService.addMemoryEvent(widget.sessionId, text);
    _loadMemoryEvents();
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('已保存为记忆事件')));
  }

  void _deleteMessage(int index) {
    setState(() => _messages.removeAt(index));
    _saveHistory();
  }

  // ========== 剧情统计摘要 ==========
  Future<void> _generateSummary() async {
    if (_isLoading) return;
    setState(() => _isLoading = true);

    try {
      // 读取自定义提示词
      final customPrompt = await StorageService.loadSummaryPrompt();
      final systemPrompt = customPrompt.isNotEmpty
          ? customPrompt
          : StorageService.defaultSummaryPrompt;

      // 获取上次摘要和索引
      final previousSummary = await StorageService.loadLatestSummary(
        widget.sessionId,
      );
      final lastIndex = await StorageService.loadLatestSummaryIndex(
        widget.sessionId,
      );

      // 收集本次需要统计的消息范围
      final int startIndex = (previousSummary.isNotEmpty) ? lastIndex : 0;
      final List<ChatMessage> unsummarized = (startIndex < _messages.length)
          ? _messages.sublist(startIndex)
          : [];

      // 构建上下文
      String contextStr = '';
      if (previousSummary.isNotEmpty) {
        contextStr += '【上一次的剧情摘要】\n$previousSummary\n\n';
      }
      if (unsummarized.isNotEmpty) {
        contextStr += '【最近的对话记录】\n';
        contextStr += unsummarized
            .map((m) => '${m.sender}：${m.text}')
            .join('\n');
      }

      // 加入记忆事件
      final memories = await StorageService.loadMemoryEvents(widget.sessionId);
      if (memories.isNotEmpty) {
        contextStr += '\n\n【重要记忆事件】\n';
        for (final mem in memories) {
          contextStr += '- $mem\n';
        }
      }

      final userPrompt = '请根据以上信息生成剧情摘要。';

      final reply = await AiService.callChatApi(
        modelLabel: _activeCharacter.aiModel,
        messages: [
          {'role': 'system', 'content': systemPrompt},
          {'role': 'user', 'content': '$contextStr\n\n$userPrompt'},
        ],
      );

      final summary = reply.trim();

      // 保存新摘要及索引
      final newIndex = _messages.length; // 下次从这儿开始
      await StorageService.saveLatestSummary(widget.sessionId, summary);
      await StorageService.saveLatestSummaryIndex(widget.sessionId, newIndex);

      // 以特殊消息形式显示摘要
      setState(() {
        _messages.add(
          ChatMessage(
            text: '📊 剧情摘要：\n$summary',
            isUser: false,
            sender: '📖 系统',
          ),
        );
        _isLoading = false;
      });
      _saveHistory();
      _scrollToBottom();
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('摘要生成失败: $e')));
      }
    }
  }

  Future<void> _loadAllData() async {
    await Future.wait([
      _loadHistory(),
      _loadWorldSetting(),
      _loadEventHistory(),
      _loadSceneCards(),
      _initParticipants(),
      _loadMemoryEvents(),
    ]);
    final prefix = await StorageService.loadImagePrefixModifier();
    final suffix = await StorageService.loadImageSuffixModifier();
    final name = await StorageService.loadUserName();
    final personality = await StorageService.loadUserPersonality();
    setState(() {
      _userName = name;
      _userPersonality = personality;
      _visibleStartIndex = (_messages.length > 50) ? _messages.length - 50 : 0;
      _imagePrefixModifier = prefix;
      _imageSuffixModifier = suffix;
    });
    _scrollToBottom();
  }

  Future<void> _loadMemoryEvents() async {
    _memoryEvents = await StorageService.loadMemoryEvents(widget.sessionId);
  }

  void _assignColors() {
    for (final c in _participants) {
      if (!_characterColors.containsKey(c.name)) {
        _characterColors[c.name] = _colorPool[_colorIndex % _colorPool.length];
        _colorIndex++;
      }
    }
  }

  Future<void> _loadWorldSetting() async {
    _worldSetting = await StorageService.loadWorldSetting(widget.sessionId);
  }

  Future<void> _loadEventHistory() async {
    _eventHistory = await StorageService.loadEventHistory(widget.sessionId);
  }

  Future<void> _loadSceneCards() async {
    _sceneCards = await StorageService.loadSceneCards();
  }

  Future<void> _loadHistory() async {
    final history = await StorageService.loadMessages(widget.sessionId);
    _messages.addAll(history);
    _scrollToBottom();
  }

  Future<void> _saveHistory() async {
    await StorageService.saveMessages(widget.sessionId, _messages);
  }

  Future<void> _saveParticipants() async {
    await StorageService.saveParticipants(widget.sessionId, _participants);
  }

  Future<void> _initParticipants() async {
    final saved = await StorageService.loadParticipants(widget.sessionId);
    if (saved.isNotEmpty) {
      _participants = saved;
    } else {
      // 没有保存过参与者，从传入的角色开始
      _participants = List.from(widget.characters);
    }
    // 确保用户角色在列表里
    final existingUser = _getUserCharacter();
    if (existingUser == null) {
      // 创建用户角色并插入到第一位
      final newUser = Character(
        id: 'user_${widget.sessionId}',
        name: _userName,
        personality: _userPersonality,
        attire: '',
        aiModel: _participants.isNotEmpty
            ? _participants.first.aiModel
            : 'deepseek',
        isUser: true,
      );
      _participants.insert(0, newUser);
    } else {
      // 更新用户名字和性格
      existingUser.name = _userName;
      existingUser.personality = _userPersonality;
    }
    // 确保活跃角色默认为第一个非用户角色（如艾莉）
    final nonUser = _participants.where((c) => !c.isUser).firstOrNull;
    _activeCharacter = nonUser ?? _participants.first;
    _assignColors();
    _saveParticipants();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  // ---------- 情感分析 ----------
  Future<void> _analyzeMood(String text) async {
    try {
      final systemPrompt = '你是一个情绪分析助手，只回复一个表情符号。';
      final userPrompt =
          '根据以下对话内容，只用一个表情符号（如😊😢😠😨😏😂😍🤔😴😱）表示说话者当前的情绪状态，可用文字说明，但不要超过8个汉字。\n对话：$text';

      // 使用活跃角色的 aiModel 配置；如果担心消耗，可暂时硬编码 'deepseek'，但建议用角色模型
      final mood = await AiService.callChatApi(
        modelLabel: _activeCharacter.aiModel,
        messages: [
          {'role': 'system', 'content': systemPrompt},
          {'role': 'user', 'content': userPrompt},
        ],
      );
      if (mood.trim().length <= 2) {
        setState(() => _activeMood = mood.trim());
      }
    } catch (_) {}
  }

  // ---------- 构建消息列表 ----------
  List<Map<String, dynamic>> _buildDeepSeekMessages(
    String systemPrompt,
    String? latestUserMessage,
  ) {
    final messages = <Map<String, dynamic>>[];
    messages.add({'role': 'system', 'content': systemPrompt});

    // 计算要保留的最近历史条数
    final int maxHistory = (_contextLength <= 0)
        ? _messages.length
        : _contextLength;
    final int start = (_messages.length - maxHistory).clamp(
      0,
      _messages.length,
    );

    for (int i = start; i < _messages.length; i++) {
      final msg = _messages[i];
      if (msg.isUser) {
        messages.add({'role': 'user', 'content': msg.text});
      } else {
        messages.add({'role': 'assistant', 'content': msg.text});
      }
    }

    if (latestUserMessage != null) {
      messages.add({'role': 'user', 'content': latestUserMessage});
    }
    return messages;
  }

  // ---------- 发送请求 ----------
  Future<void> _sendRequest({
    String? userMessage,
    Character? forcedCharacter,
  }) async {
    final speaker = forcedCharacter ?? _activeCharacter;
    final systemPrompt = _buildUltimateSystemPrompt(character: speaker);

    // 统一使用新的动态调用，根据 speaker.aiModel 查找配置
    final reply = await AiService.callChatApi(
      modelLabel: speaker.aiModel,
      messages: _buildDeepSeekMessages(systemPrompt, userMessage),
    );

    setState(() {
      _messages.add(
        ChatMessage(
          text: reply,
          isUser: speaker.isUser, // 关键：用户角色发言时，isUser 为 true
          sender: speaker.name,
        ),
      );
      _isLoading = false;
    });
    _saveHistory();
    _scrollToBottom();
    _analyzeMood(reply);
  }

  // 用户发送消息
  void _sendMessage() async {
    final text = _textController.text.trim();
    if (text.isEmpty) return;

    setState(() {
      _messages.add(ChatMessage(text: text, isUser: true, sender: _userName));
      _isLoading = true;
    });
    _textController.clear();
    await _sendRequest(userMessage: text);
  }

  // ------ 自动旁白 ------
  Future<void> _generateNarration() async {
    if (_isLoading) return;
    setState(() => _isLoading = true);

    // 从存储读取自定义旁白提示词，若为空则使用默认
    final customPrompt = await StorageService.loadNarrationPrompt();
    final systemPrompt = customPrompt.isNotEmpty
        ? customPrompt
        : StorageService.defaultNarrationPrompt;

    final recentMessages = _messages.length > 10
        ? _messages.sublist(_messages.length - 10)
        : _messages;
    final contextStr = recentMessages
        .map((m) {
          return '${m.sender}：${m.text}';
        })
        .join('\n');

    final userPrompt =
        '当前剧情上下文：\n$contextStr\n\n请根据以上内容生成一小段推动剧情发展的旁白。要求：必须发生实质性事件推进，禁止停留在当前场景的静态描写。';

    try {
      final narration = await AiService.callChatApi(
        modelLabel: _activeCharacter.aiModel,
        messages: [
          {'role': 'system', 'content': systemPrompt},
          {'role': 'user', 'content': userPrompt},
        ],
      );

      setState(() {
        _messages.add(
          ChatMessage(text: narration.trim(), isUser: false, sender: '📖 旁白'),
        );
        _isLoading = false;
      });
      _saveHistory();
      _scrollToBottom();

      // 询问是否生成分支选项
      if (mounted) {
        final generate = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('剧情分支'),
            content: const Text('是否需要基于此旁白生成后续剧情选项？'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('否'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('是'),
              ),
            ],
          ),
        );
        if (generate == true) {
          final options = await _generateBranchOptions(narration.trim());
          if (options.isNotEmpty && mounted) {
            _showBranchOptions(options);
          }
        }
      }
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('旁白生成失败: $e')));
      }
    }
  }

  // ========== 剧情分支选项 ==========
  Future<List<String>> _generateBranchOptions(String narrationText) async {
    final customPrompt = await StorageService.loadBranchPrompt();
    final systemPrompt = customPrompt.isNotEmpty
        ? customPrompt
        : StorageService.defaultBranchPrompt;

    final userPrompt = '旁白内容：\n$narrationText\n\n请生成3个后续剧情选项。';

    try {
      final reply = await AiService.callChatApi(
        modelLabel: _activeCharacter.aiModel,
        messages: [
          {'role': 'system', 'content': systemPrompt},
          {'role': 'user', 'content': userPrompt},
        ],
      );

      final lines = reply
          .split('\n')
          .where((line) => line.trim().isNotEmpty)
          .toList();
      final options = <String>[];
      for (final line in lines) {
        final cleaned = line.replaceFirst(RegExp(r'^\d+\.?\s*'), '').trim();
        if (cleaned.isNotEmpty) {
          options.add(cleaned);
        }
        if (options.length >= 3) break;
      }
      return options;
    } catch (e) {
      return [];
    }
  }

  void _showBranchOptions(List<String> options) {
    if (options.isEmpty) return;
    showDialog(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('选择后续行动'),
        children: options.map((option) {
          return SimpleDialogOption(
            onPressed: () {
              Navigator.pop(ctx);
              _sendMessageAsUser(option);
            },
            child: Text(option),
          );
        }).toList(),
      ),
    );
  }

  void _sendMessageAsUser(String text) {
    setState(() {
      _messages.add(ChatMessage(text: text, isUser: true, sender: _userName));
      _isLoading = true;
    });
    _textController.clear();
    _saveHistory();
    _sendRequest(userMessage: text);
  }

  // ========== 随机事件 ==========
  Future<void> _generateRandomEvent() async {
    if (_isLoading) return;
    setState(() => _isLoading = true);

    final customPrompt = await StorageService.loadRandomEventPrompt();
    final systemPrompt = customPrompt.isNotEmpty
        ? customPrompt
        : StorageService.defaultRandomEventPrompt;

    final recentMessages = _messages.length > 10
        ? _messages.sublist(_messages.length - 10)
        : _messages;
    final contextStr = recentMessages
        .map((m) {
          return '${m.sender}：${m.text}';
        })
        .join('\n');

    final userPrompt = '当前剧情上下文：\n$contextStr\n\n请生成一个随机事件。';

    try {
      final eventText = await AiService.callChatApi(
        modelLabel: _activeCharacter.aiModel,
        messages: [
          {'role': 'system', 'content': systemPrompt},
          {'role': 'user', 'content': userPrompt},
        ],
      );

      setState(() {
        _messages.add(
          ChatMessage(
            text: '⚡ 随机事件：${eventText.trim()}',
            isUser: true,
            sender: '上帝',
          ),
        );
        _isLoading = false;
      });
      _saveHistory();
      _scrollToBottom();
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('随机事件生成失败: $e')));
      }
    }
  }

  // 主动发言（当前活跃角色）
  void _activeCharacterSpeak() async {
    if (_isLoading) return;
    setState(() => _isLoading = true);
    await _sendRequest(userMessage: null);
  }

  void _openImageModifierPopup() {
    final preCtrl = TextEditingController(text: _imagePrefixModifier);
    final postCtrl = TextEditingController(text: _imageSuffixModifier);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('🎨 图片修饰词'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: preCtrl,
                decoration: const InputDecoration(
                  labelText: '前置修饰词',
                  hintText: '如：anime style, soft lighting',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: postCtrl,
                decoration: const InputDecoration(
                  labelText: '后置修饰词',
                  hintText: '如：high quality, no text',
                  border: OutlineInputBorder(),
                ),
                maxLines: 2,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),

          IconButton(
            icon: const Icon(Icons.save_alt),
            tooltip: '保存存档',
            onPressed: _saveAsArchive,
          ),

          FilledButton(
            onPressed: () {
              setState(() {
                _imagePrefixModifier = preCtrl.text.trim();
                _imageSuffixModifier = postCtrl.text.trim();
              });
              StorageService.saveImagePrefixModifier(_imagePrefixModifier);
              StorageService.saveImageSuffixModifier(_imageSuffixModifier);
              Navigator.pop(ctx);
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }

  // ------ 上帝模式 ------
  void _showGodModeDialog() {
    final eventController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('⚡ 上帝模式'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: eventController,
                decoration: const InputDecoration(
                  hintText: '输入事件描述',
                  border: OutlineInputBorder(),
                ),
                maxLines: 3,
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  ElevatedButton.icon(
                    icon: const Icon(Icons.collections_bookmark),
                    label: const Text('场景卡'),
                    onPressed: () {
                      Navigator.pop(context);
                      _showSceneCardPicker();
                    },
                  ),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.edit_note),
                    label: const Text('管理场景卡'),
                    onPressed: () {
                      Navigator.pop(context);
                      _manageSceneCards();
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              if (eventController.text.trim().isNotEmpty) {
                _sendGodEvent(eventController.text.trim());
                Navigator.pop(context);
              }
            },
            child: const Text('触发'),
          ),
        ],
      ),
    );
  }

  void _sendGodEvent(String event) async {
    setState(() {
      _messages.add(
        ChatMessage(text: '⚡ 上帝事件：$event', isUser: true, sender: '上帝'),
      );
      _isLoading = true;
    });
    await StorageService.addEventToHistory(widget.sessionId, event);
    _loadEventHistory();
    await _sendRequest(userMessage: '事件：$event');
  }

  // 选择场景卡
  void _showSceneCardPicker() {
    showDialog(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('选择场景卡'),
        children: _sceneCards.isEmpty
            ? [
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('暂无场景卡，请先创建'),
                ),
              ]
            : _sceneCards.map((card) {
                return SimpleDialogOption(
                  onPressed: () {
                    Navigator.pop(ctx);
                    _sendGodEvent(card['event']!);
                  },
                  child: Text(card['title']!),
                );
              }).toList(),
      ),
    );
  }

  // 管理场景卡
  void _manageSceneCards() async {
    await showDialog(
      context: context,
      builder: (context) => _SceneCardManager(
        cards: _sceneCards,
        onUpdated: (cards) async {
          _sceneCards = cards;
          await StorageService.saveSceneCards(cards);
          setState(() {});
        },
      ),
    );
    _loadSceneCards();
  }

  // 事件历史
  void _showEventHistory() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('事件历史'),
        content: SizedBox(
          width: double.maxFinite,
          child: _eventHistory.isEmpty
              ? const Text('暂无事件')
              : ListView.builder(
                  shrinkWrap: true,
                  itemCount: _eventHistory.length,
                  itemBuilder: (_, i) =>
                      ListTile(title: Text(_eventHistory[i])),
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  // ------ 图片生成（补全原方法） ------

  void _generateForLatestAi() {
    for (int i = _messages.length - 1; i >= 0; i--) {
      final msg = _messages[i];
      if (!msg.isUser && msg.imageUrl == null && !msg.isGeneratingImage) {
        _generateImageForIndex(i);
        break;
      }
    }
  }

  // ------ 角色自主对话（修复空指针）------
  Future<void> _autoConversation() async {
    // 确保参与者列表至少有两个角色
    if (_participants.length < 2) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('至少需要两个角色才能自主对话')));
      return;
    }
    setState(() => _isAutoConversation = true);
    for (int i = 0; i < 5; i++) {
      if (!_isAutoConversation) break;
      for (final c in _participants) {
        if (!_isAutoConversation) break;
        setState(() => _isLoading = true);
        await _sendRequest(userMessage: null, forcedCharacter: c);
        await Future.delayed(const Duration(seconds: 2));
      }
    }
    setState(() => _isAutoConversation = false);
  }

  void _stopAutoConversation() {
    setState(() => _isAutoConversation = false);
  }

  // ------ 世界背景编辑 ------
  void _editWorldSetting() async {
    final controller = TextEditingController(text: _worldSetting);
    final newSetting = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('世界背景'),
        content: TextField(
          controller: controller,
          maxLines: 5,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            hintText: '例如：一个魔法与科技并存的世界...',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (newSetting != null) {
      setState(() => _worldSetting = newSetting);
      await StorageService.saveWorldSetting(widget.sessionId, newSetting);
    }
  }

  // ------ 系统提示（包含世界背景、关系）------
  String _buildUltimateSystemPrompt({
    required Character character,
    String? event,
  }) {
    String prompt;
    if (character.isUser) {
      // 用户角色的系统提示
      prompt = '你现在扮演用户本人，名字是${_userName}。';
      if (character.background.isNotEmpty)
        prompt += '背景故事：${character.background}\n';
      if (character.catchphrase.isNotEmpty)
        prompt += '口头禅：${character.catchphrase}\n';
      if (character.likes.isNotEmpty) prompt += '喜好：${character.likes}\n';
      if (character.dislikes.isNotEmpty) prompt += '厌恶：${character.dislikes}\n';
      if (_userPersonality.isNotEmpty) {
        prompt += '你的性格：$_userPersonality。';
      }
      prompt += '请以${_userName}的身份和语气说话，用第一人称，不要说“用户说”之类。';
    } else {
      prompt =
          '你现在扮演${character.name}。性格：${character.personality}。着装：${character.attire}。\n';
    }
    prompt += '当前用户的名字是$_userName。\n';
    if (_worldSetting.isNotEmpty) prompt += '当前世界背景：$_worldSetting\n';
    if (character.relations.isNotEmpty) {
      prompt += '你与其他角色的关系：\n';
      character.relations.forEach((name, relation) {
        prompt += '- $name：$relation\n';
      });
      prompt += '请完全以${character.name}的身份和语气说话，不要跳出角色，回复中不要添加名字前缀。';
    }

    // 添加记忆事件（持久化的重要事件）
    if (_memoryEvents.isNotEmpty) {
      prompt += '以下是你记忆中发生过的重要事件，请始终牢记并在对话中参考：\n';
      for (final mem in _memoryEvents) {
        prompt += '- $mem\n';
      }
    }

    if (event != null) prompt += '刚刚发生了新事件：$event。请结合这个事件继续对话。\n';
    prompt += '请完全以${character.name}的身份和语气说话，不要跳出角色，回复中不要添加名字前缀。';
    return prompt;
  }

  int _getDisplayMessagesCount() {
    int total = _messages.length - _visibleStartIndex;
    if (_visibleStartIndex > 0) total += 1; // 加载更多按钮占一条
    if (_isLoading) total += 1; // 思考中提示
    return total;
  }

  Widget _buildLoadMoreButton() {
    return GestureDetector(
      onTap: () {
        setState(() {
          _visibleStartIndex = (_visibleStartIndex - 50).clamp(
            0,
            _messages.length,
          );
        });
      },
      child: Container(
        padding: const EdgeInsets.all(12),
        alignment: Alignment.center,
        child: const Text('查看更早消息', style: TextStyle(color: Colors.deepPurple)),
      ),
    );
  }

  // ------ 创建临时角色（包含关系编辑）------
  Future<void> _addCharacter() async {
    final backgroundController = TextEditingController();
    final catchphraseController = TextEditingController();
    final likesController = TextEditingController();
    final dislikesController = TextEditingController();
    final apiConfigs = await StorageService.loadChatApiConfigs();
    final labels = apiConfigs.map((c) => c['label']!).toList();
    String selectedModel = labels.isNotEmpty ? labels.first : ''; // 保留这句
    final nameController = TextEditingController();
    final personalityController = TextEditingController();
    final attireController = TextEditingController();
    // 下面这句删除：
    // String selectedModel = 'deepseek';
    Map<String, String> relations = {};

    final newChar = await showDialog<Character>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('创建临时角色'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    labelText: '名字',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: personalityController,
                  decoration: const InputDecoration(
                    labelText: '性格',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 2,
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: attireController,
                  decoration: const InputDecoration(
                    labelText: '着装',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 2,
                ),
                const SizedBox(height: 10),
                AdaptiveTextField(
                  controller: backgroundController,
                  labelText: '背景故事',
                  maxLines: 5,
                ),
                const SizedBox(height: 10),
                AdaptiveTextField(
                  controller: catchphraseController,
                  labelText: '口头禅',
                  maxLines: 2,
                ),
                const SizedBox(height: 10),
                AdaptiveTextField(
                  controller: likesController,
                  labelText: '喜好',
                  maxLines: 3,
                ),
                const SizedBox(height: 10),
                AdaptiveTextField(
                  controller: dislikesController,
                  labelText: '厌恶',
                  maxLines: 3,
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  value: selectedModel,
                  decoration: const InputDecoration(
                    labelText: 'AI 模型',
                    border: OutlineInputBorder(),
                  ),
                  items: labels.isEmpty
                      ? [
                          const DropdownMenuItem(
                            value: '',
                            child: Text('请先在设置中添加API'),
                          ),
                        ]
                      : labels.map<DropdownMenuItem<String>>((label) {
                          return DropdownMenuItem(
                            value: label,
                            child: Text(label),
                          );
                        }).toList(),
                  onChanged: (v) {
                    if (v != null && v.isNotEmpty) {
                      setDialogState(() => selectedModel = v);
                    }
                  },
                ),
                const SizedBox(height: 10),

                ElevatedButton(
                  child: const Text('设置与已有角色的关系'),
                  onPressed: () async {
                    final result = await _editRelationsDialog(relations);
                    if (result != null)
                      setDialogState(() => relations = result);
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () {
                if (nameController.text.trim().isEmpty) return;
                Navigator.pop(
                  context,
                  Character(
                    name: nameController.text.trim(),
                    personality: personalityController.text.trim(),
                    attire: attireController.text.trim(),
                    aiModel: selectedModel,
                    relations: relations,
                    background: backgroundController.text.trim(),
                    catchphrase: catchphraseController.text.trim(),
                    likes: likesController.text.trim(),
                    dislikes: dislikesController.text.trim(),
                  ),
                );
              },
              child: const Text('创建'),
            ),
          ],
        ),
      ),
    );
    if (newChar != null) {
      if (!_characterColors.containsKey(newChar.name)) {
        _characterColors[newChar.name] =
            _colorPool[_colorIndex % _colorPool.length];
        _colorIndex++;
      }
      setState(() {
        _participants.add(newChar);
        _activeCharacter = newChar;
      });
      _saveParticipants();
    }
  }

  // 编辑关系对话框（新增，解决“看不到角色关系设定”）
  Future<Map<String, String>?> _editRelationsDialog(
    Map<String, String> currentRelations,
  ) async {
    final relations = Map<String, String>.from(currentRelations);
    final controllers = <String, TextEditingController>{};
    for (final p in _participants) {
      controllers[p.name] = TextEditingController(
        text: relations[p.name] ?? '',
      );
    }

    return showDialog<Map<String, String>>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('编辑角色关系'),
        content: SingleChildScrollView(
          child: Column(
            children: _participants
                .map(
                  (p) => TextField(
                    controller: controllers[p.name],
                    decoration: InputDecoration(
                      labelText: '与 ${p.name} 的关系',
                      hintText: '朋友/敌人/恋人...',
                    ),
                  ),
                )
                .toList(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              controllers.forEach((name, ctrl) {
                final text = ctrl.text.trim();
                if (text.isNotEmpty) {
                  relations[name] = text;
                } else {
                  relations.remove(name);
                }
              });
              Navigator.pop(context, relations);
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }

  // 编辑当前活跃角色（包含关系编辑）
  Future<void> _editCharacter(Character character) async {
    // 提前声明所有控制器（即使某些分支用不到，也能避免作用域问题）
    final nameController = TextEditingController(text: character.name);
    final personalityController = TextEditingController(
      text: character.personality,
    );
    final attireController = TextEditingController(text: character.attire);
    final backgroundController = TextEditingController(
      text: character.background,
    );
    final catchphraseController = TextEditingController(
      text: character.catchphrase,
    );
    final likesController = TextEditingController(text: character.likes);
    final dislikesController = TextEditingController(text: character.dislikes);
    final apiConfigs = await StorageService.loadChatApiConfigs();
    final labels = apiConfigs.map((c) => c['label']!).toList();
    String selectedModel = character.aiModel;
    if (!labels.contains(selectedModel)) {
      selectedModel = labels.isNotEmpty ? labels.first : '';
    }
    Map<String, String> relations = Map.from(character.relations);

    if (character.isUser) {
      // 编辑用户性格（只改性格，其它字段保留不动）
      final controller = TextEditingController(text: _userPersonality);
      final result = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('编辑你的性格'),
          content: TextField(
            controller: controller,
            maxLines: 3,
            decoration: const InputDecoration(hintText: '描述你的性格...'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, controller.text),
              child: const Text('保存'),
            ),
          ],
        ),
      );
      if (result != null) {
        setState(() => _userPersonality = result);
        await StorageService.saveUserPersonality(result);
        final userChar = _participants.firstWhere((c) => c.isUser);
        userChar.personality = result;
        _saveParticipants();
      }
      return;
    }

    // 非用户角色的编辑——变量声明
    final edited = await showDialog<Character>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('编辑角色'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    labelText: '名字',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: personalityController,
                  decoration: const InputDecoration(
                    labelText: '性格',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 2,
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: attireController,
                  decoration: const InputDecoration(
                    labelText: '着装',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 2,
                ),
                const SizedBox(height: 10),
                const SizedBox(height: 10),
                AdaptiveTextField(
                  controller: backgroundController,
                  labelText: '背景故事',
                  maxLines: 5,
                ),
                const SizedBox(height: 10),
                AdaptiveTextField(
                  controller: catchphraseController,
                  labelText: '口头禅',
                  maxLines: 2,
                ),
                const SizedBox(height: 10),
                AdaptiveTextField(
                  controller: likesController,
                  labelText: '喜好',
                  maxLines: 3,
                ),
                const SizedBox(height: 10),
                AdaptiveTextField(
                  controller: dislikesController,
                  labelText: '厌恶',
                  maxLines: 3,
                ),
                DropdownButtonFormField<String>(
                  value: selectedModel,
                  decoration: const InputDecoration(
                    labelText: 'AI 模型',
                    border: OutlineInputBorder(),
                  ),
                  items: labels.isEmpty
                      ? [
                          const DropdownMenuItem(
                            value: '',
                            child: Text('请先在设置中添加API'),
                          ),
                        ]
                      : labels.map<DropdownMenuItem<String>>((label) {
                          return DropdownMenuItem(
                            value: label,
                            child: Text(label),
                          );
                        }).toList(),
                  onChanged: (v) {
                    if (v != null && v.isNotEmpty) {
                      setDialogState(() => selectedModel = v);
                    }
                  },
                ),
                const SizedBox(height: 10),
                ElevatedButton(
                  child: const Text('编辑关系'),
                  onPressed: () async {
                    final result = await _editRelationsDialog(relations);
                    if (result != null)
                      setDialogState(() => relations = result);
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () {
                final name = nameController.text.trim();
                if (name.isEmpty) return;
                Navigator.pop(
                  context,
                  Character(
                    id: character.id,
                    name: name,
                    personality: personalityController.text.trim(),
                    attire: attireController.text.trim(),
                    aiModel: selectedModel,
                    relations: relations,
                    background: backgroundController.text.trim(),
                    catchphrase: catchphraseController.text.trim(),
                    likes: likesController.text.trim(),
                    dislikes: dislikesController.text.trim(),
                  ),
                );
              },
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );

    if (edited != null) {
      setState(() {
        final index = _participants.indexWhere((c) => c.id == edited.id);
        if (index != -1) {
          _participants[index] = edited;
          if (_activeCharacter.id == edited.id) _activeCharacter = edited;
        }
        if (edited.name != character.name) {
          final color = _characterColors[character.name] ?? Colors.blue;
          _characterColors.remove(character.name);
          _characterColors[edited.name] = color;
        }
      });
      _saveParticipants();
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  // ------ UI ------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('聊天室'),
        centerTitle: true,
        actions: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.public),
                  tooltip: '世界背景',
                  onPressed: _editWorldSetting,
                ),
                IconButton(
                  icon: const Icon(Icons.history),
                  tooltip: '事件历史',
                  onPressed: _showEventHistory,
                ),
                IconButton(
                  icon: const Icon(Icons.edit),
                  tooltip: '编辑当前角色',
                  onPressed: () => _editCharacter(_activeCharacter),
                ),
                // 角色下拉框（如果觉得滑动时不好按，后面会说怎么替换）
                DropdownButton<Character>(
                  value: _activeCharacter,
                  underline: const SizedBox(),
                  icon: const Icon(
                    Icons.keyboard_arrow_down,
                    color: Colors.white,
                  ),
                  dropdownColor: Colors.deepPurple.shade50,
                  items: _participants.map((c) {
                    return DropdownMenuItem(
                      value: c,
                      child: Row(
                        children: [
                          Container(
                            width: 12,
                            height: 12,
                            decoration: BoxDecoration(
                              color: _characterColors[c.name] ?? Colors.grey,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(c.name, style: const TextStyle(fontSize: 14)),
                        ],
                      ),
                    );
                  }).toList(),
                  onChanged: (c) {
                    if (c != null) setState(() => _activeCharacter = c);
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.person_add),
                  tooltip: '添加角色',
                  onPressed: _addCharacter,
                ),
                IconButton(
                  icon: const Icon(Icons.save_alt),
                  tooltip: '保存存档',
                  onPressed: _saveAsArchive,
                ),
                IconButton(
                  icon: const Text('⚡', style: TextStyle(fontSize: 20)),
                  tooltip: '上帝模式',
                  onPressed: _showGodModeDialog,
                ),
                if (_isAutoConversation)
                  IconButton(
                    icon: const Icon(Icons.stop_circle),
                    tooltip: '停止自主对话',
                    onPressed: _stopAutoConversation,
                  )
                else
                  IconButton(
                    icon: const Icon(Icons.auto_mode),
                    tooltip: '角色自主对话',
                    onPressed: _autoConversation,
                  ),
              ],
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          if (_activeMood.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 12),
              color: Colors.deepPurple.shade50,
              child: Row(
                children: [
                  const Icon(Icons.mood, size: 18, color: Colors.deepPurple),
                  const SizedBox(width: 8),
                  Text(
                    '${_activeCharacter.name} 的情绪',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const Spacer(),
                  Text(_activeMood, style: const TextStyle(fontSize: 20)),
                ],
              ),
            ),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
            decoration: BoxDecoration(
              color: Colors.deepPurple.shade50,
              border: Border(bottom: BorderSide(color: Colors.grey.shade300)),
            ),
            child: Row(
              children: [
                const Icon(Icons.bolt, color: Colors.deepPurple, size: 20),
                const SizedBox(width: 6),
              ],
            ),
          ),

          // 上下文长度控制条
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
              itemCount: _getDisplayMessagesCount(),
              itemBuilder: (context, index) {
                // 顶部加载更多按钮
                if (index == 0 && _visibleStartIndex > 0) {
                  return _buildLoadMoreButton();
                }
                final msgIndex =
                    _visibleStartIndex +
                    (index - (_visibleStartIndex > 0 ? 1 : 0));
                if (msgIndex >= _messages.length) {
                  // 正在加载中的提示
                  if (_isLoading) {
                    return const Padding(
                      padding: EdgeInsets.all(8.0),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                          SizedBox(width: 12),
                          Text('角色正在思考...'),
                        ],
                      ),
                    );
                  }
                  return const SizedBox.shrink();
                }
                final message = _messages[msgIndex];
                final isMe = message.isUser;
                final isNarration = message.sender == '📖 旁白';
                final color = isMe
                    ? Colors.deepPurple
                    : isNarration
                    ? Colors.brown
                    : (_characterColors[message.sender] ?? Colors.grey);

                return GestureDetector(
                  onLongPress: () => _showMessageContextMenu(msgIndex),
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Column(
                      crossAxisAlignment: isMe
                          ? CrossAxisAlignment.end
                          : CrossAxisAlignment.start,
                      children: [
                        if (!isMe)
                          Padding(
                            padding: const EdgeInsets.only(left: 12, bottom: 2),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 10,
                                  height: 10,
                                  decoration: BoxDecoration(
                                    color: color,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  message.sender,
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                    color: color,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        Row(
                          mainAxisAlignment: isMe
                              ? MainAxisAlignment.end
                              : MainAxisAlignment.start,
                          children: [
                            if (!isMe)
                              Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: CircleAvatar(
                                  radius: 14,
                                  backgroundColor: color.withOpacity(0.2),
                                  child: Text(
                                    message.sender[0],
                                    style: TextStyle(
                                      color: color,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ),
                            Flexible(
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 10,
                                ),
                                decoration: BoxDecoration(
                                  color: isMe
                                      ? Colors.deepPurple.shade100
                                      : color.withOpacity(0.1),
                                  border: Border.all(
                                    color: color.withOpacity(0.3),
                                  ),
                                  borderRadius: BorderRadius.only(
                                    topLeft: const Radius.circular(18),
                                    topRight: const Radius.circular(18),
                                    bottomLeft: isMe
                                        ? const Radius.circular(18)
                                        : Radius.zero,
                                    bottomRight: isMe
                                        ? Radius.zero
                                        : const Radius.circular(18),
                                  ),
                                ),
                                child: SelectableText(
                                  message.text,
                                  style: const TextStyle(fontSize: 16),
                                ),
                              ),
                            ),
                            if (isMe)
                              Padding(
                                padding: const EdgeInsets.only(left: 8),
                                child: CircleAvatar(
                                  radius: 14,
                                  backgroundColor: Colors.deepPurple.shade100,
                                  child: Text(
                                    _userName.isNotEmpty ? _userName[0] : '我',
                                    style: const TextStyle(
                                      color: Colors.deepPurple,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                        if (message.imageUrl != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: message.imageUrl!.startsWith('http')
                                  ? CachedNetworkImage(
                                      imageUrl: message.imageUrl!,
                                      width: 200,
                                      height: 200,
                                      fit: BoxFit.cover,
                                    )
                                  : Image.file(
                                      File(message.imageUrl!),
                                      width: 200,
                                      height: 200,
                                      fit: BoxFit.cover,
                                    ),
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          // 底部控件栏（移到输入框上方）
          // 底部控件区域（分两行，手机友好）
          // 底部控制区改版
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border(top: BorderSide(color: Colors.grey.shade300)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 第一行：上下文长度滑块
                Row(
                  children: [
                    const Text('上下文:', style: TextStyle(fontSize: 12)),
                    Expanded(
                      child: Slider(
                        value: _contextLength.toDouble(),
                        min: 1,
                        max: 200,
                        divisions: 199,
                        label: _contextLength >= 200
                            ? '全文'
                            : '${_contextLength}条',
                        onChanged: (v) =>
                            setState(() => _contextLength = v.toInt()),
                      ),
                    ),
                    SizedBox(
                      width: 40,
                      child: Text(
                        _contextLength >= 200 ? '全文' : '${_contextLength}条',
                        style: const TextStyle(fontSize: 11),
                      ),
                    ),
                  ],
                ),
                // 第二行：快捷按钮行
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _buildSmallButton(
                      icon: Icons.record_voice_over,
                      label: '发言',
                      color:
                          _characterColors[_activeCharacter.name] ??
                          Colors.blue,
                      onPressed: _isLoading ? null : _activeCharacterSpeak,
                    ),
                    _buildSmallButton(
                      icon: Icons.auto_stories,
                      label: '旁白',
                      color: Colors.brown.shade300,
                      onPressed: _isLoading ? null : _generateNarration,
                    ),
                    _buildSmallButton(
                      icon: Icons.casino,
                      label: '事件',
                      color: Colors.orange.shade300,
                      onPressed: _isLoading ? null : _generateRandomEvent,
                    ),
                    _buildSmallButton(
                      icon: Icons.summarize,
                      label: '总结',
                      color: Colors.teal.shade300,
                      onPressed: _isLoading ? null : _generateSummary,
                    ),
                  ],
                ),

                // 第三行：消息输入框 + 发送按钮
              ],
            ),
          ),

          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.white,
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
                Expanded(
                  child: TextField(
                    controller: _textController,
                    minLines: 1,
                    maxLines: 6,
                    textInputAction: TextInputAction.send, // 新增
                    decoration: const InputDecoration(
                      hintText: '输入消息...',
                      border: InputBorder.none,
                    ),
                    onSubmitted: (_) => _sendMessage(),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.photo_library_outlined),
                  onPressed: _generateForLatestAi,
                ),
                IconButton(
                  icon: const Icon(Icons.send, color: Colors.deepPurple),
                  onPressed: _sendMessage,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// 场景卡管理组件
class _SceneCardManager extends StatefulWidget {
  final List<Map<String, String>> cards;
  final ValueChanged<List<Map<String, String>>> onUpdated;

  const _SceneCardManager({required this.cards, required this.onUpdated});

  @override
  State<_SceneCardManager> createState() => _SceneCardManagerState();
}

class _SceneCardManagerState extends State<_SceneCardManager> {
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
              decoration: const InputDecoration(
                labelText: '标题',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: eventCtrl,
              decoration: const InputDecoration(
                labelText: '事件描述',
                border: OutlineInputBorder(),
              ),
              maxLines: 3,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
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
                  subtitle: Text(
                    _cards[i]['event']!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete),
                    onPressed: () => _deleteCard(i),
                  ),
                ),
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('关闭'),
        ),
        ElevatedButton.icon(
          icon: const Icon(Icons.add),
          label: const Text('新场景卡'),
          onPressed: _addCard,
        ),
      ],
    );
  }
}

///////////////////////////
image_service.dart

import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import '../services/storage_service.dart';

class ImageService {
  static Future<String?> generateImage(String prompt) async {
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
        return await _saveImage(response.bodyBytes);
      }
    } catch (e) {
      print('Pollinations 生成失败: $e');
    }
    return null;
  }

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
      // 如果是 DeepAI，覆盖为它特有的 api-key 头部
      if (url.contains('api.deepai.org')) {
        headers['api-key'] = token;
        headers.remove('Authorization');
      }

      // 用占位符替换 body 模板中的 {{prompt}}
      String body = bodyTemplate.replaceAll('{{prompt}}', prompt);
      final response = await http.post(
        Uri.parse(url),
        headers: headers,
        body: body,
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        // 尝试直接获取图片字节（有些 API 直接返回图片）
        if (response.headers['content-type']?.contains('image') == true) {
          return await _saveImage(response.bodyBytes);
        }
        // 否则解析 JSON，找图片 URL 或 base64
        final data = jsonDecode(response.body);
        String? imageUrl;
        // 兼容 Stable Horde 格式
        if (data['generations'] != null && data['generations'].isNotEmpty) {
          imageUrl = data['generations'][0]['img'];
        }
        // 兼容 DeepAI 格式
        if (data['output_url'] != null) {
          imageUrl = data['output_url'];
        }
        if (imageUrl != null && imageUrl.isNotEmpty) {
          // 如果是 base64，前缀可能包含 data:image/png;base64,
          if (imageUrl.startsWith('data:image')) {
            final bytes = base64Decode(imageUrl.split(',').last);
            return await _saveImage(bytes);
          } else {
            // URL 下载
            final imgResp = await http.get(Uri.parse(imageUrl));
            if (imgResp.statusCode == 200) {
              return await _saveImage(imgResp.bodyBytes);
            }
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

  static Future<String?> _saveImage(List<int> bytes) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final galleryDir = Directory('${dir.path}/gallery');
      if (!await galleryDir.exists()) {
        await galleryDir.create(recursive: true);
      }
      final fileName = 'img_${DateTime.now().millisecondsSinceEpoch}.png';
      final file = File('${galleryDir.path}/$fileName');
      await file.writeAsBytes(bytes);
      return file.path;
    } catch (e) {
      print('图片保存失败: $e');
      return null;
    }
  }

  static Future<String?> downloadAndSave(String imageUrl) async {
    /* 可以移除或保留 */
  }
}

/////////////////////////
storage_service.dart


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

    // 同时删除该角色的对话记录（主会话 key = 'chat_$characterId'）
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('$_messagesPrefix${'chat_$characterId'}');
    // 可选：同时删除相关参与者和事件等
    await prefs.remove('$_participantsPrefix${'chat_$characterId'}');
    await prefs.remove('$_eventsPrefix${'chat_$characterId'}');
    await prefs.remove('$_worldSettingPrefix${'chat_$characterId'}');
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
      '${_memoryPrefix}$targetSessionId',
      jsonEncode(memories),
    );
  }
}

/////////////////////////////
main.dart


import 'package:flutter/material.dart';
import 'screens/character_hub_page.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '角色聊天室',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const CharacterHubPage(),
    );
  }
}

//////////////////////////////
character_hub_page.dart

import 'dart:io';
import 'package:flutter/material.dart';
import '../models/character.dart';
import '../services/storage_service.dart';
import '../services/image_service.dart';
import 'chat_page.dart';
import 'gallery_page.dart';
import 'settings_page.dart';
import '../widgets/adaptive_text_field.dart';

class CharacterHubPage extends StatefulWidget {
  const CharacterHubPage({super.key});

  @override
  State<CharacterHubPage> createState() => _CharacterHubPageState();
}

class _CharacterHubPageState extends State<CharacterHubPage> {
  List<Character> _characters = [];
  List<Map<String, dynamic>> _archives = [];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final characters = await StorageService.loadCharacters();
    final archives = await StorageService.loadArchives();
    setState(() {
      _characters = characters;
      _archives = archives;
    });
  }

  Future<void> _saveAndRefresh() async {
    await StorageService.saveCharacters(_characters);
    setState(() {});
  }

  Future<void> _confirmDeleteCharacter(Character character) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除角色'),
        content: Text('确定要删除“${character.name}”吗？\n该角色的对话记录也会被清除。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await StorageService.deleteCharacter(character.id);
      _loadData();
    }
  }

  Future<void> _showCreateCharacterDialog() async {
    final nameController = TextEditingController();
    final personalityController = TextEditingController();
    final attireController = TextEditingController();
    final backgroundController = TextEditingController();
    final catchphraseController = TextEditingController();
    final likesController = TextEditingController();
    final dislikesController = TextEditingController();
    final apiConfigs = await StorageService.loadChatApiConfigs();
    final labels = apiConfigs.map((c) => c['label']!).toList();
    String selectedModel = labels.isNotEmpty ? labels.first : '';
    String? _generatedAvatarPath;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('创建新角色'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AdaptiveTextField(
                  controller: nameController,
                  labelText: '名字',
                  hintText: '例如：艾莉丝',
                ),
                const SizedBox(height: 12),
                AdaptiveTextField(
                  controller: personalityController,
                  labelText: '性格',
                  hintText: '例如：温柔、善良、有点傲娇',
                  maxLines: 3,
                ),
                const SizedBox(height: 12),
                AdaptiveTextField(
                  controller: attireController,
                  labelText: '着装',
                  hintText: '例如：白色连衣裙，银色长发',
                  maxLines: 3,
                ),
                const SizedBox(height: 12),
                AdaptiveTextField(
                  controller: backgroundController,
                  labelText: '背景故事',
                  hintText: '角色的过往经历、出身等',
                  maxLines: 5,
                ),
                const SizedBox(height: 12),
                AdaptiveTextField(
                  controller: catchphraseController,
                  labelText: '口头禅',
                  hintText: '常说的话，如“哼~”',
                  maxLines: 2,
                ),
                const SizedBox(height: 12),
                AdaptiveTextField(
                  controller: likesController,
                  labelText: '喜好',
                  hintText: '喜欢的事物，如甜食、下雨天',
                  maxLines: 3,
                ),
                const SizedBox(height: 12),
                AdaptiveTextField(
                  controller: dislikesController,
                  labelText: '厌恶',
                  hintText: '讨厌的事物，如嘈杂、虚伪',
                  maxLines: 3,
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  value: selectedModel,
                  decoration: const InputDecoration(
                    labelText: 'AI 模型',
                    border: OutlineInputBorder(),
                  ),
                  items: labels.isEmpty
                      ? [
                          const DropdownMenuItem(
                            value: '',
                            child: Text('请先在设置中添加API'),
                          ),
                        ]
                      : labels.map<DropdownMenuItem<String>>((label) {
                          return DropdownMenuItem(
                            value: label,
                            child: Text(label),
                          );
                        }).toList(),
                  onChanged: (value) {
                    if (value != null && value.isNotEmpty) {
                      setDialogState(() => selectedModel = value);
                    }
                  },
                ),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  icon: const Icon(Icons.image),
                  label: const Text('生成头像'),
                  onPressed: () async {
                    if (nameController.text.trim().isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('请先填写角色名字和描述')),
                      );
                      return;
                    }
                    final prompt =
                        '${nameController.text.trim()}, '
                        '${personalityController.text.trim()}, '
                        '${attireController.text.trim()}, '
                        'portrait, close-up, face, high quality, detailed';
                    showDialog(
                      context: context,
                      barrierDismissible: false,
                      builder: (_) =>
                          const Center(child: CircularProgressIndicator()),
                    );
                    final avatarPath = await ImageService.generateImage(prompt);
                    Navigator.pop(context);
                    if (avatarPath != null) {
                      setDialogState(() {
                        _generatedAvatarPath = avatarPath;
                      });
                      ScaffoldMessenger.of(
                        context,
                      ).showSnackBar(const SnackBar(content: Text('头像生成成功')));
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('头像生成失败，请检查图片API配置')),
                      );
                    }
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () {
                final name = nameController.text.trim();
                final personality = personalityController.text.trim();
                final attire = attireController.text.trim();
                if (name.isEmpty) {
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(const SnackBar(content: Text('请至少填写角色名字')));
                  return;
                }
                if (selectedModel.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('请选择AI模型或先在设置中添加API')),
                  );
                  return;
                }
                _characters.add(
                  Character(
                    name: name,
                    personality: personality,
                    attire: attire,
                    aiModel: selectedModel,
                    background: backgroundController.text.trim(),
                    catchphrase: catchphraseController.text.trim(),
                    likes: likesController.text.trim(),
                    dislikes: dislikesController.text.trim(),
                    avatarPath: _generatedAvatarPath ?? '',
                  ),
                );
                _saveAndRefresh();
                Navigator.pop(context);
              },
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCharacterCard(Character character) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: InkWell(
        onTap: () {
          final sessionId = 'chat_${character.id}';
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) =>
                  ChatPage(characters: [character], sessionId: sessionId),
            ),
          );
          _loadData();
        },
        onLongPress: () => _confirmDeleteCharacter(character),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              character.avatarPath.isNotEmpty
                  ? CircleAvatar(
                      backgroundImage: FileImage(File(character.avatarPath)),
                    )
                  : CircleAvatar(
                      backgroundColor: Colors.deepPurple.shade100,
                      child: Text(
                        character.name[0],
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.deepPurple,
                        ),
                      ),
                    ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      character.name,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      character.personality.isNotEmpty
                          ? '性格：${character.personality}'
                          : '暂无性格',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 14,
                      ),
                    ),
                    if (character.attire.isNotEmpty)
                      Text(
                        '着装：${character.attire}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.grey.shade600,
                          fontSize: 13,
                        ),
                      ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildArchiveCard(Map<String, dynamic> archive) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: InkWell(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => ChatPage(
                characters: const [],
                sessionId: archive['sessionId'],
              ),
            ),
          );
          _loadData();
        },
        onLongPress: () async {
          final confirm = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('删除存档'),
              content: Text('确定要删除存档“${archive['name']}”吗？'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('取消'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('删除'),
                ),
              ],
            ),
          );
          if (confirm == true) {
            final archives = await StorageService.loadArchives();
            archives.removeWhere((a) => a['id'] == archive['id']);
            await StorageService.saveArchives(archives);
            _loadData();
          }
        },
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              const Icon(Icons.bookmark, color: Colors.deepPurple),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      archive['name'],
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '角色：${archive['characterNames'] ?? ''}',
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 14,
                      ),
                    ),
                    Text(
                      '创建时间：${archive['createdAt'] ?? ''}',
                      style: TextStyle(
                        color: Colors.grey.shade500,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('角色中心'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: '设置',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SettingsPage()),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.photo_library),
            tooltip: '图库',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const GalleryPage()),
              );
            },
          ),
        ],
      ),
      body: _characters.isEmpty && _archives.isEmpty
          ? const Center(
              child: Text(
                '还没有角色或存档\n点击右下角 + 创建角色',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 18),
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (_characters.isNotEmpty) ...[
                  const Text(
                    '我的角色',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  ..._characters.map(
                    (character) => _buildCharacterCard(character),
                  ),
                  const SizedBox(height: 24),
                ],
                if (_archives.isNotEmpty) ...[
                  const Text(
                    '存档记录',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  ..._archives.map((archive) => _buildArchiveCard(archive)),
                ],
              ],
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showCreateCharacterDialog,
        child: const Icon(Icons.add),
      ),
    );
  }
}
//////////////////////////////////
gallery_page.dart
import 'dart:io';
import 'package:flutter/material.dart';
import '../services/storage_service.dart';

class GalleryPage extends StatefulWidget {
  const GalleryPage({super.key});

  @override
  State<GalleryPage> createState() => _GalleryPageState();
}

class _GalleryPageState extends State<GalleryPage> {
  List<String> _imagePaths = [];

  @override
  void initState() {
    super.initState();
    _loadGallery();
  }

  Future<void> _loadGallery() async {
    final paths = await StorageService.loadGalleryPaths();
    setState(() => _imagePaths = paths.reversed.toList()); // 最新在前
  }

  Future<void> _deleteImage(String path) async {
    final file = File(path);
    if (await file.exists()) await file.delete();
    await StorageService.removeGalleryPath(path);
    _loadGallery();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('我的图库'), centerTitle: true),
      body: _imagePaths.isEmpty
          ? const Center(child: Text('图库还是空的，在聊天中生成图片吧！'))
          : GridView.builder(
              padding: const EdgeInsets.all(12),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
              ),
              itemCount: _imagePaths.length,
              itemBuilder: (context, index) {
                final path = _imagePaths[index];
                return GestureDetector(
                  onLongPress: () => _deleteImage(path),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.file(
                      File(path),
                      fit: BoxFit.cover,
                    ),
                  ),
                );
              },
            ),
    );
  }
}
/////////////////////////////
settings_page.dart

import 'package:flutter/material.dart';
import '../services/storage_service.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  List<Map<String, String>> _chatConfigs = [];
  List<Map<String, String>> _imageConfigs = [];
  String _activeImageLabel = '';
  String _userName = '我';
  String _userPersonality = '';

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  String _summaryPrompt = StorageService.defaultSummaryPrompt;
  String _branchPrompt = StorageService.defaultBranchPrompt;
  String _randomEventPrompt = StorageService.defaultRandomEventPrompt;
  String _narrationPrompt = StorageService.defaultNarrationPrompt;
  String _imagePrefixModifier = '';
  String _imageSuffixModifier = '';
  Future<void> _loadData() async {
    final summaryPrompt = await StorageService.loadSummaryPrompt();
    final branchPrompt = await StorageService.loadBranchPrompt();
    final randomEventPrompt = await StorageService.loadRandomEventPrompt();
    final chat = await StorageService.loadChatApiConfigs();
    final imgConfigs = await StorageService.loadImageApiConfigs();
    final activeLabel = await StorageService.loadActiveImageApiLabel();
    final name = await StorageService.loadUserName();
    final personality = await StorageService.loadUserPersonality();
    final prefix = await StorageService.loadImagePrefixModifier();
    final suffix = await StorageService.loadImageSuffixModifier();
    final narrationPrompt = await StorageService.loadNarrationPrompt();
    setState(() {
      _narrationPrompt = narrationPrompt;
      _branchPrompt = branchPrompt;
      _randomEventPrompt = randomEventPrompt;
      _summaryPrompt = summaryPrompt;
      _chatConfigs = chat;
      _imageConfigs = imgConfigs;
      _activeImageLabel = activeLabel;
      _userName = name;
      _userPersonality = personality;
      _imagePrefixModifier = prefix;
      _imageSuffixModifier = suffix;
    });
  }

  // === 对话 API 管理（保持不变）===
  // === 对话 API 管理 ===
  void _addChatConfig() {
    final labelCtrl = TextEditingController();
    final urlCtrl = TextEditingController();
    final modelCtrl = TextEditingController();
    final keyCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('添加对话 API'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: labelCtrl,
                decoration: const InputDecoration(labelText: '标签（如 deepseek）'),
              ),
              TextField(
                controller: urlCtrl,
                decoration: const InputDecoration(labelText: 'API 地址'),
              ),
              TextField(
                controller: modelCtrl,
                decoration: const InputDecoration(labelText: '模型名'),
              ),
              TextField(
                controller: keyCtrl,
                decoration: const InputDecoration(labelText: 'API Key'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              if (labelCtrl.text.isNotEmpty && urlCtrl.text.isNotEmpty) {
                _chatConfigs.add({
                  'label': labelCtrl.text,
                  'url': urlCtrl.text,
                  'model': modelCtrl.text,
                  'apiKey': keyCtrl.text,
                });
                StorageService.saveChatApiConfigs(_chatConfigs);
                setState(() {});
                Navigator.pop(ctx);
              }
            },
            child: const Text('添加'),
          ),
        ],
      ),
    );
  }

  void _editChatConfig(int index) {
    final config = _chatConfigs[index];
    final labelCtrl = TextEditingController(text: config['label']);
    final urlCtrl = TextEditingController(text: config['url']);
    final modelCtrl = TextEditingController(text: config['model']);
    final keyCtrl = TextEditingController(text: config['apiKey']);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('编辑对话 API'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: labelCtrl,
                decoration: const InputDecoration(labelText: '标签'),
              ),
              TextField(
                controller: urlCtrl,
                decoration: const InputDecoration(labelText: 'API 地址'),
              ),
              TextField(
                controller: modelCtrl,
                decoration: const InputDecoration(labelText: '模型名'),
              ),
              TextField(
                controller: keyCtrl,
                decoration: const InputDecoration(labelText: 'API Key'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              _chatConfigs[index] = {
                'label': labelCtrl.text,
                'url': urlCtrl.text,
                'model': modelCtrl.text,
                'apiKey': keyCtrl.text,
              };
              StorageService.saveChatApiConfigs(_chatConfigs);
              setState(() {});
              Navigator.pop(ctx);
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }

  void _deleteChatConfig(int index) {
    _chatConfigs.removeAt(index);
    StorageService.saveChatApiConfigs(_chatConfigs);
    setState(() {});
  }

  // === 图片 API 管理 ===
  void _addImageConfig() {
    final labelCtrl = TextEditingController();
    final urlCtrl = TextEditingController();
    final tokenCtrl = TextEditingController();
    String requestType = 'get';
    final bodyCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('添加图片 API'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: labelCtrl,
                  decoration: const InputDecoration(labelText: '标签（如 DeepAI）'),
                ),
                TextField(
                  controller: urlCtrl,
                  decoration: const InputDecoration(labelText: 'API 地址'),
                ),
                TextField(
                  controller: tokenCtrl,
                  decoration: const InputDecoration(labelText: 'Token (可选)'),
                ),
                DropdownButtonFormField<String>(
                  value: requestType,
                  decoration: const InputDecoration(labelText: '请求方式'),
                  items: ['get', 'post']
                      .map(
                        (e) => DropdownMenuItem(
                          value: e,
                          child: Text(e.toUpperCase()),
                        ),
                      )
                      .toList(),
                  onChanged: (v) => setDialogState(() => requestType = v!),
                ),
                TextField(
                  controller: bodyCtrl,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: '请求体 JSON ({{prompt}} 占位)',
                    hintText: '{"text":"{{prompt}}"}',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () {
                if (labelCtrl.text.isNotEmpty && urlCtrl.text.isNotEmpty) {
                  _imageConfigs.add({
                    'label': labelCtrl.text,
                    'url': urlCtrl.text,
                    'token': tokenCtrl.text,
                    'requestType': requestType,
                    'bodyTemplate': bodyCtrl.text,
                  });
                  StorageService.saveImageApiConfigs(_imageConfigs);
                  setState(() {});
                  Navigator.pop(ctx);
                }
              },
              child: const Text('添加'),
            ),
          ],
        ),
      ),
    );
  }

  void _editImageConfig(int index) {
    final config = _imageConfigs[index];
    final labelCtrl = TextEditingController(text: config['label']);
    final urlCtrl = TextEditingController(text: config['url']);
    final tokenCtrl = TextEditingController(text: config['token']);
    String requestType = config['requestType'] ?? 'get';
    final bodyCtrl = TextEditingController(text: config['bodyTemplate']);

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('编辑图片 API'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: labelCtrl,
                  decoration: const InputDecoration(labelText: '标签'),
                ),
                TextField(
                  controller: urlCtrl,
                  decoration: const InputDecoration(labelText: 'API 地址'),
                ),
                TextField(
                  controller: tokenCtrl,
                  decoration: const InputDecoration(labelText: 'Token'),
                ),
                DropdownButtonFormField<String>(
                  value: requestType,
                  decoration: const InputDecoration(labelText: '请求方式'),
                  items: ['get', 'post']
                      .map(
                        (e) => DropdownMenuItem(
                          value: e,
                          child: Text(e.toUpperCase()),
                        ),
                      )
                      .toList(),
                  onChanged: (v) => setDialogState(() => requestType = v!),
                ),
                TextField(
                  controller: bodyCtrl,
                  maxLines: 3,
                  decoration: const InputDecoration(labelText: '请求体 JSON'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () {
                _imageConfigs[index] = {
                  'label': labelCtrl.text,
                  'url': urlCtrl.text,
                  'token': tokenCtrl.text,
                  'requestType': requestType,
                  'bodyTemplate': bodyCtrl.text,
                };
                StorageService.saveImageApiConfigs(_imageConfigs);
                setState(() {});
                Navigator.pop(ctx);
              },
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
  }

  void _deleteImageConfig(int index) {
    final label = _imageConfigs[index]['label'];
    _imageConfigs.removeAt(index);
    StorageService.saveImageApiConfigs(_imageConfigs);
    if (_activeImageLabel == label) {
      _activeImageLabel = '';
      StorageService.saveActiveImageApiLabel('');
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('API 设置'), centerTitle: true),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ------ 你的名字 ------
          const Text(
            '你的名字',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          TextField(
            decoration: const InputDecoration(hintText: '输入你在故事中的名字'),
            controller: TextEditingController(text: _userName),
            onChanged: (v) {
              _userName = v;
              StorageService.saveUserName(v);
            },
          ),
          const SizedBox(height: 12),
          // ------ 你的性格 ------
          const Text(
            '你的性格',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          TextField(
            decoration: const InputDecoration(hintText: '例如：冷静、果断、喜欢吐槽'),
            controller: TextEditingController(text: _userPersonality),
            onChanged: (v) {
              _userPersonality = v;
              StorageService.saveUserPersonality(v);
            },
          ),
          const Divider(height: 32),
          const Divider(height: 32),
          const Text(
            '旁白提示词',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            '自定义旁白生成时的系统指令，留空则使用默认提示词',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: TextEditingController(text: _narrationPrompt),
            maxLines: 10,
            minLines: 3,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              hintText: '在此编辑旁白提示词...',
            ),
            onChanged: (v) {
              _narrationPrompt = v;
              StorageService.saveNarrationPrompt(v);
            },
          ),
          Row(
            children: [
              TextButton(
                onPressed: () {
                  setState(() {
                    _narrationPrompt = StorageService.defaultNarrationPrompt;
                  });
                  StorageService.saveNarrationPrompt(
                    StorageService.defaultNarrationPrompt,
                  );
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(const SnackBar(content: Text('已恢复默认旁白提示词')));
                },
                child: const Text('恢复默认'),
              ),
            ],
          ),
          const Divider(height: 32),
          const Text(
            '剧情分支选项提示词',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: TextEditingController(text: _branchPrompt),
            maxLines: 8,
            minLines: 3,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              hintText: '在此编辑分支选项提示词...',
            ),
            onChanged: (v) {
              _branchPrompt = v;
              StorageService.saveBranchPrompt(v);
            },
          ),
          TextButton(
            onPressed: () {
              setState(
                () => _branchPrompt = StorageService.defaultBranchPrompt,
              );
              StorageService.saveBranchPrompt(
                StorageService.defaultBranchPrompt,
              );
            },
            child: const Text('恢复默认'),
          ),
          const Divider(height: 32),
          const Text(
            '随机事件提示词',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: TextEditingController(text: _randomEventPrompt),
            maxLines: 6,
            minLines: 3,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              hintText: '在此编辑随机事件提示词...',
            ),
            onChanged: (v) {
              _randomEventPrompt = v;
              StorageService.saveRandomEventPrompt(v);
            },
          ),
          TextButton(
            onPressed: () {
              setState(
                () => _randomEventPrompt =
                    StorageService.defaultRandomEventPrompt,
              );
              StorageService.saveRandomEventPrompt(
                StorageService.defaultRandomEventPrompt,
              );
            },
            child: const Text('恢复默认'),
          ),
          const Divider(height: 32),
          const Text(
            '剧情统计提示词',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: TextEditingController(text: _summaryPrompt),
            maxLines: 8,
            minLines: 3,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              hintText: '在此编辑剧情统计提示词...',
            ),
            onChanged: (v) {
              _summaryPrompt = v;
              StorageService.saveSummaryPrompt(v);
            },
          ),
          TextButton(
            onPressed: () {
              setState(
                () => _summaryPrompt = StorageService.defaultSummaryPrompt,
              );
              StorageService.saveSummaryPrompt(
                StorageService.defaultSummaryPrompt,
              );
            },
            child: const Text('恢复默认'),
          ),

          // ------ 对话 API ------
          const Text(
            '对话 API 配置',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          ...List.generate(_chatConfigs.length, (i) {
            final cfg = _chatConfigs[i];
            return Card(
              child: ListTile(
                title: Text(cfg['label']!),
                subtitle: Text('${cfg['model']} - ${cfg['url']}'),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.edit),
                      onPressed: () => _editChatConfig(i),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete),
                      onPressed: () => _deleteChatConfig(i),
                    ),
                  ],
                ),
              ),
            );
          }),
          ElevatedButton.icon(
            onPressed: _addChatConfig,
            icon: const Icon(Icons.add),
            label: const Text('添加对话 API'),
          ),
          const Divider(height: 32),

          // ------ 图片生成 API ------
          const Text(
            '图片生成 API',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          if (_imageConfigs.isNotEmpty)
            DropdownButtonFormField<String>(
              value:
                  _activeImageLabel.isNotEmpty &&
                      _imageConfigs.any((c) => c['label'] == _activeImageLabel)
                  ? _activeImageLabel
                  : null,
              decoration: const InputDecoration(labelText: '当前使用的图片 API'),
              items: _imageConfigs
                  .map(
                    (c) => DropdownMenuItem(
                      value: c['label'],
                      child: Text(c['label']!),
                    ),
                  )
                  .toList(),
              onChanged: (v) {
                if (v != null) {
                  _activeImageLabel = v;
                  StorageService.saveActiveImageApiLabel(v);
                  setState(() {});
                }
              },
            ),
          const SizedBox(height: 12),
          ...List.generate(_imageConfigs.length, (i) {
            final cfg = _imageConfigs[i];
            return Card(
              child: ListTile(
                title: Text(cfg['label']!),
                subtitle: Text(cfg['url']!),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.edit),
                      onPressed: () => _editImageConfig(i),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete),
                      onPressed: () => _deleteImageConfig(i),
                    ),
                  ],
                ),
              ),
            );
          }),
          ElevatedButton.icon(
            onPressed: _addImageConfig,
            icon: const Icon(Icons.add),
            label: const Text('添加图片 API'),
          ),
          // 图片 API 添加按钮...
          ElevatedButton.icon(
            onPressed: _addImageConfig,
            icon: const Icon(Icons.add),
            label: const Text('添加图片 API'),
          ),
          const Divider(height: 32),
          const Text(
            '图片修饰词（全局）',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          TextField(
            decoration: const InputDecoration(
              labelText: '前置修饰词',
              hintText: '加在自动提示词前面的风格词（如：anime, oil painting）',
            ),
            controller: TextEditingController(text: _imagePrefixModifier),
            onChanged: (v) {
              _imagePrefixModifier = v;
              StorageService.saveImagePrefixModifier(v);
            },
          ),
          const SizedBox(height: 12),
          TextField(
            decoration: const InputDecoration(
              labelText: '后置修饰词',
              hintText: '加在末尾的质量/风格词（如：high quality, no text）',
            ),
            controller: TextEditingController(text: _imageSuffixModifier),
            onChanged: (v) {
              _imageSuffixModifier = v;
              StorageService.saveImageSuffixModifier(v);
            },
          ),
        ],
      ),
    );
  }
}
////////////////////////////////
adaptive_text_field.dart

import 'package:flutter/material.dart';

class AdaptiveTextField extends StatefulWidget {
  final String? labelText;
  final String? hintText;
  final int maxLines;
  final TextEditingController? controller;
  final void Function(String)? onChanged;

  const AdaptiveTextField({
    super.key,
    this.labelText,
    this.hintText,
    this.maxLines = 5,
    this.controller,
    this.onChanged,
  });

  @override
  State<AdaptiveTextField> createState() => _AdaptiveTextFieldState();
}

class _AdaptiveTextFieldState extends State<AdaptiveTextField> {
  late FocusNode _focusNode;
  int _currentMaxLines = 1;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode();
    _focusNode.addListener(() {
      setState(() {
        _currentMaxLines = _focusNode.hasFocus ? widget.maxLines : 1;
      });
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: widget.controller,
      focusNode: _focusNode,
      minLines: 1,
      maxLines: _currentMaxLines,
      decoration: InputDecoration(
        labelText: widget.labelText,
        hintText: widget.hintText,
        border: const OutlineInputBorder(),
      ),
      onChanged: widget.onChanged,
    );
  }
}


/////////////////////////////////
pubspec.yaml

name: flutter_application_1
description: "A new Flutter project."
# The following line prevents the package from being accidentally published to
# pub.dev using `flutter pub publish`. This is preferred for private packages.
publish_to: 'none' # Remove this line if you wish to publish to pub.dev

# The following defines the version and build number for your application.
# A version number is three numbers separated by dots, like 1.2.43
# followed by an optional build number separated by a +.
# Both the version and the builder number may be overridden in flutter
# build by specifying --build-name and --build-number, respectively.
# In Android, build-name is used as versionName while build-number used as versionCode.
# Read more about Android versioning at https://developer.android.com/studio/publish/versioning
# In iOS, build-name is used as CFBundleShortVersionString while build-number is used as CFBundleVersion.
# Read more about iOS versioning at
# https://developer.apple.com/library/archive/documentation/General/Reference/InfoPlistKeyReference/Articles/CoreFoundationKeys.html
# In Windows, build-name is used as the major, minor, and patch parts
# of the product and file versions while build-number is used as the build suffix.
version: 1.0.0+1

environment:
  sdk: ^3.11.5

# Dependencies specify other packages that your package needs in order to work.
# To automatically upgrade your package dependencies to the latest versions
# consider running `flutter pub upgrade --major-versions`. Alternatively,
# dependencies can be manually updated by changing the version numbers below to
# the latest version available on pub.dev. To see which dependencies have newer
# versions available, run `flutter pub outdated`.
dependencies:
  flutter:
    sdk: flutter
  http: ^1.2.0
  cached_network_image: ^3.3.1
  shared_preferences: ^2.2.2      # 新增：本地键值存储（存角色、图库索引）
  path_provider: ^2.1.1            # 新增：获取应用文档目录（存图片文件）

dev_dependencies:
  flutter_test:
    sdk: flutter

  # The "flutter_lints" package below contains a set of recommended lints to
  # encourage good coding practices. The lint set provided by the package is
  # activated in the `analysis_options.yaml` file located at the root of your
  # package. See that file for information about deactivating specific lint
  # rules and activating additional ones.
  flutter_lints: ^6.0.0

# For information on the generic Dart part of this file, see the
# following page: https://dart.dev/tools/pub/pubspec

# The following section is specific to Flutter packages.
flutter:

  # The following line ensures that the Material Icons font is
  # included with your application, so that you can use the icons in
  # the material Icons class.
  uses-material-design: true

  # To add assets to your application, add an assets section, like this:
  # assets:
  #   - images/a_dot_burr.jpeg
  #   - images/a_dot_ham.jpeg

  # An image asset can refer to one or more resolution-specific "variants", see
  # https://flutter.dev/to/resolution-aware-images

  # For details regarding adding assets from package dependencies, see
  # https://flutter.dev/to/asset-from-package

  # To add custom fonts to your application, add a fonts section here,
  # in this "flutter" section. Each entry in this list should have a
  # "family" key with the font family name, and a "fonts" key with a
  # list giving the asset and other descriptors for the font. For
  # example:
  # fonts:
  #   - family: Schyler
  #     fonts:
  #       - asset: fonts/Schyler-Regular.ttf
  #       - asset: fonts/Schyler-Italic.ttf
  #         style: italic
  #   - family: Trajan Pro
  #     fonts:
  #       - asset: fonts/TrajanPro.ttf
  #       - asset: fonts/TrajanPro_Bold.ttf
  #         weight: 700
  #
  # For details regarding fonts from package dependencies,
  # see https://flutter.dev/to/font-from-package
///////////////////////////
AndroidManifest.xml

<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <uses-permission android:name="android.permission.INTERNET"/>
    <application
        android:label="Chat Ming"
        android:name="${applicationName}"
        android:icon="@mipmap/ic_launcher"
        android:usesCleartextTraffic="true"> 
        <activity
            android:name=".MainActivity"
            android:exported="true"
            android:launchMode="singleTop"
            android:taskAffinity=""
            android:theme="@style/LaunchTheme"
            android:configChanges="orientation|keyboardHidden|keyboard|screenSize|smallestScreenSize|locale|layoutDirection|fontScale|screenLayout|density|uiMode"
            android:hardwareAccelerated="true"
            android:windowSoftInputMode="adjustResize">
            <!-- Specifies an Android theme to apply to this Activity as soon as
                 the Android process has started. This theme is visible to the user
                 while the Flutter UI initializes. After that, this theme continues
                 to determine the Window background behind the Flutter UI. -->
            <meta-data
              android:name="io.flutter.embedding.android.NormalTheme"
              android:resource="@style/NormalTheme"
              />
            <intent-filter>
                <action android:name="android.intent.action.MAIN"/>
                <category android:name="android.intent.category.LAUNCHER"/>
            </intent-filter>
        </activity>
        <!-- Don't delete the meta-data below.
             This is used by the Flutter tool to generate GeneratedPluginRegistrant.java -->
        <meta-data
            android:name="flutterEmbedding"
            android:value="2" />
    </application>
    <!-- Required to query activities that can process text, see:
         https://developer.android.com/training/package-visibility and
         https://developer.android.com/reference/android/content/Intent#ACTION_PROCESS_TEXT.

         In particular, this is used by the Flutter engine in io.flutter.plugin.text.ProcessTextPlugin. -->
    <queries>
        <intent>
            <action android:name="android.intent.action.PROCESS_TEXT"/>
            <data android:mimeType="text/plain"/>
        </intent>
    </queries>
</manifest>

