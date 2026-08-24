# Theme 主题插件撰写指南

| 元信息 | 值 |
| --- | --- |
| 状态 | deprecated（已废弃，仅历史参考） |
| 版本 | 以根 `README.md` 为准 |
| 日期 | 2026-08-25 |
| 负责人 | core-theme |
| 适用 | 主题插件作者（历史遗留） |

> ⚠️ **已废弃**：本文档描述 v1「两层 token（20 语义 + 54 组件）」模型。
> 当前实现为**扁平 8 色**模型（`ThemeDescriptor.colors`，8 键必填），
> 按本文撰写主题 JSON 会解析失败。
> **请使用** → `docs/plugin-theme.md`（快速参考卡）与 `README.md`（完整模型）。
> 本文仅保留供历史参考。

---

## 一、目录结构

```
plugins/<name>/
├── module/manifest.json    # UI 声明
├── theme/theme.json        # ★ 主题声明（本指南核心）
├── data/manifest.json      # 数据源（可选）
└── config/config.json      # 设置项（可选）
```

- `theme.json` 必须放在 `plugins/<name>/theme/`，文件名固定
- 平台通过 `scanThemes('plugins/')` 自动发现

---

## 二、theme.json 字段规范

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `type` | `string` | ✓ | 固定 `"theme"`，否则抛出 `FormatException` |
| `id` | `string` | ✓ | 全局唯一，建议 `snake_case` |
| `name` | `string` | ✓ | 展示名称，支持中文 |
| `version` | `string` | | 语义化版本（预留） |
| `mode` | `string` | | `"light"` / `"dark"` / `"both"`（预留） |
| `colors` | `object` | ✓ | 字符串值 → 语义 token，对象值 → 组件 token |

### 加载优先级（同 id 覆盖）

1. 代码注册（`store.register()`）— **最高**
2. 插件目录（`plugins/<name>/theme/theme.json`）— 开发调试
3. 内置主题（`light` / `dark`）— **最低**

> 不要用 `light` / `dark` / `default` 作为自定义 id。

---

## 三、Token 系统

### 3.1 两层架构

```
语义 Token（20 个）             组件 Token（54 个）
┌──────────────────┐           ┌──────────────────────┐
│ primary          │           │ sidebar.bg           │
│ secondary        │── 引用 ──►│ bubble.user          │
│ background       │           │ button.primary       │
│ text             │           │ ... (54 组件)        │
└──────────────────┘           └──────────────────────┘
```

切换主题时只改语义 token 色值，所有组件自动跟随。

### 3.2 语义 Token（20 个）

| # | key | 说明 | 浅色建议 | 深色建议 |
|---|-----|------|---------|---------|
| 1 | `primary` | 主色（品牌色） | `#1677FF` | `#4096FF` |
| 2 | `secondary` | 辅色 | `#4096FF` | `#69B1FF` |
| 3 | `tertiary` | 第三色 | `#69B1FF` | `#91CAFF` |
| 4 | `background` | 页面背景 | `#F5F6F8` | `#0D1117` |
| 5 | `surface` | 卡片/容器背景 | `#FFFFFF` | `#161B22` |
| 6 | `surfaceVariant` | 次级容器 | `#F0F1F3` | `#21262D` |
| 7 | `error` | 错误/危险 | `#FF4D4F` | `#FF6B6B` |
| 8 | `success` | 成功 | `#52C41A` | `#56D364` |
| 9 | `warning` | 警告 | `#FA8C16` | `#E3B341` |
| 10 | `info` | 信息 | `#1677FF` | `#4096FF` |
| 11 | `text` | 正文 | `#1A1D21` | `#E6EDF3` |
| 12 | `textSecondary` | 次要文本 | `#656D78` | `#8B949E` |
| 13 | `textTertiary` | 三级文本 | `#9CA3AF` | `#6E7681` |
| 14 | `textInverse` | 反色文本 | `#FFFFFF` | `#0D1117` |
| 15 | `border` | 边框 | `#D0D5DD` | `#30363D` |
| 16 | `shadow` | 阴影 | `#000000` | `#000000` |
| 17 | `overlay` | 遮罩 | `#000000` | `#000000` |
| 18 | `disabled` | 禁用态 | `#D0D5DD` | `#484F58` |
| 19 | `placeholder` | 占位符 | `#9CA3AF` | `#6E7681` |
| 20 | `divider` | 分割线 | `#E8EAED` | `#21262D` |

