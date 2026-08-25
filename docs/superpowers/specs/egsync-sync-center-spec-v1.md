# .egsync 同步中心契约规格 v1（远程同步中心 · 主题 3）

| 元信息 | 值 |
| --- | --- |
| 状态 | active（契约层已落地，导出/导入端待实现） |
| 版本 | 以根 `README.md` 为准（本规格内部版本见 §十一） |
| 日期 | 2026-08-25 |
| 牵头 | core-config（契约 + config.evgconfig v2） |
| 关联 | `docs/2026-08-25-general-pluginization-plan.md` §3（总规划） |

> 本规格是远程同步中心（.egsync）的**契约层**产出：定义 .egsync.zip 包结构、
> `config.evgconfig` v2 格式、同步选项模型、跨平台路径规则与会话元数据契约。
> 导出端（pack_sync + 勾选 UI，t-C2）、导入端（插件/数据源回放，t-C3）、
> 记忆拼接/会话合并（t-C4）均以本规格为接口依据。
> 已落地实现：config v2 读写（`lib/core/config/settings.dart` / `permissions.dart` /
> `config_http_server.dart`，修复 O1 六缺陷）；未落地：包级 zip 打包、UI、导入端、合并算法。

---

## 一、目标与范围

- 把**所有配置、AI 助手对话历史、断点、插件、主题、Skill、记忆**等资源导出为
  `.egsync.zip` 并跨平台（Windows / Android / macOS / Linux）加载。
- **同步选项由用户自行选择**：资源类型 × 插件分组双维勾选。
- 合并语义（用户指定）：全局记忆直接拼接；对话历史「包含则删小 / 路径分化都保留」；
  配置按 key 合并（覆盖/保留/备份由用户选择）；插件/数据源/主题版本感知冲突。

## 二、.egsync.zip 包结构

```
.egsync.zip
├── manifest.json          # 包级契约（§三）
├── config/
│   └── config.evgconfig   # 配置资源（§四，.evgconfig v2）
├── sessions/              # 对话历史（可选；合并后，见 §七）
├── memories/              # 全局记忆（可选；直接拼接后）
├── plugins/<pluginId>/    # 插件（可选；.plugin 信封布局，含能力子目录）
├── data/<pluginId>/       # 数据源（可选；data/ + config/）
└── themes/<pluginId>/     # 主题（可选；theme/theme.json）
```

规则：
- 包内**全部为相对路径**（虚拟 sync 根），禁止绝对路径（§六）。
- 未勾选的资源类型对应的目录**不出现**。
- 目录内文件布局与源平台 `.greenix/` / `plugins/` / `workspaces/` 一致
  （如 `sessions/{id}.json`、`plugins/<id>/module/index.html`），导入端原样落盘。

## 三、manifest.json 契约

```json
{
  "type": "egsync",
  "version": 1,
  "exportedAt": "2026-08-25T12:00:00.000Z",
  "appVersion": "2.0.0-rc.1",
  "platform": "windows",
  "resources": ["config", "sessions", "memories", "plugins", "data", "themes"],
  "options": {
    "selections": {
      "resources": ["config", "sessions"],
      "pluginGroups": ["builtins", "zdbk"]
    },
    "includeSecure": false,
    "merge": "merge"
  }
}
```

| 字段 | 类型 | 必填 | 说明 |
|---|---|---|---|
| `type` | string | 是 | 恒为 `"egsync"`（导入端 fail-closed 校验之一） |
| `version` | int | 是 | 包格式版本，递增；导入端接受 `[1..当前]`，更高版本拒绝 |
| `exportedAt` | string | 是 | ISO-8601 导出时间 |
| `appVersion` | string | 否 | 导出端应用版本（用于导入端兼容提示） |
| `platform` | string | 否 | 导出端平台（windows/android/linux/macos） |
| `resources` | string[] | 是 | 实际包含的资源类型清单（与顶层目录一一对应） |
| `options.selections` | object | 否 | 用户勾选快照（回显用，不参与导入逻辑） |
| `options.includeSecure` | bool | 否 | 是否包含 isSecure 明文（默认 false） |
| `options.merge` | string | 否 | `merge`（合并导入）/ `overwrite`（全量覆盖） |

