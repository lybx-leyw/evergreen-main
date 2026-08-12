/// 查老师服务——本地 JSON 数据集 + 逐条在线更新（zju / teachers）。
///
/// B3-teachers（2026-08-13）自参考工程
/// `cp_evergreen_push/lib/features/teachers/services/chalaoshi_service.dart`
/// 移植，改造点：
/// - 类名/模型加 `Zju` 前缀（规划 §5.6），模型迁至 `shared/models/zju_teacher.dart`；
/// - 移除 `.lazuli` 目录兜底（参考工程私有路径，evg-base 无此目录）；
/// - 新增 [loadDatasetStats] 供数据中枢 `zju_teachers` fetcher 缓存数据集统计；
/// - 新增 [injectDataset]（测试注入完整数据集，避免单测依赖 1.5MB asset）。
///
/// 策略（与参考一致）：
/// 1. 首次加载读取 assets/data/teacher_ratings.json（完整数据集，1.5MB）
/// 2. 搜索时先在本地数据中匹配，秒出结果
/// 3. 查到结果后，后台逐条查询在线评分，成功则替换本地数据
/// 4. 在线查失败直接用本地数据，不受网络影响
library;

import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import 'package:evergreen_base/core/log.dart';

import '../../shared/models/zju_teacher.dart';

/// chalaoshi.top 搜索页（http；在线解析仅作加分项，失败走本地）。
const String kChalaoshiSearchUrl = 'http://chalaoshi.top/';

/// 内置完整数据集 asset 路径（pubspec 声明于 flutter.assets）。
const String kTeacherRatingsAsset = 'assets/data/teacher_ratings.json';

class ZjuChalaoshiService {
  final Dio _dio;
  ZjuChalaoshiService(this._dio);

  ZjuTeacherDataset? _cache;
  bool _loaded = false;
  final Set<int> _updatingIds = {}; // 正在更新的教师 ID

  /// 从 asset 或本地缓存文件加载完整数据集。
  Future<void> _loadLocal() async {
    if (_loaded) return;
    Log().debug('[teachers] loading local dataset');

    late String content;
    // 1) Bundled asset（全平台可用，无需 package 前缀）
    try {
      content = await rootBundle.loadString(kTeacherRatingsAsset);
    } catch (_) {
      // 2) 上次在线更新写回的缓存副本（app 文档目录）
      try {
        final cacheFile = await _getCacheFile();
        if (await cacheFile.exists()) {
          content = await cacheFile.readAsString();
          Log().info('[teachers] loaded from cache file');
        } else {
          Log().warn('[teachers] local data file not found');
          _loaded = true;
          return;
        }
      } catch (e) {
        Log().warn('[teachers] data unavailable', error: e);
        _loaded = true;
        return;
      }
    }

    try {
      _parseDataset(content);
      _loaded = true;
      Log().info(
          '[teachers] loaded ${_cache!.teachers.length} teachers, '
          '${_cache!.colleges.length} colleges');
    } catch (e) {
      Log().warn('[teachers] dataset parse failed', error: e);
      _loaded = true;
    }
  }

  /// 解析数据集 JSON 文本（独立静态路径，便于单测）。
  void _parseDataset(String content) {
    final json = jsonDecode(content) as Map<String, dynamic>;
    _cache = ZjuTeacherDataset.fromJson(json);
  }

  /// 测试注入：直接给定数据集 JSON 文本（跳过 rootBundle/文件 IO）。
  @visibleForTesting
  void injectDataset(String content) {
    _parseDataset(content);
    _loaded = true;
  }

  /// 数据集规模统计（数据中枢 `zju_teachers` fetcher 缓存用）。
  ///
  /// 完整 1.5MB 数据集作为 asset 内置，不进 JSON 缓存；本方法仅返回
  /// 规模统计供状态面板展示「查老师」数据源就绪。
  Future<ZjuTeacherDataset> loadDataset() async {
    await _loadLocal();
    final cache = _cache;
    if (cache == null) {
      throw StateError('查老师数据集缺失——assets/data/teacher_ratings.json 未打包');
    }
    return cache;
  }

