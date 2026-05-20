chat_page///////////////
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/chat_message.dart';
import '../models/character.dart';
import '../services/ai_service.dart';
import '../services/image_service.dart';
import '../services/storage_service.dart';
import 'dart:io';
import '../widgets/adaptive_text_field.dart';
import 'dart:convert'; // 用于 jsonDecode
import '../widgets/small_button.dart';
import '../services/theme_provider.dart';

class ChatPage extends StatefulWidget {
  final List<Character> characters;
  final String sessionId;
  final String? archiveName;
  final ThemeProvider? themeProvider;
  const ChatPage({
    super.key,
    required this.characters,
    required this.sessionId,
    this.archiveName,
    this.themeProvider,
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

  bool _isReady = false;
  final Set<int> _animatingIndices = {};
  bool _isNearBottom = true; // 是否在底部附近
  int _lastPromptTokens = 0;
  int _lastCompletionTokens = 0;
  int _lastTotalTokens = 0;
  int _cumulativeTokens = 0;
  String _narrationPrompt = ''; // 当前聊天室的旁白提示词，空表示用系统默认
  bool _pendingSystemUpdate = false; // 是否有待处理的设定变更
  bool _isInputExpanded = false;
  bool _showEmotion = true;

  /// 插入系统提示消息，并标记下次扩大上下文
  void _insertSystemNotification(String content) {
    setState(() {
      _messages.add(
        ChatMessage(text: '【系统提示】$content', isUser: false, sender: '系统'),
      );
      _pendingSystemUpdate = true; // 下次AI调用时扩大上下文
    });
    _saveHistory();
  }

  void _regenerateMessage(int index) async {
    if (_isLoading) return;
    final msg = _messages[index];
    if (msg.isUser) return;
    // 删除这条 AI 消息
    setState(() => _messages.removeAt(index));
    _saveHistory();
    // 重新请求 AI 回复
    await _sendRequest(userMessage: null);
  }

  void _manageMemoryEvents() {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(12.0),
              child: Text(
                '记忆事件',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
              ),
            ),
            if (_memoryEvents.isEmpty)
              const Padding(padding: EdgeInsets.all(16), child: Text('暂无记忆事件'))
            else
              SizedBox(
                height: 300,
                child: ListView.builder(
                  itemCount: _memoryEvents.length,
                  itemBuilder: (_, i) => ListTile(
                    leading: const Icon(Icons.memory),
                    title: Text(
                      _memoryEvents[i],
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    onTap: () {
                      // 查看详情
                      showDialog(
                        context: context,
                        builder: (_) => AlertDialog(
                          title: const Text('记忆事件详情'),
                          content: SingleChildScrollView(
                            child: Text(_memoryEvents[i]),
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(context),
                              child: const Text('关闭'),
                            ),
                          ],
                        ),
                      );
                    },
                    trailing: IconButton(
                      icon: const Icon(Icons.delete, color: Colors.red),
                      onPressed: () async {
                        // 删除记忆事件
                        await StorageService.removeMemoryEvent(
                          widget.sessionId,
                          i,
                        );
                        _memoryEvents.removeAt(i);
                        setState(() {});
                        Navigator.pop(ctx); // 关闭当前管理窗口
                        _manageMemoryEvents(); // 重新打开刷新列表
                      },
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _showMentionPicker() {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Wrap(
          children: _participants
              .map(
                (c) => ListTile(
                  leading: CircleAvatar(
                    backgroundColor: _characterColors[c.name] ?? Colors.grey,
                    child: Text(
                      c.name[0],
                      style: TextStyle(color: Colors.white),
                    ),
                  ),
                  title: Text(c.name),
                  onTap: () {
                    Navigator.pop(ctx);
                    final text = '@${c.name} ';
                    final selection = _textController.selection;
                    final currentText = _textController.text;
                    // 在光标处插入
                    final newText =
                        currentText.substring(0, selection.start) +
                        text +
                        currentText.substring(selection.start);
                    _textController.text = newText;
                    _textController.selection = TextSelection.collapsed(
                      offset: selection.start + text.length,
                    );
                    _textFocusNode.requestFocus();
                  },
                ),
              )
              .toList(),
        ),
      ),
    );
  }

  final FocusNode _textFocusNode = FocusNode();
  // 文件：lib/screens/chat_page.dart
  void _generateImageForIndex(int index) async {
    final message = _messages[index];
    if (message.isUser ||
        message.imageUrl != null ||
        message.isGeneratingImage) {
      return;
    }

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

  Future<void> _editNarrationPrompt() async {
    final ctrl = TextEditingController(text: _narrationPrompt);
    final res = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('旁白提示词（本聊天室）'),
        content: TextField(
          controller: ctrl,
          maxLines: 10,
          decoration: const InputDecoration(
            hintText: '留空则使用系统默认旁白提示词',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (res != null) {
      setState(() => _narrationPrompt = res);
      await StorageService.saveChatNarrationPrompt(widget.sessionId, res);
      _insertSystemNotification('旁白提示词已更新');
    }
  }

  Future<R> _withExtendedContext<R>(Future<R> Function() fn) async {
    if (!_pendingSystemUpdate) return fn();
    final original = _contextLength;
    _contextLength = _messages.length; // 最大
    try {
      return await fn();
    } finally {
      _contextLength = original;
      _pendingSystemUpdate = false;
    }
  }

  Future<void> _editMyProfile() async {
    final nameCtrl = TextEditingController(text: _userName);
    final personalityCtrl = TextEditingController(text: _userPersonality);

    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('我的设定'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(labelText: '你的名字'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: personalityCtrl,
                maxLines: 3,
                decoration: const InputDecoration(labelText: '你的性格'),
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
              final name = nameCtrl.text.trim();
              if (name.isEmpty) return;

              Navigator.pop(ctx, {
                'name': name,
                'personality': personalityCtrl.text.trim(),
              });
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );

    if (result == null) return;

    final newName = result['name']!;
    final newPersonality = result['personality']!;

    setState(() {
      _userName = newName;
      _userPersonality = newPersonality;
    });

    await StorageService.saveUserName(newName);
    await StorageService.saveUserPersonality(newPersonality);

    // 直接拿到用户角色并更新（一定存在）
    final userChar = _participants.firstWhere((c) => c.isUser);
    userChar.name = newName;
    userChar.personality = newPersonality;
    _saveParticipants();

    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('主角设定已更新')));
    }
    // ... 更新 userName, userPersonality 后
    _insertSystemNotification('主角设定已更新：名字=$newName，性格=$newPersonality');
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
      final promptResponse = await AiService.callChatApi(
        modelLabel: _activeCharacter.aiModel,
        messages: [
          {'role': 'system', 'content': systemPrompt},
          {'role': 'user', 'content': chinesePrompt},
        ],
      );
      return promptResponse.content.trim();
    } catch (e) {
      print('生成提示词失败: $e');
      return null;
    }
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final maxScroll = _scrollController.position.maxScrollExtent;
    final currentScroll = _scrollController.position.pixels;
    final isNearBottom = (maxScroll - currentScroll) <= 100.0;
    if (_isNearBottom != isNearBottom) {
      setState(() => _isNearBottom = isNearBottom);
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
  final String _prePrompt = 'anime style, soft lighting';
  final String _postPrompt = 'high quality, detailed';
  String _summaryPrompt = ''; // 当前聊天室的总结提示词，空表示用全局
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
  @override
  void initState() {
    super.initState();
    _participants = widget.characters.isNotEmpty
        ? List.from(widget.characters)
        : [];
    if (_participants.isNotEmpty) {
      _activeCharacter = _participants.first;
    } else {
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
    _scrollController.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadAllData().then((_) {
        if (mounted) setState(() => _isReady = true);
      });
    });
  }

  void _showMessageContextMenu(int index) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Wrap(
          children: [
            if (_messages[index].isUser)
              ListTile(
                leading: const Icon(Icons.edit),
                title: const Text('编辑'),
                onTap: () {
                  Navigator.pop(ctx);
                  _editMessage(index);
                },
              ),
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
            if (!_messages[index].isUser)
              ListTile(
                leading: const Icon(Icons.refresh),
                title: const Text('重新生成'),
                onTap: () {
                  Navigator.pop(ctx);
                  _regenerateMessage(index);
                },
              ),
          ],
        ),
      ),
    );
  }

  void _editMessage(int index) {
    final msg = _messages[index];
    if (!msg.isUser) return;
    // 把原消息放回输入框
    _textController.text = msg.text;
    _textController.selection = TextSelection.fromPosition(
      TextPosition(offset: msg.text.length),
    );
    // 删除原消息
    setState(() => _messages.removeAt(index));
    _saveHistory();
    // 聚焦输入框
    _textFocusNode.requestFocus();
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
      final customPrompt = _summaryPrompt.isNotEmpty
          ? _summaryPrompt
          : await StorageService.loadSummaryPrompt();
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

      final replyResponse = await AiService.callChatApi(
        modelLabel: _activeCharacter.aiModel,
        messages: [
          {'role': 'system', 'content': systemPrompt},
          {'role': 'user', 'content': '$contextStr\n\n$userPrompt'},
        ],
      );
      _addTokens(replyResponse);

      final summary = replyResponse.content.trim();

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
      _scrollToBottomIfNeeded();
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
    _showEmotion = await StorageService.loadShowEmotion();
    final prefix = await StorageService.loadImagePrefixModifier();
    final suffix = await StorageService.loadImageSuffixModifier();
    final name = await StorageService.loadUserName();
    final personality = await StorageService.loadUserPersonality();
    // 加载上下文长度
    final savedContext = await StorageService.loadChatContextLength();
    // 加载旁白提示词（独立，默认用系统）
    _narrationPrompt = await StorageService.loadChatNarrationPrompt(
      widget.sessionId,
    );
    _summaryPrompt = await StorageService.loadChatSummaryPrompt(
      widget.sessionId,
    );
    setState(() {}); // 如果需要刷新UI可在这里，但旁白生成时才用，不必立即刷新
    setState(() {
      _contextLength = savedContext;
      _userName = name;
      _userPersonality = personality;
      _visibleStartIndex = (_messages.length > 50) ? _messages.length - 50 : 0;
      _imagePrefixModifier = prefix;
      _imageSuffixModifier = suffix;
    });
    _scrollToBottomIfNeeded();
    _cumulativeTokens = await StorageService.loadSessionTokens(
      widget.sessionId,
    );
    setState(() {});
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
    _scrollToBottomIfNeeded();
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

  void _scrollToBottomIfNeeded() {
    if (_isNearBottom) {
      _scrollToBottom();
    }
  }

  // ---------- 情感分析 ----------
  Future<void> _analyzeMood(String text) async {
    try {
      final systemPrompt = '你是一个情绪分析助手，只回复一个表情符号。';
      final userPrompt =
          '根据以下对话内容，只用一个表情符号（如😊😢😠😨😏😂😍🤔😴😱）表示说话者当前的情绪状态，可用文字说明，但不要超过8个汉字。\n对话：$text';

      // 使用活跃角色的 aiModel 配置；如果担心消耗，可暂时硬编码 'deepseek'，但建议用角色模型
      final moodResponse = await AiService.callChatApi(
        modelLabel: _activeCharacter.aiModel,
        messages: [
          {'role': 'system', 'content': systemPrompt},
          {'role': 'user', 'content': userPrompt},
        ],
      );
      final mood = moodResponse.content.trim();
      if (mood.length <= 2) {
        setState(() => _activeMood = mood);
      }
    } catch (_) {}
  }

  // ---------- 构建消息列表 ----------
  List<Map<String, dynamic>> _buildDeepSeekMessages(
    String systemPrompt,
    String? latestUserMessage, {
    bool forceFullHistory = false,
  }) {
    final messages = <Map<String, dynamic>>[];
    messages.add({'role': 'system', 'content': systemPrompt});

    final int maxHistory = (forceFullHistory || _contextLength <= 0)
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
        // 去除 msg.text 开头可能残留的“角色名：”或“角色名:”，避免 AI 模仿
        String cleanText = msg.text;
        final senderName = msg.sender;
        // 中文全角冒号
        if (cleanText.startsWith('$senderName：')) {
          cleanText = cleanText.substring(senderName.length + 1).trimLeft();
        }
        // 英文半角冒号（通常带空格或不带）
        else if (cleanText.startsWith('$senderName:')) {
          cleanText = cleanText.substring(senderName.length + 1).trimLeft();
        }
        messages.add({
          'role': 'assistant',
          'content': '${msg.sender}：$cleanText', // 统一添加 sender 前缀，但内容已干净
        });
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

    // 备份并临时扩大上下文
    final int originalContextLength = _contextLength;
    if (_pendingSystemUpdate) {
      _contextLength = _messages.length; // 一次性读取全部历史
    }

    final aiResponse = await AiService.callChatApi(
      modelLabel: speaker.aiModel,
      messages: _buildDeepSeekMessages(systemPrompt, userMessage),
    );
    final reply = aiResponse.content;

    // 恢复上下文长度
    if (_pendingSystemUpdate) {
      _contextLength = originalContextLength;
      _pendingSystemUpdate = false;
    }

    // 累加并持久化 token（使用 session 独立方法）
    _addTokens(aiResponse);

    setState(() {
      _lastPromptTokens = aiResponse.promptTokens;
      _lastCompletionTokens = aiResponse.completionTokens;
      _lastTotalTokens = aiResponse.totalTokens;
      _messages.add(
        ChatMessage(text: reply, isUser: speaker.isUser, sender: speaker.name),
      );
      _animatingIndices.add(_messages.length - 1);
      _isLoading = false;
    });

    Future.delayed(const Duration(milliseconds: 400), () {
      if (mounted) {
        setState(() => _animatingIndices.remove(_messages.length - 1));
      }
    });

    _saveHistory();
    _scrollToBottomIfNeeded();
    if (_showEmotion) _analyzeMood(reply);
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
    _saveHistory(); // 立即保存，防止发送过程崩溃丢失
    await _sendRequest(userMessage: null);
    _textFocusNode.unfocus(); // 收起键盘
  }

  // ------ 自动旁白 ------
  Future<void> _generateNarration() async {
    if (_isLoading) return;
    setState(() => _isLoading = true);

    // 从存储读取自定义旁白提示词，若为空则使用默认
    // 优先使用当前聊天室的独立提示词，否则用系统默认
    final customPrompt = _narrationPrompt.isNotEmpty
        ? _narrationPrompt
        : await StorageService.loadNarrationPrompt();
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
      final narrationResponse = await AiService.callChatApi(
        modelLabel: _activeCharacter.aiModel,
        messages: [
          {'role': 'system', 'content': systemPrompt},
          {'role': 'user', 'content': userPrompt},
        ],
      );
      _addTokens(narrationResponse);
      final narrationText = narrationResponse.content.trim();

      setState(() {
        _messages.add(
          ChatMessage(text: narrationText, isUser: false, sender: '📖 旁白'),
        );
        _isLoading = false;
      });
      _saveHistory();
      _scrollToBottomIfNeeded();
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('旁白生成失败: $e')));
      }
    }
  }

  void _addTokens(AiResponse response) {
    _cumulativeTokens += response.totalTokens;
    StorageService.addSessionTokens(widget.sessionId, response.totalTokens);
    setState(() {
      _lastTotalTokens = response.totalTokens;
    });
  }

  // ========== 剧情分支选项 ==========
  Future<List<String>> _generateBranchOptions(String contextPrompt) async {
    final customPrompt = await StorageService.loadBranchPrompt();
    final systemPrompt = customPrompt.isNotEmpty
        ? customPrompt
        : StorageService.defaultBranchPrompt;

    try {
      final replyResponse = await AiService.callChatApi(
        modelLabel: _activeCharacter.aiModel,
        messages: [
          {'role': 'system', 'content': systemPrompt},
          {'role': 'user', 'content': contextPrompt},
        ],
      );
      _addTokens(replyResponse);
      final replyText = replyResponse.content;
      final lines = replyText
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
    _sendRequest(userMessage: null);
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
      final eventResponse = await AiService.callChatApi(
        modelLabel: _activeCharacter.aiModel,
        messages: [
          {'role': 'system', 'content': systemPrompt},
          {'role': 'user', 'content': userPrompt},
        ],
      );
      final eventContent = eventResponse.content.trim();

      setState(() {
        _messages.add(
          ChatMessage(text: '⚡ 随机事件：$eventContent', isUser: true, sender: '上帝'),
        );
        _isLoading = false;
      });
      _saveHistory();
      _scrollToBottomIfNeeded();
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
    await _sendRequest(userMessage: null);
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
      _insertSystemNotification('世界观已更新：$newSetting');
    }
  }

  // ------ 系统提示（包含世界背景、关系）------
  String _buildUltimateSystemPrompt({
    required Character character,
    String? event,
  }) {
    String prompt;
    if (character.isUser) {
      prompt = '你现在扮演用户本人，名字是$_userName。';
      if (_userPersonality.isNotEmpty) {
        prompt += '你的性格：$_userPersonality。';
      }
      prompt += '请以$_userName的身份和语气说话，用第一人称。';
    } else {
      prompt = '你正在扮演的角色是：${character.name}。\n';
      prompt += '性格：${character.personality}\n';
      prompt += '着装：${character.attire}\n';
      if (character.background.isNotEmpty) {
        prompt += '背景故事：${character.background}\n';
      }
      if (character.catchphrase.isNotEmpty) {
        prompt += '外貌：${character.catchphrase}\n';
      }
      if (character.likes.isNotEmpty) prompt += '喜好：${character.likes}\n';
      if (character.dislikes.isNotEmpty) prompt += '厌恶：${character.dislikes}\n';
      if (character.speakingStyle.isNotEmpty)
        prompt += '说话风格：${character.speakingStyle}\n';
    }

    prompt += '当前用户的名字是$_userName。\n';
    if (_worldSetting.isNotEmpty) prompt += '世界背景：$_worldSetting\n';

    if (character.relations.isNotEmpty) {
      prompt += '你与其他角色的关系：\n';
      character.relations.forEach((name, relation) {
        prompt += '- $name：$relation\n';
      });
    }

    // 重要：强调角色不串线
    if (!character.isUser) {
      prompt +=
          '\n【重要】你只能以${character.name}的身份说话，绝不能替其他角色发言，可以描述他们的内心活动。即使上下文中有其他角色的话，你也要站在${character.name}的视角回复。\n';
    }

    if (_memoryEvents.isNotEmpty) {
      prompt += '以下是你记忆中发生过的重要事件，请参考：\n';
      for (final mem in _memoryEvents) {
        prompt += '- $mem\n';
      }
    }

    if (event != null) prompt += '刚刚发生了新事件：$event。请结合这个事件继续对话。\n';
    // 着装描述 + 防名字前缀
    if (!character.isUser) {
      prompt +=
          '\n【回复格式】重要：每次回复时，先简短描述你当前的穿着和外表,从内到外所有穿搭都会简单的描述，包括内衣内裤，放在()里。如果最近对话中提到你换了装束，就描述那套新的,如果没有提过，就按初始设定“${character.attire}”描述。';
      prompt += '禁止在正文中出现你的名字或“名字：”这样的前缀，你只需输出括号内的形象描述和对话。';
    }
    prompt += '请完全以角色的身份和语气说话。';
    return prompt;
  }

  String _cleanMessageText(ChatMessage msg) {
    String text = msg.text;
    if (!msg.isUser && msg.sender != '📖 旁白' && msg.sender != '📖 系统') {
      // 去掉开头可能出现的“名字：”或“名字:”，支持冒号后有空格
      final name = RegExp.escape(msg.sender);
      final pattern = RegExp('^$name[：:]\\s*');
      text = text.replaceFirst(pattern, '');
    }
    return text;
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
    final speakingCtrl = TextEditingController();
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
                  maxLines: 3,
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: attireController,
                  decoration: const InputDecoration(
                    labelText: '着装',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 3,
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
                  labelText: '外貌',
                  maxLines: 3,
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
                AdaptiveTextField(
                  controller: speakingCtrl,
                  labelText: '说话风格',
                  hintText: '例：古风、毒舌、话痨...',
                  maxLines: 3,
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue: selectedModel,
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
                ElevatedButton.icon(
                  icon: const Icon(Icons.auto_fix_high),
                  label: const Text('AI 解析角色'),
                  onPressed: () async {
                    final textCtrl = TextEditingController();
                    final ok = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text('粘贴角色设定文本'),
                        content: TextField(
                          controller: textCtrl,
                          maxLines: 8,
                          decoration: const InputDecoration(
                            hintText: '粘贴文本...',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(ctx, false),
                            child: const Text('取消'),
                          ),
                          FilledButton(
                            onPressed: () => Navigator.pop(ctx, true),
                            child: const Text('解析'),
                          ),
                        ],
                      ),
                    );
                    if (ok == true && textCtrl.text.trim().isNotEmpty) {
                      final parsed = await AiService.parseCharacterText(
                        textCtrl.text.trim(),
                        modelLabel: _activeCharacter.aiModel,
                      );
                      if (parsed != null) {
                        setDialogState(() {
                          nameController.text = parsed['name'] ?? '';
                          personalityController.text =
                              parsed['personality'] ?? '';
                          attireController.text = parsed['attire'] ?? '';
                          backgroundController.text =
                              parsed['background'] ?? '';
                          catchphraseController.text =
                              parsed['catchphrase'] ?? '';
                          likesController.text = parsed['likes'] ?? '';
                          dislikesController.text = parsed['dislikes'] ?? '';
                          speakingCtrl.text = parsed['speakingStyle'] ?? '';
                        });
                      }
                    }
                  },
                ),
                ElevatedButton(
                  child: const Text('设置与已有角色的关系'),
                  onPressed: () async {
                    final result = await _editRelationsDialog(relations);
                    if (result != null) {
                      setDialogState(() => relations = result);
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
                    speakingStyle: speakingCtrl.text.trim(),
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
        _insertSystemNotification('新角色“${newChar.name}”加入聊天');
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
    final speakingCtrl = TextEditingController(text: character.speakingStyle);
    final apiConfigs = await StorageService.loadChatApiConfigs();
    final labels = apiConfigs.map((c) => c['label']!).toList();
    String selectedModel = character.aiModel;
    if (!labels.contains(selectedModel)) {
      selectedModel = labels.isNotEmpty ? labels.first : '';
    }
    Map<String, String> relations = Map.from(character.relations);

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
                  maxLines: 3,
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: attireController,
                  decoration: const InputDecoration(
                    labelText: '着装',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 3,
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
                  labelText: '外貌',
                  maxLines: 3,
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
                AdaptiveTextField(
                  controller: speakingCtrl,
                  labelText: '说话风格',
                  hintText: '例：古风、毒舌、话痨...',
                  maxLines: 3,
                ),
                ElevatedButton.icon(
                  icon: const Icon(Icons.auto_fix_high),
                  label: const Text('AI 解析角色'),
                  onPressed: () async {
                    final textCtrl = TextEditingController();
                    final ok = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text('粘贴角色设定文本'),
                        content: TextField(
                          controller: textCtrl,
                          maxLines: 8,
                          decoration: const InputDecoration(
                            hintText: '粘贴文本...',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(ctx, false),
                            child: const Text('取消'),
                          ),
                          FilledButton(
                            onPressed: () => Navigator.pop(ctx, true),
                            child: const Text('解析'),
                          ),
                        ],
                      ),
                    );
                    if (ok == true && textCtrl.text.trim().isNotEmpty) {
                      final parsed = await AiService.parseCharacterText(
                        textCtrl.text.trim(),
                        modelLabel: _activeCharacter.aiModel,
                      );
                      if (parsed != null) {
                        setDialogState(() {
                          nameController.text = parsed['name'] ?? '';
                          personalityController.text =
                              parsed['personality'] ?? '';
                          attireController.text = parsed['attire'] ?? '';
                          backgroundController.text =
                              parsed['background'] ?? '';
                          catchphraseController.text =
                              parsed['catchphrase'] ?? '';
                          likesController.text = parsed['likes'] ?? '';
                          dislikesController.text = parsed['dislikes'] ?? '';
                          speakingCtrl.text = parsed['speakingStyle'] ?? '';
                        });
                      }
                    }
                  },
                ),
                DropdownButtonFormField<String>(
                  initialValue: selectedModel,
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
                    if (result != null) {
                      setDialogState(() => relations = result);
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
                    speakingStyle: speakingCtrl.text.trim(),
                    isUser: character.isUser,
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
      // 如果是用户角色，同步全局名字和性格
      if (edited.isUser) {
        _userName = edited.name;
        _userPersonality = edited.personality;
        StorageService.saveUserName(edited.name);
        StorageService.saveUserPersonality(edited.personality);
      }
      setState(() {
        final index = _participants.indexWhere((c) => c.id == edited.id);
        if (index != -1) {
          _participants[index] = edited;
          if (_activeCharacter.id == edited.id) _activeCharacter = edited;
        }
        if (edited.name != _activeCharacter.name) {
          final color = _characterColors[_activeCharacter.name] ?? Colors.blue;
          _characterColors.remove(_activeCharacter.name);
          _characterColors[edited.name] = color;
        }
      });
      _saveParticipants();
      _insertSystemNotification('角色“${edited.name}”设定已更新');
    }
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll); // 新增
    _scrollController.dispose();
    super.dispose();
    _textFocusNode.dispose();
  }

  Future<void> _confirmDeleteCharacter(Character character) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除角色'),
        content: Text('确定要从本聊天删除“${character.name}”吗？\n（该角色的历史消息仍会保留）'),
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
    if (confirmed == true) {
      setState(() {
        _participants.removeWhere((c) => c.id == character.id);
        if (_activeCharacter.id == character.id) {
          _activeCharacter = _participants.firstWhere(
            (c) => !c.isUser,
            orElse: () => _participants.first,
          );
        }
        _characterColors.remove(character.name);
      });
      _saveParticipants();
      _insertSystemNotification('角色“${character.name}”已离开聊天');
    }
  }

  // ------ UI ------
  @override
  Widget build(BuildContext context) {
    if (!_isReady) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.archiveName ?? '聊天室'),
        centerTitle: true,
        actions: [
          // 角色切换下拉框（常用入口）
          // 角色切换下拉框（常用入口）
          if (_participants.isNotEmpty &&
              _participants.contains(_activeCharacter))
            // 角色切换（弹出菜单）
            PopupMenuButton<Character>(
              icon: const Icon(Icons.people, color: Colors.white),
              tooltip: '切换角色',
              itemBuilder: (_) => _participants
                  .where((c) => !c.isUser) // 只切换非用户角色
                  .map(
                    (c) => PopupMenuItem<Character>(
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
                          Text(c.name),
                        ],
                      ),
                    ),
                  )
                  .toList(),
              onSelected: (c) => setState(() => _activeCharacter = c),
            ),
          if (_activeCharacter != null &&
              !_activeCharacter.isUser &&
              _participants.contains(_activeCharacter))
            if (!_activeCharacter.isUser)
              IconButton(
                icon: const Icon(
                  Icons.delete_outline,
                  color: Color.fromARGB(255, 202, 9, 9),
                ),
                tooltip: '删除当前角色',
                onPressed: () => _confirmDeleteCharacter(_activeCharacter),
              ),
          // 打开抽屉按钮
          Builder(
            builder: (context) => IconButton(
              icon: const Icon(Icons.menu),
              tooltip: '更多功能',
              onPressed: () => Scaffold.of(context).openEndDrawer(),
            ),
          ),
        ],
      ),
      endDrawer: Drawer(
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.symmetric(vertical: 8),
            children: [
              // 上下文长度滑块
              ListTile(
                title: const Text('上下文长度'),
                subtitle: Slider(
                  value: _contextLength.toDouble(),
                  min: 1,
                  max: 200,
                  divisions: 199,
                  label: _contextLength >= 200 ? '全文' : '$_contextLength条',
                  onChanged: (v) {
                    setState(() => _contextLength = v.toInt());
                    StorageService.saveChatContextLength(v.toInt());
                  },
                ),
              ),
              // 随机事件
              ListTile(
                leading: const Icon(Icons.casino),
                title: const Text('随机事件'), // 可以改名
                onTap: () async {
                  Navigator.pop(context);
                  // 生成分支选项需要当前上下文，我们提取最近的几条消息
                  final recentMessages = _messages.length > 10
                      ? _messages.sublist(_messages.length - 10)
                      : _messages;
                  final contextStr = recentMessages
                      .map((m) => '${m.sender}：${m.text}')
                      .join('\n');
                  final branchPrompt = '当前剧情上下文：\n$contextStr\n\n请生成3个后续剧情选项。';

                  // 调用分支选项生成
                  final options = await _generateBranchOptions(branchPrompt);
                  if (options.isNotEmpty && mounted) {
                    _showBranchOptions(options);
                  }
                },
              ),
              //  我的设定（编辑主角名字/性格）
              ListTile(
                leading: const Icon(Icons.person),
                title: const Text('我的设定'),
                onTap: () {
                  Navigator.pop(context);
                  // 打开完整角色编辑界面
                  final userChar = _participants.firstWhere((c) => c.isUser);
                  _editCharacter(userChar);
                },
              ),
              // 上帝模式
              ListTile(
                leading: const Text('⚡', style: TextStyle(fontSize: 20)),
                title: const Text('上帝模式'),
                onTap: () {
                  Navigator.pop(context);
                  _showGodModeDialog();
                },
              ),
              // 世界背景
              ListTile(
                leading: const Icon(Icons.public),
                title: const Text('世界背景'),
                onTap: () {
                  Navigator.pop(context);
                  _editWorldSetting();
                },
              ),
              // 记忆事件管理
              ListTile(
                leading: const Icon(Icons.memory),
                title: const Text('记忆事件'),
                onTap: () {
                  Navigator.pop(context);
                  _manageMemoryEvents();
                },
              ),
              // 编辑旁白提示词
              ListTile(
                leading: const Icon(Icons.edit_note),
                title: const Text('旁白提示词'),
                onTap: () {
                  Navigator.pop(context);
                  _editNarrationPrompt();
                },
              ),
              // 编辑当前角色
              ListTile(
                leading: const Icon(Icons.edit),
                title: const Text('编辑当前角色'),
                onTap: () {
                  Navigator.pop(context);
                  _editCharacter(_activeCharacter);
                },
              ),
              // 添加角色
              ListTile(
                leading: const Icon(Icons.person_add),
                title: const Text('添加角色'),
                onTap: () {
                  Navigator.pop(context);
                  _addCharacter();
                },
              ),
              // 保存存档
              ListTile(
                leading: const Icon(Icons.save_alt),
                title: const Text('保存存档'),
                onTap: () {
                  Navigator.pop(context);
                  _saveAsArchive();
                },
              ),
              // 自主对话开关
              ListTile(
                leading: Icon(
                  _isAutoConversation ? Icons.stop_circle : Icons.auto_mode,
                ),
                title: Text(_isAutoConversation ? '停止自主对话' : '角色自主对话'),
                onTap: () {
                  Navigator.pop(context);
                  if (_isAutoConversation) {
                    _stopAutoConversation();
                  } else {
                    _autoConversation();
                  }
                },
              ),
              ListTile(
                leading: const Icon(Icons.delete_sweep, color: Colors.red),
                title: const Text('清空聊天记录'),
                onTap: () async {
                  Navigator.pop(context);
                  final confirm = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('清空聊天记录'),
                      content: const Text('确定要删除所有聊天消息吗？此操作不可恢复。'),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: const Text('取消'),
                        ),
                        FilledButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          child: const Text('清空'),
                        ),
                      ],
                    ),
                  );
                  if (confirm == true) {
                    setState(() => _messages.clear());
                    _saveHistory();
                  }
                },
              ),
              // 滚动到底（浮动按钮已有，保留以防万一）
              ListTile(
                leading: const Icon(Icons.arrow_downward),
                title: const Text('滚动到底部'),
                onTap: () {
                  Navigator.pop(context);
                  if (_scrollController.hasClients) {
                    _scrollController.animateTo(
                      _scrollController.position.maxScrollExtent,
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeOut,
                    );
                  }
                },
              ),
            ],
          ),
        ),
      ),
      // ... 原来的 body 保持不变
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
            padding: EdgeInsets.symmetric(vertical: 2, horizontal: 12),
            color: Colors.grey.shade100,
            child: Text(
              '本次：$_lastTotalTokens tokens | 累计：$_cumulativeTokens tokens',
              style: TextStyle(fontSize: 12),
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
          // 消息列表
          Expanded(
            child: Stack(
              children: [
                ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 12,
                  ),
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
                      if (_isLoading) {
                        return const Padding(
                          padding: EdgeInsets.all(8.0),
                          child: Row(
                            children: [
                              SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
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

                    // 消息动画与内容（保持你原有的完整消息气泡代码）
                    final isAnimating = _animatingIndices.contains(msgIndex);
                    Widget messageContent = Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Column(
                        crossAxisAlignment: isMe
                            ? CrossAxisAlignment.end
                            : CrossAxisAlignment.start,
                        children: [
                          if (!isMe)
                            Padding(
                              padding: const EdgeInsets.only(
                                left: 12,
                                bottom: 2,
                              ),
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
                                      topLeft: const Radius.circular(20),
                                      topRight: const Radius.circular(20),
                                      bottomLeft: isMe
                                          ? const Radius.circular(20)
                                          : Radius.zero,
                                      bottomRight: isMe
                                          ? Radius.zero
                                          : const Radius.circular(20),
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withOpacity(0.05),
                                        blurRadius: 4,
                                        offset: const Offset(0, 2),
                                      ),
                                    ],
                                  ),
                                  child: SelectableText(
                                    _cleanMessageText(message),
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
                    );

                    final fullMessage = GestureDetector(
                      onLongPress: () => _showMessageContextMenu(msgIndex),
                      child: messageContent,
                    );

                    if (isAnimating) {
                      return TweenAnimationBuilder<double>(
                        tween: Tween(begin: 0.0, end: 1.0),
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeOutCubic,
                        builder: (context, value, child) {
                          return Opacity(
                            opacity: value,
                            child: Transform.translate(
                              offset: Offset(0, 20 * (1 - value)),
                              child: child,
                            ),
                          );
                        },
                        child: fullMessage,
                      );
                    } else {
                      return fullMessage;
                    }
                  },
                ),
                if (!_isNearBottom)
                  Positioned(
                    right: 16,
                    bottom: 16,
                    child: FloatingActionButton.small(
                      heroTag: 'scrollDown',
                      backgroundColor: Colors.deepPurple,
                      onPressed: () {
                        _scrollToBottom();
                        setState(() => _isNearBottom = true);
                      },
                      child: const Icon(
                        Icons.keyboard_arrow_down,
                        color: Colors.white,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          // 底部快捷按钮行（只保留发言、旁白、总结）
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border(top: BorderSide(color: Colors.grey.shade300)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                SmallButton(
                  icon: Icons.record_voice_over,
                  label: '发言',
                  color: _characterColors[_activeCharacter.name] ?? Colors.blue,
                  onPressed: _isLoading ? null : _activeCharacterSpeak,
                ),
                SmallButton(
                  icon: Icons.auto_stories,
                  label: '旁白',
                  color: Colors.brown.shade300,
                  onPressed: _isLoading ? null : _generateNarration,
                ),
                SmallButton(
                  icon: Icons.summarize,
                  label: '总结',
                  color: Colors.teal.shade300,
                  onPressed: _isLoading ? null : _generateSummary,
                ),
              ],
            ),
          ),

          // 底部输入框 + 图片生成 + 展开 + 发送按钮
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
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _textController,
                        focusNode: _textFocusNode,
                        minLines: 1,
                        maxLines: _isInputExpanded ? 6 : 1,
                        textInputAction: TextInputAction.send,
                        decoration: const InputDecoration(
                          hintText: '输入消息...',
                          border: InputBorder.none,
                        ),
                        onSubmitted: (_) => _sendMessage(),
                      ),
                    ),
                    // "更多"弹出按钮（包含@提及、图片、展开/收起）
                    PopupMenuButton<String>(
                      icon: const Icon(Icons.add_circle_outline),
                      tooltip: '更多',
                      onSelected: (value) {
                        switch (value) {
                          case 'mention':
                            _showMentionPicker();
                            break;
                          case 'image':
                            _generateForLatestAi();
                            break;
                          case 'expand':
                            setState(
                              () => _isInputExpanded = !_isInputExpanded,
                            );
                            if (_isInputExpanded) _textFocusNode.requestFocus();
                            break;
                        }
                      },
                      itemBuilder: (ctx) => [
                        const PopupMenuItem(
                          value: 'mention',
                          child: ListTile(
                            leading: Icon(Icons.alternate_email),
                            title: Text('提及角色'),
                          ),
                        ),
                        const PopupMenuItem(
                          value: 'image',
                          child: ListTile(
                            leading: Icon(Icons.photo_library_outlined),
                            title: Text('生成图片'),
                          ),
                        ),
                        PopupMenuItem(
                          value: 'expand',
                          child: ListTile(
                            leading: Icon(
                              _isInputExpanded
                                  ? Icons.expand_less
                                  : Icons.expand_more,
                            ),
                            title: Text(_isInputExpanded ? '收起输入框' : '展开输入框'),
                          ),
                        ),
                      ],
                    ),
                    // 发送按钮
                    IconButton(
                      icon: const Icon(Icons.send, color: Colors.deepPurple),
                      onPressed: _sendMessage,
                    ),
                  ],
                ),
              ],
            ),
          ),

          // 底部控制区改版
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
/////////////////////////////////////////////
novel_chat_page.dart
import 'package:flutter/material.dart';
import '../models/chat_message.dart';
import '../models/novel_project.dart';
import '../models/character.dart';
import '../services/ai_service.dart';
import '../services/novel_storage_service.dart';
import '../services/storage_service.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../widgets/small_button.dart';
import '../services/image_service.dart';
import 'package:flutter/services.dart';

