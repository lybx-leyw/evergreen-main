# Lib — Evergreen 2.0 应用层

> 入口 `main.dart` `app.dart`、提供者 `providers.dart`、barrel `evergreen_base.dart`、兼容 `theme/` `generated/`、上游 `core/`、下游 `renderer/`

Evergreen 2.0 采用**双轨架构**：`core/`（上游声明层）声明模块/主题/数据/Agent/配置，`renderer/`（下游渲染层）按声明渲染 UI。`lib/` 根目录负责将两者组装为完整应用。

---

## 架构总览

```
lib/
├── main.dart                 # 启动入口——初始化设置→模块→数据→主题→ProviderScope→runApp
├── app.dart                  # MaterialApp.router——主题解析、路由生成、快捷键
├── providers.dart            # 应用级 Riverpod 提供者（moduleRegistryProvider）
├── evergreen_base.dart       # 对外 barrel——导出 core + renderer 全部公共 API
│
├── core/                     # 上游——声明与引擎（6 个子模块 + 3 个基础工具）
│   ├── agent/                #   AI Agent 运行时
│   ├── config/               #   设置与配置
│   ├── data/                 #   数据谱仪器
│   ├── module/               #   模块声明系统
│   ├── theme/                #   主题声明系统
│   ├── services/             #   通用服务（OCR 等）
│   ├── utils/                #   工具函数
│   ├── errors.dart           #   AppError——13 种应用层错误
│   ├── log.dart              #   Log——日志单例
│   └── result.dart           #   Result<T>——Dart 3 sealed class
│
├── renderer/                 # 下游——Flutter UI 渲染（只读 core/）
│   ├── widgets/              #   原子渲染组件（48 个 dart 文件）
│   ├── shared/               #   组合视图 + 调度基础设施
│   └── compositions/         #   高级多视图叠加工作区
│
├── theme/                    # 兼容性 stub——renderer 通过旧路径引用
│   └── breakpoints.dart      #   → Breakpoints，值与 renderer 常量对齐
│
├── generated/                # 兼容性 stub——renderer 通过旧路径引用
│   └── plugin_imports.g.dart #   → re-export providers.dart
│
└── plugins/                  # 外部插件目录
```

---

## 启动流程

`main.dart` 按以下顺序初始化：

| 步骤 | 操作 | API |
|------|------|-----|
| 1 | Flutter 绑定 + 桌面窗口 | `windowManager` |
| 2 | SharedPreferences + 设置初始化 | `initSettings(prefs, pluginDirs:)` |
| 3 | 模块注册中心（内置 + 插件） | `loadBuiltinModules()` → `scanAndLoadModules()` → `registry.seal()` |
| 4 | 数据谱仪器 | `DataOrchestrator()` |
| 5 | 主题加载 | `ThemeStore` + `loadThemes()` |
| 6 | ProviderScope 注入 → runApp | `moduleRegistryProvider`、`dataOrchestratorProvider`、`themeDescriptorProvider` |

---

## 对外 API（evergreen_base.dart barrel）

### 上游 — 声明与引擎

| 模块 | Barrel | 核心类 | 用途 |
|------|--------|--------|------|
| `core/agent/` | `agent.dart` | `AgentRuntime`、`ChatMessage`、`Tool`、`PluginBridge` | AI Agent 运行时 |
| `core/config/` | `config.dart` | `SettingDecl`、`initSettings()`、`getSetting()` | 设置读写 |
| `core/data/` | `data.dart` | `DataOrchestrator`、`DataType<T>`、`DataSourceStatus` | 数据获取与缓存 |
| `core/module/` | `modules.dart` | `ModuleDescriptor`、`ModuleRegistry`、`ModuleLoader` | 模块声明与注册 |
| `core/theme/` | `theme.dart` | `ThemeDescriptor`、`ThemeStore`、`ThemeLoader` | 主题声明 |
| `core/services/` | `services.dart` | OCR 管线、更新服务 | 平台服务 |
| `core/utils/` | — | `safeParse`、`tokenEstimator`、`greenix_path` | 工具函数 |

### 下游 — 渲染

| 层级 | Barrel | 说明 |
|------|--------|------|
| `renderer/widgets/` | `widgets.dart` | 48 个原子组件（AppShell、CommandPalette、MessageBubble…） |
| `renderer/shared/` | `shared.dart` | 组合视图（ChatView…）+ 调度（ModuleDispatch、LayoutEngine）+ 主题解析 |
| `renderer/compositions/` | `compositions.dart` | 高级工作区（WorkspaceHub） |