版本兼容策略：
- 包级：`version` 递增；导入端仅支持 `[1..当前]`，`version > 当前` → 拒绝并提示升级应用。
- 未知资源类型：导入端**静默跳过**（沿用「未知静默忽略」约定），不阻断其余资源。
- 子文件独立版本：`config.evgconfig` 自带 `format`/`version`（§四）。

## 四、config.evgconfig v2 格式

### 4.1 版本与兼容

- 当前版本 `version: 2`（`kEvgConfigVersion`），最低支持导入 `version: 1`。
- **v2 = v1 + 三个可选新增段**：`dynamicSettings` / `permissions` / `appPrefs`。
- 向后兼容：旧导入器忽略新段；新导入器直接读取 v1 文件（v1 语义不变）。

### 4.2 完整结构

```json
{
  "format": "evgconfig",
  "version": 2,
  "exportedAt": "2026-08-25T12:00:00.000Z",
  "settings": { "DEEPSEEK_MODEL": "deepseek-v4-flash" },
  "dynamicSettings": { "MY_PLUGIN_CRED": "xxx" },
  "sources": [ { "url": "https://...", "name": "自定义源" } ],
  "permissions": { "my_plugin": { "web_search": true } },
  "appPrefs": { "active_theme_id": "ocean" },
  "aiMemory": { },
  "extra": { }
}
```

| 段 | v 引入 | 内容 | 说明 |
|---|---|---|---|
| `format` / `version` / `exportedAt` | v1 | 标头 | 导入端校验（§4.3） |
| `settings` | v1 | `key → String` | 仅**已声明**设置项；isSecure 默认跳过（见下） |
| `dynamicSettings` | v2 | `key → String` | 动态注册项（来源 `ConfigHttpServer.dynamicSettingKeys`） |
| `sources` | v1 | JSON 数组 | 自定义插件源（默认源不序列化，导入端恒有） |
| `permissions` | v2 | `pluginId → {permKey: bool}` | **bool 正确类型**（修复 O1①） |
| `appPrefs` | v2 | `key → String` | 未声明应用偏好（active_theme_id 等，调用方白名单） |
| `aiMemory` | v1 | 任意 JSON | 由 Agent 模块自行导入，Config 不解析 |
| `extra` | v1 | `key → String` | 兼容保留；导入端白名单过滤，`perm.*` 键走 `permissions` 段 |

isSecure 处理：导出默认**跳过** `isSecure` 声明项（防 API Key 明文泄漏），
`includeSecure: true` 才包含；导入默认跳过（防覆盖现有密钥），`allowSecure: true` 放行。

### 4.3 导入安全模型（O1 修复落点，已实现）

1. **version 校验**（O1④）：`format` 非 `evgconfig` 或 `version` 超出 `[1..2]` → 抛
   `ConfigValidationException`，拒绝导入。
2. **settings 白名单 + 类型语义校验**：仅写已声明键；`bool_` 必须 `"true"/"false"`、
   `option` 必须在选项列表，非法值跳过（stderr 提示）。
3. **dynamicSettings 白名单**（O1②）：仅写入调用方传入的 `allowedDynamicKeys`
   （= `ConfigHttpServer.dynamicSettingKeys`），杜绝任意 key 写入。
4. **permissions 正确类型**（O1①）：经 `importPermissions` 以 bool 读写，仅接受
   **已注册插件**的**已声明**权限键，走 `setPermission` 语义（非裸 SP 写）。
