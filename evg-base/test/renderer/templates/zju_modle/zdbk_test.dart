/// zdbk feature 单测（B4-fix 重写）：
/// - 模型：ZjuCourseOffering / ZjuTrainingPlan / ZjuZdbkNotification（含 HTML 三步解析）
/// - ZjuZdbkService 静态解析（无网络）：parseGrades / jsonItems / parsePlans /
///   parsePracticeScores / parseTimetable / isPdfBytes
///
/// 注：service 自 B4 起改为 HttpClient 手动两步 cookie 版（对齐参考实现
/// `cp_evergreen_push/lib/features/zdbk/services/zdbk_service.dart`），网络逻辑
/// 不再用 Dio mock 覆盖；解析逻辑提为 public static 方法供离线单测。
library;

import 'package:evergreen_base/renderer/templates/zju_modle/shared/models/zju_course_offering.dart';
import 'package:evergreen_base/renderer/templates/zju_modle/shared/models/zju_training_plan.dart';
import 'package:evergreen_base/renderer/templates/zju_modle/shared/models/zju_zdbk_notification.dart';
import 'package:evergreen_base/renderer/templates/zju_modle/zdbk/services/zdbk_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ZjuCourseOffering 模型', () {
    test('fromJson 映射 ZDBK 字段 → toJson 往返一致', () {
      final src = ZjuCourseOffering.fromJson(const {
        'kcdm': 'CS101',
        'kcmc': '数据结构',
        'jsxm': '张三',
        'skdd': '东1A-101',
        'sksj': '周一 3-4节',
        'xf': '4',
        'zxss': '64',
        'kkxy': '计算机学院',
        'kcxz': '必修',
        'kclb': '专业基础',
        'kcgs': '本专业',
        'xn': '2025',
        'xxq': '1',
        'kssj': '2025-09-01 09:00',
        'zymc': '计算机科学与技术',
        'jxjhh': 'P1001',
        'xkkh': 'X001',
      });
      expect(src.courseCode, 'CS101');
      expect(src.courseName, '数据结构');
      expect(src.teacher, '张三');
      expect(src.credits, 4.0);
      expect(src.totalHours, 64);
      expect(src.courseType, '必修');
      expect(src.planNo, 'P1001');

      final round = ZjuCourseOffering.fromJson(src.toJson());
      expect(round.courseCode, src.courseCode);
      expect(round.courseName, src.courseName);
      expect(round.teacher, src.teacher);
      expect(round.credits, src.credits);
      expect(round.totalHours, src.totalHours);
      expect(round.planNo, src.planNo);
    });

    test('fromJson 缺省字段兜底（kcmc 缺失 → 默认值 + 学分 0）', () {
      final o = ZjuCourseOffering.fromJson(const {});
      expect(o.courseName, '未命名课程');
      expect(o.credits, 0);
      expect(o.courseCode, isEmpty);
    });
  });

  group('ZjuTrainingPlan 模型', () {
    test('fromJson 多字段名回退（planNo/college）→ toJson 往返一致', () {
      final src = ZjuTrainingPlan.fromJson(const {
        'jxjhh': 'P2025-01',
        'pyfamc': '计算机科学与技术培养方案',
        'zymc': '计算机科学与技术',
        'synj': '2025',
        'xymc': '计算机学院',
        'pycc': '本科',
        'xz': '4',
        'minxf': '150',
        'yxxf': '60',
        'zt': '1',
        'bz': '备注',
      });
      expect(src.planNo, 'P2025-01');
      expect(src.planName, '计算机科学与技术培养方案');
      expect(src.major, '计算机科学与技术');
      expect(src.grade, '2025');
      expect(src.college, '计算机学院');
      expect(src.level, '本科');
      expect(src.minCredits, 150.0);

      final round = ZjuTrainingPlan.fromJson(src.toJson());
      expect(round.planNo, src.planNo);
      expect(round.planName, src.planName);
      expect(round.major, src.major);
      expect(round.grade, src.grade);
      expect(round.college, src.college);
      expect(round.minCredits, src.minCredits);
      expect(round.remarks, src.remarks);
    });

    test('fromJson 缺失字段兜底（planName 默认值 + planNo 可空）', () {
      final p = ZjuTrainingPlan.fromJson(const {});
      expect(p.planName, '未命名方案');
      expect(p.planNo, isNull);
    });
  });

  group('ZjuZdbkNotification 模型 + 解析', () {
    test('fromJson → toJson 往返一致', () {
      const src = ZjuZdbkNotification(
        id: '10001',
        title: '选课通知',
        publisher: '教务处',
        publishDate: '2025-09-01',
        viewCount: 123,
        content: '选课安排如下',
      );
      final round = ZjuZdbkNotification.fromJson(src.toJson());
      expect(round.id, src.id);
      expect(round.title, src.title);
      expect(round.publisher, src.publisher);
      expect(round.publishDate, src.publishDate);
      expect(round.viewCount, src.viewCount);
      expect(round.content, src.content);
    });

    test('parseZjuZdbkNotifications 三步解析：列表 + 详情面板', () {
      const html = '''
<ul>
  <li><a data-toggle="tab" data-xwbh="10001" href="#tabNews1"><label>选课通知</label></a></li>
  <li><a data-toggle="tab" data-xwbh="10002" href="#tabNews2"><label>考试安排</label></a></li>
</ul>
<div id="tabNews1" class="tab-pane tab-pane-news">
  <h5 class="text-center news_title1">
    <span>发布人：教务处</span>
    <span>发布时间：2025-09-01 08:00</span>
    <span>浏览人数：123</span>
  </h5>
  <div class="news_con">选课安排如下，请关注。</div>
</div>
<div id="tabNews2" class="tab-pane tab-pane-news">
  <h5 class="text-center news_title1">
    <span>发布人：教务处</span>
    <span>发布时间：2025-09-05 09:00</span>
    <span>浏览人数：45</span>
  </h5>
  <div class="news_con">期末考试安排已公布。</div>
</div>
''';
      final list = parseZjuZdbkNotifications(html);
      expect(list, hasLength(2));
      expect(list[0].id, '10001');
      expect(list[0].title, '选课通知');
      expect(list[0].publisher, '教务处');
      expect(list[0].publishDate, '2025-09-01 08:00');
      expect(list[0].viewCount, 123);
      expect(list[0].content, contains('选课安排如下'));
      expect(list[1].id, '10002');
      expect(list[1].title, '考试安排');
    });

    test('parseZjuZdbkNotifications 无详情面板 → 简单匹配保底', () {
      const html = '''
<ul>
  <li><a data-xwbh="10001" href="#tabNews0"><label>标题A</label></a></li>
</ul>
发布人：教务处 发布时间：2025-09-01 浏览人数：9
''';
      final list = parseZjuZdbkNotifications(html);
      expect(list, hasLength(1));
      expect(list[0].id, '10001');
      expect(list[0].title, '标题A');
      expect(list[0].publisher, '教务处');
      expect(list[0].viewCount, 9);
      expect(list[0].content, isNull);
    });
  });

  group('ZjuZdbkService.parseGrades（成绩单 / 主修成绩）', () {
    const okBody =
        '{"items":[{"xkkh":"(2024-2025-1)-CS101-001","kcmc":"数据结构",'
        '"xf":"4","cj":"95","jd":"4.8"},{"xkkh":"(2024-2025-1)-CS102-001",'
        '"kcmc":"高数","xf":"5","cj":"90","jd":"4.5"}],"totalResult":2}';

    test('正常路径：解析成绩列表（保留 jd 绩点）', () {
      final grades = ZjuZdbkService.parseGrades(okBody, what: '成绩单');
      expect(grades, hasLength(2));
      expect(grades.first.name, '数据结构');
      expect(grades.first.fivePoint, 4.8);
      expect(grades[1].name, '高数');
    });

    test('过滤无 xkkh 的占位行（仅保留有效课程成绩）', () {
      const body =
          '{"items":[{"xkkh":"(2024-2025-1)-CS101-001","kcmc":"数据结构",'
          '"xf":"4","cj":"95"},{"kcmc":"占位行","xf":"0","cj":"0"}],'
          '"totalResult":2}';
      final grades = ZjuZdbkService.parseGrades(body, what: '成绩单');
      expect(grades, hasLength(1));
      expect(grades.first.name, '数据结构');
    });

    test('解析为空 → 抛可读 StateError（提示页面结构变更）', () {
      expect(
        () => ZjuZdbkService.parseGrades('{}', what: '成绩单'),
        throwsA(isA<StateError>().having(
            (e) => e.message, 'message', contains('解析为空'))),
      );
    });
  });

  group('ZjuZdbkService.jsonItems（开课情况 JSON）', () {
    const okBody =
        '{"items":[{"kcdm":"CS101","kcmc":"数据结构","jsxm":"张三",'
        '"skdd":"东1A-101","xf":"4","zxss":"64","kcxz":"必修"},'
        '{"kcdm":"CS102","kcmc":"高数","jsxm":"李四","xf":"5",'
        '"zxss":"80","kcxz":"必修"}],"totalCount":2}';

    test('正常路径：items 数组解析', () {
      final items = ZjuZdbkService.jsonItems(okBody, what: '开课情况');
      expect(items, hasLength(2));
      expect(items.first['kcmc'], '数据结构');
      expect(items.first['kcxz'], '必修');
    });

    test('data 字段回退（无 items → data）', () {
      const body = '{"data":[{"kcmc":"数据结构"}],"totalCount":1}';
      final items = ZjuZdbkService.jsonItems(body, what: '开课情况');
      expect(items, hasLength(1));
      expect(items.first['kcmc'], '数据结构');
    });

    test('空 items → 空列表（不抛）', () {
      final items =
          ZjuZdbkService.jsonItems('{"items":[],"totalCount":0}', what: '开课情况');
      expect(items, isEmpty);
    });

    test('非 JSON 响应 → 抛可读 StateError', () {
      expect(
        () => ZjuZdbkService.jsonItems('<html>登录</html>', what: '开课情况'),
        throwsA(isA<StateError>().having(
            (e) => e.message, 'message', contains('响应解析失败'))),
      );
    });
  });

  group('ZjuZdbkService.parsePlans（培养方案）', () {
    const okJson =
        '{"items":[{"jxjhh":"P2025-01","pyfamc":"计算机培养方案",'
        '"zymc":"计算机科学与技术","synj":"2025","minxf":"150"}],'
        '"totalResult":1}';
    const okHtml =
        '<html>{"items":[{"jxjhh":"P2025-02","pyfamc":"软件培养方案",'
        '"zymc":"软件工程","synj":"2025","minxf":"150"}],"totalResult":1}</html>';

    test('正常路径：JSON items 解析', () {
      final plans = ZjuZdbkService.parsePlans(okJson);
      expect(plans, hasLength(1));
      expect(plans.first.planNo, 'P2025-01');
      expect(plans.first.planName, '计算机培养方案');
      expect(plans.first.major, '计算机科学与技术');
    });

    test('非 JSON（HTML 包裹）→ extractItems 回退解析', () {
      final plans = ZjuZdbkService.parsePlans(okHtml);
      expect(plans, hasLength(1));
      expect(plans.first.planName, '软件培养方案');
      expect(plans.first.planNo, 'P2025-02');
    });
  });

  group('ZjuZdbkService.parsePracticeScores（实践成绩）', () {
    test('正常路径：正则提取第二/三/四课堂分数', () {
      const html = '''
<table>
  <tr><td>1</td><td>第二课堂</td><td>2.5</td></tr>
  <tr><td>2</td><td>第三课堂</td><td>1.5</td></tr>
  <tr><td>3</td><td>第四课堂</td><td>0.5</td></tr>
  <tr><td>4</td><td>其他</td><td>99</td></tr>
</table>
''';
      final scores = ZjuZdbkService.parsePracticeScores(html);
      expect(scores['pt2'], 2.5);
      expect(scores['pt3'], 1.5);
      expect(scores['pt4'], 0.5);
    });

    test('无可匹配行 → 全 0', () {
      final scores =
          ZjuZdbkService.parsePracticeScores('<html>无数据</html>');
      expect(scores, {'pt2': 0.0, 'pt3': 0.0, 'pt4': 0.0});
    });
  });

  group('ZjuZdbkService.parseTimetable（课表）', () {
    // 响应含 kbList（正则 `(?<="kbList":)\[(.*?)\](?="xh")` 提取），
    // 其中第二条 sfyjskc=1（已结束）应被过滤。
    const kbJson = '{"kbList":['
        '{"xkkh":"(2026-2027-2)-CS101-001",'
        '"kcb":"数据结构基础<br>秋冬{第1-16周|3节/周}<br>张三<br>紫金港东1A-301",'
        '"xqj":"3","djj":"1","skcd":"2","dsz":"1-16","sfyjskc":"0","xf":"4.0"},'
        '{"xkkh":"(2026-2027-1)-PHY101-001",'
        '"kcb":"大学物理<br>秋{第1-16周|2节/周}<br>李四<br>紫金港西2-205",'
        '"xqj":"2","djj":"3","skcd":"2","dsz":"1-16","sfyjskc":"1","xf":"3.0"}'
        '],"xh":"3200100000"}';

    test('正常路径：kbList 解析 + 过滤已结束课程', () {
      final sessions = ZjuZdbkService.parseTimetable(kbJson);
      expect(sessions, hasLength(1));
      expect(sessions.first.courseName, '数据结构基础');
      expect(sessions.first.teacher, '张三');
      expect(sessions.first.location, '紫金港东1A-301');
      expect(sessions.first.dayOfWeek, 3);
      expect(sessions.first.periods, [1, 2]);
      expect(sessions.first.semester, 24); // 秋冬 → 秋(8)|冬(16)
      expect(sessions.first.courseYear, 2026);
      expect(sessions.first.isEnded, false);
    });

    test('无 kbList（页面结构变化/登录页）→ 抛 StateError', () {
      expect(
        () => ZjuZdbkService.parseTimetable('<html>登录</html>'),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('ZjuZdbkService.isPdfBytes（PDF 文件头校验）', () {
    test('%PDF 头 → true', () {
      expect(ZjuZdbkService.isPdfBytes([0x25, 0x50, 0x44, 0x46, 1, 2, 3]),
          isTrue);
    });

    test('非 PDF（如 HTML）→ false', () {
      expect(ZjuZdbkService.isPdfBytes('<html>'.codeUnits), isFalse);
    });

    test('空 / 不足 4 字节 → false', () {
      expect(ZjuZdbkService.isPdfBytes(const []), isFalse);
      expect(ZjuZdbkService.isPdfBytes(const [0x25, 0x50]), isFalse);
    });
  });
}
