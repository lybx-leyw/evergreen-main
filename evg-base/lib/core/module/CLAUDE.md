# Module — AI 协作指南

| 元信息 | 值 |
| --- | --- |
| 状态 | active |
| 版本 | 以根 `README.md` 为准 |
| 日期 | 2026-08-25 |
| 负责人 | core-module |
| 适用 | AI 协作者（module 子包） |

> 2026-08-25 | `lib/core/module/` | 负责人：core-module
>
> **HTML-first 事实**：用户侧插件创作主路径是 `html-creator` 导出的 HTML 插件
> （`plugins/<id>/module/index.html + manifest.json`，`"template":"html"`）。
> 本模块继续服务所有声明式模块（含 HTML 模板路由、v4 组件、内置模块、开发者模式），
> 并承载插件市场的契约层（六格 lattice / 权限 / sidecar / 市场发现与审核）。

## 架构管线

```
manifest.json → ModuleDescriptor.fromJson()
    ├── lattice 解析/推断（M0 六格契约，fail-closed）→ runtime 描述符（sidecar 格）
    └── ResolvedPlugin（单一事实源：lattice/runtime/capabilities 恒可消费）
        → Registry.register() → seal()
        → ModuleLoader（.exe 走 ProcessManager；sidecar 格走 SidecarController）
        → PermissionResolver → BridgeInterceptor（platform.* 桥裁决 + 审计）
        → ModuleHttpServer (REST API)
        → ProcessManager (4级进程) → ExposeStateWriter (状态快照)
```

**生命周期**: 声明(JSON) → 解析(Dart, 含 lattice/runtime) → ResolvedPlugin → 注册 → 锁定(seal)
→ 按 `template` 路由（html/v4/zju/scraper/...）→ 加载/渲染 → 权限裁决 → 进程管理 → 状态暴露

> 对 HTML 插件：`ModuleDescriptor` 仅承载元数据与 `template:"html"`，页面正文由 `index.html` 提供；
> `html_modle` 通过 WebView + JS Bridge 渲染，不经过 v4 的组件树配置。桥调用过 `PermissionResolver`。

## 文件地图

```
lib/core/module/
├── module_descriptor.dart      ← 核心: ModuleDescriptor + 子描述符树
├── module_registry.dart        ← 注册/查询/搜索/路由/导航 + ResolvedPlugin 索引
├── module_loader.dart          ← 扫描 + 加载/启动后端；sidecar 格走控制器
├── module_http_server.dart     ← REST API（端点见「跨模块契约」）
├── lattice.dart                ← M0 六格契约: 枚举 + 推断 (§2.4 优先级表)
├── runtime.dart                ← sidecar 运行时描述符 + 能力沙箱 (deny-all)
├── resolved_plugin.dart        ← 插件运行时单一事实源（registry/loader/权限统一消费）
├── permission.dart             ← 权限执行器/票据/握手/审计/桥拦截器 (M2)
├── bridge_shim.dart            ← 多版本 bridge shim 路由 (M2-6)
├── capability_bridge.dart      ← 能力维度风险定级 safe/warning/danger (M5-3/4)
├── content_address.dart        ← 内容寻址: manifest+资源 SHA-256 稳定 ID (M3-1)
├── github_source.dart          ← GitHub 源解析 + 仓库格分类 (M4-1/2)
├── scaffold_plugin.dart        ← 上架脚手架: 分类→manifest 生成 (M4-3)
├── marketplace_source.dart     ← 市场源解析 (github/localDir, fail-closed) (M5-1)
├── marketplace_scanner.dart    ← 市场源扫描 → 插件发现列表 (M5-5)
├── plugin_registry.dart        ← 远程 registry (plugins.json) 解析 (M6-0)
├── plugin_review.dart          ← 审核队列/评分聚合/评价存储 (M5-2)
├── sidecar_status_client.dart  ← /module/sidecars 状态客户端
├── sidecar/                    ← sidecar 一等公民运行时
│   ├── sidecar_controller.dart ←   抽象接口 + 端口分配/优雅停机纯逻辑 (M1·3.1)
│   ├── sidecar_factory.dart    ←   按 RuntimeKind 选控制器 (M1-6)
│   ├── node_sidecar.dart       ←   Node 实现 (M1-3)
│   ├── python_sidecar.dart     ←   Python 实现 (M1-4)
│   ├── deno_sidecar.dart       ←   Deno 实现（--allow-* 按能力收窄） (M1-5)
│   ├── process_sidecar_runtime.dart ← dart:io 进程启动实现 (M1-7)
│   ├── command.dart            ←   命令拼装 + 能力环境注入 (M1-3/4/5, M1-9)
│   └── health.dart             ←   健康检查退避纯逻辑 (M1-2)
├── capability.dart             ← 六维能力枚举 + 自动发现 + latticeToCapability 桥
├── module_lifecycle.dart       ← 安装/卸载/禁用/升级
├── process_manager.dart        ← 四级进程作用域
├── page_event_bus.dart         ← 页级跨栏事件
├── expose_state_writer.dart    ← 状态快照写入
├── plugin_manifest.dart        ← 搜索轻量模型
├── plugin_detail.dart          ← 详情信息模型
├── sidebar_section.dart        ← 侧边栏分类
├── modules.dart                ← barrel 导出
├── pubspec.yaml                ← 依赖 (flutter stub)
├── builtins/                   ← 内置模块（agent/）
├── docs/                       ← 教程（01-12）+ 插件指南（plugin-module.md 唯一权威参考）
├── example/                    ← 完整示例 + 模板插件（example/plugins/my_module/）
└── test/                       ← 测试（全量通过）
```

