/// 数据源解析器——M2 统一接入中枢。
///
/// 解析一个 [DataSourceDescriptor]，返回经 [extractPath] 提取 + [applyTransform] 转换后的数据。
/// 两种来源：
///  1) [DataSourceDescriptor.endpoint] 非空 → dio 直连 HTTP 拉取（GET/POST 尊重 method）；
///  2) [dataType] 非空且传入 [orch] → 经 [DataOrchestrator] 拉取（CLI/HTTP 插件数据源）。
///
/// 校验与降级（R5）：任何异常都被捕获、[Log].warn 记录，返回 null，绝不向上抛到 UI。
library;

import 'package:dio/dio.dart';
import 'package:evergreen_base/core/data/data.dart';
import 'package:evergreen_base/core/data/type.dart';
import 'package:evergreen_base/core/log.dart';
import 'package:evergreen_base/core/module/module_descriptor.dart';
import 'json_path.dart';
import 'transform_registry.dart';

/// 可注入的 HTTP 拉取函数（便于测试替换网络层，避免真实请求）。
/// 仅接收 [DataSourceDescriptor]；dio 由默认实现内部创建，注入的函数无需关心。
typedef HttpFetcher = Future<dynamic> Function(DataSourceDescriptor ds);

/// 解析数据源描述符，返回最终数据（可能经 dataPath 提取与 transform 转换）。
///
/// 两种数据来源（在不修改 [DataSourceDescriptor] 契约的前提下统一表达）：
///  1) [DataSourceDescriptor.endpoint] 为普通 URL → dio 直连 HTTP 拉取（GET/POST）；
///  2) [DataSourceDescriptor.endpoint] 为 `orch://<typeName>` 形式 → 经 [orch] 拉取
///     已注册的对应 [DataType]（CLI/HTTP 插件数据源），[dataType] 冗余参数也可直接指定。
/// [dio] 与 [httpFetcher] 用于路径 1；[orch] 用于路径 2。
///
/// [forceRefresh]：为 true 时 orch 路径改用 [DataOrchestrator.refresh] 强制重抓
/// （绕过缓存），供组件的 [DataSourceSlotState] 自动刷新（refreshInterval）使用——
/// 否则 [orch.get] 命中缓存会令定时刷新永远拿到旧值（R5 无实际刷新）。
Future<dynamic> resolveDataSource({
  required DataSourceDescriptor ds,
  DataOrchestrator? orch,
  String? dataType,
  Dio? dio,
  HttpFetcher? httpFetcher,
  bool forceRefresh = false,
}) async {
  try {
    dynamic raw;
    final ep = ds.endpoint;
    if (ep != null && ep.isNotEmpty) {
      if (ep.startsWith('orch://') &&
          (orch != null || dataType != null)) {
        // 引用已注册的 DataType（插件/CLI 数据源），不改动 descriptor 契约。
        final name = ep.startsWith('orch://')
            ? ep.substring('orch://'.length)
            : dataType!;
        final t = DataType<dynamic>(
          name: name,
          category: '',
          displayName: name,
          ttl: const Duration(minutes: 5),
        );
        raw = forceRefresh ? await orch!.refresh(t) : await orch!.get(t);
      } else {
        // 注入的 fetcher 仅接收 ds（1 参）；默认实现内部创建 dio（2 参）。
        raw = httpFetcher != null
            ? await httpFetcher(ds)
            : await _defaultHttpFetch(ds, dio ?? Dio());
      }
    } else if (dataType != null && dataType.isNotEmpty && orch != null) {
      final t = DataType<dynamic>(
        name: dataType,
        category: '',
        displayName: dataType,
        ttl: const Duration(minutes: 5),
      );
      raw = forceRefresh ? await orch.refresh(t) : await orch.get(t);
    } else {
      // 既无 endpoint 也无 dataType+orch → 无数据源可解析。
      return null;
    }

    if (raw == null) return null;

    if (ds.dataPath != null && ds.dataPath!.isNotEmpty) {
      raw = extractPath(raw, ds.dataPath!);
    }
    if (ds.transform != null && ds.transform!.isNotEmpty) {
      raw = applyTransform(ds.transform!, raw);
    }
    return raw;
  } catch (e, st) {
    Log().warn('resolveDataSource 失败：已降级返回 null',
        error: e, data: {'stack': st.toString()});
    return null;
  }
}

/// 默认 HTTP 拉取实现（生产路径）。超时 10s，避免阻塞 UI（配合 FutureBuilder 兜底）。
Future<dynamic> _defaultHttpFetch(DataSourceDescriptor ds, Dio dio) async {
  final options = Options(
    sendTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 10),
  );
  final Response<dynamic> response;
  if (ds.method.toUpperCase() == 'POST') {
    response = await dio.post<dynamic>(ds.endpoint!, options: options);
  } else {
    response = await dio.get<dynamic>(ds.endpoint!, options: options);
  }
  return response.data;
}
