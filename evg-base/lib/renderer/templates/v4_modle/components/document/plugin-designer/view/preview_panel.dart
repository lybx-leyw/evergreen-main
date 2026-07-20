/// 预览面板 —— 编排结果的实时预览。
///
/// P3 实现：接收 DesignDocument，分屏展示编排结果。
/// A-P3 升级：接入真实 [CompositeView] 渲染（[CompositePreviewFrame]），
/// 达成"所见即所得"——预览效果与导出后运行效果一致。
library;

import 'package:flutter/material.dart';
import 'package:evergreen_base/renderer/templates/v4_modle/components/document/plugin-designer/models/design_document.dart';
import 'package:evergreen_base/renderer/templates/v4_modle/components/document/plugin-designer/widgets/composite_preview_frame.dart';

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
          Expanded(
            child: widget.document == null
                ? const _EmptyHint('请先创建或加载设计文档')
                : widget.document!.pages.isEmpty
                    ? const _EmptyHint('暂无页面，请在画布中添加页面')
                    : CompositePreviewFrame(document: widget.document),
          ),
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
}

/// 预览空态提示（文档为空 / 无页面时由 [PreviewPanel] 直接展示）。
class _EmptyHint extends StatelessWidget {
  final String message;
  const _EmptyHint(this.message);

  @override
  Widget build(BuildContext context) {
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
}
