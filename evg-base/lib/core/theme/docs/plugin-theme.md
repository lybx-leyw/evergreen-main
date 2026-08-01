# Theme 主题插件 — 快速参考卡

| 元信息 | 值 |
| --- | --- |
| 状态 | active |
| 版本 | 1.0 |
| 日期 | 2026-08-02 |
| 负责人 | 待补充 |
| 适用 | 主题插件作者 |

> 一页纸速查：文件位置、最小 JSON、8 色清单、颜色格式、校验清单。
> 当前模型：**扁平 8 色**（v1 五层 token 模型已废弃）。

---

## 文件位置

```
plugins/<name>/theme/theme.json
```

平台启动时自动扫描（`scanThemes`），无需注册代码。格式错误会输出 ❌ 日志并跳过。

---

## 最小 theme.json（8 色全必填）

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

| 字段 | 必填 | 含义 |
|------|:---:|------|
| `type` | ✓ | 固定 `"theme"` |
| `id` | ✓ | 全局唯一，建议 `snake_case`；**不要**用 `dark`/`light`/`default`/`evergreen` |
| `name` | ✓ | 展示名称（设置页主题下拉显示） |
| `colors` | ✓ | **8 个语义色全必填**（缺一即解析失败） |

## 8 个语义色

| key | 含义 | key | 含义 |
|-----|------|-----|------|
| `background` | 页面主背景 | `text` | 主文字 |
| `surface` | 卡片/面板底色 | `textSecondary` | 次级文字 |
| `border` | 边框/分隔线 | `accent` | 强调/品牌色 |
| `error` | 错误态 | `others` | 其余杂色 |

兼容别名：`primary` → `accent`，`secondary` → `others`（迁移旧主题用，新主题直接写规范名）。

## 颜色格式

| 格式 | 示例 | 说明 |
|------|------|------|
| `#RGB` | `#FFF` | 短格式 |
| `#RRGGBB` | `#1677FF` | **推荐** |
| `#AARRGGBB` | `#801677FF` | 含 alpha |

不支持：颜色名、`rgb()`、`hsl()`、无 `#` 前缀的 hex。

## 规则

- `type` 必须为 `"theme"`，否则抛出 `FormatException`
- 同 `id` 后者覆盖（优先级：代码注册 > 插件 > 示例）
- 加载失败只会 stderr 提示，不会崩溃——**失败后去终端看 ❌ 日志**

## 校验清单

- [ ] `type` = `"theme"`
- [ ] `id` 全局唯一（不与内置 `dark`/`light`/`default`/`evergreen` 冲突）
- [ ] `colors` **8 键齐全**：background / surface / border / text / textSecondary / accent / error / others
- [ ] 颜色值均为 `#RRGGBB` 或 `#AARRGGBB`
- [ ] `theme.json` 为有效 UTF-8 JSON

## 验证方法

1. 放入 `plugins/<name>/theme/theme.json`
2. 重启应用（或查看启动日志确认无 ❌）
3. 打开「设置」→「外观 · 主题」下拉，应出现你的主题
4. 选中即全局换肤；重启后保持
