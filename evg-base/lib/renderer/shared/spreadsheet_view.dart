/// Spreadsheet 视图——单元格网格 + 公式栏 + 图表 + 多 Sheet。
///
/// 公开类：[SpreadsheetView]
import 'package:flutter/material.dart';
import 'package:evergreen_base/core/module/module_descriptor.dart';
import '../widgets/spreadsheet_cell.dart';
import '../widgets/formula_bar.dart';
import '../widgets/chart_renderer.dart';
import '../widgets/sheet_tab_bar.dart';
import '../widgets/empty_state.dart';

/// 电子表格范式完整视图。
///
/// 读取 [ModuleDescriptor.spreadsheet] 中的 [SpreadsheetOptions]。
class SpreadsheetView extends StatefulWidget {
  final ModuleDescriptor descriptor;

  const SpreadsheetView({super.key, required this.descriptor});

  @override
  State<SpreadsheetView> createState() => _SpreadsheetViewState();
}

class _SpreadsheetViewState extends State<SpreadsheetView> {
  int _activeSheet = 0;

  SpreadsheetOptions get _opts =>
      widget.descriptor.spreadsheet ?? const SpreadsheetOptions();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // 多 Sheet 标签栏
        if (_opts.sheets)
          SheetTabBar(
            sheets: const ['Sheet1'],
            activeIndex: _activeSheet,
            onSheetChanged: (i) => setState(() => _activeSheet = i),
          ),

        // 公式栏
        if (_opts.formulas) const FormulaBar(),

        // 单元格网格
        Expanded(
          child: _opts.columns != null && _opts.rows != null
              ? SpreadsheetGrid(
                  columns: _opts.columns!,
                  rows: _opts.rows!,
                  conditionalFormatting: _opts.conditionalFormatting,
                  resizableColumns: _opts.resizableColumns,
                )
              : const EmptyState(
                  icon: Icons.grid_on,
                  title: '空表格',
                  subtitle: '未配置行列数据',
                ),
        ),

        // 图表面板
        if (_opts.charts)
          SizedBox(
            height: 200,
            child: ChartRenderer(chartConfigs: const [
              ChartConfig(type: 'bar', title: '图表', labels: [], values: []),
            ]),
          ),
      ],
    );
  }
}
