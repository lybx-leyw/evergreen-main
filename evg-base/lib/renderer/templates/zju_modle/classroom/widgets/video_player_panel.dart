/// 可折叠的视频播放面板（智云课堂录播）。
///
/// B3-classroom（2026-08-12）自参考工程 `cp_evergreen_push/lib/features/
/// classroom/widgets/video_player_panel.dart` 移植（media_kit 跨平台播放）。
/// 保持原样：倍速记忆、进度记忆（shared_preferences）、错误重试。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 可折叠视频播放面板：顶部折叠条 + 展开后视频区 + 控制条。
class VideoPlayerPanel extends StatefulWidget {
  final String videoUrl;
  final String title;

  /// 播放时注入的 HTTP 请求头（如 `Cookie`/`Referer`）——media_kit 的
  /// 播放器进程不携带 Dio cookie jar，智云课堂视频流（CMC 域）必须手动
  /// 注入登录会话，否则 401/403 → 黑屏。
  final Map<String, String>? httpHeaders;

  const VideoPlayerPanel({
    super.key,
    required this.videoUrl,
    this.title = '',
    this.httpHeaders,
  });

  @override
  State<VideoPlayerPanel> createState() => _VideoPlayerPanelState();
}

class _VideoPlayerPanelState extends State<VideoPlayerPanel> {
  Player? _player;
  VideoController? _controller;
  bool _initialized = false;
  bool _isExpanded = false;
  String? _error;
  double _playbackRate = 1.0;
  bool _isPlaying = false;
  StreamSubscription<double>? _rateSub;
  StreamSubscription<bool>? _playingSub;

  @override
  void initState() {
    super.initState();
    _initPlayer();
  }

  @override
  void dispose() async {
    _rateSub?.cancel();
    _playingSub?.cancel();
    if (_player != null && widget.videoUrl.isNotEmpty) {
      try {
        final pos = await _player!.stream.position.first;
        final key = 'video_progress_${widget.videoUrl.hashCode}';
        final prefs = await SharedPreferences.getInstance();
        await prefs.setDouble(key, pos.inSeconds.toDouble());
      } catch (_) {}
    }
    _player?.dispose();
    super.dispose();
  }

  Future<void> _initPlayer() async {
    debugPrint('[VideoPlayer:D] _initPlayer() URL=${widget.videoUrl}'
        ' UriScheme=${Uri.tryParse(widget.videoUrl)?.scheme ?? "?"}'
        ' httpHeaders=${widget.httpHeaders?.keys ?? const {}}');
    // player/controller 提到 try 外：VideoController 构造器内部是 fire-and-forget
    // async（等 postFrame 后调 NativeVideoController.create → VideoOutputManager.Create
    // channel），插件缺失/初始化失败时经 completeError 抛出。若调用方不 await
    // platform.future 消费该错误，会以 unhandled async error 逃逸到全局 zone，
    // 表现为 main.dart zone 打印的 `[BOOT] 未捕获异步异常`（MissingPluginException）。
    Player? player;
    VideoController? controller;
    try {
      player = Player();
      controller = VideoController(player);
      await controller.platform.future;

      _playingSub = player.stream.playing.listen((playing) {
        debugPrint('[VideoPlayer:D] playing: $playing');
        if (mounted) setState(() => _isPlaying = playing);
      });
      player.stream.buffering.listen((buffering) {
        debugPrint('[VideoPlayer:D] buffering: $buffering');
      });
      player.stream.error.listen((error) {
        debugPrint('[VideoPlayer:D] ⛔ Player error event: $error');
        if (mounted) setState(() => _error = error.toString());
      });
      _rateSub = player.stream.rate.listen((rate) {
        if (mounted) setState(() => _playbackRate = rate);
      });

      final media = Media(
        widget.videoUrl,
        httpHeaders: widget.httpHeaders ?? const {},
      );
      debugPrint('[VideoPlayer:D] Media created, opening...');
      await player.open(media);
      debugPrint('[VideoPlayer:D] player.open() completed');

      // 恢复上次播放位置
      if (widget.videoUrl.isNotEmpty) {
        final key = 'video_progress_${widget.videoUrl.hashCode}';
        final prefs = await SharedPreferences.getInstance();
        final saved = prefs.getDouble(key);
        if (saved != null && saved > 0) {
          await player.seek(Duration(seconds: saved.toInt()));
        }
      }

      // 恢复全局偏好倍速
      if (widget.videoUrl.isNotEmpty) {
        final prefs = await SharedPreferences.getInstance();
        final savedRate = prefs.getDouble('video_playback_rate');
        if (savedRate != null && savedRate > 0) {
          _playbackRate = savedRate;
          await player.setRate(savedRate);
        }
      }

      if (mounted) {
        setState(() {
          _player = player;
          _controller = controller;
          _initialized = true;
          _error = null;
        });
      }
    } catch (e) {
      debugPrint('[VideoPlayer:D] _initPlayer() 异常: $e');
      player?.dispose();
      _player?.dispose();
      _player = null;
      _controller = null;
      if (mounted) setState(() => _error = e.toString());
    }
  }

  /// 设置播放倍速并持久化到全局偏好。
  Future<void> _setPlaybackRate(double rate) async {
    if (_player == null) return;
    await _player!.setRate(rate);
    if (mounted) setState(() => _playbackRate = rate);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('video_playback_rate', rate);
  }

