import 'dart:async';
import 'package:dio/dio.dart';
import '../../../core/log.dart';

/// Auto sign-in service — monitors for rollcall events and auto-responds.
class AutosignService {
  final Dio _dio;
  Timer? _timer;
  bool _running = false;
  final _logController = StreamController<AutosignLogEntry>.broadcast();

  Stream<AutosignLogEntry> get logStream => _logController.stream;
  bool get isRunning => _running;

  AutosignService(this._dio);

  void start() {
    if (_running) return;
    _running = true;
    _log('自动签到已启动');
    Log().info('Autosign started');
    _poll();
  }

  void stop() {
    _running = false;
    _timer?.cancel();
    _timer = null;
    _log('自动签到已停止');
    Log().info('Autosign stopped');
  }

  void _poll() {
    if (!_running) return;
    _timer = Timer(const Duration(seconds: 4), () async {
      await _checkRollcalls();
      if (_running) _poll();
    });
  }

  Future<void> _checkRollcalls() async {
    try {
      final res =
          await _dio.get('https://courses.zju.edu.cn/api/radar/rollcalls');
      final data = res.data;
      if (data is! Map || data['rollcalls'] == null) return;

      final rollcalls = data['rollcalls'] as List;
      if (rollcalls.isEmpty) {
        _log('未发现签到');
        return;
      }

      _log('发现 ${rollcalls.length} 个签到');
      for (final rc in rollcalls) {
        if (rc is! Map) continue;
        final rid = rc['rollcall_id'];
        final title = rc['title']?.toString() ?? '';
        if (rc['status'] == 'on_call_fine') {
          _log('  #$rid 已签到: $title');
          continue;
        }
        _log('  📌 正在应答签到 #$rid: $title');
        final ok = await _tryRadarSignIn(rid as int);
        _log(ok ? '  ✅ 签到成功 #$rid' : '  ❌ 签到失败 #$rid');
      }
    } catch (e) {
      Log().warn('Autosign poll error', error: e);
      _log('签到检测错误: $e');
    }
  }

  Future<bool> _tryRadarSignIn(int rid) async {
    const locations = [
      [120.089136, 30.302331],
      [120.085042, 30.30173],
      [120.077135, 30.305142],
    ];
    for (final loc in locations) {
      try {
        final res = await _dio.put(
          'https://courses.zju.edu.cn/api/rollcall/$rid/answer?api_version=1.1.2',
          data: {
            'deviceId': 'flutter-${DateTime.now().millisecondsSinceEpoch}',
            'latitude': loc[1],
            'longitude': loc[0],
            'accuracy': 68
          },
        );
        if (res.data is Map && res.data['status_name'] == 'on_call_fine') {
          return true;
        }
      } catch (_) {}
    }
    return false;
  }

  void _log(String message) {
    _logController
        .add(AutosignLogEntry(time: DateTime.now(), message: message));
  }

  void dispose() {
    stop();
    _logController.close();
  }
}

class AutosignLogEntry {
  final DateTime time;
  final String message;
  const AutosignLogEntry({required this.time, required this.message});
}
