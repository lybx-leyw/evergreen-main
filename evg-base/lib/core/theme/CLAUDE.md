# Theme 模块 — AI 协作文档

> Evergreen 主题系统——**扁平语义色板（8 色）**，主题即完整配色方案（明暗由色板决定），ChangeNotifier 响应式切换。
> ⚠️ v1「五层 token（App/Module/Page/Slot/Component）」体系已废弃（`src/tokens.dart` 与 `builtins/` 已删除），本文档下方历史章节仅作参考，**实现以代码为准**。

---

## 一、模块架构

```
ThemeDescriptor (扁平 8 色模型) + ThemeColor (值对象)
        │
   ThemeStore (ChangeNotifier)
        │
   ├── registerBuiltinThemes → 内置 dark/light/evergreen（代码注册）
   ├── ThemeLoader → plugins/ 下的主题插件（theme.json）
   └── ThemeHttpServer (7 REST 端点)
```

| 文件 | 职责 |
|------|------|
| `src/color.dart` | ThemeColor — ARGB 32 位，hex 解析/序列化 |
| `theme_descriptor.dart` | 主题数据模型（扁平 8 色，8 键必填），fromJson/toJson |
| `theme_store.dart` | 响应式容器，ChangeNotifier |
| `theme_loader.dart` | 扫描目录/文件，加载 theme.json（失败输出 ❌ 日志） |
| `builtin_themes.dart` | 内置主题（dark/light/evergreen，`registerBuiltinThemes`） |
| `theme_http_server.dart` | 7 端点 HTTP API（含 CORS 预检） |
| `render_rules.dart` | 像素级设计常量（间距/圆角/字号等） |
| `theme.dart` | barrel 导出 |

---

## 二、目录结构

```
lib/core/theme/
├── CLAUDE.md                  # 本文件
├── README.md                  # 面向人类的使用文档（扁平 8 色模型）
├── pubspec.yaml               # 包声明（依赖 flutter_stub + path）
├── dart_test.yaml             # 测试配置（concurrency:1, timeout:30s）
├── theme.dart                 # barrel 导出
├── theme_descriptor.dart      # ThemeDescriptor 数据模型（扁平 8 色）
├── theme_store.dart           # ThemeStore 响应式存储器
├── theme_loader.dart          # scanThemes / loadThemes / scanThemeFile
├── builtin_themes.dart        # 内置主题（dark/light/evergreen）
├── theme_http_server.dart     # HTTP 7 端点
├── render_rules.dart          # 像素级设计常量
├── src/
│   └── color.dart             # ThemeColor 值对象
├── docs/
│   ├── plugin-theme.md        # ★ 主题插件快速参考卡（8 色模型，插件作者必读）
│   └── plugin-authoring-guide-theme.md  # ⚠️ 已废弃（v1 两层 token，历史参考）
├── example/
│   └── plugins/my_theme/      # 示例主题插件（ocean_blue，扁平 8 色）
└── test/
    ├── theme_test.dart        # ThemeDescriptor + ThemeStore + 扫描（扁平模型）
    ├── theme_http_server_test.dart  # 7 端点测试
    ├── token_validation_test.dart   # 示例主题 8 色校验
    └── builtin_themes_test.dart     # 内置主题完整性
│   ├── mono/theme/theme.json
│   ├── sunset/theme/theme.json
│   └── violet/theme/theme.json
├── docs/
│   ├── plugin-theme.md        # 插件主题快速参考卡
│   └── plugin-authoring-guide-theme.md  # 主题插件撰写完整指南
├── example/
│   ├── example.dart           # 全 API 覆盖示例
│   └── plugins/
│       └── my_theme/
│           └── theme/
│               └── theme.json
└── test/
    ├── theme_test.dart        # ThemeDescriptor + ThemeStore + 扫描（23 用例）
    ├── theme_http_server_test.dart  # 7 端点测试（12 用例）
    └── token_validation_test.dart   # Token 完整性 + 内置主题校验（11 用例）
```

---

## 三、Token 系统设计

### 3.1 五层架构

```
Layer 1: App 层 (5 个)         Layer 2: Module 层 (1 个)    Layer 3: Page 层 (2 个)
┌──────────────────────┐      ┌──────────────────────┐      ┌──────────────────────┐
│ sidebar              │      │ chrome               │      │ tabBar               │
│ header               │      └──────────────────────┘      │ background           │
│ footer               │                                    └──────────────────────┘
│ blank                │
│ commandPalette       │      Layer 4: Slot 层 (3 个)       Layer 5: Component 层 (54 个)
└──────────────────────┘      ┌──────────────────────┐      ┌──────────────────────────────┐
                              │ header               │      │ 导航(5) 对话(5) 表单(7)      │
                              │ background           │      │ 反馈(6) 数据展示(9)           │
                              │ border               │      │ 按钮(3) 布局(6) 图表(1)      │
                              └──────────────────────┘      │ 媒体(3) 杂项(5) 范式(4)      │
                                                            └──────────────────────────────┘
```

