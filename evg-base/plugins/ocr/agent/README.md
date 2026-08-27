# plugins/ocr — OCR 工具「标准插件格式」示例（Task 四决策 4.2）

> 本目录是 **文档侧示例**，不是运行期独立插件。真实 OCR 能力由平台
> **内置 `ocr_file` / `check_ocr_ready` 工具**提供（Dart 实现，见
> `evg-base/lib/core/agent/tools/ocr_file_tool.dart`，内部走
> `core/services/ocr_pipeline.dart` 的 `OcrPipeline`——DeepSeek 云端 →
> Tesseract 本地两级降级）。

## 为什么这样设计（4.2 方案取舍）

spec 决策 4.2 要求「把 OCR 工具转成内置 agent tool 插件」「搬到
`plugins/xxx/agent/xxx` 下变成标准插件格式便于维护」。但 **OCR 管线
（OcrPipeline）是 Dart 侧实现**（DeepSeek 云端调用 + PDF 拆页 + Tesseract
子进程降级），无法用纯 Python 脚本复刻。因此采用组合方案：

| 部分 | 形态 | 说明 |
|------|------|------|
| 真实能力 | **Dart 内置工具** `ocr_file` / `check_ocr_ready` | 注册于 AI 助手三处注册点（app_bootstrap / agent_runtime / agent_factory），schema `file_path`（工作区相对路径或绝对路径），内部调 `OcrPipeline.recognizeFile` |
| 插件形态 | 本目录 `agent/manifest.json` + `agent/ocr_file.py` | 标准插件格式示例（`runtime:"python"` + `argMode:"stdin"` + `lifetime:"once"`），并作为未来 OCR 引擎 Python 化时的真实实现占位 |

**运行期行为**：因 `ocr_file` 已作为内置工具先注册，PluginBridge 扫描本插件时
按「同名跳过」处理（`PluginBridge.registerAll` 对已注册名称不重复注册），
不会产生重复工具或干扰内置工具。若未来移除内置工具，本插件即成为真实实现。

## 目录结构

```
plugins/ocr/
├── agent/
│   ├── manifest.json   # 标准 agent 插件 manifest（name/description/schema/readOnly/runtime/argMode/lifetime）
│   ├── ocr_file.py     # 纯标准库示例实现（pymupdf 文本层提取为可选增强）
│   └── README.md       # 本文件
```

## manifest 契约要点

| 字段 | 值 | 说明 |
|------|-----|------|
| `name` | `ocr_file` | 与 skill_creator 同名工具一致，便于 LLM 识别 |
| `description` | 中文 + 英文 | 对扫描版 PDF / 图片执行 OCR |
| `schema` | `{file_path: string}` | 工作区相对路径或绝对路径 |
| `readOnly` | `true` | 只读，可并行 |
| `runtime` | `"python"` | Python 入口 |
| `argMode` | `"stdin"` | 参数经 stdin JSON 注入 |
| `lifetime` | `"once"` | 一次性执行（Task 三决策 3.1） |

## 独立验证

```bash
# 格式示例自测（纯标准库，无需安装任何依赖）
echo '{"file_path": "/path/to/nonexistent.pdf"}' | python3 agent/ocr_file.py
# → {"error": "文件不存在: ..."}

# 有 pymupdf 环境下的文本层 PDF 提取
python3 -m pip install pymupdf   # 可选
echo '{"file_path": "text_layer.pdf"}' | python3 agent/ocr_file.py
```

## 依赖分发说明（spec「安装时按 Android / Windows 分别下载」）

- **Windows**：复用 `evg-base/scripts/requirements.txt` + 嵌入式 Python
  （`setup_python.cmd` 按需安装 pytesseract/Pillow/pdf2image/pymupdf），
  由 `OcrPipeline` Level 2 本地降级路径消费——已就绪，本次无新增。
- **Android**：本次**不新增 OCR 依赖**（遗留项）。现实上安卓端无系统
  Tesseract / poppler 二进制，OCR 主要靠 DeepSeek 云端降级；若后续需要
  本地 OCR，再在 `android/app/build.gradle.kts` 的 Chaquopy `pip {}`
  中按需添加纯 wheel 包。
