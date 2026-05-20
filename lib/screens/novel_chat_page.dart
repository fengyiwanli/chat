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

import '../widgets/chat_message_bubble.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../utils/app_dialogs.dart';
import '../utils/app_snackbars.dart';
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
  // 是否已完成数据加载
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
  bool _autoSummaryEnabled = false;
  int _autoSummaryThreshold = 20;
  int _maxMemoryCount = 5;
  int _messagesSinceLastSummary = 0;
  bool _pendingSystemUpdate = false;
  String _summaryPrompt = ''; // 当前小说的总结提示词，空表示用全局
  List<Map<String, String>> _customStyles = [];
  String _currentStyleId = 'normal';
  // 支线相关变量已在聊天室用过，小说页面添加：
   
    
  static const _novelMemoryPrefix = 'novel_memory_';

  // ───── 发送者常量 ─────
  static const _godSender = '👑 上帝';
  static const _narratorSender = '📖 旁白';
  static const _systemSender = '系统';

  // ───── 快速操作按钮配置 ─────
  static const _quickActions = [
    _QuickActionData(Icons.auto_stories, '旁白', Colors.brown, 'narrator'),
    _QuickActionData(Icons.summarize, '总结', Colors.teal, 'summary'),
    _QuickActionData(Icons.record_voice_over, '发言', Color(0xFF200DC9), 'speak'),
  ];
  void _insertSystemNotification(String content) {
    setState(() {
      _messages.add(
        ChatMessage(text: '【系统提示】$content', isUser: false, sender: _systemSender),
      );
      _pendingSystemUpdate = true;
    });
    _saveHistory();
  }

  static const String _defaultNarratorPrompt = '''
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
 

  
  Future<void> _autoGenerateMemorySummary() async {
    if (_isLoading) return;
    await _generateSummary();
    _messagesSinceLastSummary = 0;
    _trimMemoryEvents();
  }

  Future<void> _trimMemoryEvents() async {
    if (_memoryEvents.length > _maxMemoryCount) {
      _memoryEvents = _memoryEvents.sublist(
        _memoryEvents.length - _maxMemoryCount,
      );
      await NovelStorageService.saveMemoryEvents(_project.id, _memoryEvents);
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

  Widget _buildDrawerSection(
    BuildContext context, {
    required IconData icon,
    required String title,
    required List<Widget> children,
  }) {
    return ExpansionTile(
      leading: Icon(icon),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
      initiallyExpanded: false,
      children: children,
        );
  }

  Widget _buildDrawerTile(IconData icon, String title, VoidCallback onTap) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      onTap: () {
        Navigator.pop(context);
        onTap();
      },
        );
  }

    Widget _buildMessageAvatar(ChatMessage msg, Color color) {
    final senderChar = _project.characters
        .firstWhere(
          (c) => c.name == msg.sender,
          orElse: () => Character(
            name: '',
            personality: '',
            attire: '',
          ),
        );
    final avatarPath = senderChar.avatarPath;
    final hasAvatar = avatarPath.isNotEmpty &&
        File(avatarPath).existsSync();
    return CircleAvatar(
      radius: 14,
      backgroundColor: hasAvatar ? null : color.withOpacity(0.2),
      backgroundImage: hasAvatar ? FileImage(File(avatarPath)) : null,
      child: hasAvatar
          ? null
          : Text(
              msg.sender[0],
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.bold,
              ),
            ),
    );
  }

  Future<Character?> _showCharacterDialog({
    required String title,
    required String submitLabel,
    required Character? initial,
  }) async {
    final nameCtrl = TextEditingController(text: initial?.name ?? '');
    final persCtrl = TextEditingController(text: initial?.personality ?? '');
    final attireCtrl = TextEditingController(text: initial?.attire ?? '');
    final bgCtrl = TextEditingController(text: initial?.background ?? '');
    final catchCtrl = TextEditingController(text: initial?.catchphrase ?? '');
    final likesCtrl = TextEditingController(text: initial?.likes ?? '');
    final dislikesCtrl = TextEditingController(text: initial?.dislikes ?? '');
    final speakingCtrl = TextEditingController(text: initial?.speakingStyle ?? '');
    final configs = await StorageService.loadChatApiConfigs();
    final labels = configs.map((c) => c['label']!).toList();
    String selModel = initial?.aiModel ?? (labels.isNotEmpty ? labels.first : '');
    if (!labels.contains(selModel)) {
      selModel = labels.isNotEmpty ? labels.first : '';
    }

    final result = await showDialog<Character>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(title),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton.icon(
                      icon: const Icon(Icons.paste),
                      label: const Text('从剪贴板导入'),
                      onPressed: () async {
                        final data = await Clipboard.getData(Clipboard.kTextPlain);
                        if (data == null || data.text == null || data.text!.isEmpty) return;
                        try {
                          final json = jsonDecode(data.text!) as Map<String, dynamic>;
                          final c = Character.fromJson(json);
                          setDialogState(() {
                            nameCtrl.text = c.name;
                            persCtrl.text = c.personality;
                            attireCtrl.text = c.attire;
                            bgCtrl.text = c.background;
                            catchCtrl.text = c.catchphrase;
                            likesCtrl.text = c.likes;
                            dislikesCtrl.text = c.dislikes;
                            speakingCtrl.text = c.speakingStyle;
                          });
                        } catch (_) {}
                      },
                    ),
                  ],
                ),
                TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: '名字')),
                const SizedBox(height: 8),
                TextField(controller: persCtrl, decoration: const InputDecoration(labelText: '性格'), maxLines: 2),
                const SizedBox(height: 8),
                TextField(controller: attireCtrl, decoration: const InputDecoration(labelText: '着装'), maxLines: 2),
                const SizedBox(height: 8),
                TextField(controller: bgCtrl, decoration: const InputDecoration(labelText: '背景故事'), maxLines: 3),
                const SizedBox(height: 8),
                TextField(controller: catchCtrl, decoration: const InputDecoration(labelText: '外貌'), maxLines: 2),
                const SizedBox(height: 8),
                TextField(controller: likesCtrl, decoration: const InputDecoration(labelText: '喜好'), maxLines: 2),
                const SizedBox(height: 8),
                TextField(controller: dislikesCtrl, decoration: const InputDecoration(labelText: '厌恶'), maxLines: 2),
                const SizedBox(height: 8),
                TextField(
                  controller: speakingCtrl,
                  decoration: const InputDecoration(labelText: '说话风格', hintText: '例：古风、毒舌、话痨...'),
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
                        content: TextField(controller: textCtrl, maxLines: 8, decoration: const InputDecoration(hintText: '粘贴文本...', border: OutlineInputBorder())),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
                          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('解析')),
                        ],
                      ),
                    );
                    if (ok == true && textCtrl.text.trim().isNotEmpty) {
                      final parsed = await AiService.parseCharacterText(
                        textCtrl.text.trim(),
                        modelLabel: _project.narratorModelLabel.isNotEmpty ? _project.narratorModelLabel : 'deepseek',
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
                  items: labels.map((l) => DropdownMenuItem(value: l, child: Text(l))).toList(),
                  onChanged: (v) => setDialogState(() => selModel = v!),
                  decoration: const InputDecoration(labelText: '模型'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
            FilledButton(
              onPressed: () {
                if (nameCtrl.text.trim().isEmpty) return;
                Navigator.pop(
                  ctx,
                  Character(
                    id: initial?.id ?? '',
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
              child: Text(submitLabel),
            ),
          ],
        ),
      ),
    );
    return result;
  }

  void _characterSpeak({bool direct = false}) async {
    if (_project.characters.isEmpty) return;

    // 弹出选项面板
    final result = await showModalBottomSheet<CharacterSpeakConfig?>(
      context: context,
      builder: (ctx) => _CharacterSpeakSheet(
        characters: _project.characters,
        selectedCharacter: _selectedSpeakCharacter,
      ),
    );

    if (result == null) return;

    final char = result.character;
    final customText = result.text;

    setState(() => _isLoading = true);
    try {
      String? responseText;
      if (customText != null && customText.trim().isNotEmpty) {
        // 使用用户输入的自定义台词
        responseText = customText.trim();
      } else {
        // AI 生成发言
        final systemPrompt =
            '你扮演${char.name}，性格：${char.personality}。初始着装：${char.attire.isEmpty ? "未指定" : char.attire}。外貌：${char.catchphrase.isEmpty ? "未指定" : char.catchphrase}。背景：${char.background.isEmpty ? "未指定" : char.background}。说话风格：${char.speakingStyle.isEmpty ? "未指定" : char.speakingStyle}。\n'
            '请在当前故事背景下说一句符合性格的、推动剧情的话。同时，每次回复时，先简短描述你当前的穿着和外表，放在()里。直接输出对话。';
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
              'content': '当前上下文：\n$contextStr\n\n请${char.name}发言：',
            },
          ],
        );
        responseText = resp.content;
        _addTokens(resp);
      }

      setState(() {
        _messages.add(
          ChatMessage(text: responseText!, isUser: false, sender: char.name),
        );
        _isLoading = false;
      });
      _saveHistory();
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        AppSnackbars.showError(context, '角色发言失败: $e');
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
  // 👇👇👇 改成这样，用我们刚写的方法
  _textFocusNode.addListener(_onFocusChange);
  _scrollController.addListener(_onScroll); // 原来的滚动监听也改成这样
  _loadMessages();
}
// 👇👇👇 把这段代码粘贴到 initState 下面
void _onFocusChange() {
  if (_textFocusNode.hasFocus) {
    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted) _scrollToBottom();
    });
  }
}

// 👇👇👇 再添加滚动监听的方法
void _onScroll() {
  if (!_scrollController.hasClients) return;
  final maxScroll = _scrollController.position.maxScrollExtent;
  final currentScroll = _scrollController.position.pixels;
  final isNearBottom = (maxScroll - currentScroll) <= 100.0;
  if (_isNearBottom != isNearBottom) {
    setState(() => _isNearBottom = isNearBottom);
  }
}

  
Future<void> _loadMessages() async {
    // 从本地存储加载当前小说项目的聊天记录
    final history = await NovelStorageService.loadMessages(widget.project.id);
    setState(() {
      _messages.addAll(history);
    });
    // 加载完数据后，滚动到底部
    if (mounted) _scrollToBottom();
  }
  Future<void> _loadAllData() async {
  // 👇👇👇 第一阶段：并行加载所有不相关的独立数据（同时执行，速度最快）
  await Future.wait([
    _loadCustomStyles(), // 加载自定义风格
    _loadAutoSummarySettings(), // 加载自动摘要设置
    _loadImageModifiers(), // 加载图片修饰词
    _loadContextLength(), // 加载上下文长度
    _loadSummaryPrompt(), // 加载总结提示词
  ]);

  // 👇👇👇 第二阶段：加载当前风格ID（依赖上面的SharedPreferences）
  final prefs = await SharedPreferences.getInstance();
  _currentStyleId = prefs.getString('novel_reply_style_${_project.id}') ?? 'normal';

  // 👇👇👇 第三阶段：加载消息历史（必须单独执行，因为数据量大）
  if (widget.saveId != null) {
    await _loadSaveHistory(widget.saveId!);
  } else {
    await _loadHistory();
  }

  // 👇👇👇 第四阶段：加载依赖消息历史的数据
  final lastSummaryIndex = await NovelStorageService.loadSummaryIndex(_project.id);
  _messagesSinceLastSummary = (_messages.length - lastSummaryIndex).clamp(0, _messages.length);
  
  await _loadMemoryEvents(); // 加载记忆事件

  // 👇👇👇 第五阶段：最后加载剩余数据
  if (_project.narratorModelLabel.isEmpty) {
    await _loadDefaultModel();
  }

  _autoSelectSpeakCharacter();
}

// 👇👇👇 把原来分散的加载逻辑提取成独立的小方法（方便并行调用）
Future<void> _loadCustomStyles() async {
  _customStyles = await StorageService.loadCustomStyles();
}

Future<void> _loadAutoSummarySettings() async {
  _autoSummaryEnabled = await NovelStorageService.loadAutoSummaryEnabled(_project.id);
  _autoSummaryThreshold = await NovelStorageService.loadAutoSummaryThreshold(_project.id);
  _maxMemoryCount = await NovelStorageService.loadMaxMemoryCount(_project.id);
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

  Future<void> _createNovelBranch() async {
    final nameCtrl = TextEditingController();
    // 替换后的代码
final name = await AppDialogs.showInputDialog(
  context,
  title: '创建支线',
  hintText: '输入支线名称',
  confirmText: '创建',
);
   
   
    if (name == null || name.isEmpty) return;

    // 保存当前项目为存档，并记录为分支
    await NovelStorageService.createSave(
      _project.id,
      name,
      _messages,
      _memoryEvents,
      _cumulativeTokens,
    );
    // 提示
    if (mounted) {
      AppSnackbars.showSuccess(context, '支线“$name”已创建');
    }
  }

  Future<void> _showNovelBranchManager() async {
    final saves = await NovelStorageService.loadSaveInfos(_project.id);
    final branches = saves;

    showDialog(
      context: context,
      builder: (dialogCtx) => SimpleDialog(
        // ← 改这里
        title: const Text('支线管理'),
        children: [
          ListTile(
            title: const Text('主线'),
            subtitle: const Text('当前创作主线'),
            onTap: () {
              Navigator.pop(dialogCtx); // ← 改这里
            },
          ),
          ...branches.map(
            (branch) => ListTile(
              title: Text(branch['name'] ?? '未命名'),
              subtitle: Text(branch['id'] ?? ''),
              trailing: IconButton(
                icon: const Icon(Icons.delete, color: Colors.red),
                onPressed: () async {
                  final confirm = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      // 这里内部可以用 ctx，不会冲突
                      title: const Text('删除支线'),
                      content: Text('确定删除“${branch['name']}”吗？'),
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
                    await NovelStorageService.deleteSave(
                      _project.id,
                      branch['id']!,
                    );
                    Navigator.pop(dialogCtx); // ← 改这里
                    _showNovelBranchManager();
                  }
                },
              ),
              onTap: () {
                Navigator.pop(dialogCtx); // ← 改这里
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(
                    builder: (_) => NovelChatPage(
                      project: _project,
                      saveId: branch['id'],
                      archiveName: branch['name'],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
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
                // StorageService.addGalleryPath(localPath);///自动保存到图库
      } else {
        throw Exception('图片生成返回空结果');
      }
    } catch (e) {
      setState(() => message.isGeneratingImage = false);
      if (mounted) {
        AppSnackbars.showInfo(context, '图片生成失败: $e');
      }
    }
  }

  void _generateForLatestAi() {
    for (int i = _messages.length - 1; i >= 0; i--) {
      final msg = _messages[i];
      if (msg.sender == _narratorSender &&
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

  String _sanitizeText(String text) {
    // 移除非法 UTF-16 字符，防止渲染崩溃
    return text.replaceAll(RegExp(r'[\uD800-\uDFFF]'), '');
  }

  static String _sanitizeUtf16(String input) {
    if (input.isEmpty) return input;
    return input.replaceAllMapped(
      RegExp(r'([\uD800-\uDBFF][\uDC00-\uDFFF])|[\uD800-\uDFFF]'),
      (match) => match.group(1) != null ? match.group(1)! : '',
    );
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
    AppSnackbars.showSuccess(context, '已保存为记忆事件');
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
      final eventContent = aiResponse.content.trim();

      // 弹出确认框
      if (mounted) {
        final apply = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('随机事件'),
            content: SingleChildScrollView(child: SelectableText(eventContent)),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('应用事件'),
              ),
            ],
          ),
        );
        if (apply == true) {
          setState(() {
            _messages.add(
              ChatMessage(
                text: '⚡ 随机事件：$eventContent',
                isUser: true,
                sender: '👑 上帝',
              ),
            );
            _isLoading = false;
          });
          _saveHistory();
        } else {
          setState(() => _isLoading = false);
        }
      }
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        AppSnackbars.showError(context, '随机事件失败: $e');
      }
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
      // 应用自定义旁白风格
      if (_currentStyleId != 'normal') {
        final style = _customStyles.firstWhere(
          (s) => s['id'] == _currentStyleId,
          orElse: () => <String, String>{},
        );
        final customPrompt = style['prompt'] ?? '';
        if (customPrompt.isNotEmpty) {
          fullSystemPrompt += '\n\n【你必须严格按照以下自定义风格进行旁白创作】\n$customPrompt';
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
                if (msg.sender == _godSender) {
          messages.add({'role': 'user', 'content': msg.text});
        } else if (msg.sender == _narratorSender) {
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
      _messagesSinceLastSummary++; // 新旁白算一条消息
      if (_autoSummaryEnabled &&
          _messagesSinceLastSummary >= _autoSummaryThreshold) {
        _autoGenerateMemorySummary();
      }
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
        if (_messages[i].sender == _narratorSender) newNarrations.add(_messages[i]);
      }
      if (newNarrations.isEmpty) {
        setState(() => _isLoading = false);
        AppSnackbars.showInfo(context, '没有新的旁白内容需要总结');
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
      Future<void> trimMemoryEventsIfNeeded() async {
        if (_memoryEvents.length > _maxMemoryCount) {
          _memoryEvents = _memoryEvents.sublist(
            _memoryEvents.length - _maxMemoryCount,
          );
          if (widget.saveId == null) {
            await NovelStorageService.saveMemoryEvents(
              _project.id,
              _memoryEvents,
            );
          }
        }
      }

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
      // 同时将摘要加入记忆事件
      _memoryEvents.add(aiResponse.content);
      if (widget.saveId == null) {
        await NovelStorageService.addMemoryEvent(
          _project.id,
          aiResponse.content,
        );
      } else {
        // 存档模式下记忆事件通过 _saveHistory 保存，但我们需要立即写回存档数据
        _saveHistory(); // 已经会调用 _saveHistory，这里可省略重复，但为了安全可以再调一次
      }
      // 限制记忆数量
      await trimMemoryEventsIfNeeded();
    } catch (e) {
      setState(() => _isLoading = false);
      AppSnackbars.showError(context, '摘要失败: $e');
    }
  }

  Future<void> _exportNovel() async {
    final buffer = StringBuffer();
    for (final msg in _messages) {
      if (msg.isUser) {
        buffer.writeln('${msg.sender}：${msg.text}');
      } else if (msg.sender == _systemSender) {
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
        AppSnackbars.showError(context, '导出失败: $e');
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
    // 替换后的代码
final String? name = await AppDialogs.showInputDialog(
  context,
  title: '保存存档',
  hintText: '存档名称...',
  confirmText: '保存',
);
    
    
    if (name != null && name.isNotEmpty) {
      await NovelStorageService.createSave(
        _project.id,
        name,
        _messages,
        _memoryEvents,
        _cumulativeTokens,
      );
      AppSnackbars.showSuccess(context, '存档已保存');
    }
  }

  void _selectNarratorModel() async {
    final configs = await StorageService.loadChatApiConfigs();
    if (configs.isEmpty) {
      AppSnackbars.showError(context, '请先添加对话 API');
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
    final result = await _showCharacterDialog(
      title: '添加角色',
      submitLabel: '添加',
      initial: null,
    );
    if (result != null) {
      setState(() => _project.characters.add(result));
      await NovelStorageService.updateProject(_project);
      _insertSystemNotification('新角色"\"加入');
      await NovelStorageService.updateProject(_project);
      _autoSelectSpeakCharacter();
    }
  }
  Future<void> _editCharacter(Character character) async {
    final result = await _showCharacterDialog(
      title: '编辑角色',
      submitLabel: '保存',
      initial: character,
    );
    if (result != null) {
      setState(() {
        final idx = _project.characters.indexWhere((c) => c.id == result.id);
        if (idx != -1) _project.characters[idx] = result;
      });
      await NovelStorageService.updateProject(_project);
      _insertSystemNotification('角色"\"设定已更新');
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
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.archiveName ?? _project.title),
        actions: [
          IconButton(
            icon: const Icon(Icons.smart_toy),
            tooltip: '旁白模型',
            onPressed: _selectNarratorModel,
          ),
          // 角色切换改为弹出菜单
          if (_project.characters.isNotEmpty)
            PopupMenuButton<Character>(
              icon: const Icon(Icons.people, color: Color.fromARGB(255, 56, 9, 223)),
              tooltip: '发言角色',
              itemBuilder: (_) => _project.characters
                  .map(
                    (c) =>
                        PopupMenuItem<Character>(value: c, child: Text(c.name)),
                  )
                  .toList(),
              onSelected: (c) => setState(() => _selectedSpeakCharacter = c),
            ),
          Builder(
            builder: (context) => IconButton(
              icon: const Icon(Icons.menu),
              tooltip: '更多功能',
              onPressed: () => Scaffold.of(context).openEndDrawer(),
            ),
          ),
        ],
      ),
      
      
      endDrawer: 
      _buildEndDrawer(context),
      // ... 下面的 body 不变
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 12),
            color: Theme.of(context).brightness == Brightness.dark
        ? const Color(0xFF1E1E1E)
        : Colors.white,
            child: Text(
              '本次：$_lastTotalTokens tokens | 累计：$_cumulativeTokens tokens',
              style: const TextStyle(fontSize: 12),
            ),
          ),
          if (_project.characters.isNotEmpty)
            Container(
              height: 40,
              color: Theme.of(context).brightness == Brightness.dark
        ? const Color(0xFF1E1E1E)
        : Colors.white,
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
                  itemBuilder: (context, i) {
                    // 1. 渲染底部加载指示器（思考中/旁白生成中）
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

                    // 2. 提取当前消息与角色身份
                    final msg = _messages[i];
                    final isGod = msg.sender == _godSender; // 小说界面的用户/上帝
                    final isNarrator = msg.sender == _narratorSender;
                    
                    final color = isGod
    ? (Theme.of(context).brightness == Brightness.dark
        ? const Color(0xFF2D2D2D) // 深色模式
        : const Color.fromARGB(255, 5, 243, 25))            // 浅色模式
    : isNarrator
    ? Colors.brown
    : const Color.fromARGB(255, 0, 0, 0);
                    // 3. 匹配当前发话角色获取头像（如果该角色存在于项目中）
                    final senderChar = _project.characters
                        .where((c) => c.name == msg.sender)
                        .firstOrNull;

                    // 4. 处理系统报错的重试按钮
                    Widget? retryWidget;
                    if (msg.sender == _systemSender && msg.text.contains('旁白生成失败')) {
                      retryWidget = Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: TextButton(
                          onPressed: _triggerNarrator,
                          child: const Text('点击重试'),
                        ),
                      );
                    }

                    // 5. 调用统一的消息气泡组件
                    return ChatMessageBubble(
                      message: msg,
                      isMe: isGod, // 上帝视角的发言放在右侧
                      isNarration: isNarrator,
                      color: color,
                      userName: '👑', // 原本代码里上帝的头像是皇冠，这里直接传给组件
                      avatarPath: senderChar?.avatarPath, // 自动继承 ResizeImage 内存压缩！
                      statusWidget: retryWidget, // 巧妙利用 statusWidget 插槽放重试按钮
                      onLongPressMessage: () => _showMessageMenu(i),
                      
                      // 图片点击全屏放大功能
                      onImageTap: msg.imageUrl != null ? () {
                        showDialog(
                          context: context,
                          builder: (_) => Dialog(
                            backgroundColor: Colors.transparent,
                            child: GestureDetector(
                              onTap: () => Navigator.pop(context),
                              child: InteractiveViewer(
                                child: msg.imageUrl!.startsWith('http')
                                    ? CachedNetworkImage(
                                        imageUrl: msg.imageUrl!, 
                                        fit: BoxFit.contain,
                                      )
                                    : // 优化后的代码（聊天气泡里的图片最大宽度350像素）
Image.file(
  File(msg.imageUrl!),
  fit: BoxFit.contain,
  cacheWidth: 350, // 缓存宽度350像素（足够手机屏幕显示）
),
                              ),
                            ),
                          ),
                        );
                      } : null,
                    );
                  },
                ),
                // --- 滚动到底部的悬浮按钮保持不变 ---
                if (!_isNearBottom)
                  Positioned(
                    right: 16,
                    bottom: 16,
                    child: FloatingActionButton.small(
                      heroTag: 'chatScrollDown',
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
               
               
                if (!_isNearBottom)
                  Positioned(
                    right: 16,
                    bottom: 16,
                    child: FloatingActionButton.small(
                      heroTag: 'chatScrollDown',
                      backgroundColor: Colors.brown,
                      onPressed: () {
                        _scrollToBottom();
                        setState(() => _isNearBottom = true);
                      },
                      child: const Icon(
                        Icons.keyboard_arrow_down,
                        color: Color.fromARGB(255, 4, 66, 236),
                      ),
                    ),
                  ),
              
              
              ],
            ),
          ),

                    Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: _quickActions.map((qa) {
              VoidCallback? onPressed;
              switch (qa.action) {
                case 'narrator':
                  onPressed = _isLoading ? null : _triggerNarrator;
                  break;
                case 'summary':
                  onPressed = _isLoading ? null : _generateSummary;
                  break;
                case 'speak':
                  onPressed = _isLoading
                      ? null
                      : () => _characterSpeak(direct: true);
                  break;
              }
              return SmallButton(
                icon: qa.icon,
                label: qa.label,
                color: qa.color,
                onPressed: onPressed,
              );
            }).toList(),
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

  Drawer _buildEndDrawer(BuildContext context) {
    return Drawer(
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(vertical: 8),
          children: [
            // ───── 基础设置 ─────
            _buildDrawerSection(
              context,
              icon: Icons.settings,
              title: '基础设置',
              children: [
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
                ListTile(
                  leading: const Icon(Icons.style),
                  title: const Text('旁白风格'),
                  subtitle: Text(
                    _currentStyleId == 'normal'
                        ? '默认'
                        : (_customStyles.any(
                                (s) => s['id'] == _currentStyleId,
                              )
                              ? (_customStyles.firstWhere(
                                      (s) => s['id'] == _currentStyleId,
                                    )['name'] ??
                                    '未命名')
                              : '未命名'),
                  ),
                  onTap: () async {
                    Navigator.pop(context);
                    final selected = await showDialog<String>(
                      context: context,
                      builder: (ctx) => SimpleDialog(
                        title: const Text('选择旁白风格'),
                        children: [
                          RadioListTile<String>(
                            title: const Text('默认'),
                            subtitle: const Text('使用系统旁白提示词'),
                            value: 'normal',
                            groupValue: _currentStyleId,
                            onChanged: (v) => Navigator.pop(ctx, v),
                          ),
                          if (_customStyles.isNotEmpty) const Divider(),
                          ..._customStyles.map(
                            (style) => RadioListTile<String>(
                              title: Text(style['name'] ?? '未命名'),
                              subtitle: Text(
                                style['prompt'] ?? '',
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              value: style['id']!,
                              groupValue: _currentStyleId,
                              onChanged: (v) => Navigator.pop(ctx, v),
                            ),
                          ),
                        ],
                      ),
                    );
                    if (selected != null) {
                      _customStyles = await StorageService.loadCustomStyles();
                      final prefs = await SharedPreferences.getInstance();
                      await prefs.setString(
                        'novel_reply_style_${_project.id}',
                        selected,
                      );
                      setState(() => _currentStyleId = selected);
                      final styleName = selected == 'normal'
                          ? '默认'
                          : (_customStyles.firstWhere(
                                  (s) => s['id'] == selected,
                                  orElse: () => {'name': '新风格'},
                                )['name'] ??
                                '新风格');
                      _insertSystemNotification('旁白风格已切换为：$styleName');
                    }
                  },
                ),
                _buildDrawerTile(Icons.edit_note, '旁白提示词', _editNarratorPrompt),
                _buildDrawerTile(Icons.summarize, '总结提示词', _editSummaryPrompt),
                _buildDrawerTile(Icons.smart_toy, '旁白模型', _selectNarratorModel),
              ],
            ),
            const Divider(),

            // ───── 智能记忆 ─────
            ExpansionTile(
              leading: const Icon(Icons.memory),
              title: const Text('智能记忆'),
              initiallyExpanded: false,
              children: [
                SwitchListTile(
                  title: const Text('自动记忆摘要'),
                  subtitle: Text(_autoSummaryEnabled ? '已开启' : '已关闭'),
                  value: _autoSummaryEnabled,
                  onChanged: (v) async {
                    setState(() => _autoSummaryEnabled = v);
                    await NovelStorageService.saveAutoSummaryEnabled(
                      _project.id,
                      v,
                    );
                  },
                ),
                ListTile(
                  title: const Text('触发条数'),
                  subtitle: Slider(
                    value: _autoSummaryThreshold.toDouble(),
                    min: 10,
                    max: 100,
                    divisions: 9,
                    label: '$_autoSummaryThreshold条',
                    onChanged: (v) async {
                      setState(() => _autoSummaryThreshold = v.toInt());
                      await NovelStorageService.saveAutoSummaryThreshold(
                        _project.id,
                        v.toInt(),
                      );
                    },
                  ),
                ),
                ListTile(
                  title: const Text('记忆上限'),
                  subtitle: Slider(
                    value: _maxMemoryCount.toDouble(),
                    min: 1,
                    max: 20,
                    divisions: 19,
                    label: '$_maxMemoryCount条',
                    onChanged: (v) async {
                      setState(() => _maxMemoryCount = v.toInt());
                      await NovelStorageService.saveMaxMemoryCount(
                        _project.id,
                        v.toInt(),
                      );
                    },
                  ),
                ),
              ],
            ),
            const Divider(),

            // ───── 角色与剧情 ─────
            _buildDrawerSection(
              context,
              icon: Icons.people,
              title: '角色与剧情',
              children: [
                _buildDrawerTile(Icons.public, '世界观', _editWorldSetting),
                _buildDrawerTile(Icons.person_add, '添加角色', _addCharacter),
                ListTile(
                  leading: const Icon(Icons.ios_share),
                  title: const Text('导出角色设定'),
                  subtitle: const Text('复制当前选中角色的设定'),
                  onTap: () {
                    Navigator.pop(context);
                    if (_selectedSpeakCharacter != null) {
                      final json = jsonEncode(
                        _selectedSpeakCharacter!.toJson(),
                      );
                      Clipboard.setData(ClipboardData(text: json));
                      AppSnackbars.showInfo(context, '已复制 ${_selectedSpeakCharacter!.name} 的设定');
                    } else {
                      AppSnackbars.showError(context, '请先选择发言角色');
                    }
                  },
                ),
                _buildDrawerTile(Icons.casino, '随机事件', _generateRandomEvent),
              ],
            ),
            const Divider(),

            // ───── 记忆与数据 ─────
            _buildDrawerSection(
              context,
              icon: Icons.save,
              title: '记忆与数据',
              children: [
                _buildDrawerTile(Icons.memory, '管理记忆事件', _manageMemoryEvents),
                _buildDrawerTile(Icons.call_split, '创建支线', _createNovelBranch),
                _buildDrawerTile(Icons.account_tree, '支线管理', _showNovelBranchManager),
                _buildDrawerTile(Icons.save_alt, '保存存档', _saveAsArchive),
                _buildDrawerTile(Icons.description, '导出小说', _exportNovel),
              ],
            ),
            const Divider(),

            // ───── 其他 ─────
            _buildDrawerSection(
              context,
              icon: Icons.miscellaneous_services,
              title: '其他',
              children: [
                _buildDrawerTile(Icons.brush, '图片修饰词', _openImageModifierPopup),
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
          ],
        ),
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
                AppSnackbars.showInfo(context, '已复制到剪贴板');
              },
            ),
            // 编辑（仅上帝指令）
            if (_messages[index].sender == _godSender)
              ListTile(
                leading: const Icon(Icons.edit),
                title: const Text('编辑'),
                onTap: () {
                  Navigator.pop(ctx);
                  _editMessage(index);
                },
              ),
            // 重新生成（仅旁白）
            if (_messages[index].sender == _narratorSender)
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
      // 👇👇👇 先移除所有监听器（必须在dispose之前）
      _textFocusNode.removeListener(_onFocusChange);
      _scrollController.removeListener(_onScroll);
      
      // 再释放所有控制器
      _textFocusNode.dispose();
      _scrollController.dispose();
      _textController.dispose();
      speakingCtrl.dispose(); // 这个控制器原来定义了但没释放，顺便加上
      
      super.dispose();
    }
}

class CharacterSpeakConfig {
  final Character character;
  final String? text;
  CharacterSpeakConfig({required this.character, this.text});
}

class _QuickActionData {
  final IconData icon;
  final String label;
  final Color color;
  final String action;
  const _QuickActionData(this.icon, this.label, this.color, this.action);
}

class _CharacterSpeakSheet extends StatefulWidget {
  final List<Character> characters;
  final Character? selectedCharacter;
  const _CharacterSpeakSheet({
    required this.characters,
    this.selectedCharacter,
  });

  @override
  State<_CharacterSpeakSheet> createState() => _CharacterSpeakSheetState();
}

class _CharacterSpeakSheetState extends State<_CharacterSpeakSheet> {
  Character? _char;
  final TextEditingController _textCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _char = widget.selectedCharacter ??
        (widget.characters.isNotEmpty ? widget.characters.first : null);
    // 删除了这里的监听，弹窗里不需要它
  }
    @override
    void dispose() {
      _textCtrl.dispose(); // 释放弹窗里的文本控制器
      super.dispose();
    }
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            '角色发言',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
          ),
          const SizedBox(height: 12),
          // 角色选择
          DropdownButton<Character>(
            value: _char,
            isExpanded: true,
            items: widget.characters
                .map((c) => DropdownMenuItem(value: c, child: Text(c.name)))
                .toList(),
            onChanged: (v) => setState(() => _char = v),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _textCtrl,
            maxLines: 3,
            decoration: const InputDecoration(
              hintText: '自定义台词（留空则AI生成）',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: _char == null
                    ? null
                    : () {
                        Navigator.pop(
                          context,
                          CharacterSpeakConfig(
                            character: _char!,
                            text: _textCtrl.text.trim().isNotEmpty
                                ? _textCtrl.text.trim()
                                : null,
                          ),
                        );
                      },
                child: const Text('发言'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
