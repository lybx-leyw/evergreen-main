/// 预览面板 —— 编排结果的实时预览。
///
/// P3 实现：接收 DesignDocument 编译输出，分屏展示编排结果。
///
/// 功能：
/// - 解析编译后的 manifest JSON
/// - 按页面展示 Slot 布局（简化的 CompositeView 模拟）
/// - 支持页面切换
/// - 错误状态展示
library;

import 'package:flutter/material.dart';

import '../models/design_document.dart';
import '../services/design_to_manifest.dart';

/// 预览面板 —— 在右侧展示编排结果的实时预览。
class PreviewPanel extends StatefulWidget {
  /// 当前设计文档。
  final DesignDocument? document;

  /// 是否正在刷新。
  final bool isRefreshing;

  /// 预览宽度。
  final double width;

  const PreviewPanel({
    super.key,
    this.document,
    this.isRefreshing = false,
    this.width = 400,
  });

  @override
  State<PreviewPanel> createState() => _PreviewPanelState();
}

class _PreviewPanelState extends State<PreviewPanel> {
  int _activePageIndex = 0;
  String? _compileError;

  Map<String, dynamic>? get _manifest {
    if (widget.document == null) return null;
    try {
      _compileError = null;
      return DesignToManifest.compile(widget.document!);
    } catch (e) {
      _compileError = e.toString();
      return null;
    }
  }

