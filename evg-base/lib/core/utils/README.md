# 工具

> 源码 `safe_parse.dart` `token_estimator.dart` `python_env.dart` `greenix_path.dart` `file_utils.dart`、测试（待添加）

通用工具——安全解析、Token 估算、Python 环境、运行路径、文件工作区、文件管理。仅面向平台开发者。

---

## 一、安全解析

`SafeParse` — 将 `dynamic` 值安全转为具体类型。

```dart
import 'package:evergreen_base/core/utils/safe_parse.dart';

SafeParse.string(json['name']);           // → String，默认 ''
SafeParse.double_(json['score']);         // → double，默认 0.0
SafeParse.int_(json['count']);            // → int，默认 0
SafeParse.bool_(json['enabled']);         // → bool，默认 false
SafeParse.dateTime(json['created_at']);   // → DateTime?，失败 null
```

| 函数 | 输入 | 输出 | 说明 |
|------|------|------|------|
| `.string(v, {defaultValue})` | `v: dynamic` | `String` | 安全转字符串 |
| `.double_(v, {defaultValue})` | `v: dynamic` | `double` | 安全转浮点 |
| `.int_(v, {defaultValue})` | `v: dynamic` | `int` | 安全转整数 |
| `.bool_(v, {defaultValue})` | `v: dynamic` | `bool` | 安全转布尔 |
| `.dateTime(v)` | `v: dynamic` | `DateTime?` | 安全转时间 |

---

## 二、Token 估算

`TokenEstimator` — 估算文本/对话的 token 数。

```dart
import 'package:evergreen_base/core/utils/token_estimator.dart';

final tokens = TokenEstimator.estimate('Hello world');
final total = TokenEstimator.estimateConversation(messages);
```

| 函数 | 输入 | 输出 | 说明 |
|------|------|------|------|
| `.estimate(text)` | `text: String` | `int` | 估算单条文本 token 数 |
| `.estimateConversation(msgs)` | `msgs: List<Map>` | `int` | 估算对话总 token 数 |

---

## 三、Python 环境

`PythonEnv` — Python 解释器发现 + 依赖安装 + 子进程执行。

```dart
import 'package:evergreen_base/core/utils/python_env.dart';

final env = PythonEnv();
final error = await env.ensureReady(onProgress: (msg) => print(msg));
if (error != null) print('环境异常: $error');
```

| 函数 | 输入 | 输出 | 说明 |
|------|------|------|------|
| `PythonEnv({python, requirements})` | `python: String?` 自定义路径<br>`requirements: String?` 自定义 requirements.txt | `PythonEnv` | 创建实例 |
| `.ensureReady({onProgress})` | `onProgress: void Function(String)` | `Future<String?>` | 检查并安装依赖，null 则就绪 |
| `.checkDeps()` | — | `Future<String?>` | 仅检查依赖 |
| `.installDeps({onProgress})` | `onProgress: void Function(String, bool)` | `Future<bool>` | 仅安装 |
| `resolvePythonExe({configuredPath})` | `configuredPath: String?` | `Future<String?>` | 自动发现 Python 路径 |
| `runOcrProcess(exe, args, {dir})` | `exe: String`, `args: List<String>`, `dir: String?` | `Future<ProcessResult>` | 运行 Python 子进程 |

---

## 四、运行路径

`greenix_path.dart` — 统一管理 `.greenix/` 下所有持久化目录，对应 module/ 的 `WorkspaceDescriptor`。

```dart
import 'package:evergreen_base/core/utils/greenix_path.dart';

initGreenixPaths();                              // main() 启动时调用一次

greenixMemoriesDir;                              // → .greenix/memories/
greenixSkillsDir;                                // → .greenix/skills/
greenixWorkspacesDir;                            // → .greenix/workspaces/
greenixWorkspaceDir('agent');                    // → .greenix/workspaces/agent/
ensureWorkspaceDir('agent');                     // 确保目录存在
listWorkspaceFiles('agent');                     // 列出工作区文件
```

| 函数 | 输出 | 说明 |
|------|------|------|
| `initGreenixPaths()` | `void` | 初始化基础目录（main 中调用一次） |
| `greenixMemoriesDir` | `String` | `.greenix/memories/` |
| `greenixSkillsDir` | `String` | `.greenix/skills/` |
| `greenixWorkspacesDir` | `String` | `.greenix/workspaces/` |
| `greenixWorkspaceDir(id)` | `String` | `.greenix/workspaces/<id>/`，按模块隔离 |
| `ensureWorkspaceDir(id)` | `void` | 确保工作区目录存在 |
| `listWorkspaceFiles(id)` | `List<FileSystemEntity>` | 列出工作区所有文件 |

---

## 五、文件管理

`file_utils.dart` — 跨平台文件管理器。

```dart
import 'package:evergreen_base/core/utils/file_utils.dart';

openInFileManager('/path/to/file');  // 打开文件管理器并定位
```

| 函数 | 输入 | 输出 | 说明 |
|------|------|------|------|
| `openInFileManager(path)` | `path: String` | `void` | 打开系统文件管理器并定位到文件/目录 |

---

## 规则

- `SafeParse` — 所有 JSON 解析统一入口。
- `PythonEnv` — 子进程执行，不依赖平台 API。
- `greenix_path.dart` — 纯路径计算，无外部依赖。工作区路径按 module id 隔离。
- `file_utils.dart` — 仅调用系统命令（explorer / open / xdg-open）。
