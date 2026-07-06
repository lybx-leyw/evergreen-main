# Theme 主题插件 — 快速参考卡

> 一页纸速查：文件位置、最小 JSON、Token 列表、颜色格式、校验清单。
> **完整指南**（字段详解、Token 系统、Fallback 机制、完整示例）→ `plugin-authoring-guide-theme.md`

---

## 文件位置

```
plugins/<name>/theme/theme.json
```

---

## 最小 theme.json

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

| 字段 | 必填 | 说明 |
|------|------|------|
| `type` | ✓ | 固定 `"theme"` |
| `id` | ✓ | 全局唯一，建议 `snake_case` |
| `name` | ✓ | 展示名称 |
| `colors` | ✓ | 字符串值 → 语义 token，对象值 → 组件 token |

---

## 语义 Token（20 个）

`primary` `secondary` `tertiary` `background` `surface` `surfaceVariant`
`error` `success` `warning` `info` `text` `textSecondary` `textTertiary`
`textInverse` `border` `shadow` `overlay` `disabled` `placeholder` `divider`

---

## 组件 Token（54 个，子 token 从略）

| 分类 | 组件 |
|------|------|
| 导航 | `sidebar` `tab` `breadcrumb` `pagination` `stepper` |
| 对话 | `bubble` `thinking` `toolCall` `codeBlock` `blockquote` |
| 表单 | `input` `checkbox` `radio` `switch_` `slider` `dropdown` `datePicker` |
| 反馈 | `progressBar` `spinner` `skeleton` `toast` `alert` `emptyState` |
| 数据 | `table` `card` `list` `chip` `avatar` `badge` `tooltip` `calendar` `timeline` |
| 按钮 | `button` `iconButton` `fab` |
| 布局 | `drawer` `modal` `header` `footer` `divider` `scrollbar` |
| 图表 | `chart` |
| 媒体 | `videoPlayer` `audioPlayer` `imageViewer` |
| 杂项 | `link` `menu` `commandPalette` `contextMenu` `search` |
| 范式 | `spreadsheet` `document` `presentation` `workspace` |

> 完整子 token 定义 → `docs/plugin-authoring-guide-theme.md` §三。

---

## 颜色格式

| 格式 | 示例 | 说明 |
|------|------|------|
| `#RGB` | `#FFF` | 短格式 |
| `#RRGGBB` | `#1677FF` | **推荐** |
| `#AARRGGBB` | `#801677FF` | 含 alpha |

不支持：颜色名、`rgb()`、`hsl()`、无 `#` 前缀的 hex。

---

## 规则

- `type` 必须为 `"theme"`，否则抛出 `FormatException`
- 同 `id` 后者覆盖（优先级：`store.register()` > `example/plugins/` > `builtins/`）
- 不要用 `light`/`dark`/`default` 作为自定义 id
- 平台通过 `scanThemes()` 自动发现，无需额外注册代码

---

## 校验清单

- [ ] `type` = `"theme"`
- [ ] `id` 全局唯一（不与内置 `light`/`dark`/`default` 冲突）
- [ ] 颜色值使用 `#RRGGBB` 或 `#AARRGGBB`
- [ ] 语义 token 至少覆盖 `primary` 和 `background`
- [ ] 组件子 token 名与规范一致
- [ ] `theme.json` 为有效 UTF-8 JSON
