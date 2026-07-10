/// editable/ — 可编辑数据表格的分层架构实现
///
/// 三层架构：
///   models/       — 数据模型层（强类型，替代原始 editable 包的 Map<String, dynamic>）
///   controller/   — 控制器层（TableEditController: ChangeNotifier 驱动 UI）
///   widgets/      — UI 组件层（纯渲染，接收 controller + 数据）
///
/// 与原始 [editable] 包 (pub.dev: editable) 的关系：
///   - 借鉴了其内联编辑、保存按钮、新建行、斑马纹等核心交互概念
///   - 但用分层架构重新实现，消除了 original 的巨石设计 + 裸 dynamic 类型
///   - 新增：强类型模型、列操作、行删除、TableEditController 集中状态管理
///
/// 快速开始:
/// ```dart
/// final data = EditableTableData.fromJson(config);
/// final controller = TableEditController(data: data);
/// return EditableTable(controller: controller, zebraStripe: true);
/// ```
library editable_table_lib;

export 'models/editable_column.dart';
export 'models/editable_table_data.dart';
export 'controller/table_edit_controller.dart';
export 'widgets/editable_table.dart';
export 'widgets/editable_header_cell.dart';
export 'widgets/editable_data_cell.dart';