  /// 切换播放/暂停。
  void _togglePlayPause() {
    if (_player == null) return;
    if (_isPlaying) {
      _player!.pause();
    } else {
      _player!.play();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Toggle bar
        InkWell(
          onTap: () => setState(() => _isExpanded = !_isExpanded),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerLow,
              border: Border(
                bottom: BorderSide(
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  _isExpanded ? Icons.expand_less : Icons.play_circle_outline,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  _isExpanded ? '收起视频' : '播放录播',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const Spacer(),
                if (_error != null)
                  const Icon(Icons.error_outline, size: 16, color: Colors.red),
                if (!_initialized && _error == null)
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
          ),
        ),
        if (_isExpanded && _error == null) _buildVideoArea(context),
        if (_isExpanded && _error != null) _buildError(context),
      ],
    );
  }

  Widget _buildVideoArea(BuildContext context) {
    if (_controller == null) {
      return const SizedBox(
        height: 200,
        child: Center(child: CircularProgressIndicator()),
      );
    }
    return Container(
      color: Colors.black,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: double.infinity,
            height: 300,
            child: Video(controller: _controller!),
          ),
          _buildControlBar(context),
        ],
      ),
    );
  }

  Widget _buildControlBar(BuildContext context) {
    const allSpeeds = [0.25, 0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0, 2.5, 3.0];
    const quickSpeeds = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0];
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.grey[900],
        border: Border(top: BorderSide(color: Colors.grey[800]!)),
      ),
      child: Row(
        children: [
          // Backward 10s
          IconButton(
            icon: const Icon(Icons.replay_10, color: Colors.white70, size: 20),
            onPressed: () {
              if (_player != null) {
                _player!.stream.position.first.then((pos) {
                  final target = pos - const Duration(seconds: 10);
                  _player!.seek(target < Duration.zero ? Duration.zero : target);
                });
              }
            },
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            splashRadius: 18,
            tooltip: '后退 10 秒',
          ),
          // Play / Pause
          IconButton(
            icon: Icon(
              _isPlaying ? Icons.pause : Icons.play_arrow,
              color: Colors.white70,
              size: 20,
            ),
            onPressed: _togglePlayPause,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            splashRadius: 18,
            tooltip: _isPlaying ? '暂停' : '播放',
          ),
          // Forward 10s
          IconButton(
            icon: const Icon(Icons.forward_10, color: Colors.white70, size: 20),
            onPressed: () {
              if (_player != null) {
                _player!.stream.position.first.then((pos) {
                  _player!.seek(pos + const Duration(seconds: 10));
                });
              }
            },
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            splashRadius: 18,
            tooltip: '快进 10 秒',
          ),
          const SizedBox(width: 4),
          // Quick speed chips
          ...quickSpeeds.map((speed) {
            final isActive = (_playbackRate - speed).abs() < 0.01;
            return Padding(
              padding: const EdgeInsets.only(right: 4),
              child: InkWell(
                borderRadius: BorderRadius.circular(4),
                onTap: () => _setPlaybackRate(speed),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: isActive
                        ? theme.colorScheme.primary
                        : Colors.grey[800],
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '${speed}x',
                    style: TextStyle(
                      color: isActive ? Colors.white : Colors.white70,
                      fontSize: 12,
                      fontWeight:
                          isActive ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                ),
              ),
            );
          }),
          // More speeds
          PopupMenuButton<double>(
            icon: const Icon(Icons.more_horiz, color: Colors.white70, size: 20),
            tooltip: '更多倍速',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            splashRadius: 16,
            offset: const Offset(0, -300),
            color: Colors.grey[850],
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            initialValue: _playbackRate,
            onSelected: (rate) => _setPlaybackRate(rate),
            itemBuilder: (_) => allSpeeds.map((speed) {
              final isActive = (_playbackRate - speed).abs() < 0.01;
              return PopupMenuItem<double>(
                value: speed,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (isActive)
                      Icon(Icons.check,
                          size: 16, color: theme.colorScheme.primary)
                    else
                      const SizedBox(width: 16),
                    const SizedBox(width: 8),
                    Text(
                      '${speed}x',
                      style: TextStyle(
                        color: isActive
                            ? theme.colorScheme.primary
                            : Colors.white70,
                        fontWeight:
                            isActive ? FontWeight.bold : FontWeight.normal,
                        fontSize: 13,
                      ),
                    ),
                    if (speed == 1.0)
                      Padding(
                        padding: const EdgeInsets.only(left: 4),
                        child: Text('(正常)',
                            style: TextStyle(
                                color: Colors.grey[500], fontSize: 11)),
                      ),
                  ],
                ),
              );
            }).toList(),
          ),
          const Spacer(),
          // Current rate indicator
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: Colors.grey[800],
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              '${_playbackRate}x',
              style: TextStyle(
                color: _playbackRate != 1.0
                    ? theme.colorScheme.primary
                    : Colors.white70,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildError(BuildContext context) {
    return Container(
      height: 200,
      color: Colors.grey[900],
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.videocam_off, size: 48, color: Colors.grey),
            const SizedBox(height: 8),
            const Text('视频加载失败', style: TextStyle(color: Colors.grey)),
            const SizedBox(height: 4),
            Text(
              _error!.length > 80
                  ? '${_error!.substring(0, 80)}...'
                  : _error!,
              style: const TextStyle(color: Colors.grey, fontSize: 11),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () {
                setState(() {
                  _error = null;
                  _initialized = false;
                  _player?.dispose();
                  _player = null;
                  _controller = null;
                  _initPlayer();
                });
              },
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('重试'),
            ),
          ],
        ),
      ),
    );
  }
}
