import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/dio_client.dart';
import '../../auth/providers/auth_provider.dart';
import '../services/autosign_service.dart';

final autosignServiceProvider = Provider<AutosignService>((ref) {
  final dio = ref.read(dioClientProvider);
  return AutosignService(dio);
});

final autosignRunningProvider = StateProvider<bool>((ref) => false);

/// Whether background autosign (via BackgroundRefresher) is enabled.
/// When set to true, each auto-refresh tick will trigger a rollcall check.
final autosignBackgroundEnabledProvider = StateProvider<bool>((ref) => false);

class AutosignNotifier extends StateNotifier<List<AutosignLogEntry>> {
  final AutosignService _service;
  final Ref _ref;
  StreamSubscription<AutosignLogEntry>? _sub;

  AutosignNotifier(this._service, this._ref) : super([]) {
    _sub = _service.logStream.listen((entry) {
      state = [...state, entry].take(200).toList();
    });
  }

  /// Starts the foreground autosign timer.
  ///
  /// Returns null on success, or an error message string if the user is not
  /// logged in (auth gate).
  String? start() {
    final authState = _ref.read(authProvider);
    if (!authState.isLoggedIn) {
      const msg = '请先登录后再启动自动签到';
      _service.log(msg);
      return msg;
    }
    _service.start();
    return null;
  }

  void stop() {
    _service.stop();
    state = [];
    // Also disable background autosign so it doesn't keep running
    _ref.read(autosignBackgroundEnabledProvider.notifier).state = false;
  }

  @override
  void dispose() {
    _sub?.cancel();
    _service.stop();
    super.dispose();
  }
}

final autosignLogProvider =
    StateNotifierProvider<AutosignNotifier, List<AutosignLogEntry>>((ref) {
  final service = ref.read(autosignServiceProvider);
  return AutosignNotifier(service, ref);
});
