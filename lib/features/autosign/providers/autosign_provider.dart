import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/dio_client.dart';
import '../services/autosign_service.dart';

final autosignServiceProvider = Provider<AutosignService>((ref) {
  final dio = ref.read(dioClientProvider);
  return AutosignService(dio);
});

final autosignRunningProvider = StateProvider<bool>((ref) => false);

class AutosignNotifier extends StateNotifier<List<AutosignLogEntry>> {
  final AutosignService _service;
  StreamSubscription<AutosignLogEntry>? _sub;

  AutosignNotifier(this._service) : super([]) {
    _sub = _service.logStream.listen((entry) {
      state = [...state, entry].take(200).toList();
    });
  }

  void start() {
    _service.start();
  }

  void stop() {
    _service.stop();
    state = [];
  }

  @override
  void dispose() {
    _sub?.cancel();
    // AutosignService.dispose() returns void (closes controller).
    _service.stop();
    super.dispose();
  }
}

final autosignLogProvider =
    StateNotifierProvider<AutosignNotifier, List<AutosignLogEntry>>((ref) {
  final service = ref.read(autosignServiceProvider);
  return AutosignNotifier(service);
});
