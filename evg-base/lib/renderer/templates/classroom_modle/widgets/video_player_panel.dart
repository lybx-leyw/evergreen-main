/// 可折叠视频播放面板——基于 media_kit。
///
/// 适配自 `.refer_ui/widget/lib/features/classroom/widgets/video_player_panel.dart`。
/// 关键差异：移除 SharedPreferences 持久化，改用内存状态；无 Riverpod。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

/// 视频播放器面板。
class VideoPlayerPanel extends StatefulWidget {
  final String? videoUrl;
  /// 视频路径解析函数（相对路径 → 绝对文件路径）。
  final String Function(String raw)? resolvePath;
  /// 远程视频所需的请求头（如智云课堂录播的登录态 Cookie：{name: value}）。
  /// 仅对 http/https 地址生效，本地文件忽略。
  final Map<String, String>? httpHeaders;

  const VideoPlayerPanel({
    super.key,
    this.videoUrl,
    this.resolvePath,
    this.httpHeaders,
  });

  @override
  State<VideoPlayerPanel> createState() => _VideoPlayerPanelState();
}

class _VideoPlayerPanelState extends State<VideoPlayerPanel> {
  Player? _player;
  VideoController? _videoCtrl;
  bool _expanded = false;
  bool _initialized = false;
  bool _loading = true;
  bool _disposed = false;
  String? _error;
  // 诊断订阅：捕获 media_kit 的加载错误与 mpv 内部日志，避免「静默黑屏」。
  StreamSubscription<String>? _errSub;
  StreamSubscription<dynamic>? _logSub;

