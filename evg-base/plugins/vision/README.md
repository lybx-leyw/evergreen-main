# plugins/vision — 多模态视觉工具（OCR / 读图描述 / 生图占位）

> Task R3-5：在 R3-4 砍掉整套 OCR 路径后，重建为 **vision 多模态工具插件**——
> 以「Agent 工具插件 + 插件包 API 设置项」同包形态提供，桌面/安卓一致。
> Task R3-6：安卓 PDF 拆分平替——manifest 声明 `preprocess: "pdf_split"`，Dart 侧
> 在 Agent 调用前经 MethodChannel `evergreen/pdf` 调系统 `PdfRenderer` 预拆分，
> 以 `pages_dir` 注入 vision.py（详见 `.agent_team/evergreen/output/explore_R3-6_pdf_renderer.md`）。

## 功能

| mode | 说明 | API 配置 |
|------|------|---------|
| `ocr` | 提取图片 / PDF / PPT 中的文字（OpenAI 兼容 chat/completions 图片输入） | `OCR_API_BASE_URL` / `OCR_API_KEY` / `OCR_API_MODEL` |
| `describe` | 详细描述图片内容 | `VISION_API_BASE_URL` / `VISION_API_KEY` / `VISION_API_MODEL` |
| `generate` | 生图（**占位**，即将上线，不调 API） | — |

## 用法

Agent 经 PluginBridge 自动注册为工具 `vision`（stdin JSON + `runtime:"python"` + `lifetime:"once"` +
`preprocess:"pdf_split"`），AI 助手工具列表可见；也可命令行直接调用：

```bash
# 冒烟测试
python3 plugins/vision/agent/vision.py --help
python3 plugins/vision/agent/vision.py --self-check
echo '{"mode":"ocr","file_path":"scan.png"}' | python3 plugins/vision/agent/vision.py
```

stdin 参数：`{"mode": "ocr|describe|generate", "file_path": "工作区相对或绝对路径"}`。
可选内部参数 `pages_dir`（平台侧预拆分页图片目录，**由 Dart 侧注入，LLM 不感知**）：
存在时按页读取并跳过本地 PDF 拆分。

## API 配置

在设置面板（插件包 `config/config.json` 自动注册进设置，`_stepSettings` 扫描
`plugins/<id>/config/config.json`）填写 6 个设置项；设置经 `.greenix/config.json`
镜像（`GREENIX_CONFIG_PATH` 环境变量桌面/安卓已注入），脚本三级降级读取：
config.json（GREENIX_CONFIG_PATH）→ CWD/PROJECT_ROOT 下 `.greenix/config.json` → 环境变量。
未配置时输出可解析错误提示 `[error: vision: 请先在设置中配置 OCR API / Vision API（base_url/api_key/model）]`。

## 文件类型处理

- **图片**：png / jpg / jpeg / bmp / webp / tiff —— base64 data URI 直传。
- **PDF**：
  - 桌面：pymupdf(fitz) 逐页渲染 PNG（dpi=150）→ 逐页并发调 API（内部路径，不变）。
  - 安卓：Dart 侧（`VisionPdfPreprocess`）经 MethodChannel `evergreen/pdf` 调系统
    `PdfRenderer` 预拆分（150dpi，最长边 4096px 封顶防 OOM）→ 页图片目录以
    `pages_dir` 注入 → vision.py 按页号读取（`page_%04d.png` 数字排序）。
  - 预拆分失败 fail-open：原参透传，vision.py 输出降级提示（不崩溃）。
- **PPT/PPTX**：zipfile 纯标准库解包 `ppt/slides/media/*` 内嵌图片（不引 python-pptx；
  桌面/安卓一致，不受 pymupdf 影响）。
- 多页 `ThreadPoolExecutor(max_workers=4)` 并发，429 退避重试（1s/2s），单页失败不阻塞
  整篇，汇总标注页码/媒体名；全失败才返回 `[error: vision: ...]`。

## 输出约定

stdout 纯文本（Agent 工具可解析）；错误统一 `[error: vision: ...]` 前缀、退出码 0 不崩溃。

## 依赖与打包

- **零新增 pub 依赖**；Python 侧仅请求库 requests（嵌入式 Python 与安卓 Chaquopy 均已
  内置，缺失时回退 stdlib urllib）与 **pymupdf(fitz)**（PDF 拆分，仅桌面）。
- **桌面**：pymupdf 已在 `scripts/requirements.txt` 声明（paper_reader.py 共用），
  `setup_python.cmd` 预装到嵌入式 Python；行为与 R3-5 完全一致。
- **安卓**：Chaquopy Android 索引无 pymupdf wheel（2026-08 CI 验证），**不加入
  `chaquopy.pip`**；PDF 拆分改由 **Android 系统内置 PdfRenderer**（API 21+，零依赖）
  在 Kotlin 侧完成（`MainActivity.kt` 新增 `evergreen/pdf` 通道），Dart 预拆分后
  以 `pages_dir` 注入 vision.py。图片/PPT 处理不受影响。
- **打包镜像**：`assets/plugins_bundle/vision/` 由 `tool/bundle_plugins.dart` 生成
  （gitignored 产物），pubspec `>>>PLUGIN_ASSETS_START>>>` 标记块自动重写。

## 目录结构

```
plugins/vision/
├── agent/
│   ├── manifest.json   # name: "vision", argMode: "stdin", runtime: "python",
│   │                   # lifetime: "once", preprocess: "pdf_split"
│   └── vision.py       # stdin JSON → mode 分派 → OpenAI 协议 API（requests/urllib）
├── config/
│   └── config.json     # 6 个设置项（OCR_API_* / VISION_API_*）
└── README.md           # 本文件
```
