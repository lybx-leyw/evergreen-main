/// DSH-mode 主视图——端口配置 + WebView 承载 DSH Web UI。
///
/// 架构：用户自装 DSH（`npx @deepseek-ai/dsh web`，默认 127.0.0.1:3080），
/// 本视图要求用户填写端口号，用 WebView2 承载 DSH Web UI。
///
/// 顶部工具栏：端口输入框 + 「连接」按钮（加载/重载）；主体为 WebView。
/// 端口号持久化到 SharedPreferences（key `dsh_port`，默认 3080）。
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webview_windows/webview_windows.dart';
import 'package:evergreen_base/core/utils/greenix_path.dart';
import 'package:evergreen_base/providers.dart';
import 'package:evergreen_base/renderer/templates/html_modle/core_api_discovery.dart';

import 'dsh_injector.dart';

/// DSH 端口号持久化 key。
const String kDshPortPrefsKey = 'dsh_port';

/// DSH 默认端口（`dsh web` 默认监听 127.0.0.1:3080）。
const int kDshDefaultPort = 3080;

/// DSH-mode 主视图。
class DshModleView extends ConsumerStatefulWidget {
  final dynamic descriptor;

  const DshModleView({super.key, this.descriptor});

  @override
  ConsumerState<DshModleView> createState() => _DshModleViewState();
}

class _DshModleViewState extends ConsumerState<DshModleView> {
  final _portCtrl = TextEditingController();
  int _port = kDshDefaultPort;
  String _currentUrl = '';

  // Windows：WebView2 承载 DSH Web UI。
  WebviewController? _controller;
  bool _initialized = false;
  String? _initError;

  // 文件 watcher（主方案兜底）：周期扫描 plugins 目录注册新数据源。
  Timer? _watchTimer;

  bool get _isAndroid => defaultTargetPlatform == TargetPlatform.android;

  @override
  void initState() {
    super.initState();
    _loadPrefs();
    _startWatcher();
  }

