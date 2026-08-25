# Config

| 元信息 | 值 |
| --- | --- |
| 状态 | active |
| 版本 | 以根 `README.md` 为准 |
| 日期 | 2026-08-25 |
| 负责人 | core-config |
| 适用 | config 子包 |

> 完整用法 → [`example/example.dart`](example/example.dart) | AI 协作指南 → [`CLAUDE.md`](CLAUDE.md)
>
> **HTML-first 事实**：用户 HTML 插件用 `platform.settings.get/set` 读写设置，无需手写 config.json；
> 平台级/开发者模式插件仍可用 `config/config.json` 声明设置与权限。

---

## 一、平台开发者 API

### 设置

| 函数 | 说明 |
|------|------|
| `initSettings(prefs, {pluginDirs})` | 扫描插件目录 `config.json`，默认值写入 SP |
| `getSetting(prefs, key)` | 读值，回退声明默认值 |
| `setSetting(prefs, key, value)` | 写值 + 类型校验 |
| `getAllSettings(prefs)` | 返回 `List<({SettingDecl decl, String value})>` |
| `getSettingSources()` | 返回 `Map<String, String>`（key → 来源插件 id，按插件分组用） |
| `exportConfig(prefs, {aiMemory, extraKeys, dynamicKeys, includePermissions, appPrefs, includeSecure})` | 导出 `.evgconfig` **v2**（= v1 + 可选段 `dynamicSettings`/`permissions`/`appPrefs`；isSecure 默认跳过） |
| `importConfig(prefs, config, {allowedDynamicKeys, allowedAppPrefs, overwrite, allowSecure, onChanged})` → `Map?` | 导入 `.evgconfig` v2（兼容 v1；version 校验 + 白名单过滤 + 非空保护 + 导入后回调），返回 aiMemory |

> `.evgconfig` v2 契约与同步中心（.egsync）规格见 `docs/superpowers/specs/egsync-sync-center-spec-v1.md`。

### 凭据存储（CredentialStore，T2 主题 A 登录不挤占）

| 成员 | 说明 |
|------|------|
| `CredentialStore.get/set/delete/has` | 平台级凭据统一读写（SP 主存储 + `.greenix/config.json` / `env.json` 镜像），`set({isSecure})` 敏感标记 |
| `CredentialStore` 写路径互斥锁 | 并发写/读改写串行（对齐 Cache 锁模式） |
| `writeCredentialDirect(key, value, {isSecure})` | **不依赖 ConfigHttpServer/`.config_port` 的直写**（save_credential 已切此路径，T9）；写 SP + 镜像 config.json |
| 消费方 | `SessionProvider`（`core/data/session_provider.dart`）、scraper/html-creator `SaveCredentialTool` |

### 权限

| 函数 | 说明 |
|------|------|
| `registerPermissions(pluginId, perms)` | 注册权限声明 |
| `getPermissions(prefs, pluginId)` | 返回 `Map<String, bool>` |
| `setPermission(prefs, pluginId, permKey, granted)` | 设置单个权限，即时生效 |
| `checkPermission(prefs, pluginId, permKey)` | 检查权限，拒绝时抛 `PermissionDeniedException` |
| `describePermission(perm)` | 生成 `【标签】描述` 格式文本 |
| `getPermissionDecls(pluginId)` | 返回 `List<PermissionDecl>?` |
| `getAllPermissions(prefs)` | 枚举全部已注册插件权限状态（`.evgconfig` v2 导出用，bool 类型） |
| `importPermissions(prefs, permissions, {overwrite})` | 批量导入权限（白名单 + bool 类型 + 覆盖语义），返回写入条数 |

### 源管理

| 函数 | 说明 |
|------|------|
| `getSources(prefs)` | 返回 `List<PluginSource>`（默认源 + 自定义源） |
| `addSource(prefs, url, name)` | 添加自定义源，重复 URL 抛 `SourceDuplicateException` |
| `removeSource(prefs, url)` | 删除自定义源（默认源不可删） |

### ConfigHttpServer 附加能力

