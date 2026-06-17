import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import '../../../core/log.dart';

/// 查老师服务——本地 JSON + 逐条在线更新。
///
/// 策略：
/// 1. 首次加载读取 assets/data/teacher_ratings.json（完整数据集）
/// 2. 搜索时先在本地数据中匹配，秒出结果
/// 3. 查到结果后，后台逐条查询在线评分，成功则替换本地数据
/// 4. 在线查失败直接用本地数据，不受网络影响
class ChalaoshiService {
  final Dio _dio;
  ChalaoshiService(this._dio);

  List<TeacherRecord>? _cache;
  Map<int, String>? _collegeCache;
  bool _loaded = false;
  final Set<int> _updatingIds = {}; // 正在更新的教师 ID

  /// 从 asset 或本地缓存文件加载完整数据集。
  Future<void> _loadLocal() async {
    if (_loaded) return;
    Log().debug('Chalaoshi loading local dataset');

    late String content;
    // 1) Bundled asset (works on all platforms, does NOT need package prefix)
    try {
      content = await rootBundle.loadString('assets/data/teacher_ratings.json');
    } catch (_) {
      // 2) Cached copy from previous online fetches (app documents dir)
      try {
        final cacheFile = await _getCacheFile();
        if (await cacheFile.exists()) {
          content = await cacheFile.readAsString();
          Log().info('Chalaoshi loaded from cache');
        } else {
          Log().warn('Chalaoshi local data file not found');
          _loaded = true;
          return;
        }
      } catch (e) {
        Log().warn('Chalaoshi data unavailable', error: e);
        _loaded = true;
        return;
      }
    }

    final json = jsonDecode(content) as Map<String, dynamic>;
    _parseDataset(json);
    _loaded = true;
    Log().info('Chalaoshi loaded ${_cache!.length} teachers, ${_collegeCache!.length} colleges');
  }

  void _parseDataset(Map<String, dynamic> json) {
    _collegeCache = Map.fromEntries(
      (json['colleges'] as List).map((c) => MapEntry(c['id'] as int, c['name'] as String)),
    );
    _cache = (json['teachers'] as List).map((t) => TeacherRecord(
      id: t['id'] as int,
      name: t['name'] as String,
      py: t['py'] as String? ?? '',
      sx: t['sx'] as String? ?? '',
      collegeId: t['xy'] as int? ?? 0,
      hot: t['hot'] as int? ?? 0,
      rate: t['rate']?.toString() ?? '',
    )).toList();
  }

  /// 按姓名搜索：先预加载本地数据 → 快速试在线搜索（3s 超时 + 1 次重试）→ 失败则秒回本地结果。
  Future<List<TeacherResult>> search(String name) async {
    if (name.trim().isEmpty) return [];
    final q = name.trim();

    // 0) 预加载本地数据，确保降级路径立即可用
    try {
      await _loadLocal();
      // 也试一下 lazuli 兜底
      if (_cache == null) {
        final f = File('.lazuli/Lazuli-master/data/default.json');
        if (f.existsSync()) {
          _parseDataset(jsonDecode(f.readAsStringSync()) as Map<String, dynamic>);
          _loaded = true;
          Log().info('Chalaoshi loaded from .lazuli fallback');
        }
      }
    } catch (_) {}

    // 1) 快速试在线搜索（3s 超时，失败后 500ms 重试一次）
    List<TeacherResult>? onlineResults;
    for (int attempt = 0; attempt < 2; attempt++) {
      try {
        final encoded = Uri.encodeComponent(q);
        final res = await _dio.get(
          'http://chalaoshi.top/?search_query=$encoded&action=search',
          options: Options(
            receiveTimeout: const Duration(seconds: 3),
            headers: {
              'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
              'Referer': 'http://chalaoshi.top/',
            },
          ),
        );
        final html = res.data.toString();
        if (html.contains('result-item') && html.contains('评分')) {
          onlineResults = _parseOnlineResults(html, q);
          if (onlineResults != null && onlineResults.isNotEmpty) {
            Log().info('Chalaoshi ✅ online attempt $attempt: found ${onlineResults.length} for "$q"');
            _mergeOnlineResults(onlineResults);
            return onlineResults;
          }
        }
        // 有响应但解析不到结果，不再重试
        break;
      } catch (e) {
        if (attempt == 0) {
          Log().info('Chalaoshi ⚠️ online attempt 0 failed for "$q": $e — retrying...');
          await Future.delayed(const Duration(milliseconds: 500));
        } else {
          Log().info('Chalaoshi ⚠️ online attempt 1 also failed — falling back to local for "$q"');
        }
      }
    }

    // 2) 在线失败 → 秒回本地数据（本地已在步骤 0 预加载好）
    if (_cache == null || _cache!.isEmpty) {
      Log().info('Chalaoshi ❌ local data unavailable for "$q"');
      return [];
    }

    final localResults = _cache!.where((t) =>
        t.name.contains(q) || t.py.contains(q.toLowerCase()) || t.sx.contains(q.toLowerCase())
    ).toList();

    Log().info('Chalaoshi 📁 local: found ${localResults.length} for "$q"');
    return localResults.map((t) => TeacherResult(
      id: t.id, name: t.name,
      score: double.tryParse(t.rate),
      college: _collegeCache?[t.collegeId],
      url: 'https://chalaoshi.click/t/${t.id}',
    )).toList();
  }

