/// 原子组件画廊——展示 widgets/ 目录下的所有核心组件。
///
/// 使用 mock 数据（不依赖真实 core/ 服务），
/// 所有参数与实际组件构造函数签名完全一致。

import 'package:flutter/material.dart';
import 'package:evergreen_base/core/module/module_descriptor.dart';
import '../widgets/models.dart';
import '../widgets/message_bubble.dart';
import '../widgets/thinking_block.dart';
import '../widgets/chat_input_bar.dart';
import '../widgets/dashboard_card.dart';
import '../widgets/confirm_dialog.dart';
import '../widgets/empty_state.dart';
import '../widgets/data_table.dart';
import '../widgets/data_list.dart';
import '../widgets/data_card_grid.dart';
import '../widgets/search_bar.dart';
import '../widgets/toast.dart';
import '../widgets/error_card.dart';
import '../widgets/evergreen_progress.dart';
import '../widgets/freshness_badge.dart';
import '../widgets/loading_indicator.dart';
import '../widgets/streaming_cursor.dart';
import '../widgets/tool_call_card.dart';
import '../widgets/markdown_renderer.dart';
import '../widgets/crud_toolbar.dart';
import '../widgets/sort_header.dart';
import '../widgets/export_menu.dart';
import '../widgets/refresh_widget.dart';
import '../widgets/ability_tag.dart';
import '../widgets/install_progress.dart';
import '../widgets/notification_card.dart';
import '../widgets/permission_dialog.dart';
import '../widgets/type_check_input.dart';
import '../widgets/select_input.dart';
import '../widgets/form_field_renderer.dart';
import '../widgets/media_host.dart';
import '../widgets/image_viewer.dart';
import '../widgets/timeline_widget.dart';
import '../widgets/spreadsheet_cell.dart';
import '../widgets/formula_bar.dart';
import '../widgets/chart_renderer.dart';
import '../widgets/sheet_tab_bar.dart';
import '../widgets/slide_canvas.dart';
import '../widgets/slide_sorter.dart';
import '../widgets/speaker_notes_panel.dart';
import '../widgets/rich_text_editor.dart';
import '../widgets/code_editor.dart';
import '../shared/theme_provider.dart';

/// Mock 数据工厂——提供各组件的展示用数据。
class MockData {
  // ── Chat ──
  static final userMessage = ChatMessage(
    role: 'user',
    content: '你好！请帮我解释一下什么是 Flutter 的渲染管线？',
    timestamp: DateTime.now().subtract(const Duration(minutes: 5)),
  );

  static final assistantMessage = ChatMessage(
    role: 'assistant',
    content: 'Flutter 的渲染管线分为三个阶段：\n\n1. **布局（Layout）**：确定每个 RenderObject 的位置和大小\n2. **绘制（Paint）**：将 RenderObject 绘制到 Layer 树\n3. **合成（Composite）**：将 Layer 树提交到 GPU',
    timestamp: DateTime.now().subtract(const Duration(minutes: 4)),
  );

  static final toolCallMessage = ChatMessage(
    role: 'assistant',
    content: '让我搜索相关资料...',
    toolCalls: [
      const ToolCallData(
        name: 'web_search',
        arguments: 'Flutter rendering pipeline',
        result: '找到 3 条相关结果',
        completed: true,
      ),
    ],
    timestamp: DateTime.now().subtract(const Duration(minutes: 3)),
  );

  // ── Dashboard ──
  static const kpiCards = [
    {'title': '活跃用户', 'value': '12,345', 'trend': 'up', 'subtitle': '+12% vs 上周'},
    {'title': '会话数', 'value': '8,920', 'trend': 'up', 'subtitle': '+5% vs 上周'},
    {'title': '响应时间', 'value': '230ms', 'trend': 'down', 'subtitle': '-15% vs 上周'},
    {'title': '错误率', 'value': '0.12%', 'trend': 'down', 'subtitle': '-0.05% vs 上周'},
  ];

