# Config 模块 — AI 协作指南 (CLAUDE.md)

| 元信息 | 值 |
| --- | --- |
| 状态 | active |
| 版本 | 以根 `README.md` 为准 |
| 日期 | 2026-08-25 |
| 负责人 | core-config |
| 适用 | AI 协作者（config 子包） |

> 面向 AI 协作者：架构概览、设计决策、开发约定、跨模块契约。
>
> **HTML-first 事实**：普通用户不直接编写 `config.json`；HTML 插件通过 `platform.settings.get/set`
> 访问配置。`config.json` 声明式设置保留给内置功能与开发者模式插件。

---

## 一、模块架构

```
config.json (插件声明)
    │  _parseSetting()
    ▼
SettingDecl ──► _decls (内存 Map)
    │
    ▼
initSettings() ──► SharedPreferences (默认值写入，已有 key 不覆盖)
    │
    ├── getSetting / setSetting / getAllSettings / getSettingSources
    ├── exportConfig / importConfig（.evgconfig v2，见 §三「导出/导入 v2」）
    └── ConfigHttpServer（HTTP 端点，见 §六）──► 插件 .exe 进程
            │
            ├── registerSetting / unregisterSetting（动态注册，无需 config.json 声明）
            ├── dynamicSettingKeys（动态项枚举，供导出）
            ├── importConfigAndSync（导入 + 自动 greenix 同步）
            └── setGreenixConfigPath / syncConfigToGreenix ──► .greenix/config.json

权限: registerPermissions() ──► _permDecls ──► SP (perm. 前缀)
      ├── getAllPermissions / importPermissions（.evgconfig v2 权限段）
源:   getSources / addSource / removeSource ──► SP (_plugin_sources)
运行期热注册: registerConfigFromManifest(configServer, pluginDir) ──► registerSetting + 默认值
同步中心契约: docs/superpowers/specs/egsync-sync-center-spec-v1.md
导出端 pack_sync: SyncExportService（sync_export_service.dart）──► .egsync.zip
```

---

## 二、目录结构

```
lib/core/config/
├── config.dart              # Barrel 导出
├── settings.dart            # 设置声明、读写、持久化、导出/导入
├── permissions.dart         # 权限注册、读写、检查
├── sources.dart             # 插件源管理
├── config_http_server.dart  # HTTP API 服务器（端点见 §六）
├── sync_export_service.dart # 同步中心导出端 pack_sync（.egsync.zip，见 §三「导出端 pack_sync」）
├── register_config.dart     # 运行期热注册（registerConfigFromManifest，供设计器/爬虫）
├── exceptions.dart          # 异常类定义
├── AGENT.md                 # OWNER 职责书（core-config）
├── builtins/config.json     # 内置设置项
├── docs/
│   ├── plugin-config.md
│   └── plugin-authoring-guide-config.md
├── example/                 # 可运行示例
├── lib/
│   ├── shared_preferences_stub/  # SP 内存桩（纯 Dart，无 Flutter 依赖）
│   └── archive_stub/             # archive 桩（dependency_overrides 解析真实包，同 core 模式）
└── test/
    ├── settings_test.dart   # 设置声明/读写/导出导入测试
    ├── permissions_test.dart # 权限与插件源测试
    └── sync_export_service_test.dart # 导出端冒烟测试（zip 结构/勾选过滤/isSecure）
```

---

## 三、核心设计决策

| 决策 | 要点 |
|------|------|
| **声明式设置** | `config.json` 声明 → `initSettings()` 自动扫描，无需代码注册 |
| **写入时校验** | `setSetting()` 校验类型：bool_ 仅 `"true"/"false"`，option 必须在列表中，拒绝抛 `ConfigValidationException` |
| **默认值回退** | `getSetting()` 不存在时返回声明默认值（空串兜底），不抛异常 |
| **权限 ≠ 安装** | 拒绝权限不阻塞安装；`checkPermission()` 运行时抛 `PermissionDeniedException` |
| **SP 内存桩** | 纯 Dart 实现，无 Flutter 依赖，支持测试；限制：无 `getKeys()`，导出依赖 `_decls` |
| **导出/导入隔离** | `exportConfig` 包含 AI 记忆，`importConfig` 返回 `aiMemory` 供 Agent 处理；Config 不引入 Agent 依赖 |
| **导出/导入 v2（.evgconfig）** | `exportConfig`/`importConfig` 支持 `version:2`（= v1 + 可选段 `dynamicSettings`/`permissions`/`appPrefs`，向后兼容 v1）；导入端做 version 校验、白名单过滤（settings 仅已声明键 + 类型语义校验 / dynamic 仅调用方白名单 / appPrefs 仅白名单 / permissions 仅已注册插件已声明键 + bool 正确类型）、isSecure 默认跳过、`onChanged` 触发 greenix 同步；`overwrite` 默认 true（v1 语义），合并导入传 false 启用非空值保护。同步中心契约见 `docs/superpowers/specs/egsync-sync-center-spec-v1.md` |
| **动态注册设置** | `ConfigHttpServer.registerSetting(key, label)` 运行期注入，无需 `config.json` 声明；HTTP 写未声明 key 自动注册为 string 类型；`dynamicSettingKeys` 暴露枚举供导出 |
| **.greenix 同步** | `setGreenixConfigPath()` 后每次配置变更 `syncConfigToGreenix()` 覆写 `.greenix/config.json`（Android/scraper 凭证降级路径）；**非空值保护**：已有非空值不被 SP 空值覆写；`importConfigAndSync` 导入后自动同步 |
| **导出端 pack_sync（.egsync）** | `SyncExportService`（`sync_export_service.dart`）按用户勾选把配置/会话/记忆/插件/数据源/主题打包为 `.egsync.zip`；纯 Dart（根路径注入，不引用 Flutter）；双维过滤（资源类型 × 插件分组）；插件排除清单（.manifest/.signature/构建产物/草稿）；包内全相对路径；复用 `exportConfig` v2 + `dynamicSettingKeys`；archive 依赖走 stub + dependency_overrides（同 core 模式）。UI 由调用方（renderer）接入 |

