# Compositions — 高级组合视图

> 将多个 `shared/` 层视图叠加为复杂工作区界面。

## 用途

`widgets/` 存放原子渲染组件，`shared/` 存放单范式组合视图。当需要在一个页面中组合多个 `shared/` 视图（如编辑器 + 文件面板 + Chat 侧栏）时，放在 `compositions/` 下。

## 组件列表

| 组件 | 文件 | 说明 |
|------|------|------|
| WorkspaceHub | `workspace_hub.dart` | 文件树 + 编辑器 + Chat 侧栏三合一工作区 |
| WorkspacePage | `workspace_page.dart` | 工作区页面容器 |

## 使用

```dart
import 'package:evergreen_base/renderer/compositions/compositions.dart';

WorkspaceHub(descriptor: myModuleDescriptor);
WorkspacePage(descriptor: myModuleDescriptor);
```
