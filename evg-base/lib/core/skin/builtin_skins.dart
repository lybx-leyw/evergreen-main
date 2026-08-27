/// 内置皮肤包——代码注册的默认皮肤包（不依赖文件系统/插件扫描）。
///
/// 决策 1.2：未加装任何皮肤包时可用——像现在的亮暗色 theme 一样直接编码内置。
/// 内置 id 使用 `skin-default`（避免与主题的 dark/light/default 哨兵混淆）。
/// 默认皮肤包**只声明少数用户明确要求的覆盖**（R2-1 思考框橙黄、R2-3 用户气泡
/// 调淡），其余 DIY 段全部 null → 渲染层其余消费点回退现有默认值，保证
/// 「未装皮肤包时 UI 与行为与现状一致」。
library;

import 'skin_descriptor.dart';
import 'skin_store.dart';

/// 内置皮肤包列表（注册顺序即设置面板默认展示顺序）。
const List<SkinDescriptor> builtinSkins = [
  SkinDescriptor(
    id: 'skin-default',
    name: '默认皮肤',
    version: '1.0.0',
    description: '内置默认皮肤包：思考框恢复历史橙黄配色；用户气泡调淡；其余跟随平台主题。',
    raw: {
      // R2-1 思考框橙黄：AI 助手优化计划之前的思考气泡就是橙黄橙黄的
      // （历史背景 0xFFFFF8E1 / 边框 0xFFFFE082），默认皮肤恢复该配色。
      'thinking': {
        'colors': {
          'containerBackground': '#FFF8E1',
          'containerBorder': '#FFE082',
        },
      },
      // R2-3 用户气泡调淡：原来偏深（theme primary），默认皮肤改为
      // 淡蓝 #E3F2FD + 深蓝文字 #0D47A1（保证浅底上的可读性）。
      'bubble': {
        'userBackgroundColor': '#E3F2FD',
        'userTextColor': '#0D47A1',
      },
      // R2-3 补充：用户头像底色淡色（#E3F2FD 与气泡同系；不强制默认 SVG，
      // 无图片时渲染层用浅底 + 深色 person 图标自适应）。
      'avatar': {
        'userBackgroundColor': '#E3F2FD',
      },
      // 第三轮 R3-1：输入框上方按钮去冗余——工作区/工具/skill 在顶栏
      // （抽屉/工作区/工具/skill）已出现，输入框那排不再重复显示；
      // 联网搜索/思考档位/后台进程/清空保持缺省显示。
      'buttons': {
        'inputBar': {
          'workspace': false,
          'tools': false,
          'skills': false,
        },
      },
    },
  ),
];

/// 把内置皮肤包注册进 [store]。幂等：同 id 覆盖。
void registerBuiltinSkins(SkinStore store) {
  for (final s in builtinSkins) {
    store.register(s);
  }
}