5. **appPrefs / extra 白名单**（O1③）：extra 白名单 = 已声明设置 ∪ allowedDynamicKeys
   ∪ allowedAppPrefs；`perm.*` 键跳过并提示改用 permissions 段。
6. **导入后回调**（O1⑤）：`onChanged` 在发生实际写入后触发；ConfigHttpServer 提供
   `importConfigAndSync(...)` 便捷方法，自动在导入成功后 `syncConfigToGreenix()`。
7. **覆盖语义**：`overwrite` 默认 `true`（保持 v1 导入语义）；同步合并导入传
   `overwrite: false` 启用非空值保护（已有非空值不被覆盖，沿用 greenix 同步哲学）。

### 4.4 分组与子集筛选数据源

- 声明式设置项来源：`getSettingSources()` → `key → 插件 id`（builtins / 插件目录名 /
  config.json `id` 字段）。
- 动态注册项：`ConfigHttpServer.dynamicSettingKeys`。
- 未声明应用偏好：调用方白名单（导出端 UI 提供候选清单，如
  `active_theme_id`/`sidebar_collapsed`/`tool_disabled`/`translate_lang_in`/`translate_lang_out`/
  `translate_model`/`html_creator_layout_mode` 等）。

## 五、同步选项模型（导出端 UI 数据结构，t-C2 使用）

```dart
/// 资源类型（与 manifest.resources / 顶层目录一一对应）。
enum SyncResourceType { config, sessions, memories, plugins, data, themes }

class SyncSelection {
  final Set<SyncResourceType> resources;          // 资源类型勾选
  final Set<String> pluginGroups;                  // 插件分组勾选（builtins / 插件 id）
  final bool includeSecure;                        // 是否导出 isSecure 明文
  final bool overwriteOnImport;                    // 导入冲突策略：覆盖 vs 保留
}
```

- 维度 A：资源类型多选（默认全选，敏感项如 memories/env 单独提示）。
- 维度 B：配置子集按插件分组（builtins + 各 pluginId + 动态注册项 + 「应用偏好」组）。
- 序列化进 `manifest.options.selections`（回显用）。

## 六、跨平台路径规则

- 导出端：所有资源**相对化**后入包——`sessions/{id}.json`、`workspaces/...`、
  `plugins/<id>/...`、`memories/...`；**不序列化任何绝对路径**。
- 导入端：以目标平台运行时解析的根目录落盘：
  - `plugins/` → `resolvePluginsRoot()`（Windows 桌面 / Android 可写目录已统一，见
    `core/utils/greenix_path.dart`）。
  - `.greenix/` 下文件 → `greenixPath` 系（`initGreenixPaths()` 平台分支）。
- 路径类设置（`path` 类型，如 `MATERIAL_DOWNLOAD_PATH`/`PYTHON_EXE`/`VIDEO_OPENER`）：
  机器相关绝对路径，跨平台导入默认跳过或提供路径重映射（t-C2/t-C3 决策，本契约仅约定
  **导入端不得信任包内绝对路径**，解压做路径沙箱防 zip-slip——plugin_installer 已有先例）。
- Python 解释器路径运行时解析（`resolvePythonExe`），不序列化。

## 七、会话元数据契约（parent_id / fork_turn）

> 归属 core-agent 域（`lib/core/agent/`：`agent/session.dart` 模型 +
> `file_session_store.dart` 写盘）。本契约在此定义字段与合并语义；
> **模型落地已完成（t-C4，2026-08-25）**：`Session.parentId/forkTurn` 字段与
> `parent_id`/`fork_turn` 序列化、`forkSessionProvider` 分叉写入、
> `session_merge.dart` 合并算法、`memory/memory_merge.dart` 记忆拼接，
> 全部经 `lib/core/agent` 子包 `dart test`（251 用例，含新增 16 个合并用例）验证。

### 7.1 字段契约（`.greenix/sessions/{id}.json`）

