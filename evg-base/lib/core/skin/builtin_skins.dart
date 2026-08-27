/// 内置皮肤包——代码注册的默认皮肤包（不依赖文件系统/插件扫描）。
///
/// 决策 1.2：未加装任何皮肤包时可用——像现在的亮暗色 theme 一样直接编码内置。
/// 内置 id 使用 `skin-default`（避免与主题的 dark/light/default 哨兵混淆）。
/// 默认皮肤包**不声明任何 DIY 段**（全部 null）→ 渲染层所有消费点回退
/// 现有默认值，保证「未装皮肤包时 UI 与行为与现在完全一致」。
library;

import 'skin_descriptor.dart';
import 'skin_store.dart';

/// 内置皮肤包列表（注册顺序即设置面板默认展示顺序）。
const List<SkinDescriptor> builtinSkins = [
  SkinDescriptor(
    id: 'skin-default',
    name: '默认皮肤',
    version: '1.0.0',
    description: '内置默认皮肤包：不覆盖任何渲染点，跟随平台主题。',
  ),
];

/// 把内置皮肤包注册进 [store]。幂等：同 id 覆盖。
void registerBuiltinSkins(SkinStore store) {
  for (final s in builtinSkins) {
    store.register(s);
  }
}