  /// 在线结果覆盖到本地缓存 + 写回 JSON 文件。
  void _mergeOnlineResults(List<TeacherResult> online) {
    if (_cache == null) return;
    for (final o in online) {
      final idx = _cache!.indexWhere((t) => t.id == o.id);
      if (idx >= 0 && o.score != null) {
        _cache![idx] = TeacherRecord(
          id: _cache![idx].id, name: _cache![idx].name,
          py: _cache![idx].py, sx: _cache![idx].sx,
          collegeId: _cache![idx].collegeId,
          hot: _cache![idx].hot, rate: o.score!.toStringAsFixed(1),
        );
      }
    }
    // 写回缓存文件持久化
    _saveToLocal();
  }

  /// 解析 chalaoshi.top 在线搜索结果的 HTML。
  List<TeacherResult> _parseOnlineResults(String html, String query) {
    final results = <TeacherResult>[];
    final pattern = RegExp(
      r'<div\s+class="result-item">\s*<div>(.*?)</div>\s*<a\s+href="([^"]*teacher_id=(\d+)[^"]*)"[^>]*>.*?</a>\s*</div>',
      dotAll: true,
    );
    for (final m in pattern.allMatches(html)) {
      final nameM = RegExp(r'<strong>(.*?)</strong>').firstMatch(m.group(1)!);
      final name = nameM?.group(1)?.trim() ?? '';
      if (name.isEmpty) continue;
      final scoreM = RegExp(r'评分:\s*([\d.]+)').firstMatch(m.group(1)!);
      results.add(TeacherResult(
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
  Future<void> _refreshTeacherOnline(TeacherRecord teacher) async {
    final encoded = Uri.encodeComponent(teacher.name);
    try {
      Log().info('Chalaoshi online refresh: ${teacher.name}');
      final res = await _dio.get(
        'http://chalaoshi.top/?search_query=$encoded&action=search',
        options: Options(
          receiveTimeout: const Duration(seconds: 8),
          headers: {
            'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
            'Referer': 'http://chalaoshi.top/',
          },
        ),
      );
      final html = res.data.toString();

      // 从 HTML 解析最新评分
      final scoreMatch = RegExp(r'评分:\s*([\d.]+)').firstMatch(html);
      if (scoreMatch != null) {
        final newRate = scoreMatch.group(1)!;
        final idx = _cache!.indexWhere((t) => t.id == teacher.id);
        if (idx >= 0) {
          _cache![idx] = TeacherRecord(
            id: teacher.id, name: teacher.name,
            py: teacher.py, sx: teacher.sx,
            collegeId: teacher.collegeId,
            hot: teacher.hot, rate: newRate,
          );
          // 写回本地文件持久化
          _saveToLocal();
          Log().info('Chalaoshi ✅ ${teacher.name} updated: ${teacher.rate} → $newRate');
        }
      }
    } catch (e) {
      Log().info('Chalaoshi ❌ ${teacher.name} online refresh failed: $e');
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
    try {
      final data = {
        'colleges': _collegeCache!.entries.map((e) => {'id': e.key, 'name': e.value}).toList(),
        'teachers': _cache!.map((t) => {
          'id': t.id, 'name': t.name, 'py': t.py, 'sx': t.sx,
          'xy': t.collegeId, 'hot': t.hot, 'rate': t.rate,
        }).toList(),
      };
      final file = await _getCacheFile();
      await file.writeAsString(jsonEncode(data));
      Log().info('Chalaoshi 💾 saved to local');
    } catch (e) {
      Log().info('Chalaoshi ⚠️ save failed: $e');
    }
  }

  Future<TeacherDetail?> getDetail(int teacherId, {String name = ''}) async {
    await _loadLocal();
    // 1) 本地秒回（不阻塞 UI）
    TeacherDetail? fromLocal;
    try {
      final t = _cache!.firstWhere((t) => t.id == teacherId);
      fromLocal = TeacherDetail(id: t.id, name: t.name,
        score: double.tryParse(t.rate), raters: t.hot,
        college: _collegeCache?[t.collegeId]);
    } catch (_) { /* 本地无数据 */ }

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
        'http://chalaoshi.top/?search_query=$encoded&action=search',
        options: Options(
          receiveTimeout: const Duration(seconds: 5),
          headers: {
            'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
            'Referer': 'http://chalaoshi.top/',
          },
        ),
      );
      final html = res.data.toString();
      final scoreMatch = RegExp(r'评分:\s*([\d.]+)').firstMatch(html);
      if (scoreMatch != null) {
        final newScore = double.tryParse(scoreMatch.group(1)!);
        if (newScore != null) {
          final idx = _cache!.indexWhere((t) => t.id == teacherId);
          if (idx >= 0) {
            _cache![idx] = TeacherRecord(
              id: _cache![idx].id, name: _cache![idx].name,
              py: _cache![idx].py, sx: _cache![idx].sx,
              collegeId: _cache![idx].collegeId,
              hot: _cache![idx].hot, rate: newScore.toStringAsFixed(1),
            );
            _saveToLocal();
            Log().info('Chalaoshi detail online updated: $name → $newScore');
          }
        }
      }
    } catch (_) {
      Log().warn('Chalaoshi detail online refresh failed: $name');
    }
  }
}

class TeacherRecord {
  final int id; final String name; final String py;
  final String sx; final int collegeId; final int hot; final String rate;
  const TeacherRecord({required this.id, required this.name,
    this.py = '', this.sx = '', this.collegeId = 0, this.hot = 0, this.rate = ''});
}

class TeacherResult {
  final int id; final String name; final double? score;
  final String? college; final String url;

  /// "online" = 从 chalaoshi.top 实时抓取；"local" = 本地缓存数据。
  final String dataSource;

  const TeacherResult({required this.id, required this.name,
    this.score, this.college, required this.url, this.dataSource = 'local'});
}

class TeacherDetail {
  final int id; final String name; final double? score;
  final int raters; final String? college;
  const TeacherDetail({required this.id, required this.name,
    this.score, this.raters = 0, this.college});
}
