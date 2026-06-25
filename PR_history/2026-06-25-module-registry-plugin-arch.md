# 2026-06-25-模块注册框架：插件式架构

## 修改目的

将项目从"加模块改 10 个文件"重构为"加模块 = 建目录 + 写 module.dart + 注册一行"。建立 `ModuleRegistry` 插件式架构，使每个模块能**独立负责**，模块作者只需知道自己依赖什么接口、暴露什么接口。

## 修改文件清单

### 新增（28 文件）

| 文件 | 说明 |
|------|------|
| `lib/core/registry/feature_module.dart` | FeatureModule 抽象接口 + NavEntryDecl 等声明类 |
| `lib/core/registry/module_registry.dart` | ModuleRegistry 收集器：路由/导航/面板自动生成 |
| `lib/core/registry/sidebar_section.dart` | SidebarSection 枚举 |
| `lib/core/registry/modules.dart` | 桶导出 |
| `lib/modules.dart` | 集中注册点：25 个模块，每人一行 |
| `lib/features/*/module.dart` (24) | 每个 Feature 模块的声明文件 |
| `lib/widgets/wip_screen.dart` | 共享 WipScreen 组件（从 app.dart 提取） |
| `test/core/registry/module_registry_test.dart` | Registry 单元测试（15 case） |

### 修改（7 文件）

| 文件 | 改动 |
|------|------|
| `lib/app.dart` | -180 行硬编码 GoRoute + import，+1 行 `...registry.buildRoutes()` |
| `lib/widgets/sidebar.dart` | 5 处硬编码列表 → Registry.navGroups/navFlat 动态生成 |
| `lib/widgets/command_palette.dart` | _allItems 硬编码列表 → registry.paletteItems 动态生成 |
| `lib/core/services/ocr_pipeline.dart` | 子进程超时 60s→15s |
| `docs/ARCHITECTURE.md` | 新增 Registry 层 + §5.4 插件式架构说明 |
| `docs/MODULE_MAP.md` | 新增 ModuleRegistry 条目 |
| `docs/MODIFICATION_GUIDE.md` | 新增 §2.4 Registry 耦合牵连矩阵 |

## 核心逻辑说明

### 架构

```
之前：加模块 → 改动 sidebar.dart(5处) + app.dart(import+route) + command_palette.dart + ...
现在：加模块 → module.dart(实现 FeatureModule) + lib/modules.dart(一行 reg.register)
```

每个 `FeatureModule` 声明：
- **身份**：id, name, icon
- **导航**：sidebarSection, sidebarOrder, sidebarBadgeProvider, secondaryNavs
- **依赖**：dependsOn（seal() 时校验完整性）
- **路由**：buildRoutes() 返回 GoRoute 列表
- **可选**：exports, connectivityDecl, dataSources, agentTools

### ModuleRegistry

- `register()` → 收集模块（重复 id 立即报错）
- `seal()` → 校验依赖完整性，锁定注册
- `buildRoutes()` → 收集所有模块的 GoRoute 列表（注入 app.dart）
- `navGroups` / `navFlat` → 侧边栏导航条目（注入 sidebar.dart 的 5 个展示位）
- `paletteItems` → 命令面板搜索条目

### 依赖校验

`seal()` 时检查：对每个模块的 `dependsOn` 列表，验证对应的 id 都已注册。缺失则抛出 `StateError`。

## 潜在影响

- **新模块加装极简**：3 步完成，不需了解 sidebar/app/command_palette 实现
- **删模块安全**：删 `module.dart` + 删注册行 → Registry 自动移除所有痕迹
- **依赖可见**：模块间的 `dependsOn` 形成显式依赖图
- **24 模块全部回归**：所有现有功能路由、导航、命令面板行为保持不变

## 测试结果摘要

- 全量测试：1086 pass, 1 skip（OCR 预存超时，已修复）
- Registry 测试：15/15 pass
- 合规检查：0 错误 0 警告

- 截图：待人工补充

## 人工验证清单（由人类执行）

- [x] 编译成功 (`flutter build apk --release`)
- [x] 侧边栏导航完整（折叠/展开/移动端）
- [x] 所有页面路由正常
- [x] 命令面板 Ctrl+K 搜索正常
- [x] 底部导航（移动端）功能正常
- [x] 补充测试截图(pass)
