# Module — AI 协作指南

> v1.1 | 2026-07-06 | `lib/core/module/`

## 架构管线

```
manifest.json → ModuleDescriptor.fromJson() → Registry.register() → seal()
    → ModuleLoader (scan + start exe)
    → ModuleHttpServer (REST API)
    → ProcessManager (4级进程) → ExposeStateWriter (状态快照)
```

**生命周期**: 声明(JSON) → 解析(Dart) → 注册 → 锁定(seal) → 加载(exe) → 服务(HTTP) → 进程管理 → 状态暴露

## 文件地图

```
lib/core/module/
├── module_descriptor.dart      ← 核心: ModuleDescriptor + 30+ 子描述符 (2290行)
├── module_registry.dart        ← 核心: 注册/查询/搜索/路由/导航 (325行)
├── module_loader.dart          ← 扫描 + 启动 exe 后端 (227行)
├── module_http_server.dart     ← REST API: 6端点 (216行)
├── module_lifecycle.dart       ← 安装/卸载/禁用/升级 (317行)
├── process_manager.dart        ← 四级进程作用域 (430行)
├── page_event_bus.dart         ← 页级跨栏事件 (129行)
├── expose_state_writer.dart    ← 状态快照写入 (99行)
├── capability.dart             ← 六维能力枚举 + 自动发现 (108行)
├── plugin_manifest.dart        ← 搜索轻量模型 (92行)
├── plugin_detail.dart          ← 详情信息模型 (115行)
├── sidebar_section.dart        ← 侧边栏分类 (31行)
├── modules.dart                ← barrel 导出
├── pubspec.yaml                ← 依赖 (flutter stub)
├── builtins/                   ← 内置模块
├── docs/                       ← 14篇开发者指南
├── example/                    ← 完整示例 + 模板插件
└── test/
    ├── descriptor_test.dart    ← 解析/校验/序列化 (517行, 8组)
    ├── registry_test.dart      ← 注册/seal/查询/搜索/导航 (398行, 8组)
    └── http_server_test.dart   ← 6端点 + 错误处理 (225行, 3组)
```

---



## 核心设计决策

### 1. register → seal 不可变
`seal()` 后所有写入抛 `StateError`，消除运行时路由竞态，依赖校验在 seal 时集中执行。

**红线**: seal 后 `register()`/`setCapabilities()` 抛 `StateError`；seal 前只读方法抛 `StateError`。

### 2. const ModuleDescriptor
`ModuleDescriptor` 及所有子描述符为 `const` 构造 + `final` 字段。`==`/`hashCode` 基于 `id`。配合 `seal()` 实现不可变模块表。

### 3. 未知字段静默忽略
`fromJson()` 对未定义字段不抛异常——保证向下兼容。必填字段缺失仍抛 `FormatException`。

### 4. 六维插件模型
`agent`/`module`/`theme`/`data`/`config`/`process`——通过目录结构自动发现，一个插件可同时提供多种能力。

### 5. 四级 .exe 各自独立
模块级/页面级/栏位级/动作级四个 `process` 字段互不覆盖，`ProcessManager` 统一管理。动作级为一次性执行（完成即退出）。

### 6. actions 智能检测
JSON 数组 → `ActionButtonDescriptor[]`，JSON 对象 → 旧版 `ActionDescriptor`。Dart 层分两个字段存储，兼容新旧格式。

### 7. snake_case 兼容
仅 `ChatOptions.multiSession` 从 JSON key `multi_session` 读取。其余字段 camelCase 两层一致。

## 开发流程

### 新增 UI 范式
1. `ModuleDescriptor` 的 `ui` 文档中增加范式名
2. 创建对应 Options 类（const 构造 + `fromJson`/`toJson`）
3. `ModuleDescriptor` 新增字段 → `fromJson` 解析 → `toJson` 序列化
4. `modules.dart` 确认导出 → 更新 `README.md` 字段表 → `descriptor_test.dart` 新增测试

### 新增 ModuleDescriptor 字段
1. const 构造新增 `final` 字段（带默认值）
2. `fromJson` 用 `?? defaultValue` 模式保证向下兼容
3. `toJson` 默认值时省略 → 更新 README → 新增往返测试

### 扩展 HTTP 端点
在 `_handle` 的 `if/else` 链新增分支 → 实现私有方法 → 更新顶部文档 → 新增测试 → 更新 README

### Stub 隔离
`pubspec.yaml` 指向 `lib/flutter_stub/`（提供 `IconData` 等最小类型）。示例渲染器 `lib/renderer.dart` 是 ASCII 渲染器，不依赖 Flutter Widget 树。

---



## 测试覆盖

| 文件 | 行数 | 覆盖 |
|------|------|------|
| `descriptor_test.dart` | 517 | fromJson/toJson 往返、7种UI范式、子描述符边界、const 构造、activateSkills/version |
| `registry_test.dart` | 398 | register/seal 不可变、findById/findByRoute、search(6维度)、listByCapability、导航(navGroups/navFlat/paletteItems)、依赖校验 |
| `http_server_test.dart` | 225 | 6端点(health/modules/:id/search/nav/routes)、404/405、重复 start/stop |

---

## 跨模块契约

### ModuleHttpServer — 6端点（仅 GET）

```
GET /module/health              → 200 {"status":"ok"}
GET /module/modules             → {"modules":[...], "count":N}
GET /module/modules/:id         → ModuleDescriptor JSON | 404
GET /module/search?q=&dim=&cat= → {"results":[...], "count":N}
GET /module/nav                 → {"navGroups":[...]}
GET /module/routes              → {"routes":[...], "count":N}
```

`start()` → `Future<int>`（实际端口），`port:0` 自动分配，写入 `.module_port`。端口 9100（默认，91xx 段统一）。

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
| 页面级 | `PageDescriptor.globalProcess` | 激活 → 切走 |
| 栏位级 | `ComponentConfig.process` | 可见 → 隐藏 |
| 动作级 | `ActionButtonDescriptor.process` | 触发 → 完成退出 |

### 依赖注入约定
- `ModuleRegistry` 不持有 HTTP 客户端/文件系统/日志——通过参数注入
- `ModuleLoader` 构造需要 `projectRoot`（传给 .exe 进程）
- `ModuleLifecycle` 通过回调 `onStop`/`onRestart` 与外部 ProcessManager 解耦
- `ExposeStateWriter` 通过构造接收 `PageEventBus` 和 `workspaceRoot`
