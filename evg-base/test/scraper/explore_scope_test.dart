// explore_scope 测试（P0-1 Scope Contract 持久化授权）。
//
// 覆盖：
// 1. validateUrl 授权边界：http(s) 校验 / host 精确与子域通配 / path 前缀 / 越界拒绝
// 2. JSON 往返（.greenix/scope.json 持久化）+ 容错解析
// 3. isActive 状态 / toPromptSummary（Guardian 注入）/ toDisplaySummary（UI）
import 'package:evergreen_base/renderer/templates/scraper_modle/explore/explore_scope.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ExploreScope.validateUrl（授权边界）', () {
    const scope = ExploreScope(
      name: 'ZJU 教务课程',
      baseHost: 'zju.edu.cn',
      assets: ['zju.edu.cn', '*.zju.edu.cn'],
      paths: ['/course', '/api/courses'],
      dataScope: '课程列表与详情',
    );

    test('授权内放行：http/https + 精确 host + 前缀路径', () {
      expect(scope.validateUrl('https://zju.edu.cn/course/123'), isNull);
      expect(scope.validateUrl('http://zju.edu.cn/api/courses?term=2026'), isNull);
    });

    test('子域通配放行：*.zju.edu.cn 命中子域', () {
      expect(scope.validateUrl('https://jwxt.zju.edu.cn/course/list'), isNull);
    });

    test('越界拒绝：非 http(s) 协议', () {
      expect(
        scope.validateUrl('ftp://zju.edu.cn/course'),
        contains('仅允许 http/https'),
      );
    });

    test('越界拒绝：host 不在授权资产内', () {
      expect(
        scope.validateUrl('https://evil.com/course'),
        contains('不在授权资产'),
      );
    });

    test('越界拒绝：路径不在授权前缀内', () {
      expect(
        scope.validateUrl('https://zju.edu.cn/admin/users'),
        contains('不在授权路径'),
      );
    });

    test('paths 为空 = 路径全部放行', () {
      const openScope = ExploreScope(
        name: '公开站点',
        baseHost: 'example.com',
        assets: ['example.com'],
      );
      expect(openScope.validateUrl('https://example.com/anything/deep'), isNull);
    });

    test('空 URL / 无法解析 / 无主机均拒绝', () {
      expect(scope.validateUrl(''), isNotNull);
      expect(scope.validateUrl('   '), isNotNull);
      expect(scope.validateUrl('https://'), contains('缺少主机名'));
    });
  });

  group('ExploreScope JSON 往返（持久化）', () {
    test('toJson → fromJson 往返保真', () {
      final signed = DateTime.utc(2026, 8, 17, 8, 30);
      final scope = ExploreScope(
        name: 'ZJU 教务课程',
        baseHost: 'zju.edu.cn',
        assets: const ['zju.edu.cn', '*.zju.edu.cn'],
        paths: const ['/course'],
        dataScope: '课程列表',
        signedAt: signed,
      );
      final restored = ExploreScope.fromJson(scope.toJson());
      expect(restored.name, scope.name);
      expect(restored.baseHost, scope.baseHost);
      expect(restored.assets, scope.assets);
      expect(restored.paths, scope.paths);
      expect(restored.dataScope, scope.dataScope);
      expect(restored.signedAt, signed);
      expect(restored.status, 'active');
      expect(restored.isActive, isTrue);
    });

    test('signedAt 为 null 时落盘当前时间（ISO8601 可解析）', () {
      const scope = ExploreScope(
        name: 'x',
        baseHost: 'example.com',
        assets: ['example.com'],
      );
      final json = scope.toJson();
      expect(json['signedAt'], isA<String>());
      expect(DateTime.tryParse(json['signedAt'] as String), isNotNull);
    });

    test('fromJson 容错：缺失字段 / 脏数据清洗', () {
      final restored = ExploreScope.fromJson({
        'name': '  x  ',
        'baseHost': ' example.com ',
        'assets': [' Example.COM ', '', null],
        'paths': [' /course ', ''],
        'dataScope': null,
      });
      expect(restored.name, 'x');
      expect(restored.baseHost, 'example.com');
      expect(restored.assets, ['example.com']);
      expect(restored.paths, ['/course']);
      expect(restored.dataScope, '');
      expect(restored.status, 'active');
    });
  });

  group('ExploreScope 摘要', () {
    test('toPromptSummary 包含 Guardian 注入关键字段', () {
      const scope = ExploreScope(
        name: 'ZJU 教务课程',
        baseHost: 'zju.edu.cn',
        assets: ['zju.edu.cn', '*.zju.edu.cn'],
        paths: ['/course'],
        dataScope: '课程列表与详情',
      );
      final s = scope.toPromptSummary();
      expect(s, contains('ZJU 教务课程'));
      expect(s, contains('zju.edu.cn'));
      expect(s, contains('/course'));
      expect(s, contains('课程列表与详情'));
      expect(s, contains('GET only'));
    });

    test('toDisplaySummary 聚合站点/路径/范围', () {
      const scope = ExploreScope(
        name: 'x',
        baseHost: 'zju.edu.cn',
        assets: ['zju.edu.cn'],
        paths: ['/course'],
        dataScope: '课程',
      );
      expect(scope.toDisplaySummary(), contains('zju.edu.cn'));
      expect(scope.toDisplaySummary(), contains('/course'));
      expect(scope.toDisplaySummary(), contains('课程'));
    });
  });
}
