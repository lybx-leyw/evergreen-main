import 'dart:convert';
import 'dart:io';

import 'package:evergreen_base/core/module/module_descriptor.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final f = File(r'd:\evg-workplace\plugins\showcase-v4\module\manifest.json');
  final m = json.decode(f.readAsStringSync()) as Map<String, dynamic>;
  final module = ModuleDescriptor.fromJson(m);
  final page = module.pages.firstWhere((p) => p.id == 'page_13');
  final treeComp = page.layout.slots['tree']!.component!;
  final mapComp = page.layout.slots['map']!.component!;

  test('tree config has root', () {
    print('tree config: ${treeComp.config}');
    expect(treeComp.config['root'], isNotNull);
  });

  test('map config has map key', () {
    print('map config: ${mapComp.config}');
    expect(mapComp.config['map'], isNotNull);
  });
}
