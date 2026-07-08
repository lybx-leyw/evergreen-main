---
task_type: process
tags: [workflow, skill, rules, context, discipline]
difficulty: low
outcome: success
date: 2026-07-08
files_touched:
  - .internal/EXPERIENCE.md
  - .codebuddy/FAIL.md
---

## 做了什么
在执行"复刻 28 个插件"任务时，未先读取 `.internal/EXPERIENCE.md`、`RULES.md`、`.codebuddy/FAIL.md` 就直接进入 ever-green-workflow SKILL 步骤 2（向用户提问）。用户纠正后，补齐了全部上下文文件并重新执行步骤 2。

## 关键决策
- 严格遵守 ever-green-workflow SKILL 的 5 步流程：步骤 1 必须先读 EXPERIENCE.md + experiences + RULES.md + CLAUDE.md + 相关源码，确认理解后才进步骤 2。
- 步骤 2 必须向人类确认三件事：可修改范围 / 目标交付物 / 功能边界。

## 踩过的坑
急于给出范围计划，跳过了"理解上下文"这一步，导致没有吸收既有教训（尤其 FAIL.md 中 Python 插件禁 HTML 的铁律），且步骤 2 的确认项不完整。

**根因**：把"用户给了明确指令"误当成"已充分理解上下文"，忽略了 RULES.md / SKILL 强制的预读步骤。

**原则**：任何任务动手 / 进步骤 2 前，先读 EXPERIENCE.md + RULES.md + FAIL.md；需求模糊或范围未确认前禁止改代码。

## 可复用的模式
- 启动任务的标准动作：①读 `.internal/EXPERIENCE.md` ②读 `.internal/RULES.md` ③读 `.codebuddy/FAIL.md` ④按需读 `.internal/experiences/` 卡片 ⑤读相关源码 → 再进步骤 2 确认三件事。
