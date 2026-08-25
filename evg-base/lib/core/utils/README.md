# 工具

| 元信息 | 值 |
| --- | --- |
| 状态 | active |
| 版本 | 以根 `README.md` 为准 |
| 日期 | 2026-08-02 |
| 负责人 | 待补充 |
| 适用 | utils（路径/沙箱/Python 环境） |

> 源码 `safe_parse.dart` `token_estimator.dart` `python_env.dart` `greenix_path.dart` `path_sandbox.dart` `file_utils.dart` `plugin_asset_releaser.dart`、测试 `../test/path_sandbox_test.dart`
>
> HTML-first 下，这些工具主要为平台内部、Agent 工具与高级插件服务；普通 HTML 插件通过 JS Bridge 访问平台能力，不直接调用 Dart utils。

通用工具——安全解析、Token 估算、Python 环境、运行路径、路径沙箱、资产释放、文件管理。仅面向平台开发者。

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

`python_env.dart` — **统一解释器路径发现（单例收敛）+ 依赖安装 + 子进程执行**。

自 2026-08-25（t9）起，全仓 Python 解释器发现统一收敛到 `PythonInterpreter.resolve()`，
解析顺序：**configuredPath → Greenix 嵌入式目录 → 系统 PATH → 安卓 Chaquopy 标记**。
Greenix 目录由 `bindGreenixPythonDir(() => greenixPythonDir)` 在 app 启动
（`app_bootstrap` 的 `initGreenixPaths()` 之后）绑定为单一真理来源，消除
`python_env` 内联 cwd 路径与 `greenix_path.greenixPythonDir` 的双真理。

```dart
import 'package:evergreen_base/core/utils/python_env.dart';

// ① 新代码：结构化解析（推荐）
final rt = await PythonInterpreter.instance.resolve();
if (rt.isAvailable) {
  if (rt.isAndroidChaquopy) {
    // 安卓进程内解释器：走 ChaquopyRunner / MethodChannel，不可当命令执行
  } else {
    Process.run(rt.exePath!, [script], ...); // rt.kind: bundled | system
  }
}

// ② 旧签名兼容层（行为不变，内部已收敛到单例）
final py = await resolvePythonExe(configuredPath: bundledCandidate);
if (py != null) { /* 安卓返回 kChaquopySentinel */ }

// ③ 同步组装点（无法 await 的 provider 构造等）
final bundled = PythonInterpreter.bundledPathSync(); // → greenix 目录 python.exe 或 null
```

| 成员 | 说明 |
|------|------|
| `PythonInterpreter.instance.resolve({configuredPath})` | `Future<PythonRuntime>` — 统一解析入口（成功结果缓存，configuredPath 传参跳过缓存） |
| `PythonRuntime` | 结构化结果：`kind`（bundled/system/androidChaquopy/none）+ `exePath` + `isAvailable`/`isAndroidChaquopy`/`isBundled`/`legacyExePath` |
| `PythonRuntimeKind` | 运行时种类枚举（哨兵收敛，杜绝字符串散落） |
| `kChaquopySentinel` | 安卓哨兵常量（`'chaquopy'`，`legacyExePath` 在安卓返回） |
| `bindGreenixPythonDir(provider)` | 绑定 Greenix Python 目录（app 启动调用；消除双真理来源；会清空缓存） |
| `PythonInterpreter.resolveExePath({configuredPath})` | 兼容旧签名：返回路径 / 哨兵 / null |
| `PythonInterpreter.bundledPathSync()` | 同步探测嵌入式 Python（供无法 await 的组装点） |
| `resolvePythonExe({configuredPath})` | 顶层兼容包装（行为不变，收敛到单例） |
| `PythonEnv({python, requirements})` | OCR 依赖检查/安装实例（`pythonExe` 内部走单例） |
| `runOcrProcess(exe, args, {dir})` | 运行 OCR Python 子进程 |
| `pipInstallPackages(packages, {pythonExe, timeout})` | pip 安装（⚠️ 仅桌面：安卓 Chaquopy 无 pip，依赖须构建期打进 APK） |

---

## 四、运行路径

`greenix_path.dart` — 统一管理 `.greenix/` 下所有持久化目录与插件目录解析，对应 module/ 的 `WorkspaceDescriptor`。路径唯一真理来源，UI/插件禁止硬编码相对路径。

```dart
import 'package:evergreen_base/core/utils/greenix_path.dart';

await initGreenixPaths();                        // main() 启动时调用一次（须 await）
resolvePluginsRoot();                            // → plugins/ 绝对路径（按优先级逐级解析，见下表）
resolveProjectRoot();                            // → 含 pubspec.yaml 的项目根（向上查找）

greenixMemoriesDir;                              // → .greenix/memories/
greenixSkillsDir;                                // → .greenix/skills/（旧版平铺，仅兼容读取）
greenixSkillPluginDir('skill-name');             // → plugins/<id>/skill/（Skill 即插件，规范路径）
greenixSessionsDir;                              // → .greenix/sessions/
greenixPythonDir;                                // → .greenix/python/
greenixScriptsDir;                               // → .greenix/scripts/（OCR/论文/翻译脚本，资产释放填充）
greenixPluginsDir;                               // → .greenix/plugins/
greenixWorkspacesDir;                            // → .greenix/workspaces/
greenixWorkspaceDir('agent');                    // → .greenix/workspaces/agent/
ensureWorkspaceDir('agent');                     // 确保目录存在
listWorkspaceFiles('agent');                     // 列出工作区文件
resolvePluginAssetPath(raw, moduleId, pluginsDir); // manifest 相对资源路径 → 插件目录绝对路径
```

