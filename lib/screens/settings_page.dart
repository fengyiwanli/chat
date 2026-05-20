import 'package:flutter/material.dart';
import '../services/storage_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/theme_provider.dart';
import 'dart:convert';

// ==================== 数据模型 ====================

/// API 配置模型
class ApiConfig {
  String label;
  String url;
  String? model;
  String? apiKey;
  String? token;
  String requestType;
  String? bodyTemplate;

  ApiConfig({
    required this.label,
    required this.url,
    this.model,
    this.apiKey,
    this.token,
    this.requestType = 'get',
    this.bodyTemplate,
  });

  factory ApiConfig.fromMap(Map<String, String> map) => ApiConfig(
        label: map['label'] ?? '',
        url: map['url'] ?? '',
        model: map['model'],
        apiKey: map['apiKey'],
        token: map['token'],
        requestType: map['requestType'] ?? 'get',
        bodyTemplate: map['bodyTemplate'],
      );

  Map<String, String> toMap() => {
        'label': label,
        'url': url,
        if (model != null) 'model': model!,
        if (apiKey != null) 'apiKey': apiKey!,
        if (token != null) 'token': token!,
        'requestType': requestType,
        if (bodyTemplate != null) 'bodyTemplate': bodyTemplate!,
      };

  ApiConfig copyWith({
    String? label,
    String? url,
    String? model,
    String? apiKey,
    String? token,
    String? requestType,
    String? bodyTemplate,
  }) =>
      ApiConfig(
        label: label ?? this.label,
        url: url ?? this.url,
        model: model ?? this.model,
        apiKey: apiKey ?? this.apiKey,
        token: token ?? this.token,
        requestType: requestType ?? this.requestType,
        bodyTemplate: bodyTemplate ?? this.bodyTemplate,
      );
}

/// 自定义风格模型
class CustomStyle {
  String id;
  String name;
  String prompt;

  CustomStyle({
    required this.id,
    required this.name,
    required this.prompt,
  });

  factory CustomStyle.create({required String name, required String prompt}) =>
      CustomStyle(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        name: name,
        prompt: prompt,
      );

  Map<String, String> toMap() => {'id': id, 'name': name, 'prompt': prompt};

  factory CustomStyle.fromMap(Map<String, String> map) => CustomStyle(
        id: map['id'] ?? DateTime.now().millisecondsSinceEpoch.toString(),
        name: map['name'] ?? '未命名',
        prompt: map['prompt'] ?? '',
      );

  CustomStyle copyWith({String? name, String? prompt}) => CustomStyle(
        id: id,
        name: name ?? this.name,
        prompt: prompt ?? this.prompt,
      );
}

/// 应用设置数据类
class AppSettings {
  String userName;
  String userPersonality;
  bool showEmotion;
  bool autoSummaryEnabled;
  int autoSummaryThreshold;
  int maxMemoryCount;
  Color themeColor;
  String imagePrefixModifier;
  String imageSuffixModifier;
  String narrationPrompt;
  String branchPrompt;
  String randomEventPrompt;
  String summaryPrompt;
  bool dynamicStatusEnabled;
  String dynamicStatusPrompt;
  String statusPanelTemplate;
  Map<String, bool> statusPanelFields;
  bool highFreqStatusUpdate;
  bool statusAutoExpand;
  bool showClearInputBtn;
  bool imgLinkStatus;

  AppSettings({
    this.userName = '我',
    this.userPersonality = '',
    this.showEmotion = true,
    this.autoSummaryEnabled = false,
    this.autoSummaryThreshold = 20,
    this.maxMemoryCount = 5,
    this.themeColor = Colors.deepPurple,
    this.imagePrefixModifier = '',
    this.imageSuffixModifier = '',
    this.narrationPrompt = '',
    this.branchPrompt = '',
    this.randomEventPrompt = '',
    this.summaryPrompt = '',
    this.dynamicStatusEnabled = false,
    this.dynamicStatusPrompt = '',
    this.statusPanelTemplate = '{{label}}：{{value}}',
    this.statusPanelFields = const {},
    this.highFreqStatusUpdate = true,
    this.statusAutoExpand = false,
    this.showClearInputBtn = true,
    this.imgLinkStatus = true,
  });

  AppSettings copyWith({
    String? userName,
    String? userPersonality,
    bool? showEmotion,
    bool? autoSummaryEnabled,
    int? autoSummaryThreshold,
    int? maxMemoryCount,
    Color? themeColor,
    String? imagePrefixModifier,
    String? imageSuffixModifier,
    String? narrationPrompt,
    String? branchPrompt,
    String? randomEventPrompt,
    String? summaryPrompt,
    bool? dynamicStatusEnabled,
    String? dynamicStatusPrompt,
    String? statusPanelTemplate,
    
    Map<String, bool>? statusPanelFields,
    bool? highFreqStatusUpdate,
    bool? statusAutoExpand,
    bool? showClearInputBtn,
    bool? imgLinkStatus,
  }) =>
      AppSettings(
        userName: userName ?? this.userName,
        userPersonality: userPersonality ?? this.userPersonality,
        showEmotion: showEmotion ?? this.showEmotion,
        autoSummaryEnabled: autoSummaryEnabled ?? this.autoSummaryEnabled,
        autoSummaryThreshold: autoSummaryThreshold ?? this.autoSummaryThreshold,
        maxMemoryCount: maxMemoryCount ?? this.maxMemoryCount,
        themeColor: themeColor ?? this.themeColor,
        imagePrefixModifier: imagePrefixModifier ?? this.imagePrefixModifier,
        imageSuffixModifier: imageSuffixModifier ?? this.imageSuffixModifier,
        narrationPrompt: narrationPrompt ?? this.narrationPrompt,
        branchPrompt: branchPrompt ?? this.branchPrompt,
        randomEventPrompt: randomEventPrompt ?? this.randomEventPrompt,
        summaryPrompt: summaryPrompt ?? this.summaryPrompt,
        dynamicStatusEnabled: dynamicStatusEnabled ?? this.dynamicStatusEnabled,
        dynamicStatusPrompt: dynamicStatusPrompt ?? this.dynamicStatusPrompt,
        statusPanelTemplate: statusPanelTemplate ?? this.statusPanelTemplate,
        statusPanelFields: statusPanelFields ?? this.statusPanelFields,
        highFreqStatusUpdate: highFreqStatusUpdate ?? this.highFreqStatusUpdate,
        statusAutoExpand: statusAutoExpand ?? this.statusAutoExpand,
        showClearInputBtn: showClearInputBtn ?? this.showClearInputBtn,
        imgLinkStatus: imgLinkStatus ?? this.imgLinkStatus,
      );
}

// ==================== 设置控制器 ====================

class SettingsController extends ChangeNotifier {
  final ThemeProvider themeProvider;

  // 设置数据
  late AppSettings settings;
  List<ApiConfig> chatConfigs = [];
  List<ApiConfig> imageConfigs = [];
  String activeImageLabel = '';
  List<CustomStyle> customStyles = [];
  List<CustomStyle> statusStyles = [];

  // 加载状态
  bool isLoading = true;
  String? errorMessage;