> 深色/浅色是两套独立色值，不是反色。

### 3.3 组件 Token（54 个）

#### 导航

| 组件 | 子 token |
|------|---------|
| `sidebar` | `bg`, `text`, `active`, `hover` |
| `tab` | `text`, `active`, `indicator`, `hover` |
| `breadcrumb` | `text`, `link`, `separator` |
| `pagination` | `bg`, `active`, `text`, `hover` |
| `stepper` | `done`, `active`, `pending`, `line` |

#### 对话

| 组件 | 子 token |
|------|---------|
| `bubble` | `user`, `assistant`, `text`, `timestamp` |
| `thinking` | `bg`, `text`, `border` |
| `toolCall` | `bg`, `text`, `border` |
| `codeBlock` | `bg`, `text`, `border`, `header` |
| `blockquote` | `border`, `text`, `bg` |

#### 表单

| 组件 | 子 token |
|------|---------|
| `input` | `bg`, `text`, `border`, `focus`, `placeholder`, `error` |
| `checkbox` | `border`, `fill`, `check` |
| `radio` | `border`, `fill` |
| `switch_` | `track`, `thumb`, `trackActive` |
| `slider` | `track`, `fill`, `thumb` |
| `dropdown` | `bg`, `text`, `border`, `itemHover` |
| `datePicker` | `header`, `selected`, `today`, `hover` |

#### 反馈

| 组件 | 子 token |
|------|---------|
| `progressBar` | `track`, `fill`, `text` |
| `spinner` | `color`, `track` |
| `skeleton` | `bg`, `shimmer` |
| `toast` | `bg`, `text`, `border`, `success`, `error`, `warning`, `info` |
| `alert` | `bg`, `text`, `border`, `icon` |
| `emptyState` | `icon`, `text`, `action` |

#### 数据展示

| 组件 | 子 token |
|------|---------|
| `table` | `header`, `stripe`, `text`, `border`, `hover` |
| `card` | `bg`, `border`, `shadow`, `text` |
| `list` | `bg`, `hover`, `divider` |
| `chip` | `bg`, `text`, `border`, `close` |
| `avatar` | `bg`, `text`, `border` |
| `badge` | `bg`, `text` |
| `tooltip` | `bg`, `text` |
| `calendar` | `header`, `selected`, `today`, `otherMonth`, `event` |
| `timeline` | `line`, `dot`, `card` |

#### 按钮

| 组件 | 子 token |
|------|---------|
| `button` | `primary`, `hover`, `active`, `disabled`, `text` |
| `iconButton` | `color`, `hover`, `active` |
| `fab` | `bg`, `icon`, `shadow` |

#### 布局

| 组件 | 子 token |
|------|---------|
| `drawer` | `bg`, `text`, `overlay` |
| `modal` | `bg`, `overlay`, `text`, `border` |
| `header` | `bg`, `text`, `border` |
| `footer` | `bg`, `text`, `border` |
| `divider` | `color`, `thickness` |
| `scrollbar` | `thumb`, `track` |

> **divider 冲突**：`divider` 在语义 token 中是字符串（`"#E8EAED"`），在组件 token 中是对象（`{"color": "...", "thickness": "1"}`）。同一 JSON 只能选一种形态。

#### 图表

| 组件 | 子 token |
|------|---------|
| `chart` | `colors` (数组), `axis`, `grid`, `tooltip` |

> `chart.colors` 是数组型 palette，hex 校验时跳过。

#### 媒体

| 组件 | 子 token |
|------|---------|
| `videoPlayer` | `controls`, `progress`, `overlay` |
| `audioPlayer` | `controls`, `waveform`, `progress` |
| `imageViewer` | `bg`, `overlay` |

#### 杂项

| 组件 | 子 token |
|------|---------|
| `link` | `text`, `hover`, `visited` |
| `menu` | `bg`, `text`, `hover`, `divider` |
| `commandPalette` | `bg`, `text`, `highlight`, `border` |
| `contextMenu` | `bg`, `text`, `hover`, `divider` |
| `search` | `bg`, `text`, `border`, `focus`, `icon` |

#### 范式

