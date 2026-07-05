/// ZJU 教务通知工具——获取 ZDBK 通知公告列表。
library;

import '../tool.dart';
import 'zju_data_source.dart';

class ZjuNotificationsTool extends Tool {
  final ZjuDataSource _dataSource;

  ZjuNotificationsTool(this._dataSource);

  @override
  String get name => 'get_notifications';

  @override
  String get description =>
      '获取浙江大学教务系统（ZDBK）的通知公告列表，'
      '包含每条通知的标题、发布人、发布时间、浏览数和正文内容。'
      '可用于回答"有什么最新通知""教务系统有什么公告"等问题。';

  @override
  Map<String, dynamic> get schema => {
        'type': 'object',
        'properties': {},
        'required': [],
      };

  @override
  Future<String> execute(Map<String, dynamic> args) async {
    try {
      final notifications = await _dataSource.getNotifications();
      if (notifications.isEmpty) return '当前没有通知公告。';

      final buf = StringBuffer();
      buf.writeln('找到 ${notifications.length} 条通知：\n');

      for (var i = 0; i < notifications.length; i++) {
        final n = notifications[i];
        buf.writeln('### ${i + 1}. ${n.title}\n');
        if (n.publisher != null || n.publishDate != null) {
          buf.writeln(
              '_${[n.publisher, n.publishDate].where((e) => e != null && e.isNotEmpty).join(" · ")}_');
          buf.writeln();
        }
        if (n.content != null && n.content!.isNotEmpty) {
          buf.writeln('${n.content}\n');
        }
        buf.writeln('---\n');
      }

      return buf.toString().trim();
    } catch (e) {
      return '[查询失败: $e]';
    }
  }

  @override
  bool get readOnly => true;
}
