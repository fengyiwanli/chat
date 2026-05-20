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
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/services.dart';

import '../utils/app_dialogs.dart';
import '../utils/app_snackbars.dart';
import 'package:intl/intl.dart'; // ✅ 正确


import 'package:path_provider/path_provider.dart';

class ChatController extends ChangeNotifier {
  final String sessionId;
  List<String> memoryEvents = [];

  ChatController({required this.sessionId});

  // 添加记忆事件（原有逻辑 + RAG 存储）
  Future<void> addMemoryEvent(String event) async {
    memoryEvents.add(event);
    // 新增：向量化存储
    try {
      
      debugPrint('RAG 已存入记忆: $event');
    } catch (e) {
      debugPrint('RAG 存入失败: $e');
    }
    notifyListeners();
  }

  // 构建系统提示词时检索相关记忆
 
}
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

class _ChatPageState extends State<ChatPage>with WidgetsBindingObserver  {
  Character? _getUserCharacter() {
    for (final c in _participants) {
      if (c.isUser) return c;
    }
    return null;
  }

  Map<String, dynamic> _relationData = {}; // 存好感度、信任度、亲密感、简述
  bool _autoLongTermMemory = false;
  List<String> _longTermMemories = [];
  int _messageCountSinceLastSummary = 0;
  String _replyStyle = 'normal'; // 'normal' 或 'detailed'
  final bool _isReady = false;
  final Set<int> _animatingIndices = {};
  late ChatController controller;
  bool _statusAutoExpand = false;
  bool _showClearInputBtn = true;
  bool _isNearBottom = true; // 是否在底部附近
  int _lastPromptTokens = 0;
  int _lastCompletionTokens = 0;
  bool _autoSummaryEnabled = false;
  int _autoSummaryThreshold = 20;
  int _maxMemoryCount = 5;
  int _messagesSinceLastSummary = 0;
  int _lastTotalTokens = 0;
  int _cumulativeTokens = 0;
  String _narrationPrompt = ''; // 当前聊天室的旁白提示词，空表示用系统默认
  bool _pendingSystemUpdate = false; // 是否有待处理的设定变更
  bool _isInputExpanded = false;
  bool _showEmotion = true;
  List<Map<String, String>> _customStyles = [];
  String _currentStyleId = 'normal'; // 当前选择的风格ID，normal表示默认
  /// 插入系统提示消息，并标记下次扩大上下文
  ///   bool _autoSummaryEnabled = false;
  /// // 草稿自动保存

  bool _dynamicStatusEnabled = false;
  String _dynamicStatusPrompt =
      '请以生动的文学语言描述角色的当前状态，用JSON返回，字段名固定为：attire（着装）、catchphrase（外貌）、personality（性格）、speakingStyle（说话风格）。每个字段的值应是一段自然描述，而不是简单词语。例如：\n'
      '{"attire":"她穿着修身的白色校服，领口系着蝴蝶结，深蓝色百褶裙在微风中轻轻摆动，白色的及膝袜包裹着纤细的小腿","catchphrase":"一头乌黑的长直发，眼眸清澈，五官精致","personality":"外表文静，内心活泼，略带傲娇","speakingStyle":"语调轻柔，偶尔带点任性的上扬"}';
  Map<String, Map<String, String>> _dynamicStatuses = {}; // 角色名 -> 动态状态JSON
  List<Map<String, String>> _statusStyles = [];
  String _currentStatusStyleId = 'default'; // default 表示不额外生成，用原始设定
  List<String> _customStatusFieldDefs = [];
   // 加载聊天设置
  Future<void> _loadChatSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _statusAutoExpand = prefs.getBool('status_auto_expand') ?? false;
      _showClearInputBtn = prefs.getBool('show_clear_input_btn') ?? true;
    });
  }
  void _insertSystemNotification(String content) {
    setState(() {
      _messages.add(
        ChatMessage(text: '【系统提示】$content', isUser: false, sender: '系统'),
      );
      _pendingSystemUpdate = true; // 下次AI调用时扩大上下文
    });
    _saveHistory();
  }

  String _sanitizeText(String text) {
    // 移除非法 UTF-16 字符，防止渲染崩溃
    return text.replaceAll(RegExp(r'[\uD800-\uDFFF]'), '');
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

  Future<void> _generateDynamicStatus(Character character) async {
    if (_currentStatusStyleId == 'default') return;
    final style = _statusStyles.firstWhere(
      (s) => s['id'] == _currentStatusStyleId,
      orElse: () => <String, String>{},
    );
    final customPrompt = style['prompt'] ?? '';
    if (customPrompt.isEmpty) return;

    // 收集最近的聊天记录（8条）
    final recentMessages = _messages.length > 8
        ? _messages.sublist(_messages.length - 8)
        : _messages;
    final contextStr = recentMessages
        .map((m) => '${m.sender}: ${m.text}')
        .join('\n');

    final systemPrompt = '''你是一个角色状态分析助手。
你的任务是根据当前对话内容，生成角色此刻的状态信息。
你必须严格遵守下面的规则：
1. 只输出 JSON 格式，不要加任何解释、说明或标记。
2. JSON 的字段名由用户要求决定，你可以增加或减少字段，但必须涵盖用户提到的所有字段。
3. 绝对不要照搬用户给出的示例文本。示例只是风格参考，你需要根据当前对话中的角色表现，重新创作每一段描述。
4. 如果某个状态在对话中没有体现，可以合理推测，但不能编造不合理的内容。''';

    final userPrompt =
        '''角色名称：${character.name}
角色基本设定（仅供参考，以实际对话表现为准）：
着装：${character.attire}
外貌：${character.catchphrase}
性格：${character.personality}
说话风格：${character.speakingStyle}

以下是最近的对话历史：
------------------------------------------------
$contextStr
------------------------------------------------

请根据以上对话历史，以及下面的【风格与字段要求】，生成该角色当前的状态 JSON。
$customPrompt
''';

    try {
      final response = await AiService.callChatApi(
        modelLabel: character.aiModel,
        messages: [
          {'role': 'system', 'content': systemPrompt},
          {'role': 'user', 'content': userPrompt},
        ],
      );
      final json = jsonDecode(response.content.trim()) as Map<String, dynamic>;
      final Map<String, String> statusMap = {};
      json.forEach((k, v) => statusMap[k] = v.toString());

      // 将快照写入该角色最新的一条消息中
      for (int i = _messages.length - 1; i >= 0; i--) {
        if (_messages[i].sender == character.name) {
          _messages[i].statusSnapshot = statusMap;
          debugPrint('已为 ${character.name} 保存状态快照：$statusMap');
          setState(() {}); // 刷新界面
          break;
        }
      }
    } catch (e) {
      debugPrint('生成动态状态失败: $e');
    }
  }
// 保存草稿
// 保存草稿
Future<void> _saveDraft() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(
    "chat_draft_${widget.sessionId}",
    _textController.text,
  );
}

// 读取草稿
Future<void> _loadDraft() async {
  final prefs = await SharedPreferences.getInstance();
  final text = prefs.getString("chat_draft_${widget.sessionId}") ?? "";
  _textController.text = text;
  setState(() {});
}

