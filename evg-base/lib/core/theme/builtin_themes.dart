/// 内置主题——代码注册的扁平 8 色主题（不依赖文件系统/插件扫描）。
///
/// 优先级设计（与 theme_loader 注释一致）：`store.register()`（本文件）
/// 最高，插件主题（plugins/<name>/theme/theme.json）与示例主题次之；
/// 同 id 后者覆盖。内置 id 使用 `dark` / `light` / `evergreen`，
/// 插件不应与之冲突（见 docs/plugin-theme.md 校验清单）。
library;

import 'theme_descriptor.dart';
import 'theme_store.dart';

/// 内置主题列表（注册顺序即默认展示顺序）。
///
/// 色板来源：
/// - `dark`：GitHub Dark 色板——与组件层既有硬编码色（终端/气泡/日志面板）
///   同源，作为默认主题时观感最一致；
/// - `light`：GitHub Light 色板；
/// - `evergreen`：品牌绿（深色系，呼应产品名）。
const List<ThemeDescriptor> builtinThemes = [
  ThemeDescriptor(
    id: 'dark',
    name: '深色（GitHub Dark）',
    colors: {
      'background': '#0D1117',
      'surface': '#161B22',
      'border': '#30363D',
      'text': '#C9D1D9',
      'textSecondary': '#8B949E',
      'accent': '#58A6FF',
      'error': '#FF7B72',
      'others': '#8B949E',
    },
  ),
  ThemeDescriptor(
    id: 'light',
    name: '浅色（GitHub Light）',
    colors: {
      'background': '#FFFFFF',
      'surface': '#F6F8FA',
      'border': '#D0D7DE',
      'text': '#1F2328',
      'textSecondary': '#656D76',
      'accent': '#0969DA',
      'error': '#CF222E',
      'others': '#57606A',
    },
  ),
  ThemeDescriptor(
    id: 'evergreen',
    name: 'Evergreen 品牌绿',
    colors: {
      'background': '#0E1713',
      'surface': '#15231D',
      'border': '#2C4238',
      'text': '#DCE8E1',
      'textSecondary': '#8FA99C',
      'accent': '#3FB950',
      'error': '#F85149',
      'others': '#56D364',
    },
  ),
];

/// 把内置主题注册进 [store]。幂等：同 id 覆盖。
void registerBuiltinThemes(ThemeStore store) {
  for (final t in builtinThemes) {
    store.register(t);
  }
}