  /// 按姓名搜索：先预加载本地数据 → 快速试在线搜索（3s 超时 + 1 次重试）→
  /// 失败则秒回本地结果。
  Future<List<ZjuTeacherResult>> search(String name) async {
    if (name.trim().isEmpty) return [];
    final q = name.trim();

    // 0) 预加载本地数据，确保降级路径立即可用
    try {
      await _loadLocal();
    } catch (_) {}

    // 1) 快速试在线搜索（3s 超时，失败后 500ms 重试一次）
    List<ZjuTeacherResult>? onlineResults;
    for (int attempt = 0; attempt < 2; attempt++) {
      try {
        final encoded = Uri.encodeComponent(q);
        final res = await _dio.get(
          '$kChalaoshiSearchUrl?search_query=$encoded&action=search',
          options: Options(
            receiveTimeout: const Duration(seconds: 3),
            headers: _searchHeaders,
          ),
        );
        final html = res.data.toString();
        if (html.contains('result-item') && html.contains('评分')) {
          onlineResults = _parseOnlineResults(html, q);
          if (onlineResults != null && onlineResults.isNotEmpty) {
            Log().info(
                '[teachers] online attempt $attempt: found '
                '${onlineResults.length} for "$q"');
            _mergeOnlineResults(onlineResults);
            return onlineResults;
          }
        }
        // 有响应但解析不到结果，不再重试
        break;
      } catch (e) {
        if (attempt == 0) {
          Log().info('[teachers] online attempt 0 failed for "$q": $e — retrying...');
          await Future.delayed(const Duration(milliseconds: 500));
        } else {
          Log().info('[teachers] online attempt 1 failed — falling back to local for "$q"');
        }
      }
    }

    // 2) 在线失败 → 秒回本地数据（本地已在步骤 0 预加载好）
    final cache = _cache;
    if (cache == null || cache.teachers.isEmpty) {
      Log().info('[teachers] local data unavailable for "$q"');
      return [];
    }

    final localResults = cache.teachers
        .where((t) =>
            t.name.contains(q) ||
            t.py.contains(q.toLowerCase()) ||
            t.sx.contains(q.toLowerCase()))
        .toList();

    Log().info('[teachers] local: found ${localResults.length} for "$q"');
    return localResults
        .map((t) => ZjuTeacherResult(
              id: t.id,
              name: t.name,
              score: double.tryParse(t.rate),
              college: cache.collegeName(t.collegeId),
              url: 'https://chalaoshi.click/t/${t.id}',
            ))
        .toList();
  }

  /// 在线结果覆盖到本地缓存 + 写回 JSON 文件。
  void _mergeOnlineResults(List<ZjuTeacherResult> online) {
    final cache = _cache;
    if (cache == null) return;
    final updated = [...cache.teachers];
    var changed = false;
    for (final o in online) {
      final idx = updated.indexWhere((t) => t.id == o.id);
      if (idx >= 0 && o.score != null) {
        updated[idx] = ZjuTeacherRecord(
          id: updated[idx].id,
          name: updated[idx].name,
          py: updated[idx].py,
          sx: updated[idx].sx,
          collegeId: updated[idx].collegeId,
          hot: updated[idx].hot,
          rate: o.score!.toStringAsFixed(1),
        );
        changed = true;
      }
    }
    if (changed) {
      _cache = ZjuTeacherDataset(
          colleges: cache.colleges, teachers: updated);
      _saveToLocal();
    }
  }

  /// 解析 chalaoshi.top 在线搜索结果的 HTML。
  List<ZjuTeacherResult> _parseOnlineResults(String html, String query) {
    final results = <ZjuTeacherResult>[];
    final pattern = RegExp(
      r'<div\s+class="result-item">\s*<div>(.*?)</div>\s*<a\s+href="([^"]*teacher_id=(\d+)[^"]*)"[^>]*>.*?</a>\s*</div>',
      dotAll: true,
    );
    for (final m in pattern.allMatches(html)) {
      final nameM = RegExp(r'<strong>(.*?)</strong>').firstMatch(m.group(1)!);
      final name = nameM?.group(1)?.trim() ?? '';
      if (name.isEmpty) continue;
      final scoreM = RegExp(r'评分:\s*([\d.]+)').firstMatch(m.group(1)!);
      results.add(ZjuTeacherResult(
        id: int.tryParse(m.group(3) ?? '') ?? 0,
        name: name,
        score: scoreM != null ? double.tryParse(scoreM.group(1)!) : null,
        url: 'https://chalaoshi.click/t/${m.group(3)}',
        dataSource: 'online',
      ));
    }
    final filtered = results.where((t) => t.name.contains(query)).toList();
    return (filtered.isNotEmpty ? filtered : results).take(15).toList();
  }

