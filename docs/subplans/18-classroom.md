# 18 — Classroom 智云课堂

**层级：** 六 | **估时：** 4 天 | **依赖：** 09 登录, 10 ZDBK | **关联 Bug：** BUG-06

---

## 1. 现状

智云课堂已实现课程列表、PPT 下载、字幕获取、视频播放、OCR、AI 笔记导入等核心功能。

### 1.1 已实现

| 功能 | 状态 |
|------|:----:|
| 课程列表（课程名 + 视频数） | ✅ |
| 视频播放器（media_kit） | ✅ |
| PPT 幻灯片逐页查看 | ✅ |
| 字幕检索/时间线 | ✅ |
| OCR 文字提取 | ✅ |
| AI 笔记导入（从 PPT 到 Tutor） | ✅ |
| 下载进度回调（FetchProgress） | ✅ |
| loading / empty / error 四态 | ✅ |

### 1.2 待实现

| 优先级 | 功能 | 说明 |
|:------:|------|------|
| **P0** | **BUG-06：导入 AI 笔记丢失 PPT 数据** | 按钮触发时未传递 PPT 图片，Tutor 收到空内容 |
| **P1** | **视频播放记忆进度** | 关闭后重新打开从上次位置继续 |
| P1 | 字幕搜索 | 跨课程搜索字幕文本，定位视频位置 |
| P2 | PPT 导出 PDF | 将幻灯片图片合并为 PDF 文件 |
| P2 | OCR 进度条 | 批量 OCR 时显示处理进度 |

---

## 2. 技术方案

### 2.1 BUG-06：导入 AI 笔记传递 PPT 数据

**现状：** `notes_screen.dart` 中的"导入 AI 笔记"按钮调用了 `importPptToTutor()`，但没有将当前 PPT 的图片数据附加到请求中。

**修复方案：**

```dart
// notes_screen.dart — 导入时携带 PPT 图片
Future<void> _importToTutor(PPT内容数据) async {
  final pptImages = await _fetchCurrentPptImages();
  final notifier = ref.read(tutorProvider.notifier);
  notifier.addSystemMessage('导入以下 PPT 内容：\n${pptImages.join('\n')}');
  // 然后调转到 AI 对话页面
  context.go('/tutor');
}
```

**关键文件：**
- `lib/features/tutor/screens/notes_screen.dart`
- `lib/features/tutor/providers/notes_provider.dart`

### 2.2 视频播放记忆进度

使用 `SharedPreferences` 存储 `classroom_video_progress_{courseId}_{subId}`：

```dart
// 保存进度
await prefs.setDouble('classroom_video_progress_${courseId}_$subId', position);

// 恢复进度
final saved = prefs.getDouble('classroom_video_progress_${courseId}_$subId');
if (saved != null && saved > 0) {
  player.seek(Duration(seconds: saved.toInt()));
}
```

**关键文件：**
- `lib/features/classroom/widgets/video_player_panel.dart`
- `lib/features/classroom/screens/classroom_viewer_screen.dart`

### 2.3 字幕搜索

使用现有字幕数据构建搜索索引：

```dart
final subtitles = await crawler.fetchSubtitles(subId);
final results = subtitles.where((s) =>
    s.text.contains(query) || s.textZh.contains(query));
// 点击结果 → 跳转到视频对应时间点
```

**关键文件：**
- `lib/features/classroom/widgets/subtitle_timeline.dart`

### 2.4 PPT 导出 PDF

使用 `pdf` 包（或打印服务）将 PPT 图片合成为 PDF：

```dart
final pdf = pw.Document();
for (final img in pptImages) {
  pdf.addPage(pw.Page(build: (ctx) => pw.Center(
    child: pw.Image(pw.MemoryImage(img.bytes)),
  )));
}
await File(path).writeAsBytes(await pdf.save());
```

### 2.5 OCR 进度条

`ClassroomCrawler` 已有 `OnFetchProgress` 回调。OCR 处理时同样触发进度回调：

```dart
int total = images.length;
for (var i = 0; i < total; i++) {
  onProgress?.call(FetchProgress(phase: 'ocr', completed: i + 1, total: total, elapsedMs: ...));
  final text = await _ocrImage(images[i]);
}
```

---

## 3. 实现顺序

| 步骤 | 内容 | 估时 |
|:----:|------|:----:|
| 1 | BUG-06：修复导入 AI 笔记 | 0.5 天 |
| 2 | 视频播放记忆进度 | 0.5 天 |
| 3 | 字幕搜索 UI + 逻辑 | 0.8 天 |
| 4 | PPT 导出 PDF | 0.8 天 |
| 5 | OCR 进度条 | 0.3 天 |

---

## 4. 验收标准

- [ ] BUG-06：导入 AI 笔记后 Tutor 正确收到 PPT 图片数据
- [ ] 视频进度记忆：关闭后重开从上次位置播放
- [ ] 字幕搜索输入关键词后正确高亮并跳转
- [ ] PPT 导出为可打开的 PDF 文件
- [ ] OCR 批量处理时显示进度条
- [ ] loading / empty / error / data 四态覆盖
- [ ] 全部现有 200+ 测试通过
