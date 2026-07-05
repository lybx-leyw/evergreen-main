# plugin-theme — 插件主题开发规范

> 面向插件开发者：如何编写 `theme.json` 为 Evergreen 平台提供配色方案。

---

## 一、文件位置

```
plugins/<your_plugin>/theme/theme.json
```

插件目录结构示例：

```
plugins/acme_corp/
  module/manifest.json    ← UI 声明
  theme/theme.json        ← 配色方案
  data/manifest.json      ← 数据源（可选）
  config/config.json      ← 设置项（可选）
```

---

## 二、最小 theme.json

至少需要 `type`、`id`、`name` 和一个语义 token：

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

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `type` | `"theme"` | ✓ | 固定值 |
| `id` | string | ✓ | 全局唯一标识（snake_case 建议） |
| `name` | string | ✓ | 展示名称（支持中文） |
| `colors` | object | ✓ | 颜色映射；值为字符串为语义 token，值为对象为组件 token |

---

## 三、colors 规则

### 3.1 值类型决定 token 类别

| 值的类型 | 映射到 | 示例 |
|----------|--------|------|
| 字符串（`"#xxx"`） | **语义 token** | `"primary": "#1677FF"` |
| 对象（`{...}`） | **组件 token** | `"sidebar": { "bg": "#FFF" }` |

### 3.2 颜色格式

支持三种 hex 格式：

| 格式 | 示例 | 说明 |
|------|------|------|
| `#RGB` | `#FFF` | 短格式（展开为 `#FFRRGGBB`） |
| `#RRGGBB` | `#1677FF` | 推荐标准格式 |
| `#AARRGGBB` | `#801677FF` | 含 alpha 通道 |

### 3.3 同 id 覆盖

后加载的主题覆盖先加载的同 `id` 主题。建议内置主题（`default`、`light`、`dark`）不被覆盖；自定义主题使用不同的 `id`。

---

## 四、语义 token（20 个）

| # | key | 说明 | 建议值 |
|---|-----|------|--------|
| 1 | `primary` | 主色 | 品牌色 |
| 2 | `secondary` | 辅色 | 略浅于 primary |
| 3 | `tertiary` | 第三色 | 最浅变体 |
| 4 | `background` | 页面背景 | 浅色主题用 `#F5F6F8` |
| 5 | `surface` | 卡片/容器背景 | 浅色主题用 `#FFFFFF` |
| 6 | `surfaceVariant` | 次级容器背景 | 略暗于 surface |
| 7 | `error` | 错误/危险色 | `#FF4D4F` |
| 8 | `success` | 成功色 | `#52C41A` |
| 9 | `warning` | 警告色 | `#FA8C16` |
| 10 | `info` | 信息色 | 同 primary 或 `#1677FF` |
| 11 | `text` | 正文 | 深色 |
| 12 | `textSecondary` | 次要文本 | 中灰色 |
| 13 | `textTertiary` | 三级文本 | 浅灰色 |
| 14 | `textInverse` | 反色文本 | 深底白字 |
| 15 | `border` | 边框 | `#D0D5DD` |
| 16 | `shadow` | 阴影 | `#000000` |
| 17 | `overlay` | 遮罩 | `#000000` |
| 18 | `disabled` | 禁用态 | 浅灰 |
| 19 | `placeholder` | 占位符 | 比 textSecondary 更浅 |
| 20 | `divider` | 分割线 | `#E8EAED` |

---

## 五、组件 token（54 个）

### 导航（5）

| 组件 | 子 token |
|------|---------|
| `sidebar` | `bg`, `text`, `active`, `hover` |
| `tab` | `text`, `active`, `indicator`, `hover` |
| `breadcrumb` | `text`, `link`, `separator` |
| `pagination` | `bg`, `active`, `text`, `hover` |
| `stepper` | `done`, `active`, `pending`, `line` |

### 对话（5）

| 组件 | 子 token |
|------|---------|
| `bubble` | `user`, `assistant`, `text`, `timestamp` |
| `thinking` | `bg`, `text`, `border` |
| `toolCall` | `bg`, `text`, `border` |
| `codeBlock` | `bg`, `text`, `border`, `header` |
| `blockquote` | `border`, `text`, `bg` |

### 表单（7）

