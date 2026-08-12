/// scores feature 单测（B3 第二接入，B4-fix 适配 HttpClient 版 service）：
/// - ZjuGrade 模型 fromJson（jd 权威绩点 / fallback）/ toJson 往返 / 派生字段
/// - ZjuGpaCalculator：4 刻度 GPA / 分组 / 首修-最高策略
/// - ZjuZdbkService.parseGrades：静态解析成绩单（service 网络逻辑已改 HttpClient，不再 mock）
library;

import 'package:evergreen_base/renderer/templates/zju_modle/shared/models/zju_grade.dart';
import 'package:evergreen_base/renderer/templates/zju_modle/shared/utils/zju_gpa_calculator.dart';
import 'package:evergreen_base/renderer/templates/zju_modle/zdbk/services/zdbk_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ZjuGrade 模型', () {
    test('fromJson 优先使用 ZDBK 权威 jd 绩点', () {
      final g = ZjuGrade.fromJson({
        'xkkh': '(2024-2025-1)-CS101-001',
        'kcmc': '数据结构',
        'xf': 3.0,
        'cj': '95',
        'jd': 5.0,
        'major': true,
      });
      expect(g.id, '(2024-2025-1)-CS101-001');
      expect(g.name, '数据结构');
      expect(g.credit, 3.0);
      expect(g.original, '95');
      expect(g.fivePoint, 5.0);
      expect(g.fivePointSource, ZjuFivePointSource.jd);
      expect(g.major, isTrue);
    });

    test('jd 缺失/非数字 → fallback 从 cj 估算', () {
      final g = ZjuGrade.fromJson({
        'xkkh': 'x1',
        'kcmc': '高数',
        'xf': 4.5,
        'cj': '优',
      });
      expect(g.fivePoint, 5.0); // 优 → 5.0
      expect(g.fivePointSource, ZjuFivePointSource.fallback);
    });

    test('toJson → fromJson 往返一致', () {
      final src = ZjuGrade(
        id: '(2024-2025-1)-CS101-001',
        name: '数据结构',
        credit: 3.0,
        original: '95',
        fivePoint: 5.0,
        fivePointSource: ZjuFivePointSource.jd,
      );
      final round = ZjuGrade.fromJson(src.toJson());
      expect(round.id, src.id);
      expect(round.name, src.name);
      expect(round.credit, src.credit);
      expect(round.original, src.original);
      expect(round.fivePoint, src.fivePoint);
      expect(round.fivePointSource, src.fivePointSource);
    });

    test('派生字段：realId 归一重修 / earnedCredit / hundredPoint / 排除', () {
      final g = ZjuGrade.fromJson({
        'xkkh': '(2023-2024-2)-CS101-001',
        'kcmc': '数据结构',
        'xf': 3.0,
        'cj': '86',
        'jd': 4.2,
      });
      expect(g.realId, '(2023-2024-2)-CS101'); // 去掉重修后缀
      expect(g.earnedCredit, 3.0);
      expect(g.fourPointGpa, 4.0); // 4.2 → 映射表 4.0
      expect(g.hundredPoint, 86);

      final failed = ZjuGrade.fromJson({
        'xkkh': 'x2',
        'kcmc': '弃修课',
        'xf': 2.0,
        'cj': '弃修',
        'jd': 0.0,
      });
      expect(failed.isExcludedFromGpa, isTrue);
      expect(failed.earnedCredit, 0.0);
    });
  });

  group('ZjuGpaCalculator', () {
    List<ZjuGrade> _sample() => [
          ZjuGrade.fromJson({
            'xkkh': '(2024-2025-1)-CS101-001',
            'kcmc': 'A',
            'xf': 3.0,
            'cj': '90',
            'jd': 5.0,
          }),
          ZjuGrade.fromJson({
            'xkkh': '(2024-2025-1)-CS102-001',
            'kcmc': 'B',
            'xf': 3.0,
            'cj': '80',
            'jd': 4.0,
          }),
          ZjuGrade.fromJson({
            'xkkh': '(2024-2025-1)-CS103-001',
            'kcmc': 'C',
            'xf': 2.0,
            'cj': '弃修',
            'jd': 0.0,
          }),
        ];

    test('calculateGpa 加权平均（排除弃修）', () {
      final r = ZjuGpaCalculator.calculateGpa(_sample());
      // 排除弃修后：学分 3+3=6；五分制 (5*3+4*3)/6=4.5
      expect(r.fivePoint, closeTo(4.5, 1e-9));
      // 4.3 刻度：5.0→4.3、4.0→4.0 → (4.3*3+4.0*3)/6=4.15
      expect(r.fourPoint, closeTo(4.15, 1e-9));
      expect(r.earnedCredits, closeTo(6.0, 1e-9)); // 弃修不计
    });

    test('groupByCourseId 以 realId 分组（重修合并）', () {
      final grades = [
        ZjuGrade.fromJson({
          'xkkh': '(2024-2025-1)-CS101-001',
          'kcmc': 'A',
          'xf': 3.0,
          'cj': '70',
          'jd': 3.0,
        }),
        ZjuGrade.fromJson({
          'xkkh': '(2024-2025-1)-CS101-002',
          'kcmc': 'A（重修）',
          'xf': 3.0,
          'cj': '95',
          'jd': 5.0,
        }),
      ];
      final groups = ZjuGpaCalculator.groupByCourseId(grades);
      expect(groups, hasLength(1));
      expect(groups.values.first, hasLength(2));
    });

    test('pickFirstAttempt 取首次 / pickHighestAttempt 取最高', () {
      final grades = [
        ZjuGrade.fromJson({
          'xkkh': '(2024-2025-1)-CS101-001',
          'kcmc': 'A',
          'xf': 3.0,
          'cj': '70',
          'jd': 3.0,
        }),
        ZjuGrade.fromJson({
          'xkkh': '(2024-2025-1)-CS101-002',
          'kcmc': 'A（重修）',
          'xf': 3.0,
          'cj': '95',
          'jd': 5.0,
        }),
      ];
      final first = ZjuGpaCalculator.pickFirstAttempt(grades);
      expect(first, hasLength(1));
      expect(first.single.fivePoint, 3.0);

      final highest = ZjuGpaCalculator.pickHighestAttempt(grades);
      expect(highest, hasLength(1));
      expect(highest.single.fivePoint, 5.0);
    });

    test('ZjuGpaResult toJson → fromJson 往返', () {
      const r = ZjuGpaResult(
        fivePoint: 4.5,
        fourPoint: 4.1,
        fourPointLegacy: 3.9,
        hundredPoint: 87.5,
        earnedCredits: 42.0,
      );
      final round = ZjuGpaResult.fromJson(r.toJson());
      expect(round.fivePoint, 4.5);
      expect(round.fourPoint, 4.1);
      expect(round.fourPointLegacy, 3.9);
      expect(round.hundredPoint, 87.5);
      expect(round.earnedCredits, 42.0);
    });
  });

  group('ZjuZdbkService.parseGrades（成绩单静态解析）', () {
    // 正常成绩单响应（JSON items，走 ZdbkPatterns.itemsWithTotalResult）
    const okBody =
        '{"items":[{"xkkh":"(2024-2025-1)-CS101-001","kcmc":"数据结构",'
        '"xf":3.0,"cj":"95","jd":5.0},{"xkkh":"(2024-2025-1)-CS102-001",'
        '"kcmc":"高数","xf":4.5,"cj":"优","jd":4.8}],"totalResult":2}';

    test('正常路径：解析成绩列表（保留 jd 绩点）', () {
      final grades = ZjuZdbkService.parseGrades(okBody, what: '成绩单');
      expect(grades, hasLength(2));
      expect(grades.first.name, '数据结构');
      expect(grades.first.fivePoint, 5.0);
      expect(grades[1].fivePointSource, ZjuFivePointSource.jd);
    });

    test('过滤无 xkkh 的占位行', () {
      const body =
          '{"items":[{"xkkh":"(2024-2025-1)-CS101-001","kcmc":"数据结构",'
          '"xf":3.0,"cj":"95"},{"kcmc":"占位行","xf":0,"cj":"0"}],'
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
}
