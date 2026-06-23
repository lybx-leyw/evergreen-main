---
task_type: feature
tags: [python, subprocess, pdf2zh, pip, translate, deps]
files_touched:
  - lib/core/services/pdf_translate_service.dart
  - lib/core/utils/python_env.dart
  - lib/core/errors.dart
  - lib/core/config/app_config.dart
  - lib/features/translate/providers/translate_provider.dart
  - lib/features/translate/screens/translate_screen.dart
  - scripts/pdf_translate.py
  - scripts/pdf2zh_next/
difficulty: hard
outcome: success
date: 2026-06-19
related_pr: 2026-06-19-pdf-translate.md
---

## 做了什么

将 PDFMathTranslate-next 的 DeepSeek API PDF 翻译能力集成到 Evergreen，通过 Python 子进程调用内置于 `scripts/pdf2zh_next/` 的 pdf2zh 引擎。

## 关键决策

- **引擎源码内置而非 pip 安装**：pdf2zh 上游是 AGPL-3.0，依赖复杂。决策：将精简后的引擎源码放入 `scripts/pdf2zh_next/`，仅保留 `config/` `translator/` `high_level.py`，删除 GUI/CLI/assets
- **JSON 事件流协议**：子进程 stdout → 逐行 JSON（`{"type":"progress",...}` / `{"type":"finish",...}`），与 OCR 子进程保持一致的通信模式
- **自动依赖安装**：首次使用时自动检测 Python → 导入 pdf2zh → 缺失则 `pip install babeldoc pymupdf openai`，无需用户手动操作
- **复用 DeepSeek API Key**：翻译不额外要求 API Key，复用 AppConfig 已有的 `deepseekApiKey`

## 踩过的坑

### 1. Windows 中文路径下 Python import 失败
- **现象**：`sys.path.insert(0, scriptsDir)` 在路径含中文字符时，Python 子进程 import pdf2zh 报 `ModuleNotFoundError`
- **根因**：`Process.start` 传递的路径编码问题
- **解决**：在 `checkPdf2zhDeps()` 和 `PdfTranslateService.translate()` 中，始终对路径做 `replaceAll('\\', '\\\\')` 处理

### 2. SharedPreferences 旧版类型残留导致启动崩溃
- **现象**：v1.1 升级后，`AppConfig.initialize()` 的 `_loadFromPrefs()` 中 `getString()` 读取旧版 `bool` / `int` 类型的 key 时抛出 `TypeError`
- **根因**：早期版本直接用 `setBool()` / `setInt()` 写 SharedPreferences，新版改为全 String 存储
- **解决**：在 `main.dart` 新增 `_healLegacyPrefs()`，启动时遍历所有配置 key，检测类型不匹配则用 `remove()` + `setString()` 修复

### 3. Dart `??` 运算符优先级陷阱
- **现象**：`translate_screen.dart:267` 的 `a ?? b ? c : d` 导致 String→bool 类型崩溃
- **根因**：`??` 和 `?:` 的优先级——Dart 将 `a ?? b ? c : d` 解析为 `(a ?? b) ? c : d`，而非 `a ?? (b ? c : d)`
- **解决**：显式加括号 `a ?? (b ? c : d)`

## 可复用的模式

### Python 子进程环境检测模式
```dart
// 检测 → 安装 → 再检测 的三段式
Future<String?> ensureReady(scriptsDir) async {
  final hasPython = await checkPython();
  if (!hasPython) return '未找到 Python';

  final missing = await checkDeps(scriptsDir);
  if (missing == null) return null;           // 全部就绪

  await installDeps();                        // 自动安装
  final stillMissing = await checkDeps(scriptsDir);
  if (stillMissing != null) return stillMissing; // 安装失败
  return null;                                // 就绪
}
```

### JSON 事件流子进程模式
```dart
process.stdout
  .transform(utf8.decoder)
  .transform(const LineSplitter())
  .listen((line) {
    final event = jsonDecode(line);
    switch (event['type']) {
      case 'progress': onProgress(...);
      case 'finish': completer.complete(result);
      case 'error': completer.completeError(...);
    }
  });
```

## 注意事项

- 修改 `AppConfig` 新增配置字段必须**五处同步**（env / envFile / prefs / set / saveToEnvFile）
- Python 子进程必须设置 `includeParentEnvironment: true`（传递 HF_TOKEN）
- pdf2zh 是 AGPL-3.0，修改其源码必须在 `ATTRIBUTION.md` 中记录
- Android 不支持 Python 子进程，翻译功能标记为"开发中"