  // 文本控制器（持久化避免重建）
  late TextEditingController userNameController;
  late TextEditingController userPersonalityController;
  late TextEditingController imagePrefixController;
  late TextEditingController imageSuffixController;
// ==================== 新增：聊天偏好设置 ====================
bool get highFreqStatusUpdate => settings.highFreqStatusUpdate;
bool get statusAutoExpand => settings.statusAutoExpand;
bool get showClearInputBtn => settings.showClearInputBtn;
bool get imgLinkStatus => settings.imgLinkStatus;

Future<void> updateHighFreqStatusUpdate(bool value) async {
  settings = settings.copyWith(highFreqStatusUpdate: value);
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool('high_freq_status_update', value);
  notifyListeners();
}

Future<void> updateStatusAutoExpand(bool value) async {
  settings = settings.copyWith(statusAutoExpand: value);
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool('status_auto_expand', value);
  notifyListeners();
}

Future<void> updateShowClearInputBtn(bool value) async {
  settings = settings.copyWith(showClearInputBtn: value);
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool('show_clear_input_btn', value);
  notifyListeners();
}

Future<void> updateImgLinkStatus(bool value) async {
  settings = settings.copyWith(imgLinkStatus: value);
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool('img_link_status', value);
  notifyListeners();
}
  SettingsController({required this.themeProvider}) {
    settings = AppSettings();
    _initControllers();
    loadData();
  }

  void _initControllers() {
    userNameController = TextEditingController(text: settings.userName);
    userPersonalityController = TextEditingController(text: settings.userPersonality);
    imagePrefixController = TextEditingController(text: settings.imagePrefixModifier);
    imageSuffixController = TextEditingController(text: settings.imageSuffixModifier);
  }

  void _updateControllers() {
    userNameController.text = settings.userName;
    userPersonalityController.text = settings.userPersonality;
    imagePrefixController.text = settings.imagePrefixModifier;
    imageSuffixController.text = settings.imageSuffixModifier;
  }

  @override
void dispose() {
  // 释放所有文本编辑控制器
  userNameController.dispose();
  userPersonalityController.dispose();
  imagePrefixController.dispose();
  imageSuffixController.dispose();
  super.dispose();
}
  // ==================== 数据加载 ====================

  Future<void> loadData() async {
    isLoading = true;
    errorMessage = null;
    notifyListeners();

    try {
      final prefs = await SharedPreferences.getInstance();

      // 加载提示词
      final narrationPrompt = await StorageService.loadNarrationPrompt();
      final branchPrompt = await StorageService.loadBranchPrompt();
      final randomEventPrompt = await StorageService.loadRandomEventPrompt();
      final summaryPrompt = await StorageService.loadSummaryPrompt();

      // 加载 API 配置
      final chatMaps = await StorageService.loadChatApiConfigs();
      final imageMaps = await StorageService.loadImageApiConfigs();
      final activeLabel = await StorageService.loadActiveImageApiLabel();

      // 加载用户设置
      final userName = await StorageService.loadUserName();
      final userPersonality = await StorageService.loadUserPersonality();
      final prefix = await StorageService.loadImagePrefixModifier();
      final suffix = await StorageService.loadImageSuffixModifier();

      // 加载风格设置
      final customStyleMaps = await StorageService.loadCustomStyles();
      final statusStyleMaps = await StorageService.loadCustomStatusStyles();

      // 加载智能记忆设置
      final autoSummaryEnabled = await StorageService.loadAutoSummaryEnabled();
      final autoSummaryThreshold = await StorageService.loadAutoSummaryThreshold();
      final maxMemoryCount = await StorageService.loadMaxMemoryCount();

      // 加载状态面板设置
      final dynamicStatusEnabled = prefs.getBool('dynamic_status_enabled') ?? false;
      final dynamicStatusPrompt = prefs.getString('dynamic_status_prompt') ?? _defaultStatusPrompt;
      final fieldsJson = prefs.getString('status_panel_fields');
      final statusPanelFields = fieldsJson != null
          ? Map<String, bool>.from(jsonDecode(fieldsJson))
          : _defaultStatusPanelFields;
      final statusPanelTemplate = prefs.getString('status_panel_template') ?? '{{label}}：{{value}}';

      // 加载主题色
      final colorValue = prefs.getInt('theme_color');
      final themeColor = colorValue != null ? Color(colorValue) : Colors.deepPurple;

      // 加载显示设置
      final showEmotion = prefs.getBool('show_emotion') ?? true;
// 👇 新增：加载聊天偏好设置
final highFreqStatusUpdate = prefs.getBool('high_freq_status_update') ?? true;
final statusAutoExpand = prefs.getBool('status_auto_expand') ?? false;
final showClearInputBtn = prefs.getBool('show_clear_input_btn') ?? true;
final imgLinkStatus = prefs.getBool('img_link_status') ?? true;
      // 更新设置
      settings = AppSettings(
        userName: userName,
        userPersonality: userPersonality,
        showEmotion: showEmotion,
        autoSummaryEnabled: autoSummaryEnabled,
        autoSummaryThreshold: autoSummaryThreshold,
        maxMemoryCount: maxMemoryCount,
        themeColor: themeColor,
        imagePrefixModifier: prefix,
        imageSuffixModifier: suffix,
        narrationPrompt: narrationPrompt,
        branchPrompt: branchPrompt,
        randomEventPrompt: randomEventPrompt,
        summaryPrompt: summaryPrompt,
        dynamicStatusEnabled: dynamicStatusEnabled,
        dynamicStatusPrompt: dynamicStatusPrompt,
        statusPanelTemplate: statusPanelTemplate,
        statusPanelFields: statusPanelFields,
        // 👇 新增
  highFreqStatusUpdate: highFreqStatusUpdate,
  statusAutoExpand: statusAutoExpand,
  showClearInputBtn: showClearInputBtn,
  imgLinkStatus: imgLinkStatus,
      );

      // 更新列表数据
      chatConfigs = chatMaps.map(ApiConfig.fromMap).toList();
      imageConfigs = imageMaps.map(ApiConfig.fromMap).toList();
      activeImageLabel = activeLabel;
      customStyles = customStyleMaps.map(CustomStyle.fromMap).toList();
      statusStyles = statusStyleMaps.map(CustomStyle.fromMap).toList();

      // 应用主题色
      themeProvider.setSeedColor(themeColor);
      _updateControllers();

      isLoading = false;
      notifyListeners();
    } catch (e) {
      isLoading = false;
      errorMessage = '加载设置失败: $e';
      notifyListeners();
    }
  }

  // ==================== 设置更新方法 ====================

  Future<void> updateUserName(String value) async {
    settings = settings.copyWith(userName: value);
    await StorageService.saveUserName(value);
    notifyListeners();
  }

  Future<void> updateUserPersonality(String value) async {
    settings = settings.copyWith(userPersonality: value);
    await StorageService.saveUserPersonality(value);
    notifyListeners();
  }

