# Renderer — AI 协作规范

| 元信息 | 值 |
| --- | --- |
| 状态 | active |
| 版本 | 见根 `README.md` |
| 日期 | 2026-08-02 |
| 负责人 | renderer |
| 适用 | AI 协作者（renderer 层） |

> 供 AI 助手理解本模块约定。最后更新：2026-08-25。

---

## 目录结构（实际代码）

```
lib/renderer/
├── app/               # 应用壳（AppShell / CommandPalette / DebugErrorBar / DevModeHub）
│   └── service/       #   全局 Provider、主题服务（ThemeProvider / RenderTokens）
├── atomic/            # 原子取数原语（DataSourceResolver / JSONPath / TransformRegistry）
├── components/        # 共享组件
│   ├── shared/        #   TemplateEngine / SlotScale / AgentTrace 等组合基础设施
│   └── shared/widgets/ #   Chat / 表格 / 编辑器 / 媒体 / 表单 / 市场 等原子组件
├── module/            # 模块调度（EvergreenModulePage / ModuleDispatch）
├── multi_agent/       # 多 Agent 并行视图
├── page/              # 页面视图（市场 / 设置 / 数据看板 / 文件查看器 / 全局记忆 / Skill 管理）
├── templates/         # 模板（modle）渲染器与注册表
│   ├── v4_modle/      # 通用组件式模板（slot 分派 + 组件域收敛于此）
│   ├── html_modle/    # HTML 插件模板（WebView + JS Bridge）
│   ├── scraper_modle/ # 爬虫生成器
│   ├── theme_creator_modle/ # 主题创作中心
│   ├── skill_creator_modle/ # Skill 创作中心
│   ├── dsh_modle/     # DeepSeek Harness
│   └── zju_modle/     # 浙大校园（zju / classroom / zdbk）
├── lib/               # Stub 包（独立 dart analyze，清单见 lib/）
├── docs/              # 设计规范 + 渲染常量
└── renderer.dart      # barrel 导出
```

---

## 核心规则

1. **组件层不直接调业务 API** — `components/shared/widgets/` 只接收描述符 + 数据，不管理状态。
2. **模块调度 V2** — 不再使用 `descriptor.ui` 字段；`ModuleDispatch` 按 `template` / `pages` / `workspace` 自动选择视图。
3. **未知静默忽略** — 未识别字段/UI 值不抛异常（容错）。
4. **描述符驱动** — 配置通过 `*Options` / `*Descriptor` 不可变类传入。
5. **数据注入分离** — 视图接收 `descriptor`（配置）与 `data`（运行时数据）独立参数分离注入。
6. **Stub 隔离** — `lib/` 下 stub 包使 renderer 可脱离 Flutter SDK 独立分析。

### 模块调度（V2）

| 条件 | → 视图 | 说明 |
|------|--------|------|
| `descriptor.id == 'ai-assistant'` | `ChatControllerView` | 全屏 AI 对话 |
| `descriptor.template` 非空且非 `v4` | `TemplateRegistry.render` | 按 `html` / `scraper` / `theme-creator` / `skill-creator` / `dsh` / `zju` / `classroom` / `zdbk` 路由 |
| `descriptor.pages` 非空 | `TemplateRegistry.render` | 通常走 v4 composite |
| `descriptor.workspace.enabled` | `EditorView` | 代码/文本编辑器 |
| 其他 | `DefaultView` | 数据绑定兜底（不崩溃） |

> **lattice 契约现状**：六格契约（`static-web`/`web-bridged`/`data-source`/`sidecar`/`agent-tool`/`external-app`）由 `core/module` 解析与权限层（`PermissionResolver`/`BridgeInterceptor`）裁决，renderer **不按 lattice 路由**——`ModuleDispatch` 只消费 `template`/`pages`/`workspace`；`external-app`「不内嵌、深链」语义当前由 core 侧契约定义（`resolved_plugin.isExternalApp`），renderer 未做深链跳转特判。sidecar 格由 `core/module` 的 `SidecarController` 管理进程与端口，renderer 正常按模板渲染（数据经 bridge/HTTP 转发）。若 renderer 需按 lattice 区分渲染/深链，属跨 OWNER 契约变更，需与 core-module 对齐后广播。