  /// 启动文件 watcher（仅 Windows）：每 3s 扫描一次新数据源。
  void _startWatcher() {
    if (_isAndroid) return;
    _watchTimer?.cancel();
    _watchTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      _rescanOnce();
    });
  }

  /// 单次扫描：发现新数据源即热注册。
  void _rescanOnce() {
    try {
      final pluginsDir = resolvePluginsRoot();
      final orch = ref.read(dataOrchestratorProvider);
      final newly = rescanDataSources(pluginsDir: pluginsDir, orch: orch);
      if (newly.isNotEmpty) {
        debugPrint('[DshModleView] 热注册新数据源: $newly');
      }
    } catch (e) {
      // orchestrator 未注入 / 目录缺失等：静默忽略，下次轮询重试。
    }
  }

  Future<void> _loadPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getInt(kDshPortPrefsKey) ?? kDshDefaultPort;
      if (!mounted) return;
      setState(() {
        _port = saved;
        _portCtrl.text = '$saved';
      });
    } catch (_) {
      // 无存储环境（测试）兜底默认端口。
      if (mounted) _portCtrl.text = '$_port';
    }
  }

  Future<void> _savePort(int port) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(kDshPortPrefsKey, port);
    } catch (_) {
      // 持久化失败静默降级（本次会话内仍生效）。
    }
  }

  /// 解析端口号：非法/越界返回 null。
  int? _parsePort(String text) {
    final p = int.tryParse(text.trim());
    if (p == null || p < 1 || p > 65535) return null;
    return p;
  }

  /// 连接（或重连）到 DSH：注入 evergreen 能力 + 加载 WebView。
  void _connect() {
    final port = _parsePort(_portCtrl.text);
    if (port == null) {
      _showSnack('端口号无效，请输入 1-65535 之间的整数');
      return;
    }
    setState(() => _port = port);
    _savePort(port);
    _injectEvergreen();
    _loadUrl();
  }

  /// 注入 evergreen 能力到用户 DSH home（路径契约 + preset + skill + tool）。
  void _injectEvergreen() {
    if (_isAndroid) return;
    try {
      final pluginsDir = resolvePluginsRoot();
      final dataPort = coreApiDiscovery.portOf(CoreService.data) ?? 0;
      final scraperPort = _readScraperBridgePort();
      final projectRoot = resolveProjectRoot() ?? Directory.current.path;
      final result = injectEvergreen(
        pluginsDir: pluginsDir,
        dataHttpPort: dataPort,
        scraperBridgePort: scraperPort,
        projectRoot: projectRoot,
      );
      _showSnack(result.allOk
          ? '已注入 Evergreen 能力（preset/skill/tool/bridge）'
          : '注入部分失败（bridge=${result.bridgeOk} preset=${result.presetOk} '
              'skill=${result.skillOk} tool=${result.toolOk}）');
    } catch (e) {
      _showSnack('注入 Evergreen 能力失败: $e');
    }
  }

  /// 读 `.scraper_bridge_port` 端口文件（ScraperBridgeServer 常驻写入）。
  int _readScraperBridgePort() {
    try {
      final root = resolveProjectRoot() ?? Directory.current.path;
      final raw = File('$root/.scraper_bridge_port').readAsStringSync().trim();
      return int.tryParse(raw) ?? 0;
    } catch (_) {
      return 0;
    }
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }

  /// 构建 DSH Web UI 地址并加载。
  void _loadUrl() {
    if (_isAndroid) return;
    final url = 'http://127.0.0.1:$_port';
    setState(() => _currentUrl = url);
    _initWebView();
  }

  /// 初始化 WebView2 并加载 DSH Web UI。
  ///
  /// 注意：`WebviewController.initializeEnvironment` 已由 AppBootstrap 在
  /// 启动早期统一初始化，这里只创建/复用 controller 并 loadUrl。
  Future<void> _initWebView() async {
    if (_isAndroid) return;
    try {
      if (_controller == null) {
        _controller = WebviewController();
        await _controller!.initialize();
      }
      if (!mounted) return;
      setState(() {
        _initialized = true;
        _initError = null;
      });
      await _controller!.loadUrl(_currentUrl);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _initError = e.toString();
        _initialized = false;
      });
    }
  }

  @override
  void dispose() {
    _watchTimer?.cancel();
    _portCtrl.dispose();
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isAndroid) {
      return const _AndroidPlaceholder();
    }

    return Column(
      children: [
        _buildToolbar(),
        const Divider(height: 1),
        Expanded(child: _buildWebViewArea()),
      ],
    );
  }

  /// 顶部工具栏：端口输入 + 连接按钮。
  Widget _buildToolbar() {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Icon(Icons.hub_outlined, size: 20, color: scheme.primary),
          const SizedBox(width: 8),
          Text('DSH 端口', style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(width: 12),
          SizedBox(
            width: 120,
            child: TextField(
              controller: _portCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                isDense: true,
                border: OutlineInputBorder(),
                hintText: '3080',
                prefixText: '127.0.0.1:',
                prefixStyle: TextStyle(fontSize: 12),
              ),
              onSubmitted: (_) => _connect(),
            ),
          ),
          const SizedBox(width: 12),
          FilledButton.icon(
            onPressed: _connect,
            icon: const Icon(Icons.refresh, size: 18),
            label: const Text('连接'),
          ),
          const Spacer(),
          Text(
            _currentUrl.isEmpty ? '未连接' : _currentUrl,
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  /// WebView 区域（含初始化错误/未连接占位）。
  Widget _buildWebViewArea() {
    if (_initError != null) {
      return _ErrorPlaceholder(message: _initError!);
    }
    if (!_initialized || _controller == null) {
      return const _NotConnectedPlaceholder();
    }
    // WebView2 纹理视图：Webview 组件 + 简单加载态。
    return Stack(
      children: [
        Webview(_controller!),
        // 加载遮罩（loadingState 是 Stream，非 ValueListenable）。
        StreamBuilder<LoadingState>(
          stream: _controller!.loadingState,
          builder: (context, snapshot) {
            if (snapshot.data == LoadingState.loading) {
              return const Center(child: CircularProgressIndicator());
            }
            return const SizedBox.shrink();
          },
        ),
      ],
    );
  }
}

// ═══════ 占位页 ═══════

/// 安卓占位页——DSH 仅支持 Windows（依赖 WebView2）。
class _AndroidPlaceholder extends StatelessWidget {
  const _AndroidPlaceholder();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.phonelink_lock_outlined, size: 64, color: scheme.primary),
          const SizedBox(height: 16),
          Text(
            'DSH-mode 仅支持 Windows 版',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            'DSH（DeepSeek Harness）依赖 WebView2，'
            '请在 Windows 版 Evergreen 中使用。',
            textAlign: TextAlign.center,
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

/// 未连接占位——提示填写端口并连接。
class _NotConnectedPlaceholder extends StatelessWidget {
  const _NotConnectedPlaceholder();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.hub_outlined, size: 64, color: scheme.primary),
          const SizedBox(height: 16),
          Text('未连接 DSH', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(
            '请确认本地已通过 npx @deepseek-ai/dsh web 启动 DSH，\n'
            '在上方填写端口号后点击「连接」。',
            textAlign: TextAlign.center,
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

/// 初始化错误占位。
class _ErrorPlaceholder extends StatelessWidget {
  final String message;
  const _ErrorPlaceholder({required this.message});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 48, color: scheme.error),
            const SizedBox(height: 12),
            Text('WebView 初始化失败', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}