```json
{
  "id": "sess_abc123",
  "parent_id": null,
  "fork_turn": null,
  "createdAt": "2026-08-25T10:00:00.000Z",
  "updatedAt": "2026-08-25T10:30:00.000Z",
  "messages": [ ]
}
```

| 字段 | 类型 | 说明 |
|---|---|---|
| `parent_id` | `string \| null` | 本会话派生的父会话 id；`null` = 根会话（默认） |
| `fork_turn` | `int \| null` | 分叉点在父会话 `messages` 中的 **0-based 索引**：子会话继承父消息 `[0..fork_turn)` 后路径分化；`null` = 未分叉（普通续写，父消息全继承） |

约束：
- `fork_turn != null` 时 `parent_id` 必须非空。
- 分叉点之后父/子消息内容不同（即真正分化）；若子会话只是父会话的**纯前缀扩展**
  （子消息 = 父消息 + 追加），则 `parent_id` 应置 `null`（或由合并算法按启发式判定）。

### 7.2 合并语义（t-C4 实施依据）

| 情形 | 判定 | 动作 |
|---|---|---|
| A 完全包含于 B | `A.parent_id == B.id` 且 `B.fork_turn == null`，且 A.messages 是 B.messages 前缀（或按 parent 链） | **删 A 保留 B**（"包含则删小"） |
| 路径分化 | `A.parent_id == B.id` 且 `A.fork_turn != null`，分叉点消息不同 | **A、B 都保留**（"路径分化都保留"） |
| 独立树 | `A.parent_id == null && B.parent_id == null` | 都保留 |
| 无元数据（旧数据/启发式兜底） | 前缀比较 A.messages ⊆ B.messages | 删小保大；否则都保留 |

### 7.3 落地建议（core-agent）— ✅ 已实施（t-C4，2026-08-25）

- `agent.Session` 增加 `parentId` / `forkTurn` 字段（`toJson`/`fromJson` 往返，旧数据缺失
  时回退 null，向后兼容）✅。
- 会话续写/复制时填充：分支入口（如「从此处继续」/多 Agent fork）设置
  `parentId = 当前会话 id`、`forkTurn = 分叉消息索引` ✅（`session_manager.dart`
  新增 `forkSessionProvider`；`createSessionProvider` 重置根会话；
  `switchSessionProvider` 透传派生元数据）。
- `FileSessionStore` 原样透传字段 ✅（`toJson`/`fromJson` 自动往返，无需改动）。

## 八、合并语义总表（引用总规划 §3.3）

| 资源 | 合并策略 | 落地 |
|---|---|---|
| 全局记忆 | 直接拼接（frontmatter+body 追加，索引重建） | t-C4（core-agent） |
| 对话历史 | 包含则删小 / 分化都保留（§7.2） | t-C4（core-agent） |
| 配置 | 按 key 合并；冲突覆盖/保留/备份由用户选择（`overwrite` 参数） | config v2 已支持（本任务） |
| 插件/数据源/主题 | 版本感知冲突（同内容 no-op / 新版覆盖 / 备份 config） | t-C3（core-module + core-data） |

## 九、安全

- 包级：`type` fail-closed 校验 + `version` 范围校验。
- 解压：路径沙箱（zip-slip 防护，plugin_installer 已有先例）——导入端不得信任包内绝对
  路径或 `../` 逃逸。
- 配置：白名单过滤（settings 已声明 / dynamic 白名单 / appPrefs 白名单 / permissions
  已注册插件已声明键）；isSecure 默认跳过；敏感项（memories/env.json）导出前用户确认。
- 冲突：非空值保护（`overwrite: false`）默认推荐，全量覆盖需用户显式选择。

## 十、已落地 vs 遗留跨域落地点

### 已落地（core-config 域）
- `lib/core/config/settings.dart`：exportConfig/importConfig v2（O1 六缺陷修复）、
  `kEvgConfigVersion`/`kEvgConfigMinVersion`、`getSettingSources()`、`_writeIfAllowed`。
