import 'package:flutter/material.dart';

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
  }) => ApiConfig(
    label: label ?? this.label,
    url: url ?? this.url,
    model: model ?? this.model,
    apiKey: apiKey ?? this.apiKey,
    token: token ?? this.token,
    requestType: requestType ?? this.requestType,
    bodyTemplate: bodyTemplate ?? this.bodyTemplate,
  );
}

class CustomStyle {
  String id;
  String name;
  String prompt;

  CustomStyle({required this.id, required this.name, required this.prompt});

  factory CustomStyle.create({required String name, required String prompt}) =>
      CustomStyle(id: DateTime.now().millisecondsSinceEpoch.toString(), name: name, prompt: prompt);

  Map<String, String> toMap() => {'id': id, 'name': name, 'prompt': prompt};

  factory CustomStyle.fromMap(Map<String, String> map) => CustomStyle(
    id: map['id'] ?? DateTime.now().millisecondsSinceEpoch.toString(),
    name: map['name'] ?? '未命名',
    prompt: map['prompt'] ?? '',
  );

  CustomStyle copyWith({String? name, String? prompt}) =>
      CustomStyle(id: id, name: name ?? this.name, prompt: prompt ?? this.prompt);
}

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
  }) => AppSettings(
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
