# 08 · 文件与媒体

视频、PDF、图片、文档——任何文件都可以内嵌展示。

## 核心概念

`accept` 声明文件后缀，下游自动匹配渲染器。不是写 `type: "video"`，而是写 `accept: "*.mp4"`。

## 通用字段

```json
{
  "media": {
    "accept": "*.mp4,*.webm",
    "mode": "fullscreen",
    "direction": "top",
    "controls": true
  }
}
```

| 字段 | 默认值 | 说明 |
|------|--------|------|
| `accept` | `"*.*"` | 文件后缀，逗号分隔 |
| `mode` | `"inline"` | 展示模式 |
| `controls` | `true` | 显示控件/工具栏 |

## 五种展示模式

| `mode` | 效果 |
|--------|------|
| `"inline"` | 内嵌在页面内容流中，随滚动 |
| `"fullscreen"` | 撑满模块视口（保留导航栏） |
| `"drawer"` | 从边缘滑入面板，推挤内容 |
| `"dropdown"` | 从顶部下拉，下方内容重排 |
| `"fixed"` | 固定尺寸区域 |

`drawer`/`dropdown` 用 `direction` 控制方向（`"top"` / `"bottom"` / `"left"` / `"right"`）。

`fixed` 用 `fixedSize` 定尺寸：

```json
{ "mode": "fixed", "fixedSize": { "width": 640, "height": 360 } }
```

不填 = 自适应。

---

## 后缀匹配 → 专属选项

根据 `accept` 的后缀，可以写对应子块：

### 视频（`*.mp4,*.webm,*.avi,*.mov`）

```json
{ "video": { "speeds": [0.5, 1.0, 1.5, 2.0], "cache": true, "quality": "auto", "captions": false } }
```

### 音频（`*.mp3,*.wav,*.ogg,*.flac`）

```json
{ "audio": { "speeds": [0.5, 1.0, 1.5, 2.0], "waveform": false } }
```

### 文档（`*.pdf,*.docx,*.pptx,*.xlsx`）

```json
{ "document": { "zoomable": true, "searchable": true, "pageIndicator": true, "paginated": false } }
```

### 图片（`*.jpg,*.png,*.gif,*.svg,*.webp`）

```json
{ "image": { "zoomable": true, "gallery": false } }
```

---

## 常用配方

```jsonc
// 课程视频——全屏倍速
{ "media": { "accept": "*.mp4", "mode": "fullscreen", "video": { "speeds": [0.5,1,1.5,2] } } }

// 讲义 PDF——下拉分页
{ "media": { "accept": "*.pdf", "mode": "dropdown", "document": { "paginated": true, "zoomable": true } } }

// 图片画廊——全屏翻页
{ "media": { "accept": "*.jpg,*.png", "mode": "fullscreen", "image": { "gallery": true } } }

// Word 文档——固定区域
{ "media": { "accept": "*.docx", "mode": "fixed", "fixedSize": { "height": 600 } } }
```

## 下一步

- [09 · 文件工作区](09-workspace.md)
