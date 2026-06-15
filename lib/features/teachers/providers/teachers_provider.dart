import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/log.dart';
import '../../../core/network/dio_client.dart';
import '../services/chalaoshi_service.dart';

final chalaoshiServiceProvider = Provider<ChalaoshiService>((ref) {
  final dio = ref.read(dioClientProvider);
  return ChalaoshiService(dio);
});

final teacherSearchProvider =
    FutureProvider.family<List<TeacherResult>, String>((ref, name) async {
  final service = ref.read(chalaoshiServiceProvider);
  try {
    return await service.search(name);
  } catch (e) {
    Log().warn('Chalaoshi search failed', error: e);
    return [];
  }
});

final teacherDetailProvider =
    FutureProvider.family<TeacherDetail?, ({int id, String name})>((ref, params) async {
  final service = ref.read(chalaoshiServiceProvider);
  return service.getDetail(params.id, name: params.name);
});
