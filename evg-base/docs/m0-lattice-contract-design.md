# M0 第 1 步设计草案 —「契约格」（contract lattice）六格契约 + 往返测试清单

> 状态：**待评审（v0.1）**。本文件只做设计，未经批准**不落 `.dart` 代码**。
> 上游规划：根目录 `plugin-ecosphere.md`（M0：契约字段，12–15 commits）。
> 落点：`evg-base/lib/core/module/module_descriptor.dart`（`ModuleDescriptor`）+ 同包建议新增 `lattice.dart` / `runtime.dart`。

## 1. 背景与目标

Evergreen 2.0-beta 的第三方插件将来自「zju 场景插件市场」——自动爬取 GitHub 上为浙大做的 repo 并转成可加载插件。第三方代码不可信，必须在**契约层**先回答一个问题：*这个插件运行时能做什么？*

六格契约（lattice 0–5）把插件运行时能力分成六个信任等级，从最安全到最外置：

| 格 | 契约 | 运行时形态 | 平台交互 |
|---|---|---|---|
| 0 | `static-web` | 纯静态 HTML/CSS/JS | 无 bridge，零权限 |
| 1 | `web-bridged` | HTML + JS Bridge | `platform.*`，按 capability 开票 |
| 2 | `data-source` | 数据源声明（`orch://`） | DataHttpServer |
| 3 | `sidecar` | 独立进程（Node/Python/Deno） | RPC（HTTP/stdio）+ 能力沙箱 |
| 4 | `agent-tool` | Agent 工具声明 | PluginBridge / skill 激活 |
| 5 | `external-app` | 外部应用 | 深链，不内嵌 |

M0 只做「契约字段 + 往返测试」：让 manifest 能**声明** lattice/runtime/capabilities，并在 `ModuleDescriptor` 里**解析、校验、往返**。不启动进程、不执行权限——那是 M1/M2。

---

## 2. 契约格 JSON schema（wire format）

### 2.1 `lattice` 字段

```json
"lattice": "sidecar"
```

可选；缺省时按 §2.4 推断。枚举（wire 连字符 ↔ Dart 小驼峰）：

| wire 值 | Dart enum |
|---|---|
| `static-web` | `Lattice.staticWeb` |
| `web-bridged` | `Lattice.webBridged` |
| `data-source` | `Lattice.dataSource` |
| `sidecar` | `Lattice.sidecar` |
| `agent-tool` | `Lattice.agentTool` |
| `external-app` | `Lattice.externalApp` |

解析规则：
- 大小写不敏感；下划线与连字符等价（`web_bridged` == `web-bridged`）。
- **缺失** → 推断（§2.4）。
- **存在但非法** → `FormatException`（fail-closed：安全相关字段不静默降级为高权限格）。

### 2.2 `runtime` 字段（仅 `sidecar` 格）

```json
"runtime": {
  "kind": "node",
  "entry": "sidecar/index.js",
  "protocol": "http",
  "port": 0,
  "gracefulTimeoutMs": 8000,
  "capabilities": { }
}
```

| 字段 | 取值 | 缺省 |
|---|---|---|
| `kind` | `node` \| `python` \| `deno` | 必填 |
| `entry` | 相对插件根的入口路径 | 必填 |
| `protocol` | `http` \| `stdio` | `http` |
| `port` | `0` = 自动分配 | `0` |
| `gracefulTimeoutMs` | 优雅停机超时 | `8000` |
| `capabilities` | §2.3 | deny-all |

校验规则：
- `lattice == sidecar` 且缺 `runtime` → `FormatException`。
- `lattice != sidecar` 却带 `runtime` → `FormatException`（避免「声明了进程却按静态渲染」的静默降级）。

### 2.3 `capabilities`（能力申请，flat 键）

```json
"capabilities": {
  "fs.scope": "plugin-dir",
  "net.allow": ["127.0.0.1", "api.github.com:443"],
  "spawn": []
}
```

| 键 | 取值 | 缺省 | 说明 |
|---|---|---|---|
| `fs.scope` | `none` \| `plugin-dir` \| `app-data` | `none` | v1 不允许 `home`/绝对路径 |
| `net.allow` | `string[]`，条目形如 `host` / `host:port` | `[]` | 白名单制；v1 禁止 `*` |
| `spawn` | `string[]` 可执行名白名单 | `[]` | 空 = 禁子进程 |