  Future<void> updateShowEmotion(bool value) async {
    settings = settings.copyWith(showEmotion: value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('show_emotion', value);
    notifyListeners();
  }

  Future<void> updateThemeColor(Color color) async {
    settings = settings.copyWith(themeColor: color);
    themeProvider.setSeedColor(color);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('theme_color', color.value);  // 改为 .value
    notifyListeners();
  }

  Future<void> updateImagePrefix(String value) async {
    settings = settings.copyWith(imagePrefixModifier: value);
    await StorageService.saveImagePrefixModifier(value);
    notifyListeners();
  }

  Future<void> updateImageSuffix(String value) async {
    settings = settings.copyWith(imageSuffixModifier: value);
    await StorageService.saveImageSuffixModifier(value);
    notifyListeners();
  }

  Future<void> updateAutoSummaryEnabled(bool value) async {
    settings = settings.copyWith(autoSummaryEnabled: value);
    await StorageService.saveAutoSummaryEnabled(value);
    notifyListeners();
  }

  Future<void> updateAutoSummaryThreshold(int value) async {
    settings = settings.copyWith(autoSummaryThreshold: value);
    await StorageService.saveAutoSummaryThreshold(value);
    notifyListeners();
  }

  Future<void> updateMaxMemoryCount(int value) async {
    settings = settings.copyWith(maxMemoryCount: value);
    await StorageService.saveMaxMemoryCount(value);
    notifyListeners();
  }

  Future<void> updateDynamicStatusEnabled(bool value) async {
    settings = settings.copyWith(dynamicStatusEnabled: value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('dynamic_status_enabled', value);
    notifyListeners();
  }

  Future<void> updateDynamicStatusPrompt(String value) async {
    settings = settings.copyWith(dynamicStatusPrompt: value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('dynamic_status_prompt', value);
    notifyListeners();
  }

  Future<void> updateStatusPanelTemplate(String value) async {
    settings = settings.copyWith(statusPanelTemplate: value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('status_panel_template', value);
    notifyListeners();
  }

  Future<void> updateStatusPanelField(String field, bool value) async {
    final newFields = Map<String, bool>.from(settings.statusPanelFields);
    newFields[field] = value;
    settings = settings.copyWith(statusPanelFields: newFields);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('status_panel_fields', jsonEncode(newFields));
    notifyListeners();
  }

  // ==================== 提示词更新 ====================

  Future<void> updateNarrationPrompt(String value) async {
    settings = settings.copyWith(narrationPrompt: value);
    await StorageService.saveNarrationPrompt(value);
    notifyListeners();
  }

  Future<void> updateBranchPrompt(String value) async {
    settings = settings.copyWith(branchPrompt: value);
    await StorageService.saveBranchPrompt(value);
    notifyListeners();
  }

  Future<void> updateRandomEventPrompt(String value) async {
    settings = settings.copyWith(randomEventPrompt: value);
    await StorageService.saveRandomEventPrompt(value);
    notifyListeners();
  }

  Future<void> updateSummaryPrompt(String value) async {
    settings = settings.copyWith(summaryPrompt: value);
    await StorageService.saveSummaryPrompt(value);
    notifyListeners();
  }

  // ==================== API 配置管理 ====================

  Future<void> addChatConfig(ApiConfig config) async {
    chatConfigs.add(config);
    await StorageService.saveChatApiConfigs(
      chatConfigs.map((c) => c.toMap()).toList(),
    );
    notifyListeners();
  }

  Future<void> updateChatConfig(int index, ApiConfig config) async {
    chatConfigs[index] = config;
    await StorageService.saveChatApiConfigs(
      chatConfigs.map((c) => c.toMap()).toList(),
    );
    notifyListeners();
  }

  Future<void> deleteChatConfig(int index) async {
    chatConfigs.removeAt(index);
    await StorageService.saveChatApiConfigs(
      chatConfigs.map((c) => c.toMap()).toList(),
    );
    notifyListeners();
  }

  Future<void> addImageConfig(ApiConfig config) async {
    imageConfigs.add(config);
    await StorageService.saveImageApiConfigs(
      imageConfigs.map((c) => c.toMap()).toList(),
    );
    notifyListeners();
  }

  Future<void> updateImageConfig(int index, ApiConfig config) async {
    final oldLabel = imageConfigs[index].label;
    imageConfigs[index] = config;
    await StorageService.saveImageApiConfigs(
      imageConfigs.map((c) => c.toMap()).toList(),
    );
    // 如果修改的是当前激活的配置，更新激活标签
    if (activeImageLabel == oldLabel) {
      activeImageLabel = config.label;
      await StorageService.saveActiveImageApiLabel(config.label);
    }
    notifyListeners();
  }

  Future<void> deleteImageConfig(int index) async {
    final label = imageConfigs[index].label;
    imageConfigs.removeAt(index);
    await StorageService.saveImageApiConfigs(
      imageConfigs.map((c) => c.toMap()).toList(),
    );
    if (activeImageLabel == label) {
      activeImageLabel = '';
      await StorageService.saveActiveImageApiLabel('');
    }
    notifyListeners();
  }

  Future<void> setActiveImageApi(String? label) async {
    activeImageLabel = label ?? '';
    await StorageService.saveActiveImageApiLabel(activeImageLabel);
    notifyListeners();
  }

  // ==================== 风格管理 ====================

  Future<void> addCustomStyle(String name, String prompt) async {
    final style = CustomStyle.create(name: name, prompt: prompt);
    customStyles.add(style);
    await StorageService.saveCustomStyles(
      customStyles.map((s) => s.toMap()).toList(),
    );
    notifyListeners();
  }

  Future<void> updateCustomStyle(int index, String name, String prompt) async {
    customStyles[index] = customStyles[index].copyWith(name: name, prompt: prompt);
    await StorageService.saveCustomStyles(
      customStyles.map((s) => s.toMap()).toList(),
    );
    notifyListeners();
  }

  Future<void> deleteCustomStyle(int index) async {
    customStyles.removeAt(index);
    await StorageService.saveCustomStyles(
      customStyles.map((s) => s.toMap()).toList(),
    );
    notifyListeners();
  }

  Future<void> addStatusStyle(String name, String prompt) async {
    final style = CustomStyle.create(name: name, prompt: prompt);
    statusStyles.add(style);
    await StorageService.saveCustomStatusStyles(
      statusStyles.map((s) => s.toMap()).toList(),
    );
    notifyListeners();
  }

  Future<void> updateStatusStyle(int index, String name, String prompt) async {
    statusStyles[index] = statusStyles[index].copyWith(name: name, prompt: prompt);
    await StorageService.saveCustomStatusStyles(
      statusStyles.map((s) => s.toMap()).toList(),
    );
    notifyListeners();
  }

  Future<void> deleteStatusStyle(int index) async {
    statusStyles.removeAt(index);
    await StorageService.saveCustomStatusStyles(
      statusStyles.map((s) => s.toMap()).toList(),
    );
    notifyListeners();
  }

  // ==================== 默认值 ====================

  static const _defaultStatusPrompt =
      '请以生动的文学语言描述角色的当前状态，用JSON返回，字段名固定为：attire（着装）、catchphrase（外貌）、personality（性格）、speakingStyle（说话风格）。每个字段的值应是一段自然描述，而不是简单词语。例如：\n'
      '{"attire":"她穿着修身的白色校服，领口系着蝴蝶结，深蓝色百褶裙在微风中轻轻摆动，白色的及膝袜包裹着纤细的小腿","catchphrase":"一头乌黑的长直发，眼眸清澈，五官精致","personality":"外表文静，内心活泼，略带傲娇","speakingStyle":"语调轻柔，偶尔带点任性的上扬"}';

  static const _defaultStatusPanelFields = {
    'attire': true,
    'catchphrase': true,
    'personality': true,
    'speakingStyle': true,
    'emotion': true,
    'relation': true,
  };
}

// ==================== UI 组件 ====================

class SettingsPage extends StatefulWidget {
  final ThemeProvider themeProvider;

  const SettingsPage({super.key, required this.themeProvider});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late SettingsController _controller;
// 聊天偏好设置
bool _highFreqStatusUpdate = true;
bool _statusAutoExpand = false;
bool _showClearInputBtn = true;
bool _imgLinkStatus = true;
// 加载设置
// 👇 替换成主题包设置
  int _currentThemeIndex = 0;
  Future<void> _loadChatSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _highFreqStatusUpdate = prefs.getBool('high_freq_status_update') ?? true;
      _statusAutoExpand = prefs.getBool('status_auto_expand') ?? false;
      _showClearInputBtn = prefs.getBool('show_clear_input_btn') ?? true;
      _imgLinkStatus = prefs.getBool('img_link_status') ?? true;
      _currentThemeIndex = prefs.getInt('app_theme_index') ?? 0;
      _applyTheme(_presetThemes[_currentThemeIndex]);
    });
  }
// 👇 新增：应用主题
// 应用主题（自动文字颜色，完美明暗适配）
void _applyTheme(AppTheme theme) {
  final isDark = theme.brightness == Brightness.dark;

  widget.themeProvider.setThemeData(
    ThemeData(
      brightness: theme.brightness,
      primaryColor: theme.primary,
      colorScheme: ColorScheme(
        brightness: theme.brightness,
        primary: theme.primary,
        onPrimary: Colors.white,
        secondary: theme.secondary,
        onSecondary: Colors.white,
        background: theme.background,
        onBackground: isDark ? Colors.white : Color(0xFF1E293B),
        surface: theme.surface,
        onSurface: isDark ? Colors.white : Color(0xFF1E293B),
        error: Colors.red,
        onError: Colors.white,
      ),
      scaffoldBackgroundColor: theme.background,
      cardColor: theme.surface,
      useMaterial3: true,

      // ✅ 自动文字颜色（核心！）
      textTheme: TextTheme(
        bodyLarge: TextStyle(
          color: isDark ? Colors.white : Color(0xFF1E293B),
          fontSize: 16,
        ),
        bodyMedium: TextStyle(
          color: isDark ? Color(0xFFE0E0E0) : Color(0xFF475569),
          fontSize: 15,
        ),
        titleLarge: TextStyle(
          color: isDark ? Colors.white : Color(0xFF1E293B),
          fontSize: 20,
          fontWeight: FontWeight.w600,
        ),
      ),

      // ✅ 图标自动变色
      iconTheme: IconThemeData(
        color: isDark ? Colors.white : Color(0xFF1E293B),
      ),

      // ✅ AppBar自动变色
      appBarTheme: AppBarTheme(
        backgroundColor: theme.background,
        foregroundColor: isDark ? Colors.white : Color(0xFF1E293B),
        titleTextStyle: TextStyle(
          color: isDark ? Colors.white : Color(0xFF1E293B),
          fontSize: 20,
          fontWeight: FontWeight.w600,
        ),
        iconTheme: IconThemeData(
          color: isDark ? Colors.white : Color(0xFF1E293B),
        ),
      ),
    ),
  );
}
// 精准色板
MaterialColor _createMaterialColor(Color color) {
  return MaterialColor(color.value, {
    50: color.withOpacity(0.1),
    100: color.withOpacity(0.2),
    200: color.withOpacity(0.3),
    300: color.withOpacity(0.4),
    400: color.withOpacity(0.5),
    500: color.withOpacity(0.6),
    600: color.withOpacity(0.7),
    700: color.withOpacity(0.8),
    800: color.withOpacity(0.9),
    900: color.withOpacity(1),
  });
}

  // 👇 新增：更新主题
  Future<void> _updateTheme(int index) async {
    setState(() {
      _currentThemeIndex = index;
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('app_theme_index', index);
    _applyTheme(_presetThemes[index]);
  }
  // 保存设置
  Future<void> _saveSetting(String key, bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, value);
  }
  @override
  void initState() {
    super.initState();
    _loadChatSettings(); // 加载聊天偏好设置
    _controller = SettingsController(themeProvider: widget.themeProvider);
    _controller.addListener(_onControllerUpdate);
  }

  @override
  void dispose() {
    _controller.removeListener(_onControllerUpdate);
    _controller.dispose();
    super.dispose();
  }

  void _onControllerUpdate() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_controller.isLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text('设置'), centerTitle: true),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_controller.errorMessage != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('设置'), centerTitle: true),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline, size: 48, color: theme.colorScheme.error),
              const SizedBox(height: 16),
              Text(_controller.errorMessage!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _controller.loadData,
                child: const Text('重试'),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('设置'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _controller.loadData,
            tooltip: '刷新',
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          // 用户设定
          _UserProfileSection(controller: _controller),

          const Divider(height: 32, indent: 16, endIndent: 16),

          // 提示词编辑
          _PromptSection(controller: _controller),

          const Divider(height: 16, indent: 16, endIndent: 16),

          // API 配置
          _ApiConfigSection(controller: _controller),

          const Divider(height: 16, indent: 16, endIndent: 16),

          // 风格与面板
          _StyleSection(controller: _controller),

          const Divider(height: 16, indent: 16, endIndent: 16),

          // 智能记忆
          _MemorySection(controller: _controller),

          const Divider(height: 16, indent: 16, endIndent: 16),
ExpansionTile(
  leading: const Icon(Icons.tune),
  title: const Text(
    '聊天偏好设置',
    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
  ),
  initiallyExpanded: false, // 默认收起，节省空间
  children: [
    SwitchListTile(
      title: const Text('高频更新角色状态'),
      subtitle: const Text('每轮对话自动更新角色状态'),
      value: _highFreqStatusUpdate,
      onChanged: (value) {
        setState(() {
          _highFreqStatusUpdate = value;
          _saveSetting('high_freq_status_update', value);
        });
      },
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
    ),
    SwitchListTile(
      title: const Text('状态默认展开'),
      subtitle: const Text('消息的角色状态默认展开显示'),
      value: _statusAutoExpand,
      onChanged: (value) {
        setState(() {
          _statusAutoExpand = value;
          _saveSetting('status_auto_expand', value);
        });
      },
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
    ),
    SwitchListTile(
      title: const Text('输入框清空按钮'),
      subtitle: const Text('显示一键清空输入内容按钮'),
      value: _showClearInputBtn,
      onChanged: (value) {
        setState(() {
          _showClearInputBtn = value;
          _saveSetting('show_clear_input_btn', value);
        });
      },
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
    ),
    SwitchListTile(
      title: const Text('图片生成联动状态'),
      subtitle: const Text('根据角色状态生成对应风格图片'),
      value: _imgLinkStatus,
      onChanged: (value) {
        setState(() {
          _imgLinkStatus = value;
          _saveSetting('img_link_status', value);
        });
      },
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
    ),
    const SizedBox(height: 8),
  ],
),

          // 图片修饰词
          _ImageModifierSection(controller: _controller),

          const SizedBox(height: 16),

const SizedBox(height: 8),



// 主题设置（可折叠，极致紧凑版）
ExpansionTile(
  leading: Icon(Icons.color_lens),
  title: Text(
    '主题设置',
    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
  ),
  initiallyExpanded: false,
  children: [
    Padding(
      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: GridView.builder(
        shrinkWrap: true,
        physics: NeverScrollableScrollPhysics(),
        // 👇 4列布局，每个按钮宽高比2:1
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 4,
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          childAspectRatio: 2.0,
        ),
        itemCount: _presetThemes.length,
        itemBuilder: (_, i) => _ThemePreviewCard(
          theme: _presetThemes[i],
          isSelected: _currentThemeIndex == i,
          onTap: () => _updateTheme(i),
        ),
      ),
    ),
    SizedBox(height: 8),
  ],
),

SizedBox(height: 32),
SizedBox(height: 32),
SizedBox(height: 32), // 去掉const



const SizedBox(height: 32),
const SizedBox(height: 32),
const SizedBox(height: 32),
        ],
      ),
    );
  }
}