  List<Map<String, dynamic>> get _pages {
    final m = _manifest;
    if (m == null) return [];
    return (m['pages'] as List?)?.cast<Map<String, dynamic>>() ?? [];
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: widget.width,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(
          left: BorderSide(
            color: Theme.of(context).dividerColor,
            width: 1,
          ),
        ),
      ),
      child: Column(
        children: [
          _buildHeader(),
          _buildPageTabs(),
          Expanded(child: _buildContent()),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: Theme.of(context).dividerColor,
          ),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.preview,
            size: 18,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(width: 8),
          Text(
            '实时预览',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 14,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          const Spacer(),
          if (widget.isRefreshing)
            SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildPageTabs() {
    final pages = _pages;
    if (pages.isEmpty) {
      return const SizedBox.shrink();
    }

    return SizedBox(
      height: 36,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        itemCount: pages.length,
        separatorBuilder: (_, __) => const SizedBox(width: 4),
        itemBuilder: (context, index) {
          final page = pages[index];
          final isActive = index == _activePageIndex;
          return GestureDetector(
            onTap: () => setState(() => _activePageIndex = index),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: isActive
                    ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.12)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(6),
                border: isActive
                    ? Border.all(
                        color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.3),
                      )
                    : null,
              ),
              alignment: Alignment.center,
              child: Text(
                page['label'] as String? ?? '页面 ${index + 1}',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                  color: isActive
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(context).colorScheme.onSurface,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildContent() {
    // 空文档
    if (widget.document == null) {
      return _buildEmpty('请先创建或加载设计文档');
    }

    // 编译错误
    if (_compileError != null) {
      return _buildError(_compileError!);
    }

    // 无页面
    final pages = _pages;
    if (pages.isEmpty) {
      return _buildEmpty('暂无页面，请在画布中添加页面');
    }

    // 确保 activePageIndex 有效
    if (_activePageIndex >= pages.length) {
      _activePageIndex = 0;
    }
    final page = pages[_activePageIndex];
    return _buildPagePreview(page);
  }

  Widget _buildEmpty(String message) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.web_asset_outlined,
            size: 48,
            color: Theme.of(context).disabledColor,
          ),
          const SizedBox(height: 12),
          Text(
            message,
            style: TextStyle(
              color: Theme.of(context).disabledColor,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildError(String error) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 36, color: Colors.red.shade300),
            const SizedBox(height: 8),
            Text(
              '编译错误',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 13,
                color: Colors.red.shade400,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              error,
              style: TextStyle(fontSize: 11, color: Colors.red.shade300),
              textAlign: TextAlign.center,
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPagePreview(Map<String, dynamic> page) {
    final layout = page['layout'] as Map<String, dynamic>?;
    final slots = layout?['slots'] as Map<String, dynamic>? ?? {};
    final layoutType = layout?['type'] as String? ?? 'grid';

    if (slots.isEmpty) {
      return _buildEmpty('当前页面无 Slot，请在画布中框选区域');
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 页面信息
          _buildPageInfo(page, layoutType),
          const SizedBox(height: 8),
          // Slot 列表（按 region 排序）
          ..._buildSlotCards(slots),
        ],
      ),
    );
  }

  Widget _buildPageInfo(Map<String, dynamic> page, String layoutType) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        children: [
          Icon(Icons.tablet_mac, size: 16,
              color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              '${page['label'] ?? '页面'}  ·  $layoutType',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              layoutType.toUpperCase(),
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildSlotCards(Map<String, dynamic> slots) {
    // 按 region 排序：top → left → center → right → bottom
    final regionOrder = ['top', 'left', 'center', 'right', 'bottom'];
    final entries = slots.entries.toList()
      ..sort((a, b) {
        final regionA = (a.value as Map<String, dynamic>?)?['region'] as String? ?? 'center';
        final regionB = (b.value as Map<String, dynamic>?)?['region'] as String? ?? 'center';
        return regionOrder.indexOf(regionA).compareTo(regionOrder.indexOf(regionB));
      });

    return entries.map((entry) {
      final slotData = entry.value as Map<String, dynamic>;
      final component = slotData['component'] as Map<String, dynamic>?;
      final region = slotData['region'] as String? ?? 'center';
      final label = slotData['label'] as String?;
      final slotLabel = label ?? entry.key;

      return Container(
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          border: Border.all(
            color: Theme.of(context).dividerColor,
          ),
          borderRadius: BorderRadius.circular(6),
          color: Theme.of(context).colorScheme.surface,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Slot 头部
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(5)),
              ),
              child: Row(
                children: [
                  _regionIcon(region),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      slotLabel,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(3),
                    ),
                    child: Text(
                      region,
                      style: TextStyle(
                        fontSize: 10,
                        color: Theme.of(context).colorScheme.onPrimaryContainer,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // 组件信息
            Padding(
              padding: const EdgeInsets.all(10),
              child: component != null
                  ? _buildComponentPreview(component)
                  : Text(
                      '（空 Slot，未绑定组件）',
                      style: TextStyle(
                        fontSize: 12,
                        fontStyle: FontStyle.italic,
                        color: Theme.of(context).disabledColor,
                      ),
                    ),
            ),
          ],
        ),
      );
    }).toList();
  }

  Widget _buildComponentPreview(Map<String, dynamic> component) {
    final type = component['type'] as String? ?? 'unknown';
    final config = component['config'] as Map<String, dynamic>?;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          _componentIcon(type),
          size: 28,
          color: Theme.of(context).colorScheme.primary,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                type,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (config != null && config.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    config.entries.map((e) => '${e.key}: ${e.value}').join('  ·  '),
                    style: TextStyle(
                      fontSize: 11,
                      color: Theme.of(context).disabledColor,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  IconData _componentIcon(String type) {
    switch (type) {
      case 'ai-assistant': return Icons.psychology;
      case 'data-table': return Icons.table_chart;
      case 'chart': return Icons.bar_chart;
      case 'card-list': return Icons.view_list;
      case 'markdown': return Icons.description;
      case 'code-editor': return Icons.code;
      case 'map': return Icons.map;
      case 'calendar': return Icons.calendar_month;
      case 'kanban': return Icons.view_kanban;
      case 'timeline': return Icons.timeline;
      case 'video-player': return Icons.videocam;
      case 'audio-player': return Icons.headphones;
      case 'webview': return Icons.language;
      default: return Icons.widgets;
    }
  }

  Widget _regionIcon(String region) {
    final icon = switch (region) {
      'top' => Icons.vertical_align_top,
      'left' => Icons.vertical_split,
      'center' => Icons.crop_square,
      'right' => Icons.vertical_split,
      'bottom' => Icons.vertical_align_bottom,
      _ => Icons.crop_square,
    };
    return Icon(icon, size: 16, color: Theme.of(context).disabledColor);
  }
}
