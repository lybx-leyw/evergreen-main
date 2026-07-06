# Theme 模块 — AI 协作文档

> Evergreen 主题系统——两层 token（20 语义 + 54 组件），深色/浅色双主题，响应式切换。

---

## 一、模块架构

```
ThemeDescriptor (数据模型) + ThemeColor (值对象)
        │
   ThemeStore (ChangeNotifier)
        │
   ├── ThemeLoader → builtins/ + plugins/
   └── ThemeHttpServer (6 REST 端点)
```

| 文件 | 职责 |
|------|------|
| `src/color.dart` | ThemeColor — ARGB 32 位，hex 解析/序列化 |
| `src/tokens.dart` | 20 语义 + 54 组件 token 白名单常量 |
| `theme_descriptor.dart` | 主题数据模型，fromJson/toJson，token 查询 |
| `theme_store.dart` | 响应式容器，ChangeNotifier |
| `theme_loader.dart` | 扫描目录/文件，加载 theme.json |
| `theme_http_server.dart` | 6 端点 HTTP API |
| `render_rules.dart` | 像素级设计常量（间距/圆角/字号等） |
| `theme.dart` | barrel 导出 |

---

## 二、目录结构

```
lib/core/theme/
├── CLAUDE.md                  # 本文件
├── README.md                  # 面向人类的使用文档
├── pubspec.yaml               # 包声明（依赖 flutter_stub + path）
├── dart_test.yaml             # 测试配置（concurrency:1, timeout:30s）
├── theme.dart                 # barrel 导出
├── theme_descriptor.dart      # ThemeDescriptor 数据模型
├── theme_store.dart           # ThemeStore 响应式存储器
├── theme_loader.dart          # scanThemes / loadThemes / scanThemeFile
├── theme_http_server.dart     # HTTP 6 端点
├── render_rules.dart          # 像素级设计常量
├── src/
│   ├── color.dart             # ThemeColor 值对象
│   └── tokens.dart            # SemanticTokens + ComponentTokens 常量
├── lib/
│   └── flutter_stub/          # Flutter foundation 桩（提供 ChangeNotifier）
│       └── lib/
│           ├── foundation.dart
│           └── widgets.dart
├── builtins/                  # 10 个内置主题（JSON）
│   ├── light/theme/theme.json
│   ├── dark/theme/theme.json
│   ├── default/theme/theme.json
│   ├── evergreen/theme/theme.json
│   ├── forest/theme/theme.json
│   ├── high_contrast/theme/theme.json
│   ├── liyu/theme/theme.json
│   ├── mono/theme/theme.json
│   ├── sunset/theme/theme.json
│   └── violet/theme/theme.json
├── docs/
│   └── plugin-theme.md        # 插件主题开发规范
├── example/
│   ├── example.dart           # 全 API 覆盖示例
│   └── plugins/
│       └── my_theme/
│           └── theme/
│               └── theme.json
└── test/
    ├── theme_test.dart        # ThemeDescriptor + ThemeStore + 扫描
    ├── theme_http_server_test.dart  # 6 端点测试
    └── token_validation_test.dart   # Token 完整性 + 内置主题校验
```

---

## 三、Token 系统设计

### 3.1 两层架构

```
语义 Token（20 个）          组件 Token（54 个）
┌─────────────────┐         ┌─────────────────────┐
│ primary         │──┐      │ sidebar.bg          │
│ secondary       │  │      │ sidebar.text        │
│ background      │  │      │ sidebar.active      │
│ surface         │  │      │ sidebar.hover       │
│ text            │  │      │ bubble.user         │
│ ...             │  │      │ bubble.assistant    │
└─────────────────┘  │      │ button.primary      │
                      ├─────►│ button.hover        │
                      │      │ ... (54 组件)       │
                      │      └─────────────────────┘
                      │
                      │      渲染层引用组件 token，
                      │      组件 token 引用语义 token，
                      │      切换主题时全量自动跟随。
```

**设计理由**：如果组件 token 直接写死色值，切换主题时组件无法自动跟随。两层间接引用确保主题切换即时生效。

### 3.2 语义 Token（20 个）