### HTML 插件渲染

- `html_modle` 以本地 HTTP 服务加载 `plugins/<id>/module/index.html`。
- Windows 使用 `webview_windows`，Android 使用 `webview_flutter`。
- 统一注入 `platform.*` JS Bridge（Promise 风格，双通道 `chrome.webview` / `evgBridge`）：
  - `platform.data.get(name)` / `list()` / `refresh(name)` / `testConnectivity()` / `subscribe(name, fn)`
  - `platform.ai.chat(prompt, [style])`（style ∈ explanatory/learning/concise/socratic）
  - `platform.api.call(service, path, {method, body})` — 通用 core 服务转发（agent/config/data/module/theme/core，端口来自 `.xxx_port` 端口文件）
  - `platform.process.run(exe, {args})` / `start` / `write` / `stop` / `read` / `onOutput(fn)` / `onExit(fn)` — 运行 manifest `process` 白名单内声明的 exe（fail-closed；`scope:"long"` 为常驻进程）
  - `platform.settings.get(key)` / `set(key, value)`
  - `platform.theme.getColors()`
  - `platform.emit(event, payload)` / `platform.on(event, fn)`
- bridge 注入三保险：服务端文档顶部内联 + document-created + onPageStarted（幂等守卫）。
- 当前主题色板自动注入为 `--evg-*` CSS 变量（background/surface/border/text/textSecondary/accent/accentBg/accentBorder/error/others），主题切换时实时推送。
- 特例：`descriptor.id == 'html-creator'` 时短路到 Dart 原生 `HtmlCreatorView`（创作中心），不启动本地 HTTP / WebView。

### HTML 插件导出链路（单目标）

- 创作中心导出 = `HtmlExportService`（手动）/ `ExportHtmlPluginTool`（AI），两者共用
  `writeHtmlPluginModule()`：**单目标**写入 `{resolvePluginsRoot()}/{id}/module/`
  （`manifest.json` + `index.html`，`"template":"html"`）——路径解析统一走
  `core/utils/greenix_path.dart` 的 `resolvePluginsRoot()`，与主题插件
  `ThemeExporter`（`plugins/<id>/theme/theme.json`）同根，**安卓/桌面行为一致**
  （安卓 = 应用私有 `.greenix/plugins`，不再依赖 `pluginsDirProvider` 注入）。
- **不变式**：`assets/plugins_bundle/` 是 `plugins/` 的纯镜像，仅由
  `tool/bundle_plugins.dart` 生成；renderer 导出**禁止直写 bundle**。
- 加固：插件 id 经共享 `htmlPluginIdError()` 校验（小写字母开头 kebab-case，
  拒绝纯数字/路径穿越）；落盘路径经 `PathSandbox` confine；写入为**原子导出**
  （临时目录复制旧 module/ → 写新文件 → rename 替换 + 备份回滚）。
- 绑定不可改：插件 id 在画板创建/加载时由 `CanvasManager.ensureInstance`
  固定分配（实例 id == 插件 id，写回 `meta.json`），**随画板绑定、用户与 AI
  均不可更改**。工具栏 id 输入框为只读锁定展示；AI 导出 `ExportHtmlPluginTool`
  始终复用画板绑定 id，传入的 `plugin_id` 被忽略（未绑定则拒绝导出）。派生规则
  见 `canvas_manager._sanitizeId`（强制小写字母开头，保证通过 `htmlPluginIdError`）。
- 导出成功即热注册：`reloadModule`（侧边栏/路由）+ `pluginStateProvider`
  `registerInstalled`/`touch`（插件中心/最近使用）；失败原因经 `Log()` +
  SnackBar 用户可见（不静默）。

---

## 代码模式

### 原子组件（components/shared/widgets/）
```dart
// 纯展示：Options + 数据模型
class MyWidget extends StatelessWidget {
  final MyOptions options;
  final ChatMessage message;
  const MyWidget({required this.options, required this.message});
}
```