---

## 核心设计决策

### 1. register → seal 不可变
`seal()` 后所有写入抛 `StateError`，消除运行时路由竞态，依赖校验在 seal 时集中执行。

**红线**: seal 后 `register()`/`setCapabilities()` 抛 `StateError`；seal 前只读方法抛 `StateError`。
例外：`reloadModule()` / `unregister()` 专为插件设计器「安装/热重载」在 seal 后仍可用。

### 2. const ModuleDescriptor
`ModuleDescriptor` 及所有子描述符为 `const` 构造 + `final` 字段。`==`/`hashCode` 基于 `id`。配合 `seal()` 实现不可变模块表。

### 3. 未知字段静默忽略
`fromJson()` 对未定义字段不抛异常——保证向下兼容。必填字段缺失仍抛 `FormatException`。
**例外（fail-closed）**：`lattice` / `runtime` / `capabilities` 属安全相关字段，非法值一律抛 `FormatException`，绝不静默放宽或降级。

### 4. 六维插件模型
`agent`/`module`/`theme`/`data`/`config`/`process`——通过目录结构自动发现，一个插件可同时提供多种能力。

### 5. 四级 .exe 各自独立
模块级/页面级/栏位级/动作级四个 `process` 字段互不覆盖，`ProcessManager` 统一管理。动作级为一次性执行（完成即退出）。
V2 起 `process` 为**数组**（`ProcessDescriptor[]`），单对象形式仅作 V1 兼容自动包装。

### 6. actions 智能检测
JSON 数组 → `ActionButtonDescriptor[]`，JSON 对象 → 旧版 `ActionDescriptor`。Dart 层分两个字段存储，兼容新旧格式。

### 7. snake_case 兼容
仅 `ChatOptions.multiSession` 从 JSON key `multi_session` 读取。其余字段 camelCase 两层一致。
例外：`modleRoute` 的 JSON key 是 `modle_route`（历史命名保留）。

### 8. M0 六格契约（lattice）
插件运行时信任等级：`static-web` → `web-bridged` → `data-source` → `sidecar` → `agent-tool` → `external-app`（最安全到最外置）。
- 显式声明：大小写不敏感，`-`/`_` 等价；非法值抛 `FormatException`（fail-closed）。
- 缺省推断（§2.4 优先级）：`runtime` → sidecar；`template:html` → web-bridged；`template:scraper` 或 `dataSource(s)` → data-source；`activateSkills` 非空 → agent-tool；其它 → static-web。
- 显式声明才写回 `toJson`（`latticeExplicit`），保证旧 manifest 字节兼容。
- 设计上游：`evg-base/docs/m0-lattice-contract-design.md`。

### 9. ResolvedPlugin 单一事实源
`ModuleDescriptor` 解析后包装为不可变 `ResolvedPlugin`（lattice/runtime/capabilities 恒可消费）。
registry（`registerResolved`）/ loader（`ModuleLoader.fromResolved`）/ 权限执行器（`PermissionResolver.fromResolved`）统一消费它，杜绝各方各读各的 JSON。