// ==================== 分区组件 ====================

class _UserProfileSection extends StatelessWidget {
  final SettingsController controller;

  const _UserProfileSection({required this.controller});

  @override
  Widget build(BuildContext context) {
    return _SettingsCard(
      title: '你的设定',
      icon: Icons.person_outline,
      children: [
        TextField(
          decoration: const InputDecoration(
            labelText: '名字',
            hintText: '输入你在故事中的名字',
            prefixIcon: Icon(Icons.badge_outlined),
          ),
          controller: controller.userNameController,
          onChanged: controller.updateUserName,
        ),
        const SizedBox(height: 16),
        TextField(
          decoration: const InputDecoration(
            labelText: '性格',
            hintText: '例如：冷静、果断、喜欢吐槽',
            prefixIcon: Icon(Icons.psychology_outlined),
          ),
          controller: controller.userPersonalityController,
          onChanged: controller.updateUserPersonality,
        ),
        const SizedBox(height: 8),
        SwitchListTile(
          title: const Text('显示情感表情'),
          subtitle: const Text('关闭后可节省少量 token'),
          value: controller.settings.showEmotion,
          onChanged: controller.updateShowEmotion,
          contentPadding: EdgeInsets.zero,
        ),
      ],
    );
  }
}

class _PromptSection extends StatelessWidget {
  final SettingsController controller;