  // ── Data Table ──
  static const tableColumns = ['名称', '版本', '作者', '安装数', '评分'];
  static final tableRows = [
    {'名称': '词汇导师', '版本': '1.2.0', '作者': 'Evergreen', '安装数': '1,234', '评分': '4.8'},
    {'名称': '番茄钟', '版本': '2.1.0', '作者': 'Community', '安装数': '890', '评分': '4.6'},
    {'名称': '代码审查', '版本': '0.9.5', '作者': 'Evergreen', '安装数': '567', '评分': '4.3'},
    {'名称': '思维导图', '版本': '3.0.1', '作者': 'Community', '安装数': '2,100', '评分': '4.9'},
  ];

  // ── Markdown ──
  static const sampleMarkdown = '# Markdown 渲染示例\n\n## 代码块\n\n```dart\nvoid main() {\n  print(\'Hello, Evergreen!\');\n}\n```\n\n## 列表\n\n- 项目 A\n- 项目 B\n\n## 表格\n\n| 功能 | 状态 | 进度 |\n|------|------|------|\n| 渲染引擎 | ✅ | 100% |\n| 插件系统 | ✅ | 100% |\n\n## 引用\n\n> Evergreen 是一个模块化的桌面插件平台。\n\n**粗体** *斜体* `行内代码`';

  // ── Ability tags ──
  static const abilities = [
    AbilityDim.agent,
    AbilityDim.ui,
    AbilityDim.data,
    AbilityDim.theme,
    AbilityDim.settings,
    AbilityDim.skill,
  ];

  // ── Select options ──
  static const selectOptions = ['Flutter', 'React', 'Vue', 'Angular', 'Svelte'];

  // ── Chart ──
  static const chartConfigs = [
    ChartConfig(type: 'bar', title: '季度统计', labels: ['Q1', 'Q2', 'Q3', 'Q4'], values: [120, 180, 140, 200]),
  ];
}

class WidgetGallery extends StatelessWidget {
  const WidgetGallery({super.key});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionTitle(context, 'Chat 原子组件'),
          const SizedBox(height: 12),
          _buildChatSection(context),

          const SizedBox(height: 32),
          _buildSectionTitle(context, 'Dashboard 卡片'),
          const SizedBox(height: 12),
          _buildDashboardSection(context),

          const SizedBox(height: 32),
          _buildSectionTitle(context, '数据展示组件'),
          const SizedBox(height: 12),
          _buildDataDisplaySection(context),

          const SizedBox(height: 32),
          _buildSectionTitle(context, '通用工具组件'),
          const SizedBox(height: 12),
          _buildUtilitySection(context),

          const SizedBox(height: 32),
          _buildSectionTitle(context, '交互组件'),
          const SizedBox(height: 12),
          _buildInteractionSection(context),

          const SizedBox(height: 32),
          _buildSectionTitle(context, '表单组件'),
          const SizedBox(height: 12),
          _buildFormSection(context),

          const SizedBox(height: 32),
          _buildSectionTitle(context, 'Spreadsheet 组件'),
          const SizedBox(height: 12),
          _buildSpreadsheetSection(context),

          const SizedBox(height: 32),
          _buildSectionTitle(context, 'Presentation 组件'),
          const SizedBox(height: 12),
          _buildPresentationSection(context),

          const SizedBox(height: 32),
          _buildSectionTitle(context, '页面辅助组件'),
          const SizedBox(height: 12),
          _buildPageHelperSection(context),

          const SizedBox(height: 32),
          _buildSectionTitle(context, '媒体渲染组件'),
          const SizedBox(height: 12),
          _buildMediaSection(context),

          const SizedBox(height: 32),
          _buildSectionTitle(context, 'Markdown 渲染'),
          const SizedBox(height: 12),
          _buildMarkdownSection(context),

