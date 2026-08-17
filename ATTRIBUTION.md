# 致谢与开源合规声明

Evergreen 2.0 建立在大量优秀的开源项目之上。我们在此郑重致谢，并声明本项目严格遵守各上游项目的开源许可协议。

---

## 一、特别致谢

### Reasonix → Greenix（Agent 运行时核心）

| 项目 | 说明 |
|------|------|
| **Reasonix** | AI 编码助手的 Agent 运行时（Go 实现），MIT License |
| 仓库 | https://github.com/esengine/reasonix |
| 移植 | Greenix — 参考 Reasonix 架构，以 Dart 复刻核心逻辑 |
| 授权 | MIT 许可证允许再分发与修改，本项目在源码文件中保留了指向原始 Go 源的文档注释 |

参考复刻的模块：`message`、`event`、`tool`、`provider`、`agent`、`session`、`controller`、`memory` 等关键抽象（详见 `evg-base/ATTRIBUTION.md`）。

### pdf2zh（PDF 翻译引擎）

| 项目 | 说明 |
|------|------|
| **pdf2zh** | 学术 PDF 双语翻译工具，AGPL-3.0 License |
| 仓库 | https://github.com/Byaidu/PDFMathTranslate |
| 使用方式 | `scripts/pdf2zh_next/` 为 pdf2zh 的本地化集成模块，作为 Python 管线被 `paper_reader.py` / `pdf_translate.py` 通过 import 调用 |
| 合规性 | pdf2zh 为 AGPL-3.0，本项目为 GPL-3.0（兼容性 OK）；本项目仅通过子进程调用，未修改 pdf2zh 核心代码；pdf2zh_next 仅做配置适配与接口封装 |

