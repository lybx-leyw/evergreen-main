# Evergreen Multi-Tools v1.4.0

> **v1.4.0**: RVPN enabled · Initial repo-wide refactoring · 100-agent AI fleet trial  
> **Next: v2.0.0** — after full refactoring + multi-agent federation stabilization

> An open-source practice of bringing Allport's trait theory into AI memory.  
> A ZJU campus toolkit with an integrated Agent runtime.  
> A practitioner in AI Agent contribution governance + multi-agent federation.  
> **ZJU students — welcome to build together.**

---

## Quick Start

```bash
# Flutter desktop app
flutter pub get && flutter run -d windows

# 100-agent AI fleet (for repo-wide refactoring)
cd agent_contributing\evergreen_agents\reasonix
go build -o bin/reasonix_gr.exe ./cmd/reasonix_gr
reasonix_gr ceo
```

---

## Core Features

- **🧠 Allport's Trait Theory Memory** — `MemoryAgent` analyzes user traits after every turn, five-layer structure, fully transparent and editable
- **📋 Hot-Loading Skill System** — Drop a `.md` into `.greenix/skills/` and the AI loads it instantly
- **🔍 Dual-Tier OCR** — DeepSeek-OCR cloud → Tesseract local automatic fallback
- **🤖 Self-Built Agent Runtime** — A Dart reimplementation of Reasonix with 17 typed events
- **🏰 Palace Cognitive Middleware** — Event capture · AI refinement · Lesson smelting · Cognitive echo
- **📊 1000+ Automated Tests** (1067 passed)
- **🖥️ RVPN** — Campus VPN via zju-connect SOCKS5 proxy (enabled in v1.4.0)
- **🤖 100-Agent AI Fleet** — reasonix_gr: persistent Keeper+Executor per module, zero-cost idle (exploratory, v2.0.0 target)

---

## Modules (18)

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
| Palace | Cognitive palace (event capture · AI refinement · tree view) |
| WordPecker | FSRS spaced-repetition vocabulary |
| Downloads | Course material download manager |
| Plan | Multi-plan management, outline tasks, weekly timetable color-coding |
| RVPN | ✅ Campus VPN (zju-connect SOCKS5 proxy) — **enabled in v1.4.0** |
| Settings | Configuration & preferences |

> ⚠️ Temporarily disabled: Library, Campus Card, PTA Q&A, Auto Check-in, Smart Scheduling.

---

## Two Work Modes for AI Agents

| Mode | Entry | Use Case | Workflow |
|------|------|----------|----------|
| **11-Step Skill** | Load `agent_contributing/skill/SKILL.md` | Single focused tasks, daily dev | State-machine 11-step |
| **Federation Fleet** | `reasonix_gr ceo` | Repo-wide refactoring, cross-module | CEO→Keeper→Executor (lightweight, exploratory) |

> Federation mode skips the full 11-step workflow — cross-module refactoring is complex enough without the overhead. v2.0.0 will stabilize this.

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
# Flutter desktop
flutter build windows --release

# Android (buildable, no functionality commitment)
flutter build apk --release

# 100-agent AI fleet
cd agent_contributing\evergreen_agents\reasonix
go build -o bin/reasonix_gr.exe ./cmd/reasonix_gr
```

> ⚠️ The Android version compiles and produces an APK, but **no functionality is guaranteed**. Advanced features such as OCR and AI assistant have not been adapted for mobile. Windows desktop is recommended for the full experience.

---

## Project Lineage

- **v1.4.0** (current) — RVPN enabled · Initial repo-wide refactoring · 100-agent AI fleet trial (reasonix_gr)
- Agent runtime inspired by [Reasonix](https://github.com/esengine/reasonix) (MIT), independently rewritten in Dart
- reasonix_gr is a deep fork of [DeepSeek-Reasonix](https://github.com/esengine/DeepSeek-Reasonix) (MIT) — multi-agent federation derivative
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
- **[AGENT_CONTRIBUTING.md](./AGENT_CONTRIBUTING.md)** — AI Agent governance. Two modes: 11-Step Skill (daily dev) + Federation Fleet (repo-wide refactoring). AI-generated PRs that violate this guide will be rejected.

We believe defining how AI participates in open source is as important as building with AI itself.

---

## License

**GPL-3.0** — See [LICENSE](./LICENSE) for details.
