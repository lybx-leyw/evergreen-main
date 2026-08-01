/// html-creator 组件 Slot 注册入口。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:evergreen_base/core/module/module_descriptor.dart';
import 'html_creator_view.dart';

class HtmlCreatorSlot extends ConsumerWidget {
  final ModuleDescriptor? descriptor;
  final ComponentDescriptor? component;
  final String? pluginsDir;

  const HtmlCreatorSlot({
    super.key,
    this.descriptor,
    this.component,
    this.pluginsDir,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return HtmlCreatorView(
      descriptor: descriptor,
      component: component,
      pluginsDir: pluginsDir,
    );
  }
}
