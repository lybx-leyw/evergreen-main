---
name: renderer-templates
role: Evergreen 下游 renderer/templates 子 OWNER
scope: evg-base/lib/renderer/templates/
parent: renderer
---

# AGENT.md — renderer-templates 职责书

> 本文件是「谁负责这里」的职责书。技术原理见 `../CLAUDE.md`。
> 最后更新：2026-08-25

## 1. 职责范围

- 管辖目录：`evg-base/lib/renderer/templates/`（模板 + 注册表）
- 一句话定位：模板（modle）渲染器集合 + `TemplateRegistry` 分派 + `templates_index.json`。

### 模板清单（含让渡标注）

| 模板 | 目录 | 归属 | 用途 |
|------|------|------|------|
| `v4_modle` | `v4_modle/` | **本 OWNER** | 通用组件式模板（最重） |
| `paper_reading_modle` | `paper_reading_modle/` | **本 OWNER** | 论文阅读 |
| `skill_creator_modle` | `skill_creator_modle/` | **本 OWNER** | Skill 创作中心 |
| `generated/` | `generated/` | **本 OWNER** | 生成代码 |
| `theme_creator_modle` | `theme_creator_modle/` | **已让渡 → plugin-theme-creator** | 主题创作中心 |
| `html_modle` | `html_modle/` | **已让渡 → plugin-html-creator** | HTML 插件（WebView + JS Bridge） |
| `scraper_modle` | `scraper_modle/` | **已让渡 → plugin-scraper** | 所见即所得爬虫 |
| `dsh_modle` | `dsh_modle/` | **已让渡 → plugin-dsh** | DeepSeek Harness |
| `zju_modle` | `zju_modle/` | **已让渡 → plugin-zju** | 浙大校园 |

> **让渡说明**：以上独立模板已移交独立 OWNER（见各 `*_modle/AGENT.md` 或 `plugins/<id>/AGENT.md`）。本 OWNER 仍负责「模板注册表」整体（`TemplateRegistry` + `templates_index.json`），但模板内部实现由独立 OWNER 自治。
>
> **v4_modle 内组件归属**：`v4_modle/components/` 下的 `marketplace/`、`interaction/chat/`、`translate/` 组件目录**仍归本 OWNER**（不从 v4_modle 剥离），但被独立 OWNER（`plugin-marketplace`/`plugin-ai-assistant`/`plugin-pdf-translate`）通过「对外契约」引用协作。

## 2. 边界与红线

- ✅ 可以：改本 OWNER 保留的模板（`v4_modle`、`paper_reading_modle`、`skill_creator_modle`、`generated/`）及模板注册表整体；新增模板。
- ❌ 禁止：写业务逻辑；直调 HTTP；改动 core/ 或其他 renderer 子 OWNER；改动已让渡的独立模板（`theme_creator_modle`/`html_modle`/`scraper_modle`/`dsh_modle`/`zju_modle`）内部实现（应派发给对应独立 OWNER）。
- ⚠️ 需协调：新增模板必须在 `templates_index.json` 登记 + 重新生成 `template_registry.g.dart`（否则 AOT tree-shaker 无法裁剪）；`template` 字段路由变更需与 `core-module` 对齐；`modle_route` 超参数语义：模板只按 `modle_route` 渲染子视图，不内置 Tab/多 page。独立 OWNER 改其模板的注册/路由时，须通知本 OWNER 同步注册表。

## 3. 对外契约（可被其他 OWNER 依赖的公开接口）

| 契约 | 形式 | 消费方 | 变更须知 |
|------|------|--------|---------|
| `ModleRenderer` 接口 | `template.dart` | core-module + app-shell | 接口变更需广播 |
| `TemplateRegistry` | `template_registry.dart` | app-shell | 模板增删需重新生成注册表 |
| `templates_index.json` | JSON | tool（gen_template_registry） | 登记字段变更需通知 platform |
| 各模板渲染器 | 各 `*_modle/` | core-module | 消费方 manifest 用 `template` 选择 |

## 4. 规则（本 OWNER 内必须遵守）

- 渲染层只画 UI，不写业务逻辑。
- 共享原子层（`renderer/atomic/`）只含取数原语；组件/布局策略全部模板私有（见 CLAUDE.md）。
- 新增模板：`templates_index.json` 登记 → `dart tool/gen_template_registry.dart` 重生成。
- 某模板若异于其他模板的渲染需求（独占全屏、内部复杂 LayoutBuilder），考虑独立模板而非在 slot 链路打补丁。

## 5. 验收标准

- 改完必须：相关 `flutter test` 通过；新增模板需重新生成注册表并全量回归。

## 6. 引用索引

- 心智模型：`../CLAUDE.md`
- 上层职责书：`../AGENT.md`