| 组件 | 子 token |
|------|---------|
| `spreadsheet` | `header`, `grid`, `cell`, `cellSelected`, `formulaBar`, `tab` |
| `document` | `bg`, `text`, `ruler`, `pageShadow`, `comment`, `selection` |
| `presentation` | `bg`, `canvas`, `slideBorder`, `toolbar`, `notes` |
| `workspace` | `bg`, `tabBar`, `panel`, `resizeHandle`, `empty` |

---

## 四、色值格式

| 格式 | 示例 | 说明 |
|------|------|------|
| `#RGB` | `#FFF` | 短格式 |
| `#RRGGBB` | `#1677FF` | **推荐** |
| `#AARRGGBB` | `#801677FF` | 含 alpha |

不支持：颜色名、`rgb()`、`hsl()`、无 `#` 前缀的 hex。

### 深色模式建议

- 降低饱和度（高饱和色在深底上刺眼）
- 增加明度（品牌色需更亮）
- 避免纯黑背景（用 `#0D1117` 等近黑色）
- 文本层级明度差需足够明显

---

## 五、Fallback 机制

```
componentColor("button", "primary")
  → componentTokens["button"] 存在？
    → map["primary"] 存在？
      → ThemeColor ✅
      → null ⚠️
    → null ⚠️
```

| 方法 | 未命中 |
|------|--------|
| `semanticColor(key)` | `null` |
| `componentColor(c, t)` | `null` |
| `semanticColorOr(key, fallback)` | `fallback` |
| `componentColorOr(c, t, fallback)` | `fallback` |

原则：不抛异常、静默降级、通过 `unknown*Keys` / `invalidColors` 暴露问题。

---

## 六、完整示例

```json
{
  "type": "theme",
  "id": "ocean_blue",
  "name": "海洋蓝",
  "colors": {
    "primary": "#0D47A1",
    "secondary": "#42A5F5",
    "background": "#F0F4F8",
    "surface": "#FFFFFF",
    "error": "#E53935",
    "text": "#1A2332",
    "textSecondary": "#78909C",

    "sidebar": { "bg": "#0D47A1", "text": "#FFFFFF", "active": "#42A5F5", "hover": "#1565C0" },
    "bubble": { "user": "#0D47A1", "assistant": "#E8EDF2", "text": "#1A2332" },
    "thinking": { "bg": "#E3F2FD", "text": "#0D47A1", "border": "#90CAF9" },
    "toolCall": { "bg": "#FFF8E1", "text": "#E65100", "border": "#FFB74D" },
    "button": { "primary": "#0D47A1", "hover": "#0A3D8F", "active": "#082E6E", "disabled": "#BDBDBD", "text": "#FFFFFF" },
    "table": { "header": "#E3F2FD", "stripe": "#F5F8FC", "text": "#1A2332" }
  }
}
```

> 完整 54 组件 token 的完整色值定义见本文档 §三（组件 Token 子 token 表）。

---

## 七、调试与测试

### HTTP 端点验证

```bash
curl http://127.0.0.1:<port>/theme/health
curl http://127.0.0.1:<port>/theme/themes
curl http://127.0.0.1:<port>/theme/themes/light
curl -X POST http://127.0.0.1:<port>/theme/active -H "Content-Type: application/json" -d '{"id":"dark"}'
curl "http://127.0.0.1:<port>/theme/token?component=sidebar&token=bg"
```

### 平台端验证

主题加载后，平台自动应用。验证方法：

1. 启动平台 → 设置界面应出现你的主题
2. 选择主题 → UI 立即切换
3. HTTP API 查询当前激活的主题：

```bash
curl http://127.0.0.1:PORT/theme/active
```

### 命令行

将 `theme.json` 放入 `plugins/<name>/theme/` 目录，启动平台后自动加载。可通过 HTTP API 验证：

```bash
curl http://127.0.0.1:PORT/theme/themes
curl http://127.0.0.1:PORT/theme/themes/ocean_blue
curl -X POST http://127.0.0.1:PORT/theme/active -H "Content-Type: application/json" -d '{"id":"ocean_blue"}'
```

---

## 八、部署自检

- [ ] `type` = `"theme"`
- [ ] `id` 全局唯一
- [ ] 颜色格式 `#RRGGBB` 或 `#AARRGGBB`
- [ ] 语义 token 至少覆盖 `primary` + `background`
- [ ] 组件子 token 名与 §三 一致
- [ ] `theme.json` 为有效 UTF-8 JSON
- [ ] `theme.json` 放入 `plugins/<name>/theme/` 后平台自动加载成功