  /// 后台更新单个教师的在线评分。
  Future<void> _refreshTeacherOnline(ZjuTeacherRecord teacher) async {
    final encoded = Uri.encodeComponent(teacher.name);
    try {
      Log().info('[teachers] online refresh: ${teacher.name}');
      final res = await _dio.get(
        '$kChalaoshiSearchUrl?search_query=$encoded&action=search',
        options: Options(
          receiveTimeout: const Duration(seconds: 8),
          headers: _searchHeaders,
        ),
      );
      final html = res.data.toString();

      // 从 HTML 解析最新评分
      final scoreMatch = RegExp(r'评分:\s*([\d.]+)').firstMatch(html);
      if (scoreMatch != null) {
        final newRate = scoreMatch.group(1)!;
        final cache = _cache;
        if (cache != null) {
          final updated = [...cache.teachers];
          final idx = updated.indexWhere((t) => t.id == teacher.id);
          if (idx >= 0) {
            updated[idx] = ZjuTeacherRecord(
              id: teacher.id,
              name: teacher.name,
              py: teacher.py,
              sx: teacher.sx,
              collegeId: teacher.collegeId,
              hot: teacher.hot,
              rate: newRate,
            );
            _cache = ZjuTeacherDataset(
                colleges: cache.colleges, teachers: updated);
            _saveToLocal();
            Log().info(
                '[teachers] ${teacher.name} updated: ${teacher.rate} → $newRate');
          }
        }
      }
    } catch (e) {
      Log().info('[teachers] ${teacher.name} online refresh failed: $e');
    } finally {
      _updatingIds.remove(teacher.id);
    }
  }

  /// 获取缓存文件路径（app 文档目录下，全平台可用）。
  Future<File> _getCacheFile() async {
    final appDir = await getApplicationDocumentsDirectory();
    return File('${appDir.path}${Platform.pathSeparator}teacher_ratings.json');
  }

  /// 将更新写回本地缓存文件（app 文档目录下，全平台可用）。
  Future<void> _saveToLocal() async {
    final cache = _cache;
    if (cache == null) return;
    try {
      final file = await _getCacheFile();
      await file.writeAsString(jsonEncode(cache.toJson()));
      Log().info('[teachers] saved to local');
    } catch (e) {
      Log().info('[teachers] save failed: $e');
    }
  }

  /// 教师详情：本地秒回（不阻塞 UI）+ 后台异步查在线评分。
  Future<ZjuTeacherDetail?> getDetail(int teacherId, {String name = ''}) async {
    await _loadLocal();
    final cache = _cache;
    if (cache == null) return null;

    // 1) 本地秒回
    ZjuTeacherDetail? fromLocal;
    try {
      final t = cache.teachers.firstWhere((t) => t.id == teacherId);
      fromLocal = ZjuTeacherDetail(
        id: t.id,
        name: t.name,
        score: double.tryParse(t.rate),
        raters: t.hot,
        college: cache.collegeName(t.collegeId),
      );
    } catch (_) {
      /* 本地无数据 */
    }

    // 2) 后台异步查在线评分（不阻塞返回）
    if (fromLocal != null && name.isNotEmpty) {
      _refreshDetailOnline(teacherId, name);
    }

    return fromLocal;
  }

  /// 后台刷新教师在线评分（不阻塞调用方）。
  Future<void> _refreshDetailOnline(int teacherId, String name) async {
    try {
      final encoded = Uri.encodeComponent(name);
      final res = await _dio.get(
        '$kChalaoshiSearchUrl?search_query=$encoded&action=search',
        options: Options(
          receiveTimeout: const Duration(seconds: 5),
          headers: _searchHeaders,
        ),
      );
      final html = res.data.toString();
      final scoreMatch = RegExp(r'评分:\s*([\d.]+)').firstMatch(html);
      if (scoreMatch != null) {
        final newScore = double.tryParse(scoreMatch.group(1)!);
        final cache = _cache;
        if (newScore != null && cache != null) {
          final updated = [...cache.teachers];
          final idx = updated.indexWhere((t) => t.id == teacherId);
          if (idx >= 0) {
            updated[idx] = ZjuTeacherRecord(
              id: updated[idx].id,
              name: updated[idx].name,
              py: updated[idx].py,
              sx: updated[idx].sx,
              collegeId: updated[idx].collegeId,
              hot: updated[idx].hot,
              rate: newScore.toStringAsFixed(1),
            );
            _cache = ZjuTeacherDataset(
                colleges: cache.colleges, teachers: updated);
            _saveToLocal();
            Log().info('[teachers] detail online updated: $name → $newScore');
          }
        }
      }
    } catch (_) {
      Log().warn('[teachers] detail online refresh failed: $name');
    }
  }

  /// chalaoshi.top 搜索页请求头（浏览器伪装 + Referer 鉴权）。
  static const Map<String, String> _searchHeaders = {
    'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
    'Referer': kChalaoshiSearchUrl,
  };
}
