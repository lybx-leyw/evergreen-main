import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Collapsible video player panel for 智云课堂 recordings.
///
/// Uses [media_kit] for cross-platform playback (libmpv on desktop,
/// ExoPlayer on Android, AVPlayer on iOS).
/// Collapsible to save screen space when viewing PPT / subtitles.
class VideoPlayerPanel extends StatefulWidget {
  final String videoUrl;
  final String title;

  const VideoPlayerPanel({
    super.key,
    required this.videoUrl,
    this.title = '',
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

  @override
  void initState() {
    super.initState();
    _initPlayer();
  }

  @override
  void dispose() async {
    if (_player != null && widget.videoUrl.isNotEmpty) {
      final pos = await _player!.stream.position.first;
      final key = 'video_progress_${widget.videoUrl.hashCode}';
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(key, pos.inSeconds.toDouble());
      debugPrint('[VideoPlayer] saved position: ${pos.inSeconds}s');
    }
    _player?.dispose();
    super.dispose();
  }

  Future<void> _initPlayer() async {
    debugPrint('[VideoPlayer:D] _initPlayer() URL=${widget.videoUrl}'
        ' UriScheme=${Uri.tryParse(widget.videoUrl)?.scheme ?? "?"}');
    try {
      final player = Player();
      final controller = VideoController(player);

      // Listen for playback state changes
      player.stream.playing.listen((playing) {
        debugPrint('[VideoPlayer:D] playing: $playing');
      });
      player.stream.buffering.listen((buffering) {
        debugPrint('[VideoPlayer:D] buffering: $buffering');
      });
      player.stream.error.listen((error) {
        debugPrint('[VideoPlayer:D] ⛔ Player error event: $error');
        if (mounted) {
          setState(() => _error = error.toString());
        }
      });

      final media = Media(widget.videoUrl);
      debugPrint('[VideoPlayer:D] Media created, opening...');
      await player.open(media);
      debugPrint('[VideoPlayer:D] player.open() completed');

      // 恢复上次播放位置
      if (widget.videoUrl.isNotEmpty) {
        final key = 'video_progress_${widget.videoUrl.hashCode}';
        final prefs = await SharedPreferences.getInstance();
        final saved = prefs.getDouble(key);
        if (saved != null && saved > 0) {
          final seekPos = Duration(seconds: saved.toInt());
          debugPrint('[VideoPlayer] restoring position: ${seekPos.inSeconds}s');
          await player.seek(seekPos);
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
      debugPrint('[VideoPlayer:D] ❌ init failed: $e');
      if (mounted) setState(() => _error = e.toString());
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
                    width: 16, height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
          ),
        ),

        // Expanded video area
        if (_isExpanded && _error == null)
          _buildVideoArea(context),

        if (_isExpanded && _error != null)
          _buildError(context),
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
            child: Video(
              controller: _controller!,
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