### 10. sidecar 一等公民（M1）
`lattice: sidecar` + `runtime` 描述符声明语言运行时进程（node/python/deno），
`SidecarController` 统一生命周期（install → 校验 → 起进程 → 健康检查 → 注册端口 → 优雅停 + 强杀兜底）。
`RuntimeCapabilities` deny-all 默认：`fs.scope`（none/plugin-dir/app-data）+ `net.allow` + `spawn` 白名单，能力只窄不宽。

### 11. 权限执行器（M2）
`PermissionResolver` 由 ResolvedPlugin 推导允许维度 → `BridgeInterceptor` 在 `platform.*` 桥调用进入 core 前裁决 → `PermissionTicket`（granted/denied + 审计）。`BridgeHandshake`（`platform.hello` 版本协商）与 `BridgeShimRouter`（多版本 shim 路由）保障新旧插件共存。

### 12. 市场生态（M4–M6）
- 发现：`GithubSource` 解析 + `RepoClassification` 分类 → `MarketplaceSource`（github/localDir）→ `MarketplaceScanner` 扫描（`scanPluginDir` / `scanSources`）。
- 分发：`PluginRegistry` 解析远程 `plugins.json`（RegistryPlugin + PluginManifest 内嵌/local/github + installStrategy source/release）。
- 信任：`ReviewQueue`（pending/approved/rejected，fail-closed 默认拒绝曝光）+ `ReviewStore`（用户评价聚合）。
- 全部为纯 Dart 可单测层；网络克隆/抓取在主包 `core/services/` 完成，经 `GithubCloner` 注入。

## 开发流程

### 新增 UI 范式
1. 在 `ModuleDescriptor` / `PageDescriptor` / `ComponentDescriptor` 中确认承载位置（V2 不使用顶层 `ui` 字段；范式由 `template` + `pages[].layout.slots[].component.type` 声明）
2. 创建对应 Options 类（const 构造 + `fromJson`/`toJson`）
3. 新增字段 → `fromJson` 解析 → `toJson` 序列化
4. `modules.dart` 确认导出 → 更新 `README.md` 字段表 → `descriptor_test.dart` 新增测试

### 新增 ModuleDescriptor 字段
1. const 构造新增 `final` 字段（带默认值）
2. `fromJson` 用 `?? defaultValue` 模式保证向下兼容
3. `toJson` 默认值时省略 → 更新 README → 新增往返测试

### 扩展 HTTP 端点
在 `_handle` 的 `if/else` 链新增分支 → 实现私有方法 → 更新顶部文档 → 新增测试 → 更新 README

### 新增市场/契约纯逻辑文件
1. 纯函数 + fail-closed（非法输入抛 `FormatException`，不静默变空列表）
2. 在 `modules.dart` barrel 导出
3. `test/` 下建对应测试文件（fake clone / 内存收集，不触网络与真实子进程）
4. 更新 `CLAUDE.md` 文件地图 + `README.md` 模型表

### Stub 隔离
`pubspec.yaml` 指向 `lib/flutter_stub/`（提供 `IconData` 等最小类型）。示例渲染器 `lib/renderer.dart` 是 ASCII 渲染器，不依赖 Flutter Widget 树。

---

## 测试覆盖

| 测试文件 | 覆盖 |
|---------|------|
| `descriptor_test.dart` | fromJson/toJson 往返、V2 pages/layout/slots/component、子描述符边界、const 构造、activateSkills/version |
| `registry_test.dart` | register/seal 不可变、findById/findByRoute、search(6维度)、listByCapability、导航、依赖校验 |
| `http_server_test.dart` | 全部端点(health/modules/:id/search/nav/routes/sidecars)、404/405、重复 start/stop |
| `lattice_roundtrip_test.dart` | G1 解析与推断、G2 runtime、G3 capabilities、G4 序列化幂等、G5 与 v5P 字段共存 |
| `resolved_plugin_test.dart` | ResolvedPlugin.fromDescriptor、isSidecar/isStatic/isExternalApp |
| `registry_lattice_test.dart` | registry+ResolvedPlugin (M0-13)、latticeToCapability 桥 (M0-15)、findByLattice |
| `permission_test.dart` | PermissionResolver (M2-1)、Ticket (M2-2)、Handshake (M2-5)、Audit (M2-4)、Interceptor (M2-3) |
| `bridge_shim_test.dart` | BridgeShimRouter 版本选择/回退 |
| `bridge_integration_test.dart` | BridgeInterceptor 端到端（deny-all → permission_denied） |
| `capability_bridge_test.dart` | riskOf / maxRisk / riskToPermissionLevel |
| `content_address_test.dart` | computeContentAddress 稳定 ID/篡改检测 |
| `github_source_test.dart` | parseGithubSource (M4-1)、classifyRepo (M4-2)、generateManifest (M4-3) |
| `marketplace_source_test.dart` | MarketplaceSource.fromJson、parseMarketplaceSources、去重、enabledSources |
| `marketplace_scanner_test.dart` | localDir 扫描、github 源（fake clone） |
| `plugin_registry_test.dart` | parsePluginRegistry (M6-0)、PluginManifest、installStrategy、manifestRelativePath |
| `plugin_review_test.dart` | PluginReview、aggregateReviews、ReviewQueue、fromJsonSource (M5-7)、ReviewStore (M5-12) |
| `sidecar_test.dart` | resolveSidecarPort、gracefulKillTimeoutMs、factory、健康策略、命令拼装、控制器（fake runtime） |
| `sidecar_status_client_test.dart` | parseSidecarsResponse |

