# Renderer — AI 协作规范

| 元信息 | 值 |
| --- | --- |
| 状态 | active |
| 版本 | 1.0 |
| 日期 | 2026-08-02 |
| 负责人 | 待补充 |
| 适用 | AI 协作者（renderer 层） |

> 供 AI 助手理解本模块约定。最后更新：2026-08-21。

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
│   ├── v4_modle/      # 通用组件式模板
│   ├── html_modle/    # HTML 插件模板（WebView + JS Bridge）
│   ├── scraper_modle/ # 爬虫生成器
│   ├── theme_creator_modle/ # 主题创作中心
│   ├── skill_creator_modle/ # Skill 创作中心
│   ├── dsh_modle/     # DeepSeek Harness
│   ├── paper_reading_modle/ # 论文阅读
│   └── zju_modle/     # 浙大校园（zju / classroom / zdbk）
├── lib/               # 11 个 Stub 包（独立 dart analyze）
├── docs/              # 设计规范 + 渲染常量
└── renderer.dart      # barrel 导出
```

---

## 核心规则

1. **组件层不直接调业务 API** — `components/shared/widgets/` 只接收描述符 + 数据，不管理状态。
2. **模块调度 V2** — 不再使用 `descriptor.ui` 字段；`ModuleDispatch` 按 `template` / `pages` / `workspace` 自动选择视图。
3. **未知静默忽略** — 未识别字段/UI 值不抛异常（容错）。
4. **描述符驱动** — 配置通过 `*Options` / `*Descriptor` 不可变类传入。
5. **数据注入分离** — 视图接收 `descriptor`（配置）和 `data`（运行时数据）两个独立参数。
6. **Stub 隔离** — `lib/` 下 11 个 stub 包使 renderer 可脱离 Flutter SDK 独立分析。

### 模块调度（V2）

| 条件 | → 视图 | 说明 |
|------|--------|------|
| `descriptor.id == 'ai-assistant'` | `ChatControllerView` | 全屏 AI 对话 |
| `descriptor.template` 非空且非 `v4` | `TemplateRegistry.render` | 按 `html` / `scraper` / `theme-creator` / `skill-creator` / `dsh` / `zju` / `paper_reading` 路由 |
| `descriptor.pages` 非空 | `TemplateRegistry.render` | 通常走 v4 composite |
| `descriptor.workspace.enabled` | `EditorView` | 代码/文本编辑器 |
| 其他 | `DefaultView` | 数据绑定兜底（不崩溃） |

### HTML 插件渲染

- `html_modle` 以本地 HTTP 服务加载 `plugins/<id>/module/index.html`。
- Windows 使用 `webview_windows`，Android 使用 `webview_flutter`。
- 统一注入 `platform.*` JS Bridge：
  - `platform.data.get/refresh/subscribe`
  - `platform.ai.chat`
  - `platform.api.call(service, path, opts)`
  - `platform.settings.get/set`
  - `platform.theme.getColors()`
  - `platform.emit/on`
- 当前主题色板自动注入为 `--evg-*` CSS 变量，主题切换时实时推送。

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

## 当前状态 (2026-08-21)

- ✅ V2 调度已对齐：`ModuleDispatch` 按 template/pages/workspace 自动选择，不使用 `ui` 字段
- ✅ HTML 插件主路径：`html-creator` 三栏 IDE + `html_modle` WebView + JS Bridge + 导出热注册
- ✅ 模板注册表：v4 / html / scraper / theme-creator / skill-creator / dsh / zju / paper_reading 共 10 条路由
- ✅ 主题色统一：RenderTokens 从扁平 8 色 ThemeDescriptor 动态派生，HTML 引擎使用 CSS 变量
- ✅ 11 个 stub 包，`dart analyze lib/` 可独立通过
