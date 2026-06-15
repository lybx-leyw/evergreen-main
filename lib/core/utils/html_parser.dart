import 'dart:convert';

import '../../features/zdbk/services/zdbk_patterns.dart';

/// Regex-based HTML parsing utilities for ZDBK + ZJU subsystem responses.
class HtmlParser {
  /// Extract a JSON array from a ZDBK HTML response.
  static List<Map<String, dynamic>> extractItems(String html) {
    final match1 = ZdbkPatterns.itemsWithLimit.firstMatch(html);
    if (match1 != null && match1.group(0) != null) {
      return _parseJsonArray(match1.group(0)!);
    }

    final match2 = ZdbkPatterns.itemsWithTotalResult.firstMatch(html);
    if (match2 != null && match2.group(0) != null) {
      return _parseJsonArray(match2.group(0)!);
    }

    return [];
  }

  static List<Map<String, dynamic>> _parseJsonArray(String jsonStr) {
    try {
      final decoded = jsonDecode(jsonStr);
      return (decoded as List)
          .whereType<Map<String, dynamic>>()
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// 检测 HTML 是否包含 CAS 统一认证登录页（会话过期）。
  ///
  /// 覆盖 ZJU 以下子系统的 CAS 变体：
  /// - ZDBK（教务）：`login_ssologin`
  /// - 统一认证中心：`cas/login`、`统一身份认证`
  /// - 图书馆：`idp.zju.edu.cn`
  /// - 一卡通：`ecard.zju.edu.cn/login`
  /// - 通用 CAS 重定向：`/cas/`、`service=`
  static bool isSessionExpired(String html) {
    return html.contains('login_ssologin') ||
        html.contains('cas/login') ||
        html.contains('idp.zju.edu.cn') ||
        html.contains('统一身份认证') ||
        html.contains('统一认证') ||
        html.contains('/cas/');
  }

  /// 检测是否需要验证码。
  static bool requiresCaptcha(String html) {
    return html.contains('captcha_error') ||
        html.contains('请输入验证码');
  }
}
