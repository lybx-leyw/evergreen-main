---
name: ever-green-workflow
description: >
  Evergreen Multi-Tools 复杂仓库操作 Skill。强制执行 11 步完整交付流程，
  通过 agent_flow.py 状态机约束步骤顺序，步骤 9 后强制等待人类反馈。
  加载此 Skill 后，AI 必须先运行 `python agent_contributing/skill/agent_flow.py start --task="<描述>"`
  初始化任务状态，然后按步骤逐一执行。所有 Python 脚本由 AI 直接执行，
  人类仅在步骤 9 给出自然语言反馈。
run_as: inline
---

# Evergreen Multi-Tools 工程流程 Skill

你是 Evergreen Multi-Tools 项目的**常驻贡献者**，此 Skill 约束你必须按规定的 11 步流程完成代码交付。

---

## 🚨 角色分工

| 角色 | 职责 |
|------|------|
| **AI（你）** | 执行所有 Python 脚本、读写代码、运行测试、更新文档 |
| **人类** | 仅在步骤 3 确认需求、步骤 9 给出反馈（自然语言） |

**所有 `agent_flow.py` 和 `check_feature.py` 命令由你（AI）通过 execute_command 执行，不要让人类去跑。**

---

## 🚨 终极铁律

1. **加载此 Skill 后，立即运行 `python agent_contributing/skill/agent_flow.py status`** 检查是否有进行中的任务。
2. 如果有任务且步骤 ≥ 9 并等待反馈 → 等待人类反馈。
3. 如果无任务或人类给了新任务 → 运行 `start` 初始化。
4. **每完成一个步骤，立即运行 `python agent_contributing/skill/agent_flow.py check` 推进状态。**
5. **步骤 9 后禁止自动进入步骤 10。** 向人类汇报，等待自然语言反馈。
6. 收到人类反馈后，**AI 判断 pass/fail**，自行运行 `feedback --result=pass/fail`。

---

## 启动流程

收到任务后，第一件事不是写代码，而是：

```
# 第一步：检查是否有进行中的任务
> execute_command: python agent_contributing/skill/agent_flow.py status

# 第二步：如果无任务或开始新任务
> execute_command: python agent_contributing/skill/agent_flow.py start --task="<一句话描述>"
```

---

## 11 步完整流程

### 步骤 0：阅读经验库
- 阅读 `agent_contributing/EXPERIENCE.md` 索引
- 根据任务 tags 找到相关经验卡片并阅读
- 完成后：```bash python agent_contributing/skill/agent_flow.py check```

### 步骤 1：阅读规则文档
- 通读 `AGENT_CONTRIBUTING.md`（完整）
- 通读 `CONTRIBUTING.md`
- 理解所有禁止清单和网络/状态/错误处理规则
- 完成后：```bash python agent_contributing/skill/agent_flow.py check```

### 步骤 2：阅读核心代码
- 找到与任务相关的 Service、Provider、UI 文件
- 弄清现有架构、数据流、依赖关系
- 完成后：```bash python agent_contributing/skill/agent_flow.py check```

### 步骤 3：确认需求边界
- 🛑 **向人类提问**，确认功能边界、API 行为、UI 样式
- 有任何不明确的地方必须先问清楚
- 人类确认后才算完成此步骤
- 完成后：```bash python agent_contributing/skill/agent_flow.py check```

### 步骤 4：修改代码
- 遵循 AGENT_CONTRIBUTING.md 第 1-12 条规则
- 写完代码后**立即**运行合规检查（AI 自己跑，不通过就修改）：
  ```bash
  python agent_contributing/skill/check_feature.py lib/features/<your_feature>/
  ```
- ❌ 有错误 → 继续修改，不得跳过
- ✅ 通过 → ```bash python agent_contributing/skill/agent_flow.py check```

### 步骤 5：写测试
- 为新增代码写单元测试 / Widget 测试
- 测试使用 `MockDioAdapter`，覆盖成功/失败/边界路径
- 完成后：```bash python agent_contributing/skill/agent_flow.py check```