红线：
- **deny-all 默认**：三键全缺省 = 零权限。能力只窄不宽。
- 非法 `fs.scope`、空串/`file://` 类 `net.allow` 条目 → `FormatException`。
- 未知 capability 键（如 `net.wildcard`）→ **静默忽略**（沿用「未知字段静默忽略」约定）。

### 2.4 缺省 `lattice` 推断表（向后兼容）

manifest 没有 `lattice` 时，按现有信号推断：

| 优先级 | 信号 | 推断结果 | 理由 |
|---|---|---|---|
| 1 | `runtime` 存在 | `sidecar` | 显式声明进程 |
| 2 | `template == 'html'` | `web-bridged` | HTML-first 现状即走 bridge，不回归 |
| 3 | `template == 'scraper'` | `data-source` | 爬虫产出数据源 |
| 4 | `dataSource` 或 `dataSources` 存在 | `data-source` | 声明式数据源 |
| 5 | `activateSkills` 非空 | `agent-tool` | agent 工具声明 |
| 6 | 其它（v4 及内置声明式模板） | `static-web` | 最安全兜底：纯声明，无代码执行 |

> ⚠️ 语义张力见 §6 O1：v4 是 Flutter 声明式 UI，并非「静态网页」，用 `static-web` 作信任兜底是否可接受，待拍板。

---

## 3. Dart 侧类型映射（仅命名，M0 不写实现）

建议新增 `evg-base/lib/core/module/lattice.dart` 与 `runtime.dart`，`ModuleDescriptor` 增两字段：

```dart
// 命名草案（非实现）
enum Lattice { staticWeb, webBridged, dataSource, sidecar, agentTool, externalApp }
enum RuntimeKind { node, python, deno }
enum RuntimeProtocol { http, stdio }
enum FileScope { none, pluginDir, appData }

class RuntimeCapabilities {
  final FileScope fsScope;        // 默认 none
  final List<String> netAllow;    // 默认 []
  final List<String> spawnAllow;  // 默认 []
  bool get isDenyAll =>
      fsScope == FileScope.none && netAllow.isEmpty && spawnAllow.isEmpty;
}

class RuntimeDescriptor {
  final RuntimeKind kind;
  final String entry;
  final RuntimeProtocol protocol; // 默认 http
  final int port;                 // 默认 0
  final int gracefulTimeoutMs;    // 默认 8000
  final RuntimeCapabilities capabilities;
}
```

`ModuleDescriptor` 增加：
```dart
final Lattice? lattice;           // 可空：直接构造可缺省；fromJson 恒解析为具体值
final RuntimeDescriptor? runtime; // 仅 sidecar 格非空
```

序列化约定（对齐现有 `toJson` 省默认值风格）：
- `lattice`：仅当 JSON 里**显式出现** `lattice` 键（或构造时显式传入）才写回——用私有 `_latticeExplicit` 标志（见 O4）。
- `runtime`/`capabilities`：非默认值才写回；`capabilities.isDenyAll` 时不写 `capabilities`。

---

## 4. 安全红线（M0 就钉死）

1. **fail-closed**：非法 lattice/runtime/capabilities 一律 `FormatException`，绝不静默放宽。
2. **deny-all 默认**：capabilities 三字段缺省 = 零权限。
3. **窄权限**：`fs.scope` 上限 `app-data`，无 `home`、无绝对路径；`net.allow` 白名单制，v1 禁止 `*`。
4. **只声明不执行**：M0 只解析/校验/往返；进程启动与权限执行在 M1/M2 落地。

---

## 5. 往返测试用例清单（M0 验收）

> 全部写入 `evg-base/lib/core/module/test/lattice_roundtrip_test.dart`（或并入 `descriptor_test.dart`），沿用现有 group/test 风格。

### G1 — lattice 解析与默认推断

