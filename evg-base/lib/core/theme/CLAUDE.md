# Theme 模块 — AI 协作文档

| 元信息 | 值 |
| --- | --- |
| 状态 | active |
| 版本 | 以根 `README.md` 为准 |
| 日期 | 2026-08-25 |
| 负责人 | core-theme |
| 适用 | AI 协作者（theme 子包） |

> Evergreen 主题系统——**扁平语义色板（8 色）**，主题即完整配色方案（明暗由色板决定），ChangeNotifier 响应式切换。
> ⚠️ v1「五层 token（App/Module/Page/Slot/Component）」体系已废弃，**实现以当前扁平 8 色模型为准**。

---

## 一、模块架构

```
ThemeDescriptor (扁平 8 色模型) + ThemeColor (值对象)
        │
   ThemeStore (ChangeNotifier)
        │
   ├── registerBuiltinThemes → 内置 dark/light/evergreen（代码注册）
   ├── ThemeLoader → plugins/ 下的主题插件（theme.json）
   └── ThemeHttpServer（HTTP 端点，见 §七）
```

| 文件 | 职责 |
|------|------|
| `src/color.dart` | ThemeColor — ARGB 32 位，hex 解析/序列化 |
| `theme_descriptor.dart` | 主题数据模型（扁平 8 色，8 键必填），fromJson/toJson |
| `theme_store.dart` | 响应式容器，ChangeNotifier |
| `theme_loader.dart` | 扫描目录/文件，加载 theme.json（失败输出 ❌ 日志） |
| `builtin_themes.dart` | 内置主题（dark/light/evergreen，`registerBuiltinThemes`） |
| `theme_http_server.dart` | HTTP API（端点见 §七，含 CORS 预检） |
| `render_rules.dart` | 像素级设计常量（间距/圆角/字号等） |
| `theme.dart` | barrel 导出 |

---

## 二、目录结构

```
lib/core/theme/
├── AGENT.md                  # OWNER 职责书（core-theme）
├── CLAUDE.md                  # 本文件
├── README.md                  # 面向人类的使用文档（扁平 8 色模型）
├── pubspec.yaml               # 包声明（依赖 flutter_stub + path）
├── theme.dart                 # barrel 导出
├── theme_descriptor.dart      # ThemeDescriptor 数据模型（扁平 8 色）
├── theme_store.dart           # ThemeStore 响应式存储器
├── theme_loader.dart          # scanThemes / loadThemes / scanThemeFile
├── builtin_themes.dart        # 内置主题（dark/light/evergreen）
├── theme_http_server.dart     # HTTP API（端点见 §七）
├── render_rules.dart          # 像素级设计常量
├── src/
│   └── color.dart             # ThemeColor 值对象
├── docs/
│   ├── plugin-theme.md        # ★ 主题插件快速参考卡（8 色模型，插件作者必读）
│   └── plugin-authoring-guide-theme.md  # ⚠️ 历史遗留文档，仅参考旧 v1 两层 token
├── example/
│   └── plugins/my_theme/      # 示例主题插件（ocean_blue，扁平 8 色）
└── test/
    ├── theme_test.dart        # ThemeDescriptor + ThemeStore + 扫描（扁平模型）
    ├── theme_http_server_test.dart  # HTTP 端点测试
    ├── token_validation_test.dart   # 示例主题 8 色校验
    └── builtin_themes_test.dart     # 内置主题完整性
```

---

## 三、核心设计决策

### 3.1 扁平 8 色模型

一个主题 = `id` + `name` + 8 个**必填**语义色：

| 字段 | 必填 | 含义 | 映射 |
|------|:---:|------|------|
| `background` | ✓ | 页面主背景（scaffold） | scaffoldBackgroundColor |
| `surface` | ✓ | 卡片/面板底色 | surface |
| `border` | ✓ | 默认边框/分隔线 | outline |
| `text` | ✓ | 主文字 | onSurface |
| `textSecondary` | ✓ | 次级/弱化文字 | onSurfaceVariant |
| `accent` | ✓ | 强调/品牌色 | primary |
| `error` | ✓ | 错误态 | error |
| `others` | ✓ | 其余杂色 | secondary |

兼容别名：`primary` → `accent`，`secondary` → `others`（旧 theme.json 可无缝迁移）。
除上述 8 键外**不接受**其他语义键（多余键会被忽略，但 8 键缺一即解析失败）。

### 3.2 主题来源与优先级

| 来源 | 路径/方式 | 优先级 |
|------|-----------|:---:|
| 代码注册 | `store.register(ThemeDescriptor(...))`，内置见 `builtin_themes.dart` | 高 |
| 主题插件 | `plugins/<name>/theme/theme.json`（`scanThemes` 自动发现） | 中 |
| 示例 | `lib/core/theme/example/plugins/my_theme/` | 低 |

