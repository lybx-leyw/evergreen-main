import 'package:flutter_test/flutter_test.dart';
import 'package:evergreen_multi_tools/core/models/zdbk_notification.dart';

/// 模拟的 ZDBK 通知 HTML（含 news_con 内容区）。
const _mockHtml = '''
<html><body>
<div id="newTabbable" class="tabbable tabs-left tabbable-news">
  <ul id="newsNavTabs" class="nav nav-tabs nav-tabs-news">
    <li>
      <a data-toggle="tab" data-xwbh="AAA001" href="#tabNews0">
        <label>关于期末考试的安排通知</label>
      </a>
    </li>
    <li>
      <a data-toggle="tab" data-xwbh="AAA002" href="#tabNews1">
        <label>【选课】2026-2027学年秋冬学期选课通知</label>
      </a>
    </li>
    <li>
      <a data-toggle="tab" data-xwbh="AAA003" href="#tabNews2">
        <label>  关于毕业生图像采集的通知　　 </label>
      </a>
    </li>
  </ul>
  <div id="newsTabContent" class="tab-content tab-content-news">
    <div id="tabNews0" class="tab-pane tab-pane-news">
      <h3>关于期末考试的安排通知</h3>
      <h5 class="text-center news_title1">
        <span>发布人：本科生院</span>
        <span>发布时间：2026-06-06</span>
        <span>浏览人数：1523</span>
      </h5>
      <hr>
      <div class="news_con"><p>考试安排在6月25日-7月4日</p></div>
    </div>
    <div id="tabNews1" class="tab-pane tab-pane-news">
      <h3>2026-2027学年秋冬学期选课通知</h3>
      <h5 class="text-center news_title1">
        <span>发布人：教务处</span>
        <span>发布时间：2026-05-28</span>
        <span>浏览人数：4023</span>
      </h5>
      <hr>
      <div class="news_con"><p>选课安排内容</p></div>
    </div>
    <div id="tabNews2" class="tab-pane tab-pane-news">
      <h3>关于毕业生图像采集的通知</h3>
      <h5 class="text-center news_title1">
        <span>发布人：教务处</span>
        <span>发布时间：2026-04-15</span>
        <span>浏览人数：2105</span>
      </h5>
      <hr>
      <div class="news_con"><p>图像采集内容</p></div>
    </div>
  </div>
</div>
</body></html>
''';

/// 不带 news_con 的 HTML（测试 fallback 解析路径）。
const _mockHtmlNoContent = '''
<html><body>
<div id="newTabbable">
  <ul id="newsNavTabs">
    <li><a data-xwbh="F1"><label>无内容通知</label></a></li>
  </ul>
  <div id="newsTabContent">
    <div id="tabNews0">
      <h3>无内容通知</h3>
      <h5>
        <span>发布人：测试办</span>
        <span>发布时间：2026-01-01</span>
        <span>浏览人数：100</span>
      </h5>
    </div>
  </div>
</div>
</body></html>
''';

void main() {
  group('parseZdbkNotifications', () {
    test('解析 3 条通知', () {
      final results = parseZdbkNotifications(_mockHtml);
      expect(results.length, 3);
    });

    test('正确提取标题、去空白', () {
      final results = parseZdbkNotifications(_mockHtml);
      expect(results[0].title, '关于期末考试的安排通知');
      expect(results[1].title, '【选课】2026-2027学年秋冬学期选课通知');
      expect(results[2].title, '关于毕业生图像采集的通知');
    });

    test('正确提取数据 ID', () {
      final results = parseZdbkNotifications(_mockHtml);
      expect(results[0].id, 'AAA001');
      expect(results[1].id, 'AAA002');
    });

    test('正确提取发布人', () {
      final results = parseZdbkNotifications(_mockHtml);
      expect(results[0].publisher, '本科生院');
      expect(results[1].publisher, '教务处');
    });

    test('正确提取发布时间', () {
      final results = parseZdbkNotifications(_mockHtml);
      expect(results[0].publishDate, '2026-06-06');
      expect(results[1].publishDate, '2026-05-28');
    });

    test('正确提取浏览数', () {
      final results = parseZdbkNotifications(_mockHtml);
      expect(results[0].viewCount, 1523);
      expect(results[1].viewCount, 4023);
      expect(results[2].viewCount, 2105);
    });

    test('正确提取正文内容（保留 HTML）', () {
      final results = parseZdbkNotifications(_mockHtml);
      expect(results[0].content, '<p>考试安排在6月25日-7月4日</p>');
      expect(results[1].content, '<p>选课安排内容</p>');
    });
  });

  group('ZdbkNotification 模型', () {
    test('默认构造', () {
      const n = ZdbkNotification(id: 'X1', title: '测试');
      expect(n.id, 'X1');
      expect(n.title, '测试');
      expect(n.publisher, null);
      expect(n.publishDate, null);
      expect(n.viewCount, null);
      expect(n.content, null);
    });

    test('全字段构造', () {
      const n = ZdbkNotification(
        id: 'X2',
        title: '全字段',
        publisher: '教务处',
        publishDate: '2026-01-01',
        viewCount: 999,
        content: '<p>内容</p>',
      );
      expect(n.publisher, '教务处');
      expect(n.publishDate, '2026-01-01');
      expect(n.viewCount, 999);
      expect(n.content, '<p>内容</p>');
    });
  });

  group('边界情况', () {
    test('空 HTML 返回空列表', () {
      expect(parseZdbkNotifications(''), isEmpty);
    });

    test('无通知 HTML 返回空列表', () {
      expect(parseZdbkNotifications('<html><body>无通知</body></html>'), isEmpty);
    });

    test('无 news_con 时使用 fallback 解析', () {
      final results = parseZdbkNotifications(_mockHtmlNoContent);
      expect(results.length, 1);
      expect(results[0].title, '无内容通知');
      expect(results[0].publisher, '测试办');
      expect(results[0].content, null); // fallback 不提取 content
    });

    test('标签中有额外 HTML 格式', () {
      const html = '''
      <ul>
        <li><a data-xwbh="B1"><label><b>加粗标题</b></label></a></li>
      </ul>
      ''';
      final results = parseZdbkNotifications(html);
      expect(results.length, 1);
      expect(results[0].title, '加粗标题');
    });

    test('ID 为空时跳过', () {
      const html = '''
      <ul>
        <li><a data-xwbh=""><label>空ID</label></a></li>
        <li><a data-xwbh="R1"><label>有效</label></a></li>
      </ul>
      ''';
      final results = parseZdbkNotifications(html);
      expect(results.length, 1);
      expect(results[0].id, 'R1');
    });
  });
}
