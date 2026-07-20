/// 属性编辑面板 —— 编辑选中 Slot 的属性或组件配置。
///
/// v3 简化：移除绝对位置编辑（x/y/w/h），按钮式设计器不需要手动定位。
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:evergreen_base/renderer/templates/v4_modle/components/document/plugin-designer/models/design_component.dart';
import 'package:evergreen_base/renderer/templates/v4_modle/components/document/plugin-designer/models/design_slot.dart';
import 'package:evergreen_base/renderer/templates/v4_modle/components/document/plugin-designer/models/design_page.dart';
import 'package:evergreen_base/renderer/templates/v4_modle/components/document/plugin-designer/services/auto_data_source_service.dart';
import 'json_path_picker.dart';

/// Slot 属性变更回调（v3：不再包含 rect）。
typedef SlotPropChanged = void Function({
  String? label,
  SlotRegion? region,
  List<double>? rect,
});

/// 组件配置变更回调。
typedef ComponentConfigChanged = void Function(String? type, Map<String, dynamic> config);

/// 选中已注册数据源类型回调（嵌入 orch://<type> 到组件 config）。
typedef SelectDataSource = void Function(String type);

/// 打开数据采集向导回调。
typedef OpenDataCollectionWizard = void Function();

/// 获取指定 orch 类型原始数据的预览（用于弹出 JSON 格式展示）。
typedef FetchDataPreview = Future<dynamic> Function(String type);

/// 获取指定 orch 类型的原始 decoded JSON（用于可点选的结构树）。
typedef FetchRawData = Future<dynamic> Function(String type);

/// 更新 dataSource.dataPath 回调。
typedef UpdateDataPath = void Function(String path);

/// 数据驱动组件类型集合（继承 DataSourceSlot 基类，通过 orch:// 获取数据）。
const _dataDrivenTypes = <String>{
  'data-dashboard', 'data-table', 'card-list', 'data-list', 'chart',
  'stat-tile', 'kanban', 'tree', 'timeline', 'map', 'calendar', 'timetable',
};

