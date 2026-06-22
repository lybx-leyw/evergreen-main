# Evergreen Multi-Tools (Beta version, not promoted temporarily)

> An open-source practice of bringing Allport's trait theory into AI memory.  
> A self-built Agent runtime powering the ZJU campus toolkit.  
> A pioneer in AI Agent contribution governance.  
> **ZJU students — welcome to build together.**

If you find this project useful, a ⭐ Star would be much appreciated!

---

## Quick Start

```bash
cd evergreen-multi-tools
flutter pub get
flutter run -d windows
```

---

## Core Features

- **🧠 Allport's Trait Theory Memory** — `MemoryAgent` analyzes user traits after every turn, five-layer structure, fully transparent and editable
- **📋 Hot-Loading Skill System** — Drop a `.md` into `.greenix/skills/` and the AI loads it instantly
- **🔍 Dual-Tier OCR** — DeepSeek-OCR cloud → Tesseract local automatic fallback
- **🤖 Self-Built Agent Runtime** — A Dart reimplementation of Reasonix with 17 typed events
- **📊 1000+ Automated Tests** (1006 passed)

---

## Modules (16)

| Module | Description |
|---|---|
| Auth | ZJU SSO unified authentication |
| Courses | Course list |
| Scores | Grades + 4 GPA formats |
| Exams | Exam countdown |
| Todo | Tasks + DingTalk push |
| ZDBK | Academic affairs notifications, course offerings |
| Classroom | ZJU Classroom videos + slides |
| Teachers | Instructor ratings |
| Schedule | iCal timetable export |
| Tutor | AI notes + DeepSeek + OCR |
| Agent | AI teaching assistant (chat + tools) |
| Translate | PDF translation (DeepSeek + pdf2zh engine) |
| WordPecker | FSRS spaced-repetition vocabulary |
| Downloads | Course material download manager |
| Plan | Multi-plan management, outline tasks, weekly timetable color-coding |
| Settings | Configuration & preferences |

> ⚠️ The following modules are temporarily disabled due to backend API unavailability: Library, Campus Card, PTA Q&A, Auto Check-in, RVPN, Smart Scheduling.

---

## Installation & Dependencies

### Windows (Recommended)

The Windows installer includes a **bundled Python 3.10 runtime** — no manual dependency installation required. See [BUILD.md](./BUILD.md).

### Local OCR

Dual-tier OCR: Cloud DeepSeek-OCR (DashScope API) → Local Tesseract automatic fallback.

1. Download and install [Tesseract OCR](https://github.com/UB-Mannheim/tesseract/wiki). During installation, check the **"Chinese Simplified"** language pack.
2. `pip install -r scripts/requirements.txt`

### Cloud OCR (Optional)

Enter your DashScope API Key in Settings and enable the `vanchin/deepseek-ocr` model. Falls back to local Tesseract automatically when not configured.

### PDF Translation

PDF translation runs the pdf2zh engine (bundled at `scripts/pdf2zh_next/`) via a Python subprocess, outputting bilingual comparison PDFs with preserved layout, formulas, and figures.

Features:
- **Zero-config**: bundled Python with automatic detection fallback (bundled → configured → system PATH)
- **Stage pipeline**: 9-stage visual progress indicator with Chinese labels
- **In-app reader**: full-screen PDF reader with page navigation (pdfrx)
- **Batch translation**: multi-file queue with per-file progress and immediate results

---

## Build

```bash
# Windows (includes Python OCR scripts + local Tesseract)
flutter build windows --release

# Android (buildable, no functionality commitment)
flutter build apk --release
```

> ⚠️ The Android version compiles and produces an APK, but **no functionality is guaranteed**. Advanced features such as OCR and AI assistant have not been adapted for mobile. Windows desktop is recommended for the full experience.

---

## Project Lineage

- **v1.2** (current) — Dart/Flutter desktop app, 16 modules, self-built Agent runtime, data status management, PDF translation
- Agent runtime inspired by [Reasonix](https://github.com/esengine/reasonix) (MIT), independently rewritten in Dart
- Grade calculation & academic affairs integration adapted from [Celechron](https://github.com/Celechron/Celechron) (GPL-3.0)
- Instructor rating data sourced from [Lazuli](https://github.com/ADSR1042/Lazuli) (GPL-3.0)
- WordPecker spaced-repetition engine adapted from [Qwerty Learner](https://github.com/RealKai42/qwerty-learner) (GPL-3.0)
- PDF translation engine embedded from [PDFMathTranslate-next](https://github.com/PDFMathTranslate-next/PDFMathTranslate-next) (AGPL-3.0)
- Agent contribution governance inspired by [MemGovern](https://github.com/esengine/memgovern) (MIT)

Full attributions in **[ATTRIBUTION.md](./ATTRIBUTION.md)**.

---

## Contributing

All contributions are welcome:

- 🐛 **[Report Bugs](https://github.com/lybx-leyw/evergreen-main/issues)** / 💡 **[Submit Ideas](https://github.com/lybx-leyw/evergreen-main/issues)**
- 📋 **[Share Your Skill](https://github.com/lybx-leyw/evergreen-main/issues)** — drop a `.md` into `.greenix/skills/` and the AI loads it instantly
- 🔧 **[Open a PR](https://github.com/lybx-leyw/evergreen-main/pulls)** — follow [CONTRIBUTING.md](./CONTRIBUTING.md)

See **[CONTRIBUTING.md](./CONTRIBUTING.md)** for details.

---

## AI Agent Contribution Governance

This project maintains a dual-track contribution protocol:

- **[CONTRIBUTING.md](./CONTRIBUTING.md)** — Architecture, code style, and development standards.
- **[AGENT_CONTRIBUTING.md](./AGENT_CONTRIBUTING.md)** — AI Agent governance. Entry point: [`agent_contributing/SKILL.md`](./agent_contributing/SKILL.md). AI-generated PRs that violate this guide will be rejected.

We believe defining how AI participates in open source is as important as building with AI itself.

---

## License

**GPL-3.0** — See [LICENSE](./LICENSE) for details.