| # | 用例 | 断言 |
|---|---|---|
| 1 | 缺 lattice + `template:'html'` | → `web-bridged` |
| 2 | 缺 lattice + `dataSource` 存在 | → `data-source` |
| 3 | 缺 lattice + `dataSources` 存在 | → `data-source` |
| 4 | 缺 lattice + `activateSkills` 非空 | → `agent-tool` |
| 5 | 缺 lattice + `runtime` 存在 | → `sidecar`（优先级最高） |
| 6 | 缺 lattice + 纯 v4 pages | → `static-web` |
| 7 | 显式 `lattice:'sidecar'` | 精确 `sidecar`，不受其它信号影响 |
| 8 | `web_bridged` / `WEB-BRIDGED` 容错 | → `web-bridged` |
| 9 | `lattice:'quantum'` | `throwsFormatException`（fail-closed） |
| 10 | 六格逐一往返 | `Lattice.values` 各 round-trip |

### G2 — runtime 描述符

| # | 用例 | 断言 |
|---|---|---|
| 11 | 完整 runtime 往返 | 全字段恢复相等 |
| 12 | runtime 缺省字段 | protocol→http / port→0 / gracefulTimeoutMs→8000 |
| 13 | `kind:'rust'` / `protocol:'grpc'` | `throwsFormatException` |
| 14 | `sidecar` 缺 `runtime` | `throwsFormatException` |
| 15 | `static-web` 却带 `runtime` | `throwsFormatException`（防静默降级） |
| 16 | `entry` 空串/缺失 | `throwsFormatException` |

### G3 — capabilities

| # | 用例 | 断言 |
|---|---|---|
| 17 | capabilities 全缺省 | deny-all（none/[]/[]） |
| 18 | `fs.scope` 三值 round-trip | none/plugin-dir/app-data |
| 19 | `fs.scope:'home'` / `'/'` | `throwsFormatException` |
| 20 | `net.allow` 白名单 round-trip | 列表恢复相等 |
| 21 | `net.allow:['']` / `['file://x']` | `throwsFormatException` |
| 22 | `spawn:[]` 与 `spawn:['node']` round-trip | 恢复相等 |
| 23 | 未知 capability 键 | 静默忽略，不抛 |
| 24 | toJson 省 deny-all capabilities | 输出不含 `capabilities` 键 |

### G4 — 序列化与幂等

| # | 用例 | 断言 |
|---|---|---|
| 25 | 旧 manifest round-trip 不新增字段 | 无 `lattice`/`runtime` 键（依赖 O4 标志） |
| 26 | 显式 lattice 写回 | toJson 含 `lattice` |
| 27 | `fromJson(toJson(d)) == d`（幂等） | 六格各一次 |

### G5 — 与 v5P 字段共存

| # | 用例 | 断言 |
|---|---|---|
| 28 | lattice 与 template/dataSource/dataSources/modleRoute 共存 | 互不覆盖 |
| 29 | 现有 850 行 descriptor_test 全绿 | 无回归 |

---

## 6. 开放问题（请拍板）

- **O1（推断兜底）**：v4/内置声明式模块映射 `static-web` 有语义张力（并非「网页」）。备选：引入第 7 个 `native` 格，或 `lattice` 可空表示「首方原生」。推荐先按 §2.4 表落地——M0 只影响解析，不改变渲染行为。
- **O2（非法值策略）**：非法 lattice 抛 `FormatException`（推荐，fail-closed）还是静默回退推断值？（推荐抛）
- **O3（capabilities 序列化）**：deny-all 时 `toJson` 是否省略 `capabilities` 键？（推荐省略，对齐现有省默认值风格）
- **O4（显式性追踪）**：为保证旧 manifest 字节兼容，需 `_latticeExplicit` 私有标志区分「显式声明」与「推断」；是否接受？（推荐接受）
- **O5（spawn 类型）**：`spawn` 用可执行名白名单 `string[]`（推荐，窄权限更可控）还是布尔开关？

---

## 7. 批准后下一步（M0 实现动工）

1. 新增 `lattice.dart`（枚举 + parse/format + 推断函数）与 `runtime.dart`（RuntimeDescriptor/RuntimeCapabilities/FileScope + fromJson/toJson）。
2. `ModuleDescriptor` 增 `lattice`/`runtime` 两字段（含 `_latticeExplicit`），`fromJson`/`toJson` 接入。
3. 新增 `lattice_roundtrip_test.dart`（§5 全部用例），旧 descriptor_test 保持全绿。
4. `modules.dart` barrel 导出 + `core/module/README.md` 字段表更新。