pdf2zh 使得 Evergreen 能够实现高质量的中英文学术论文翻译，特别感谢其作者 [Byaidu](https://github.com/Byaidu)。

### reverse-skill → Scraper 安全治理机制（AI 探索模式）

| 项目 | 说明 |
|------|------|
| **reverse-skill** | 安全任务 AI 技能路由器（授权门 / 证据链 / 决策框架 / 经验回写），MIT License |
| 仓库 | https://github.com/zhaoxuya520/reverse-skill |
| 作者 | [zhaoxuya520](https://github.com/zhaoxuya520) |
| 移植 | Scraper AI 探索模式（Phase 4）借鉴其机制设计：持久化授权范围（Scope Contract）→ `.greenix/scope.json`、候选数据源证据绑定（Evidence → Finding）→ `CandidateDataSource.evidence`、无进展熔断（R43）、经验 Journal 回写（field-journal）、工具能力事实源注入（tool-index）与借口反驳表 |
| 授权 | MIT 许可证允许参考与再实现；本项目仅借鉴机制与接口形态，未复制其源代码文件，相关实现见 `Scraper_reverse-skill_集成策略.md` |

reverse-skill 的安全任务治理思路（"AI 对真实目标执行有副作用操作时必须可授权、可追溯、可熔断"）直接补全了 Scraper 探索模式在持久化授权与正面证据上的缺口。

### 教师评分数据 — Lazuli（ZJU 教务增强）

- **内置数据集（只读 asset）**: [`evg-base/assets/data/teacher_ratings.json`](evg-base/assets/data/teacher_ratings.json)（完整数据集，1.5 MB，随应用打包）
- **原始冻结副本**: [`evg-base/docs/reference/teacher_ratings_original.json`](evg-base/docs/reference/teacher_ratings_original.json)（对照基准，永不被修改）
- **来源**: Lazuli — 浙江大学教务系统增强插件
- **作者**: [ADSR1042](https://github.com/ADSR1042)
- **仓库**: https://github.com/ADSR1042/Lazuli
- **许可证**: GNU General Public License v3.0

该数据集包含浙江大学教师的公开评分信息，仅用于教学辅助用途。

**运行时修改声明：** 本应用在运行时从 `chalaoshi.top` 在线抓取最新评分与热度，并写回**应用文档目录**下的 `teacher_ratings.json` 缓存副本（`_getCacheFile()` / `_saveToLocal()` 负责）；内置 asset 只读、永不被覆写。修改逻辑位于 [`evg-base/lib/renderer/templates/zju_modle/teachers/services/chalaoshi_service.dart`](evg-base/lib/renderer/templates/zju_modle/teachers/services/chalaoshi_service.dart) 的 `_mergeOnlineResults()` 和 `_saveToLocal()` 方法。文件结构、教师 `id`/`name`/`py`/`sx`/`xy` 字段及学院数据**保持不变**，仅 `rate`（评分）与 `hot`（热度）数值被更新。

根据 GPL v3 第 5 条的要求：完整源代码可在上述仓库获取，任何修改必须标明，数据以"原样"提供且无任何担保。

---

## 二、所有第三方依赖致谢

### Flutter / Dart 生态（39 项）

| 依赖 | 许可 | 用途 |
|------|------|------|
| **Flutter** | BSD-3-Clause | 应用框架 |
| **Dart** | BSD-3-Clause | 语言运行时 |
| **flutter_riverpod** | MIT | 状态管理 |
| **go_router** | BSD-3-Clause | 声明式路由 |
| **dio** | MIT | HTTP 客户端 |
| **shared_preferences** | BSD-3-Clause | 键值对本地存储 |
| **path_provider** | BSD-3-Clause | 平台路径 |
| **url_launcher** | BSD-3-Clause | URL 启动 |
| **webview_flutter** | BSD-3-Clause | WebView 内嵌 |
| **window_manager** | MIT | 桌面窗口管理 |
| **screen_retriever_windows** | MIT | 屏幕信息检索 |
| **uuid** | MIT | UUID 生成 |
| **path** | BSD-3-Clause | 路径工具 |
| **archive** | MIT | 压缩/解压 |
| **crypto** | BSD-3-Clause | 加密哈希 |
| **media_kit** | MIT | 视频播放（基于 libmpv） |
| **flutter_markdown** | BSD-3-Clause | Markdown 渲染 |
| **flutter_math_fork** | MIT | 数学公式（KaTeX） |
| **flutter_widget_from_html** | MIT | HTML 渲染 |
| **flutter_highlight** | MIT | 代码语法高亮 |
| **flutter_mermaid** | MIT | Mermaid 图表渲染 |
| **flutter_svg** | BSD-3-Clause | SVG 渲染 |
| **google_fonts** | Apache-2.0 | Google 字体加载 |
| **file_picker** | MIT | 文件选择对话框 |
| **re_editor** | MIT | 代码编辑器组件 |
| **webview_windows** | MIT | Windows WebView |
| **xterm** | MIT | 终端模拟器 UI |
| **flutter_pty** | MIT | 伪终端后端 |
| **diff_match_patch** | Apache-2.0 | 文本差异算法 |
| **watcher** | BSD-3-Clause | 文件系统监控 |
| **pdfx** | MIT | PDF 渲染 |
| **mobile_scanner** | MIT | 摄像头扫码 |
| **markdown** | BSD-3-Clause | Markdown 解析 |
| **meta** | BSD-3-Clause | Dart 元注解 |

### Python 生态（20 项）

| 依赖 | 许可 | 用途 |
|------|------|------|
| **PyMuPDF (fitz)** | AGPL-3.0 / 商业 | PDF 文本提取 |
| **pytesseract** | Apache-2.0 | OCR 文字识别 |
| **Pillow** | HPND (PIL) | 图像处理 |
| **pdf2image** | MIT | PDF 转图片 |
| **requests** | Apache-2.0 | HTTP 请求 |
| **httpx** | BSD-3-Clause | 异步 HTTP 客户端 |
| **pydantic** | MIT | 数据模型验证 |
| **tomlkit** | MIT | TOML 配置解析 |
| **openai** | Apache-2.0 | OpenAI API 客户端 |
| **tenacity** | Apache-2.0 | 重试机制 |
| **peewee** | MIT | 轻量 ORM（翻译缓存） |
| **babeldoc** | AGPL-3.0 | PDF 翻译核心引擎 |
| **rich** | MIT | 终端富文本输出 |
| **deepl** | MIT | DeepL 翻译客户端 |
| **ollama** | MIT | Ollama 本地 LLM 客户端 |
| **azure-ai-translation-text** | MIT | Azure 翻译服务 |
| **xinference-client** | Apache-2.0 | Xinference LLM 客户端 |
| **tencentcloud-sdk-python** | Apache-2.0 | 腾讯云机器翻译 SDK |
| **pycryptodome** | BSD-2-Clause / Public Domain | RSA/AES 加密 |
| **Cha****quopy** | MIT | Android 端 Python 运行时 |

---

## 三、合规声明

### 3.1 许可兼容性

| 本项目许可 | GPL-3.0 |
|------------|---------|
| MIT / BSD / Apache-2.0 依赖 | ✅ 完全兼容，GPL-3.0 允许链接 |
| AGPL-3.0 依赖（pdf2zh、babeldoc、PyMuPDF） | ✅ AGPL-3.0 ↔ GPL-3.0 兼容，本项目通过子进程调用，未修改上游源码 |
| 商业许可（PyMuPDF 商业版） | N/A — 本项目仅使用 AGPL-3.0 授权的开源版本 |

### 3.2 署名保留

- **Reasonix → Greenix**：参考移植的 Dart 文件头部保留指向 Reasonix 原始 Go 源的文档注释，`evg-base/ATTRIBUTION.md` 中列出映射关系
- **pdf2zh**：`scripts/pdf2zh_next/` 目录保留原始模块结构和版权声明，`paper_reader.py` 注释中标注调用链
- **所有 Flutter/Dart 依赖**：通过 `pubspec.yaml` 标准依赖声明，编译器自动保留包内 LICENSE 文件
- **所有 Python 依赖**：通过 `pip` / `requirements.txt` 标准依赖声明

### 3.3 使用方式

- 本项目**未修改**任何上游依赖的源代码（`pdf2zh_next/` 仅做配置适配和接口封装，不修改 pdf2zh 核心逻辑）
- Reasonix 的架构参考与核心逻辑复刻属于 MIT 许可证明确允许的行为
- 所有 Python 脚本通过**子进程 JSON Lines 协议**与核心通信，属于标准的进程隔离调用，不构成代码合并

### 3.4 Evergreen 自身许可

**Evergreen Base** 以 **GNU General Public License v3.0 (GPL-3.0)** 发布。

```
Evergreen Base
Copyright (C) 2024-2026  Evergreen Base 贡献者

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.
```

---

## 四、致所有开源贡献者

每当你打开 Evergreen，你使用的不仅是我们的代码——更是成百上千开源贡献者数十年心血的结晶。从 Flutter 框架到每一个 Python 库，从 Reasonix 的 Agent 架构到 pdf2zh 的翻译引擎——我们站在巨人的肩膀上。

**谢谢你们。** 🙏

---

*最后更新：2026-08-17*
