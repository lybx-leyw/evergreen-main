# 主题

> 两层 token（20 语义 + 54 组件），深色/浅色双主题，ChangeNotifier 即时切换。

---

## 一、API 速览

### ThemeDescriptor

| 字段 | 必填 | 类型 | 说明 |
|------|------|------|------|
| `id` | ✓ | `String` | 唯一标识 |
| `name` | ✓ | `String` | 展示名称 |
| `semanticTokens` | | `Map<String,String>` | 语义 token（20 个） |
| `componentTokens` | | `Map<String,Map<String,String>>` | 组件 token（54 个） |

| 方法 | 说明 |
|------|------|
| `ThemeDescriptor.fromJson(json)` | 解析 JSON，校验 `type=="theme"` |
| `semantic(key)` → `String?` | 获取语义 token 原始 hex |
| `semanticColor(key)` → `ThemeColor?` | 语义 token → 颜色对象 |
| `semanticColorOr(key, fallback)` → `ThemeColor` | 语义 token + 兜底 |
| `componentColor(c, t)` → `ThemeColor?` | 组件 token → 颜色对象 |
| `componentColorOr(c, t, fallback)` → `ThemeColor` | 组件 token + 兜底 |
| `unknownSemanticKeys` → `List<String>` | 不在 20 规范中的 key |
| `unknownComponentKeys` → `List<String>` | 不在 54 规范中的 key |
| `invalidColors` → `List<MapEntry>` | 格式非法条目 |

### ThemeColor

| 方法 | 说明 |
|------|------|
| `ThemeColor.fromHex("#1677FF")` | hex 构造 |
| `ThemeColor.tryParse(hex)` → `ThemeColor?` | 安全解析 |
| `toHex()` → `String` | 序列化为 `#AARRGGBB` |

### ThemeStore

| 方法 | 说明 |
|------|------|
| `register(theme)` | 注册（同 id 覆盖） |
| `activeTheme` / `activeTheme=` | 当前主题 / 切换（触发通知） |
| `setActiveById(id)` → `bool` | 按 id 切换 |
| `addListener(fn)` / `dispose()` | ChangeNotifier |

### 加载函数

| 函数 | 说明 |
|------|------|
| `scanThemes(dir)` → `List<ThemeDescriptor>` | 扫描 `<dir>/<name>/theme/theme.json` |
| `loadThemes(dir, store)` | 扫描 + 注册到 store |

### ThemeHttpServer（6 端点）

| 方法 | 路径 | 说明 |
|------|------|------|
| GET | `/theme/health` | 健康检查 |
| GET | `/theme/themes` | 列出所有主题 |
| GET | `/theme/themes/:id` | 主题详情 |
| GET | `/theme/active` | 当前活跃主题 |
| POST | `/theme/active` | 切换活跃主题 |
| GET | `/theme/token?component=&token=` | 查询 token 颜色 |

### render_rules

| 类 | 常量 |
|-----|------|
| `Spacing` | `xs=4`, `sm=8`, `md=16`, `lg=24`, `xl=32`, `xxl=48` |
| `Radii` | `sm=4`, `md=8`, `lg=12`, `xl=16`, `full=9999` |
| `FontSize` | `caption=12`, `body=14`, `subtitle=16`, `title=20`, `heading=24`, `display=32` |
| `Durations` | `fast=150`, `normal=300`, `slow=500` |
| `Shadows` | `none`, `card`, `elevated`, `modal`, `drawer`, `fab` |

---

## 二、Token 体系

### 语义 Token（20 个）

`primary`, `secondary`, `tertiary`, `background`, `surface`, `surfaceVariant`, `error`, `success`, `warning`, `info`, `text`, `textSecondary`, `textTertiary`, `textInverse`, `border`, `shadow`, `overlay`, `disabled`, `placeholder`, `divider`

### 组件 Token（54 个，按分类）

| 分类 | 组件 |
|------|------|
| 导航 | `sidebar`, `tab`, `breadcrumb`, `pagination`, `stepper` |
| 对话 | `bubble`, `thinking`, `toolCall`, `codeBlock`, `blockquote` |
| 表单 | `input`, `checkbox`, `radio`, `switch_`, `slider`, `dropdown`, `datePicker` |
| 反馈 | `progressBar`, `spinner`, `skeleton`, `toast`, `alert`, `emptyState` |
| 数据 | `table`, `card`, `list`, `chip`, `avatar`, `badge`, `tooltip`, `calendar`, `timeline` |
| 按钮 | `button`, `iconButton`, `fab` |
| 布局 | `drawer`, `modal`, `header`, `footer`, `divider`, `scrollbar` |
| 图表 | `chart` |
| 媒体 | `videoPlayer`, `audioPlayer`, `imageViewer` |
| 杂项 | `link`, `menu`, `commandPalette`, `contextMenu`, `search` |
| 范式 | `spreadsheet`, `document`, `presentation`, `workspace` |

> 完整子 token 定义见 `docs/plugin-authoring-guide-theme.md`。

---

## 三、插件开发者指南

**最小 `theme.json`**（放入 `plugins/<name>/theme/theme.json`）：

```json
{
  "type": "theme",
  "id": "my_theme",
  "name": "我的主题",
  "colors": {
    "primary": "#1976D2",
    "background": "#FAFAFA"
  }
}
```

**规则**：
- `type` 必须为 `"theme"`，否则解析抛出 `FormatException`
- `colors` 中字符串值 → 语义 token，对象值 → 组件 token
- 颜色格式：`#RGB` / `#RRGGBB` / `#AARRGGBB`
- 同 `id` 后者覆盖前者（加载优先级：`store.register()` > `example/plugins/` > `builtins/`）
- 完整指南 → `docs/plugin-authoring-guide-theme.md`，快速参考 → `docs/plugin-theme.md`

---

## 四、架构决策

### 两层 Token

组件 token 引用语义 token，切换主题时全量自动跟随。禁止组件 token 直接写死色值。

### Fallback 不抛异常

`semanticColor()` / `componentColor()` 对缺失 token 返回 `null`，不崩溃页面。

### 深色/浅色独立色值

不是"反色"，而是两套独立设计的配色方案。

### 内置主题路径

`builtins/<name>/theme/theme.json`，与 `scanThemes()` 期望一致。

---

## 五、质量

| 维度 | 状态 |
|------|------|
| 测试 | ✅ 99 用例全量通过 |
| Example | ✅ 覆盖全部 API |
| 文档 | ✅ README + CLAUDE.md + 2 份插件指南 |
| 内置主题 | ✅ 10 个（`builtins/`） |
| dart analyze | ✅ 零 errors |

---

## 六、已知问题

- `ThemeColor` 与 Flutter `dart:ui` Color 是不同类，渲染器通过 `.value` 桥接
- 内置 `light`/`dark` 仅覆盖核心组件 token，其余需渲染器 fallback
- HTTP 服务器绑定 `loopbackIPv4` 仅内部可访问
- 未知 token key 静默兼容，不抛错
- `divider` 键名在语义/组件间冲突，同一 JSON 只能选一种形态
- 非法 hex 值返回 `null`，使用 `*Or()` 方法指定兜底色
