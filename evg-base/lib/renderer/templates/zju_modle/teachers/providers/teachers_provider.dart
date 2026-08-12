/// 查老师 Riverpod providers（zju / teachers）。
///
/// B3-teachers（2026-08-13）自参考工程
/// `cp_evergreen_push/lib/features/teachers/providers/teachers_provider.dart`
/// 移植，改造点：
/// - provider 名加 `zju` 前缀（规划 §5.6，避免与全局 providers 冲突）；
/// - 不再复用 SSO `zjuDioClientProvider`（查老师为公网搜索，无需浙大凭证/
///   cookie 会话）——独立裸 Dio，避免触发 CAS 登录；
/// - 模型类换 `ZjuTeacher*`（shared/models/zju_teacher.dart）。
library;

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:evergreen_base/core/log.dart';

import '../../shared/models/zju_teacher.dart';
import '../services/chalaoshi_service.dart';

/// 查老师服务单例（独立裸 Dio：chalaoshi.top 公网，无 SSO 依赖）。
final zjuChalaoshiServiceProvider = Provider<ZjuChalaoshiService>((ref) {
  return ZjuChalaoshiService(Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 10),
  )));
});

/// 教师搜索（按姓名/拼音/拼音缩写；在线优先，失败本地秒回）。
final zjuTeacherSearchProvider =
    FutureProvider.family<List<ZjuTeacherResult>, String>((ref, name) async {
  final service = ref.read(zjuChalaoshiServiceProvider);
  try {
    return await service.search(name);
  } catch (e) {
    Log().warn('[teachers] search failed: $name', error: e);
    return [];
  }
});

/// 教师详情（本地秒回 + 后台在线刷新）。
final zjuTeacherDetailProvider = FutureProvider.family<ZjuTeacherDetail?,
    ({int id, String name})>((ref, params) async {
  final service = ref.read(zjuChalaoshiServiceProvider);
  return service.getDetail(params.id, name: params.name);
});
