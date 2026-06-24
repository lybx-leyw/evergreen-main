---
task_type: bug-fix
tags: [flutter, lifecycle, async, pdf-preview, setState, dispose, mounted]
files_touched:
  - lib/features/translate/widgets/pdf_preview_widget.dart
difficulty: easy
outcome: success
date: 2026-06-24
---

## 尝试了什么
`PdfPreviewWidget` 的 `initState()` 中调用 `async _loadPdf()`，在 `await` 完成后直接 `setState()`。

## 为什么失败
`_loadPdf()` 有三个 `await` 点：
1. `await file.exists()` — 文件存在检查
2. `await PdfDocument.openFile()` — PDF 解析
3. `await page.render()` — 页面渲染

用户在任何 `await` 期间离开页面，widget 被 `dispose()`，后续 `setState()` 触发：

```
setState() called after dispose(): _PdfPreviewWidgetState
```

## 发现的问题
- `initState()` 中启动的 async 方法必须在每个 `await` 后检查 `mounted`
- `_renderPage()` 同样有两个 `await` 点（`page.render()` + `pdfImage.createImage()`），也缺 `mounted` 守卫

## 学到什么
1. **任何 async 方法中 `await` 后调 `setState()` 前必须 `if (!mounted) return`**
2. 这个模式与 Navigator.pop `_debugLocked` 同属"异步 + 生命周期"陷阱家族
3. `MediaQuery.of(context)` 在 dispose 后也会出问题，应在 await 前先取值

## 最终采用了什么替代方案
在每个 `await` 后加 `if (!mounted) return;` 守卫（共 5 处）：
- `_loadPdf()`: 3 处
- `_renderPage()`: 2 处
