---
task_type: refactor
tags: [architecture, module, registry, plugin, decoupling, sidebar, routing, agent]
difficulty: hard
outcome: success
date: 2026-06-25
files_touched:
  - lib/core/registry/** (4 new files)
  - lib/features/*/module.dart (24 new files)
  - lib/modules.dart (new)
  - lib/widgets/wip_screen.dart (extracted from app.dart)
  - lib/widgets/sidebar.dart (5 处硬编码 → Registry 驱动)
  - lib/widgets/command_palette.dart (硬编码 → Registry 驱动)
  - lib/app.dart (-180 行硬编码, +1 行 registry.buildRoutes())
  - lib/core/services/ocr_pipeline.dart (子进程超时 60s→15s)
  - docs/ARCHITECTURE.md, docs/MODULE_MAP.md, docs/MODIFICATION_GUIDE.md
---

## 做了什么

建立了插件式模块注册框架（`lib/core/registry/`），24 个 feature 模块全部通过 `module.dart` 声明自己的身份、路由、导航、依赖、导出。框架层（ModuleRegistry）自动生成 GoRouter 路由表、侧边栏导航（4 种形态）、命令面板搜索条目。

## 关键决策

### 1. FeatureModule 抽象接口
每个模块实现一个 `FeatureModule` 子类，放在模块根目录 `module.dart`。模块作者只需：
1. 建目录 + 写代码
2. 写 `module.dart`
3. 在 `lib/modules.dart` 加一行 `reg.register(MyModule())`

### 2. 集中注册点
`lib/modules.dart` 是所有模块的注册入口，每人一行。同一个文件内按 Section 分组排序，merge conflict 面积极小。

### 3. 渐进迁移策略
先建框架（registry/），再选 Palace/Courses/Agent 试点，验证 sidebar 和 app.dart 可全量解耦后，一次性迁移所有剩余 21 个模块。

### 4. secondaryNavs 模式
一个模块有多个独立页面时（如 zdbk 的 教务通知+开课情况+培养方案），通过 `secondaryNavs` 声明额外导航条目，可放在不同 section。

### 5. 子进程超时收紧
`_tesseractOcrUrl` 的子进程超时从 60s→15s。下载单张图片 15s 足够，60s 会导致测试悬挂。

## 踩过的坑

### 1. 测试 URL 不能是真实服务器
OCR 回退测试的 URL 指向 `img.cmc.zju.edu.cn`——Dart 层 mock 了 Dio 失败，但 Python 子进程独立下载，卡在真实网络请求上。修复：改用 `127.0.0.1:1` 保证两层都瞬间失败。

### 2. 模块声明缺少 import → 编译失败
`sidebar_section.dart` 的 `NavDecl` 用了 `IconData` 但没 import `flutter/widgets.dart`。核心层文件需显式 import 所有 Flutter 类型。

### 3. 重复 id 检测在 register() 而非 seal()
测试期望 seal() 时校验重复 id，但生产代码在 register() 就抛异常。对齐测试：重复 id 在注册时立即检测。

### 4. ClassroomViewerScreen 有必填 courseId
子路由需要路径参数时不能直接用 `const` 构造，需设计参数化路由。当前暂移除该子路由，后续迭代加。

## 可复用的模式

### 插件式模块声明模板
```dart
// lib/features/my_feature/module.dart
class MyFeatureModule extends FeatureModule {
  @override String get id => 'my_feature';
  @override String get name => '我的功能';
  @override IconData get icon => Icons.star;
  @override SidebarSection get sidebarSection => SidebarSection.aiTools;
  @override int get sidebarOrder => 50;
  @override List<String> get dependsOn => ['auth'];
  @override List<RouteBase> buildRoutes() => [
    GoRoute(path: '/my-feature', pageBuilder: (c, s) => CustomTransitionPage<void>(
      key: s.pageKey, child: const MyScreen(),
      transitionsBuilder: (c, a, _, ch) => FadeTransition(opacity: a, child: ch),
      transitionDuration: const Duration(milliseconds: 200),
    )),
  ];
}
```
然后在 `lib/modules.dart` 加一行 `reg.register(MyFeatureModule());`

### 多页面模块模式
```dart
@override
List<NavEntryDecl> get secondaryNavs => [
  NavEntryDecl(icon: Icons.book, label: '子页面', routePath: '/sub-page',
    section: SidebarSection.learning, order: 20),
];
```