- `lib/core/config/permissions.dart`：`getAllPermissions()` / `importPermissions()`。
- `lib/core/config/config_http_server.dart`：`dynamicSettingKeys` / `importConfigAndSync`。
- **`lib/core/config/sync_export_service.dart`（导出端 pack_sync，t15）**：见 §十二。
- 测试：settings_test.dart（+15 v2 用例）、permissions_test.dart（+5 用例）、
  sync_export_service_test.dart（+4 导出冒烟用例），全量通过（81 用例）。
- 文档：config/CLAUDE.md、config/README.md、docs/plugin-config.md（§十一 版本历史）。

### 遗留跨域落地点（依赖本契约）
| 落地点 | 任务 | OWNER | 依赖 |
|---|---|---|---|
| 勾选 UI（renderer 接入导出入口） | t-C2 余项 | core-config + renderer | §十二 API |
| ✅ 导入端（插件 .plugin 信封复用 / 数据源回放 / fail-closed / 冲突策略 / 路径沙箱） | t-C3（2026-08-25） | core-module + core-data | §二/§三/§六；落地见 §十三 |
| ~~记忆直接拼接 + 会话合并（包含则删小/分化都保留）~~ | ✅ t-C4（2026-08-25） | core-agent | §七/§八（`session_merge.dart` / `memory/memory_merge.dart`，16 合并用例通过） |
| ~~会话 parent_id/fork_turn 模型落地~~ | ✅ t-C4（2026-08-25） | core-agent | §七.1（`Session.parentId/forkTurn` + `forkSessionProvider`） |
| 路径重映射 / env.json 敏感项 UI | t-C2 余项 | core-config | §六 |

## 十一、导出端实现（t15，已落地）

> 契约落地：`lib/core/config/sync_export_service.dart`（纯 Dart，不引用 Flutter Widget）。

### 11.1 公开 API

```dart
enum SyncResourceType { config, sessions, memories, plugins, data, themes }

class SyncSelection {
  final Set<SyncResourceType> resources;   // 资源类型勾选
  final Set<String> pluginGroups;          // 插件分组勾选（空 = 全部）
  final bool includeSecure;                // 是否导出 isSecure 明文
  final String merge;                      // "merge" / "overwrite"（写入 manifest.options.merge）
}

class SyncExportResult {
  final bool success;
  final String? outputPath;
  final int fileCount;                     // 不含 manifest.json
  final Map<String, Object?> manifest;     // 已写入包的 manifest（回显）
  final String? error;
}

class SyncExportService {
  SyncExportService({
    required String greenixRoot,           // 运行期来自 greenix_path
    required String pluginsRoot,           // 运行期来自 resolvePluginsRoot()
    String? sessionsDir, String? memoriesDir, // 缺省 $greenixRoot/{sessions,memories}
    Map<String, String> appPrefsCandidates = const {}, // appPrefs 白名单候选
    String? appVersion,
  });
  Future<SyncExportResult> export({
    required SharedPreferences prefs,
    required String outputPath,            // 目标 .egsync.zip 路径
    required SyncSelection selection,
    ConfigHttpServer? configServer,        // 提供 dynamicSettingKeys 枚举
    Map<String, dynamic>? aiMemory,        // 随 config 导出（Agent 提供）
  });
}
```

### 11.2 打包行为（与 §二/§三/§五 逐条对应）

| 资源 | 数据源 | 包内路径 |
|---|---|---|
| config | `exportConfig` v2（dynamicKeys=configServer 枚举、includePermissions、appPrefs 候选、includeSecure） | `config/config.evgconfig` |
| sessions | `$greenixRoot/sessions/**` 原始拷贝（隐藏项跳过） | `sessions/…` |
| memories | `$greenixRoot/memories/**` 原始拷贝 | `memories/…` |
| plugins | `$pluginsRoot/<id>/**`（能力标记过滤 + 排除清单） | `plugins/<id>/…` |
| data | `$pluginsRoot/<id>/{data,config}/` | `data/<id>/{data,config}/…` |
| themes | `$pluginsRoot/<id>/theme/theme.json` | `themes/<id>/theme/theme.json` |

