/// HtmlRenderView — HTML 模块内嵌 WebView 渲染。
///
/// 优先加载模块进程 HTTP 端口（如 settings.exe），无端口时从 manifest 生成 HTML。
/// WebView 初始化失败时回退到 Dart 提示页面。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:webview_windows/webview_windows.dart';
import 'html_renderer.dart';
import '../app/service/providers/renderer_providers.dart';
import '../../providers.dart';

/// HTML 模块内嵌渲染视图。
class HtmlRenderView extends ConsumerStatefulWidget {
  final String moduleId;

  const HtmlRenderView({super.key, required this.moduleId});

  @override
  ConsumerState<HtmlRenderView> createState() => _HtmlRenderViewState();
}

class _HtmlRenderViewState extends ConsumerState<HtmlRenderView> {
  final _controller = WebviewController();
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _initWebView();
  }

  Future<void> _initWebView() async {
    try {
      await _controller.initialize();

      // 始终从 manifest JSON 生成 HTML（与 Dart CompositeView 同源）
      await _controller.loadStringContent(_buildHtml());

      if (mounted) setState(() => _loading = false);
    } catch (e) {
      debugPrint('[HtmlRenderView] WebView 初始化失败: $e');
      if (mounted) setState(() { _loading = false; _error = e.toString(); });
    }
  }

  String _buildHtml() {
    final rawJson = ref.read(v2ManifestProvider)[widget.moduleId];
    if (rawJson == null || rawJson.isEmpty) {
      return '<html><body style="background:#0d1117;color:#c9d1d9;display:flex;align-items:center;justify-content:center;height:100vh;font-family:sans-serif"><p>模块 "${widget.moduleId}" 无 manifest 数据</p></body></html>';
    }
    return HtmlRenderer.render(rawJson, embedded: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.language, size: 48, color: Colors.grey),
              const SizedBox(height: 16),
              Text('HTML 模块: ${widget.moduleId}',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              const Text('WebView 渲染不可用（需 Edge WebView2 运行时）',
                  style: TextStyle(color: Colors.grey)),
              const SizedBox(height: 16),
              Text(_error!, style: const TextStyle(fontSize: 11, fontFamily: 'monospace')),
            ],
          ),
        ),
      );
    }
    return SizedBox.expand(child: Webview(_controller));
  }
}