/// 每个数据驱动组件的所需数据格式说明。
///
/// 数据源返回的顶层 JSON 可以是列表或对象；组件通过 mergeData 提取目标字段。
/// 格式文本含 字段说明 + JSON 示例。
const _componentDataFormats = <String, String>{
  'chart': '''**期望结构**: List\<{label, value}\> 或 {labels, series}

**字段说明**:
- `label` String — 分类/标签名
- `value` num — 对应数值

**JSON 示例**:
```json
[
  {"label": "Q1", "value": 120},
  {"label": "Q2", "value": 180},
  {"label": "Q3", "value": 200}
]
```

或 {labels, series} 格式:
```json
{
  "labels": ["Q1","Q2","Q3"],
  "series": [{"name": "销售额", "data": [120,180,200]}]
}
```''',

  'data-table': '''**期望结构**: List\<Map\> (行列表)

**字段说明**:
- 每行为一个 Map，键=列名，值=单元格内容
- 第一行的键将作为表头

**JSON 示例**:
```json
[
  {"学号": "2024001", "姓名": "张三", "成绩": 92},
  {"学号": "2024002", "姓名": "李四", "成绩": 85}
]
```

也可用 `{"rows": [...]}` 包裹。''',

  'data-list': '''**期望结构**: List\<Map\> (项列表)

**字段说明**:
- 每项为 Map，字段名对应列表模板中的 {{key}} 占位符
- 组件内用 `item` 字段定义模板（如 {"title": "{{name}}"}）

**JSON 示例**:
```json
[
  {"name": "高等数学", "teacher": "张教授", "credits": 4},
  {"name": "线性代数", "teacher": "李教授", "credits": 3}
]
```

也可用 `{"items": [...]}` 包裹。''',

  'card-list': '''**期望结构**: List\<Map\> (卡片列表)

**字段说明**:
- `title` String — 卡片标题
- `body` String — 卡片正文
- `description` String (可选) — 副标题/描述

**JSON 示例**:
```json
[
  {"title": "高等数学", "body": "微积分与数学分析基础", "description": "4学分"},
  {"title": "线性代数", "body": "矩阵与向量空间", "description": "3学分"}
]
```

也可用 `{"cards": [...]}` 包裹。''',

  'stat-tile': '''**期望结构**: 单对象或标量

**字段说明** (对象模式):
- `title` String — 指标名称
- `value` String/num — 指标值
- `subtitle` String (可选) — 副标题
- `trend` String (可选) — "up"/"down"

**JSON 示例**:
```json
{
  "title": "在线用户",
  "value": "1,234",
  "subtitle": "较昨日 +12%",
  "trend": "up"
}
```

标量模式: 返回单个数值，将填入 value 字段。''',

  'kanban': '''**期望结构**: List\<Map\> (看板列)

**字段说明**:
- `title` String — 列标题
- `items` List\<Map\> — 列内卡片列表
  - `title` String — 卡片标题
  - `label` String (可选) — 标签

**JSON 示例**:
```json
[
  {"title": "待办", "items": [
    {"title": "完成报告", "label": "紧急"},
    {"title": "修复bug"}
  ]},
  {"title": "进行中", "items": [
    {"title": "新功能开发"}
  ]}
]
```

也可用 `{"columns": [...]}` 包裹。''',

  'tree': '''**期望结构**: 单对象（树根节点）

**字段说明**:
- `label` String — 节点名称
- `icon` String (可选) — 图标
- `expanded` bool (可选) — 是否展开
- `children` List\<Map\> — 子节点数组（递归同结构）

**JSON 示例**:
```json
{
  "label": "计算机科学",
  "children": [
    {"label": "数据结构", "children": [
      {"label": "数组"}, {"label": "链表"}
    ]},
    {"label": "操作系统"}
  ]
}
```

注意: 数据源顶层直接是根节点对象，无需包裹在 List 中。''',

  'timeline': '''**期望结构**: List\<Map\> (事件列表)

**字段说明**:
- `time` 或 `date` String — 时间/日期
- `label` 或 `title` String — 事件标题
- `description` 或 `subtitle` String (可选) — 详细描述

**JSON 示例**:
```json
[
  {"time": "09:00", "title": "晨会", "description": "每日站会"},
  {"time": "10:30", "title": "开发评审", "description": "M3需求评审"},
  {"time": "14:00", "title": "周报提交"}
]
```

也可用 `{"items": [...]}` 包裹。''',

  'map': '''**期望结构**: {center, zoom, markers?}

**字段说明**:
- `center` Map — {"lat": 纬度, "lng": 经度}
- `zoom` int — 缩放级别 (1-20)
- `markers` bool (可选) — 是否显示标记点

**JSON 示例**:
```json
{
  "center": {"lat": 30.2741, "lng": 120.1551},
  "zoom": 15,
  "markers": true
}
```

也可用 `{"map": {...}}` 包裹。''',

  'calendar': '''**期望结构**: List\<Map\> (事件列表)

**字段说明**:
- `date` String — 日期 (ISO 8601: "2025-03-15")
- `title` String — 事件标题
- `color` String (可选) — 颜色 "#FF5733"

**JSON 示例**:
```json
[
  {"date": "2025-03-15", "title": "期中考试", "color": "#FF4444"},
  {"date": "2025-03-18", "title": "实验室开放日", "color": "#44AAFF"}
]
```

也可用 `{"events": [...]}` 包裹。''',

  'timetable': '''**期望结构**: List\<Map\> (课程列表)

**字段说明**:
- `courseName` 或 `name` String — 课程名称
- `dayOfWeek` int — 星期几 (1=周一 … 7=周日)
- `periods` List\<int\> — 节次数组 ([1,2] = 第1-2节)

**JSON 示例**:
```json
[
  {"courseName": "高等数学", "dayOfWeek": 1, "periods": [1, 2]},
  {"courseName": "线性代数", "dayOfWeek": 1, "periods": [3, 4]},
  {"courseName": "数据结构", "dayOfWeek": 3, "periods": [1, 2, 3]}
]
```

也可用 `{"sessions": [...]}` 包裹。''',

  'data-dashboard': '''**期望结构**: List\<Map\> (仪表盘卡片列表)

**字段说明**:
- `title` String — 卡片标题
- `value` String/num — 指标值
- `subtitle` String (可选) — 副标题
- `trend` String (可选) — "up"/"down"

**JSON 示例**:
```json
[
  {"title": "总用户数", "value": "12,345", "trend": "up"},
  {"title": "HttpServer", "value": "6", "subtitle": "全部运行中"}
]
```

也可用 `{"cards": [...]}` 包裹。''',
};