  const _PromptSection({required this.controller});

  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      leading: const Icon(Icons.edit_note),
      title: const Text(
        '提示词编辑',
        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
      initiallyExpanded: false,
      children: [
        _PromptEditorTile(
          label: '旁白提示词',
          value: controller.settings.narrationPrompt,
          defaultValue: StorageService.defaultNarrationPrompt,
          onSave: controller.updateNarrationPrompt,
        ),
        _PromptEditorTile(
          label: '分支选项提示词',
          value: controller.settings.branchPrompt,
          defaultValue: StorageService.defaultBranchPrompt,
          onSave: controller.updateBranchPrompt,
        ),
        _PromptEditorTile(
          label: '随机事件提示词',
          value: controller.settings.randomEventPrompt,
          defaultValue: StorageService.defaultRandomEventPrompt,
          onSave: controller.updateRandomEventPrompt,
        ),
        _PromptEditorTile(
          label: '剧情统计提示词',
          value: controller.settings.summaryPrompt,
          defaultValue: StorageService.defaultSummaryPrompt,
          onSave: controller.updateSummaryPrompt,
        ),
      ],
    );
  }
}

class _ApiConfigSection extends StatelessWidget {
  final SettingsController controller;

  const _ApiConfigSection({required this.controller});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // 对话 API
        ExpansionTile(
          leading: const Icon(Icons.chat_bubble_outline),
          title: const Text(
            '对话 API 配置',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          subtitle: Text(
            '${controller.chatConfigs.length} 个配置',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
          ),
          children: [
            _ApiConfigList(
              configs: controller.chatConfigs,
              onEdit: (index) => _showChatConfigDialog(context, index),
              onDelete: controller.deleteChatConfig,
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: ElevatedButton.icon(
                onPressed: () => _showChatConfigDialog(context, -1),
                icon: const Icon(Icons.add),
                label: const Text('添加对话 API'),
              ),
            ),
          ],
        ),

        // 图片 API
        ExpansionTile(
          leading: const Icon(Icons.image_outlined),
          title: const Text(
            '图片生成 API',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          subtitle: Text(
            '${controller.imageConfigs.length} 个配置',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
          ),
          children: [
            if (controller.imageConfigs.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: DropdownButtonFormField<String?>(
                  value: controller.imageConfigs.any((c) => c.label == controller.activeImageLabel)
                      ? controller.activeImageLabel
                      : null,
                  decoration: const InputDecoration(
                    labelText: '当前使用的图片 API',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('不启用')),
                    ...controller.imageConfigs.map(
                      (c) => DropdownMenuItem(value: c.label, child: Text(c.label)),
                    ),
                  ],
                  onChanged: (v) => controller.setActiveImageApi(v),
                ),
              ),
            _ApiConfigList(
              configs: controller.imageConfigs,
              onEdit: (index) => _showImageConfigDialog(context, index),
              onDelete: controller.deleteImageConfig,
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: ElevatedButton.icon(
                onPressed: () => _showImageConfigDialog(context, -1),
                icon: const Icon(Icons.add),
                label: const Text('添加图片 API'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  void _showChatConfigDialog(BuildContext context, int index) {
    final isNew = index < 0;
    final config = isNew ? null : controller.chatConfigs[index];

    showDialog(
      context: context,
      builder: (ctx) => _ChatConfigDialog(
        config: config,
        onSave: (newConfig) {
          if (isNew) {
            controller.addChatConfig(newConfig);
          } else {
            controller.updateChatConfig(index, newConfig);
          }
        },
      ),
    );
  }

  void _showImageConfigDialog(BuildContext context, int index) {
    final isNew = index < 0;
    final config = isNew ? null : controller.imageConfigs[index];

    showDialog(
      context: context,
      builder: (ctx) => _ImageConfigDialog(
        config: config,
        onSave: (newConfig) {
          if (isNew) {
            controller.addImageConfig(newConfig);
          } else {
            controller.updateImageConfig(index, newConfig);
          }
        },
      ),
    );
  }
}

class _StyleSection extends StatelessWidget {
  final SettingsController controller;

  const _StyleSection({required this.controller});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // 回复风格
        ExpansionTile(
          leading: const Icon(Icons.style_outlined),
          title: const Text(
            '回复风格',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          subtitle: Text(
            '${controller.customStyles.length} 个风格',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
          ),
          children: [
            _StyleList(
              styles: controller.customStyles,
              onEdit: (index) => _showStyleDialog(
                context,
                index: index,
                isStatusStyle: false,
              ),
              onDelete: controller.deleteCustomStyle,
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: ElevatedButton.icon(
                onPressed: () => _showStyleDialog(context, index: -1, isStatusStyle: false),
                icon: const Icon(Icons.add),
                label: const Text('添加新风格'),
              ),
            ),
          ],
        ),

        // 角色状态面板
        ExpansionTile(
          leading: const Icon(Icons.dashboard_outlined),
          title: const Text(
            '角色状态面板',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          children: [
            ListTile(
              title: const Text('显示格式模板'),
              subtitle: const Text('使用 {{label}} 和 {{value}} 占位符'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _showTemplateEditor(context),
            ),
            SwitchListTile(
              title: const Text('AI 动态生成状态描述'),
              subtitle: const Text('开启后每次AI回复会重新描写状态（消耗Token）'),
              value: controller.settings.dynamicStatusEnabled,
              onChanged: controller.updateDynamicStatusEnabled,
            ),
            ListTile(
              title: const Text('状态描写提示词'),
              subtitle: const Text('编辑提示词以控制描述风格'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _showStatusPromptEditor(context),
            ),
          ],
        ),

        // 状态描写风格
        ExpansionTile(
          leading: const Icon(Icons.palette_outlined),
          title: const Text(
            '状态描写风格',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          subtitle: Text(
            '${controller.statusStyles.length} 个风格',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
          ),
          children: [
            _StyleList(
              styles: controller.statusStyles,
              onEdit: (index) => _showStyleDialog(
                context,
                index: index,
                isStatusStyle: true,
              ),
              onDelete: controller.deleteStatusStyle,
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: ElevatedButton.icon(
                onPressed: () => _showStyleDialog(context, index: -1, isStatusStyle: true),
                icon: const Icon(Icons.add),
                label: const Text('添加新状态风格'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  void _showTemplateEditor(BuildContext context) {
    final ctrl = TextEditingController(text: controller.settings.statusPanelTemplate);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('状态面板模板'),
        content: TextField(
          controller: ctrl,
          maxLines: 3,
          decoration: const InputDecoration(
            hintText: '例如：{{label}}：{{value}}',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              controller.updateStatusPanelTemplate(ctrl.text);
              Navigator.pop(ctx);
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }

  void _showStatusPromptEditor(BuildContext context) {
    final ctrl = TextEditingController(text: controller.settings.dynamicStatusPrompt);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('状态描写提示词'),
        content: TextField(
          controller: ctrl,
          maxLines: 10,
          decoration: const InputDecoration(
            hintText: '例如：以细腻的笔触描述角色的着装和外貌...',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              controller.updateDynamicStatusPrompt(ctrl.text);
              Navigator.pop(ctx);
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }

  void _showStyleDialog(
    BuildContext context, {
    required int index,
    required bool isStatusStyle,
  }) {
    final isNew = index < 0;
    final style = isNew
        ? null
        : (isStatusStyle ? controller.statusStyles[index] : controller.customStyles[index]);

    showDialog(
      context: context,
      builder: (ctx) => _StyleDialog(
        style: style,
        isStatusStyle: isStatusStyle,
        onSave: (name, prompt) {
          if (isStatusStyle) {
            if (isNew) {
              controller.addStatusStyle(name, prompt);
            } else {
              controller.updateStatusStyle(index, name, prompt);
            }
          } else {
            if (isNew) {
              controller.addCustomStyle(name, prompt);
            } else {
              controller.updateCustomStyle(index, name, prompt);
            }
          }
        },
      ),
    );
  }
}

class _MemorySection extends StatelessWidget {
  final SettingsController controller;

  const _MemorySection({required this.controller});

  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      leading: const Icon(Icons.memory_outlined),
      title: const Text(
        '智能记忆',
        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
      children: [
        SwitchListTile(
          title: const Text('自动生成记忆摘要'),
          subtitle: const Text('当新消息达到一定数量时自动总结'),
          value: controller.settings.autoSummaryEnabled,
          onChanged: controller.updateAutoSummaryEnabled,
        ),
        ListTile(
          title: const Text('触发摘要的新消息数'),
          subtitle: Slider(
            value: controller.settings.autoSummaryThreshold.toDouble(),
            min: 10,
            max: 100,
            divisions: 9,
            label: '${controller.settings.autoSummaryThreshold}条',
            onChanged: (v) => controller.updateAutoSummaryThreshold(v.toInt()),
          ),
        ),
        ListTile(
          title: const Text('最多保留记忆条数'),
          subtitle: Slider(
            value: controller.settings.maxMemoryCount.toDouble(),
            min: 1,
            max: 20,
            divisions: 19,
            label: '${controller.settings.maxMemoryCount}条',
            onChanged: (v) => controller.updateMaxMemoryCount(v.toInt()),
          ),
        ),
      ],
    );
  }
}

class _ImageModifierSection extends StatelessWidget {
  final SettingsController controller;

  const _ImageModifierSection({required this.controller});

  @override
  Widget build(BuildContext context) {
    return _SettingsCard(
      title: '图片修饰词（全局）',
      icon: Icons.tune,
      children: [
        TextField(
          decoration: const InputDecoration(
            labelText: '前置修饰词',
            hintText: '例如：anime style, soft lighting',
            prefixIcon: Icon(Icons.arrow_forward),
          ),
          controller: controller.imagePrefixController,
          onChanged: controller.updateImagePrefix,
        ),
        const SizedBox(height: 16),
        TextField(
          decoration: const InputDecoration(
            labelText: '后置修饰词',
            hintText: '例如：high quality, no text',
            prefixIcon: Icon(Icons.arrow_back),
          ),
          controller: controller.imageSuffixController,
          onChanged: controller.updateImageSuffix,
        ),
      ],
    );
  }
}


// ==================== 通用组件 ====================

class _SettingsCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<Widget> children;

  const _SettingsCard({
    required this.title,
    required this.icon,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ],
            ),
            const SizedBox(height: 16),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _PromptEditorTile extends StatefulWidget {
  final String label;
  final String value;
  final String defaultValue;
  final ValueChanged<String> onSave;

  const _PromptEditorTile({
    required this.label,
    required this.value,
    required this.defaultValue,
    required this.onSave,
  });

  @override
  State<_PromptEditorTile> createState() => _PromptEditorTileState();
}

class _PromptEditorTileState extends State<_PromptEditorTile> {
  late TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.value);
  }

  @override
  void didUpdateWidget(covariant _PromptEditorTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != oldWidget.value) {
      _controller.text = widget.value;
      // 将光标移到末尾
      _controller.selection = TextSelection.fromPosition(
        TextPosition(offset: _controller.text.length),
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ListTile(
            title: Text(widget.label, style: const TextStyle(fontWeight: FontWeight.w600)),
            trailing: TextButton(
              onPressed: () {
                widget.onSave(widget.defaultValue);
                _controller.text = widget.defaultValue;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('已恢复默认${widget.label}')),
                );
              },
              child: const Text('恢复默认'),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              '留空则使用系统默认提示词',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: TextField(
              controller: _controller,
              maxLines: 3,
              minLines: 2,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: '编辑...',
              ),
              onChanged: widget.onSave,
            ),
          ),
        ],
      ),
    );
  }
}
class _ApiConfigList extends StatelessWidget {
  final List<ApiConfig> configs;
  final ValueChanged<int> onEdit;
  final ValueChanged<int> onDelete;

  const _ApiConfigList({
    required this.configs,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    if (configs.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Center(
          child: Text('暂无配置', style: TextStyle(color: Colors.grey)),
        ),
      );
    }

    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: configs.length,
      itemBuilder: (context, i) {
        final config = configs[i];
        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: ListTile(
            title: Text(config.label),
            subtitle: Text(config.model != null ? '${config.model} - ${config.url}' : config.url),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.edit_outlined),
                  onPressed: () => onEdit(i),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline, color: Colors.red),
                  onPressed: () => _showDeleteConfirm(context, i),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showDeleteConfirm(BuildContext context, int index) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认删除'),
        content: const Text('确定要删除这个 API 配置吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              onDelete(index);
              Navigator.pop(ctx);
            },
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }
}

class _StyleList extends StatelessWidget {
  final List<CustomStyle> styles;
  final ValueChanged<int> onEdit;
  final ValueChanged<int> onDelete;

  const _StyleList({
    required this.styles,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    if (styles.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Center(
          child: Text('暂无风格', style: TextStyle(color: Colors.grey)),
        ),
      );
    }

    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: styles.length,
      itemBuilder: (context, i) {
        final style = styles[i];
        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: ListTile(
            title: Text(style.name),
            subtitle: Text(
              style.prompt,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.edit_outlined),
                  onPressed: () => onEdit(i),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline, color: Colors.red),
                  onPressed: () => _showDeleteConfirm(context, i),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showDeleteConfirm(BuildContext context, int index) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认删除'),
        content: const Text('确定要删除这个风格吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              onDelete(index);
              Navigator.pop(ctx);
            },
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }
}

class _ColorPickerItem extends StatelessWidget {
  final Color color;
  final bool isSelected;
  final VoidCallback onTap;

  const _ColorPickerItem({
    required this.color,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: isSelected
              ? Border.all(width: 3, color: Colors.white)
              : null,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.2),
              blurRadius: isSelected ? 4 : 2,
              spreadRadius: isSelected ? 1 : 0,
            ),
          ],
        ),
        child: isSelected
            ? const Icon(Icons.check, color: Colors.white, size: 16)
            : null,
      ),
    );
  }
}

// ==================== 对话框组件 ====================

class _ChatConfigDialog extends StatefulWidget {
  final ApiConfig? config;
  final ValueChanged<ApiConfig> onSave;

  const _ChatConfigDialog({this.config, required this.onSave});

  @override
  State<_ChatConfigDialog> createState() => _ChatConfigDialogState();
}

class _ChatConfigDialogState extends State<_ChatConfigDialog> {
  late final TextEditingController _labelCtrl;
  late final TextEditingController _urlCtrl;
  late final TextEditingController _modelCtrl;
  late final TextEditingController _keyCtrl;
  final _formKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    _labelCtrl = TextEditingController(text: widget.config?.label ?? '');
    _urlCtrl = TextEditingController(text: widget.config?.url ?? '');
    _modelCtrl = TextEditingController(text: widget.config?.model ?? '');
    _keyCtrl = TextEditingController(text: widget.config?.apiKey ?? '');
  }

  @override
  void dispose() {
    _labelCtrl.dispose();
    _urlCtrl.dispose();
    _modelCtrl.dispose();
    _keyCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.config == null ? '添加对话 API' : '编辑对话 API'),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _labelCtrl,
                decoration: const InputDecoration(
                  labelText: '标签',
                  hintText: '如 deepseek',
                ),
                validator: (v) => v?.isEmpty == true ? '请输入标签' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _urlCtrl,
                decoration: const InputDecoration(
                  labelText: 'API 地址',
                  hintText: 'https://api.example.com/v1/chat',
                ),
                validator: (v) => v?.isEmpty == true ? '请输入 API 地址' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _modelCtrl,
                decoration: const InputDecoration(
                  labelText: '模型名',
                  hintText: '如 gpt-4',
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _keyCtrl,
                decoration: const InputDecoration(
                  labelText: 'API Key',
                ),
                obscureText: true,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _save,
          child: const Text('保存'),
        ),
      ],
    );
  }

  void _save() {
    if (_formKey.currentState?.validate() != true) return;
    widget.onSave(ApiConfig(
      label: _labelCtrl.text.trim(),
      url: _urlCtrl.text.trim(),
      model: _modelCtrl.text.trim().isEmpty ? null : _modelCtrl.text.trim(),
      apiKey: _keyCtrl.text.trim().isEmpty ? null : _keyCtrl.text.trim(),
    ));
    Navigator.pop(context);
  }
}

class _ImageConfigDialog extends StatefulWidget {
  final ApiConfig? config;
  final ValueChanged<ApiConfig> onSave;

  const _ImageConfigDialog({this.config, required this.onSave});

  @override
  State<_ImageConfigDialog> createState() => _ImageConfigDialogState();
}

class _ImageConfigDialogState extends State<_ImageConfigDialog> {
  late final TextEditingController _labelCtrl;
  late final TextEditingController _urlCtrl;
  late final TextEditingController _tokenCtrl;
  late final TextEditingController _bodyCtrl;
  late String _requestType;
  final _formKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    _labelCtrl = TextEditingController(text: widget.config?.label ?? '');
    _urlCtrl = TextEditingController(text: widget.config?.url ?? '');
    _tokenCtrl = TextEditingController(text: widget.config?.token ?? '');
    _bodyCtrl = TextEditingController(text: widget.config?.bodyTemplate ?? '');
    _requestType = widget.config?.requestType ?? 'get';
  }

  @override
  void dispose() {
    _labelCtrl.dispose();
    _urlCtrl.dispose();
    _tokenCtrl.dispose();
    _bodyCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.config == null ? '添加图片 API' : '编辑图片 API'),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _labelCtrl,
                decoration: const InputDecoration(
                  labelText: '标签',
                  hintText: '如 DeepAI',
                ),
                validator: (v) => v?.isEmpty == true ? '请输入标签' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _urlCtrl,
                decoration: const InputDecoration(
                  labelText: 'API 地址',
                ),
                validator: (v) => v?.isEmpty == true ? '请输入 API 地址' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _tokenCtrl,
                decoration: const InputDecoration(
                  labelText: 'Token (可选)',
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: _requestType,
                decoration: const InputDecoration(labelText: '请求方式'),
                items: ['get', 'post']
                    .map((e) => DropdownMenuItem(value: e, child: Text(e.toUpperCase())))
                    .toList(),
                onChanged: (v) => setState(() => _requestType = v!),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _bodyCtrl,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: '请求体 JSON ({{prompt}} 占位)',
                  hintText: '{"text":"{{prompt}}"}',
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _save,
          child: const Text('保存'),
        ),
      ],
    );
  }

  void _save() {
    if (_formKey.currentState?.validate() != true) return;
    widget.onSave(ApiConfig(
      label: _labelCtrl.text.trim(),
      url: _urlCtrl.text.trim(),
      token: _tokenCtrl.text.trim().isEmpty ? null : _tokenCtrl.text.trim(),
      requestType: _requestType,
      bodyTemplate: _bodyCtrl.text.trim().isEmpty ? null : _bodyCtrl.text.trim(),
    ));
    Navigator.pop(context);
  }
}

class _StyleDialog extends StatefulWidget {
  final CustomStyle? style;
  final bool isStatusStyle;
  final void Function(String name, String prompt) onSave;

