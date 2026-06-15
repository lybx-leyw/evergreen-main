/// 网络层集中配置——替代散落的魔术数字。
class NetworkConfig {
  NetworkConfig._();

  // ── 超时 ──
  static const Duration connectTimeout = Duration(seconds: 30);
  static const Duration receiveTimeout = Duration(seconds: 60);
  static const Duration casValidateTimeout = Duration(seconds: 5);

  // ── 重试 ──
  static const int maxRetries = 3;
  static const Duration maxRetryDelay = Duration(seconds: 30);
  static const Set<int> retryableStatusCodes = {429, 502, 503};

  // ── ZJU 域名白名单 ──
  static const Set<String> zjuDomains = {
    'zjuam.zju.edu.cn',
    'zdbk.zju.edu.cn',
    'courses.zju.edu.cn',
    'classroom.zju.edu.cn',
    'tgmedia.cmc.zju.edu.cn',
    'education.cmc.zju.edu.cn',
    'yjapi.cmc.zju.edu.cn',
    'api.lib.zju.edu.cn',
    'elife.zju.edu.cn',
    'chalaoshi.top',
  };

  static bool isZjuDomain(String url) =>
      zjuDomains.contains(Uri.tryParse(url)?.host ?? '');
}
