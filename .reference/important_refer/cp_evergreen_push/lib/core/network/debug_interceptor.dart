import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../../../core/log.dart';

/// Debug interceptor — logs request/response details in debug mode only.
///
/// Release 模式零开销——每个方法顶部 `if (!kDebugMode) return`。
class DebugInterceptor extends Interceptor {
  final int maxBodyLength;

  DebugInterceptor({this.maxBodyLength = 500});

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (kDebugMode) {
      Log().debug('HTTP >>', data: {
        'method': options.method,
        'uri': options.uri.toString(),
        'headers': _sanitizeHeaders(options.headers),
        'body': _truncate(options.data?.toString()),
      });
    }
    handler.next(options);
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    if (kDebugMode) {
      Log().debug('HTTP <<', data: {
        'status': response.statusCode,
        'uri': response.requestOptions.uri.toString(),
        'body': _truncate(response.data?.toString()),
      });
    }
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    if (kDebugMode) {
      Log().debug('HTTP !!', data: {
        'status': err.response?.statusCode,
        'uri': err.requestOptions.uri.toString(),
        'type': err.type.name,
        'message': err.message,
      });
    }
    handler.next(err);
  }

  Map<String, String> _sanitizeHeaders(Map<String, dynamic> headers) {
    final out = <String, String>{};
    headers.forEach((k, v) {
      final key = k.toLowerCase();
      if (key == 'cookie') {
        out[k] = _maskCookie(v.toString());
      } else if (key == 'authorization') {
        out[k] = 'Bearer ***';
      } else {
        out[k] = v.toString();
      }
    });
    return out;
  }

  String _maskCookie(String raw) {
    return raw.split(';').map((p) {
      final eq = p.trim().indexOf('=');
      if (eq <= 0) return p.trim();
      final name = p.trim().substring(0, eq);
      final val = p.trim().substring(eq + 1);
      return '$name=${val.length <= 8 ? val : '${val.substring(0, 4)}...${val.substring(val.length - 4)}'}';
    }).join('; ');
  }

  String? _truncate(String? text) {
    if (text == null || text.isEmpty) return null;
    return text.length > maxBodyLength
        ? '${text.substring(0, maxBodyLength)}... (${text.length} total)'
        : text;
  }
}
