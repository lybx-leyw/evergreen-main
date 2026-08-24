---
name: core-theme
role: Evergreen 上游 core/theme 子包 OWNER
scope: evg-base/lib/core/theme/
parent: core
---

# AGENT.md — core-theme 职责书

> 本文件是「谁负责这里」的职责书。技术原理见同目录 `CLAUDE.md`。
> 最后更新：2026-08-25

## 1. 职责范围

- 管辖目录：`evg-base/lib/core/theme/`
- 一句话定位：主题系统——扁平语义色板（8 色）+ `ThemeStore` + `ThemeLoader` + `ThemeHttpServer`。

## 2. 边界与红线

- ✅ 可以：改 `theme/` 内一切实现；新增内置主题、渲染规则。
- ❌ 禁止：引用 Flutter Widget；改动其他子包；恢复已废弃的「五层 token」体系（见 CLAUDE.md）。
- ⚠️ 需协调：`ThemeDescriptor`（扁平 8 色）字段变更会影响 renderer 主题消费；`render_rules.dart` 像素级常量变更需通知 renderer。

## 3. 对外契约（可被其他 OWNER 依赖的公开接口）

| 契约 | 形式 | 消费方 | 变更须知 |
|------|------|--------|---------|
| `ThemeDescriptor`（扁平 8 色） | `theme_descriptor.dart` | renderer | 色板结构变更需通知 renderer |
| `ThemeStore`（响应式） | `theme_store.dart` | renderer | 切换行为变更需广播 |
| `ThemeHttpServer`（HTTP） | HTTP（`.theme_port`） | plugins .exe | 端点变更需通知 plugins |
| `builtinThemes` | `builtin_themes.dart` | renderer | 内置主题增删需通知 renderer |

## 4. 规则（本 OWNER 内必须遵守）

- 纯 Dart，禁止 Flutter 依赖。
- 实现以「扁平 8 色模型」为准，勿沿用废弃的五层 token。

## 5. 验收标准

- 改完必须：`cd lib/core/theme && dart test` 通过；`ThemeDescriptor` 变更需全量 `flutter test` 无回归。

## 6. 引用索引

- 心智模型：`CLAUDE.md`
- 模块说明：`README.md`
- 上层职责书：`../AGENT.md`
