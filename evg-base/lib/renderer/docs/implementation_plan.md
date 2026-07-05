# 渲染层 Sprint 2 实施计划

> 基于 Phase 1 原型 (`docs/prototype.html`) 的 Flutter 代码实施路线图
> 设计/渲染工程师双签：—

---

## 架构复用策略

遵循现有三层架构：`widgets(原子) → shared(范式视图+页面) → compositions(高级组合)`

所有新页面遵循「描述符驱动 + 数据注入」模式。

---

## 交付物清单

| # | 文件 | 类型 | 对应任务 | 优先级 |
|---|------|------|---------|--------|
| 1 | `CLAUDE.md` | 文档 | 渲染交付物#3 | P0 |
| 2 | `shared/market_view.dart` | 页面 | R-S2-1 | P0 |
| 3 | `shared/plugin_detail_view.dart` | 页面 | R-S2-2 | P1 |
| 4 | `shared/my_plugins_view.dart` | 页面 | R-S2-6 | P1 |
| 5 | `shared/settings_view.dart` | 页面 | R-S2-7 | P1 |
| 6 | `widgets/install_progress.dart` | 组件 | R-S2-3 | P1 |
| 7 | `widgets/permission_dialog.dart` | 组件 | R-S2-9 | P2 |
| 8 | `widgets/notification_card.dart` | 组件 | R-S2-8 | P2 |
| 9 | `compositions/workspace_page.dart` | 页面 | R-S2-4 | P0 |
| 10 | 测试更新 | 测试 | 全部 | P0 |

---

## 数据模型扩展

在 `widgets/models.dart` 中新增：

```dart
class PluginDescriptor {
  final String id;
  final String name;
  final String description;
  final String longDescription;
  final String author;
  final String version;
  final List<AbilityDim> dimensions;
  final List<PluginPermission> permissions;
  final int screenshotCount;
  final int installCount;
  final double rating;
  final bool installed;
  final bool hasUpdate;
}

enum AbilityDim { agent, ui, data, theme, settings, skill }

class PluginPermission {
  final String name;
  final PermissionLevel level;
}

enum PermissionLevel { safe, warning, danger }

class SettingsGroup {
  final String title;
  final List<SettingsItem> items;
}

class SettingsItem {
  final String label;
  final String? description;
  final SettingsItemType type;
  final dynamic value;
}

enum SettingsItemType { toggle, link, info }
```

---

## 实施顺序

1. **CLAUDE.md** — 文档先行
2. **扩展 models.dart** — 数据模型
3. **widgets/ 原子组件** — permission_dialog, install_progress, notification_card
4. **shared/ 页面** — market_view, plugin_detail_view, my_plugins_view, settings_view
5. **compositions/workspace_page.dart** — 工作台页面
6. **测试更新** — 覆盖所有新组件/页面
7. **导出更新** — widgets.dart, shared.dart 更新导出