---

## 四、开发约定

### 新增设置项
- **平台级**：编辑 `builtins/config.json` → 运行测试
- **插件级**：在插件 `config/config.json` 声明 → `initSettings()` 自动发现，无需改源码
- **运行期动态注册**：`ConfigHttpServer.registerSetting(key, label)`（或 `unregisterSetting`）——设计器/爬虫等场景生成 `config/config.json` 后，用 `registerConfigFromManifest(configServer, pluginDir)` 热注册；返回 `ConfigRegisterSummary(registered, savedDefaults)`，默认值由调用方写入 SP

### 新增权限
- 插件 `agent/manifest.json` 声明 → Core 调用 `registerPermissions()`
- 也可在 `config.json` 的 `permissions` 字段声明（`initSettings` 自动注册）

### 扩展 HTTP 端点
- 精确匹配路由加入 `_routes`，参数路由（`/:key`）加入 `_paramRoutes`
- 所有响应通过 `_respond()` 统一处理（JSON + CORS）
- 异常在 handler 中捕获并映射到 HTTP 状态码

### 新增异常
- `exceptions.dart` 新增类 → 实现 `Exception`，覆盖 `toString()`
- 在 ConfigHttpServer 对应 handler 中 `on` 捕获并映射状态码

---

## 五、测试策略

| 文件 | 覆盖范围 |
|------|---------|
| `settings_test.dart` | SettingDecl 构造、initSettings（扫描/默认值/类型解析）、getSetting/setSetting（读写/校验）、getAllSettings、getSettingSources、exportConfig/importConfig v2（动态段/权限段/appPrefs/白名单/version 校验/isSecure/非空保护/onChanged/v1 兼容/类型语义校验）、异常 toString |
| `permissions_test.dart` | PermissionDecl 构造、registerPermissions/getPermissions、setPermission/checkPermission、describePermission、getAllPermissions/importPermissions（枚举/bool 类型/白名单/覆盖语义）、PluginSource、getSources/addSource/removeSource、异常 toString |
| `sync_export_service_test.dart` | 导出端冒烟：.egsync.zip 结构（§二）、排除清单、全相对路径、manifest 内容、双维勾选过滤、空勾选、isSecure 明文控制 |

**运行**：
```bash
cd lib/core/config/ && dart pub get && dart test
```

---

## 六、跨模块接口契约

### HTTP 端点

| 方法 | 路径 | 说明 |
|------|------|------|
| GET | `/config/health` | 健康检查 |
| GET | `/config/settings` | 列出全部设置 |
| POST | `/config/settings` | 按 body `{"key","value"}` 写设置（未声明 key 自动动态注册） |
| GET | `/config/settings/:key` | 读单个设置 |
| POST | `/config/settings/:key` | 按路径写设置 body `{"value":"..."}`（未声明 key 自动动态注册） |
| GET | `/config/permissions/:id` | 读插件权限 |
| POST | `/config/permissions/:id` | 设权限 body `{"key":"...","granted":bool}` |
| GET | `/config/sources` | 列出插件源 |
| POST | `/config/sources` | 增删源 `{"action":"add"/"remove","url":"...","name":"..."}` |

所有响应带 `Access-Control-Allow-Origin: *`（JSON + CORS），异常在 handler 内捕获并映射状态码（400/404/409/500）。

### ConfigHttpServer 附加能力

| 成员 | 说明 |
|------|------|
| `registerSetting(key, label)` / `unregisterSetting(key)` | 动态注册/注销设置项（无需 `config.json` 声明；HTTP 读写后出现在 `GET /config/settings` 列表，类型固定 string） |
| `dynamicSettingKeys` | 动态注册设置项的 key 枚举（供 `.evgconfig` v2 导出：`exportConfig(prefs, dynamicKeys: configServer.dynamicSettingKeys)`） |
| `setGreenixConfigPath(path)` | 设置 `.greenix/config.json` 写入路径并触发首次全量同步 |
| `syncConfigToGreenix()` | 将静态声明 + 动态注册全部配置覆写为扁平 JSON 字典；⚠️ 已有非空值不被 SP 空值覆写（Android 首启保护凭证） |
| `importConfigAndSync(config, {allowedDynamicKeys, allowedAppPrefs, overwrite, allowSecure})` | 导入 `.evgconfig` 并在发生实际写入后自动 `syncConfigToGreenix()`（= `importConfig(..., onChanged: syncConfigToGreenix)`） |