          const SizedBox(height: 32),
          _buildSectionTitle(context, 'Timeline / 编辑器'),
          const SizedBox(height: 12),
          _buildTimelineEditorSection(context),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(BuildContext context, String title) {
    return Text(
      title,
      style: Theme.of(context).textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.bold,
          ),
    );
  }

  // ── Chat ──
  Widget _buildChatSection(BuildContext context) {
    return Column(
      children: [
        MessageBubble(
          message: MockData.userMessage,
          bubble: const BubbleOptions(style: 'rounded'),
          stream: const StreamOptions(),
          isLast: false,
          showThinking: false,
        ),
        const SizedBox(height: 8),
        MessageBubble(
          message: MockData.assistantMessage,
          bubble: const BubbleOptions(style: 'rounded'),
          stream: const StreamOptions(),
          isLast: true,
          showThinking: false,
        ),
        const SizedBox(height: 8),
        MessageBubble(
          message: MockData.toolCallMessage,
          bubble: const BubbleOptions(style: 'rounded'),
          stream: const StreamOptions(),
          isLast: false,
          showThinking: false,
        ),
        const SizedBox(height: 8),
        const StreamingCursor(),
      ],
    );
  }

  // ── Dashboard ──
  Widget _buildDashboardSection(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        childAspectRatio: 1.5,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: MockData.kpiCards.length,
      itemBuilder: (context, index) {
        final card = MockData.kpiCards[index];
        return DashboardCard(
          title: card['title']!,
          value: card['value']!,
          trend: card['trend']!,
          subtitle: card['subtitle']!,
        );
      },
    );
  }

  // ── Data Display ──
  Widget _buildDataDisplaySection(BuildContext context) {
    return Column(
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: EvergreenDataTable(
              columns: MockData.tableColumns,
              rows: MockData.tableRows,
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: DataList(
              items: MockData.tableRows,
              titleKey: '名称',
              subtitleKey: '作者',
              trailingKey: '评分',
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: DataCardGrid(
              items: MockData.tableRows,
              titleKey: '名称',
              bodyKey: '描述',
              footerKey: '版本',
            ),
          ),
        ),
      ],
    );
  }

  // ── Utility ──
  Widget _buildUtilitySection(BuildContext context) {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        const EmptyState(
          icon: Icons.inbox_outlined,
          title: '暂无数据',
          subtitle: '这里还没有任何内容',
        ),
        const ErrorCard(
          message: '网络连接失败',
          detail: '请检查网络设置后重试',
          hint: '确保设备已连接到互联网',
        ),
        const EvergreenProgress(value: 0.65, label: '加载中... 65%'),
        const FreshnessBadge(lastFetchedAt: null),
        const LoadingIndicator(message: '正在加载数据...'),
        const LoadingIndicator.compact(hint: '查询中...'),
      ],
    );
  }

  // ── Interaction ──
  Widget _buildInteractionSection(BuildContext context) {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        ElevatedButton(
          onPressed: () {
            ConfirmDialog.show(
              context,
              title: '确认删除',
              message: '确定要删除此项目吗？此操作不可撤销。',
            );
          },
          child: const Text('显示确认弹窗'),
        ),
        CrudToolbar(
          onAdd: () => Toast.success(context, '新增'),
          onEdit: () => Toast.info(context, '编辑'),
          onDelete: () => Toast.error(context, '删除'),
          onRefresh: () => Toast.info(context, '刷新'),
        ),
        const SortHeader(
          label: '名称',
          sortable: true,
          active: true,
          ascending: true,
        ),
        ExportMenu(
          actions: const ActionDescriptor(exportable: ['csv', 'json', 'pdf']),
          onExport: (fmt) => Toast.success(context, '导出 ${fmt.name}'),
        ),
        const EvergreenSearchBar(hintText: '搜索组件...'),
        RefreshWidget(onRefresh: () {}),
      ],
    );
  }

  // ── Form ──
  Widget _buildFormSection(BuildContext context) {
    return Column(
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: TypeCheckInput(
              input: const InputOptions(
                mode: 'type-check',
                options: ['apple'],
              ),
              onChanged: (v) {},
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: SelectInput(
              input: const InputOptions(
                mode: 'select',
                options: ['Flutter', 'React', 'Vue', 'Angular', 'Svelte'],
              ),
              onChanged: (v) => Toast.info(context, '选择了: $v'),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                FormFieldRenderer(
                  field: const FormFieldDescriptor(
                    label: '插件名称',
                    type: 'text',
                    placeholder: '输入插件名称',
                  ),
                ),
                const SizedBox(height: 12),
                FormFieldRenderer(
                  field: const FormFieldDescriptor(
                    label: '描述',
                    type: 'textarea',
                    placeholder: '简要描述插件功能',
                  ),
                ),
                const SizedBox(height: 12),
                FormFieldRenderer(
                  field: const FormFieldDescriptor(
                    label: '启用通知',
                    type: 'bool_',
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ── Spreadsheet ──
  Widget _buildSpreadsheetSection(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          children: [
            const FormulaBar(formula: '=SUM(A1:A10)'),
            const SheetTabBar(
              tabs: ['Sheet1', 'Sheet2', 'Sheet3'],
              activeIndex: 0,
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 44,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: 5,
                itemBuilder: (context, index) {
                  return SizedBox(
                    width: 100,
                    child: SpreadsheetCell(
                      value: 'Cell ${index + 1}',
                      isHeader: index == 0,
                      isSelected: index == 2,
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 12),
            const ChartRenderer(chartConfigs: MockData.chartConfigs),
          ],
        ),
      ),
    );
  }

  // ── Presentation ──
  Widget _buildPresentationSection(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            const SlideCanvas(
              slides: [
                SlideData(title: '封面', layout: 'title'),
                SlideData(title: '内容页 1', layout: 'content'),
                SlideData(title: '内容页 2', layout: 'two-column'),
                SlideData(title: '结束页', layout: 'end'),
              ],
              activeIndex: 1,
            ),
            const SizedBox(height: 12),
            const SlideSorter(
              slides: [
                SlideData(title: '封面', layout: 'title'),
                SlideData(title: '内容页 1', layout: 'content'),
                SlideData(title: '内容页 2', layout: 'two-column'),
              ],
              activeIndex: 0,
            ),
            const SizedBox(height: 12),
            const SpeakerNotesPanel(
              notes: '这是演讲者注释内容。\n\n- 要点 1\n- 要点 2',
            ),
          ],
        ),
      ),
    );
  }

  // ── Page Helper ──
  Widget _buildPageHelperSection(BuildContext context) {
    return Column(
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: MockData.abilities
              .map((dim) => AbilityTag(dimension: dim))
              .toList(),
        ),
        const SizedBox(height: 16),
        const InstallProgressWidget(
          progress: InstallProgress(
            pluginId: 'demo',
            progress: 0.7,
            status: InstallStatus.downloading,
          ),
        ),
        const SizedBox(height: 8),
        NotificationCard(
          notification: AppNotification(
            title: '插件更新',
            message: '词汇导师 v1.3.0 已发布',
            type: NotificationType.update,
            time: DateTime.now().subtract(const Duration(minutes: 5)),
          ),
        ),
        const SizedBox(height: 8),
        ElevatedButton(
          onPressed: () {
            showPermissionDialog(
              context,
              pluginName: '词汇导师',
              permissions: const [
                PluginPermission(name: '读取文件', level: PermissionLevel.safe),
                PluginPermission(name: '网络访问', level: PermissionLevel.warning),
                PluginPermission(name: '执行脚本', level: PermissionLevel.danger),
              ],
            );
          },
          child: const Text('显示权限弹窗'),
        ),
      ],
    );
  }

  // ── Media ──
  Widget _buildMediaSection(BuildContext context) {
    return const Card(
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          children: [
            MediaHost(
              mediaType: 'image',
              src: '',
              fallbackLabel: '示例图片',
            ),
            SizedBox(height: 12),
            ImageViewer(src: '', alt: '示例图片'),
          ],
        ),
      ),
    );
  }

  // ── Markdown ──
  Widget _buildMarkdownSection(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: MarkdownRenderer(data: MockData.sampleMarkdown),
      ),
    );
  }

  // ── Timeline / Editor ──
  Widget _buildTimelineEditorSection(BuildContext context) {
    return Column(
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: TimelineWidget(
              timeline: const TimelineDescriptor(mode: 'list'),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: RichTextEditor(
              initialContent: '这是一个富文本编辑器的示例内容。',
              onChanged: (content) {},
            ),
          ),
        ),
        const SizedBox(height: 12),
        const Card(
          child: SizedBox(
            height: 200,
            child: CodeEditor(
              language: 'dart',
              initialCode: 'void main() {\n  print("Hello!");\n}',
            ),
          ),
        ),
      ],
    );
  }
}