  @override
  void initState() {
    super.initState();
    // 关键修复：原实现用 build 内的「懒初始化」守卫 `!_initialized && !_loading`，
    // 但 _loading 初始值被误设为 true，导致该守卫恒为 false → _init 永远不被调用 →
    // 播放器始终未初始化，点击「播放录播」折叠条无任何反应（UI 无任何变化）。
    // 改为在 initState 直接初始化（对齐 .refer_ui 参考实现）。_loading 初始 true
    // 仅用于在初始化完成前显示加载圈。
    final url = widget.videoUrl;
    if (url != null && url.isNotEmpty) {
      // 仅对本地相对路径做插件路径解析；远程播放地址（http/https）必须原样交给
      // media_kit——否则 resolvePluginAssetPath 会把 URL 拼成垃圾文件系统路径，
      // 导致视频无法打开（「视频无法播放」）。
      final isRemote =
          url.startsWith('http://') || url.startsWith('https://');
      final resolved = (!isRemote && widget.resolvePath != null)
          ? widget.resolvePath!(url)
          : url;
      _init(resolved);
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _safeDisposePlayer();
    super.dispose();
  }

  /// 安全释放播放器：避免重复 dispose / 在已卸载时访问 State。
  void _safeDisposePlayer() {
    try {
      _errSub?.cancel();
      _logSub?.cancel();
      _videoCtrl = null;
      _player?.dispose();
    } catch (_) {
      // 释放失败不致命，忽略。
    }
    _errSub = null;
    _logSub = null;
    _player = null;
  }

  Future<void> _init(String url) async {
    if (_initialized || _disposed) return;
    try {
      MediaKit.ensureInitialized();
      _player ??= Player();
      // 捕获 media_kit 的加载错误与 mpv 内部日志——视频拉不到流（链接失效 /
      // 需鉴权 / 编码不支持）时，native 纹理 rect 始终停在 0x0，Flutter 侧只会
      // 显示 Container 的黑色 fill，属于「静默黑屏」。把这些信号打出来才能定位。
      _errSub = _player!.stream.error.listen((e) {
        debugPrint('[VideoPlayerPanel] player.error: $e');
        // 诊断增强：把 media_kit 加载/解码错误**上屏**，不再只打日志。
        // 之前 HEVC/H.265 这类「无 error 事件、仅 width=null」的失败是静默黑屏，
        // 与本文件顶部「黑屏必须可诊断」原则相悖。这里让真实 error 也能触发错误 UI。
        if (!mounted || _disposed) return;
        if (_error == null) {
          setState(() {
            _error = '视频解码/加载失败：$e';
          });
        }
      });
      _logSub = _player!.stream.log.listen((e) {
        // e 为 PlayerLog(prefix/level/text)
        debugPrint('[VideoPlayerPanel][mpv] ${e.level}: ${e.text}');
      });
      // 仅对远程地址注入请求头（如 ZJU 课堂录播需要的登录态 Cookie）；本地文件忽略。
      final isRemote = url.startsWith('http://') || url.startsWith('https://');
      final Media media;
      if (isRemote && widget.httpHeaders != null && widget.httpHeaders!.isNotEmpty) {
        final cookie = widget.httpHeaders!
            .entries
            .map((kv) => '${kv.key}=${kv.value}')
            .join('; ');
        media = Media(url, httpHeaders: {'Cookie': cookie});
        debugPrint('[VideoPlayerPanel] 远程地址注入 Cookie 头（${widget.httpHeaders!.length} 项），打开: $url');
      } else {
        media = Media(url);
        debugPrint('[VideoPlayerPanel] 打开: $url (remote=$isRemote, hasCookie=${widget.httpHeaders?.isNotEmpty ?? false})');
      }
      // 必须 play:true：media_kit 在 Windows 上对「暂停打开」的视频不会解码首帧，
      // 纹理停留 1px 黑色占位层（video_texture.dart rect<=1px 分支）→ 黑屏。
      await _player!.open(media, play: true);
      if (!mounted || _disposed) return;
      _videoCtrl = VideoController(_player!);
      if (!mounted || _disposed) {
        _safeDisposePlayer();
        return;
      }
      // 探针：2 秒后若仍无视频尺寸，说明源未解出帧（链接失效/需鉴权/编码不支持）。
      // 此时 native 纹理 rect 停在 0x0，UI 只会显示黑色 fill。
      // 诊断增强：**本地源**已 open 却 width==null/0 → 编码不被内置 libmpv 解码
      // （如 HEVC/H.265）→ 置 _error 上屏，把「静默黑屏」变可操作提示。
      // 仅对本地源做此激进判定：远程流首帧可能 >2s 才到达，避免误报。
      Future.delayed(const Duration(seconds: 2), () {
        if (_disposed || _player == null) return;
        final s = _player!.state;
        debugPrint('[VideoPlayerPanel] probe@2s playing=${s.playing} '
            'w=${s.width} h=${s.height} dur=${s.duration} '
            'pos=${s.position} buf=${s.buffer} buffering=${s.buffering}');
        if (!isRemote && (s.width == null || s.width == 0)) {
          if (!mounted || _disposed) return;
          setState(() {
            _error =
                '当前播放器不支持该视频编码（疑似 HEVC/H.265 等不被内置解码器支持），'
                '请转码为 H.264 后重试。\n源：$url';
          });
          // 无视频帧却可能在放音频，暂停避免黑屏时背景音突兀。
          _player?.pause();
        }
      });
      setState(() {
        _initialized = true;
        _loading = false;
        _expanded = true;
      });
    } catch (e) {
      if (!mounted || _disposed) return;
      debugPrint('[VideoPlayerPanel] init 异常: $e');
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final url = widget.videoUrl;
    if (url == null || url.isEmpty) {
      return _noVideoState(context);
    }

    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 折叠/展开切换条
        InkWell(
          onTap: () => setState(() => _expanded = !_expanded),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            color: theme.colorScheme.surfaceContainerLow,
            child: Row(
              children: [
                Icon(
                  _expanded ? Icons.expand_less : Icons.play_circle_outline,
                  size: 18,
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    _expanded ? '收起视频' : '播放录播',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
                if (_loading)
                  const SizedBox(
                      width: 16, height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2)),
                if (_error != null)
                  Icon(Icons.error, size: 16, color: theme.colorScheme.error),
              ],
            ),
          ),
        ),
        // 错误状态
        if (_error != null && _expanded)
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                const Icon(Icons.videocam_off, size: 36, color: Colors.red),
                const SizedBox(height: 4),
                Text(
                  _error!.length > 80
                      ? '${_error!.substring(0, 80)}...'
                      : _error!,
                  style: theme.textTheme.bodySmall,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                ElevatedButton.icon(
                  onPressed: () {
                    // 彻底重置：先释放旧播放器，下一帧用全新 Player 重新打开，
                    // 避免复用处于错误态的旧实例导致重试仍失败。
                    _safeDisposePlayer();
                    setState(() {
                      _error = null;
                      _initialized = false;
                      _loading = true;
                      _expanded = true;
                    });
                    final url = widget.videoUrl;
                    if (url != null && url.isNotEmpty) {
                      final isRemote =
                          url.startsWith('http://') || url.startsWith('https://');
                      final resolved = (!isRemote && widget.resolvePath != null)
                          ? widget.resolvePath!(url)
                          : url;
                      _init(resolved);
                    }
                  },
                  icon: const Icon(Icons.refresh, size: 16),
                  label: const Text('重试'),
                ),
              ],
            ),
          ),
        // 视频区域：MaterialVideoControls 提供进度条（主体）+ 全屏按钮；
        // 但 media_kit 1.3.1 无公开的倍速/音量按钮类，默认 bottomButtonBar 仅
        // [进度, Spacer, 全屏]。故用 MaterialVideoControlsTheme 注入 normal 与
        // fullscreen 两个主题，并在底部栏追加自定义 _VolumeButton / _SpeedButton
        // （通过 VideoStateInheritedWidget 拿到 player 调用 setVolume/setRate）。
        if (_expanded && _initialized && _error == null && _videoCtrl != null) ...[
          ClipRect(
            child: LayoutBuilder(
              builder: (context, constraints) {
                // 按宽度比值自适应高度（16:9），避免绝对高度在不同宽度下变形/留白。
                // 用 LayoutBuilder+SizedBox 而非 AspectRatio：media_kit 的 Video 在
                // AspectRatio 的 tight 约束下偶发纹理尺寸为 0（首帧占位黑层常驻，见
                // media_kit_video video_texture.dart rect<=1px 分支），导致整块黑屏；
                // 回到与之前可正常显示的 SizedBox 等价形态，仅高度改为比值。
                // 关键修复：必须给 Video 显式非零宽高，否则 media_kit 纹理 rect=0x0
                // （日志 VideoOutput.Resize rect:{height:0,width:0}）落到黑色占位分支。
                // 宽度优先级：父级有限宽 → MediaQuery 视口宽 → 兜底 640。
                double w = 640.0;
                if (constraints.maxWidth.isFinite && constraints.maxWidth > 0) {
                  w = constraints.maxWidth;
                } else {
                  final mq = MediaQuery.maybeOf(context)?.size.width ?? 0;
                  if (mq > 0) w = mq;
                }
                final videoHeight = w * 9 / 16;
                debugPrint('[VideoPlayerPanel] 视频区域尺寸 w=$w h=$videoHeight');
                return SizedBox(
                  width: w,
                  height: videoHeight,
                  child: MaterialVideoControlsTheme(
                    normal: MaterialVideoControlsThemeData(
                      bottomButtonBar: [
                        MaterialPositionIndicator(),
                        Spacer(),
                        _VolumeButton(),
                        _SpeedButton(),
                        MaterialFullscreenButton(),
                      ],
                    ),
                    fullscreen: MaterialVideoControlsThemeData(
                      bottomButtonBar: [
                        MaterialPositionIndicator(),
                        Spacer(),
                        _VolumeButton(),
                        _SpeedButton(),
                        MaterialFullscreenButton(),
                      ],
                    ),
                    child: Video(
                      // 直接给 Video 显式宽高：即便父级 SizedBox 偶发塌缩，
                      // media_kit 也能拿到非零尺寸解码首帧，避免 0x0 黑屏。
                      width: w,
                      height: videoHeight,
                      controller: _videoCtrl!,
                      controls: MaterialVideoControls,
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ],
    );
  }

  Widget _noVideoState(BuildContext context) => Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Icon(Icons.videocam_off, size: 16,
                color: Theme.of(context).colorScheme.onSurfaceVariant),
            const SizedBox(width: 6),
            Text('无视频',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ],
        ),
      );
}

/// 倍速按钮：借 MaterialVideoControls 的 bottomButtonBar 注入。
/// 通过 [VideoStateInheritedWidget] 拿到 [Player] 后调用 [Player.setRate]。
class _SpeedButton extends StatelessWidget {
  const _SpeedButton();

  static const List<double> _rates = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0];

  @override
  Widget build(BuildContext context) {
    final player = VideoStateInheritedWidget.of(context).state.widget.controller.player;
    return PopupMenuButton<double>(
      icon: const Icon(Icons.speed, color: Color(0xFFFFFFFF), size: 24.0),
      tooltip: '倍速',
      initialValue: 1.0,
      itemBuilder: (ctx) => _rates
          .map((r) => PopupMenuItem<double>(
                value: r,
                child: Text(
                    '${r.toStringAsFixed(r == r.roundToDouble() ? 0 : 2)}x'),
              ))
          .toList(),
      onSelected: (r) => player.setRate(r),
    );
  }
}

/// 音量按钮：借 MaterialVideoControls 的 bottomButtonBar 注入。
/// 通过 [VideoStateInheritedWidget] 拿到 [Player]，弹出滑块调用 [Player.setVolume]。
class _VolumeButton extends StatelessWidget {
  const _VolumeButton();

  @override
  Widget build(BuildContext context) {
    final player = VideoStateInheritedWidget.of(context).state.widget.controller.player;
    return StreamBuilder<double>(
      stream: player.stream.volume,
      builder: (ctx, snapshot) {
        final vol = (snapshot.data ?? 100.0).clamp(0.0, 100.0);
        final icon = vol == 0
            ? Icons.volume_off
            : vol < 50
                ? Icons.volume_down
                : Icons.volume_up;
        return PopupMenuButton<double>(
          icon: Icon(icon, color: const Color(0xFFFFFFFF), size: 24.0),
          tooltip: '音量',
          itemBuilder: (ctx) => [
            PopupMenuItem<double>(
              enabled: false,
              child: SizedBox(
                width: 220,
                child: Row(
                  children: [
                    const Icon(Icons.volume_up, size: 18),
                    Expanded(
                      child: Slider(
                        value: vol,
                        min: 0,
                        max: 100,
                        onChanged: (v) => player.setVolume(v),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
