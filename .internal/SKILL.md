---
name: ever-green-workflow
description: >
  Evergreen Multi-Tools 复杂仓库操作 Skill。强制执行 5 步完整交付流程，
  步骤 4 后强制等待人类反馈。
run_as: inline
---

# Evergreen Multi-Tools 工程流程 Skill

你是 Evergreen 项目的**常驻贡献者**。此 Skill 约束你必须按规定的 5 步流程完成代码交付。

---

## 🚨 角色与铁律

| 角色 | 职责 |
|------|------|
| **AI（你）** | 读文档/读代码 → 实现 → 测试 → 编译 → 归档 |
| **人类** | 步骤 2 确认需求、步骤 4 给出反馈 |

### 铁律

1. **步骤 4 后禁止自动进入步骤 5。** 必须等待人类反馈。
2. 同一方法连续失败 3 次 → **熔断**，告知用户、提出替代方案。
3. 需求模糊时**禁止直接动手改代码**——先问清楚再动。

---

## 前置：项目心智模型

```
上游 core/  ←──HTTP JSON──  中游 plugins/  ──Riverpod→  下游 renderer/
(纯Dart服务层)               (JSON声明+.exe)              (纯渲染层)
```

- **core/** 不画像素 · **plugins/** 不写 Dart UI · **renderer/** 不写业务逻辑
- **main.dart** 横跨三层组装：启动 6 个 HTTP Server → 扫描插件 → 注册 → 注入 Riverpod → runApp
- 详见 `.internal/CLAUDE.md`

---

## 5 步交付流程

### 步骤 1：理解上下文

1. 读 `.internal/EXPERIENCE.md` + 相关经验卡片（`.internal/experiences/`），避免重蹈覆辙
2. 读 `.internal/RULES.md`（工作规范）+ `.internal/CLAUDE.md`（架构心智模型）
3. 读与任务相关的核心源码，弄清现有架构、数据流、依赖关系
4. ✅ 确认理解后进入步骤 2

### 步骤 2：确认需求

🛑 **向人类确认三件事：**
- 可修改范围——哪些文件/目录可以改、哪些不能碰
- 目标交付物——最终要产出什么、什么形式
- 功能边界——API 行为、UI 样式、特殊约束

有任何不明确必须先问清楚。人类确认后才进入步骤 3。

### 步骤 3：实现与验证

**3a. 修改代码**——遵循红线：

| ❌ 禁止 | 理由 |
|--------|------|
| renderer/ 写业务逻辑或调 HTTP API | 渲染层只画 UI |
| core/ 引用 Flutter Widget | 上游纯 Dart |
| 绕过 ModuleDescriptor 硬编码路由 | 必须走注册中心 |
| .exe 进程管理出现在渲染层 | 进程归 core 管 |
| 修改其他子模块代码 | 隔离原则 |

**3b. 写测试**——必须为新增代码或新增实现编写对应测试：
- 测试应覆盖**成功路径 + 失败路径 + 边界条件**
- 测试必须**直接验证目标是否达成**——而不是仅仅验证"代码能跑"
- 测试文件放在 `evg-base/test/` 对应路径下

**3c. 自验证**——写完后跑三项检查：

```powershell
# ① 静态分析
cd evg-base && dart analyze lib/

# ② 测试（新增 + 全量，确保无回归）
cd evg-base && flutter test

# ③ 编译（Windows）
cd evg-base && flutter build windows --release
```

**三项必须全部通过，且测试结果必须证明目标已达成**，才能进入步骤 4。

如果 `windows/flutter/ephemeral/` 缺失，按 `.codebuddy/memory/MEMORY.md` 记录的修复命令恢复。

### 步骤 4：🛑 等待人类反馈

向人类汇报：
```
✅ 步骤 1-3 全部完成。
   - dart analyze: 通过
   - 新增测试: X 条，覆盖目标场景
   - flutter test: 全部通过，已自验证目标达成
   - flutter build windows: 通过
请人工验证后给出反馈：
   - 功能正常 → "通过" / "pass" / "没问题"
   - 有问题 → 描述具体问题
```

**在收到人类回复前，不得执行步骤 5。**

#### 收到反馈后：

- ✅ **pass**（`通过` `没问题` `ok` `LGTM`）→ 进入步骤 5
- ❌ **fail**（`不行` `bug` `错误` `改一下`）→ 立即写失败经验卡片（`.internal/experiences/`）→ 回步骤 3

### 步骤 5：归档

1. **写经验卡片**：`.internal/experiences/YYYY-MM-DD-<简述>.md`（做了什么 / 关键决策 / 踩坑 / 可复用模式）→ 更新 `.internal/EXPERIENCE.md` 索引
2. **写工作日志**：`.codebuddy/memory/YYYY-MM-DD.md` 追加摘要
3. **更新长期记忆**：如有新约定/架构决策 → 更新 `.codebuddy/memory/MEMORY.md`
4. **更新对应模块的CLAUDE.md**：如有新约定/架构决策 → 更新 对应模块目录下的`CLAUDE.md`

✅ 全部完成。

---

## 别猜

碰到不确定的参数名、API 字段、认证方式——停下来，加 `// TODO(AI): 需要人工确认 - <具体问题>`，然后问用户。

目标不是"尽快交付"，而是"不出已知的错"。
