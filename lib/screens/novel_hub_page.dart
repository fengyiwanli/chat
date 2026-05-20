import 'package:flutter/material.dart';
import '../models/novel_project.dart';
import '../services/novel_storage_service.dart';
import 'novel_chat_page.dart';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/character.dart';
import '../utils/app_dialogs.dart';
import '../utils/app_snackbars.dart';
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
    // 替换后的代码
final name = await AppDialogs.showInputDialog(
  context,
  title: '创建小说',
  hintText: '小说名称',
  confirmText: '创建',
);
   
   
    if (name != null && name.isNotEmpty) {
      final project = NovelProject(title: name);
      _projects.add(project);
      await NovelStorageService.saveProjects(_projects);
      _load();
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => NovelChatPage(project: project)),
      );
      _load();
    }
  }

  void _deleteProject(NovelProject project) async {
    final saves = _projectSaves[project.id] ?? [];

    // 替换后的代码
final confirm = await AppDialogs.showConfirmDialog(
  context,
  title: '删除小说',
  content: '确定要删除“${project.title}”吗？\n'
      '${saves.isNotEmpty ? "该小说的 ${saves.length} 个存档将转为独立小说。" : ""}',
  confirmText: '删除',
  isDestructive: true,
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
      color: Theme.of(context).brightness == Brightness.dark
        ? const Color(0xFF1E1E1E)
        : Colors.white,
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
        color: Theme.of(context).brightness == Brightness.dark
        ? const Color(0xFF1E1E1E)
        : Colors.white,
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
           // 替换后的代码
final confirm = await AppDialogs.showConfirmDialog(
  context,
  title: '删除存档',
  content: '确定要删除存档“${save['name']}”吗？',
  confirmText: '删除',
  isDestructive: true,
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
        heroTag: 'createNovel',
        onPressed: _createProject,
        child: const Icon(Icons.add),
      ),
    );
  }
}