// 发送后清空草稿
Future<void> _clearDraft() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.remove("chat_draft_${widget.sessionId}");
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

  Future<void> _showBranchManager() async {
    final branches = await StorageService.loadBranchArchives(widget.sessionId);
    // 主分支也显示在列表中
    final allBranches = <Map<String, dynamic>>[
      {
        'id': widget.sessionId,
        'name': '主线',
        'createdAt': '当前',
        'characterNames': _participants.map((c) => c.name).join(', '),
      },
      ...branches,
    ];

    showDialog(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('选择分支'),
        children: allBranches
            .map(
              (branch) => ListTile(
                title: Text(branch['name']),
                subtitle: Text('角色：${branch['characterNames']}'),
                trailing: branch['id'] != widget.sessionId
                    ? IconButton(
                        icon: const Icon(Icons.delete, color: Colors.red),
                        onPressed: () async {
                          // 删除分支
                          final confirm = await AppDialogs.showConfirmDialog(
  context,
  title: '删除消息',
  content: '确定要删除这条消息吗？',
  confirmText: '删除',
  isDestructive: true,
);
                          if (confirm == true) {
                            branches.removeWhere(
                              (b) => b['id'] == branch['id'],
                            );
                            await StorageService.saveBranchArchives(
                              widget.sessionId,
                              branches,
                            );
                            // 同时删除存档数据
                            await StorageService.deleteCharacter(
                              branch['id'],
                            ); // 或者专门写一个删除存档的方法
                            Navigator.pop(ctx);
                            _showBranchManager(); // 刷新列表
                          }
                        },
                      )
                    : null,
                onTap: () {
                  Navigator.pop(ctx);
                  if (branch['id'] != widget.sessionId) {
                    // 切换到分支存档
                    Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ChatPage(
                          characters: const [],
                          sessionId: branch['id'],
                          archiveName: branch['name'],
                        ),
                      ),
                    );
                  }
                },
              ),
            )
            .toList(),
      ),
    );
  }

  Widget _buildStatusItem(String label, String value) {
    if (value.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$label：',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
          ),
          Expanded(child: Text(value, style: const TextStyle(fontSize: 13))),
        ],
      ),
    );
  }

  Map<String, bool> _statusPanelFields = {
    'attire': true,
    'catchphrase': true,
    'personality': true,
    'speakingStyle': true,
    'emotion': true,
    'relation': true,
  };
  String _statusPanelTemplate = '{{label}}：{{value}}';

 Widget _buildRoleStatusTile(ChatMessage message) {
  if (message.statusSnapshot == null || message.statusSnapshot!.isEmpty) {
    return const SizedBox.shrink();
  }

  final status = message.statusSnapshot!;

  // 👇 万能中英文映射，你随便加字段，自动翻译
  final Map<String, String> autoNameMap = {
    'attire': '着装',
    'catchphrase': '外貌',
    'personality': '性格',
    'speakingStyle': '说话风格',
    'emotion': '情绪',
    'mood': '心情',
    'relation': '关系',
    'action': '动作',
    'location': '位置',
    'breastStatus': '胸部状态',
    'pussyStatus': '下体状态',
    'anusStatus': '后庭状态',
    'expression': '表情',
    'posture': '姿态',
    'feeling': '感受',
    'desire': '欲望',
  };

  return Theme(
    data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
    child: ExpansionTile(
      tilePadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      childrenPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      leading: const Icon(Icons.info_outline, size: 18),
      title: const Text(
        "角色状态",
        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
      ),
      trailing: Text("${status.length}项", style: const TextStyle(fontSize: 12)),
      initiallyExpanded: _statusAutoExpand,
      children: [
        Column(
          children: status.entries.map((e) {
            final showLabel = autoNameMap[e.key] ?? e.key;
            return _buildFullWidthStatusItem(showLabel, e.value);
          }).toList(),
        ),
      ],
    ),
  );
}
void _deleteImageFromMessage(BuildContext context, ChatMessage message) async {
    final confirm = await AppDialogs.showConfirmDialog(
      context,
      title: '删除图片',
      content: '确定要删除这张图片吗？',
      confirmText: '删除',
      isDestructive: true,
    );

    if (confirm == true) {
      setState(() {
        message.imageUrl = null;
      });
      AppSnackbars.showSuccess(context, '图片已删除');
    }
  }