/// 属性编辑面板。
///
/// v3 简化：
/// - 无选中 → 空态提示
/// - 选中 Slot → 编辑 label / region
/// - 有绑定组件 → 编辑组件 type + config JSON + dataSource
class PropertyPanel extends StatefulWidget {
  final DesignSlot? selectedSlot;
  final SlotPropChanged? onSlotPropChanged;
  final ComponentConfigChanged? onComponentConfigChanged;
  final VoidCallback? onSlotDeleted;

  /// 当前页面的布局预设（用于控制是否显示定位编辑等）。
  final DesignPageLayout? layoutPreset;

  /// 判断某数据源类型是否已注册。
  final bool Function(String)? isTypeRegistered;

  /// 一键爬取生成数据源回调（打开 DataSourceCaptureDialog）。
  final VoidCallback? onAutoGenerateDataSource;

  /// 已注册的 orch 数据源类型列表（供下拉选择）。
  final List<String> registeredTypes;

  /// 选中某个已注册 orch 类型 → 嵌入 dataSource endpoint。
  final SelectDataSource? onSelectDataSource;

  /// 打开完整数据采集四步向导。
  final OpenDataCollectionWizard? onOpenDataCollectionWizard;

  /// 获取指定 orch 类型的原始 JSON 数据用于预览弹窗。
  final FetchDataPreview? onFetchDataPreview;

  /// 获取指定 orch 类型的原始 decoded JSON（结构树点选路径）。
  final FetchRawData? onFetchRawData;

  /// 更新 dataSource.dataPath 键路径。
  final UpdateDataPath? onUpdateDataPath;

  const PropertyPanel({
    super.key,
    this.selectedSlot,
    this.onSlotPropChanged,
    this.onComponentConfigChanged,
    this.onSlotDeleted,
    this.isTypeRegistered,
    this.onAutoGenerateDataSource,
    this.registeredTypes = const [],
    this.onSelectDataSource,
      this.onOpenDataCollectionWizard,
      this.onFetchDataPreview,
      this.onFetchRawData,
      this.onUpdateDataPath,
      this.layoutPreset,
  });

  @override
  State<PropertyPanel> createState() => PropertyPanelState();

  static void refresh(BuildContext context) {
    final state = context.findAncestorStateOfType<PropertyPanelState>();
    state?._loadCurrentValues();
  }
}

class PropertyPanelState extends State<PropertyPanel> {
  late TextEditingController _labelCtrl;
  late TextEditingController _compTypeCtrl;
  late TextEditingController _dataPathCtrl;
  late TextEditingController _xCtrl;
  late TextEditingController _yCtrl;
  late TextEditingController _wCtrl;
  late TextEditingController _hCtrl;
  SlotRegion _selectedRegion = SlotRegion.center;
  final Map<String, TextEditingController> _configCtrls = {};

  /// 数据格式要求面板展开状态。
  bool _showFormatHelp = false;

  /// 从组件 config 解析当前绑定的 orch://<type> 中的 type 名。
  String? get _currentOrchType {
    final comp = widget.selectedSlot?.component;
    if (comp == null) return null;
    final ds = comp.config['dataSource'];
    if (ds is! Map || ds['endpoint'] is! String) return null;
    return AutoDataSourceService.extractOrchType(ds['endpoint'] as String);
  }

  /// 从组件 config 解析当前的 dataPath（JSON 键路径）。
  String? get _currentDataPath {
    final comp = widget.selectedSlot?.component;
    if (comp == null) return null;
    final ds = comp.config['dataSource'];
    if (ds is! Map) return null;
    return ds['dataPath'] as String?;
  }

  /// 当前组件是否为数据驱动组件。
  bool get _isDataDriven {
    final type = widget.selectedSlot?.component?.type;
    return type != null && _dataDrivenTypes.contains(type);
  }

  @override
  void initState() {
    super.initState();
    _labelCtrl = TextEditingController();
    _compTypeCtrl = TextEditingController();
    _dataPathCtrl = TextEditingController();
    _xCtrl = TextEditingController();
    _yCtrl = TextEditingController();
    _wCtrl = TextEditingController();
    _hCtrl = TextEditingController();
    _loadCurrentValues();
  }