  const _StyleDialog({
    this.style,
    required this.isStatusStyle,
    required this.onSave,
  });

  @override
  State<_StyleDialog> createState() => _StyleDialogState();
}

class _StyleDialogState extends State<_StyleDialog> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _promptCtrl;
  final _formKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.style?.name ?? '');
    _promptCtrl = TextEditingController(
      text: widget.style?.prompt ?? _defaultPrompt,
    );
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _promptCtrl.dispose();
    super.dispose();
  }

  String get _defaultPrompt => widget.isStatusStyle
      ? '请根据角色当前状态，为以下字段生成生动自然的描述，用 JSON 格式返回，字段名固定为用户指定的这些。例如，如果你定义了字段 "attire" 和 "relation"，则应输出：\n{"attire":"描述文字","relation":"描述文字"}。\n\n示例：\n{"attire":"她身穿一件白色衬衫...","relation":"与主角关系亲密，但内心有些纠结..."}'
      : '请在这里编写你的自定义提示词。';

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.style == null
          ? (widget.isStatusStyle ? '新建状态风格' : '新建风格')
          : (widget.isStatusStyle ? '编辑状态风格' : '编辑风格')),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _nameCtrl,
                decoration: const InputDecoration(labelText: '风格名称'),
                validator: (v) => v?.trim().isEmpty == true ? '请输入名称' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _promptCtrl,
                maxLines: 10,
                minLines: 5,
                decoration: const InputDecoration(
                  labelText: '提示词内容',
                  border: OutlineInputBorder(),
                ),
                validator: (v) => v?.trim().isEmpty == true ? '请输入提示词' : null,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _save,
          child: const Text('保存'),
        ),
      ],
    );
  }

  void _save() {
    if (_formKey.currentState?.validate() != true) return;
    widget.onSave(_nameCtrl.text.trim(), _promptCtrl.text.trim());
    Navigator.pop(context);
  }
}

