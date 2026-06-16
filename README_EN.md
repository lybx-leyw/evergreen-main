# Evergreen Multi-Tools(Beta version, not promoted temporarily)

> An open-source practice of bringing Allport's trait theory into AI memory.  
> A self-built Agent runtime powering the ZJU campus toolkit.  
> A pioneer in AI Agent contribution governance.  
> **ZJU students — welcome to build together.**

Author: **绿意不息 (Evergreen)**

---

## Getting Started

```bash
cd evergreen-multi-tools
flutter pub get
flutter run -d windows
```

---

## Core Features

- **🧠 Allport's Trait Theory Memory** — A standalone `MemoryAgent` analyzes user traits after every conversation turn, structured in five layers: *Cardinal Traits / Central Traits / Secondary Traits / User Needs / Key Facts*. Fully transparent — users can view and edit at any time.

- **📋 Hot-Loading Skill System** — Drop a `.md` file into `.greenix/skills/` and the AI loads it instantly. Supports both inline and subagent execution modes.

- **🔍 Dual-Tier OCR** — DeepSeek-OCR cloud high-precision → Tesseract local automatic fallback. PDFs are auto-split into pages for per-page recognition.

- **🤖 Self-Built Agent Runtime** — A Dart reimplementation of Reasonix: `compose → LLM → tool → loop → readiness`, with 17 typed events.

- **📊 917 Automated Tests** (0 failures)

---

## Modules (15)

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
| WordPecker | FSRS spaced-repetition vocabulary |
| Downloads | Course material download manager |
| Plan | Multi-plan management, outline tasks, weekly timetable color-coding |
| Settings | Configuration & preferences |

> ⚠️ The following modules are temporarily disabled due to backend API unavailability: Library, Campus Card, PTA Q&A, Auto Check-in, RVPN, Smart Scheduling.

---

## OCR Dependencies

Dual-tier OCR: Cloud DeepSeek-OCR (DashScope API) → Local Tesseract automatic fallback.

### Local OCR (Required)

1. Download and install [Tesseract OCR](https://github.com/UB-Mannheim/tesseract/wiki). During installation, check the **"Chinese Simplified"** language pack.
2. `pip install -r scripts/requirements.txt`

### Cloud OCR (Optional)

Enter your DashScope API Key in Settings and enable the `vanchin/deepseek-ocr` model. Falls back to local Tesseract automatically when not configured.

---

## Build

```bash
# Windows (includes Python OCR scripts + local Tesseract)
flutter build windows --release

# Android (buildable but untested; OCR not supported)
flutter build apk --release
```

> ⚠️ The Android version is **untested**, and Python OCR scripts are not supported. OCR is desktop-only.

---

## Project Lineage

- **v1.1** (current) — Dart/Flutter desktop app, 15 modules, self-built Agent runtime, data status management
- Agent runtime inspired by [Reasonix](https://github.com/esengine/reasonix) (MIT), independently rewritten in Dart
- Grade calculation & academic affairs integration adapted from [Celechron](https://github.com/Celechron/Celechron) (GPL-3.0)
- Instructor rating data sourced from [Lazuli](https://github.com/ADSR1042/Lazuli) (GPL-3.0)
- WordPecker spaced-repetition engine adapted from [Qwerty Learner](https://github.com/RealKai42/qwerty-learner) (GPL-3.0)

Full attributions in **[ATTRIBUTION.md](./ATTRIBUTION.md)**.

---

## AI Agent Contribution Governance

This project maintains a dual-track contribution protocol:

- **[CONTRIBUTING.md](./CONTRIBUTING.md)** — Architecture, code style, and development standards for all contributors.
- **[AGENT_CONTRIBUTING.md](./AGENT_CONTRIBUTING.md)** — A dedicated governance document for AI Agents: 10-step delivery pipeline, self-check checklist, prohibited behaviors, and uncertainty-handling rules. AI-generated PRs that violate this guide will be rejected.

We believe defining how AI participates in open source is as important as building with AI itself.

---

## License

**GPL-3.0** — See [LICENSE](./LICENSE) for details.
