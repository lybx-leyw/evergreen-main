/// CredentialStore 测试——统一凭据读写 / 镜像 / isSecure / 写锁。
library;

import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import 'package:shared_preferences/shared_preferences.dart';

import '../credential_store.dart';

void main() {
  late SharedPreferences prefs;
  late Directory tmp;

  String cfgPath(String name) =>
      '${tmp.path}${Platform.pathSeparator}$name';

  setUp(() async {
    prefs = await SharedPreferences.getInstance();
    tmp = Directory.systemTemp.createTempSync('cred_store_test_');
  });

  tearDown(() {
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  group('读写', () {
    test('set 后 get 返回写入值', () async {
      final store = CredentialStore(prefs: prefs);
      await store.set('SCRAPER_USERNAME', 'alice');
      expect(store.get('SCRAPER_USERNAME'), 'alice');
      expect(store.has('SCRAPER_USERNAME'), isTrue);
    });

    test('get 未写入返回 null，has 返回 false', () {
      final store = CredentialStore(prefs: prefs);
      expect(store.get('MISSING_KEY'), isNull);
      expect(store.has('MISSING_KEY'), isFalse);
    });

    test('delete 后 get 返回 null', () async {
      final store = CredentialStore(prefs: prefs);
      await store.set('K', 'v');
      await store.delete('K');
      expect(store.get('K'), isNull);
      expect(store.has('K'), isFalse);
    });

    test('set 空值等价于删除', () async {
      final store = CredentialStore(prefs: prefs);
      await store.set('K', 'v');
      await store.set('K', '');
      expect(store.get('K'), isNull);
    });
  });

  group('config.json 镜像', () {
    test('set 写入镜像文件并保留其它 key', () async {
      final path = cfgPath('config.json');
      File(path).writeAsStringSync(jsonEncode({'OTHER': 'keep'}));
      final store = CredentialStore(prefs: prefs, configPath: path);

      await store.set('SECRET', 's3cret');

      final map = jsonDecode(File(path).readAsStringSync()) as Map;
      expect(map['SECRET'], 's3cret');
      expect(map['OTHER'], 'keep'); // 保留其它 key（读改写）
    });

    test('delete 从镜像文件移除该 key', () async {
      final path = cfgPath('config.json');
      File(path).writeAsStringSync(jsonEncode({'A': '1', 'B': '2'}));
      final store = CredentialStore(prefs: prefs, configPath: path);

      await store.delete('A');

      final map = jsonDecode(File(path).readAsStringSync()) as Map;
      expect(map.containsKey('A'), isFalse);
      expect(map['B'], '2');
    });

    test('get 回退到 config.json（SP 为空）', () async {
      final path = cfgPath('config.json');
      File(path).writeAsStringSync(jsonEncode({'CFG_ONLY': 'from_file'}));
      final store = CredentialStore(prefs: prefs, configPath: path);
      expect(store.get('CFG_ONLY'), 'from_file');
      expect(store.has('CFG_ONLY'), isTrue);
    });

    test('SP 非空优先于 config.json', () async {
      final path = cfgPath('config.json');
      File(path).writeAsStringSync(jsonEncode({'K': 'file'}));
      final store = CredentialStore(prefs: prefs, configPath: path);
      await store.set('K', 'sp');
      expect(store.get('K'), 'sp');
    });
  });

  group('env.json 镜像', () {
    test('mirrorEnv=true 时写 env.json', () async {
      final env = cfgPath('env.json');
      final cfg = cfgPath('config.json');
      final store = CredentialStore(
          prefs: prefs, configPath: cfg, envPath: env);

      await store.set('SCRAPER_TOKEN', 'tok', mirrorEnv: true);

      final envMap = jsonDecode(File(env).readAsStringSync()) as Map;
      expect(envMap['SCRAPER_TOKEN'], 'tok');
      final cfgMap = jsonDecode(File(cfg).readAsStringSync()) as Map;
      expect(cfgMap['SCRAPER_TOKEN'], 'tok');
    });

    test('mirrorEnv=false（默认）不写 env.json', () async {
      final env = cfgPath('env.json');
      final store = CredentialStore(prefs: prefs, envPath: env);
      await store.set('K', 'v');
      expect(File(env).existsSync(), isFalse);
    });
  });

  group('isSecure', () {
    test('set(isSecure:true) 标记安全 key', () async {
      final store = CredentialStore(prefs: prefs);
      await store.set('API_KEY', 'x', isSecure: true);
      expect(store.isSecure('API_KEY'), isTrue);
      expect(store.secureKeys, contains('API_KEY'));
    });

    test('set(isSecure:false) 不标记安全 key', () async {
      final store = CredentialStore(prefs: prefs);
      await store.set('PUBLIC', 'x', isSecure: false);
      expect(store.isSecure('PUBLIC'), isFalse);
      expect(store.secureKeys, isNot(contains('PUBLIC')));
    });

    test('默认 isSecure=false', () async {
      final store = CredentialStore(prefs: prefs);
      await store.set('K', 'x');
      expect(store.isSecure('K'), isFalse);
    });

    test('重写为非安全后清除标记', () async {
      final store = CredentialStore(prefs: prefs);
      await store.set('K', 'x', isSecure: true);
      await store.set('K', 'y', isSecure: false);
      expect(store.isSecure('K'), isFalse);
    });

    test('delete 清除安全标记', () async {
      final store = CredentialStore(prefs: prefs);
      await store.set('K', 'x', isSecure: true);
      await store.delete('K');
      expect(store.isSecure('K'), isFalse);
    });
  });

  group('写路径互斥（锁）', () {
    test('并发写不同 key 全部落盘（不交叉丢失）', () async {
      final path = cfgPath('config.json');
      final store = CredentialStore(prefs: prefs, configPath: path);

      await Future.wait([
        for (var i = 0; i < 20; i++) store.set('KEY_$i', 'v$i'),
      ]);

      final map = jsonDecode(File(path).readAsStringSync()) as Map;
      for (var i = 0; i < 20; i++) {
        expect(map['KEY_$i'], 'v$i');
      }
    });

    test('并发写同 key 串行落盘（最后写入胜出）', () async {
      final path = cfgPath('config.json');
      final store = CredentialStore(prefs: prefs, configPath: path);

      await Future.wait([
        store.set('SAME', 'a'),
        store.set('SAME', 'b'),
        store.set('SAME', 'c'),
        store.set('SAME', 'd'),
      ]);

      final map = jsonDecode(File(path).readAsStringSync()) as Map;
      expect(map['SAME'], 'd'); // 调用顺序串行，最后写入胜出
      expect(store.get('SAME'), 'd');
    });
  });

  group('writeCredentialDirect', () {
    test('直写 SP + config.json，不依赖 HTTP', () async {
      final path = cfgPath('config.json');
      await writeCredentialDirect(
        prefs: prefs,
        key: 'SCRAPER_PASSWORD',
        value: 'p@ss',
        configPath: path,
      );
      expect(prefs.getString('SCRAPER_PASSWORD'), 'p@ss');
      final map = jsonDecode(File(path).readAsStringSync()) as Map;
      expect(map['SCRAPER_PASSWORD'], 'p@ss');
    });
  });
}