Widget _buildFullWidthStatusItem(String label, String value) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 72,
          child: Text(
            "$label：",
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Theme.of(context).colorScheme.primary,
            ),
            textAlign: TextAlign.right,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(fontSize: 13, height: 1.5),
          ),
        ),
      ],
    ),
  );
}
// 配套的状态行组件（不动）

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
                      style: TextStyle(
                        color: const Color.fromARGB(255, 4, 170, 46),
                      ),
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

  Future<void> _createBranch() async {
    final nameCtrl = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('创建分支'),
        content: TextField(
          controller: nameCtrl,
          decoration: const InputDecoration(hintText: '输入分支名称（如：选择离开）'),
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
    if (name == null || name.isEmpty) return;

    // 生成新存档 ID
    final archiveId = 'branch_${DateTime.now().millisecondsSinceEpoch}';
    // 复制当前会话数据
    await StorageService.cloneSessionTo(widget.sessionId, archiveId);

    // 将新分支添加到分支列表（并记录父级为主 session）
    final branches = await StorageService.loadBranchArchives(widget.sessionId);
    branches.add({
      'id': archiveId,
      'name': name,
      'createdAt': DateTime.now().toString().substring(0, 19),
      'characterNames': _participants.map((c) => c.name).join(', '),
    });
    await StorageService.saveBranchArchives(widget.sessionId, branches);

    // 同时，在全局存档列表中也加入（可选，用于在角色中心显示所有分支）
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
      AppSnackbars.showError(context,'分支“$name”已创建');
    }
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
        //StorageService.addGalleryPath(localPath);//自动保存到图库
        _saveHistory();
      } else {
        throw Exception('图片生成返回空结果');
      }
    } catch (e) {
      setState(() => message.isGeneratingImage = false);
      if (mounted) {
        AppSnackbars.showError(context,'图片生成失败: $e');
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
      AppSnackbars.showError(context,'主角设定已更新');
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
      AppSnackbars.showError(context,'存档已保存，返回主页可查看');
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
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadChatSettings();
    controller = ChatController(sessionId: widget.sessionId);
     _loadDraft(); // 打开页面时读取草稿
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
     _textFocusNode.addListener(_onFocusChange);   // 添加这行
  _scrollController.addListener(_onScroll);
    _loadAllData();
  }
void _onFocusChange() {
  if (_textFocusNode.hasFocus && _isNearBottom) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients && _isNearBottom) {
        _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
      }
    });
  }
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
  // 原有本地存储
  await StorageService.addMemoryEvent(widget.sessionId, text);
  // 更新显示列表
  _memoryEvents.add(text);
  
  // 刷新界面
  setState(() {});
  AppSnackbars.showSuccess(context, '已保存为记忆事件');
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
      _memoryEvents.add(summary);
      await StorageService.addMemoryEvent(widget.sessionId, summary);
      _saveHistory();
      _scrollToBottomIfNeeded();
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        AppSnackbars.showError(context, '摘要生成失败: $e');
      }
    }
  }

  Future<void> _setReplyStyle(String style) async {
    setState(() => _replyStyle = style);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('reply_style_${widget.sessionId}', style);
  }

  Future<void> _setCurrentStyle(String styleId) async {
    _customStyles = await StorageService.loadCustomStyles();
    setState(() => _currentStyleId = styleId);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('reply_style_${widget.sessionId}', styleId);
  }

  Future<void> _setAutoLongTermMemory(bool value) async {
    setState(() => _autoLongTermMemory = value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('auto_ltm_${widget.sessionId}', value);
  }

  Future<void> _autoGenerateMemorySummary() async {
    // 避免并发
    if (_isLoading) return;
    // 调用现有的摘要生成（它会自动获取从上次索引后的新旁白/对话并生成摘要）
    await _generateSummary();
    // 摘要生成完成，重置计数
    _messagesSinceLastSummary = 0;
    // 限制记忆数量
    _trimMemoryEvents();
  }

  Future<void> _trimMemoryEvents() async {
    if (_memoryEvents.length > _maxMemoryCount) {
      _memoryEvents = _memoryEvents.sublist(
        _memoryEvents.length - _maxMemoryCount,
      );
      await StorageService.saveMemoryEvents(widget.sessionId, _memoryEvents);
    }
  }

  Future<void> _loadAllData() async {
  // ==============================================
  // 第一阶段：并行加载除了聊天记录之外的所有数据（速度最快）
  // ==============================================
  final futures = [
    // _loadHistory(), // 👈 把这行从这里删掉！
    _loadWorldSetting(),
    _loadEventHistory(),
    _loadSceneCards(),
    _initParticipants(),
    _loadMemoryEvents(),
    StorageService.loadCustomStyles(),
    StorageService.loadCustomStatusStyles(),
    StorageService.loadAutoSummaryEnabled(),
    StorageService.loadAutoSummaryThreshold(),
    StorageService.loadMaxMemoryCount(),
    StorageService.loadLatestSummaryIndex(widget.sessionId),
    StorageService.loadShowEmotion(),
    StorageService.loadUserName(),
    StorageService.loadUserPersonality(),
    StorageService.loadImagePrefixModifier(),
    StorageService.loadImageSuffixModifier(),
    StorageService.loadChatContextLength(),
    StorageService.loadChatNarrationPrompt(widget.sessionId),
    StorageService.loadChatSummaryPrompt(widget.sessionId),
    StorageService.loadSessionTokens(widget.sessionId),
    StorageService.loadCustomStatusFields(),
  ];

  // 安全的并行加载，单个失败不影响整体
  final results = await Future.wait(
    futures.map((f) => f.catchError((e) {
      debugPrint('加载失败: $e');
      return null;
    })),
  );

  // 安全赋值，添加默认值
  _customStyles = (results[5] as List?)?.map((item) => Map<String, String>.from(item)).toList() ?? []; // 👈 注意索引从6变成5了！
  _statusStyles = (results[6] as List?)?.map((item) => Map<String, String>.from(item)).toList() ?? []; // 👈 索引从7变成6
  _autoSummaryEnabled = results[7] as bool? ?? false; // 👈 索引从8变成7
  _autoSummaryThreshold = results[8] as int? ?? 20; // 👈 索引从9变成8
  _maxMemoryCount = results[9] as int? ?? 5; // 👈 索引从10变成9
  final lastIndex = results[10] as int? ?? 0; // 👈 索引从11变成10
  _showEmotion = results[11] as bool? ?? true; // 👈 索引从12变成11
  final name = results[12] as String? ?? '我'; // 👈 索引从13变成12
  final personality = results[13] as String? ?? ''; // 👈 索引从14变成13
  final prefix = results[14] as String? ?? ''; // 👈 索引从15变成14
  final suffix = results[15] as String? ?? ''; // 👈 索引从16变成15
  final savedContext = results[16] as int? ?? 30; // 👈 索引从17变成16
  _narrationPrompt = results[17] as String? ?? ''; // 👈 索引从18变成17
  _summaryPrompt = results[18] as String? ?? ''; // 👈 索引从19变成18
  _cumulativeTokens = results[19] as int? ?? 0; // 👈 索引从20变成19
  _customStatusFieldDefs = (results[20] as List?)?.cast<String>() ?? []; // 👈 索引从21变成20

  // 打印调试信息
  debugPrint('已加载 ${_customStyles.length} 个自定义风格');

  // ==============================================
  // 第二阶段：单独加载聊天记录（必须串行，确保完成后再刷新）
  // ==============================================
  await _loadHistory(); // 👈 在这里单独加载聊天记录，等它完成再往下走
  debugPrint('已加载 ${_messages.length} 条聊天记录');

  // ==============================================
  // 第三阶段：加载依赖SharedPreferences和聊天记录的数据
  // ==============================================
  final prefs = await SharedPreferences.getInstance();
  // 在第二阶段加载SharedPreferences的部分添加
final savedDynamicStatuses = prefs.getString('dynamic_statuses_${widget.sessionId}');
if (savedDynamicStatuses != null) {
  try {
    final decoded = jsonDecode(savedDynamicStatuses) as Map<String, dynamic>;
    _dynamicStatuses = decoded.map(
      (key, value) => MapEntry(key, Map<String, String>.from(value as Map)),
    );
  } catch (e) {
    debugPrint('解析动态状态失败: $e');
  }
}
  _currentStyleId = prefs.getString('reply_style_${widget.sessionId}') ?? 'normal';
  _autoLongTermMemory = (prefs.getBool('auto_ltm_${widget.sessionId}') ?? false);
  _longTermMemories = await StorageService.loadLongTermMemories(widget.sessionId);
  _messageCountSinceLastSummary = 0;
  
  // ✅ 现在_messages已经有数据了，计算才是正确的
  _messagesSinceLastSummary = (_messages.length - lastIndex).clamp(0, _messages.length);
  
  _currentStatusStyleId = prefs.getString('status_style_${widget.sessionId}') ?? 'default';
  _dynamicStatusEnabled = prefs.getBool('dynamic_status_enabled') ?? false;
  _dynamicStatusPrompt = prefs.getString('dynamic_status_prompt') ?? '...';
  
  final savedStatuses = prefs.getString('dynamic_statuses_${widget.sessionId}');
  if (savedStatuses != null) {
    try {
      final decoded = jsonDecode(savedStatuses) as Map<String, dynamic>;
      _dynamicStatuses = decoded.map(
        (key, value) => MapEntry(key, Map<String, String>.from(value as Map)),
      );
    } catch (e) {
      debugPrint('解析动态状态失败: $e');
    }
  }

  final fieldsJson = prefs.getString('status_panel_fields');
  if (fieldsJson != null) {
    try {
      _statusPanelFields = Map<String, bool>.from(jsonDecode(fieldsJson));
    } catch (e) {
      debugPrint('解析状态面板配置失败: $e');
    }
  }
  
  _statusPanelTemplate = prefs.getString('status_panel_template') ?? '{{label}}：{{value}}';

  final relStr = prefs.getString('relation_${widget.sessionId}');
  if (relStr != null) {
    try {
      _relationData = Map<String, dynamic>.from(jsonDecode(relStr));
    } catch (e) {
      debugPrint('解析情感数据失败: $e');
    }
  }

  // ==============================================
  // 第四阶段：更新界面和收尾工作
  // ==============================================
  setState(() {
    _contextLength = savedContext;
    _userName = name;
    _userPersonality = personality;
    _visibleStartIndex = (_messages.length > 50) ? _messages.length - 50 : 0;
    _imagePrefixModifier = prefix;
    _imageSuffixModifier = suffix;
  });

  _scrollToBottomIfNeeded();
  setState(() {});
}
  
  
  
  Future<void> _analyzeRelation() async {
    if (_isLoading) return;
    try {
      final recent = _messages.length > 5
          ? _messages.sublist(_messages.length - 5)
          : _messages;
      final context = recent.map((m) => '${m.sender}: ${m.text}').join('\n');
      final systemPrompt =
          '你是一个情感分析器。根据以下对话，评估角色（非用户）对用户当前的好感度(0-100)、信任度(0-100)、亲密感(0-100)，并给出一句简短原因。返回纯JSON：{"affection":60,"trust":50,"intimacy":40,"comment":"原因是..."}';
      final response = await AiService.callChatApi(
        modelLabel: _activeCharacter.aiModel,
        messages: [
          {'role': 'system', 'content': systemPrompt},
          {'role': 'user', 'content': '对话历史：\n$context'},
        ],
      );
      final content = response.content.trim();
      final map = jsonDecode(content) as Map<String, dynamic>;
      setState(() {
        _relationData = {
          'affection': map['affection'] ?? 50,
          'trust': map['trust'] ?? 50,
          'intimacy': map['intimacy'] ?? 50,
          'comment': map['comment'] ?? '',
        };
      });
      // 持久化
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        'relation_${widget.sessionId}',
        jsonEncode(_relationData),
      );
    } catch (e) {
      // 忽略解析错误
    }
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
  setState(() { // 👈 加上setState
    _messages.addAll(history);
  });
  _scrollToBottomIfNeeded();
}
// 图片长按菜单
void _showImageLongPressMenu(BuildContext context, ChatMessage message) {
  showModalBottomSheet(
    context: context,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.bookmark_border),
            title: const Text('保存到我的图库'),
            onTap: () async {
              Navigator.pop(context);
              await _saveToAppGallery(context, message);
            },
          ),
          ListTile(
            leading: const Icon(Icons.delete_outline, color: Colors.red),
            title: const Text('删除图片', style: TextStyle(color: Colors.red)),
            onTap: () async {
  // 先弹出确认对话框
  final confirm = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('删除图片'),
      content: const Text('确定要删除这张图片吗？'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('删除')),
      ],
    ),
  );

  // 确认后执行删除
  if (confirm == true) {
    setState(() => message.imageUrl = null);
    await _saveHistory();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('图片已删除')),
    );
  }

  // 最后关闭长按菜单
  if (mounted) Navigator.pop(context);
},
          ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
}
// 保存到APP内置图库（自动处理网络/本地图片）
// 保存到APP内置图库（兼容所有Flutter版本）
Future<void> _saveToAppGallery(BuildContext context, ChatMessage message) async {
  try {
    final imageUrl = message.imageUrl!;
    
    if (imageUrl.startsWith('http')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('正在保存图片...')),
      );
      
      // 手动读取字节流（兼容所有版本）
      final response = await HttpClient().getUrl(Uri.parse(imageUrl));
      final httpResponse = await response.close();
      
      // 手动拼接字节
      final List<int> bytes = [];
      await for (var chunk in httpResponse) {
        bytes.addAll(chunk);
      }
      
      final tempDir = await getTemporaryDirectory();
      final fileName = '${DateTime.now().millisecondsSinceEpoch}.png';
      final file = await File('${tempDir.path}/$fileName').writeAsBytes(bytes);
      
      await StorageService.addGalleryPath(file.path);
      
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已保存到我的图库')),
      );
    } else {
      await StorageService.addGalleryPath(imageUrl);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已保存到我的图库')),
      );
    }
  } catch (e) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('保存失败')),
    );
  }
}

