import 'character.dart';

class NovelProject {
  final String id;
  String title;
  List<Character> characters; // 角色列表
  String worldSetting; // 世界观
  String narratorPrompt; // 旁白专属提示词
  String narratorModelLabel; // 旁白使用的 API 模型标签
  List<Map<String, String>> sceneCards; // 场景卡（可选）
  List<String> eventHistory; // 事件历史（可选）

  NovelProject({
    String? id,
    required this.title,
    List<Character>? characters,
    this.worldSetting = '',
    this.narratorPrompt = '',
    this.narratorModelLabel = '', // 空字符串表示未设置
    List<Map<String, String>>? sceneCards,
    List<String>? eventHistory,
  }) : id = id ?? DateTime.now().millisecondsSinceEpoch.toString(),
       characters = characters ?? [],
       sceneCards = sceneCards ?? [],
       eventHistory = eventHistory ?? [];

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'characters': characters.map((c) => c.toJson()).toList(),
    'worldSetting': worldSetting,
    'narratorPrompt': narratorPrompt,
    'narratorModelLabel': narratorModelLabel,
    'sceneCards': sceneCards,
    'eventHistory': eventHistory,
  };

  factory NovelProject.fromJson(Map<String, dynamic> json) => NovelProject(
    id: json['id'],
    title: json['title'],
    characters: (json['characters'] as List)
        .map((c) => Character.fromJson(c))
        .toList(),
    worldSetting: json['worldSetting'] ?? '',
    narratorPrompt: json['narratorPrompt'] ?? '',
    narratorModelLabel: json['narratorModelLabel'] ?? '',
    sceneCards:
        (json['sceneCards'] as List?)
            ?.map((e) => Map<String, String>.from(e))
            .toList() ??
        [],
    eventHistory: (json['eventHistory'] as List?)?.cast<String>() ?? [],
  );
}
