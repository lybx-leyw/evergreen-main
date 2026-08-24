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
    ├── getSetting / setSetting / getAllSettings
    ├── exportConfig / importConfig
    └── ConfigHttpServer（HTTP 端点，见 §六）──► 插件 .exe 进程
            │
            ├── registerSetting / unregisterSetting（动态注册，无需 config.json 声明）
            └── setGreenixConfigPath / syncConfigToGreenix ──► .greenix/config.json

权限: registerPermissions() ──► _permDecls ──► SP (perm. 前缀)
源:   getSources / addSource / removeSource ──► SP (_plugin_sources)
运行期热注册: registerConfigFromManifest(configServer, pluginDir) ──► registerSetting + 默认值
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
├── register_config.dart     # 运行期热注册（registerConfigFromManifest，供设计器/爬虫）
├── exceptions.dart          # 异常类定义
├── AGENT.md                 # OWNER 职责书（core-config）
├── builtins/config.json     # 内置设置项
├── docs/
│   ├── plugin-config.md
│   └── plugin-authoring-guide-config.md
├── example/                 # 可运行示例
├── lib/shared_preferences_stub/  # 内存桩（纯 Dart，无 Flutter 依赖）
└── test/
    ├── settings_test.dart   # 设置声明/读写/导出导入测试
    └── permissions_test.dart # 权限与插件源测试
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
| **动态注册设置** | `ConfigHttpServer.registerSetting(key, label)` 运行期注入，无需 `config.json` 声明；HTTP 写未声明 key 自动注册为 string 类型 |
| **.greenix 同步** | `setGreenixConfigPath()` 后每次配置变更 `syncConfigToGreenix()` 覆写 `.greenix/config.json`（Android/scraper 凭证降级路径）；**非空值保护**：已有非空值不被 SP 空值覆写 |

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
| `settings_test.dart` | SettingDecl 构造、initSettings（扫描/默认值/类型解析）、getSetting/setSetting（读写/校验）、getAllSettings、exportConfig/importConfig、异常 toString |
| `permissions_test.dart` | PermissionDecl 构造、registerPermissions/getPermissions、setPermission/checkPermission、describePermission、PluginSource、getSources/addSource/removeSource、异常 toString |

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
| `setGreenixConfigPath(path)` | 设置 `.greenix/config.json` 写入路径并触发首次全量同步 |
| `syncConfigToGreenix()` | 将静态声明 + 动态注册全部配置覆写为扁平 JSON 字典；⚠️ 已有非空值不被 SP 空值覆写（Android 首启保护凭证） |

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
  ├── dart:convert / dart:io
  └── (无 Flutter 依赖)
```

## 八、已知限制

1. SP stub 无 `getKeys()`，导出依赖 `_decls` 列表
2. 端口由外部写入 `.config_port` 发现
3. `_decls` 模块级可变状态，重复调用 `initSettings()` 会清空重建——**只在 main() 调用一次**
4. 所有值以字符串存于 SP，bool 为 `"true"/"false"` 字符串
5. 动态注册（`registerSetting` / HTTP 写未声明 key）的类型固定为 string，无 bool/option 校验
6. `registerConfigFromManifest` 只注册动态设置表并标记默认值，默认值落 SP 由调用方负责；`register_config.dart` 不在 `config.dart` barrel 导出（消费方需直接 import）

## 九、版本历史

| 日期 | 变更 |
|------|------|
| 2026-08-25 | 文档对齐代码：ConfigHttpServer 端点表修正（对齐源码路由）、补充动态注册（registerSetting/unregisterSetting）、.greenix 同步（setGreenixConfigPath/syncConfigToGreenix）、运行期热注册（registerConfigFromManifest）、目录结构补 register_config.dart/AGENT.md；按文档修订三原则去除硬编码数量与版本号 |
| 2026-08-02 | 初始版本：创建 CLAUDE.md（声明式设置 / 写入校验 / HTTP 端点契约） |