**设计理由**：从 v1 的两层（语义 + 组件）升级到 v2 的五层，每层对应 UI 树的不同嵌套级别。上层 token 可被子层继承/覆盖，切换主题时所有层全量自动跟随。渲染层引用 Component token，Component 引用上层 token，形成**级联引用链**：`App → Module → Page → Slot → Component`。

### 3.2 App 层 Token（5 个）

| # | key | 说明 |
|---|-----|------|
| 1 | `sidebar` | 侧边栏区域 |
| 2 | `header` | 顶部导航 |
| 3 | `footer` | 底部状态栏 |
| 4 | `blank` | 空白占位区 |
| 5 | `commandPalette` | 命令面板 |

常量定义：`src/tokens.dart` → `AppTokens.allowedKeys`

### 3.3 Module 层 Token（1 个）

| # | key | 说明 |
|---|-----|------|
| 1 | `chrome` | 模块级外壳（模块边框/底色） |

常量定义：`src/tokens.dart` → `ModuleTokens.allowedKeys`

### 3.4 Page 层 Token（2 个）

| # | key | 说明 |
|---|-----|------|
| 1 | `tabBar` | 页标签栏 |
| 2 | `background` | 页面主体背景 |

常量定义：`src/tokens.dart` → `PageTokens.allowedKeys`

### 3.5 Slot 层 Token（3 个）

| # | key | 说明 |
|---|-----|------|
| 1 | `header` | 栏位标题区 |
| 2 | `background` | 栏位背景 |
| 3 | `border` | 栏位外框 |

常量定义：`src/tokens.dart` → `SlotTokens.allowedKeys`

### 3.6 Component 层 Token（54 个）

| 分类 | 数量 | 组件列表 |
|------|------|---------|
| 导航 | 5 | sidebar, tab, breadcrumb, pagination, stepper |
| 对话 | 5 | bubble, thinking, toolCall, codeBlock, blockquote |
| 表单 | 7 | input, checkbox, radio, switch\_, slider, dropdown, datePicker |
| 反馈 | 6 | progressBar, spinner, skeleton, toast, alert, emptyState |
| 数据展示 | 9 | table, card, list, chip, avatar, badge, tooltip, calendar, timeline |
| 按钮 | 3 | button, iconButton, fab |
| 布局 | 6 | drawer, modal, header, footer, divider, scrollbar |
| 图表 | 1 | chart |
| 媒体 | 3 | videoPlayer, audioPlayer, imageViewer |
| 杂项 | 5 | link, menu, commandPalette, contextMenu, search |
| 范式 | 4 | spreadsheet, document, presentation, workspace |

常量定义：`src/tokens.dart` → `ComponentTokens.allowedKeys`
子 token 集合：`ComponentTokens.subTokens`

### 3.7 divider 兼容处理

`divider` 在旧版（v1 语义层）为字符串值，新版（v2 Component 层）为对象值。同一 JSON 文件只能选一种形态：
- `light.json` / `dark.json`：使用语义形态（`"divider": "#E8EAED"`）
- 其他 8 个内置主题：使用组件形态（`"divider": {"color": "...", "thickness": "1"}`）

组件形态中 `thickness` 是已知非颜色子 token，`isValidHexColor` 校验时会被跳过。

---

## 四、核心设计决策

### 4.1 Token 层级设计

- **为什么采用五层**：渲染层引用 Component token，Component 逐层引用上层 token（App/Module/Page/Slot）。切换主题时所有层全量自动跟随。扁平化（组件直接写死色值）会导致切换主题时需要手动更新每个组件。
- **级联引用链**：`App → Module → Page → Slot → Component`，每层可被子层继承或覆盖。
- **约束**：不可将 Component token 直接写死色值，必须通过层引用链路。

### 4.2 Fallback 机制

- `tokenValue(layer, component, subToken)` → 未注册返回 `null`
- `tokenColor(layer, component, subToken)` → 未注册返回 `null`
- `ThemeDescriptor` 提供五层 token 查询接口，每层独立 fallback
- **原则**：不让一个缺失的 token 崩溃整个页面

### 4.3 深色/浅色独立色值

- 深色和浅色各有完整的五层色值体系
- **不是**"深色 = 浅色反色"，而是独立设计的配色方案
- 内置 `light.json` 和 `dark.json` 各提供完整色值

### 4.4 主题注册/切换

- `ThemeStore.register()` 注册主题，同 id 后者覆盖
- `ThemeStore.activeTheme=` 设置活跃主题，触发 `ChangeNotifier.notifyListeners()`
- 同主题不重复通知（`if (_active?.id == theme?.id) return`）
- 预期 ≤ 500ms 内所有可见组件完成重绘