- **插件过滤**：`_listPluginIds()` 仅收录有能力标记（根 manifest.json 或
  module/agent/data/skill/config/theme 子目录）的目录；无标记草稿整体跳过。
- **排除清单**（t7 探索）：`.manifest`/`.signature`/`.released_manifest.json`/
  `.config_backup`（导入端重新生成）、`__pycache__`/`build`/`dist`/`node_modules`/
  `.dart_tool`/`*.spec`、`.git`、`drafts`/`backup` 嵌套草稿。
- **勾选过滤（双维）**：资源类型缺省不出现对应目录；`pluginGroups` 非空时——
  config 的 `settings` 按来源插件 id（`getSettingSources()`）、`permissions` 按
  pluginId 裁剪（dynamicSettings/appPrefs/sources 属运行期/应用级，保持原样）；
  插件/数据源/主题按插件 id 裁剪。
- **跨平台**：包内全相对路径（正斜杠），不序列化绝对路径；`platform` 写入
  manifest（`Platform.operatingSystem`）。
- **合并预留**：导出只做「按现状打包」；会话合并/记忆拼接（t-C4）结果由调用方
  落盘到 sessionsDir/memoriesDir 后再导出（路径可注入）。

### 11.3 冒烟验证（sync_export_service_test.dart，4 用例通过）
- 全量导出结构 = §二（9 类条目齐全）；排除清单生效（.manifest/__pycache__/build/
  drafts/无标记草稿均不在包内）；全条目相对路径（无盘符/反斜杠）；manifest 字段
  与 config.evgconfig v2 内容正确。
- 双维过滤：仅 config+plugins、分组 cfg-plugin → sessions/memories/其他插件/数据源/
  主题均不出现；`resources: ['config','plugins']`；config 子集仅保留该组设置。
- 空勾选 → 仅 manifest.json；`includeSecure=false` → SEC_KEY 明文不入包，
  `true` → 入包。

## 十二、导入端实现（t-C3，已落地）

> 契约落地：`lib/core/services/sync_import_service.dart`（纯 Dart；barrel 经
> `core/services/services.dart` 导出）；冒烟：`evg-base/test/sync_import_smoke_test.dart`（7 用例通过）。

### 12.1 公开 API

```dart
class SyncImportService {
  SyncImportService({
    ModuleRegistry? registry,        // 插件注册回放（reloadModule）
    ThemeStore? themeStore,          // 主题热注册
    DataOrchestrator? orch,          // 数据源模型 A 热注册
    String? projectRoot,             // 数据源 CLI fetcher --project-root
    String? pluginsRoot,             // 缺省 resolvePluginsRoot()（跨平台）
    String? sessionsRoot, String? memoriesRoot, // 测试可注入
    Future<String?> Function(String configDirPath)? configImporter, // core-config 交接
  });
  Future<Result<SyncImportResult>> importZip(String zipPath,
      {SyncImportPolicy policy = const SyncImportPolicy()});
}

class SyncImportPolicy {
  final bool overwriteNewer = true;         // 新版覆盖（备份旧 config/）
  final bool overwriteSameVersion = false;  // 同版本不同内容 → 冲突清单
  final bool allowDowngrade = false;        // 版本回退 → 冲突清单
  final bool applyConflicts = false;        // true: 按开关自动执行冲突决策
  final bool overwriteThemes = true;        // 主题纯数据默认覆盖
  final bool overwriteRuntimeData = false;  // sessions/memories 已存在默认冲突
}
```

### 12.2 导入行为（与 §二/§三/§六 逐条对应）

