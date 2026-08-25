/// DataOrchestrator 文件下载声明查询测试（T8a）：registerFile / fileOf / fileByName。
library;

import 'package:test/test.dart';

import '../orchestrator.dart';
import '../type.dart';
import '../plugin/data_source_manifest.dart';

void main() {
  const type = DataType<Map<String, dynamic>>(name: 'documents');

  DataOrchestrator orch() => DataOrchestrator();

  test('registerFile 后 fileOf / fileByName 返回声明', () {
    final o = orch();
    o.register(type, () async => <String, dynamic>{});
    const decl =
        DataSourceFileDecl(enabled: true, downloadEndpoint: '/download');
    o.registerFile('documents', decl);

    expect(o.fileOf(type), same(decl));
    expect(o.fileByName('documents'), same(decl));
  });

  test('未登记 / 未注册返回 null', () {
    final o = orch();
    o.register(type, () async => <String, dynamic>{});
    expect(o.fileOf(type), isNull);
    expect(o.fileByName('documents'), isNull);
    expect(o.fileByName('ghost'), isNull);
  });

  test('registerFile(null) 清除既有声明（重注册语义收敛）', () {
    final o = orch();
    o.register(type, () async => <String, dynamic>{});
    o.registerFile('documents',
        const DataSourceFileDecl(enabled: true, downloadEndpoint: '/d'));
    expect(o.fileByName('documents'), isNotNull);

    o.registerFile('documents', null);
    expect(o.fileByName('documents'), isNull);
  });

  test('unregister 连带清除文件声明', () {
    final o = orch();
    o.register(type, () async => <String, dynamic>{});
    o.registerFile('documents',
        const DataSourceFileDecl(enabled: true, downloadEndpoint: '/d'));
    o.unregister(type);

    expect(o.fileByName('documents'), isNull);
  });

  test('enabled=false 的声明仍可被查询（由消费方判 enabled）', () {
    final o = orch();
    o.register(type, () async => <String, dynamic>{});
    const decl = DataSourceFileDecl(enabled: false);
    o.registerFile('documents', decl);

    expect(o.fileOf(type), same(decl));
    expect(o.fileOf(type)!.enabled, isFalse);
  });
}