### 4.5 加载优先级

1. Dart 代码中 `store.register(ThemeDescriptor(...))` — 最高
2. 示例目录 `example/plugins/` — 开发调试
3. 内置主题 `builtins/` — 最低（可被同 id 覆盖）

### 4.6 内置主题路径约定

`scanThemes()` 期望 `<dir>/<name>/theme/theme.json` 结构。实际采用 `builtins/<name>/theme/theme.json`，与 `scanThemes('builtins')` 兼容。

---

## 五、开发约定

### 5.1 新增层 Token（App/Module/Page/Slot）

1. 在 `src/tokens.dart` → 对应层类（`AppTokens`/`ModuleTokens`/`PageTokens`/`SlotTokens`）中添加 `static const` 常量
2. 将新 key 加入对应层的 `allowedKeys` 集合
3. 更新内置主题 JSON 文件的对应层字段
4. 更新 README.md 和本文件中的 token 列表
5. 运行 `dart test` 确保对应层 count 测试通过

### 5.2 新增组件 Token

1. 在 `src/tokens.dart` → `ComponentTokens` 中添加 `static const` 常量
2. 将新 key 加入 `ComponentTokens.allowedKeys` 集合
3. 在 `ComponentTokens.subTokens` 中添加子 token 集合
4. 更新 README.md 和本文件中的组件列表
5. 运行 `dart test` 确保 `ComponentTokens.count` 和 `subTokens` 覆盖测试通过

### 5.3 新增内置主题

1. 在 `builtins/<name>/theme/theme.json` 创建 JSON 文件
2. `type` 必须为 `"theme"`
3. 五层 token 全覆盖（建议至少覆盖 App 层和 Component 层）
4. 运行 `dart run example/example.dart` 验证

### 5.4 RenderRules 像素常量

- **禁止**修改 `render_rules.dart` 中的任何像素常量值
- 修改前必须有设计依据，不能凭感觉调

### 5.5 纯 Dart 约束

- Theme 模块不引用 Flutter Widget（`dart:ui` Color 等）
- 颜色值用 hex 字符串（`#RRGGBB`）或 `ThemeColor` int value
- 渲染层负责 hex → Flutter Color 桥接

---

## 六、Stub 隔离说明

`lib/flutter_stub/` 提供 Flutter `foundation.dart` 的桩实现：

- `ChangeNotifier`：含 `addListener` / `removeListener` / `notifyListeners` / `dispose`
- `widgets.dart`：空桩，供 `pubspec.yaml` 依赖解析

主项目运行时由真实 Flutter SDK 覆盖。此桩使 `dart test` 可在纯 Dart 环境运行，无需完整 Flutter SDK。

---

## 七、测试策略

| 文件 | 覆盖 |
|------|------|
| `test/theme_test.dart` | ThemeDescriptor、ThemeColor、ThemeStore、扫描、Token 常量、fromJson 校验 |
| `test/theme_http_server_test.dart` | 6 端点 × 3 状态 |
| `test/token_validation_test.dart` | Token 完整性、内置主题校验、hex 往返 |

**配置**：`concurrency: 1`（HTTP 端口绑定），`timeout: 30s`。运行：`dart pub get && dart test`。

---

## 八、跨模块接口契约

### HTTP 端点（7 个）

| # | 方法 | 路径 | 说明 |
|---|------|------|------|
| 1 | GET | `/theme/health` | `{status, timestamp, themeCount}` |
| 2 | GET | `/theme/themes` | 列出所有主题 |
| 3 | GET | `/theme/themes/:id` | 主题详情或 404 |
| 4 | GET | `/theme/active` | 活跃主题或 404 |
| 5 | POST | `/theme/active` | 切换（`{id}`），返回 400/404 |
| 6 | GET | `/theme/token?layer=&component=&token=` | 查询五层 token 颜色 |
| 7 | OPTIONS | `/*` | CORS 预检（返回 204 + Allow-Origin） |

### Token 命名

- 层/组件/子 token 统一 camelCase

### 渲染层调用

`ThemeStore.activeTheme` → `ThemeDescriptor.tokenValue(layer, component, subToken)` → `ThemeColor.value` → Flutter `Color`

---

## 九、已知限制

- `ThemeColor` 与 Flutter `dart:ui` Color 不同类，通过 `.value` 桥接
- 内置 `light`/`dark` 仅覆盖核心层 token，其余需渲染器 fallback
- HTTP 绑定 `loopbackIPv4` 仅内部可访问
- 未知 token key 静默兼容（不抛错），通过 `unknown*Keys` / `invalidColors` 暴露
- `divider` 旧版语义/新版组件形态兼容，同一 JSON 只能选一种
- 非法 hex 返回 `null`，使用 fallback 参数指定兜底
