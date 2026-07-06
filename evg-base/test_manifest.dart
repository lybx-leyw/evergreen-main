import 'dart:convert';
import 'dart:io';
import 'package:evergreen_base/core/module/module_descriptor.dart';
void main() {
  final f = File(r'..\plugins\showcase\module\manifest.json');
  final json = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
  final d = ModuleDescriptor.fromJson(json);
  print('showcase: OK, pages=${d.pages.length}, hasSidebar=${d.hasSidebar}, process=${d.process.length}');
  for (int i = 0; i < d.pages.length; i++) {
    final p = d.pages[i];
    print('  page[$i]: ${p.id}, slots=${p.layout.slots.length}');
  }
  final f2 = File(r'..\plugins\showcase-dart\module\manifest.json');
  final json2 = jsonDecode(f2.readAsStringSync()) as Map<String, dynamic>;
  final d2 = ModuleDescriptor.fromJson(json2);
  print('showcase-dart: OK, pages=${d2.pages.length}, hasSidebar=${d2.hasSidebar}');
}