| 成员 | 说明 |
|------|------|
| `registerSetting(key, label)` / `unregisterSetting(key)` | 动态注册/注销设置项（无需 config.json 声明，HTTP 可读写） |
| `dynamicSettingKeys` | 动态注册设置项的 key 枚举（供 `.evgconfig` v2 导出） |
| `setGreenixConfigPath(path)` | 设置 `.greenix/config.json` 写入路径并触发首次全量同步 |
| `syncConfigToGreenix()` | 全部配置（静态 + 动态）覆写为扁平 JSON；非空值保护，Android 首启不覆写凭证 |
| `importConfigAndSync(config, {...})` | 导入 `.evgconfig` 并在写入后自动 `syncConfigToGreenix()` |

### 运行期热注册（设计器/爬虫）

| 函数 | 说明 |
|------|------|
| `registerConfigFromManifest({configServer, pluginDir})` | 读取插件 `config/config.json` → `registerSetting` 热注册；返回 `ConfigRegisterSummary(registered, savedDefaults)`，默认值由调用方写入 SP |

### 同步中心导出端（pack_sync，`.egsync.zip`）

> 契约：`docs/superpowers/specs/egsync-sync-center-spec-v1.md`（§二/§三/§五/§十一）。
> 实现：`sync_export_service.dart`（纯 Dart，直接 import，不在 barrel）。

| 成员 | 说明 |
|------|------|
| `SyncResourceType` | 资源类型枚举：`config` / `sessions` / `memories` / `plugins` / `data` / `themes` |
| `SyncSelection(resources, {pluginGroups, includeSecure, merge})` | 用户勾选（资源类型 × 插件分组双维；`pluginGroups` 空 = 全部） |
| `SyncExportService({greenixRoot, pluginsRoot, sessionsDir?, memoriesDir?, appPrefsCandidates?, appVersion?})` | 导出服务（根路径注入，运行期来自 greenix_path / resolvePluginsRoot） |
| `SyncExportService.export({prefs, outputPath, selection, configServer?, aiMemory?})` → `SyncExportResult` | 打包 `.egsync.zip`；返回 `{success, outputPath, fileCount, manifest, error}` |

行为：配置走 `exportConfig` v2（复用 t11）；会话/记忆原始拷贝；插件按能力标记 + 排除清单
（.manifest/.signature/构建产物/草稿）拷贝；数据源 `data/<id>/{data,config}/`；主题
`themes/<id>/theme/theme.json`；包内全相对路径；`manifest.json` 含 type/version/
exportedAt/platform/resources/options.selections。

### HTTP 端点（ConfigHttpServer）

| 方法 | 路径 | 说明 |
|------|------|------|
| GET | `/config/health` | 健康检查 |
| GET | `/config/settings` | 列出全部设置项 |
| POST | `/config/settings` | 按 body `{"key","value"}` 写设置（动态注册） |
| GET | `/config/settings/:key` | 读单个设置 |
| POST | `/config/settings/:key` | 写设置 `{"value":"..."}` |
| GET | `/config/permissions/:id` | 读插件权限 |
| POST | `/config/permissions/:id` | 设权限 `{"key":"...","granted":true}` |
| GET | `/config/sources` | 列出插件源 |
| POST | `/config/sources` | 增删源 `{"action":"add"\|"remove","url":"...","name":"..."}` |

> 注：`POST /config/settings` 与 `POST /config/settings/:key` 写入未在 config.json 声明的 key 时，会自动动态注册（类型固定 string，响应 `registered: true`）。所有响应带 CORS 头 `Access-Control-Allow-Origin: *`。

### 类型

| 类型 | 字段 |
|------|------|
| `SettingDecl` | `key`, `label`, `type`, `defaultValue`, `isSecure`, `options`, `hint`, `suggestions` |
| `SettingType` | `string` / `bool_` / `path` / `option` |
| `SettingOption` | `value`, `label` |
| `PermissionDecl` | `key`, `label`, `description`, `defaultGranted` |
| `PluginSource` | `url`, `name`, `isDefault` |

### 异常

| 异常 | 触发场景 |
|------|---------|
| `ConfigMissingException` | 请求了未声明的配置项 |
| `ConfigValidationException` | bool_ 非 "true"/"false"、option 值不在列表中、删除默认源 |
| `PermissionDeniedException` | `checkPermission()` 时权限被拒绝 |
| `SourceDuplicateException` | 重复添加同名源 URL |

---

## 二、插件开发者