// 完整主题包模型
class AppTheme {
  final String name;
  final Color primary;
  final Color secondary;
  final Color background;
  final Color surface;
  final Color textPrimary;
  final Color textSecondary;
  final Brightness brightness;

  AppTheme({
    required this.name,
    required this.primary,
    required this.secondary,
    required this.background,
    required this.surface,
    required this.textPrimary,
    required this.textSecondary,
    required this.brightness,
  });
}

// 预设主题包（8套，4列×2行完美填满）
final List<AppTheme> _presetThemes = [
  // 浅色主题（4个）
  AppTheme(
    name: '深海蓝',
    primary: Color(0xFF1976D2),
    secondary: Color(0xFF42A5F5),
    background: Color(0xFFFAFAFA),
    surface: Color(0xFFFFFFFF),
    textPrimary: Color(0xFF212121),
    textSecondary: Color(0xFF757575),
    brightness: Brightness.light,
  ),
  AppTheme(
    name: '森林绿',
    primary: Color(0xFF2E7D32),
    secondary: Color(0xFF66BB6A),
    background: Color(0xFFFAFAFA),
    surface: Color(0xFFFFFFFF),
    textPrimary: Color(0xFF212121),
    textSecondary: Color(0xFF757575),
    brightness: Brightness.light,
  ),
  AppTheme(
    name: '日落橙',
    primary: Color(0xFFE64A19),
    secondary: Color(0xFFFF7043),
    background: Color(0xFFFAFAFA),
    surface: Color(0xFFFFFFFF),
    textPrimary: Color(0xFF212121),
    textSecondary: Color(0xFF757575),
    brightness: Brightness.light,
  ),
  AppTheme(
    name: '薄荷青',
    primary: Color(0xFF00897B),
    secondary: Color(0xFF26A69A),
    background: Color(0xFFFAFAFA),
    surface: Color(0xFFFFFFFF),
    textPrimary: Color(0xFF212121),
    textSecondary: Color(0xFF757575),
    brightness: Brightness.light,
  ),
  // 深色主题（4个）
  AppTheme(
    name: '暗夜黑',
    primary: Color(0xFF90CAF9),
    secondary: Color(0xFF42A5F5),
    background: Color(0xFF121212),
    surface: Color(0xFF1E1E1E),
    textPrimary: Color(0xFFFFFFFF),
    textSecondary: Color(0xFFB0B0B0),
    brightness: Brightness.dark,
  ),
  AppTheme(
    name: '墨绿黑',
    primary: Color(0xFFA5D6A7),
    secondary: Color(0xFF66BB6A),
    background: Color(0xFF121212),
    surface: Color(0xFF1E1E1E),
    textPrimary: Color(0xFFFFFFFF),
    textSecondary: Color(0xFFB0B0B0),
    brightness: Brightness.dark,
  ),
  AppTheme(
    name: '紫夜',
    primary: Color(0xFFCE93D8),
    secondary: Color(0xFFAB47BC),
    background: Color(0xFF121212),
    surface: Color(0xFF1E1E1E),
    textPrimary: Color(0xFFFFFFFF),
    textSecondary: Color(0xFFB0B0B0),
    brightness: Brightness.dark,
  ),
  AppTheme(
    name: '琥珀夜',
    primary: Color(0xFFFFCC80),
    secondary: Color(0xFFFFB74D),
    background: Color(0xFF121212),
    surface: Color(0xFF1E1E1E),
    textPrimary: Color(0xFFFFFFFF),
    textSecondary: Color(0xFFB0B0B0),
    brightness: Brightness.dark,
  ),
];
// 主题预览卡片组件（紧凑版）
class _ThemePreviewCard extends StatelessWidget {
  final AppTheme theme;
  final bool isSelected;
  final VoidCallback onTap;

  _ThemePreviewCard({
    required this.theme,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: theme.surface,
          borderRadius: BorderRadius.circular(8),
          border: isSelected
              ? Border.all(width: 2, color: theme.primary)
              : null,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.08),
              blurRadius: 2,
              offset: Offset(0, 1),
            ),
          ],
        ),
        child: Column(
          children: [
            // 顶部颜色条
            Container(
              height: 24,
              decoration: BoxDecoration(
                color: theme.primary,
                borderRadius: BorderRadius.vertical(top: Radius.circular(8)),
              ),
            ),
            // 主题名字
            Expanded(
              child: Center(
                child: Text(
                  theme.name,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: theme.textPrimary,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}









//