  @override
  void didUpdateWidget(covariant PropertyPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedSlot?.id != widget.selectedSlot?.id) {
      _loadCurrentValues();
    }
  }

  void _loadCurrentValues() {
    final slot = widget.selectedSlot;
    if (slot == null) return;
    _labelCtrl.text = slot.label;
    _selectedRegion = slot.region;
    _compTypeCtrl.text = slot.component?.type ?? '';
    _dataPathCtrl.text = _currentDataPath ?? '';
    final r = slot.rect;
    // rect 内部为百分比（0-100）。旧 manifest（绝对像素）加载时按 1 位小数显示即可。
    _xCtrl.text = r.isNotEmpty ? _formatRectValue(r[0]) : '0';
    _yCtrl.text = r.length > 1 ? _formatRectValue(r[1]) : '0';
    _wCtrl.text = r.length > 2 ? _formatRectValue(r[2]) : '50';
    _hCtrl.text = r.length > 3 ? _formatRectValue(r[3]) : '50';
    setState(() {});
  }

  /// 格式化 rect 数值显示。
  /// - 整数（如 50）→ 不带小数
  /// - 小数（如 33.3）→ 保留 1 位
  /// - 异常值（< 0 或 > 200）→ 提示可能为旧像素数据
  String _formatRectValue(double v) {
    if (v.isFinite && v >= 0 && v <= 200) {
      return v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);
    }
    // 可能是旧像素数据（如 300），原样显示
    return v.toStringAsFixed(0);
  }

  @override
  void dispose() {
    _labelCtrl.dispose();
    _compTypeCtrl.dispose();
    _dataPathCtrl.dispose();
    _xCtrl.dispose();
    _yCtrl.dispose();
    _wCtrl.dispose();
    _hCtrl.dispose();
    for (final c in _configCtrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final slot = widget.selectedSlot;
    if (slot == null) {
      return _buildEmpty();
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: _buildSectionHeader('Slot 属性', Icons.crop_free)),
              if (widget.onSlotDeleted != null)
                IconButton(
                  icon: const Icon(Icons.delete_outline, size: 18),
                  tooltip: '删除 Slot',
                  onPressed: widget.onSlotDeleted,
                ),
            ],
          ),
          const SizedBox(height: 8),
          _buildTextField('标签', _labelCtrl, onChanged: (_) => _notifySlotChange()),
          const SizedBox(height: 8),
          _buildRegionDropdown(),
          // ── 绝对定位编辑（仅 absolute 布局时显示）──
          if (widget.layoutPreset == DesignPageLayout.absolute) ...[
            const SizedBox(height: 12),
            _buildSectionHeader('定位', Icons.open_with),
            const SizedBox(height: 8),
            _buildAbsolutePositionEditor(),
          ],
          const SizedBox(height: 16),
          const Divider(),
          const SizedBox(height: 12),
          _buildSectionHeader('绑定组件', Icons.widgets),
          const SizedBox(height: 8),
          ..._buildDataSourceWarning(),
          _buildTextField('组件类型', _compTypeCtrl,
              hint: '未绑定',
              onChanged: (_) => _notifyComponentChange()),
          // ── 数据驱动组件：数据源嵌入选项 ──
          if (_isDataDriven) ...[
            const SizedBox(height: 12),
            _buildDataSourceSection(),
          ],
          ..._buildConfigEditor(),
        ],
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.touch_app, size: 40, color: Colors.grey.shade300),
          const SizedBox(height: 12),
          Text(
            '选择一个 Slot\n查看和编辑其属性',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey.shade400, fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 16, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 6),
        Text(
          title,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
      ],
    );
  }

  Widget _buildTextField(
    String label,
    TextEditingController ctrl, {
    String? hint,
    ValueChanged<String>? onChanged,
  }) {
    return TextField(
      controller: ctrl,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
      ),
      style: const TextStyle(fontSize: 13),
      onChanged: onChanged,
    );
  }

  Widget _buildRegionDropdown() {
    return DropdownButtonFormField<SlotRegion>(
      value: _selectedRegion,
      decoration: InputDecoration(
        labelText: '区域',
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
      ),
      style: const TextStyle(fontSize: 13),
      items: SlotRegion.values.map((r) {
        return DropdownMenuItem(value: r, child: Text(r.name));
      }).toList(),
      onChanged: (v) {
        if (v != null) {
          setState(() => _selectedRegion = v);
          _notifySlotChange();
        }
      },
    );
  }

  /// 绝对定位编辑控件（x, y, w, h 四个输入框，全部为百分比 0-100）。
  Widget _buildAbsolutePositionEditor() {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _buildNumberField('X (%)', _xCtrl,
                  tooltip: '距左侧距离，单位 %（0-100）', onChanged: () => _notifySlotChange(includeRect: true)),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _buildNumberField('Y (%)', _yCtrl,
                  tooltip: '距顶部距离，单位 %（0-100）', onChanged: () => _notifySlotChange(includeRect: true)),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: _buildNumberField('宽度 (%)', _wCtrl,
                  tooltip: 'Slot 宽度，单位 %（0-100）', onChanged: () => _notifySlotChange(includeRect: true)),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _buildNumberField('高度 (%)', _hCtrl,
                  tooltip: 'Slot 高度，单位 %（0-100）', onChanged: () => _notifySlotChange(includeRect: true)),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          '百分比按父容器尺寸自适应，支持 0-200 范围（>100% 允许溢出）',
          style: TextStyle(fontSize: 10, color: Theme.of(context).hintColor),
        ),
      ],
    );
  }

  /// 紧凑数值输入框。
  Widget _buildNumberField(String label, TextEditingController ctrl, {
    String? tooltip,
    VoidCallback? onChanged,
  }) {
    final field = TextField(
      controller: ctrl,
      keyboardType: TextInputType.number,
      decoration: InputDecoration(
        labelText: label,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
      ),
      style: const TextStyle(fontSize: 13),
      onChanged: (_) => onChanged?.call(),
    );
    if (tooltip == null) return field;
    return Tooltip(message: tooltip, child: field);
  }

  List<Widget> _buildDataSourceWarning() {
    final comp = widget.selectedSlot?.component;
    final ds = comp?.config['dataSource'];
    if (ds is! Map || ds['endpoint'] is! String) return [];
    final type = AutoDataSourceService.extractOrchType(ds['endpoint'] as String);
    if (type == null || type.isEmpty) return [];
    final registered = widget.isTypeRegistered?.call(type) ?? false;
    if (registered) return [];

    final theme = Theme.of(context);
    return [
      Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: theme.colorScheme.errorContainer.withValues(alpha: 0.25),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: theme.colorScheme.error.withValues(alpha: 0.4),
            width: 0.5,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.warning_amber_rounded,
                    size: 16, color: theme.colorScheme.error),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '数据源 "$type" 尚未生成',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.error,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: widget.onAutoGenerateDataSource,
                icon: const Icon(Icons.auto_awesome, size: 14),
                label: const Text('✨ 自动爬取生成数据源', style: TextStyle(fontSize: 12)),
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 12),
    ];
  }

  /// 数据源嵌入选项 —— 仅对数据驱动组件显示。
  ///
  /// 允许用户从已注册的 orch 类型中选择一个嵌入到组件 config：
  ///   config['dataSource'] = {'endpoint': 'orch://<type>'}
  /// 也提供一键创建新数据源和打开完整采集向导的入口。
  Widget _buildDataSourceSection() {
    // 同步 dataPath 控制器（父级 setState 重建时 text 可能与最新 config 不一致）
    final currentDataPath = _currentDataPath ?? '';
    if (_dataPathCtrl.text != currentDataPath) {
      _dataPathCtrl.text = currentDataPath;
    }

    final theme = Theme.of(context);
    final currentType = _currentOrchType;
    final isRegistered = currentType != null &&
        (widget.isTypeRegistered?.call(currentType) ?? false);
    final availableTypes = widget.registeredTypes;

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: theme.colorScheme.primary.withValues(alpha: 0.25),
          width: 0.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 标题 + 当前绑定状态
          Row(
            children: [
              Icon(Icons.storage, size: 16, color: theme.colorScheme.primary),
              const SizedBox(width: 6),
              Text('数据源', style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.primary,
              )),
              const Spacer(),
              if (currentType != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: isRegistered
                        ? theme.colorScheme.primaryContainer
                        : theme.colorScheme.errorContainer.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    isRegistered ? '已注册' : '未注册',
                    style: TextStyle(
                      fontSize: 10,
                      color: isRegistered
                          ? theme.colorScheme.primary
                          : theme.colorScheme.error,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),

          // 当前绑定信息
          if (currentType != null) ...[
            Row(
              children: [
                Icon(Icons.link, size: 13, color: Colors.grey),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    'orch://$currentType',
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
          ],

          // ═══ 数据格式要求（可折叠） ═══
          _buildFormatHelp(),

          // 已注册 orch 类型下拉选择
          if (availableTypes.isNotEmpty) ...[
            Text('嵌入已有数据源：', style: TextStyle(
              fontSize: 11, color: Colors.grey.shade600,
            )),
            const SizedBox(height: 4),
            DropdownButtonFormField<String>(
              value: (currentType != null && availableTypes.contains(currentType))
                  ? currentType
                  : null,
              isExpanded: true,
              decoration: InputDecoration(
                hintText: currentType != null
                    ? '更换数据源…'
                    : '选择已注册的数据源…',
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 10),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6)),
              ),
              style: const TextStyle(fontSize: 13),
              items: availableTypes.map((t) {
                return DropdownMenuItem(value: t, child: Text(t));
              }).toList(),
              onChanged: (v) {
                if (v != null) {
                  debugPrint('[PropertyPanel] 📡 嵌入数据源: orch://$v');
                  widget.onSelectDataSource?.call(v);
                }
              },
            ),
            const SizedBox(height: 8),
          ],

          // 无已注册类型时提示
          if (availableTypes.isEmpty && currentType == null) ...[
            Text(
              '暂无已注册的数据源。',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 2),
            Text(
              '可先通过数据采集向导创建数据源。',
              style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
            ),
            const SizedBox(height: 8),
          ],

          // ═══ JSON 预览 + dataPath 配置 ═══
          // 仅当已绑定已注册数据源时显示
          if (currentType != null && isRegistered && widget.onFetchDataPreview != null) ...[
            const SizedBox(height: 8),
            // 预览按钮
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => _showDataPreviewDialog(currentType),
                icon: const Icon(Icons.account_tree_outlined, size: 16),
                label: const Text('预览数据 & 点选路径',
                    style: TextStyle(fontSize: 12)),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                ),
              ),
            ),
            const SizedBox(height: 8),
            // dataPath 输入
            TextField(
              controller: _dataPathCtrl,
              decoration: InputDecoration(
                labelText: '数据路径 (dataPath)',
                hintText: '如: results.items, data[0].rows',
                helperText: '留空使用全量数据。点上方按钮可在结构树中直接点选生成路径',
                helperMaxLines: 2,
                helperStyle: TextStyle(fontSize: 10, color: Colors.grey.shade500),
                isDense: true,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
              ),
              style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
              onChanged: (v) {
                widget.onUpdateDataPath?.call(v.trim());
              },
            ),
            const SizedBox(height: 4),
          ],

          // 操作按钮行
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              if (widget.onOpenDataCollectionWizard != null)
                _miniActionButton(
                  icon: Icons.wifi_find_rounded,
                  label: '采集新数据',
                  onTap: widget.onOpenDataCollectionWizard,
                ),
              if (widget.onAutoGenerateDataSource != null)
                _miniActionButton(
                  icon: Icons.auto_awesome,
                  label: '自动爬取',
                  onTap: widget.onAutoGenerateDataSource,
                ),
            ],
          ),
        ],
      ),
    );
  }

  /// 数据格式要求面板 — 可折叠，展示当前组件类型所需的数据结构。
  ///
  /// 显示在数据源 area 内，帮助用户理解应提供什么格式的 JSON。
  Widget _buildFormatHelp() {
    final type = widget.selectedSlot?.component?.type;
    if (type == null) return const SizedBox.shrink();
    final formatText = _componentDataFormats[type];
    if (formatText == null) return const SizedBox.shrink();

    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 4),
        InkWell(
          onTap: () => setState(() => _showFormatHelp = !_showFormatHelp),
          borderRadius: BorderRadius.circular(4),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              children: [
                Icon(
                  _showFormatHelp
                      ? Icons.info_outline
                      : Icons.info_outline,
                  size: 13,
                  color: theme.colorScheme.secondary,
                ),
                const SizedBox(width: 4),
                Text(
                  '数据格式要求',
                  style: TextStyle(
                    fontSize: 11,
                    color: theme.colorScheme.secondary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(width: 4),
                Icon(
                  _showFormatHelp
                      ? Icons.expand_less
                      : Icons.expand_more,
                  size: 14,
                  color: Colors.grey,
                ),
              ],
            ),
          ),
        ),
        if (_showFormatHelp) ...[
          const SizedBox(height: 4),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest
                  .withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: theme.dividerColor,
                width: 0.5,
              ),
            ),
            child: SelectionArea(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Text(
                  formatText,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 11,
                    height: 1.5,
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  /// 迷你操作按钮（紧凑样式，与 Section 风格一致）。
  Widget _miniActionButton({
    required IconData icon,
    required String label,
    VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: Theme.of(context).dividerColor,
            width: 0.5,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12),
            const SizedBox(width: 4),
            Text(label, style: const TextStyle(fontSize: 11)),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildConfigEditor() {
    final comp = widget.selectedSlot?.component;
    if (comp == null || comp.config.isEmpty) return [];

    // 过滤出非 dataSource 的配置项（dataSource 由 _buildDataSourceSection 专门处理）
    final visibleEntries = comp.config.entries
        .where((e) => e.key != 'dataSource')
        .toList();
    if (visibleEntries.isEmpty) return [];

    final widgets = <Widget>[
      const SizedBox(height: 12),
      _buildSectionHeader('组件配置', Icons.tune),
      const SizedBox(height: 8),
    ];

    for (final entry in visibleEntries) {
      if (!_configCtrls.containsKey(entry.key)) {
        _configCtrls[entry.key] = TextEditingController(text: entry.value.toString());
      }
      widgets.add(Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: TextField(
          controller: _configCtrls[entry.key],
          decoration: InputDecoration(
            labelText: entry.key,
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
          ),
          style: const TextStyle(fontSize: 13),
          onChanged: (_) => _notifyComponentChange(),
        ),
      ));
    }
    return widgets;
  }

  void _notifySlotChange({bool includeRect = false}) {
    widget.onSlotPropChanged?.call(
      label: _labelCtrl.text,
      region: _selectedRegion,
      // rect 内部为百分比 0-100。允许 0-200 范围（>100% 允许溢出）。
      // 负数和无意义值截断为 0。
      rect: includeRect ? [
        (double.tryParse(_xCtrl.text) ?? 0).clamp(0.0, 200.0),
        (double.tryParse(_yCtrl.text) ?? 0).clamp(0.0, 200.0),
        (double.tryParse(_wCtrl.text) ?? 50).clamp(0.0, 200.0),
        (double.tryParse(_hCtrl.text) ?? 50).clamp(0.0, 200.0),
      ] : null,
    );
  }

  void _notifyComponentChange() {
    final type = _compTypeCtrl.text.trim();
    final config = <String, dynamic>{};
    for (final entry in _configCtrls.entries) {
      config[entry.key] = entry.value.text;
    }
    // 保留 dataSource Map（非文本编辑，由 _buildDataSourceSection 管理）
    final originalDs = widget.selectedSlot?.component?.config['dataSource'];
    if (originalDs is Map) {
      config['dataSource'] = originalDs;
    }
    widget.onComponentConfigChanged?.call(
      type.isEmpty ? null : type,
      config,
    );
  }

  /// 弹出「数据预览与路径选择」对话框。
  ///
  /// 双 Tab：
  /// - 结构树：可交互 JSON 树，点击任意节点自动生成 dataPath（`a.b[0].c`），
  ///   键名无法被 extractPath 表达的节点禁止点选；
  /// - 原始文本：原有的 dumpDataFormat 格式文本预览。
  /// 底部展示已选路径，「使用此路径」回填输入框并写回组件 config。
  Future<void> _showDataPreviewDialog(String type) async {
    final theme = Theme.of(context);
    final textFuture = widget.onFetchDataPreview?.call(type);
    final rawFuture = widget.onFetchRawData?.call(type);
    String? pickedPath; // 弹窗内点选、尚未确认应用的路径

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          // 底部栏展示路径：优先弹窗内新点选，其次已配置值
          final effectivePath = pickedPath ?? _currentDataPath ?? '';
          return AlertDialog(
            title: Row(
              children: [
                const Icon(Icons.account_tree_outlined, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '数据预览与路径选择',
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: theme.colorScheme.onSurface),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            content: SizedBox(
              width: 480,
              height: 460,
              child: DefaultTabController(
                length: 2,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primaryContainer
                            .withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        'orch://$type',
                        style: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 11,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ),
                    TabBar(
                      labelStyle: const TextStyle(fontSize: 12),
                      tabs: const [
                        Tab(text: '结构树（点选路径）'),
                        Tab(text: '原始文本'),
                      ],
                    ),
                    Expanded(
                      child: TabBarView(
                        children: [
                          _buildTreeTab(rawFuture, type,
                              (p) => setDialogState(() => pickedPath = p)),
                          _buildTextTab(textFuture, theme),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    // 底部已选路径栏
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 6),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerHighest
                            .withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(6),
                        border:
                            Border.all(color: theme.dividerColor, width: 0.5),
                      ),
                      child: Row(
                        children: [
                          Text('已选路径:',
                              style: TextStyle(
                                  fontSize: 11,
                                  color:
                                      theme.colorScheme.onSurfaceVariant)),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              effectivePath.isEmpty
                                  ? '（全量数据）'
                                  : effectivePath,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: effectivePath.isEmpty
                                    ? theme.disabledColor
                                    : theme.colorScheme.primary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  _applyDataPathFromDialog('');
                  Navigator.of(ctx).pop();
                },
                child: const Text('清除路径'),
              ),
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('关闭'),
              ),
              FilledButton(
                onPressed: pickedPath != null
                    ? () {
                        _applyDataPathFromDialog(pickedPath!);
                        Navigator.of(ctx).pop();
                      }
                    : null,
                child: const Text('使用此路径'),
              ),
            ],
          );
        },
      ),
    );
  }

  /// 将弹窗中确认的路径回填输入框并写回组件 config。
  void _applyDataPathFromDialog(String path) {
    debugPrint('[PropertyPanel] 弹窗确认 dataPath: "$path"');
    _dataPathCtrl.text = path;
    widget.onUpdateDataPath?.call(path);
  }

  /// 结构树 Tab：拉取原始 decoded JSON，构建可点选路径的树。
  Widget _buildTreeTab(Future<dynamic>? rawFuture, String type,
      ValueChanged<String> onPick) {
    if (rawFuture == null) {
      return const Center(
          child: Text('未配置原始数据获取回调', style: TextStyle(fontSize: 12)));
    }
    return FutureBuilder<dynamic>(
      future: rawFuture,
      builder: (_, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return Center(
            child: Text('加载失败: ${snap.error}',
                style: TextStyle(
                    color: Theme.of(context).colorScheme.error, fontSize: 13),
                textAlign: TextAlign.center),
          );
        }
        final raw = snap.data;
        // 错误/空态哨兵（与 _fetchRawData 约定）
        if (raw is Map && raw['_error'] != null) {
          return Center(
            child: Text('加载失败: ${raw['_error']}',
                style: TextStyle(
                    color: Theme.of(context).colorScheme.error, fontSize: 13),
                textAlign: TextAlign.center),
          );
        }
        if (raw == null) {
          return const Center(
            child: Text('该数据源暂无缓存数据，请先采集或刷新',
                style: TextStyle(fontSize: 12), textAlign: TextAlign.center),
          );
        }
        if (raw is! Map && raw is! List) {
          return const Center(
            child: Text('该数据源为标量值，无需设置路径（留空即可）',
                style: TextStyle(fontSize: 12), textAlign: TextAlign.center),
          );
        }
        return JsonPathPicker(
          data: raw,
          initialPath: _currentDataPath,
          onPathSelected: onPick,
        );
      },
    );
  }

  /// 原始文本 Tab：沿用 dumpDataFormat 格式文本预览。
  Widget _buildTextTab(Future<dynamic>? textFuture, ThemeData theme) {
    return FutureBuilder<dynamic>(
      future: textFuture,
      builder: (_, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return Center(
            child: Text('加载失败: ${snap.error}',
                style: TextStyle(color: theme.colorScheme.error, fontSize: 13),
                textAlign: TextAlign.center),
          );
        }
        final raw = snap.data;
        // 区分两种返回：String=格式文本, Map=错误/空态
        final String display;
        if (raw is String) {
          // dumpDataFormat 返回的格式文本直接展示
          display = raw.length > 20000
              ? '${raw.substring(0, 20000)}\n\n… (已截断，完整长度: ${raw.length} 字符)'
              : raw;
        } else {
          final encoder = const JsonEncoder.withIndent('  ');
          final String pretty = (() {
            try {
              return encoder.convert(raw);
            } catch (_) {
              return raw?.toString() ?? '(null)';
            }
          })();
          display = pretty.length > 20000
              ? '${pretty.substring(0, 20000)}\n\n… (已截断，完整长度: ${pretty.length} 字符)'
              : pretty;
        }

        return Container(
          width: double.infinity,
          margin: const EdgeInsets.only(top: 8),
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest
                .withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: theme.dividerColor, width: 0.5),
          ),
          child: SingleChildScrollView(
            child: SelectableText(
              display,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 11,
                height: 1.5,
              ),
            ),
          ),
        );
      },
    );
  }
}