---

## 跨模块契约

### ModuleHttpServer — 端点（仅 GET，源码 `module_http_server.dart` 为准）

```
GET /module/health              → 200 {"status":"ok"}
GET /module/modules             → {"modules":[...], "count":N}
GET /module/modules/:id         → ModuleDescriptor JSON | 404
GET /module/search?q=&dim=&cat= → {"results":[...], "count":N}
GET /module/nav                 → {"navGroups":[...]}
GET /module/routes              → {"routes":[...], "count":N}
GET /module/sidecars            → {"sidecars":[...], "count":N}   ← M1-10 sidecar 状态
```

`start()` → `Future<int>`（实际端口），`port:0` 自动分配，写入 `.module_port`。端口 9100（默认，91xx 段统一）。
sidecar 状态由宿主调用 `setSidecarSnapshots()` / `addSidecarSnapshot()` 刷新（server 不直接依赖 loader）。

### lattice / runtime → renderer 契约
`ModuleDescriptor.lattice`（显式或推断）与 `runtime` 是 renderer 判断「插件怎么跑」的依据：
- `static-web` / `web-bridged` → 正常内嵌渲染（后者桥调用过权限裁决）。
- `sidecar` → 启动语言运行时进程，RPC 走 `runtime.protocol`（http/stdio）。
- `external-app` → 深链，不内嵌。
字段增删需通知 renderer OWNER（跨 OWNER 契约变更上报队长）。

### activateSkills → Agent 契约
`activateSkills` 是 `List<String>`（Skill.name）。Module 只声明——Agent 工程师负责 `AgentController.activateSkill` 消费逻辑。**Module 工程师红线**: 不修改 Agent 的 activateSkill 逻辑。

### PageEventBus — 栏间事件

```dart
SlotEvent { event, sourceSlot, data: Map<String,dynamic>, timestamp }
```
每个页面一个 EventBus 实例。页面激活创建 → 切走 dispose。不跨页面、不跨模块、不持久化。manifest 中 `events: {emit: [...], subscribe: [...]}` 声明。

### ProcessManager — 四级作用域

| 作用域 | 来源 | 生命周期 |
|--------|------|---------|
| 模块级 | `ModuleDescriptor.process` | 激活 → 切走 |
| 页面级 | `PageDescriptor.process`（V1 别名 `globalProcess`） | 激活 → 切走 |
| 栏位级 | `SlotDescriptor.process` | 可见 → 隐藏 |
| 动作级 | `ActionButtonDescriptor.process` | 触发 → 完成退出 |

> V2 起 `process` 为数组；sidecar 格（lattice: sidecar）不再走 ProcessManager，由 `SidecarController` 统一管理。

### 依赖注入约定
- `ModuleRegistry` 不持有 HTTP 客户端/文件系统/日志——通过参数注入
- `ModuleLoader` 构造需要 `projectRoot`（传给 .exe 进程）；sidecar 可注入 `SidecarRuntime`（测试替身）
- `ModuleLifecycle` 通过回调 `onStop`/`onRestart` 与外部 ProcessManager 解耦
- `ExposeStateWriter` 通过构造接收 `PageEventBus` 和 `workspaceRoot`
- 市场层 `GithubCloner` 由主包注入（单测用 fake），core 子包不碰 git/网络
