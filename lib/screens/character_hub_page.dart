import 'dart:io';
import 'package:flutter/material.dart';
import '../models/character.dart';
import '../services/storage_service.dart';
import '../services/image_service.dart';
import 'chat_page.dart';
import '../widgets/adaptive_text_field.dart';
// 用于 jsonDecode
import '../services/theme_provider.dart';
import '../services/ai_service.dart'; // AiService 类（如果已有则跳过）
import 'package:flutter/services.dart';
import 'dart:convert';

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
        content: Text(
          '确定要删除“${character.name}”吗？\n\n'
          '• 该角色当前的聊天记录会被删除。\n'
          '• 该角色已有的存档（如果有）会保留，不会被删除。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除角色'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await StorageService.deleteCharacter(character.id);
      setState(() {
        _characters.removeWhere((c) => c.id == character.id);
      });
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
                    if (character.speakingStyle.isNotEmpty)
                      Text(
                        '风格：${character.speakingStyle}',
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
              // 在 Row 的末尾，Icon(Icons.chevron_right) 之前或之后
              IconButton(
                icon: const Icon(Icons.ios_share, size: 18, color: Colors.grey),
                tooltip: '导出设定',
                onPressed: () {
                  final json = jsonEncode(character.toJson());
                  Clipboard.setData(ClipboardData(text: json));
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('${character.name} 的设定已复制到剪贴板')),
                  );
                },
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
              content: Text(
                '确定要删除存档“${archive['name']}”吗？\n\n'
                '• 该存档内的聊天记录会被删除。\n'
                '• 关联的角色本体和角色其他存档不受影响。',
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

  Future<void> _importCharacterFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data == null || data.text == null || data.text!.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('剪贴板为空')));
      return;
    }
    try {
      final json = jsonDecode(data.text!) as Map<String, dynamic>;
      final character = Character.fromJson(json);
      // 生成全新 id，避免关联旧聊天记录
      final newCharacter = Character(
        id: DateTime.now().millisecondsSinceEpoch.toString(), // 新 id
        name: character.name,
        personality: character.personality,
        attire: character.attire,
        aiModel: character.aiModel,
        worldSetting: character.worldSetting,
        relations: character.relations,
        background: character.background,
        catchphrase: character.catchphrase,
        likes: character.likes,
        dislikes: character.dislikes,
        isUser: character.isUser,
        avatarPath: character.avatarPath,
        speakingStyle: character.speakingStyle,
      );
      setState(() => _characters.add(newCharacter));
      await StorageService.saveCharacters(_characters);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('已导入角色：${character.name}')));
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('剪贴板内容不是有效的角色 JSON')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('角色中心'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.paste),
            tooltip: '导入角色',
            onPressed: _importCharacterFromClipboard,
          ),
        ],
      ),
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
        heroTag: 'createCharacter',
        onPressed: _showCreateCharacterDialog,
        child: const Icon(Icons.add),
      ),
    );
  }
}