class NovelChatPage extends StatefulWidget {
  final NovelProject project;
  final String? saveId;
  final String? archiveName;
  const NovelChatPage({
    super.key,
    required this.project,
    this.saveId,
    this.archiveName,
  });

  @override
  State<NovelChatPage> createState() => _NovelChatPageState();
}

class _NovelChatPageState extends State<NovelChatPage> {
  late NovelProject _project;
  final List<ChatMessage> _messages = [];
  final TextEditingController _textController = TextEditingController();
  bool _isLoading = false;
  bool _isNearBottom = true;
  bool _isReady = false; // 是否已完成数据加载
  Character? _selectedSpeakCharacter; // 预设的发言角色，空则弹窗选择
  int _lastTotalTokens = 0;
  int _cumulativeTokens = 0;
  String _imagePrefixModifier = '';
  String _imageSuffixModifier = '';
  final speakingCtrl = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  int _contextLength = 20;
  List<String> _memoryEvents = [];
  bool _isInputExpanded = false;
  final FocusNode _textFocusNode = FocusNode();

  bool _pendingSystemUpdate = false;
  String _summaryPrompt = ''; // 当前小说的总结提示词，空表示用全局
  void _insertSystemNotification(String content) {
    setState(() {
      _messages.add(
        ChatMessage(text: '【系统提示】$content', isUser: false, sender: '系统'),
      );
      _pendingSystemUpdate = true;
    });
    _saveHistory();
  }

