import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/config/app_config.dart';
import '../../../core/storage/settings_service.dart';

/// Settings state.
class SettingsState {
  final Map<String, String?> values;
  final bool isLoading;
  final bool isSaving;
  final String? saveError;

  const SettingsState({
    this.values = const {},
    this.isLoading = false,
    this.isSaving = false,
    this.saveError,
  });

  SettingsState copyWith({
    Map<String, String?>? values,
    bool? isLoading,
    bool? isSaving,
    String? saveError,
  }) {
    return SettingsState(
      values: values ?? this.values,
      isLoading: isLoading ?? this.isLoading,
      isSaving: isSaving ?? this.isSaving,
      saveError: saveError,
    );
  }
}

class SettingsNotifier extends StateNotifier<SettingsState> {
  final SettingsService _service;

  SettingsNotifier(this._service) : super(const SettingsState(isLoading: true));

  Future<void> load() async {
    try {
      final values = await _service.loadAll();
      state = SettingsState(values: values);
    } catch (e) {
      state = SettingsState(saveError: '加载设置失败: $e');
    }
  }

  Future<void> save(String key, String? value) async {
    state = state.copyWith(isSaving: true, saveError: null);
    try {
      await _service.save(key, value);
      final newValues = Map<String, String?>.from(state.values);
      newValues[key] = value;
      state = SettingsState(values: newValues);
    } catch (e) {
      state = state.copyWith(saveError: '保存失败: $e');
    } finally {
      state = state.copyWith(isSaving: false);
    }
  }

  Future<void> saveAll(Map<String, String> settings) async {
    state = state.copyWith(isSaving: true, saveError: null);
    try {
      await _service.saveAll(settings);
      state = SettingsState(values: Map<String, String?>.from(settings));
    } catch (e) {
      state = state.copyWith(saveError: '保存失败: $e');
    } finally {
      state = state.copyWith(isSaving: false);
    }
  }
}

final settingsProvider =
    StateNotifierProvider<SettingsNotifier, SettingsState>((ref) {
  final service = ref.read(settingsServiceProvider);
  final notifier = SettingsNotifier(service);
  // Load settings on creation
  notifier.load();
  return notifier;
});