### 应用级

| 文件 | 说明 |
|------|------|
| `providers.dart` | **canonical** — `moduleRegistryProvider` 唯一正源 |
| `theme/breakpoints.dart` | 兼容性 stub — `Breakpoints` 类，值与 renderer 常量对齐 |
| `generated/plugin_imports.g.dart` | 兼容性 stub — re-export `providers.dart` |

> renderer 通过旧路径 `theme/breakpoints.dart` 和 `generated/plugin_imports.g.dart` 引用，
> 实际逻辑分别委托到 `renderer/shared/renderer_providers.dart` 和 `providers.dart`。
> 新代码应直接从 `providers.dart` 导入。

---

## 核心类速查

### ModuleRegistry（`core/module/module_registry.dart`）

| 方法 | 说明 |
|------|------|
| `register(d)` | 注册模块 |
| `registerAll(list)` | 批量注册 |
| `seal()` | 锁定 + 依赖校验 |
| `modules` | 只读模块列表 |
| `findById(id)` | 按 id 查找 |
| `navGroups` | 分组导航条目 |
| `navFlat` | 扁平导航条目 |
| `paletteItems` | 命令面板条目 |

### DataOrchestrator（`core/data/orchestrator.dart`）

| 方法 | 说明 |
|------|------|
| `register(type, fetcher)` | 注册数据类型 |
| `get(type)` | 缓存优先获取 |
| `refresh(type)` | 强制拉取 |
| `startAutoRefresh()` | 定时自动刷新 |
| `allStatuses` | 全部数据源状态 |

### ThemeDescriptor（`core/theme/theme_descriptor.dart`）

| 方法 | 说明 |
|------|------|
| `ThemeDescriptor.fromJson(json)` | 从 theme.json 解析 |
| `semanticTokens` | 语义 token（primary、background…） |
| `componentTokens` | 组件 token（bubble、sidebar…） |

---

## 插件目录规范

```
plugins/<name>/
  agent/manifest.json + .exe      ← PluginBridge（AI 工具）
  module/manifest.json            ← ModuleLoader（UI 声明）
  theme/theme.json                ← ThemeLoader（配色声明）
  data/manifest.json              ← DataSourceLoader（数据源）
  config/config.json              ← SettingsLoader（设置项）
```

一个插件可同时提供多种类型——各子目录互不冲突。

---

## 使用示例

### 注册内置模块

```dart
import 'package:evergreen_base/core/module/modules.dart';

final registry = ModuleRegistry();

// 从 manifest.json 字符串注册
registry.registerFromJson('''
{
  "type": "module",
  "id": "chat",
  "name": "AI 对话",
  "icon": "chat",
  "route": "/chat",
  "ui": "chat",
  "sidebar": {"section": "主功能", "order": 10}
}
''');

registry.seal();
```

### 获取设置值

```dart
import 'package:shared_preferences/shared_preferences.dart';
import 'package:evergreen_base/core/config/config.dart';

final prefs = await SharedPreferences.getInstance();
final apiKey = getSetting(prefs, 'DEEPSEEK_API_KEY');
await setSetting(prefs, 'THEME_MODE', 'dark');
```

### 注册数据源

```dart
import 'package:evergreen_base/core/data/data.dart';

final orchestrator = DataOrchestrator();
orchestrator.register(
  DataType<String>(name: 'weather', label: '天气', category: '外部'),
  () async => fetchWeather(),
);
final weather = await orchestrator.get(weatherType);
```

---

## 规则

- **上游声明，下游渲染**：`core/` 只声明不渲染，`renderer/` 按声明渲染。
- **只读边界**：渲染工程师可读 `core/` 全部，但不可写。Core 子模块之间只读彼此对外接口。
- **描述符优先**：渲染逻辑依赖 `ModuleDescriptor`、`ThemeDescriptor` 等描述符结构，不依赖实现细节。
- **未知静默忽略**：所有渲染器对未知字段必须静默回退到默认值。
- **barrel 导出**：所有公共 API 通过 `evergreen_base.dart` 统一导出，消费者 `import 'package:evergreen_base/evergreen_base.dart'` 即可获得全部能力。