在插件目录放置 `config/config.json`（推荐）或 `config.json`。`initSettings()` 自动扫描并集成，无需代码注册。

### 字段速查

**顶层：**

| 字段 | 必填 | 说明 |
|------|------|------|
| `id` | 是 | 插件唯一标识 |
| `name` | 是 | UI 分组标题 |
| `settings` | 否 | 设置项数组 |
| `permissions` | 否 | 权限声明数组 |

**settings 条目：**

| 字段 | 必填 | 类型 | 说明 |
|------|------|------|------|
| `key` | 是 | 全部 | 存储键，全局唯一 |
| `label` | 是 | 全部 | UI 标签 |
| `type` | 否 | 全部 | `string`(默认) / `bool` / `path` / `option` |
| `default` | 否 | 全部 | 默认值字符串 |
| `isSecure` | 否 | string | 敏感标记，仅 string 有效 |
| `hint` | 否 | string/path/option | 帮助文本 |
| `options` | 是* | option | `[{"value":"...","label":"..."}]` |
| `suggestions` | 否 | string/path | 快捷填充建议（仅 UI 提示，**不参与写入校验**，可自由填写任意值）；元素支持 `{"value","label"}` 或纯字符串两种写法 |

**permissions 条目：**

| 字段 | 必填 | 说明 |
|------|------|------|
| `key` | 是 | 权限标识，建议 `UPPER_SNAKE_CASE` |
| `label` | 是 | UI 标签 |
| `description` | 是 | 用途与风险说明 |
| `default` | 否 | 默认授权状态，默认 `true` |

> 完整指南 → [`docs/plugin-authoring-guide-config.md`](docs/plugin-authoring-guide-config.md)

---

## 三、质量自评

| 维度 | 状态 |
|------|------|
| 设置注册/读写/持久化 + 默认值回退 + 类型校验 | ✅ |
| 权限注册/读写/即时生效/拒绝不阻塞安装 | ✅ |
| 源管理（默认源 + 自定义源增删） | ✅ |
| ConfigHttpServer 端点（含动态注册，见上表） | ✅ |
| 配置导出/导入 v2（.evgconfig：动态段/权限段/appPrefs + version 校验 + 白名单 + isSecure + 非空保护 + 导入后同步） | ✅ |
| 权限自动提取（config.json `permissions` 字段） | ✅ |
| 权限枚举/批量导入（getAllPermissions / importPermissions） | ✅ |
| 设置项来源分组（getSettingSources，按插件筛选） | ✅ |
| `.greenix/config.json` 同步（非空值保护） | ✅ |
| 运行期热注册（registerConfigFromManifest） | ✅ |
| 同步中心契约（.egsync 规格 v1，config 侧已落地） | ✅ |
| 同步中心导出端（SyncExportService → .egsync.zip，双维勾选过滤 + 排除清单 + 全相对路径） | ✅ |
| 测试：`dart test` 全量通过（见 `test/`，含 v2 与导出冒烟用例） | ✅ |
| 静态分析：`dart analyze` 零错误零警告 | ✅ |
| 示例：`dart run example/example.dart` 正常运行 | ✅ |

## 四、已知限制

- SharedPreferences stub 不支持 `getKeys()`，导出依赖 `_decls` 列表 + 调用方显式传入（`dynamicKeys` / `appPrefs` 白名单）；实际运行时完整 SP 支持。
- ConfigHttpServer 端口由外部写入 `.config_port` 文件发现。
- `_decls` 模块级可变状态，重复调用 `initSettings()` 会清空重建。**只在 main() 调用一次**。
- 所有值以字符串存于 SP，bool 为 `"true"/"false"` 字符串。
- `.evgconfig` v2 导出默认跳过 isSecure 明文；跨平台导入时 `path` 类型设置（机器绝对路径）需调用方跳过或重映射（见 .egsync 规格 §六）。
- `sync_export_service.dart` 不在 barrel（依赖 archive/path，直接 import，同 register_config 模式）；`SyncExportService` 依赖注入 greenixRoot/pluginsRoot，调用方从 greenix_path / resolvePluginsRoot 取值。
- 勾选 UI（renderer 接入）与导入端插件回放 / 会话合并算法分别属 t-C2 余项 / t-C3 / t-C4（见总规划 §5）。
