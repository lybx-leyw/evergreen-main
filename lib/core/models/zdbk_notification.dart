/// ZDBK 通知模型。
class ZdbkNotification {
  final String id;
  final String title;
  final String? publisher;
  final String? publishDate;
  final int? viewCount;

  /// 纯文本内容（HTML 标签已剥离）。
  final String? content;

  const ZdbkNotification({
    required this.id,
    required this.title,
    this.publisher,
    this.publishDate,
    this.viewCount,
    this.content,
  });
}

/// 从 ZDBK 通知 HTML 中解析通知列表。
List<ZdbkNotification> parseZdbkNotifications(String html) {
  final results = <ZdbkNotification>[];

  // 步骤 1: 从 <li> 列表中提取 id + 标题
  final itemRegex = RegExp(
    r'<li>\s*<a[^>]*data-xwbh="([^"]+)"[^>]*>.*?<label>(.*?)</label>',
    dotAll: true,
  );
  for (final m in itemRegex.allMatches(html)) {
    final id = m.group(1) ?? '';
    final title = _stripHtml(m.group(2) ?? '').trim();
    if (id.isEmpty) continue;
    results.add(ZdbkNotification(id: id, title: title));
  }

  // 步骤 2: 提取发布人/日期/浏览数 + 内容
  final paneRegex = RegExp(
    r'<div[^>]*id="tabNews(\d+)"[^>]*class="tab-pane tab-pane-news"[^>]*>'
    r'(.*?)发布人[：:]\s*([^<]+).*?发布时间[：:]\s*([^<]+).*?浏览人数[：:]\s*(\d+)'
    r'.*?<div class="news_con">(.*?)</div>\s*</div>',
    dotAll: true,
  );
  var i = 0;
  for (final m in paneRegex.allMatches(html)) {
    if (i >= results.length) break;
    results[i] = ZdbkNotification(
      id: results[i].id,
      title: results[i].title,
      publisher: m.group(3)?.trim(),
      publishDate: m.group(4)?.trim(),
      viewCount: int.tryParse(m.group(5) ?? ''),
      content: m.group(6)?.trim(),
    );
    i++;
  }

  // 步骤 3: 如果步骤 2 没匹配到，用旧的简单匹配保底
  if (i == 0) {
    final detailRegex = RegExp(
      r'发布人[：:]\s*([^<]+).*?发布时间[：:]\s*([^<]+).*?浏览人数[：:]\s*(\d+)',
      dotAll: true,
    );
    for (final m in detailRegex.allMatches(html)) {
      if (i >= results.length) break;
      results[i] = ZdbkNotification(
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