| 校验层 | 规则 | 违规后果 |
|---|---|---|
| 包级 | `manifest.json` 存在、`type=="egsync"`、`version∈[1..kEgsyncCurrentVersion]` | **整体拒绝** → `Err` |
| 路径 | 任意 ZIP 条目含绝对路径 / `..` / 反斜杠 / 盘符 / 非法空段 | **整体拒绝**（不静默跳过） |
| 资源声明 | `resources` 声明的目录必须存在于包内 | 该项 error，其余继续 |
| 插件 | `module/manifest.json` 可解析；.plugin 信封 `type=="plugin"` + id/name/version + `files` 逐文件 SHA-256 + `.signature` 常数时间比对（若带） | 该项 error，不落盘 |
| 数据源 | `data/manifest.json` 可解析且 `type=="data-source"` | 该项 error |
| 主题 | `theme/theme.json` 可经 `ThemeDescriptor.fromJson`（8 必填色） | 该项 error |
| 未知资源类型 | 静默跳过（「未知静默忽略」约定） | skipped 项 |

**冲突策略（版本感知）**：同版本同内容（目录指纹 SHA-256）→ no-op；新版 → 覆盖
（先备份旧 `config/` → `.config_backup_<ts>`，解包后恢复，用户 config 保留）；
同版本不同内容 / 版本回退 → `SyncConflict` 清单（`same-version-different` /
`downgrade` / `newer-blocked`），默认**不自动破坏**；`applyConflicts: true` 时按
`overwriteSameVersion` / `allowDowngrade` 开关执行（开关为关 → 该项 skip）。

**注册回放**：
- 插件：落盘 `resolvePluginsRoot()/<id>/` → `ModuleRegistry.reloadModule`（seal 后可用）。
- 数据源：落盘 `resolvePluginsRoot()/<id>/{data,config}/` → 模型 A
  `registerDataSourcesFromManifest`（与 `POST /data/register` 同契约）；模型 B
  （HTTP 长驻 .exe，legacy）→ `DataSourceLoader` 直接回放（`workingDirectory=<target>/data`，
  **best-effort**：回放失败仅降级为 item message，不阻断包——覆盖安卓无法 exec 桌面 PE 的场景）。
- 主题：落盘 `resolvePluginsRoot()/<id>/theme/theme.json` → `ThemeStore.register`。
- sessions/memories：原样落盘到 `.greenix/{sessions,memories}`（合并结果由 t-C4 产出后导入）。
- config：解包到临时目录 → 交 `configImporter`（core-config `importConfigAndSync`）。

## 十三、版本历史

| 版本 | 日期 | 变更 |
|---|---|---|
| v1.3 | 2026-08-25 | 导入端落地（t-C3）：`sync_import_service.dart`（SyncImportService/SyncImportPolicy/SyncImportResult/SyncConflict + 包级与资源级 fail-closed 校验 + 版本感知冲突 + 注册回放含模型 B DataSourceLoader best-effort + 冒烟测试 8 用例）；§十/§十二 更新 |
| v1.2 | 2026-08-25 | 合并语义落地（t-C4）：Session.parentId/forkTurn 模型 + forkSessionProvider 写入 + session_merge（mergeSessions：包含删小/分化都保留/空会话保护/同 id 冲突）+ memory_merge（mergeMemories/mergeMemoriesIntoStore：直接拼接 + 同 id 跳过 + 索引重建）；§七/§十 更新 |
| v1.1 | 2026-08-25 | 导出端落地（t15）：`sync_export_service.dart`（SyncExportService/SyncSelection/SyncExportResult + archive 依赖 + 冒烟测试）；§十/§十一 更新 |
| v1.0 | 2026-08-25 | 契约层初版：.egsync.zip 包结构、manifest.json、config.evgconfig v2（O1 六缺陷修复）、同步选项模型、跨平台路径规则、会话 parent_id/fork_turn 元数据契约；config v2 实现落地 |
