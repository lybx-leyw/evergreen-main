# 主题

| 元信息 | 值 |
| --- | --- |
| 状态 | active |
| 版本 | 以根 `README.md` 为准 |
| 日期 | 2026-08-25 |
| 负责人 | core-theme |
| 适用 | theme 子包 |

> 扁平语义色板（8 色），亮/暗由主题自身色板决定，ChangeNotifier 即时切换。
> 当前模型：**扁平 8 色**（v1 五层 token 体系已废弃，勿参考旧文档）。

---

## 一、主题模型

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

## 二、主题来源与优先级

| 来源 | 路径/方式 | 优先级 |
|------|-----------|:---:|
| 代码注册 | `store.register(ThemeDescriptor(...))`，内置见 `builtin_themes.dart`（dark/light/evergreen） | 高 |
| 主题插件 | `plugins/<name>/theme/theme.json`（`scanThemes` 自动发现） | 中 |
| 示例 | `lib/core/theme/example/plugins/my_theme/`（`ocean_blue`，供复制验证） | 低 |

同 `id` 后者覆盖。加载失败（缺 8 色/hex 非法）→ stderr ❌ 明细 + 汇总，**静默跳过**。

## 三、插件格式（minimal theme.json）

```json
{
  "type": "theme",
  "id": "my_theme",
  "name": "我的主题",
  "colors": {
    "background": "#0D1117",
    "surface": "#161B22",
    "border": "#30363D",
    "text": "#C9D1D9",
    "textSecondary": "#8B949E",
    "accent": "#58A6FF",
    "error": "#FF7B72",
    "others": "#8B949E"
  }
}
```

颜色格式：`#RGB` / `#RRGGBB`（推荐）/ `#AARRGGBB`。不支持颜色名、`rgb()`、无 `#` 前缀。

校验清单：
- [ ] `type` = `"theme"`
- [ ] `id` 全局唯一（**不要**用 `dark`/`light`/`default`/`evergreen`，与内置冲突）
- [ ] `colors` 8 键全必填、值均为合法 hex
- [ ] `theme.json` 为有效 UTF-8 JSON

## 四、运行时切换

```
UI（设置页「外观·主题」下拉）→ store.setActiveById(id)
    → ChangeNotifier → themeDescriptorProvider（renderer）重建
        → MaterialApp theme（buildAppThemeFromDescriptor）
        → RenderTokens.applyTheme → 组件层静态色板
```

持久化：`SharedPreferences['active_theme_id']`，启动时恢复（无效 id 回退内置 dark）。

HTTP 通道（供插件 .exe）：`ThemeHttpServer` 端点 ——
`GET /theme/health` `GET /theme/themes` `GET /theme/themes/:id`
`GET /theme/active` `POST /theme/active {id}` `GET /theme/token?key=` + OPTIONS。

## 五、API 速览

| 类 | 关键成员 |
|----|----------|
| `ThemeDescriptor` | `fromJson`（校验 type/8 色/hex）、`color(key)`、`parseHex`、`toJson` |
| `ThemeColor` | `fromHex` / `tryParse` / `toHex`（ARGB 32 位） |
| `ThemeStore` | `register` / `all` / `findById` / `activeTheme` / `setActiveById` / `activeOrFirst` |
| `scanThemes(dir)` | 扫描 `plugins/<dir>/theme/theme.json` → `List<ThemeDescriptor>` |
| `scanThemeFile(path)` | 加载单个 theme.json（文件不存在/格式错误抛异常） |
| `loadThemes(dir, store)` | 扫描 + 注册 |
| `registerBuiltinThemes(store)` | 注册内置 dark/light/evergreen |
| `ThemeHttpServer(store)` | HTTP 服务（端点见 §四） |

## 六、渲染层消费

- `lib/renderer/app/service/theme/theme_provider.dart`：`buildAppThemeFromDescriptor`（8 色 → Material ColorScheme）
- `lib/renderer/app/service/theme/render_tokens.dart`：`RenderTokensColors.fromTheme` + `RenderTokens.applyTheme`（组件层共享色板）
- `lib/renderer/app/service/providers/renderer_providers.dart`：`themeDescriptorProvider` / `renderTokensProvider`（watch 链路）

HTML 插件：页面自动注入 `--evg-*` CSS 变量（`--evg-background` / `--evg-surface` / `--evg-border` / `--evg-text` / `--evg-text-secondary` / `--evg-accent` / `--evg-error` / `--evg-others`），主题切换实时更新；JS 侧用 `platform.theme.getColors()` 获取、监听 `theme:changed` 事件。

## 七、设计常量

像素级规范（间距/圆角/字号/阴影/动效）见 `render_rules.dart`（Spacing 4px 基准 / Radii / FontSize / Shadows / Durations / ComponentSize）——渲染层应引用，禁止新增硬编码。
