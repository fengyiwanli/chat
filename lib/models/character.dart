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
  String catchphrase; // 外貌
  String likes; // 喜好
  String dislikes; // 厌恶
  String speakingStyle;
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
    this.speakingStyle = '',
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

    'speakingStyle': speakingStyle,
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
    speakingStyle: json['speakingStyle'] ?? '',
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
