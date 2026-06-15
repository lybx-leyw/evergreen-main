# Subplan Index (Topological Order)

> Arranged bottom-up by dependency. Lower numbers = more foundational.  
> Same tier items can be developed in parallel.  
> 🟢 已达到 · 🟡 勉强达到 · 🔴 未实现 · ⏸ 暂缓 · ⚪ 远期

---

## Tier 0: Zero Dependencies

| # | Document | Status | Dependencies | Blocks |
|---|---|---|---|---|
| 01 | [Error Handling](./01-error-handling.md) | 🟢 | none | blocks all Services |
| 02 | [Test Infrastructure](./02-test-infrastructure.md) | ⏸ | none | — |
| 03 | [App Config](./03-app-config.md) | 🟡 | none | — |
| 04 | [Data Models](./04-data-models.md) | 🟡 | none | — |
| 05 | [Shared Widgets](./05-shared-widgets.md) | 🟢 | none | — |
| 06 | [Memory System](./06-memory-system.md) | 🟡 | none | — |

## Tier 1: Depends on Tier 0

| # | Document | Status | Dependencies | Related Bugs |
|---|---|---|---|---|
| 07 | [Network Layer](./07-network-layer.md) | 🟡 | 03 | BUG-01 prereq |
| 08 | [Utility Classes](./08-utility-classes.md) | 🟡 | 04 | — |

## Tier 2: Depends on Tier 1

| # | Document | Status | Dependencies | Related Bugs |
|---|---|---|---|---|
| 09 | [Login Refactor](./09-login-refactor.md) | 🟡 | 03, 07 | BUG-10 |
| 10 | [ZDBK Service](./10-zdbk-service.md) | 🟡 | 07, 04 | — |

## Tier 3: Depends on Tier 2

| # | Document | Status | Dependencies |
|---|---|---|---|
| 11 | [Auto Login Chain](./11-auto-login-chain.md) | 🟢 | 09 |
| 12 | [Provider Migration](./12-provider-migration.md) | 🟡 | 01, 09, 10 |

## Tier 4: Core Features (depends on Tier 3)

| # | Document | Status | Dependencies |
|---|---|---|---|
| 13 | [Scores](./13-scores.md) | 🟡 | 10, 12 |
| 14 | [Courses](./14-courses.md) | 🟡 | 10, 12 |
| 15 | [Exams](./15-exams.md) | 🟡 | 10, 12 |
| 16 | [Todo](./16-todo.md) | 🟡 | 10, 12 |

## Tier 5: Extensions — Light Dependencies

| # | Document | Status | Dependencies | Related Bugs |
|---|---|---|---|---|
| 17 | [Word Pecker](./17-word-pecker.md) | ⏸ | 03 | BUG-13 |

## Tier 6: Extensions — Depends on Auth + ZDBK

| # | Document | Status | Dependencies | Related Bugs |
|---|---|---|---|---|
| 18 | [Classroom](./18-classroom.md) | 🟡 | 09, 10 | BUG-06 |
| 19 | [Tutor OCR](./19-tutor-ocr.md) | 🟡 | 09, 10 | BUG-02,05,07,08 |
| 20 | [Library + Teachers](./20-library-teachers.md) | 🟡 | 09, 10 | — |
| 21 | [Ecard + Autosign](./21-ecard-autosign.md) | ⏸ | 09 | BUG-01,11 |
| 22 | [Downloads + Quiz + RVPN + Schedule](./22-downloads-quiz-rvpn-schedule.md) | 🔴 | 09, 10 | BUG-05 |

## Tier 7: Depends on Memory / Provider Migration

| # | Document | Status | Dependencies | Related Bugs |
|---|---|---|---|---|
| 23 | [Agent Multi Session](./23-agent-multi-session.md) | 🔴 | 06, 12 | BUG-14,16 |

## Tier 8: Integration (depends on multiple upstream)

| # | Document | Status | Dependencies | Related Bugs |
|---|---|---|---|---|
| 24 | [Scheduler + Settings](./24-scheduler-settings.md) | 🟡 | 10, 03 | BUG-10 |

## Tier 9: UI/UX (depends on all features)

| # | Document | Status | Dependencies | Related Bugs |
|---|---|---|---|---|
| 25 | [Theme + Nav + UI](./25-theme-nav-ui.md) | 🟢 | 13~24 all | BUG-03,09,15 |
| 26 | [Engineering + Packaging](./26-engineering-packaging.md) | ⏸ | 25 | — |

## Tier 10: Quality Assurance

| # | Document | Status | Dependencies |
|---|---|---|---|
| 27 | [Test Coverage](./27-test-coverage.md) | ⏸ | 02, 13~24 |
| 28 | [Documentation + Release](./28-documentation-release.md) | ⏸ | all |

## Future

| # | Document | Status | Dependencies |
|---|---|---|---|
| 29 | [AI Tutoring + Mobile](./29-future-ai-tutoring.md) | ⚪ | 10, 25 |
| 30 | [Wellness Agent](./30-future-wellness-agent.md) | ⚪ | 23 |

---

## Summary

| Status | Count |
|---|---|
| 🟢 已达到 | 4 (01, 05, 11, 25) |
| 🟡 勉强达到 | 16 (03,04,06,07,08,09,10,12,13,14,15,16,18,19,20,24) |
| 🔴 未实现 | 2 (22, 23) |
| ⏸ 暂缓 | 6 (02, 17, 21, 26, 27, 28) |
| ⚪ 远期 | 2 (29, 30) |

*最后更新: 2026-06-12*