| # | key | 说明 |
|---|-----|------|
| 1 | `primary` | 主色（品牌色） |
| 2 | `secondary` | 辅色 |
| 3 | `tertiary` | 第三色 |
| 4 | `background` | 页面背景 |
| 5 | `surface` | 卡片/容器背景 |
| 6 | `surfaceVariant` | 次级容器背景 |
| 7 | `error` | 错误/危险色 |
| 8 | `success` | 成功色 |
| 9 | `warning` | 警告色 |
| 10 | `info` | 信息色 |
| 11 | `text` | 正文 |
| 12 | `textSecondary` | 次要文本 |
| 13 | `textTertiary` | 三级文本 |
| 14 | `textInverse` | 反色文本（深底亮字） |
| 15 | `border` | 边框 |
| 16 | `shadow` | 阴影 |
| 17 | `overlay` | 遮罩 |
| 18 | `disabled` | 禁用态 |
| 19 | `placeholder` | 占位符 |
| 20 | `divider` | 分割线 |

常量定义位置：`src/tokens.dart` → `SemanticTokens.allowedKeys`

### 3.3 组件 Token（54 个）

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

常量定义位置：`src/tokens.dart` → `ComponentTokens.allowedKeys`
子 token 集合：`ComponentTokens.subTokens`

### 3.4 divider 冲突处理

`divider` 在语义 token（字符串值）和组件 token（对象值）中同名。同一 JSON 文件只能选一种形态：
- `light.json` / `dark.json`：使用语义形态（`"divider": "#E8EAED"`）
- 其他 8 个内置主题：使用组件形态（`"divider": {"color": "...", "thickness": "1"}`）

组件形态中 `thickness` 是已知非颜色子 token，`isValidHexColor` 校验时会被跳过。

---

## 四、核心设计决策

### 4.1 Token 层级设计

- **为什么必须两层**：渲染层引用组件 token，组件 token 引用语义 token。切换主题时语义 token 变化 → 所有组件自动跟随。扁平化（组件直接写死色值）会导致切换主题时需要手动更新每个组件。
- **约束**：不可将组件 token 直接写死色值，必须引用语义 token。

### 4.2 Fallback 机制

- `semantic(key)` → 未注册返回 `null`
- `componentColor(component, token)` → 未注册返回 `null`
- `semanticColorOr(key, fallback)` / `componentColorOr(c, t, fallback)` → 未注册返回指定 fallback
- **原则**：不让一个缺失的 token 崩溃整个页面

### 4.3 深色/浅色独立色值

- 深色和浅色各有完整的一套 20 语义 token 色值
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

### 5.1 新增语义 Token

1. 在 `src/tokens.dart` → `SemanticTokens` 中添加 `static const` 常量
2. 将新 key 加入 `SemanticTokens.allowedKeys` 集合
3. 更新 `light.json` 和 `dark.json` 的 `colors` 字段
4. 更新 README.md 和本文件中的 token 列表
5. 运行 `dart test` 确保 `SemanticTokens.count` 测试通过

### 5.2 新增组件 Token

1. 在 `src/tokens.dart` → `ComponentTokens` 中添加 `static const` 常量
2. 将新 key 加入 `ComponentTokens.allowedKeys` 集合
3. 在 `ComponentTokens.subTokens` 中添加子 token 集合
4. 更新 README.md 和本文件中的组件列表
5. 运行 `dart test` 确保 `ComponentTokens.count` 和 `subTokens` 覆盖测试通过

### 5.3 新增内置主题

1. 在 `builtins/<name>/theme/theme.json` 创建 JSON 文件
2. `type` 必须为 `"theme"`
3. 20 语义 token 全覆盖（建议）
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

### HTTP 端点（6 个）

| # | 方法 | 路径 | 说明 |
|---|------|------|------|
| 1 | GET | `/theme/health` | `{status, timestamp, themeCount}` |
| 2 | GET | `/theme/themes` | 列出所有主题 |
| 3 | GET | `/theme/themes/:id` | 主题详情或 404 |
| 4 | GET | `/theme/active` | 活跃主题或 404 |
| 5 | POST | `/theme/active` | 切换（`{id}`），返回 400/404 |
| 6 | GET | `/theme/token?component=&token=` | 查询 token 颜色 |

### Token 命名

- 语义/组件/子 token 统一 camelCase

### 渲染层调用

`ThemeStore.activeTheme` → `ThemeDescriptor.semanticColor()` / `componentColor()` → `ThemeColor.value` → Flutter `Color`

---

## 九、已知限制

- `ThemeColor` 与 Flutter `dart:ui` Color 不同类，通过 `.value` 桥接
- 内置 `light`/`dark` 仅覆盖核心组件 token，其余需渲染器 fallback
- HTTP 绑定 `loopbackIPv4` 仅内部可访问
- 未知 token key 静默兼容（不抛错），通过 `unknown*Keys` / `invalidColors` 暴露
- `divider` 语义/组件形态冲突，同一 JSON 只能选一种
- 非法 hex 返回 `null`，使用 `*Or()` 方法指定兜底