### 端口发现
ConfigHttpServer 绑定 `127.0.0.1`（loopbackIPv4），端口由外部写入 `.config_port`（与 AgentHttpServer 模式一致）。

### 与 Agent 交互
- `exportConfig(prefs, aiMemory: ...)` 将 AI 记忆序列化到导出数据
- `importConfig(prefs, config)` 返回 `aiMemory` 供 Agent 自行导入
- Config **不依赖** Agent 或 MemoryStore

### 与 Module 交互
- Config 不修改 `module_descriptor.dart`
- 插件安装时 Core 调用 `registerPermissions()`
- `initSettings()` 自动从 `config.json` 的 `permissions` 字段注册

### Key 命名约定
- 全局唯一，建议加插件前缀：`MY_PLUGIN_API_KEY`
- 内置设置大写蛇形：`DEEPSEEK_API_KEY`

---

## 七、依赖

```
config (纯 Dart)
  ├── shared_preferences (stub, 本地路径依赖)
  ├── archive (stub, 本地路径依赖；dependency_overrides 解析真实包)   ← sync_export_service
  ├── path ^1.8.0                                                     ← sync_export_service
  ├── dart:convert / dart:io
  └── (无 Flutter 依赖)
```

## 八、已知限制

1. SP stub 无 `getKeys()`，导出依赖 `_decls` 列表；动态注册项/未声明应用偏好需调用方显式传入（`dynamicKeys` / `appPrefs` 白名单）
2. 端口由外部写入 `.config_port` 发现
3. `_decls` 模块级可变状态，重复调用 `initSettings()` 会清空重建——**只在 main() 调用一次**
4. 所有值以字符串存于 SP，bool 为 `"true"/"false"` 字符串
5. 动态注册（`registerSetting` / HTTP 写未声明 key）的类型固定为 string，无 bool/option 校验
6. `registerConfigFromManifest` 只注册动态设置表并标记默认值，默认值落 SP 由调用方负责；`register_config.dart` 不在 `config.dart` barrel 导出（消费方需直接 import）
7. `.evgconfig` v2 导出默认跳过 isSecure 明文（`includeSecure: true` 才包含）；跨平台导入时 `path` 类型设置（机器绝对路径）需调用方跳过或重映射（同步中心约定见 .egsync 规格 §六）
8. `sync_export_service.dart` 不在 `config.dart` barrel 导出（依赖 archive/path，消费方需直接 import，同 register_config 模式）
9. `SyncExportService` 依赖注入根路径（greenixRoot/pluginsRoot）——调用方（renderer）需从 `greenix_path.dart`/`resolvePluginsRoot()` 取值后传入，服务本身保持纯 Dart
10. 会话合并/记忆拼接（t-C4）不在导出端：导出按现状打包；如需导出合并后数据，调用方先落盘再导出（路径可注入）
11. 勾选 UI（renderer 接入）不在本模块——导出入口 API 即 `SyncExportService.export`

## 九、版本历史

| 日期 | 变更 |
|------|------|
| 2026-08-25 | **导出端 pack_sync 实现（t15）**：新增 `sync_export_service.dart`（SyncExportService/SyncSelection/SyncExportResult，.egsync.zip 打包：config v2 + sessions/memories/plugins/data/themes 按勾选收集 + 排除清单 + 全相对路径 + manifest）；config 新增 archive/path 依赖（stub + dependency_overrides，同 core 模式）；测试 +4 冒烟用例（sync_export_service_test.dart），全量 81 用例通过；规格文档更新 v1.1 |
| 2026-08-25 | **config v2（.evgconfig）实现**：exportConfig/importConfig 升级 v2（dynamicSettings/permissions/appPrefs 可选段 + version 校验 + 白名单过滤 + isSecure 跳过 + onChanged 触发 greenix 同步 + overwrite 覆盖语义），修复 O1 ①权限类型②动态项枚举③extra 无过滤④无 version 校验⑤导入不同步⑥isSecure 明文；新增 getSettingSources / getAllPermissions / importPermissions / ConfigHttpServer.dynamicSettingKeys / importConfigAndSync；同步中心契约规格 docs/superpowers/specs/egsync-sync-center-spec-v1.md；测试 +20 用例全量通过 |
| 2026-08-25 | 文档对齐代码：ConfigHttpServer 端点表修正（对齐源码路由）、补充动态注册（registerSetting/unregisterSetting）、.greenix 同步（setGreenixConfigPath/syncConfigToGreenix）、运行期热注册（registerConfigFromManifest）、目录结构补 register_config.dart/AGENT.md；按文档修订三原则去除硬编码数量与版本号 |
| 2026-08-02 | 初始版本：创建 CLAUDE.md（声明式设置 / 写入校验 / HTTP 端点契约） |