  static const String _defaultNarratorPrompt = '''
你是小说叙事引擎，以文学旁白口吻推进故事。
只输出旁白，不添加任何解释或对话。
使用第三人称过去时，描写场景、动作、心理，生动细腻。
每次回复 150-350 字。
''';
  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final maxScroll = _scrollController.position.maxScrollExtent;
    final currentScroll = _scrollController.position.pixels;
    final isNearBottom = (maxScroll - currentScroll) <= 100.0;
    if (_isNearBottom != isNearBottom) {
      setState(() => _isNearBottom = isNearBottom);
    }
  }

  void _addTokens(AiResponse response) {
    _cumulativeTokens += response.totalTokens;
    _lastTotalTokens = response.totalTokens;
    setState(() {});
  }

  Future<void> _loadSummaryPrompt() async {
    _summaryPrompt = await NovelStorageService.loadSummaryPrompt(_project.id);
    setState(() {});
  }

  void _scrollToBottomIfNeeded() {
    if (_isNearBottom) {
      _scrollToBottom();
    }
  }

  void _triggerNarrator() async {
    _messages.add(
      ChatMessage(text: '旁白正在生成...', isUser: false, sender: '📖 旁白'),
    );
    setState(() => _isLoading = true);

    try {
      final aiResponse = await _callNarrator(userPrompt: '请根据当前剧情继续发展下一段故事。');
      _messages.removeLast();
      _messages.add(
        ChatMessage(text: aiResponse.content, isUser: false, sender: '📖 旁白'),
      );
    } catch (e) {
      _messages.removeLast();
      _messages.add(
        ChatMessage(text: '旁白生成失败: $e', isUser: false, sender: '系统'),
      );
    }

    setState(() => _isLoading = false);
    _saveHistory();
    _scrollToBottomIfNeeded();
  }

  void _regenerateNarration(int index) async {
    if (_isLoading) return;
    final msg = _messages[index];
    if (msg.sender != '📖 旁白') return;

    // 删除原来的旁白
    setState(() => _messages.removeAt(index));
    _saveHistory();

    // 重新生成一段旁白
    _triggerNarrator(); // _triggerNarrator 已经是 void async，不要用 await 它的返回值
  }

  void _characterSpeak({bool direct = false}) async {
    if (_project.characters.isEmpty) return;

    // 先取得一个非空的角色引用
    final Character? selectedChar;
    if (direct && _selectedSpeakCharacter != null) {
      selectedChar = _selectedSpeakCharacter;
    } else {
      selectedChar = await showDialog<Character>(
        context: context,
        builder: (dialogCtx) => SimpleDialog(
          title: const Text('选择发言角色'),
          children: _project.characters
              .map(
                (c) => SimpleDialogOption(
                  onPressed: () => Navigator.pop(dialogCtx, c),
                  child: Text(c.name),
                ),
              )
              .toList(),
        ),
      );
    }
    if (selectedChar == null) return;

    // 现在 selectedChar 已确定非空，赋给 final 变量
    final char = selectedChar;

    setState(() => _isLoading = true);
    try {
      final systemPrompt =
          '你扮演${char.name}，性格：${char.personality}。初始着装：${char.attire.isEmpty ? "未指定" : char.attire}。外貌：${char.catchphrase.isEmpty ? "未指定" : char.catchphrase}。背景：${char.background.isEmpty ? "未指定" : char.background}。说话风格：${char.speakingStyle.isEmpty ? "未指定" : char.speakingStyle}。\n'
          '请在当前故事背景下...';
      final recent = _messages.length > 5
          ? _messages.sublist(_messages.length - 5)
          : _messages;
      final contextStr = recent.map((m) => m.text).join('\n');
      final resp = await AiService.callChatApi(
        modelLabel: char.aiModel.isNotEmpty
            ? char.aiModel
            : (_project.narratorModelLabel.isNotEmpty
                  ? _project.narratorModelLabel
                  : 'deepseek'),
        messages: [
          {'role': 'system', 'content': systemPrompt},
          {
            'role': 'user',
            'content': '当前剧情上下文：\n$contextStr\n\n请${char.name}发言：',
          },
        ],
      );
      _addTokens(resp);
      setState(() {
        _messages.add(
          ChatMessage(text: resp.content, isUser: false, sender: char.name),
        );
        _isLoading = false;
      });
      _saveHistory();
      _scrollToBottomIfNeeded();
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('角色发言失败: $e')));
      }
    }
  }

  void _autoSelectSpeakCharacter() {
    if (_project.characters.isNotEmpty) {
      _selectedSpeakCharacter = _project.characters.first;
    } else {
      _selectedSpeakCharacter = null; // 防止悬空引用
    }
  }

  @override
  void initState() {
    super.initState();
    _project = widget.project;
    _scrollController.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadAllData().then((_) {
        if (mounted) setState(() => _isReady = true);
      });
    });
  }

  Future<void> _loadAllData() async {
    if (widget.saveId != null) {
      await _loadSaveHistory(widget.saveId!);
    } else {
      await _loadHistory();
    }
    await _loadMemoryEvents();
    if (_project.narratorModelLabel.isEmpty) await _loadDefaultModel();
    await _loadImageModifiers();
    await _loadContextLength();
    await _loadSummaryPrompt();
    _autoSelectSpeakCharacter();
  }

  Future<void> _loadSaveHistory(String saveId) async {
    final saveData = await NovelStorageService.loadSaveData(saveId);
    final messages = saveData['messages'] as List<ChatMessage>;
    final memories = saveData['memoryEvents'] as List<String>;
    final totalTokens = saveData['totalTokens'] as int? ?? 0;
    _cumulativeTokens = totalTokens;
    setState(() {
      _messages.addAll(messages);
      _memoryEvents = memories;
    });
  }

  Future<void> _editSummaryPrompt() async {
    final ctrl = TextEditingController(text: _summaryPrompt);
    final res = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('总结提示词（本小说）'),
        content: TextField(
          controller: ctrl,
          maxLines: 10,
          minLines: 3,
          decoration: const InputDecoration(
            hintText: '留空则使用全局设置',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (res != null) {
      setState(() => _summaryPrompt = res);
      await NovelStorageService.saveSummaryPrompt(_project.id, res);
    }
  }

  Future<void> _loadImageModifiers() async {
    final prefix = await StorageService.loadImagePrefixModifier();
    final suffix = await StorageService.loadImageSuffixModifier();
    if (!mounted) return;
    setState(() {
      _imagePrefixModifier = prefix;
      _imageSuffixModifier = suffix;
    });
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
      final modelLabel = _project.narratorModelLabel.isNotEmpty
          ? _project.narratorModelLabel
          : 'deepseek';
      final promptResponse = await AiService.callChatApi(
        modelLabel: modelLabel,
        messages: [
          {'role': 'system', 'content': systemPrompt},
          {'role': 'user', 'content': chinesePrompt},
        ],
      );
      return promptResponse.content.trim();
    } catch (e) {
      print('生成提示词失败: $e');
      return null;
    }
  }

  void _generateImageForIndex(int index) async {
    final message = _messages[index];
    // 只为旁白消息生成图片，且不能已有图片或正在生成
    if (message.sender != '📖 旁白' ||
        message.imageUrl != null ||
        message.isGeneratingImage) {
      return;
    }

    setState(() => message.isGeneratingImage = true);

    try {
      // 1. 生成英文提示词
      final englishPrompt = await _generateImagePrompt(message.text);
      if (englishPrompt == null) throw Exception('AI生成提示词失败');

      // 2. 拼接修饰词
      String finalPrompt = englishPrompt;
      if (_imagePrefixModifier.isNotEmpty) {
        finalPrompt = '$_imagePrefixModifier, $finalPrompt';
      }
      if (_imageSuffixModifier.isNotEmpty) {
        finalPrompt = '$finalPrompt, $_imageSuffixModifier';
      }

      // 3. 调用绘图 API
      final localPath = await ImageService.generateImage(finalPrompt);
      if (localPath != null) {
        setState(() {
          message.isGeneratingImage = false;
          message.imageUrl = localPath;
        });
        StorageService.addGalleryPath(localPath);
        _saveHistory(); // 保存消息（图片路径）
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

  void _generateForLatestAi() {
    for (int i = _messages.length - 1; i >= 0; i--) {
      final msg = _messages[i];
      if (msg.sender == '📖 旁白' &&
          msg.imageUrl == null &&
          !msg.isGeneratingImage) {
        _generateImageForIndex(i);
        break;
      }
    }
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

  Future<void> _loadDefaultModel() async {
    final configs = await StorageService.loadChatApiConfigs();
    if (configs.isNotEmpty && _project.narratorModelLabel.isEmpty) {
      setState(() {
        _project.narratorModelLabel = configs.first['label']!;
      });
      await NovelStorageService.updateProject(_project);
    }
  }

  Future<void> _loadHistory() async {
    _cumulativeTokens = await NovelStorageService.loadProjectTokens(
      _project.id,
    );
    final history = await NovelStorageService.loadMessages(_project.id);
    setState(() => _messages.addAll(history));
  }

  Future<void> _saveHistory() async {
    if (widget.saveId != null) {
      // 存档模式：更新存档内的消息、记忆和 token
      final prefs = await SharedPreferences.getInstance();
      final dataStr = prefs.getString('novel_save_data_${widget.saveId}');
      if (dataStr != null) {
        final data = jsonDecode(dataStr);
        data['messages'] = _messages.map((m) => m.toJson()).toList();
        data['memoryEvents'] = _memoryEvents;
        data['totalTokens'] = _cumulativeTokens;
        await prefs.setString(
          'novel_save_data_${widget.saveId}',
          jsonEncode(data),
        );
      }
    } else {
      // 本体模式：保存到项目
      await NovelStorageService.saveMessages(_project.id, _messages);
    }
  }

  Future<void> _loadMemoryEvents() async {
    if (widget.saveId != null) return; // 存档模式下已在 _loadSaveHistory 设置
    _memoryEvents = await NovelStorageService.loadMemoryEvents(_project.id);
    setState(() {});
  }

  // 无关代码：删除旧的 _loadCumulativeTokens（已不再需要）

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

  void _deleteMessage(int index) {
    setState(() => _messages.removeAt(index));
    _saveHistory();
  }

  void _addToMemory(int index) async {
    final text = _messages[index].text;
    _memoryEvents.add(text);
    setState(() {});
    // 全局记忆在本体模式下才需要额外存储，存档模式由 _saveHistory 处理
    if (widget.saveId == null) {
      await NovelStorageService.addMemoryEvent(_project.id, text);
    }
    _saveHistory();
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('已保存为记忆事件')));
  }

  void _manageMemoryEvents() {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(12.0),
              child: Text(
                '记忆事件',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
              ),
            ),
            if (_memoryEvents.isEmpty)
              const Padding(padding: EdgeInsets.all(16), child: Text('暂无记忆事件'))
            else
              SizedBox(
                height: 300,
                child: ListView.builder(
                  itemCount: _memoryEvents.length,
                  itemBuilder: (_, i) => ListTile(
                    leading: const Icon(Icons.memory),
                    title: Text(
                      _memoryEvents[i],
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    onTap: () {
                      showDialog(
                        context: context,
                        builder: (_) => AlertDialog(
                          title: const Text('记忆事件详情'),
                          content: SingleChildScrollView(
                            child: Text(_memoryEvents[i]),
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(context),
                              child: const Text('关闭'),
                            ),
                          ],
                        ),
                      );
                    },
                    trailing: IconButton(
                      icon: const Icon(Icons.delete, color: Colors.red),
                      onPressed: () async {
                        _memoryEvents.removeAt(i);
                        setState(() {});
                        if (widget.saveId == null) {
                          await NovelStorageService.removeMemoryEvent(
                            _project.id,
                            i,
                          );
                        }
                        _saveHistory(); // 统一保存（存档模式自动写回存档）
                        Navigator.pop(ctx);
                        _manageMemoryEvents();
                      },
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _sendGodCommand() async {
    final text = _textController.text.trim();
    if (text.isEmpty) return;

    _messages.add(
      ChatMessage(text: '上帝指令：$text', isUser: true, sender: '👑 上帝'),
    );
    _messages.add(
      ChatMessage(text: '旁白正在生成...', isUser: false, sender: '📖 旁白'),
    );
    setState(() {
      _isLoading = true;
      _textController.clear();
    });

    try {
      final aiResponse = await _callNarrator(userPrompt: null);
      _messages.removeLast();
      _messages.add(
        ChatMessage(text: aiResponse.content, isUser: false, sender: '📖 旁白'),
      );
    } catch (e) {
      _messages.removeLast();
      _messages.add(
        ChatMessage(text: '旁白生成失败: $e', isUser: false, sender: '系统'),
      );
    }

    setState(() => _isLoading = false);
    _saveHistory();
    _textFocusNode.unfocus();
  }

  Future<void> _loadContextLength() async {
    _contextLength = await StorageService.loadNovelContextLength();
    setState(() {});
  }

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
        .map((m) => '${m.sender}：${m.text}')
        .join('\n');
    final userPrompt = '当前剧情上下文：\n$contextStr\n\n请生成一个随机事件。';

    try {
      final aiResponse = await AiService.callChatApi(
        modelLabel: _project.narratorModelLabel,
        messages: [
          {'role': 'system', 'content': systemPrompt},
          {'role': 'user', 'content': userPrompt},
        ],
      );
      setState(() {
        _messages.add(
          ChatMessage(
            text: '⚡ 随机事件：${aiResponse.content}',
            isUser: true,
            sender: '👑 上帝',
          ),
        );
        _isLoading = false;
      });
      _saveHistory();
    } catch (e) {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('随机事件失败: $e')));
    }
  }

  Future<AiResponse> _callNarrator({String? userPrompt}) async {
    final originalContext = _contextLength;
    if (_pendingSystemUpdate) {
      _contextLength = _messages.length;
    }
    try {
      String modelLabel = _project.narratorModelLabel;
      if (modelLabel.isEmpty) {
        final configs = await StorageService.loadChatApiConfigs();
        modelLabel = configs.isNotEmpty ? configs.first['label']! : '';
      }
      if (modelLabel.isEmpty) {
        // 实在没有则返回错误
        return AiResponse(
          content: '未配置旁白模型',
          promptTokens: 0,
          completionTokens: 0,
          totalTokens: 0,
        );
      }
      final messages = <Map<String, dynamic>>[];
      String fullSystemPrompt = _project.narratorPrompt.isNotEmpty
          ? _project.narratorPrompt
          : _defaultNarratorPrompt;
      if (_project.worldSetting.isNotEmpty) {
        fullSystemPrompt += '\n世界观：${_project.worldSetting}';
      }
      if (_project.characters.isNotEmpty) {
        fullSystemPrompt +=
            '\n角色：${_project.characters.map((c) => "${c.name}（${c.personality}，着装：${c.attire}，说话风格：${c.speakingStyle}）").join("、")}';
      }
      if (_memoryEvents.isNotEmpty) {
        fullSystemPrompt += '\n重要记忆：';
        for (final mem in _memoryEvents) {
          fullSystemPrompt += '\n- $mem';
        }
      }
      messages.add({'role': 'system', 'content': fullSystemPrompt});

      final int maxHistory = _contextLength <= 0
          ? _messages.length
          : _contextLength;
      final int start = (_messages.length - maxHistory).clamp(
        0,
        _messages.length,
      );
      for (int i = start; i < _messages.length; i++) {
        final msg = _messages[i];
        if (msg.sender == '👑 上帝') {
          messages.add({'role': 'user', 'content': msg.text});
        } else if (msg.sender == '📖 旁白') {
          messages.add({'role': 'assistant', 'content': msg.text});
        }
      }
      if (userPrompt != null) {
        messages.add({'role': 'user', 'content': userPrompt});
      }

      final aiResponse = await AiService.callChatApi(
        modelLabel: modelLabel,
        messages: messages,
      );

      // 更新 token（仅此处）
      _lastTotalTokens = aiResponse.totalTokens;
      _cumulativeTokens += aiResponse.totalTokens;
      if (widget.saveId != null) {
        final prefs = await SharedPreferences.getInstance();
        final dataStr = prefs.getString('novel_save_data_${widget.saveId}');
        if (dataStr != null) {
          final data = jsonDecode(dataStr);
          data['totalTokens'] = _cumulativeTokens;
          await prefs.setString(
            'novel_save_data_${widget.saveId}',
            jsonEncode(data),
          );
        }
      } else {
        await NovelStorageService.saveProjectTokens(
          _project.id,
          _cumulativeTokens,
        );
      }
      setState(() {});
      _saveHistory();
      return aiResponse;
    } finally {
      if (_pendingSystemUpdate) {
        _contextLength = originalContext;
        _pendingSystemUpdate = false;
      }
    }
  }

  Future<void> _generateSummary() async {
    if (_isLoading) return;
    setState(() => _isLoading = true);
    try {
      // 优先用项目自身的提示词，为空则用全局设置，再为空用默认
      final customPrompt = _summaryPrompt.isNotEmpty
          ? _summaryPrompt
          : await StorageService.loadSummaryPrompt();
      final summaryPrompt = customPrompt.isNotEmpty
          ? customPrompt
          : StorageService.defaultSummaryPrompt;

      final lastSummaryIndex = await NovelStorageService.loadSummaryIndex(
        _project.id,
      );
      final newNarrations = <ChatMessage>[];
      for (int i = lastSummaryIndex; i < _messages.length; i++) {
        if (_messages[i].sender == '📖 旁白') newNarrations.add(_messages[i]);
      }
      if (newNarrations.isEmpty) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('没有新的旁白内容需要总结')));
        return;
      }

      final narrationText = newNarrations.map((m) => m.text).join('\n');
      final userPrompt = '请对以下新剧情生成简要摘要：\n$narrationText';
      final aiResponse = await AiService.callChatApi(
        modelLabel: _project.narratorModelLabel.isNotEmpty
            ? _project.narratorModelLabel
            : 'deepseek',
        messages: [
          {'role': 'system', 'content': summaryPrompt},
          {'role': 'user', 'content': userPrompt},
        ],
      );
      final newIndex = _messages.length;
      await NovelStorageService.saveSummaryIndex(_project.id, newIndex);

      setState(() {
        _messages.add(
          ChatMessage(
            text: '📊 剧情摘要：\n${aiResponse.content}',
            isUser: false,
            sender: '📖 系统',
          ),
        );
        _isLoading = false;
      });
      _saveHistory();
    } catch (e) {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('摘要失败: $e')));
    }
  }

  Future<void> _exportNovel() async {
    final buffer = StringBuffer();
    for (final msg in _messages) {
      if (msg.isUser) {
        buffer.writeln('${msg.sender}：${msg.text}');
      } else if (msg.sender == '📖 系统') {
        continue;
      } else {
        buffer.writeln(msg.text);
      }
      buffer.writeln();
    }
    final fullText = buffer.toString();
    if (!mounted) return;

    final shouldSave = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('小说预览'),
        content: SizedBox(
          width: double.maxFinite,
          height: 400,
          child: SingleChildScrollView(child: SelectableText(fullText)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('关闭'),
          ),
          FilledButton.icon(
            icon: const Icon(Icons.share),
            label: const Text('分享 / 保存'),
            onPressed: () => Navigator.pop(ctx, true),
          ),
        ],
      ),
    );
    if (shouldSave != true) return;

    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/${_project.title}.txt');
      await file.writeAsString(fullText);
      await Share.shareXFiles([XFile(file.path)], subject: _project.title);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('导出失败: $e')));
      }
    }
  }

  void _editWorldSetting() async {
    final ctrl = TextEditingController(text: _project.worldSetting);
    final res = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('世界观'),
        content: TextField(
          controller: ctrl,
          maxLines: 5,
          decoration: const InputDecoration(hintText: '世界背景...'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (res != null) {
      setState(() => _project.worldSetting = res);
      await NovelStorageService.updateProject(_project);
      _insertSystemNotification('世界观已更新：$res');
    }
  }

  void _editNarratorPrompt() async {
    final ctrl = TextEditingController(
      text: _project.narratorPrompt.isEmpty
          ? _defaultNarratorPrompt
          : _project.narratorPrompt,
    );
    final res = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('旁白提示词'),
        content: TextField(
          controller: ctrl,
          maxLines: 10,
          decoration: const InputDecoration(border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (res != null) {
      setState(() => _project.narratorPrompt = res);
      await NovelStorageService.updateProject(_project);
      _insertSystemNotification('旁白提示词已更新');
    }
  }

  Future<void> _saveAsArchive() async {
    final nameCtrl = TextEditingController();
    final String? name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('保存存档'),
        content: TextField(
          controller: nameCtrl,
          decoration: const InputDecoration(hintText: '存档名称...'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, nameCtrl.text.trim()),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (name != null && name.isNotEmpty) {
      await NovelStorageService.createSave(
        _project.id,
        name,
        _messages,
        _memoryEvents,
        _cumulativeTokens,
      );
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('存档已保存')));
    }
  }

  void _selectNarratorModel() async {
    final configs = await StorageService.loadChatApiConfigs();
    if (configs.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请先添加对话 API')));
      return;
    }
    final labels = configs.map((c) => c['label']!).toList();
    final selected = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('旁白模型'),
        children: labels
            .map(
              (l) => RadioListTile<String>(
                title: Text(l),
                value: l,
                groupValue: _project.narratorModelLabel,
                onChanged: (v) => Navigator.pop(ctx, v),
              ),
            )
            .toList(),
      ),
    );
    if (selected != null) {
      setState(() => _project.narratorModelLabel = selected);
      await NovelStorageService.updateProject(_project);
      _insertSystemNotification('旁白模型已切换为 $selected');
    }
  }

  Future<void> _addCharacter() async {
    final nameCtrl = TextEditingController();
    final persCtrl = TextEditingController();
    final attireCtrl = TextEditingController();
    final bgCtrl = TextEditingController();
    final catchCtrl = TextEditingController();
    final likesCtrl = TextEditingController();
    final dislikesCtrl = TextEditingController();
    final speakingCtrl = TextEditingController();
    final configs = await StorageService.loadChatApiConfigs();
    final labels = configs.map((c) => c['label']!).toList();
    String selModel = labels.isNotEmpty ? labels.first : '';

    final newChar = await showDialog<Character>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('添加角色'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(labelText: '名字'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: persCtrl,
                  decoration: const InputDecoration(labelText: '性格'),
                  maxLines: 2,
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: attireCtrl,
                  decoration: const InputDecoration(labelText: '着装'),
                  maxLines: 2,
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: bgCtrl,
                  decoration: const InputDecoration(labelText: '背景故事'),
                  maxLines: 3,
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: catchCtrl,
                  decoration: const InputDecoration(labelText: '外貌'),
                  maxLines: 2,
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: likesCtrl,
                  decoration: const InputDecoration(labelText: '喜好'),
                  maxLines: 2,
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: dislikesCtrl,
                  decoration: const InputDecoration(labelText: '厌恶'),
                  maxLines: 2,
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: speakingCtrl,
                  decoration: const InputDecoration(
                    labelText: '说话风格',
                    hintText: '例：古风、毒舌、话痨...',
                  ),
                  maxLines: 2,
                ),
                ElevatedButton.icon(
                  icon: const Icon(Icons.auto_fix_high),
                  label: const Text('AI 解析角色'),
                  onPressed: () async {
                    final textCtrl = TextEditingController();
                    final ok = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text('粘贴角色设定文本'),
                        content: TextField(
                          controller: textCtrl,
                          maxLines: 8,
                          decoration: const InputDecoration(
                            hintText: '粘贴文本...',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(ctx, false),
                            child: const Text('取消'),
                          ),
                          FilledButton(
                            onPressed: () => Navigator.pop(ctx, true),
                            child: const Text('解析'),
                          ),
                        ],
                      ),
                    );
                    if (ok == true && textCtrl.text.trim().isNotEmpty) {
                      final parsed = await AiService.parseCharacterText(
                        textCtrl.text.trim(),
                        modelLabel: _project.narratorModelLabel.isNotEmpty
                            ? _project.narratorModelLabel
                            : 'deepseek', // 或从配置取第一个
                      );
                      if (parsed != null) {
                        setDialogState(() {
                          nameCtrl.text = parsed['name'] ?? '';
                          persCtrl.text = parsed['personality'] ?? '';
                          attireCtrl.text = parsed['attire'] ?? '';
                          bgCtrl.text = parsed['background'] ?? '';
                          catchCtrl.text = parsed['catchphrase'] ?? '';
                          likesCtrl.text = parsed['likes'] ?? '';
                          dislikesCtrl.text = parsed['dislikes'] ?? '';
                          speakingCtrl.text = parsed['speakingStyle'] ?? '';
                        });
                      }
                    }
                  },
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  initialValue: selModel,
                  items: labels
                      .map((l) => DropdownMenuItem(value: l, child: Text(l)))
                      .toList(),
                  onChanged: (v) => setDialogState(() => selModel = v!),
                  decoration: const InputDecoration(labelText: '模型'),
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
                if (nameCtrl.text.trim().isEmpty) return;
                Navigator.pop(
                  ctx,
                  Character(
                    name: nameCtrl.text.trim(),
                    personality: persCtrl.text.trim(),
                    attire: attireCtrl.text.trim(),
                    background: bgCtrl.text.trim(),
                    catchphrase: catchCtrl.text.trim(),
                    likes: likesCtrl.text.trim(),
                    dislikes: dislikesCtrl.text.trim(),
                    speakingStyle: speakingCtrl.text.trim(),
                    aiModel: selModel,
                  ),
                );
              },
              child: const Text('添加'),
            ),
          ],
        ),
      ),
    );
    if (newChar != null) {
      setState(() => _project.characters.add(newChar));
      await NovelStorageService.updateProject(_project);
      _insertSystemNotification('新角色“${newChar.name}”加入');
      await NovelStorageService.updateProject(_project);
      _autoSelectSpeakCharacter();
    }
  }

  Future<void> _editCharacter(Character character) async {
    final nameCtrl = TextEditingController(text: character.name);
    final persCtrl = TextEditingController(text: character.personality);
    final attireCtrl = TextEditingController(text: character.attire);
    final bgCtrl = TextEditingController(text: character.background);
    final catchCtrl = TextEditingController(text: character.catchphrase);
    final likesCtrl = TextEditingController(text: character.likes);
    final dislikesCtrl = TextEditingController(text: character.dislikes);
    final speakingCtrl = TextEditingController(text: character.speakingStyle);
    final configs = await StorageService.loadChatApiConfigs();
    final labels = configs.map((c) => c['label']!).toList();
    String selModel = character.aiModel;
    if (!labels.contains(selModel)) {
      selModel = labels.isNotEmpty ? labels.first : '';
    }

    final edited = await showDialog<Character>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('编辑角色'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(labelText: '名字'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: persCtrl,
                  decoration: const InputDecoration(labelText: '性格'),
                  maxLines: 2,
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: attireCtrl,
                  decoration: const InputDecoration(labelText: '着装'),
                  maxLines: 2,
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: bgCtrl,
                  decoration: const InputDecoration(labelText: '背景故事'),
                  maxLines: 3,
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: catchCtrl,
                  decoration: const InputDecoration(labelText: '外貌'),
                  maxLines: 2,
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: likesCtrl,
                  decoration: const InputDecoration(labelText: '喜好'),
                  maxLines: 2,
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: dislikesCtrl,
                  decoration: const InputDecoration(labelText: '厌恶'),
                  maxLines: 2,
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: speakingCtrl,
                  decoration: const InputDecoration(
                    labelText: '说话风格',
                    hintText: '例：古风、毒舌、话痨...',
                  ),
                  maxLines: 2,
                ),
                const SizedBox(height: 8),
                ElevatedButton.icon(
                  icon: const Icon(Icons.auto_fix_high),
                  label: const Text('AI 解析角色'),
                  onPressed: () async {
                    final textCtrl = TextEditingController();
                    final ok = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text('粘贴角色设定文本'),
                        content: TextField(
                          controller: textCtrl,
                          maxLines: 8,
                          decoration: const InputDecoration(
                            hintText: '粘贴文本...',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(ctx, false),
                            child: const Text('取消'),
                          ),
                          FilledButton(
                            onPressed: () => Navigator.pop(ctx, true),
                            child: const Text('解析'),
                          ),
                        ],
                      ),
                    );
                    if (ok == true && textCtrl.text.trim().isNotEmpty) {
                      final parsed = await AiService.parseCharacterText(
                        textCtrl.text.trim(),
                        modelLabel: _project.narratorModelLabel.isNotEmpty
                            ? _project.narratorModelLabel
                            : 'deepseek', // 或从配置取第一个
                      );
                      if (parsed != null) {
                        setDialogState(() {
                          nameCtrl.text = parsed['name'] ?? '';
                          persCtrl.text = parsed['personality'] ?? '';
                          attireCtrl.text = parsed['attire'] ?? '';
                          bgCtrl.text = parsed['background'] ?? '';
                          catchCtrl.text = parsed['catchphrase'] ?? '';
                          likesCtrl.text = parsed['likes'] ?? '';
                          dislikesCtrl.text = parsed['dislikes'] ?? '';
                          speakingCtrl.text = parsed['speakingStyle'] ?? '';
                        });
                      }
                    }
                  },
                ),
                DropdownButtonFormField<String>(
                  initialValue: selModel,
                  items: labels
                      .map((l) => DropdownMenuItem(value: l, child: Text(l)))
                      .toList(),
                  onChanged: (v) => setDialogState(() => selModel = v!),
                  decoration: const InputDecoration(labelText: '模型'),
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
                if (nameCtrl.text.trim().isEmpty) return;
                Navigator.pop(
                  ctx,
                  Character(
                    id: character.id,
                    name: nameCtrl.text.trim(),
                    personality: persCtrl.text.trim(),
                    attire: attireCtrl.text.trim(),
                    background: bgCtrl.text.trim(),
                    catchphrase: catchCtrl.text.trim(),
                    likes: likesCtrl.text.trim(),
                    dislikes: dislikesCtrl.text.trim(),
                    speakingStyle: speakingCtrl.text.trim(),
                    aiModel: selModel,
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
        final idx = _project.characters.indexWhere((c) => c.id == edited.id);
        if (idx != -1) _project.characters[idx] = edited;
      });
      await NovelStorageService.updateProject(_project);
      _insertSystemNotification('角色“${edited.name}”设定已更新');
      _autoSelectSpeakCharacter();
    }
  }

  void _deleteCharacter(Character character) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除角色'),
        content: Text('确定要移除“${character.name}”吗？'),
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
      setState(() => _project.characters.remove(character));
      await NovelStorageService.updateProject(_project);
      _insertSystemNotification('角色“${character.name}”已移除');
      _autoSelectSpeakCharacter();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_isReady) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.archiveName ?? _project.title),
        actions: [
          // 旁白模型选择（常用）
          IconButton(
            icon: const Icon(Icons.smart_toy),
            tooltip: '旁白模型',
            onPressed: _selectNarratorModel,
          ),
          // 发言角色选择（类似聊天室的角色下拉）
          if (_project.characters.isNotEmpty)
            if (_project.characters.isNotEmpty &&
                _selectedSpeakCharacter != null)
              DropdownButton<Character>(
                value: _selectedSpeakCharacter,
                underline: const SizedBox(),
                icon: const Icon(
                  Icons.keyboard_arrow_down,
                  color: Colors.white,
                ),
                dropdownColor: Colors.brown.shade50,
                items: _project.characters.map((c) {
                  return DropdownMenuItem(
                    value: c,
                    child: Text(c.name, style: const TextStyle(fontSize: 14)),
                  );
                }).toList(),
                onChanged: (c) {
                  if (c != null) setState(() => _selectedSpeakCharacter = c);
                },
              ),
          // 打开抽屉按钮
          Builder(
            builder: (context) => IconButton(
              icon: const Icon(Icons.menu),
              tooltip: '更多功能',
              onPressed: () => Scaffold.of(context).openEndDrawer(),
            ),
          ),
        ],
      ),
      endDrawer: Drawer(
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.symmetric(vertical: 8),
            children: [
              // 上下文长度滑块
              ListTile(
                title: const Text('上下文长度'),
                subtitle: Slider(
                  value: _contextLength.toDouble(),
                  min: 1,
                  max: 100,
                  divisions: 99,
                  label: _contextLength >= 100 ? '全文' : '$_contextLength条',
                  onChanged: (v) {
                    setState(() => _contextLength = v.toInt());
                    StorageService.saveNovelContextLength(v.toInt());
                  },
                ),
              ),
              // 随机事件
              ListTile(
                leading: const Icon(Icons.casino),
                title: const Text('随机事件'),
                onTap: () {
                  Navigator.pop(context);
                  _generateRandomEvent();
                },
              ),
              // 世界观
              ListTile(
                leading: const Icon(Icons.public),
                title: const Text('世界观'),
                onTap: () {
                  Navigator.pop(context);
                  _editWorldSetting();
                },
              ),
              // 旁白提示词
              ListTile(
                leading: const Icon(Icons.edit_note),
                title: const Text('旁白提示词'),
                onTap: () {
                  Navigator.pop(context);
                  _editNarratorPrompt();
                },
              ),
              // 编辑总结提示词
              ListTile(
                leading: const Icon(Icons.summarize),
                title: const Text('总结提示词'),
                onTap: () {
                  Navigator.pop(context);
                  _editSummaryPrompt();
                },
              ),
              // 添加角色
              ListTile(
                leading: const Icon(Icons.person_add),
                title: const Text('添加角色'),
                onTap: () {
                  Navigator.pop(context);
                  _addCharacter();
                },
              ),
              // 记忆事件管理
              ListTile(
                leading: const Icon(Icons.memory),
                title: const Text('记忆事件'),
                onTap: () {
                  Navigator.pop(context);
                  _manageMemoryEvents();
                },
              ),
              // 导出小说
              ListTile(
                leading: const Icon(Icons.description),
                title: const Text('导出小说'),
                onTap: () {
                  Navigator.pop(context);
                  _exportNovel();
                },
              ),
              // 保存存档
              ListTile(
                leading: const Icon(Icons.save_alt),
                title: const Text('保存存档'),
                onTap: () {
                  Navigator.pop(context);
                  _saveAsArchive();
                },
              ),
              // 图片修饰词
              ListTile(
                leading: const Icon(Icons.brush),
                title: const Text('图片修饰词'),
                onTap: () {
                  Navigator.pop(context);
                  _openImageModifierPopup();
                },
              ),
              // 滚动到底
              ListTile(
                leading: const Icon(Icons.arrow_downward),
                title: const Text('滚动到底部'),
                onTap: () {
                  Navigator.pop(context);
                  if (_scrollController.hasClients) {
                    _scrollController.animateTo(
                      _scrollController.position.maxScrollExtent,
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeOut,
                    );
                  }
                },
              ),
            ],
          ),
        ),
      ),
      // ... 下面的 body 不变
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 12),
            color: Colors.grey.shade100,
            child: Text(
              '本次：$_lastTotalTokens tokens | 累计：$_cumulativeTokens tokens',
              style: const TextStyle(fontSize: 12),
            ),
          ),
          if (_project.characters.isNotEmpty)
            Container(
              height: 40,
              color: Colors.grey.shade100,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: _project.characters.length,
                itemBuilder: (_, i) {
                  final char = _project.characters[i];
                  return GestureDetector(
                    onTap: () => _editCharacter(char),
                    child: Chip(
                      label: Text(char.name),
                      onDeleted: () => _deleteCharacter(char),
                    ),
                  );
                },
              ),
            ),
          Expanded(
            child: Stack(
              children: [
                ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 12,
                  ),
                  itemCount: _messages.length + (_isLoading ? 1 : 0),
                  itemBuilder: (_, i) {
                    if (i >= _messages.length) {
                      return const Padding(
                        padding: EdgeInsets.all(8.0),
                        child: Row(
                          children: [
                            CircularProgressIndicator(strokeWidth: 2),
                            SizedBox(width: 12),
                            Text('旁白生成中...'),
                          ],
                        ),
                      );
                    }
                    final msg = _messages[i];
                    final isGod = msg.sender == '👑 上帝';
                    final isNarrator = msg.sender == '📖 旁白';
                    final color = isGod
                        ? Colors.deepPurple
                        : isNarrator
                        ? Colors.brown
                        : Colors.grey;
                    return GestureDetector(
                      onLongPress: () => _showMessageMenu(i),
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Column(
                          crossAxisAlignment: isGod
                              ? CrossAxisAlignment.end
                              : CrossAxisAlignment.start,
                          children: [
                            if (!isGod)
                              Padding(
                                padding: const EdgeInsets.only(
                                  left: 12,
                                  bottom: 2,
                                ),
                                child: Text(
                                  msg.sender,
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                    color: color,
                                  ),
                                ),
                              ),
                            Row(
                              mainAxisAlignment: isGod
                                  ? MainAxisAlignment.end
                                  : MainAxisAlignment.start,
                              children: [
                                if (!isGod)
                                  Padding(
                                    padding: const EdgeInsets.only(right: 8),
                                    child: CircleAvatar(
                                      radius: 14,
                                      backgroundColor: color.withOpacity(0.2),
                                      child: Text(
                                        msg.sender[0],
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
                                      color: isGod
                                          ? Colors.deepPurple.shade100
                                          : color.withOpacity(0.1),
                                      border: Border.all(
                                        color: color.withOpacity(0.3),
                                      ),
                                      borderRadius: BorderRadius.only(
                                        topLeft: const Radius.circular(20),
                                        topRight: const Radius.circular(20),
                                        bottomLeft: isGod
                                            ? const Radius.circular(20)
                                            : Radius.zero,
                                        bottomRight: isGod
                                            ? Radius.zero
                                            : const Radius.circular(20),
                                      ),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black.withOpacity(0.05),
                                          blurRadius: 4,
                                          offset: const Offset(0, 2),
                                        ),
                                      ],
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        SelectableText(
                                          msg.text,
                                          style: const TextStyle(fontSize: 16),
                                        ),
                                        // 重试按钮：仅当系统错误且包含旁白失败时显示
                                        if (msg.sender == '系统' &&
                                            msg.text.contains('旁白生成失败'))
                                          Padding(
                                            padding: const EdgeInsets.only(
                                              top: 4,
                                            ),
                                            child: TextButton(
                                              onPressed: _triggerNarrator,
                                              child: const Text('点击重试'),
                                            ),
                                          ),
                                        if (msg.imageUrl != null)
                                          Padding(
                                            padding: const EdgeInsets.only(
                                              top: 8,
                                            ),
                                            child: ClipRRect(
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                              child: Image.file(
                                                File(msg.imageUrl!),
                                                width: 200,
                                                height: 200,
                                                fit: BoxFit.cover,
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                ),
                                if (isGod)
                                  Padding(
                                    padding: const EdgeInsets.only(left: 8),
                                    child: CircleAvatar(
                                      radius: 14,
                                      backgroundColor:
                                          Colors.deepPurple.shade100,
                                      child: const Text(
                                        '👑',
                                        style: TextStyle(fontSize: 14),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
                if (!_isNearBottom)
                  Positioned(
                    right: 16,
                    bottom: 16,
                    child: FloatingActionButton.small(
                      heroTag: 'novelScrollDown',
                      backgroundColor: Colors.brown,
                      onPressed: () {
                        _scrollToBottom();
                        setState(() => _isNearBottom = true);
                      },
                      child: const Icon(
                        Icons.keyboard_arrow_down,
                        color: Colors.white,
                      ),
                    ),
                  ),
              ],
            ),
          ),

          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              SmallButton(
                icon: Icons.auto_stories,
                label: '旁白',
                color: Colors.brown,
                onPressed: _isLoading ? null : _triggerNarrator,
              ),

              SmallButton(
                icon: Icons.summarize,
                label: '总结',
                color: Colors.teal,
                onPressed: _isLoading ? null : _generateSummary,
              ),
              SmallButton(
                icon: Icons.record_voice_over,
                label: '发言',
                color: const Color.fromARGB(255, 32, 13, 201),
                onPressed: _isLoading
                    ? null
                    : () => _characterSpeak(direct: true),
              ),
            ],
          ),
          Container(
            padding: const EdgeInsets.all(8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _textController,
                        focusNode: _textFocusNode,
                        minLines: 1,
                        maxLines: _isInputExpanded ? 6 : 1,
                        decoration: const InputDecoration(
                          hintText: '上帝指令...',
                          border: OutlineInputBorder(),
                        ),
                        onSubmitted: (_) => _sendGodCommand(),
                      ),
                    ),
                    IconButton(
                      icon: Icon(
                        _isInputExpanded
                            ? Icons.expand_less
                            : Icons.expand_more,
                      ),
                      tooltip: _isInputExpanded ? '收起' : '展开',
                      onPressed: () {
                        setState(() => _isInputExpanded = !_isInputExpanded);
                        if (_isInputExpanded) _textFocusNode.requestFocus();
                      },
                    ),
                    IconButton(
                      // 图片生成按钮（新增）
                      icon: const Icon(Icons.photo_library_outlined),
                      onPressed: _generateForLatestAi,
                    ),
                    IconButton(
                      icon: const Icon(Icons.send, color: Colors.brown),
                      onPressed: _sendGodCommand,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _editMessage(int index) {
    final msg = _messages[index];
    if (msg.sender != '👑 上帝') return;
    // 把原指令放回输入框
    _textController.text = msg.text.replaceFirst('上帝指令：', '').trim();
    _textController.selection = TextSelection.fromPosition(
      TextPosition(offset: _textController.text.length),
    );
    // 删除原消息
    setState(() => _messages.removeAt(index));
    _saveHistory();
    // 聚焦输入框
    _textFocusNode.requestFocus();
  }

  void _showMessageMenu(int index) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Wrap(
          children: [
            // 复制文本
            ListTile(
              leading: const Icon(Icons.copy),
              title: const Text('复制文本'),
              onTap: () {
                Navigator.pop(ctx);
                Clipboard.setData(ClipboardData(text: _messages[index].text));
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(const SnackBar(content: Text('已复制到剪贴板')));
              },
            ),
            // 编辑（仅上帝指令）
            if (_messages[index].sender == '👑 上帝')
              ListTile(
                leading: const Icon(Icons.edit),
                title: const Text('编辑'),
                onTap: () {
                  Navigator.pop(ctx);
                  _editMessage(index);
                },
              ),
            // 重新生成（仅旁白）
            if (_messages[index].sender == '📖 旁白')
              ListTile(
                leading: const Icon(Icons.refresh),
                title: const Text('重新生成'),
                onTap: () {
                  Navigator.pop(ctx);
                  _regenerateNarration(index);
                },
              ),
            // 加入记忆事件
            ListTile(
              leading: const Icon(Icons.memory),
              title: const Text('加入记忆事件'),
              onTap: () {
                Navigator.pop(ctx);
                _addToMemory(index);
              },
            ),
            // 删除消息
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

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
    _scrollController.removeListener(_onScroll);
    _textFocusNode.dispose();
  }
}
///////////////////////////////////
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
import 'novel_hub_page.dart';
// 用于 jsonDecode
import '../services/theme_provider.dart';
import '../services/ai_service.dart'; // AiService 类（如果已有则跳过）

class CharacterHubPage extends StatefulWidget {
  final ThemeProvider themeProvider;
  const CharacterHubPage({super.key, required this.themeProvider});

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
    final speakingCtrl = TextEditingController();
    final apiConfigs = await StorageService.loadChatApiConfigs();
    final labels = apiConfigs.map((c) => c['label']!).toList();
    String selectedModel = labels.isNotEmpty ? labels.first : '';
    String? generatedAvatarPath;

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
                  labelText: '外貌',
                  hintText: '例如：长发飘逸，大眼睛',
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
                const SizedBox(height: 12),
                AdaptiveTextField(
                  controller: speakingCtrl,
                  labelText: '说话风格',
                  hintText: '例如：古风、毒舌、话痨',
                  maxLines: 3,
                ),
                ElevatedButton.icon(
                  icon: const Icon(Icons.auto_fix_high),
                  label: const Text('AI 解析角色'),
                  onPressed: () async {
                    final textCtrl = TextEditingController();
                    final ok = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text('粘贴角色设定文本'),
                        content: TextField(
                          controller: textCtrl,
                          maxLines: 8,
                          decoration: const InputDecoration(
                            hintText: '例如：\n名字：艾莉丝\n性格：温柔善良...',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(ctx, false),
                            child: const Text('取消'),
                          ),
                          FilledButton(
                            onPressed: () => Navigator.pop(ctx, true),
                            child: const Text('解析'),
                          ),
                        ],
                      ),
                    );
                    if (ok == true && textCtrl.text.trim().isNotEmpty) {
                      // 动态获取可用模型标签（优先取第一个角色的模型，否则取设置中第一个API）
                      String modelLabel = 'deepseek'; // 最后的fallback
                      if (_characters.isNotEmpty) {
                        modelLabel = _characters.first.aiModel;
                      } else {
                        final configs =
                            await StorageService.loadChatApiConfigs();
                        if (configs.isNotEmpty) {
                          modelLabel = configs.first['label']!;
                        }
                      }
                      final parsed = await AiService.parseCharacterText(
                        textCtrl.text.trim(),
                        modelLabel: modelLabel,
                      );
                      if (parsed != null) {
                        setDialogState(() {
                          nameController.text = parsed['name'] ?? '';
                          personalityController.text =
                              parsed['personality'] ?? '';
                          attireController.text = parsed['attire'] ?? '';
                          backgroundController.text =
                              parsed['background'] ?? '';
                          catchphraseController.text =
                              parsed['catchphrase'] ?? '';
                          likesController.text = parsed['likes'] ?? '';
                          dislikesController.text = parsed['dislikes'] ?? '';
                          speakingCtrl.text = parsed['speakingStyle'] ?? '';
                        });
                      }
                    }
                  },
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: selectedModel,
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
                        generatedAvatarPath = avatarPath;
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
                    speakingStyle: speakingCtrl.text.trim(),
                    avatarPath: generatedAvatarPath ?? '',
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
              builder: (context) => ChatPage(
                characters: [character],
                sessionId: sessionId,
                themeProvider: widget.themeProvider,
              ),
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
                archiveName: archive['name'],
                themeProvider: widget.themeProvider,
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
      appBar: AppBar(title: const Text('角色中心'), centerTitle: true),
      body: _characters.isEmpty && _archives.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.people_outline,
                    size: 80,
                    color: Colors.grey.shade400,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '还没有角色',
                    style: TextStyle(fontSize: 18, color: Colors.grey.shade600),
                  ),
                  const SizedBox(height: 8),
                  ElevatedButton.icon(
                    onPressed: _showCreateCharacterDialog,
                    icon: const Icon(Icons.add),
                    label: const Text('创建角色'),
                  ),
                ],
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
////////////////////////////
novel_hub_page.dart
import 'package:flutter/material.dart';
import '../models/novel_project.dart';
import '../services/novel_storage_service.dart';
import 'novel_chat_page.dart';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/character.dart';

class NovelHubPage extends StatefulWidget {
  const NovelHubPage({super.key});

  @override
  State<NovelHubPage> createState() => _NovelHubPageState();
}

class _NovelHubPageState extends State<NovelHubPage> {
  List<NovelProject> _projects = [];
  Map<String, List<Map<String, String>>> _projectSaves = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final projects = await NovelStorageService.loadProjects();
    final savesMap = <String, List<Map<String, String>>>{};
    for (final p in projects) {
      savesMap[p.id] = await NovelStorageService.loadSaveInfos(p.id);
    }
    setState(() {
      _projects = projects;
      _projectSaves = savesMap;
    });
  }

  void _createProject() async {
    final nameCtrl = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('创建小说'),
        content: TextField(
          controller: nameCtrl,
          decoration: const InputDecoration(hintText: '小说名称'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, nameCtrl.text.trim()),
            child: const Text('创建'),
          ),
        ],
      ),
    );
    if (name != null && name.isNotEmpty) {
      final project = NovelProject(title: name);
      _projects.add(project);
      await NovelStorageService.saveProjects(_projects);
      _load();
      // 直接进入小说
      await Navigator.push(
        // ← 原来没 await
        context,
        MaterialPageRoute(builder: (_) => NovelChatPage(project: project)),
      );
      _load();
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => NovelChatPage(project: project)),
      );
    }
  }

  void _deleteProject(NovelProject project) async {
    final saves = _projectSaves[project.id] ?? [];

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除小说'),
        content: Text(
          '确定要删除“${project.title}”吗？\n'
          '${saves.isNotEmpty ? "该小说的 ${saves.length} 个存档将转为独立小说。" : ""}',
        ),
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
    if (confirm != true) return;

    // 迁移每个存档为独立项目
    for (final save in saves) {
      final newTitle = '${project.title}-${save['name']}'; // 本体名-存档名
      final newProject = NovelProject(
        title: newTitle,
        characters: List<Character>.from(project.characters),
        worldSetting: project.worldSetting,
        narratorPrompt: project.narratorPrompt,
        narratorModelLabel: project.narratorModelLabel,
        // 注意：newProject.id 默认为时间戳，后续我们会使用迁移后的项目id来存储消息
      );
      // 保存新项目（先加入项目列表，后续迁移数据时用到 newProject.id）
      // 但我们还没保存到存储，为了后面迁移时能获取 id，需要先保存项目列表
      // 临时添加，等迁移完成后再正式保存
      _projects.add(newProject);
      // 迁移存档数据到新项目本体
      await NovelStorageService.migrateSaveToProject(
        save['id']!,
        newProject.id,
      );
      // 从原项目的存档列表中删除该存档 id（已经迁移，不再需要）
      // 注意：原项目的存档列表将在删除本体时被清除，这里可暂时忽略
    }

    // 从列表中移除本体
    _projects.removeWhere((p) => p.id == project.id);
    // 保存项目列表
    await NovelStorageService.saveProjects(_projects);
    // 删除原项目的所有数据（消息、记忆、token等）
    await NovelStorageService.deleteProjectData(project.id);

    _load(); // 重新加载界面
  }

  Future<void> _showSaveList(NovelProject project) async {
    final saveIds = await NovelStorageService.loadSaveIds(project.id);
    if (saveIds.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('暂无存档')));
      return;
    }
    // 加载所有存档名称
    final saves = <Map<String, String>>[];
    for (final id in saveIds) {
      // 我们需要一个快速获取存档名称的方法，这里简单从 SharedPreferences 读取
      final prefs = await SharedPreferences.getInstance();
      final dataStr = prefs.getString('novel_save_data_$id');
      if (dataStr != null) {
        final data = jsonDecode(dataStr);
        saves.add({'id': id, 'name': data['name'] ?? '未命名'});
      }
    }
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('选择存档'),
        content: SizedBox(
          height: 200,
          child: ListView.builder(
            itemCount: saves.length,
            itemBuilder: (_, i) => ListTile(
              title: Text(saves[i]['name']!),
              onTap: () async {
                Navigator.pop(ctx);
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => NovelChatPage(
                      project: project,
                      saveId: saves[i]['id'],
                      archiveName: saves[i]['name'], // 正确位置
                    ),
                  ),
                );
                _load(); // 返回后刷新
              },
              trailing: IconButton(
                icon: const Icon(Icons.delete, color: Colors.red),
                onPressed: () async {
                  await NovelStorageService.deleteSave(
                    project.id,
                    saves[i]['id']!,
                  );
                  Navigator.pop(ctx);
                  _load();
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  // 小说本体卡片（占满整行）
  Widget _buildNovelCard(NovelProject project) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 3,
      color: Colors.orange.shade50,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => NovelChatPage(project: project)),
          );
          _load();
        },
        onLongPress: () => _deleteProject(project),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                project.title,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 16,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.people, size: 16, color: Colors.grey),
                      const SizedBox(width: 4),
                      Text('${project.characters.length} 个角色'),
                    ],
                  ),
                  if (_projectSaves[project.id]?.isNotEmpty == true)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.save, size: 16, color: Colors.grey),
                        const SizedBox(width: 4),
                        Text('${_projectSaves[project.id]!.length} 个存档'),
                      ],
                    ),
                ],
              ),
              if (project.worldSetting.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  project.worldSetting,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13, color: Colors.grey),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // 存档卡片（占满整行，稍有缩进效果，颜色不同）
  Widget _buildSaveCard(NovelProject project, Map<String, String> save) {
    return Padding(
      padding: const EdgeInsets.only(left: 24, bottom: 8),
      child: Card(
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        elevation: 1,
        color: Colors.grey.shade100,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () async {
            await Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => NovelChatPage(
                  project: project,
                  saveId: save['id']!,
                  archiveName: save['name'],
                ),
              ),
            );
            _load();
          },
          onLongPress: () async {
            final confirm = await showDialog<bool>(
              context: context,
              builder: (ctx) => AlertDialog(
                title: const Text('删除存档'),
                content: Text('确定要删除存档“${save['name']}”吗？'),
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
              await NovelStorageService.deleteSave(project.id, save['id']!);
              _load();
            }
          },
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                const Icon(Icons.bookmark, color: Colors.brown, size: 18),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    save['name']!,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                const Icon(Icons.chevron_right, color: Colors.grey),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('小说工坊'), centerTitle: true),
      body: _projects.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.book_outlined,
                    size: 80,
                    color: Colors.grey.shade400,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '还没有小说',
                    style: TextStyle(fontSize: 18, color: Colors.grey.shade600),
                  ),
                  const SizedBox(height: 8),
                  ElevatedButton.icon(
                    onPressed: _createProject,
                    icon: const Icon(Icons.add),
                    label: const Text('创建小说'),
                  ),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _projects.length,
              itemBuilder: (_, i) {
                final project = _projects[i];
                final saves = _projectSaves[project.id] ?? [];
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // 小说本体卡片（占满整行）
                    _buildNovelCard(project),
                    // 每个存档各占一行
                    ...saves.map((save) => _buildSaveCard(project, save)),
                    const SizedBox(height: 12),
                  ],
                );
              },
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: _createProject,
        child: const Icon(Icons.add),
      ),
    );
  }
}
///////////////////////////
main.dart
import 'package:flutter/material.dart';
import 'screens/home_page.dart'; // 新主页
import 'services/theme_provider.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  final ThemeProvider themeProvider = ThemeProvider();

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: themeProvider,
      builder: (context, _) {
        return MaterialApp(
          title: '角色聊天室',
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            colorScheme: ColorScheme.fromSeed(
              seedColor: themeProvider.seedColor,
            ),
            useMaterial3: true,
            cardTheme: CardThemeData(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              elevation: 2,
            ),
            dialogTheme: DialogThemeData(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              titleTextStyle: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: ColorScheme.fromSeed(
                  seedColor: themeProvider.seedColor,
                ).primary,
              ),
            ),
            inputDecorationTheme: InputDecorationTheme(
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          home: HomePage(themeProvider: themeProvider),
        );
      },
    );
  }
}
//////////////////////////////////
home_page.dart
import 'package:flutter/material.dart';
import '../services/theme_provider.dart';
import 'character_hub_page.dart';
import 'novel_hub_page.dart';
import 'gallery_page.dart';
import 'settings_page.dart';

class HomePage extends StatefulWidget {
  final ThemeProvider themeProvider;
  const HomePage({super.key, required this.themeProvider});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _currentIndex = 0;

  final List<Widget> _pages = [];

  @override
  void initState() {
    super.initState();
    _pages.addAll([
      CharacterHubPage(themeProvider: widget.themeProvider),
      const NovelHubPage(),
      const GalleryPage(),
      SettingsPage(themeProvider: widget.themeProvider),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _currentIndex, children: _pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (index) => setState(() => _currentIndex = index),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.chat), label: '聊天'),
          NavigationDestination(icon: Icon(Icons.book), label: '小说'),
          NavigationDestination(icon: Icon(Icons.photo_library), label: '图库'),
          NavigationDestination(icon: Icon(Icons.settings), label: '设置'),
        ],
      ),
    );
  }
}
////////////////////////////////
theme_provider.dart
import 'package:flutter/material.dart';

class ThemeProvider extends ChangeNotifier {
  Color _seedColor = Colors.deepPurple; // 默认主色
  Color get seedColor => _seedColor;

  void setSeedColor(Color color) {
    _seedColor = color;
    notifyListeners();
  }
}
