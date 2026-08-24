# Lib — Evergreen 应用层

> 入口 `main.dart` `app.dart`、提供者 `providers.dart`、barrel `evergreen_base.dart`、兼容 `theme/` `generated/`、上游 `core/`、下游 `renderer/`
> 版本号以根 `README.md` 为准。

Evergreen 采用**双轨架构**：`core/`（上游声明层）声明模块/主题/数据/Agent/配置，`renderer/`（下游渲染层）按声明渲染 UI。`lib/` 根目录负责将两者组装为完整应用。

> **用户插件创作事实**：用户侧已切换为 **HTML 为主**。用户通过 `html-creator` 编写 HTML/CSS/JS，
> 平台提供实时预览、AI 辅助生成与一键导出；导出物是 `plugins/<id>/module/index.html + manifest.json`
> （`"template":"html"`），由 `renderer/templates/html_modle` 以 WebView 加载。JSON 声明模块、
> `.exe` 数据源/Agent 工具保留为开发者模式与内置能力。

---

## 架构总览

```
lib/
├── main.dart                 # 启动入口——注册全局错误处理 + 构造 AppBootstrap 执行启动步骤序列
├── app_bootstrap.dart        # 启动序列（逐步骤 [BOOT] N/total 日志、致命步骤、窗口最后 show）
├── app.dart                  # MaterialApp.router——主题解析、路由生成、快捷键
├── providers.dart            # 应用级 Riverpod 提供者（moduleRegistryProvider 等，清单见文件）
├── evergreen_base.dart       # 对外 barrel——导出 core + renderer 全部公共 API
│
├── core/                     # 上游——声明与引擎（agent/config/data/module/theme + services/utils/plugin/feedback）
│   ├── agent/                #   AI Agent 运行时
│   ├── config/               #   设置与配置
│   ├── data/                 #   数据谱仪器
│   ├── module/               #   模块声明系统
│   ├── theme/                #   主题声明系统
│   ├── services/             #   通用服务（OCR 等）
│   ├── utils/                #   工具函数
│   ├── errors.dart           #   AppError——应用层错误（类型清单见 core/errors.dart）
│   ├── log.dart              #   Log——日志单例
│   └── result.dart           #   Result<T>——Dart 3 sealed class
│
├── renderer/                 # 下游——Flutter UI 渲染（只读 core/）
│   ├── app/                  #   应用壳、主题服务、全局 Provider
│   ├── atomic/               #   原子取数原语（data_source_resolver/json_path）
│   ├── components/           #   共享组件（widgets + shared）
│   ├── module/               #   模块调度（ModuleDispatch / ModulePage）
│   ├── multi_agent/          #   多 Agent 并行视图
│   ├── page/                 #   页面视图（市场/设置/数据看板/文件/全局记忆）
│   └── templates/            #   模板路由（v4/zju/html/scraper/theme-creator/skill-creator/dsh/paper_reading）+ slot/组件域（v4_modle 内）
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

`main.dart` 只做三件事：注册全局错误处理（`FlutterError.onError` / `ErrorWidget` / zone）、Web 环境提前退出、构造 `AppBootstrap` 执行启动序列。启动细节全部在 `app_bootstrap.dart` 的**步骤序列**中，每步输出 `[BOOT] N/total <step-id>` 日志，任意步骤失败凭 errorId 定位：

| 阶段 | 步骤 id | 说明 |
|------|---------|------|
| 窗口/路径 | `window-init` → `greenix-paths` | 桌面窗口参数预设（只设不 show）；Greenix 路径初始化（**致命步骤**，失败中止启动） |
| 运行时 | `release-assets` / `media-kit` / `webview2` | 运行时资产释放、media_kit、WebView2 CDP 环境 |
| 基础状态 | `prefs` / `settings` / `data-orchestrator` / `themes` | SharedPreferences、设置、数据谱仪器、主题加载 |
| 核心服务 | `http-services` / `zju-safety` / `agent-runtime` / `agent-tools` / `tool-disabled` / `agent-controller` | 核心服务构造、ZJU 凭证安全网、Agent 运行时/工具/控制器 |
| 服务启动 | `servers-start` | 启动 core HttpServer + ScraperBridge（写 `.xxx_port` 端口文件） |
| 注册中心 | `v2-scan` / `data-sources` / `modules` / `module-server` | V2 清单扫描、数据插件注册、模块注册中心、ModuleHttpServer |
| UI 收尾 | `default-theme` / `ui-launch` / `window-show` | 默认主题、`ProviderScope.overrides` 注入 → `runApp`、窗口显示（最后，避免白屏） |

> `kZjuEnabled`（`--dart-define=EVERGREEN_ZJU`）控制浙大专用内容：false 时 `registerZjuDataSources` / `registerZjuBuiltinModules` 不可达，浙大依赖被 AOT tree-shaker 整体剔除（通用版 release）。

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
| `renderer/app/` | `app.dart` | 应用壳、CommandPalette、DevModeHub、主题服务 |
| `renderer/atomic/` | `atomic.dart` | 数据源解析、JSON Path、转换注册 |
| `renderer/components/` | `components/shared/widgets/widgets.dart` | 共享原子组件（Chat、表格、编辑器、媒体…） |
| `renderer/module/` | `module/module.dart` | ModuleDispatch / ModulePage（V2 按内容自动选视图） |
| `renderer/multi_agent/` | `multi_agent_view.dart` | 多 Agent 并行工作区 |
| `renderer/page/` | `page/page.dart` | 市场、设置、数据看板、文件查看器、全局记忆 |
| `renderer/templates/` | `templates/template_registry.dart` | 模板路由（清单见 `templates/templates_index.json`） |

### 应用级

| 文件 | 说明 |
|------|------|
| `providers.dart` | **canonical** — `moduleRegistryProvider` 唯一正源 |
| `theme/breakpoints.dart` | 兼容性 stub — `Breakpoints` 类，值与 renderer 常量对齐 |
| `generated/plugin_imports.g.dart` | 兼容性 stub — re-export `providers.dart` |

> renderer 通过旧路径 `theme/breakpoints.dart` 和 `generated/plugin_imports.g.dart` 引用，
> 实际逻辑分别委托到 `renderer/app/service/providers/renderer_providers.dart` 和 `providers.dart`。
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
| `ThemeDescriptor.fromJson(json)` | 从 theme.json 解析（扁平 8 色） |
| `color(key)` | 按 key 取色（background/surface/border/text/textSecondary/accent/error/others） |

---

## 插件目录规范

```
plugins/<name>/
  module/index.html               ← HTML 插件主文件（用户侧主路径，可含 css/js）
  module/manifest.json            ← 模块声明（HTML 插件模板为 "template":"html"）
  agent/manifest.json + .exe      ← PluginBridge（AI 工具，开发者模式）
  theme/theme.json                ← ThemeLoader（配色声明）
  data/manifest.json              ← DataSourceLoader（数据源，开发者模式）
  config/config.json              ← SettingsLoader（设置项）
```

一个插件可同时提供多种类型——各子目录互不冲突。

---

## 使用示例

### 注册内置模块

```dart
import 'package:evergreen_base/core/module/modules.dart';

final registry = ModuleRegistry();

// 从 manifest.json 字符串注册（V2：不使用 ui 字段，按 template/pages/workspace 分派）
registry.registerFromJson('''
{
  "type": "module",
  "id": "chat",
  "name": "AI 对话",
  "icon": "chat",
  "route": "/chat",
  "template": "html",
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