// 显示全屏可缩放图片（同时支持网络和本地文件）
void _showFullScreenImage(BuildContext context, String imageUrl) {
  showDialog(
    context: context,
    barrierColor: Colors.black87, // 半透明黑色背景
    builder: (context) => Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: EdgeInsets.zero, // 真正全屏显示
      child: Stack(
        children: [
          // 支持双指缩放、拖动的图片
          InteractiveViewer(
            minScale: 0.5, // 最小缩小到一半
            maxScale: 4.0, // 最大放大4倍
            child: Center(
              child: imageUrl.startsWith('http')
                  ? CachedNetworkImage(
                      imageUrl: imageUrl,
                      fit: BoxFit.contain,
                      width: double.infinity,
                      height: double.infinity,
                      placeholder: (context, url) => const Center(
                        child: CircularProgressIndicator(color: Colors.white),
                      ),
                      errorWidget: (context, url, error) => const Center(
                        child: Icon(Icons.broken_image, color: Colors.white, size: 64),
                      ),
                    )
                  : Image.file(
                      File(imageUrl),
                      fit: BoxFit.contain,
                      width: double.infinity,
                      height: double.infinity,
                    ),
            ),
          ),
          // 右上角关闭按钮
          Positioned(
            top: 40,
            right: 20,
            child: IconButton(
              icon: const Icon(Icons.close, color: Colors.white, size: 30),
              onPressed: () => Navigator.pop(context),
            ),
          ),
        ],
      ),
    ),
  );
}
// 从消息中删除图片（和你图库的删除风格保持一致）
// 从消息中删除图片（显式传递context，绝对不会报错）

