\# 角色聊天室 + 小说创作应用 —— 项目交接文档



\## 1. 项目概览

\- \*\*应用名称\*\*：角色聊天室

\- \*\*核心功能\*\*：

&#x20; - 创建 AI 角色（名字、性格、着装、外貌、喜好、厌恶、背景故事、说话风格）

&#x20; - 多角色群聊（共享上下文，角色不串线）

&#x20; - 上帝模式：手动注入事件、场景卡

&#x20; - 旁白生成（可自定义提示词）

&#x20; - 自定义回复风格（用户可编写任意提示词，与角色设定叠加）

&#x20; - 自定义角色状态描写风格（动态生成 JSON 状态快照，随对话更新）

&#x20; - 多线叙事分支存档（支线管理）

&#x20; - 智能记忆（自动摘要 + 记忆数量上限控制）

&#x20; - 情感弧线追踪（好感度、信任度、亲密感）

&#x20; - 图片生成（多 API 支持，带缓存，气泡内点击放大、长按保存/删除）

&#x20; - 小说创作模块（独立项目，旁白驱动，角色、世界观、存档、导出）

&#x20; - 全局主题色切换

&#x20; - 角色设定导出/导入（JSON 格式，剪贴板）

&#x20; - 图库管理（多选分享/删除）

\- \*\*技术栈\*\*：Flutter 3.41.8 / Dart 3.11.5 + SharedPreferences + path\_provider + share\_plus + http + cached\_network\_image

\- \*\*运行环境\*\*：Windows 桌面版（开发）、Android APK



\## 2. 当前文件结构

flutter\_application\_1/

├── lib/

│ ├── main.dart

│ ├── models/

│ │ ├── character.dart # 角色模型（含说话风格 speakingStyle、头像 avatarPath）

│ │ ├── chat\_message.dart # 聊天消息模型（含 statusSnapshot 字段）

│ │ └── novel\_project.dart # 小说项目模型

│ ├── services/

│ │ ├── ai\_service.dart # AI 调用（返回 AiResponse，含 token 统计）

│ │ ├── image\_service.dart # 图片生成（多 API 支持，有缓存）

│ │ ├── storage\_service.dart # 聊天室持久化（角色、消息、存档、API配置、记忆等）

│ │ ├── novel\_storage\_service.dart # 小说项目持久化

│ │ └── theme\_provider.dart # 全局主题色管理

│ ├── screens/

│ │ ├── home\_page.dart # 主页（底部导航切换四个标签）

│ │ ├── character\_hub\_page.dart # 角色中心（创建角色、导入导出、存档列表）

│ │ ├── chat\_page.dart # 聊天室（核心文件，所有对话逻辑）

│ │ ├── gallery\_page.dart # 图库（多选、分享、删除）

│ │ ├── settings\_page.dart # 设置（API配置、提示词编辑、风格管理等）

│ │ ├── novel\_hub\_page.dart # 小说工坊（项目列表、存档卡片）

│ │ └── novel\_chat\_page.dart # 小说创作界面（旁白、上帝指令、角色发言）

│ ├── widgets/

│ │ ├── adaptive\_text\_field.dart # 自适应高度文本框

│ │ ├── small\_button.dart # 底部快捷操作按钮组件

│ │ └── chat\_message\_bubble.dart # 聊天气泡组件（独立封装，支持头像、图片、动画）

│ └── utils/ (如有) # 可能包含 app\_dialogs.dart, app\_snackbars.dart

├── pubspec.yaml

└── .gitignore



\## 3. 核心功能模块说明



\### 3.1 聊天室 (chat\_page.dart)

\- 多角色群聊、自定义回复风格、自定义角色状态面板、上帝模式、旁白生成、支线管理、智能记忆、情感弧线追踪、图片生成、消息长按操作、状态快照等。



\### 3.2 小说工坊 (novel\_chat\_page.dart)

\- 旁白驱动创作、角色发言、上帝指令、随机事件（带确认）、支线管理、导出小说等。



\### 3.3 设置页 (settings\_page.dart)

\- 用户设定、提示词编辑、对话/图片 API 配置、回复风格管理、状态描写风格管理、角色状态面板配置、智能记忆设置、图片修饰词、主题色选择。



\### 3.4 数据持久化

\- 聊天室：SharedPreferences，键名前缀区分功能（chat\_、archive\_、branch\_）

\- 小说：SharedPreferences，项目与存档独立存储

\- Token 统计：按 sessionId 独立存储



\## 4. 关键设计模式

\- \*\*会话隔离\*\*：本体用 chat\_角色id，存档用 archive\_时间戳，支线用 branch\_时间戳

\- \*\*状态快照\*\*：ChatMessage.statusSnapshot 字段，在消息创建时植入，toJson/fromJson 已支持持久化

\- \*\*主题色\*\*：ThemeProvider 全局通知，气泡颜色已适配 primaryColor

\- \*\*抽屉分组\*\*：使用 \_buildDrawerSection 辅助方法，设置页使用 ExpansionTile 折叠



\## 5. 最近完成的主要改动

\- 图片重复显示修复、状态面板闪烁修复（状态快照机制）、图片气泡内操作（点击放大、长按保存/删除）

\- 图片不再自动保存到图库、自定义状态描写风格、设置页 UI 重构、聊天室抽屉 UI 优化、多线支线管理

\- 情感弧线追踪、智能记忆摘要



\## 6. 当前待清理/注意事项

\- 检查 lib/utils/ 目录是否存在 app\_dialogs.dart 和 app\_snackbars.dart，如有缺失请还原为原始 ScaffoldMessenger 写法。

\- 模型文件（assets/models/）已从 Git 中排除，不会上传。

\- android/app/build/ 等构建产物已通过 .gitignore 忽略。



\## 7. pubspec.yaml 当前依赖

```yaml

dependencies:

&#x20; flutter:

&#x20;   sdk: flutter

&#x20; http: ^1.2.0

&#x20; cached\_network\_image: ^3.3.1

&#x20; shared\_preferences: ^2.2.2

&#x20; path\_provider: ^2.1.1

&#x20; share\_plus: ^7.2.1



dev\_dependencies:

&#x20; flutter\_test:

&#x20;   sdk: flutter

&#x20; flutter\_lints: ^6.0.0

&#x20; . 给接手 AI 的建议

修改功能时优先阅读 chat\_page.dart 和 storage\_service.dart，这是最核心的两个文件。



新增设置项请在 settings\_page.dart 中添加 UI，并在对应 State 中加载/保存。



修改状态面板相关逻辑时，务必理解 statusSnapshot 的生成和显示流程。



注意 SharedPreferences 的键名必须唯一，且与已有键不冲突。



调试时可添加 debugPrint 语句观察控制台输出。



文档结束。如有疑问，请参考代码注释或联系原开发者。

