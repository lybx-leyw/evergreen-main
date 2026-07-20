/// WebView 槽位——基于 `webview_windows` 内嵌 Edge WebView2。
///
/// 支持 http/https URL 和本地相对路径（自动解析为绝对 file:///）。
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:webview_windows/webview_windows.dart';
import 'package:evergreen_base/core/module/module_descriptor.dart';
import 'package:evergreen_base/core/utils/greenix_path.dart';

/// WebView——`webview` 组件（真浏览器引擎）。
class WebViewSlot extends StatefulWidget {
  final ComponentDescriptor config;
  final String? moduleId;
  final String? pluginsDir;

  const WebViewSlot({
    super.key,
    required this.config,
    this.moduleId,
    this.pluginsDir,
  });

  @override
  State<WebViewSlot> createState() => _WebViewSlotState();
}

class _WebViewSlotState extends State<WebViewSlot> {
  final WebviewController _controller = WebviewController();
  bool _initialized = false;
  String? _error;
  String _rawUrl = '';
  String _resolvedUrl = '';
  bool _isLoading = false;
  bool _canGoBack = false;
  bool _canGoForward = false;

  StreamSubscription? _loadingSub;
  StreamSubscription? _urlSub;
  StreamSubscription? _historySub;

  @override
  void initState() {
    super.initState();
    _initWebView();
  }

  String _resolveUrl(String raw) {
    if (raw.startsWith('http://') || raw.startsWith('https://')) return raw;
    if (raw.startsWith('file:///')) return raw;

    // Windows 绝对路径 → 转 file:///
    if (Platform.isWindows && raw.length >= 2 && raw[1] == ':') {
      return 'file:///${raw.replaceAll('\\', '/')}';
    }
    if (raw.startsWith('/')) return 'file://$raw';

    // 相对路径 → resolvePluginAssetPath
    final mid = widget.moduleId;
    final pd = widget.pluginsDir ?? resolvePluginsRoot();
    if (mid == null) return raw;
    final resolved = resolvePluginAssetPath(raw, mid, pd);
    if (resolved == null) return raw;
    return 'file:///${resolved.replaceAll('\\', '/')}';
  }

  Future<void> _initWebView() async {
    final cfg = widget.config.config;
    _rawUrl = cfg['url'] as String? ?? '';
    if (_rawUrl.isEmpty) return;

    _resolvedUrl = _resolveUrl(_rawUrl);

    try {
      await _controller.initialize();
      if (!mounted) return;

      _loadingSub = _controller.loadingState.listen((state) {
        if (!mounted) return;
        setState(() {
          _isLoading = state == LoadingState.loading;
        });
      });

      _urlSub = _controller.url.listen((url) {
        if (!mounted || url.isEmpty) return;
      });

      _historySub = _controller.historyChanged.listen((h) {
        if (!mounted) return;
        setState(() {
          _canGoBack = h.canGoBack;
          _canGoForward = h.canGoForward;
        });
      });

      _controller.loadUrl(_resolvedUrl);

      if (mounted) setState(() => _initialized = true);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  void _goBack() => _controller.goBack();
  void _goForward() => _controller.goForward();
  void _reload() => _controller.reload();

  @override
  Widget build(BuildContext context) {
    if (_rawUrl.isEmpty) return _emptyState(context);

    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 地址栏
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            border: Border(bottom: BorderSide(color: theme.dividerColor)),
          ),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back, size: 18),
                onPressed: _canGoBack ? _goBack : null,
                tooltip: '后退',
              ),
              IconButton(
                icon: const Icon(Icons.arrow_forward, size: 18),
                onPressed: _canGoForward ? _goForward : null,
                tooltip: '前进',
              ),
              IconButton(
                icon: const Icon(Icons.refresh, size: 18),
                onPressed: _initialized ? _reload : null,
                tooltip: '刷新',
              ),
              Expanded(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(
                    _rawUrl,
                    style: theme.textTheme.bodySmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ],
          ),
        ),
        // WebView 主区域
        Expanded(
          child: _buildBody(theme),
        ),
      ],
    );
  }

  Widget _buildBody(ThemeData theme) {
    if (_error != null) {
      return Container(
        alignment: Alignment.center,
        color: theme.colorScheme.surfaceContainerLowest,
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 36, color: Colors.red),
            const SizedBox(height: 8),
            Text('WebView 初始化失败', style: theme.textTheme.titleSmall),
            const SizedBox(height: 4),
            Text(
              '需 Edge WebView2 运行时\n$_error',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    if (!_initialized) {
      return Container(
        alignment: Alignment.center,
        color: theme.colorScheme.surfaceContainerLowest,
        child: const CircularProgressIndicator(),
      );
    }

    return Stack(
      children: [
        Webview(_controller),
        if (_isLoading)
          const Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: LinearProgressIndicator(),
          ),
      ],
    );
  }

  Widget _emptyState(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.public,
              size: 48, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(height: 8),
          Text('未配置网页地址 (config.url)',
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _loadingSub?.cancel();
    _urlSub?.cancel();
    _historySub?.cancel();
    _controller.dispose();
    super.dispose();
  }
}