// 点击展开的状态标签组件
Widget _buildCompactStatusChip(String label, String value) {
  final ValueNotifier<bool> isExpanded = ValueNotifier(false);

  return ValueListenableBuilder<bool>(
    valueListenable: isExpanded,
    builder: (context, expanded, child) {
      return GestureDetector(
        onTap: () => isExpanded.value = !expanded,
        child: Tooltip(
          message: '点击${expanded ? '收起' : '展开'}',
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.5),
              borderRadius: BorderRadius.circular(6),
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.4,
              ),
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: '$label：',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                    TextSpan(
                      text: value,
                      style: TextStyle(
                        fontSize: 10,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
                maxLines: expanded ? null : 2,
                overflow: expanded ? TextOverflow.visible : TextOverflow.ellipsis,
              ),
            ),
          ),
        ),
      );
    },
  );
}
  Future<void> _saveHistory() async {
  await StorageService.saveMessages(widget.sessionId, _messages);
  
  // ✅ 新增：保存全局动态状态
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(
    'dynamic_statuses_${widget.sessionId}',
    jsonEncode(_dynamicStatuses),
  );
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
      final systemPrompt = '你是一个情绪分析助手，只回复一个表情符号和不超过3个字的情感描述，例如“😊 愉快”。';
      final userPrompt =
          '根据以下对话内容，判断说话者当前的情绪状态，回复格式：表情符号 + 一个空格 + 简短中文情感词。\n对话：$text';

      final moodResponse = await AiService.callChatApi(
        modelLabel: _activeCharacter.aiModel,
        messages: [
          {'role': 'system', 'content': systemPrompt},
          {'role': 'user', 'content': userPrompt},
        ],
      );
      final raw = moodResponse.content.trim();
      if (raw.isNotEmpty) {
        setState(() {
          // 如果包含空格，则分离表情和文字
          if (raw.contains(' ') && raw.length > 2) {
            _activeMood = raw; // 直接使用“😊 愉快”
          } else {
            _activeMood = raw; // 只有表情或太短
          }
        });
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

  static String _sanitizeUtf16(String input) {
    if (input.isEmpty) return input;
    return input.replaceAllMapped(
      RegExp(r'([\uD800-\uDBFF][\uDC00-\uDFFF])|[\uD800-\uDFFF]'),
      (match) => match.group(1) != null ? match.group(1)! : '',
    );
  }

 Future<Map<String, String>?> _generateDynamicStatusForReply(
  Character character,
  String replyText,
) async {
  final style = _statusStyles.firstWhere(
    (s) => s['id'] == _currentStatusStyleId,
    orElse: () => <String, String>{},
  );

  final customPrompt = style['prompt'] ?? '';
  if (_currentStatusStyleId != 'default' && customPrompt.isEmpty) {
    return null;
  }

  final recentMessages = _messages.length > 6
      ? _messages.sublist(_messages.length - 6)
      : _messages;
  final history = recentMessages
      .map((m) => "${m.sender}: ${m.text}")
      .join("\n");

  final lastStatus = _dynamicStatuses[character.name] ?? {};

  // ==============================================
  // 🔴 核心终极版：自动识别你的自定义字段！！！
  // ==============================================
  late String systemPrompt;

  if (_currentStatusStyleId == "default") {
    systemPrompt = '''
你是角色状态生成器，只输出JSON。

【严格遵守以下规则】
1. 状态必须连续自然，不能突然突变。
2. 只微调情绪、动作、表情，不要大幅度改变。
3. 穿着、外貌这种固定设定，没有剧情改动就绝不修改。
4. 内容必须根据对话上下文生成。
5. 保持符合角色性格。

必须包含5个字段：
emotion（情绪）、attire（着装）、catchphrase（外貌）、action（动作）、location（位置）
''';
  } else {
    systemPrompt = '''
你是角色状态生成器，只输出JSON。
从用户提供的状态模板中，**提取所有字段**。
根据对话自动生成最新状态，**绝对不要复制模板原文**。
保持状态连续性，合理变化，符合当前情境。
状态必须连续自然，不能突然突变。
基于上一次状态微调，不要完全重写。
只改变情绪、动作、表情、感受等临时状态。
穿着、外貌、体型等固定设定，没有特殊剧情改动就绝不修改。
内容必须根据对话上下文生成，不复制模板。
''';
  }

  final userPrompt = '''
角色：${character.name}
性格：${character.personality}
着装：${character.attire}
外貌：${character.catchphrase}

【状态字段模板】
$customPrompt

【上一次状态】
${jsonEncode(lastStatus)}

【对话历史】
$history

【本次回复】
$replyText

请输出最新状态JSON，不要多余内容。
''';

  try {
    final res = await AiService.callChatApi(
      modelLabel: character.aiModel,
      messages: [
        {'role': 'system', 'content': systemPrompt},
        {'role': 'user', 'content': userPrompt},
      ],
    );

    final json = jsonDecode(res.content.trim()) as Map<String, dynamic>;
    final Map<String, String> result = {};
    json.forEach((k, v) => result[k] = v.toString().trim());

    _dynamicStatuses[character.name] = result;
    return result;
  } catch (e) {
    debugPrint("状态生成失败：$e");
    return lastStatus.isNotEmpty ? lastStatus : null;
  }
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
    String reply = aiResponse.content;
    // 清洗非法UTF-16字符
    reply = _sanitizeUtf16(reply);

    // 恢复上下文长度
    if (_pendingSystemUpdate) {
      _contextLength = originalContextLength;
      _pendingSystemUpdate = false;
    }

    // 累加并持久化 token（使用 session 独立方法）

    _addTokens(aiResponse);

    // 预先为即将添加的 AI 回复生成状态快照
    Map<String, String>? statusSnapshot;
    if (_currentStatusStyleId != 'default' && !speaker.isUser) {
      statusSnapshot = await _generateDynamicStatusForReply(speaker, reply);
    }

    setState(() {
      _lastPromptTokens = aiResponse.promptTokens;
      _lastCompletionTokens = aiResponse.completionTokens;
      _lastTotalTokens = aiResponse.totalTokens;
      final newMsg = ChatMessage(
        text: reply,
        isUser: speaker.isUser,
        sender: speaker.name,
        statusSnapshot: statusSnapshot,
      );
      _messages.add(newMsg);
      _animatingIndices.add(_messages.length - 1);
      _isLoading = false;
    });

    Future.delayed(const Duration(milliseconds: 400), () {
      if (mounted) {
        setState(() => _animatingIndices.remove(_messages.length - 1));
      }
    });

    _saveHistory();

    // 新增情感分析（可独立开关）
    if (_showEmotion && !speaker.isUser) _analyzeRelation();
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
    // 在 _sendRequest 的末尾（保存历史之后、_scrollToBottomIfNeeded 之前）
    _messagesSinceLastSummary++; // 因为本次新增了一条 AI 消息
    if (_autoSummaryEnabled &&
        _messagesSinceLastSummary >= _autoSummaryThreshold) {
      _autoGenerateMemorySummary();
    }
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
        AppSnackbars.showError(context, '旁白生成失败: $e');
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
        AppSnackbars.showError(context, '随机事件生成失败: $e');
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
        insetPadding: const EdgeInsets.all(8), // ← 缩小外边距，对话框变宽
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                height: 120,
                child: TextField(
                  controller: eventController,
                  decoration: const InputDecoration(
                    hintText: '输入事件描述',
                    border: OutlineInputBorder(),
                  ),
                  expands: true, // 填满 SizedBox
                  maxLines: null, // 必须为 null
                  minLines: null, // 必须为 null
                  textAlignVertical: TextAlignVertical.top,
                ),
              ), // 在上帝模式对话框的 children 中，TextField 之后添加
              Wrap(
                spacing: 8,
                children: [
                  ActionChip(
                    label: const Text('换装'),
                    onPressed: () {
                      eventController.text = '角色换上了一套新的服装：';
                      // 可选：自动更新角色着装？这里仅填入指令
                    },
                  ),
                  ActionChip(
                    label: const Text('突发事件'),
                    onPressed: () => eventController.text = '突然，',
                  ),
                  ActionChip(
                    label: const Text('情绪'),
                    onPressed: () => eventController.text = '此刻，角色的情绪发生了转变：',
                  ),
                ],
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

void _generateForLatestAi() {
  // 从最后一条消息开始向前查找
  for (int i = _messages.length - 1; i >= 0; i--) {
    final msg = _messages[i];
    if (!msg.isUser && msg.imageUrl == null && !msg.isGeneratingImage) {
      _generateImageForIndex(i);
      return; // 找到就停止
    }
  }
  // 没找到
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(content: Text("没有可生成图片的AI回复")),
  );
}
  // ------ 角色自主对话（修复空指针）------
  Future<void> _autoConversation() async {
    // 确保参与者列表至少有两个角色
    if (_participants.length < 2) {
      AppSnackbars.showError(context, '至少需要两个角色才能自主对话');
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

  void _showRelationPanel() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${_activeCharacter.name} 对你的情感'),
        content: _relationData.isEmpty
            ? const Text('暂无情感数据，继续聊天即可生成。')
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildRelationBar(
                    '好感度',
                    _relationData['affection'] ?? 0,
                    Colors.red,
                  ),
                  const SizedBox(height: 12),
                  _buildRelationBar(
                    '信任度',
                    _relationData['trust'] ?? 0,
                    Colors.blue,
                  ),
                  const SizedBox(height: 12),
                  _buildRelationBar(
                    '亲密感',
                    _relationData['intimacy'] ?? 0,
                    Colors.pink,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '简述：${_relationData['comment'] ?? ''}',
                    style: const TextStyle(fontStyle: FontStyle.italic),
                  ),
                ],
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

  Widget _buildRelationBar(String label, int value, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('$label: $value'),
        const SizedBox(height: 4),
        LinearProgressIndicator(
          value: value / 100.0,
          color: color,
          backgroundColor: color.withOpacity(0.2),
        ),
      ],
    );
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
    if (character.speakingStyle.isNotEmpty) {
      prompt += '说话风格：${character.speakingStyle}\n';
    }
    if (_relationData.isNotEmpty && !character.isUser) {
      prompt += '\n\n【角色当前对你的情感状态（需在对话中自然体现）】';
      prompt += '\n好感度：${_relationData['affection'] ?? 50}';
      prompt += '\n信任度：${_relationData['trust'] ?? 50}';
      prompt += '\n亲密感：${_relationData['intimacy'] ?? 50}';
      prompt += '\n情感简述：${_relationData['comment'] ?? ''}';
    }
  }

  prompt += '当前用户的名字是$_userName。\n';
  if (_worldSetting.isNotEmpty) prompt += '世界背景：$_worldSetting\n';

  if (character.relations.isNotEmpty) {
    prompt += '你与其他角色的关系：\n';
    character.relations.forEach((name, relation) {
      prompt += '- $name：$relation\n';
    });
  }

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

  // ───── 自定义风格 / 普通模式 ─────
  if (_currentStyleId != 'normal' && !character.isUser) {
    String customPrompt = '';
    try {
      final style = _customStyles.firstWhere((s) => s['id'] == _currentStyleId);
      customPrompt = style['prompt'] ?? '';
    } catch (_) {}

    if (customPrompt.isNotEmpty) {
      prompt += '\n【你必须立即按照以下自定义风格回复消息，不得偏离】\n$customPrompt';
    } else {
      if (!character.isUser) {
        prompt +=
            '\n【回复格式】重要：每次回复时，先简短描述你当前的穿着和外表，从内到外所有穿搭都会简单的描述，包括内衣内裤，放在()里。如果最近对话中提到你换了装束，就描述那套新的,如果没有提过，就按初始设定“${character.attire}”描述。';
        prompt += '禁止在正文中出现你的名字或“名字：”这样的前缀，你只需输出括号内的形象描述和对话。';
      }
      prompt += '请完全以角色的身份和语气说话。';
    }
  }  
  

  debugPrint('完整系统提示词：$prompt');
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
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton.icon(
                      icon: const Icon(Icons.paste),
                      label: const Text('从剪贴板导入'),
                      onPressed: () async {
                        final data = await Clipboard.getData(
                          Clipboard.kTextPlain,
                        );
                        if (data == null ||
                            data.text == null ||
                            data.text!.isEmpty) {
                          return;
                        }
                        try {
                          final json =
                              jsonDecode(data.text!) as Map<String, dynamic>;
                          final c = Character.fromJson(json);
                          setDialogState(() {
                            nameController.text = c.name;
                            personalityController.text = c.personality;
                            attireController.text = c.attire;
                            backgroundController.text = c.background;
                            catchphraseController.text = c.catchphrase;
                            likesController.text = c.likes;
                            dislikesController.text = c.dislikes;
                            speakingCtrl.text = c.speakingStyle;
                          });
                        } catch (_) {
                          // 忽略格式错误
                        }
                      },
                    ),
                  ],
                ),
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
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton.icon(
                      icon: const Icon(Icons.paste),
                      label: const Text('从剪贴板导入'),
                      onPressed: () async {
                        final data = await Clipboard.getData(
                          Clipboard.kTextPlain,
                        );
                        if (data == null ||
                            data.text == null ||
                            data.text!.isEmpty) {
                          return;
                        }
                        try {
                          final json =
                              jsonDecode(data.text!) as Map<String, dynamic>;
                          final c = Character.fromJson(json);
                          setDialogState(() {
                            nameController.text = c.name;
                            personalityController.text = c.personality;
                            attireController.text = c.attire;
                            backgroundController.text = c.background;
                            catchphraseController.text = c.catchphrase;
                            likesController.text = c.likes;
                            dislikesController.text = c.dislikes;
                            speakingCtrl.text = c.speakingStyle;
                          });
                        } catch (_) {
                          // 忽略格式错误
                        }
                      },
                    ),
                  ],
                ),
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
  WidgetsBinding.instance.removeObserver(this);
  // 1. 先移除所有监听器（必须在dispose之前）
  _scrollController.removeListener(_onScroll);
  
  // 2. 释放所有控制器
  _scrollController.dispose();
  _textController.dispose(); // 输入框控制器
  _textFocusNode.dispose(); // 输入框焦点控制器
  _textFocusNode.removeListener(_onFocusChange);
  // 3. 取消所有未完成的异步请求（防止页面关闭后还在后台运行）
  controller.dispose(); // 你的ChatController如果有dispose方法就调用
  _saveDraft();
  super.dispose();
}


  Future<void> _confirmDeleteCharacter(Character character) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除角色'),
        content: Text(
          '确定要从本聊天删除“${character.name}”吗？\n(该角色的历史消息仍会保留，已保存的存档不受影响)',
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
    final primaryColor = Theme.of(context).colorScheme.primary;
    // 提前计算常用条件，让模板更干净
    final canShowRoleSwitcher =
        _participants.isNotEmpty && _participants.contains(_activeCharacter);
    final canDeleteRole =
        !_activeCharacter.isUser &&
        _participants.contains(_activeCharacter);

    return Scaffold(
      resizeToAvoidBottomInset: true,
      
      // ── 顶部栏 ──
      appBar: AppBar(
        title: Text(widget.archiveName ?? '聊天室'),
        centerTitle: true,
        actions: [
          if (canShowRoleSwitcher)
            PopupMenuButton<Character>(
              icon: Icon(Icons.people, color: primaryColor),
              tooltip: '切换角色',
              itemBuilder: (_) => _participants
                  .where((c) => !c.isUser)
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
          if (canDeleteRole)
            IconButton(
              icon: const Icon(
                Icons.delete_outline,
                color: Color.fromARGB(255, 202, 9, 9),
              ),
              tooltip: '删除当前角色',
              onPressed: () => _confirmDeleteCharacter(_activeCharacter),
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
      endDrawer: Drawer(
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
                      max: 200,
                      divisions: 199,
                      label: _contextLength >= 200 ? '全文' : '$_contextLength条',
                      onChanged: (v) {
                        setState(() => _contextLength = v.toInt());
                        StorageService.saveChatContextLength(v.toInt());
                      },
                    ),
                  ),
                  ListTile(
                    leading: const Icon(Icons.style),
                    title: const Text('回复风格'),
                    subtitle: Text(
                      _currentStyleId == 'normal'
                          ? '普通对话'
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
                      // 弹出风格选择对话框...（保持之前的选择逻辑，不需重复写这里）
                      final selected = await showDialog<String>(
                        context: context,
                        builder: (ctx) => SimpleDialog(
                          title: const Text('选择回复风格'),
                          children: [
                            RadioListTile<String>(
                              title: const Text('普通对话'),
                              subtitle: const Text('简洁模式，先简短描述穿着再说话'),
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
                          'reply_style_${widget.sessionId}',
                          selected,
                        );
                        setState(() => _currentStyleId = selected);
                        final styleName = selected == 'normal'
                            ? '普通对话'
                            : (_customStyles.firstWhere(
                                    (s) => s['id'] == selected,
                                    orElse: () => {'name': '新风格'},
                                  )['name'] ??
                                  '新风格');
                        _insertSystemNotification('对话风格已切换为：$styleName');
                      }
                    },
                  ),
                ],
              ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.call_split),
                title: const Text('分支管理'),
                onTap: () async {
                  Navigator.pop(context);
                  _showBranchManager();
                },
              ),
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
                      await StorageService.saveAutoSummaryEnabled(v);
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
                        await StorageService.saveAutoSummaryThreshold(
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
                        await StorageService.saveMaxMemoryCount(v.toInt());
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
                  ListTile(
                    leading: const Icon(Icons.person),
                    title: const Text('我的设定'),
                    onTap: () {
                      Navigator.pop(context);
                      final userChar = _participants.firstWhere(
                        (c) => c.isUser,
                      );
                      _editCharacter(userChar);
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.face),
                    title: const Text('状态描写风格'),
                    subtitle: Text(
                      _currentStatusStyleId == 'default'
                          ? '原始设定'
                          : (_statusStyles.any(
                                  (s) => s['id'] == _currentStatusStyleId,
                                )
                                ? (_statusStyles.firstWhere(
                                        (s) => s['id'] == _currentStatusStyleId,
                                      )['name'] ??
                                      '未命名')
                                : '未命名'),
                    ),
                    onTap: () async {
                      Navigator.pop(context);
                      final selected = await showDialog<String>(
                        context: context,
                        builder: (ctx) => SimpleDialog(
                          title: const Text('选择状态描写风格'),
                          children: [
                            RadioListTile<String>(
                              title: const Text('原始设定'),
                              subtitle: const Text('直接显示角色原本的设定字段'),
                              value: 'default',
                              groupValue: _currentStatusStyleId,
                              onChanged: (v) => Navigator.pop(ctx, v),
                            ),
                            if (_statusStyles.isNotEmpty) const Divider(),
                            ..._statusStyles.map(
                              (style) => RadioListTile<String>(
                                title: Text(style['name'] ?? '未命名'),
                                subtitle: Text(
                                  style['prompt'] ?? '',
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                value: style['id']!,
                                groupValue: _currentStatusStyleId,
                                onChanged: (v) => Navigator.pop(ctx, v),
                              ),
                            ),
                          ],
                        ),
                      );
                      if (selected != null) {
                        setState(() => _currentStatusStyleId = selected);
                        final prefs = await SharedPreferences.getInstance();
                        await prefs.setString(
                          'status_style_${widget.sessionId}',
                          selected,
                        );
                        // 切换后，如果需要立即生成一次状态，可以触发一次生成（可选）
                        if (selected != 'default') {
                          // 这里可以手动调用一次生成，例如：
                          if (!_activeCharacter.isUser) {
                            _generateDynamicStatus(_activeCharacter);
                          }
                        }
                      }
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.favorite),
                    title: const Text('角色情感'),
                    subtitle: Text(
                      _relationData.isNotEmpty
                          ? '好感${_relationData['affection']} | 信任${_relationData['trust']} | 亲密${_relationData['intimacy']}'
                          : '暂无数据',
                    ),
                    onTap: () {
                      Navigator.pop(context);
                      _showRelationPanel();
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.edit),
                    title: const Text('编辑当前角色'),
                    onTap: () {
                      Navigator.pop(context);
                      _editCharacter(_activeCharacter);
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.person_add),
                    title: const Text('添加角色'),
                    onTap: () {
                      Navigator.pop(context);
                      _addCharacter();
                    },
                  ),
                  ListTile(
                    leading: const Text('⚡', style: TextStyle(fontSize: 20)),
                    title: const Text('上帝模式'),
                    onTap: () {
                      Navigator.pop(context);
                      _showGodModeDialog();
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.public),
                    title: const Text('世界背景'),
                    onTap: () {
                      Navigator.pop(context);
                      _editWorldSetting();
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.edit_note),
                    title: const Text('旁白提示词'),
                    onTap: () {
                      Navigator.pop(context);
                      _editNarrationPrompt();
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.casino),
                    title: const Text('剧情分支'),
                    onTap: () async {
                      Navigator.pop(context);
                      final recentMessages = _messages.length > 10
                          ? _messages.sublist(_messages.length - 10)
                          : _messages;
                      final contextStr = recentMessages
                          .map((m) => '${m.sender}：${m.text}')
                          .join('\n');
                      final branchPrompt =
                          '当前剧情上下文：\n$contextStr\n\n请生成3个后续剧情选项。';
                      final options = await _generateBranchOptions(
                        branchPrompt,
                      );
                      if (options.isNotEmpty && mounted) {
                        _showBranchOptions(options);
                      }
                    },
                  ),
                ],
              ),
              const Divider(),

              // ───── 记忆与数据 ─────
              _buildDrawerSection(
                context,
                icon: Icons.save,
                title: '记忆与数据',
                children: [
                  ListTile(
                    leading: const Icon(Icons.memory),
                    title: const Text('管理记忆事件'),
                    onTap: () {
                      Navigator.pop(context);
                      _manageMemoryEvents();
                    },
                  ),
                  // ---- 加在“保存存档”之前或之后 ----
                  ListTile(
                    leading: const Icon(Icons.call_split),
                    title: const Text('创建支线'),
                    onTap: () {
                      Navigator.pop(context);
                      _createBranch();
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.account_tree),
                    title: const Text('支线管理'),
                    onTap: () {
                      Navigator.pop(context);
                      _showBranchManager();
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.save_alt),
                    title: const Text('保存存档'),
                    onTap: () {
                      Navigator.pop(context);
                      _saveAsArchive();
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.ios_share),
                    title: const Text('导出当前角色设定'),
                    onTap: () {
                      Navigator.pop(context);
                      final json = jsonEncode(_activeCharacter!.toJson());
                      Clipboard.setData(ClipboardData(text: json));
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('已复制 ${_activeCharacter!.name} 的设定'),
                        ),
                      );
                                        },
                  ),
                ],
              ),
              const Divider(),

              // ───── 其他操作 ─────
              _buildDrawerSection(
                context,
                icon: Icons.miscellaneous_services,
                title: '其他',
                children: [
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
                  ListTile(
  leading: const Icon(Icons.arrow_downward),
  title: const Text('滚动到底部'),
  onTap: () {
    // 只关闭菜单，不做任何其他操作
    Navigator.pop(context);

    // 用最稳的 JUMP，不卡、不回弹、直接到底
    _scrollController.jumpTo(9999999);
  },
),
                
                ],
              ),
            ],
          ),
        ),
      ),
      // ... 原来的 body 保持不变
      body: Column(
        children: [
          // 情绪条
          // 优化后的情绪条
if (_activeMood.isNotEmpty)
  Container(
    padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 16),
    decoration: BoxDecoration(
      gradient: LinearGradient(
        colors: [
          Theme.of(context).colorScheme.primary.withOpacity(0.05),
          Theme.of(context).colorScheme.primary.withOpacity(0.1),
        ],
      ),
      border: Border(
        bottom: BorderSide(
          color: Theme.of(context).colorScheme.primary.withOpacity(0.2),
        ),
      ),
    ),
    child: Row(
      children: [
        CircleAvatar(
          radius: 12,
          backgroundColor: Theme.of(context).colorScheme.primary.withOpacity(0.2),
          child: Icon(Icons.mood, size: 16, color: Theme.of(context).colorScheme.primary),
        ),
        const SizedBox(width: 10),
        Text(
          '${_activeCharacter.name} 当前状态',
          style: TextStyle(
            fontWeight: FontWeight.w600,
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
        const Spacer(),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primary.withOpacity(0.15),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            _activeMood,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
        ),
      ],
    ),
  ),
          // Token 统计
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

          // 消息列表
          Expanded(
            child: Stack(
              children: [
                ListView.builder(
                  controller: _scrollController,
                  reverse: false,
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
                      // 优化后的加载状态（带角色头像和打字动画）
if (_isLoading) {
  return Padding(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
    child: Row(
      children: [
        // 显示当前活跃角色的头像
        CircleAvatar(
          radius: 14,
          backgroundColor: _characterColors[_activeCharacter.name]?.withOpacity(0.2) ?? Colors.grey.withOpacity(0.2),
          backgroundImage: _activeCharacter.avatarPath.isNotEmpty && File(_activeCharacter.avatarPath).existsSync()
              ? FileImage(File(_activeCharacter.avatarPath))
              : null,
          child: _activeCharacter.avatarPath.isEmpty
              ? Text(
                  _activeCharacter.name[0],
                  style: TextStyle(
                    color: _characterColors[_activeCharacter.name] ?? Colors.grey,
                    fontWeight: FontWeight.bold,
                  ),
                )
              : null,
        ),
        const SizedBox(width: 12),
        Text(
          '${_activeCharacter.name}正在输入',
          style: TextStyle(color: Colors.grey.shade600),
        ),
        const _TypingIndicator(), // 打字动画
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
                                  child: Builder(
                                    builder: (_) {
                                      final senderChar = _participants
                                          .firstWhere(
                                            (c) => c.name == message.sender,
                                            orElse: () => Character(
                                              name: '',
                                              personality: '',
                                              attire: '',
                                            ),
                                          );
                                      final avatarPath = senderChar.avatarPath;
                                      final hasAvatar =
                                          avatarPath.isNotEmpty &&
                                          File(avatarPath).existsSync();
                                      return CircleAvatar(
                                        radius: 14,
                                        backgroundColor: hasAvatar
                                            ? null
                                            : color.withOpacity(0.2),
                                        backgroundImage: hasAvatar
                                            ? FileImage(File(avatarPath))
                                            : null,
                                        child: hasAvatar
                                            ? null
                                            : Text(
                                                message.sender[0],
                                                style: TextStyle(
                                                  color: color,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                      );
                                    },
                                  ),
                                ),

                              // 优化后的消息气泡代码
Flexible(
  child: Container(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    constraints: BoxConstraints(
      maxWidth: MediaQuery.of(context).size.width * 0.75,
    ),
    decoration: BoxDecoration(
      // ✅ 核心修复：气泡自动跟随主题
      color: isMe
          ? Theme.of(context).colorScheme.primary
          : Theme.of(context).brightness == Brightness.dark
              ? const Color(0xFF2D2D2D) // 深色气泡
              : Colors.white, // 浅色气泡
      borderRadius: BorderRadius.circular(16),
      boxShadow: isMe
          ? null
          : [
              BoxShadow(
                color: Theme.of(context).brightness == Brightness.dark
                    ? Colors.black12
                    : Colors.grey.withOpacity(0.08),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        SelectableText(
          _sanitizeText(_cleanMessageText(message)),
          style: TextStyle(
            fontSize: 15,
            height: 1.5,
            // ✅ 文字自动变色：深色白字 / 浅色黑字
            color: isMe
                ? Colors.white
                : Theme.of(context).brightness == Brightness.dark
                    ? Colors.white
                    : const Color(0xFF1E293B),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 6.0),
          child: Text(
            DateFormat('HH:mm').format(message.timestamp),
            style: TextStyle(
              fontSize: 11,
              color: isMe
                  ? Colors.white.withOpacity(0.7)
                  : Theme.of(context).brightness == Brightness.dark
                      ? Colors.white70
                      : const Color(0xFF94A3B8),
            ),
          ),
        ),
        if (!isMe && !isNarration && message.sender != '系统')
          _buildRoleStatusTile(message),
        if (message.imageUrl != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: GestureDetector(
              onTap: () => _showFullScreenImage(context, message.imageUrl!),
              onLongPress: () => _showImageLongPressMenu(context, message),
              behavior: HitTestBehavior.opaque,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: message.imageUrl!.startsWith('http')
                    ? CachedNetworkImage(
                        imageUrl: message.imageUrl!,
                        width: 200,
                        height: 200,
                        fit: BoxFit.cover,
                        memCacheWidth: 200,
                        memCacheHeight: 200,
                      )
                    : Image.file(
                        File(message.imageUrl!),
                        width: 200,
                        height: 200,
                        fit: BoxFit.cover,
                        cacheWidth: 200,
                        cacheHeight: 200,
                      ),
              ),
            ),
          ),
      ],
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
                      heroTag: 'chatScrollDown',
                      backgroundColor: primaryColor,
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
              color: Theme.of(context).brightness == Brightness.dark
        ? const Color(0xFF1E1E1E)
        : Colors.white,
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

          // ── 输入框区域 ──
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              // ✅ 自动跟随主题：浅色白 / 深色深灰
    color: Theme.of(context).brightness == Brightness.dark
        ? const Color(0xFF1E1E1E)
        : Colors.white,
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
                    focusNode: _textFocusNode,
                    minLines: 1,
                    maxLines: _isInputExpanded ? 6 : 1,
                     onTap: () {
    
  },
                    textInputAction: TextInputAction.send,
                    onChanged: (text) {
      setState(() {});
    },
                    decoration: const InputDecoration(
                      hintText: '输入消息...',
                      border: InputBorder.none,
                    ),
                    onSubmitted: (_) => _sendMessage(),
                  ),
                ),
                PopupMenuButton<String>(
                  icon: Icon(Icons.add_circle_outline, color: primaryColor),
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
  setState(() => _isInputExpanded = !_isInputExpanded);
  if (_isInputExpanded) {
    _textFocusNode.requestFocus();

    
  }
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
                // 优化后的发送按钮（空输入时禁用）
IconButton(
  icon: const Icon(Icons.send),
  color: _textController.text.trim().isEmpty
      ? const Color.fromARGB(255, 26, 3, 233)
      : Theme.of(context).colorScheme.primary,
  onPressed: _textController.text.trim().isEmpty
      ? null
      : _sendMessage,
)
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
// 打字动画组件（放在文件最底部）
class _TypingIndicator extends StatefulWidget {
  const _TypingIndicator();

  @override
  State<_TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<_TypingIndicator> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _dot1;
  late Animation<double> _dot2;
  late Animation<double> _dot3;

  @override
  void initState() {
    super.initState();
    // 创建动画控制器，1.2秒循环一次
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();

    // 三个点依次淡入淡出
    _dot1 = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _controller, curve: const Interval(0.0, 0.4)),
    );
    _dot2 = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _controller, curve: const Interval(0.2, 0.6)),
    );
    _dot3 = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _controller, curve: const Interval(0.4, 0.8)),
    );
  }

  @override
  void dispose() {
    
    _controller.dispose(); // 释放动画控制器
    
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        FadeTransition(opacity: _dot1, child: const Text('.', style: TextStyle(fontSize: 20))),
        FadeTransition(opacity: _dot2, child: const Text('.', style: TextStyle(fontSize: 20))),
        FadeTransition(opacity: _dot3, child: const Text('.', style: TextStyle(fontSize: 20))),
      ],
    );
  }
}