| 组件 | 子 token |
|------|---------|
| `input` | `bg`, `text`, `border`, `focus`, `placeholder`, `error` |
| `checkbox` | `border`, `fill`, `check` |
| `radio` | `border`, `fill` |
| `switch_` | `track`, `thumb`, `trackActive` |
| `slider` | `track`, `fill`, `thumb` |
| `dropdown` | `bg`, `text`, `border`, `itemHover` |
| `datePicker` | `header`, `selected`, `today`, `hover` |

### 反馈（6）

| 组件 | 子 token |
|------|---------|
| `progressBar` | `track`, `fill`, `text` |
| `spinner` | `color`, `track` |
| `skeleton` | `bg`, `shimmer` |
| `toast` | `bg`, `text`, `border`, `success`, `error`, `warning`, `info` |
| `alert` | `bg`, `text`, `border`, `icon` |
| `emptyState` | `icon`, `text`, `action` |

### 数据展示（9）

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

### 按钮（3）

| 组件 | 子 token |
|------|---------|
| `button` | `primary`, `hover`, `active`, `disabled`, `text` |
| `iconButton` | `color`, `hover`, `active` |
| `fab` | `bg`, `icon`, `shadow` |

### 布局（6）

| 组件 | 子 token |
|------|---------|
| `drawer` | `bg`, `text`, `overlay` |
| `modal` | `bg`, `overlay`, `text`, `border` |
| `header` | `bg`, `text`, `border` |
| `footer` | `bg`, `text`, `border` |
| `divider` | `color`, `thickness` |
| `scrollbar` | `thumb`, `track` |

### 图表（1）

| 组件 | 子 token |
|------|---------|
| `chart` | `colors`, `axis`, `grid`, `tooltip` |

### 媒体（3）

| 组件 | 子 token |
|------|---------|
| `videoPlayer` | `controls`, `progress`, `overlay` |
| `audioPlayer` | `controls`, `waveform`, `progress` |
| `imageViewer` | `bg`, `overlay` |

### 杂项（5）

| 组件 | 子 token |
|------|---------|
| `link` | `text`, `hover`, `visited` |
| `menu` | `bg`, `text`, `hover`, `divider` |
| `commandPalette` | `bg`, `text`, `highlight`, `border` |
| `contextMenu` | `bg`, `text`, `hover`, `divider` |
| `search` | `bg`, `text`, `border`, `focus`, `icon` |

### 范式（4）

| 组件 | 子 token |
|------|---------|
| `spreadsheet` | `header`, `grid`, `cell`, `cellSelected`, `formulaBar`, `tab` |
| `document` | `bg`, `text`, `ruler`, `pageShadow`, `comment`, `selection` |
| `presentation` | `bg`, `canvas`, `slideBorder`, `toolbar`, `notes` |
| `workspace` | `bg`, `tabBar`, `panel`, `resizeHandle`, `empty` |

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

---

## 七、注册与加载

主题由 `ThemeLoader` 自动发现：扫描 `plugins/` 下各子目录的 `theme/theme.json` 并注册到 `ThemeStore`。插件开发者只需将 `theme.json` 放入正确位置即可，无需额外注册代码。

### 加载优先级

1. Dart 代码中直接 `store.register(ThemeDescriptor(...))` — 最高
2. 示例目录 `example/plugins/` — 开发调试用
3. 内置主题 `builtins/` — 最低（可被同 id 覆盖）

---

## 八、深色/浅色适配

平台内置 `light`（浅色）和 `dark`（深色）两个基础主题。插件不需要单独提供双主题；平台使用者可通过 `ThemeStore.activeTheme` 切换已注册的任意主题。

如果插件想提供双主题变体，建议命名规则：

```
plugins/my_plugin/theme/
  light_my.json    ← id: "light_my"
  dark_my.json     ← id: "dark_my"
```

---

## 九、校验清单

部署前自检：

- [ ] `type` = `"theme"`
- [ ] `id` 全局唯一（不与内置 `light`/`dark`/`default` 冲突）
- [ ] 颜色值使用 `#RRGGBB` 或 `#AARRGGBB` 格式
- [ ] 语义 token 至少覆盖 `primary` 和 `background`
- [ ] 组件 token 子 token 名与本文档一致
- [ ] `theme.json` 为有效 UTF-8 JSON