| 函数 | 输出 | 说明 |
|------|------|------|
| `initGreenixPaths()` | `Future<void>` | 初始化基础目录（main 中调用一次；移动端用 app 可写目录） |
| `resolvePluginsRoot()` | `String` | 插件根绝对路径：安卓释放目录 → `EVERGREEN_PLUGINS_DIR` → 项目根 → `.greenix/plugins` → cwd 回退 |
| `resolveProjectRoot()` | `String?` | 从可执行文件目录 / cwd 向上找 `pubspec.yaml` 所在目录 |
| `androidPluginsDir` | `String` | 安卓插件释放目录（=`greenixPluginsDir`） |
| `greenixMemoriesDir` | `String` | `.greenix/memories/` |
| `greenixSkillsDir` | `String` | `.greenix/skills/` 旧版平铺路径（兼容读取） |
| `greenixSkillPluginDir(name)` | `String` | `plugins/<id>/skill/` 插件形态 Skill 目录 |
| `greenixSkillPluginPath(name)` | `String` | `plugins/<id>/skill/<id>.md`（Skill 唯一写入路径） |
| `greenixSessionsDir` | `String` | `.greenix/sessions/` 会话持久化目录 |
| `greenixPythonDir` | `String` | `.greenix/python/` 嵌入式 Python 运行时 |
| `greenixScriptsDir` | `String` | `.greenix/scripts/` 管线脚本目录 |
| `greenixPluginsDir` | `String` | `.greenix/plugins/`（安卓/分布式桌面插件目录） |
| `greenixWorkspacesDir` | `String` | `.greenix/workspaces/` |
| `greenixWorkspaceDir(id)` | `String` | `.greenix/workspaces/<id>/`，按模块隔离 |
| `ensureWorkspaceDir(id)` | `void` | 确保工作区目录存在 |
| `listWorkspaceFiles(id)` | `List<FileSystemEntity>` | 列出工作区所有文件 |
| `resolvePluginAssetPath(raw, id, dir)` | `String?` | manifest 相对资源 → 插件目录绝对路径 |

> 其他持久化点位：`greenixConfigPath`（config.json 同步副本）、`greenixEnvPath`（爬虫环境变量）、
> `greenixScopePath`（探索授权）、`greenixJournalDir`（探索 Journal）、`cookieJarPath` / `zjuCookiesPath`（SSO 会话）。

---

## 五、路径沙箱

`path_sandbox.dart` — 防止 Agent 工具越界读写文件。

```dart
import 'package:evergreen_base/core/utils/path_sandbox.dart';

final sandbox = PathSandbox('/workspace/ai-assistant');
final safe = sandbox.confine('output/report.md');       // → /workspace/ai-assistant/output/report.md
final blocked = sandbox.confine('../../../etc/passwd'); // → null (被拒绝)
```

| 函数 | 输入 | 输出 | 说明 |
|------|------|------|------|
| `PathSandbox(root)` | `root: String` 沙箱根目录 | `PathSandbox` | 创建沙箱实例 |
| `.confine(path)` | `path: String` 用户提供的路径 | `String?` | 约束在沙箱内返回绝对路径，越界返回 null |
| `.root` | — | `String` | 沙箱根目录（绝对路径） |
| `PathSandboxException` | — | — | 路径越界异常 |

---

## 六、文件管理

`file_utils.dart` — 跨平台文件管理器。

```dart
import 'package:evergreen_base/core/utils/file_utils.dart';

openInFileManager('/path/to/file');  // 打开文件管理器并定位
```

| 函数 | 输入 | 输出 | 说明 |
|------|------|------|------|
| `openInFileManager(path)` | `path: String` | `void` | 打开系统文件管理器并定位到文件/目录 |

---

## 七、资产释放

`plugin_asset_releaser.dart` — 把打包进 APK/安装包的插件与 Python 脚本资产一次性释放到可写目录（幂等）。

```dart
import 'package:evergreen_base/core/utils/plugin_asset_releaser.dart';

await releasePluginsAssetsIfNeeded();   // 释放插件 bundle → resolvePluginsRoot() 指向的目录
await releaseScriptsAssetsIfNeeded();   // 释放 Python 脚本 → greenixScriptsDir
```

| 函数 | 输出 | 说明 |
|------|------|------|
| `releasePluginsAssetsIfNeeded()` | `Future<void>` | 幂等释放插件资产（校验产物完整性，不只看标记） |
| `releaseScriptsAssetsIfNeeded()` | `Future<void>` | 幂等释放 OCR/论文/翻译脚本到 `.greenix/scripts` |

> 释放目标与 `greenix_path.resolvePluginsRoot()` / `greenixScriptsDir` 一致（安卓侧统一入口），
> 桌面端由安装包预置，无需释放。

---

## 规则

- `SafeParse` — 所有 JSON 解析统一入口。
- `PythonEnv` — 子进程执行，不依赖平台 API。
- `greenix_path.dart` — 纯路径计算，无外部依赖。工作区路径按 module id 隔离。
- `path_sandbox.dart` — 规范化路径 + 越界拒绝，所有 Agent 文件操作工具统一入口。
- `file_utils.dart` — 仅调用系统命令（explorer / open / xdg-open），使用 Log() 替代 Flutter debugPrint。
