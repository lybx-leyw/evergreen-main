/// 属性编辑面板 —— 编辑选中 Slot 的属性或组件配置。
///
/// P2 实现：
/// - 无选中：显示空态提示
/// - 选中 Slot：编辑 label/region/rect
/// - 选中 Slot 且有绑定组件：编辑组件 type + config
library;

import 'package:flutter/material.dart';

import '../models/design_component.dart';
import '../models/design_slot.dart';

/// Slot 属性变更回调。
typedef SlotPropChanged = void Function({
  String? label,
  SlotRegion? region,
  List<double>? rect,
});

/// 组件配置变更回调。 
typedef ComponentConfigChanged = void Function(String? type, Map<String, dynamic> config);

/// 属性编辑面板 —— 右侧栏。
///
/// 根据选中状态显示不同编辑界面：
/// - [selectedSlot] == null → 空态提示
/// - [selectedSlot] != null && component == null → Slot 属性编辑
/// - [selectedSlot] != null && component != null → Slot + 组件编辑
class PropertyPanel extends StatefulWidget {
  final DesignSlot? selectedSlot;
  final SlotPropChanged? onSlotPropChanged;
  final ComponentConfigChanged? onComponentConfigChanged;

  const PropertyPanel({
    super.key,
    this.selectedSlot,
    this.onSlotPropChanged,
    this.onComponentConfigChanged,
  });

  @override
  State<PropertyPanel> createState() => PropertyPanelState();

  /// 暴露给外部强制刷新（如 Slot 切换时）。
  static void refresh(BuildContext context) {
    final state = context.findAncestorStateOfType<PropertyPanelState>();
    state?._loadCurrentValues();
  }
}

class PropertyPanelState extends State<PropertyPanel> {
  late TextEditingController _labelCtrl;
  late TextEditingController _xCtrl;
  late TextEditingController _yCtrl;
  late TextEditingController _wCtrl;
  late TextEditingController _hCtrl;
  late TextEditingController _compTypeCtrl;
  SlotRegion _selectedRegion = SlotRegion.center;
  final Map<String, TextEditingController> _configCtrls = {};

  @override
  void initState() {
    super.initState();
    _labelCtrl = TextEditingController();
    _xCtrl = TextEditingController();
    _yCtrl = TextEditingController();
    _wCtrl = TextEditingController();
    _hCtrl = TextEditingController();
    _compTypeCtrl = TextEditingController();
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
    _xCtrl.text = slot.rect[0].toStringAsFixed(0);
    _yCtrl.text = slot.rect[1].toStringAsFixed(0);
    _wCtrl.text = slot.rect[2].toStringAsFixed(0);
    _hCtrl.text = slot.rect[3].toStringAsFixed(0);
    _compTypeCtrl.text = slot.component?.type ?? '';
    setState(() {});
  }

  @override
  void dispose() {
    _labelCtrl.dispose();
    _xCtrl.dispose();
    _yCtrl.dispose();
    _wCtrl.dispose();
    _hCtrl.dispose();
    _compTypeCtrl.dispose();
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
          _buildSectionHeader('Slot 属性', Icons.crop_free),
          const SizedBox(height: 8),
          _buildTextField('标签', _labelCtrl, onChanged: (_) => _notifySlotChange()),
          const SizedBox(height: 8),
          _buildRegionDropdown(),
          const SizedBox(height: 12),
          _buildSectionHeader('位置与大小', Icons.format_shapes),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(child: _buildTextField('X', _xCtrl, onChanged: (_) => _notifySlotChange())),
              const SizedBox(width: 8),
              Expanded(child: _buildTextField('Y', _yCtrl, onChanged: (_) => _notifySlotChange())),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(child: _buildTextField('宽', _wCtrl, onChanged: (_) => _notifySlotChange())),
              const SizedBox(width: 8),
              Expanded(child: _buildTextField('高', _hCtrl, onChanged: (_) => _notifySlotChange())),
            ],
          ),
          const SizedBox(height: 16),
          const Divider(),
          const SizedBox(height: 12),
          _buildSectionHeader('绑定组件', Icons.widgets),
          const SizedBox(height: 8),
          _buildTextField('组件类型', _compTypeCtrl,
              hint: '未绑定',
              onChanged: (_) => _notifyComponentChange()),
          // 组件 config（若有）
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
            '在画布上选择一个 Slot\n查看和编辑其属性',
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

  List<Widget> _buildConfigEditor() {
    final comp = widget.selectedSlot?.component;
    if (comp == null || comp.config.isEmpty) return [];

    final widgets = <Widget>[
      const SizedBox(height: 12),
      _buildSectionHeader('组件配置', Icons.tune),
      const SizedBox(height: 8),
    ];

    for (final entry in comp.config.entries) {
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

  void _notifySlotChange() {
    widget.onSlotPropChanged?.call(
      label: _labelCtrl.text,
      region: _selectedRegion,
      rect: [
        double.tryParse(_xCtrl.text) ?? 0,
        double.tryParse(_yCtrl.text) ?? 0,
        double.tryParse(_wCtrl.text) ?? 200,
        double.tryParse(_hCtrl.text) ?? 150,
      ],
    );
  }

  void _notifyComponentChange() {
    final type = _compTypeCtrl.text.trim();
    final config = <String, dynamic>{};
    for (final entry in _configCtrls.entries) {
      config[entry.key] = entry.value.text;
    }
    widget.onComponentConfigChanged?.call(
      type.isEmpty ? null : type,
      config,
    );
  }
}
