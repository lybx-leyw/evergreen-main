# AI Agent 贡献指南

> 当你（AI Agent）被要求为此项目生成代码、修改文件或创建 Pull Request 时，请严格遵循以下规则。  
> 任何违反本指南的 PR 都会被要求修改或直接拒绝。

**🚨 入口：先加载 `agent_contributing/SKILL.md`。** 该 Skill 定义了完整的强制流程（阅读规则 → 查经验库 → 按工程流程执行 → 写经验卡片）。

**本文件与 `CONTRIBUTING.md` 的关系**：  
- `CONTRIBUTING.md` 定义了项目的基础架构、代码风格和通用开发规范，所有贡献者（包括人类与 AI）必须遵守。  
- 本文件仅补充 AI Agent 特有的行为约束和交付流程。**当两者冲突时，以本文件为准**，但 Agent 仍需尽量同时满足两者。  
- Agent 应在阅读完 `CONTRIBUTING.md` 后再阅读本文件。

**本文件与 `agent_contributing/EXPERIENCE.md` 的关系**：  
- 本文件是**规则**（必须遵守的约束），经验库是**案例**（具体任务中的踩坑记录和可复用模式）。  
- Agent 在开始任务前必须阅读经验库中与当前任务相关的卡片，任务完成后必须写入新的经验卡片（成功 ✅ 和失败 ❌ 都必须写）。  
- 详见 [§13 工程流程](#13-工程流程完整交付步骤)。

---

## 0. 核心原则

- **只改该改的**：不要无谓地重构已有稳定代码，不要添加未经要求的“增强功能”。
- **不要破坏现有协议**：项目已有基础设施（网络、认证、状态管理）必须遵守。
- **优先复用，禁止重复造轮子**：已经存在的工具类、拦截器、Provider 必须直接使用。
- **所有输出必须基于项目当前代码结构**：如果不确定，请要求用户提供相关文件或解释，不要猜测。

---

## 1. 网络请求（最高优先级）

### 1.1 必须使用项目已有的 HTTP 客户端

```dart
// ✅ 正确
final dio = ref.read(dioClientProvider);
await dio.get('/api/xxx');

// ❌ 禁止：直接创建新的 Dio 实例
final dio = Dio();
// ❌ 禁止：使用 http 包
import 'package:http/http.dart' as http;
```

### 1.2 Cookie 管理必须通过 `CookieManager`

```dart
// ✅ 正确
final cookieJar = ref.read(cookieJarProvider);
// 添加 Cookie 由 CookieManager 负责，Agent 不应手动操作

// ❌ 禁止：手动拼接 "Cookie: xxx" 头
```

### 1.3 日志必须使用 `Log()` 类

```dart
import 'package:evergreen_multi_tools/core/log/log.dart';

// ✅ 正确
Log().info('用户登录成功');
Log().error('网络超时', error: e);

// ❌ 禁止
print('debug');
debugPrint('something');
```

### 1.4 超时、重试、白名单等网络配置必须引用 `NetworkConfig`

```dart
import 'package:evergreen_multi_tools/core/network/network_config.dart';

// ✅ 正确
const timeout = NetworkConfig.connectTimeout;
```

---

## 2. 认证与登录

### 2.1 认证方式表格（禁止混用）

| 平台 | 认证方式 | 说明 |
|------|---------|------|
| ZJU SSO | `Cookie: iPlanetDirectoryPro` | ZDBK / Courses / Classroom |
| BlueWare | `synjones-auth: bearer` | 功能暂停 |
| PTA | `Cookie: PTASession` | 需手动粘贴 |
| DeepSeek | `Authorization: Bearer` | API Key |

- **绝不允许**用 SSO Cookie 去调用 BlueWare API，反之亦然。

### 2.2 新增服务必须接入 `ConnectionManager`

```dart
// ❌ 禁止：在 app.dart 或其他地方直接调用 Service.login()
await myNewService.login();

// ✅ 正确：在 ConnectionManager 中添加 checkMyNewService()
// 并在 _triggerAutoLogin 中统一调用 manager.checkAll()
```

### 2.3 登录失败处理

- 每个服务的登录失败**不能阻断**其他服务的登录。
- 必须返回 `ServiceResult.failure`，而不是抛出异常。

---

## 3. 状态管理（Riverpod）

### 3.1 依赖登录状态的 Provider 必须使用 `ref.watch`

```dart
// ✅ 正确：会自动响应登录态变化
final auth = ref.watch(authProvider);

// ❌ 错误：仅在读取瞬间获取一次，登录后不会刷新
final auth = ref.read(authProvider);
```

### 3.2 异步结果统一用 `Result<T>`

```dart
import 'package:evergreen_multi_tools/core/result/result.dart';

Future<Result<List<Course>>> fetchCourses() async {
  try {
    final data = await dio.get(...);
    return Ok(data);
  } on DioException catch (e) {
    return Err(AppError.fromDio(e));
  }
}
```

- Service 层**不允许抛异常**，必须返回 `Result<T>`。

---

## 4. 错误处理

### 4.1 所有 `AppError` 必须包含

- `userMessage`：用户可读的错误信息
- `recoveryHint`：如何恢复（如“请检查网络后重试”）

```dart
AppError(
  userMessage: '加载课表失败',
  recoveryHint: '请确认已登录 ZJU SSO 并重试',
  cause: dioException,
);
```

### 4.2 不允许透传 `DioException` 原文给 UI

```dart
// ❌ 错误
showDialog(context, content: e.message);

// ✅ 正确
showDialog(context, content: error.userMessage);
```

---

## 5. 代码风格（Dart & Flutter）

### 5.1 import 顺序

1. Dart SDK（`dart:async`）
2. Flutter（`package:flutter/`）
3. 第三方（`package:dio/`、`package:flutter_riverpod/`）
4. 项目内部（从 `package:evergreen_multi_tools/core/` 到 `features/`）

### 5.2 敏感信息脱敏

```dart
@override
String toString() {
  return 'User(token=${AppConfigData.mask(token)})';
}
```

### 5.3 Widget 编写

- 使用 `ConsumerWidget` / `ConsumerStatefulWidget`，不用 `StatelessWidget` + `Provider.of`
- `build()` 方法内**禁止**网络请求、异步操作
- 复用 `lib/widgets/` 下的通用组件（如 `_previewCard`、`_wipCard`）

### 5.4 配置管理：新增字段必须五处同步

新增 AppConfig 字段（API Key、路径、开关等）必须在以下**五个位置**同步添加，缺一不可：

1. `_loadFromEnv()` — 系统环境变量读取
2. `_loadFromEnvFile()` — `.env` 文件读取
3. `_loadFromPrefs()` — SharedPreferences 读取
4. `set()` 方法 — 运行时写入
5. `saveToEnvFile()` + `SettingsService._keys` — 持久化回写

敏感字段必须加 `@Secure()` 标记，`toString()` 自动脱敏。

```dart
// ✅ 正确
@Secure()
late String deepseekApiKey;

// ❌ 禁止：只改一处，遗漏其他四个位置
```

---

## 6. Agent 运行时开发规范

> `core/agent/` 是自研 LLM Agent 框架（Reasonix 的 Dart 复刻）。
> 📖 实战经验：`agent_contributing/experiences/2026-06-18-global-memory-dedup.md`、`agent_contributing/experiences/2026-06-16-cache-first-architecture.md`

### 6.1 新增 Agent 工具

- 工具命名**必须** `snake_case`
- 只读工具（`readOnly => true`）可**并行**，写工具（`readOnly => false`）**串行**
- **必须**通过 `ZjuDataSource` 接口获取业务数据，**禁止**直接依赖 Riverpod

```dart
// ✅ 正确：实现 Tool 接口 → 通过 ZjuDataSource 解耦
class GetMyDataTool extends Tool {
  final ZjuDataSource dataSource;
  @override String get name => 'get_my_data';
  @override bool get readOnly => true;
  // ...
}
// 在库初始化时注册到 BuiltinRegistry

// ❌ 禁止：工具中直接 ref.read(coursesProvider)
```

### 6.2 ZjuDataSource 扩展

新增方法 → **所有** `implements ZjuDataSource` 的类同步更新。Agent 工具不直接访问 Provider。

### 6.3 新增 Skill

- 放在 `.greenix/skills/`（**不是** `reasonix/skills/`）
- YAML frontmatter 必填 `name` + `description`，可选 `run_as`（`inline` / `subagent`）
- 优先级覆盖：`custom > project > global > builtin`

---

## 7. Python 子进程 & 外部依赖

> OCR 和 PDF 翻译通过 Python 子进程执行。**严禁**绕过封装类直接操作子进程。
> 📖 实战经验：`agent_contributing/experiences/2026-06-19-pdf-translate-python-subprocess.md`

### 7.1 子进程通过封装类调用

```dart
// ✅ 正确：OCR → runOcrProcess()
// ✅ 正确：PDF 翻译 → PdfTranslateService
// ❌ 禁止：直接 Process.start / Process.run
```

### 7.2 三条铁律

1. **JSON 事件流** — stdout 逐行 JSON，不解析原始文本
2. **`includeParentEnvironment: true`** — 必须设置（传递 HF_TOKEN）
3. **Python 路径从 `AppConfig.pythonExe` 读取** — 禁止硬编码 `'python'`

### 7.3 新增 Python 依赖时

必须同步更新：`requirements.txt`、`PythonEnv.checkDeps()`、`BUILD.md`

---

## 8. 记忆系统规范

> `.greenix/memories/` 是跨会话持久化的全局记忆，按奥尔波特特质理论组织。
> 📖 实战经验：`agent_contributing/experiences/2026-06-18-global-memory-dedup.md`

### 8.1 文件格式

```yaml
---
name: <kebab-slug>
description: <一行摘要>
type: user | feedback | project | reference
priority: cardinal | central | secondary | requirement | high | medium | low
---
正文内容
```

### 8.2 五层优先级

`cardinal`(首要) > `central`(中心) > `secondary`(次要) > `requirement`(需求) > `high`/`medium`/`low`(事实)

### 8.3 禁止

- ❌ 手动删除 `.greenix/memories/` 下的文件或 `MEMORY.md` 索引
- ❌ 绕过 `MemoryAgent` / `write_global_memory` 工具直接写 `FileMemoryStore`
- ❌ 把 `reasonix/memories/` 当作用户记忆目录（路径已统一为 `.greenix/memories/`）

---

## 9. 第三方代码引入规范

当引入上游开源项目的源码时（如 pdf2zh、Reasonix 移植），必须：

1. **ATTRIBUTION.md** — 记录来源、作者、仓库、许可证、引用范围
2. **精简到必要部分** — 删除 GUI/CLI/assets 等不必要文件
3. **确认许可证兼容** — GPL-3.0 项目引入 AGPL-3.0 代码需审慎评估
4. **标注改动** — 修改过的文件在文件头注释说明修改内容
5. **PR_history** — 说明引入原因和修改范围
6. **上游更新时** — 对比 diff 后选择性合并，不要全量覆盖

---

## 10. 功能开发 / 修改

> 📖 实战经验：`agent_contributing/experiences/2026-06-16-cache-first-architecture.md`

### 10.1 后端 API 不可用时

- 标记为 `(开发中)`
- UI 使用 `_wipCard` 替代 `_previewCard`
- 侧边栏标签加 `(开发中)`
- **不要删除** Service/Provider 代码，加注释说明阻塞原因
- 在 `docs/dev/` 下写说明文档

### 10.2 添加新功能时

- 必须编写对应的测试文件（`test/features/.../xxx_test.dart`）
- 测试必须使用 `MockDioAdapter` 和独立的 `PersistCookieJar`
- 覆盖成功、空数据、401/404、网络异常等路径

---

## 11. 禁止清单（Agent 特别注意）

- ❌ 手动拼接 `Cookie` 头
- ❌ 在 `build()` 中发起网络请求
- ❌ 不同认证方式混用
- ❌ 使用 `print()` / `debugPrint()`
- ❌ 删除暂时不可用功能的代码（改为”开发中”标记）
- ❌ 在 Provider 中使用 `ref.read(authProvider)` 代替 `ref.watch`
- ❌ 跳过 `ConnectionManager` 直接调用 Service 登录
- ❌ Service 抛出异常（必须返回 `Result`）
- ❌ 重复造轮子（已存在的工具类、Provider 必须复用）
- ❌ 绕过 `PythonEnv` / `PdfTranslateService` 直接 `Process.run` / `Process.start`
- ❌ 在 Agent 工具中直接依赖 Riverpod Provider（必须通过 `ZjuDataSource`）
- ❌ 删除 `.greenix/memories/` 下的记忆文件或 `MEMORY.md` 索引
- ❌ 硬编码 `'python'` 路径（应从 `AppConfig.pythonExe` 读取）
- ❌ 子进程遗漏 `includeParentEnvironment: true`
- ❌ 新增 AppConfig 字段未五处同步
- ❌ 引入第三方源码不更新 `ATTRIBUTION.md`

---

## 12. PR 自检清单（Agent 提交前必须检查）

- [ ] 所有网络请求通过 `dioClientProvider`
- [ ] 没有手动操作 Cookie
- [ ] 日志使用 `Log()`，没有 `print`
- [ ] 新增/修改的 Service 返回 `Result<T>`
- [ ] 错误处理提供了 `userMessage` 和 `recoveryHint`
- [ ] 依赖登录态的 Provider 用了 `ref.watch`
- [ ] 没有破坏现有路由/侧边栏/登录流程
- [ ] 测试已更新，且全部通过
- [ ] 没有删除标记为”开发中”或”暂停”的代码
- [ ] Python 子进程通过封装类调用，`includeParentEnvironment: true`
- [ ] 新增 Agent 工具已注册到 `BuiltinRegistry`
- [ ] 新增 AppConfig 字段已五处同步
- [ ] Android 平台已做兼容处理
- [ ] 第三方代码已记录到 `ATTRIBUTION.md`
- [ ] 相关 md 文档已同步更新
- [ ] **已写经验卡片**到 `agent_contributing/experiences/`（含踩坑和可复用模式）
- [ ] **已更新经验索引** `agent_contributing/EXPERIENCE.md`

---

## 13. 工程流程（完整交付步骤）

> 当你（AI Agent）完成代码修改后，必须按照以下步骤完成交付，**缺一不可**。

0. **【新增】阅读经验库**  
   阅读 `agent_contributing/EXPERIENCE.md` 索引，根据当前任务的 tags / files 找到并阅读相关经验卡片。这一步帮你避免重复已知的坑。

1. **阅读所有中文知道的文档（完整）和所有代码的开头**  
   理解项目的设计哲学、架构约束、已有实现方式，不要凭经验猜测。

2. **详细阅读核心代码文件，和与你目标相关的代码文件**  
   找到你需要修改或扩展的模块（如 Service、Provider、UI），先通读再动手。

3. **询问清楚用户需求**  
   如果有任何不明确的地方（功能边界、UI 样式、API 行为），必须先向用户确认，不要自行假设。

4. **根据需求修改代码**  
   遵循本指南第 1–12 条的所有规则进行修改。

5. **写测试，尽量覆盖所有新增代码**  
   每个新增函数、分支逻辑、错误路径都要有对应的单元测试或 Widget 测试。

6. **运行新增测试，确保新增代码无错误**  
   使用 `flutter test <新增测试文件>` 单独验证通过。

7. **运行全量测试，确保未引入新错误**  
   优先使用并行脚本加速：`python scripts/run_tests_parallel.py`（将 6 组测试并行运行，对齐 CI）。  
   也可单独验证某组：`python scripts/run_tests_parallel.py --group core`。  
   若脚本不可用，回退到串行 `flutter test`。

8. **修改对应的状态文档**  
   按改动类型对照下表更新，保持文档与代码同步：

   | 改动类型 | 必须更新的文档 |
   |---------|-------------|
   | 新增 Feature / 模块 | `ARCHITECTURE.md` + `MODULE_MAP.md` + `DATA_FLOW.md` + `README.md` |
   | 新增/修改 API 或数据流 | `DATA_FLOW.md` |
   | 新增第三方代码 | `ATTRIBUTION.md` |
   | 修改配置项 | `BUILD.md`（如涉及环境变量） |
   | 新增暂停功能 | `docs/dev/WIP_2026-06.md` |
   | 完成子计划 | `docs/ALL_PLANS.md` |
   | 重大架构变更 | `MODIFICATION_GUIDE.md` |

9. **编译并 release 新的版本，并亲自测试新版本是否能正常运行**  
   - 编译：`flutter build apk --release`（或对应平台的构建命令）  
   - 安装到真机或模拟器  
   - 人工验证新功能正常工作，且未破坏已有核心流程（登录、网络请求、页面跳转）

10. **【新增】写入经验卡片（验证后立即写，成功和失败都必须记录）**  
    在 `agent_contributing/experiences/` 下创建 `YYYY-MM-DD-<简短描述>.md`。

    **成功**按此模板：
    ```markdown
    ---
    task_type: bug-fix | feature | refactor
    tags: [关键词1, 关键词2, ...]
    files_touched: [改动的关键文件]
    difficulty: easy | medium | hard
    outcome: success
    date: YYYY-MM-DD
    related_pr: xxx.md
    ---

    ## 做了什么
    ## 关键决策
    ## 踩过的坑
    ## 可复用的模式
    ## 注意事项
    ```

    **失败或被废弃的方案**按此模板（同等重要）：
    ```markdown
    ---
    task_type: experiment | refactor | feature
    tags: [关键词1, 关键词2, ...]
    difficulty: easy | medium | hard
    outcome: failure | abandoned | reverted
    date: YYYY-MM-DD
    superseded_by: 替代方案的 PR 文件名（可选）
    ---

    ## 尝试了什么
    ## 为什么失败 / 为什么废弃
    ## 发现的问题（具体的错误信息、性能数据等）
    ## 学到什么（以后不要再走这条路）
    ## 最终采用了什么替代方案
    ```
    然后更新 `agent_contributing/EXPERIENCE.md` 索引（失败卡片用 `❌` 标记）。

    🚨 **分支点**：
    - **✅ 成功** → 继续步骤 11（写 PR_history）
    - **❌ 失败** → 回到步骤 4（修改代码），带着经验卡片中记录的教训重新来

11. **将本次修改涉及的所有内容写入根目录 `PR_history`**（仅成功时执行）  
    - 命名格式：`YYYY-MM-DD-<修改简述>.md`（示例：`2026-06-14-添加计划管理栏目.md`）  
    - 必须包含以下内容：
      - 修改目的
      - 修改的文件清单
      - 核心逻辑说明
      - 潜在影响
      - **测试结果摘要**（Agent 可输出测试命令及预期结果，由人工执行后补充截图）
      - **人工验证清单**（供人类贡献者勾选，Agent 不得自动打勾）
    - 模板如下（Agent 应生成此结构，其中截图部分留空或注明”待人工补充”）：
      ```markdown
      # PR_history/YYYY-MM-DD-<修改简述>.md

      ## 修改目的
      ...

      ## 修改文件清单
      - path/to/file1.dart
      - path/to/file2.dart

      ## 核心逻辑说明
      ...

      ## 潜在影响
      ...

      ## 测试结果摘要
      - 新增测试：`flutter test test/xxx_test.dart` ✅ 通过（预期）
      - 全量测试：`flutter test` ✅ 通过（预期）
      - 截图：待人工补充

      ## 人工验证清单（由人类执行）
      - [ ] 编译成功
      - [ ] 新功能在真机上表现符合预期
      - [ ] 已有核心流程（登录、课表、AI 对话）未受影响
      - [ ] 补充测试截图至本文件
      ```

    - **Agent 禁止**声称已执行人工验证或已获得截图，必须明确标注”待人工补充”。

---

## 14. 不确定情况的处理

> 当 Agent 无法确定某个技术细节、API 行为、认证方式或架构约定时，**不得自行猜测或编造**。

### 14.1 必须做的事情

- 在生成的代码中插入明确的注释，格式：  
  `// TODO(AI): 需要人工确认 - <具体问题描述>`
- 在 PR_history 文件中增加一个 **“待确认事项”** 小节，列出所有不确定点。
- 向用户提问，等待用户明确答复后再继续。

### 14.2 示例

```dart
// TODO(AI): 需要人工确认 - 该 API 的响应字段是 `data.list` 还是 `data.items`？
final response = await dio.get('/courses');
```

PR_history 中的待确认事项：

```markdown
## 待确认事项（需人工回复后修改代码）
1. 教室预约 API 的认证方式：是否复用 ZJU SSO 还是需要独立 token？
2. 课程列表接口的分页参数名是 `page` 还是 `offset`？
```

### 14.3 禁止的行为

- ❌ 假设一个不存在的方法或参数
- ❌ 编造示例输出（如假 JSON）
- ❌ 擅自选择一个“看起来合理”的方案而不告知用户

---

> **最后提醒**：Agent 如果对任何规则不确定，请在生成的代码中加上 `// TODO(AI): confirm with user about ...` 注释，并主动向用户提问。宁可多问，不要瞎猜。