### 步骤 6：运行新增测试
- ```bash flutter test test/features/<your_feature>/```
- 验证通过
- 完成后：```bash python agent_contributing/skill/agent_flow.py check```

### 步骤 7：运行全量测试
- ```bash python scripts/run_tests_parallel.py```
- 确保未引入回归错误
- 完成后：```bash python agent_contributing/skill/agent_flow.py check```

### 步骤 8：更新状态文档
- 按改动类型更新对应文档（见 AGENT_CONTRIBUTING.md §13 步骤 8 表格）
- 完成后：```bash python agent_contributing/skill/agent_flow.py check```

### 步骤 9：编译验证 + 🛑 等待人类反馈

1. 编译：```bash flutter build apk --release```（或对应平台）
2. 安装并人工验证功能正常
3. **立即运行 check 标记完成：**
   ```bash
   python agent_contributing/skill/agent_flow.py check
   ```
   输出会显示 "⛔ 此步骤后需要人类反馈"。
4. **🛑 停止一切操作。** 向人类汇报当前进度，请求反馈。
   汇报内容示例：
   ```
   ✅ 步骤 1-9 全部完成。编译通过，代码合规。
   请人工验证后给出反馈：
   - 功能正常 → "通过" / "没问题" / "pass"
   - 有问题 → 描述具体问题
   ```
5. **等待人类回复——在收到回复前，不得执行步骤 10。**

---

### 🔀 收到人类反馈后的处理（AI 自行判断并执行）

**AI 必须解析人类自然语言回复，判断是 pass 还是 fail。**

#### ✅ 正面反馈（pass）
关键词：`可以` `没问题` `通过` `不错` `good` `ok` `pass` `LGTM`

→ AI 立即执行：
```bash
python agent_contributing/skill/agent_flow.py feedback --result=pass
```
→ 然后继续步骤 10。

#### ❌ 负面反馈（fail）
关键词：`不行` `有问题` `bug` `错误` `改一下` `不对` `fail` `no`

→ AI 立即执行：
```bash
python agent_contributing/skill/agent_flow.py feedback --result=fail --note="<人类反馈原文>"
```
→ 然后执行"反馈失败的特殊流程"（见下文），再回到步骤 4。

---

### 步骤 10：写经验卡片

在 `agent_contributing/experiences/` 下创建 `YYYY-MM-DD-<简短描述>.md`：
- 成功按成功模板
- 更新 `agent_contributing/EXPERIENCE.md` 索引
- 完成后：```bash python agent_contributing/skill/agent_flow.py check```

### 步骤 11：写 PR_history

在 `PR_history/` 下创建 `YYYY-MM-DD-<修改简述>.md`：
- **禁止声称已执行人工验证，截图标注"待人工补充"**
- 完成后：```bash python agent_contributing/skill/agent_flow.py check``` → 状态机标记 `done`

---

## 反馈失败的特殊流程

当 `feedback --result=fail` 执行后，AI 必须：

1. **立即写失败经验卡片**（不等到步骤 10）
2. 更新 `EXPERIENCE.md` 索引
3. 带着教训回到步骤 4（修改代码）

**失败后完整路径**：写失败经验 → 步骤 4 → 5 → 6 → 7 → 8 → 9 → 等待反馈

---

## 命令清单（全部由 AI 执行）

| 命令 | 场景 |
|------|------|
| `agent_flow.py status` | 加载 Skill 后立即运行、随时查看进度 |
| `agent_flow.py start --task="..."` | 开始新任务 |
| `agent_flow.py check` | 每完成一个步骤后立即运行 |
| `agent_flow.py feedback --result=pass` | 人类 pass 后，AI 自行执行 |
| `agent_flow.py feedback --result=fail --note="..."` | 人类 fail 后，AI 自行执行 |
| `agent_flow.py reset --step=N` | 人类明确说"回退到步骤 N" |
| `check_feature.py <path>` | 步骤 4 写代码后必须运行 |

---

## 别猜

碰到不确定的参数名、API 字段、认证方式——停下来，在代码里加 `// TODO(AI): 需要人工确认 - <具体问题>`，然后向用户提问。

你的目标不是"尽快交付"，而是"不出已知的错"。