### 模块调度（module/）
```dart
class MyPage extends StatelessWidget {
  final ModuleDescriptor descriptor;
  // 内部由 EvergreenModulePage → ModuleDispatch 自动选择模板/视图
}
```

### 模板渲染器（templates/）
```dart
class MyModleTemplate extends ModleRenderer {
  @override
  Widget build(BuildContext context, {required ModuleDescriptor descriptor, String? workingDirectory}) {
    return MyModleView(descriptor: descriptor, workingDirectory: workingDirectory);
  }
}
```

---

## 环境 & 测试

| 命令 | 目录 |
|------|------|
| `dart analyze lib/` | `renderer/` |
| `dart pub get` | `renderer/` |
| `flutter test` | 项目根 |

测试模式：`testWidgets` + `MaterialApp` + `Scaffold`，验证 `findsOneWidget` + 数据正确性。

---

## 当前状态 (2026-08-25)

- ✅ V2 调度已对齐：`ModuleDispatch` 按 template/pages/workspace 自动选择，不使用 `ui` 字段
- ✅ HTML 插件主路径：`html-creator` 三栏 IDE + `html_modle` WebView + JS Bridge（含 `platform.process.*` 进程白名单）+ 导出热注册
- ✅ 模板注册表：路由清单见 `templates/templates_index.json`（生成物 `generated/template_registry.g.dart`）
- ✅ 主题色统一：RenderTokens 从扁平 8 色 ThemeDescriptor 动态派生，HTML 引擎使用 CSS 变量
- ✅ PDF 翻译已撤销（t20）：删除 `v4_modle/components/translate/`（translate_slot/translate_models）与
  `_registrations.dart` 的 `pdf-translate` slot/capability 注册及对应测试；论文阅读翻译走 paper_reader.py，不受影响
- ✅ 发现插件分类修复（t24）：`registryPluginToDescriptor`（`page/market_view.dart`）把 registry `lattice`
  （插件类型权威声明）并入能力维度（去重、声明维度在前）——主题插件（warm_study）在「发现插件」页
  显示/筛选为「主题」而非仅「界面」，不依赖修改 registry 数据；未知 lattice 保持既有行为
- ✅ paper_reading_modle 模板已撤销（t25）：删除整个模板目录（24 文件）；`PymupdfTool`（skill_creator
  的 `pdf_extract_text` 工具在用）迁移至 `skill_creator_modle/tools/pymupdf_tool.dart`；templates_index.json
  与 build_profiles 移除 paper_reading，`template_registry.g.dart` 已重新生成（10→9 路由）
- ✅ Stub 包，`dart analyze lib/` 可独立通过
- ✅ `renderer.dart` barrel 已收敛：slot/ 与组件域随 v4_modle 移入 `templates/v4_modle/`，导出路径同步更新
- ✅ 流式消费契约（T7a/T7b）：新增 `components/shared/stream_source.dart`（`StreamSource` 描述符：url/protocol
  （hls/mp4/http-flv/sse/stdio-jsonl，对齐 manifest `stream.protocol`）/mime/credentialed/headers/ttl +
  `MediaRequestHeadersProvider` 凭证注入抽象 + 默认空实现）、`components/shared/stream_playback.dart`
  （`buildMedia`：StreamSource → media_kit，`resolveStreamUrl`/`resolveStreamHeaders` 纯函数）；
  修 `platform.data.list()` 运行期未实现 bug（`html_modle_view.dart` 补 case，与预览面板同构）；
  `platform.data.subscribe` 事件驱动化（`DataSubscriptionPoller` 注入 core `dataChangeEvents`，命中即推
  `data:changed`，5s 轮询保留兜底 + `_eventFresh` 跳轮，dispose 取消订阅）
- ✅ 数据源文件导出（T8b）：新增 `components/shared/file_export_names.dart`（纯函数，零依赖）、
  `file_export.dart`（选目录 + `exportFileEntry`/`exportFileEntries`，下载走 core `DataFileService`）、
  `file_export_bar.dart`（`FileExportButton`/`FileExportBar`）；barrel 已导出，README 记录用法；演示页未接
