/// ZjuZdbkNotification — 教务（ZDBK）通知公告模型。
///
/// B3-zdbk（2026-08-12）自参考工程 `cp_evergreen_push/lib/core/models/
/// zdbk_notification.dart` 拷入并前缀 `Zju`（规划 §5.6 防符号冲突）。
/// 保留 fromJson/toJson 双向桥接——fetcher 产出 JSON（数据中枢 jsonEncode
/// 缓存），renderer 侧 fromJson 还原。
library;

/// 一条教务通知。
class ZjuZdbkNotification {
  /// 通知 ID（data-xwbh）。
  final String id;

  /// 标题。
  final String title;

  /// 发布人。
  final String? publisher;

  /// 发布时间。
  final String? publishDate;

  /// 浏览人数。
  final int? viewCount;

  /// 纯文本内容（HTML 标签已剥离）。
  final String? content;

  const ZjuZdbkNotification({
    required this.id,
    required this.title,
    this.publisher,
    this.publishDate,
    this.viewCount,
    this.content,
  });

  factory ZjuZdbkNotification.fromJson(Map<String, dynamic> json) {
    return ZjuZdbkNotification(
      id: (json['id'] ?? '').toString(),
      title: (json['title'] ?? '').toString(),
      publisher: json['publisher']?.toString(),
      publishDate: json['publishDate']?.toString(),
      viewCount: int.tryParse(json['viewCount']?.toString() ?? ''),
      content: json['content']?.toString(),
    );
  }

  /// 序列化（数据中枢缓存契约）——fromJson 可还原。
  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'publisher': publisher,
        'publishDate': publishDate,
        'viewCount': viewCount,
        'content': content,
      };
}

/// 从 ZDBK 通知 HTML 中解析通知列表（三步：列表 → 详情面板 → 简单保底）。
///
/// 照抄参考实现 `parseZdbkNotifications`，仅类型前缀 `Zju`。
List<ZjuZdbkNotification> parseZjuZdbkNotifications(String html) {
  final results = <ZjuZdbkNotification>[];

  // 步骤 1：从 <li> 列表中提取 id + 标题
  final itemRegex = RegExp(
    r'<li>\s*<a[^>]*data-xwbh="([^"]+)"[^>]*>.*?<label>(.*?)</label>',
    dotAll: true,
  );
  for (final m in itemRegex.allMatches(html)) {
    final id = m.group(1) ?? '';
    final title = _stripHtml(m.group(2) ?? '').trim();
    if (id.isEmpty) continue;
    results.add(ZjuZdbkNotification(id: id, title: title));
  }

  // 步骤 2：提取发布人/日期/浏览数 + 内容
  final paneRegex = RegExp(
    r'<div[^>]*id="tabNews(\d+)"[^>]*class="tab-pane tab-pane-news"[^>]*>'
    r'(.*?)发布人[：:]\s*([^<]+).*?发布时间[：:]\s*([^<]+).*?浏览人数[：:]\s*(\d+)'
    r'.*?<div class="news_con">(.*?)</div>\s*</div>',
    dotAll: true,
  );
  var i = 0;
  for (final m in paneRegex.allMatches(html)) {
    if (i >= results.length) break;
    results[i] = ZjuZdbkNotification(
      id: results[i].id,
      title: results[i].title,
      publisher: m.group(3)?.trim(),
      publishDate: m.group(4)?.trim(),
      viewCount: int.tryParse(m.group(5) ?? ''),
      content: m.group(6)?.trim(),
    );
    i++;
  }

  // 步骤 3：如果步骤 2 没匹配到，用旧的简单匹配保底
  if (i == 0) {
    final detailRegex = RegExp(
      r'发布人[：:]\s*([^<]+).*?发布时间[：:]\s*([^<]+).*?浏览人数[：:]\s*(\d+)',
      dotAll: true,
    );
    for (final m in detailRegex.allMatches(html)) {
      if (i >= results.length) break;
      results[i] = ZjuZdbkNotification(
        id: results[i].id,
        title: results[i].title,
        publisher: m.group(1)?.trim(),
        publishDate: m.group(2)?.trim(),
        viewCount: int.tryParse(m.group(3) ?? ''),
      );
      i++;
    }
  }

  return results;
}

String _stripHtml(String html) {
  return html
      .replaceAll(RegExp(r'<[^>]*>'), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}