同 `id` 后者覆盖。加载失败（缺 8 色/hex 非法）→ stderr ❌ 明细 + 汇总，**静默跳过**。

### 3.3 主题切换与持久化

```
UI（设置页「外观·主题」下拉）→ store.setActiveById(id)
    → ChangeNotifier → themeDescriptorProvider（renderer）重建
        → MaterialApp theme（buildAppThemeFromDescriptor）
        → RenderTokens.applyTheme → 组件层静态色板
```

持久化：`SharedPreferences['active_theme_id']`，启动时恢复（无效 id 回退内置 dark）。

### 3.4 HTML 插件主题注入

HTML 插件由 `html_modle` 注入当前主题色板为 CSS 变量：

```css
:root {
  --evg-background: ...;
  --evg-surface: ...;
  --evg-border: ...;
  --evg-text: ...;
  --evg-text-secondary: ...;
  --evg-accent: ...;
  --evg-error: ...;
  --evg-others: ...;
}
```

JS 侧可用 `platform.theme.getColors()` 获取，并监听 `theme:changed` 实时更新。

---

## 四、开发约定

### 新增主题

1. 在 `example/plugins/my_theme/theme/theme.json` 或 `plugins/<name>/theme/theme.json` 创建 JSON
2. `type` 必须为 `"theme"`
3. 8 个语义色全必填，值均为合法 hex（`#RGB` / `#RRGGBB` / `#AARRGGBB`）
4. 不要用 `dark` / `light` / `default` / `evergreen` 作为 id（与内置冲突）
5. 运行 `dart test` 验证

### RenderRules 像素常量

- **禁止**修改 `render_rules.dart` 中的任何像素常量值
- 修改前必须有设计依据，不能凭感觉调

### 纯 Dart 约束

- Theme 模块不引用 Flutter Widget（`dart:ui` Color 等）
- 颜色值用 hex 字符串（`#RRGGBB`）或 `ThemeColor` int value
- 渲染层负责 hex → Flutter Color 桥接

---

## 五、Stub 隔离说明

`lib/flutter_stub/` 提供 Flutter `foundation.dart` 的桩实现：

- `ChangeNotifier`：含 `addListener` / `removeListener` / `notifyListeners` / `dispose`
- `widgets.dart`：空桩，供 `pubspec.yaml` 依赖解析

主项目运行时由真实 Flutter SDK 覆盖。此桩使 `dart test` 可在纯 Dart 环境运行。

---

## 六、测试策略

| 文件 | 覆盖 |
|------|------|
| `test/theme_test.dart` | ThemeDescriptor、ThemeColor、ThemeStore、扫描、fromJson 校验 |
| `test/theme_http_server_test.dart` | HTTP 端点 + 错误处理 |
| `test/token_validation_test.dart` | 8 色完整性、内置主题校验、hex 往返 |
| `test/builtin_themes_test.dart` | 内置主题完整性 |

运行：`dart pub get && dart test`

---

## 七、跨模块接口契约

### HTTP 端点

| 方法 | 路径 | 说明 |
|------|------|------|
| GET | `/theme/health` | `{status, timestamp, themeCount}` |
| GET | `/theme/themes` | 列出所有主题 |
| GET | `/theme/themes/:id` | 主题详情或 404 |
| GET | `/theme/active` | 活跃主题或 404 |
| POST | `/theme/active` | 切换（`{id}`），返回 400/404 |
| GET | `/theme/token?key=` | 查询语义色 |
| OPTIONS | `/*` | CORS 预检（返回 204 + Allow-Origin） |

### 渲染层调用

`ThemeStore.activeTheme` → `ThemeDescriptor.color(key)` → `ThemeColor.value` → Flutter `Color`

### HTML 插件调用

`platform.theme.getColors()` → `Promise<Object>`，对象含 `background/surface/border/text/textSecondary/accent/error/others` 及派生 `accentBg/accentBorder`。

---

## 八、已知限制

- `ThemeColor` 与 Flutter `dart:ui` Color 不同类，通过 `.value` 桥接
- 内置 `light`/`dark` 仅覆盖核心语义色，其余由渲染器 fallback
- HTTP 绑定 `loopbackIPv4` 仅内部可访问
- 非法 hex 返回 `null`，使用 fallback 参数指定兜底

---

## 九、版本历史

| 日期 | 变更 |
|------|------|
| 2026-08-25 | 文档对齐代码：目录结构补 AGENT.md；确认 ThemeHttpServer 端点表与扁平 8 色模型一致（含 OPTIONS 预检）；按文档修订三原则去除硬编码数量与版本号 |
| 2026-08-02 | 初始版本：创建 CLAUDE.md（扁平 8 色模型 / 废弃五层 token / HTTP 端点契约） |
