/// 主题注册框架——外部插件通过 theme.json 提供全局配色方案。
///
/// 下游渲染层根据 [ThemeDescriptor] 中声明的语义 token 和组件 token
/// 替换对应 UI 组件的颜色。
///
/// # 导出模块
///
/// | 模块 | 职责 |
/// |------|------|
/// | `theme_descriptor.dart` | ThemeDescriptor 数据模型 |
/// | `theme_store.dart` | ThemeStore 响应式存储器 |
/// | `theme_loader.dart` | scanThemes / loadThemes / scanThemeFile |
/// | `theme_http_server.dart` | ThemeHttpServer 6 端点 |
/// | `render_rules.dart` | 像素级设计常量 |
/// | `src/color.dart` | ThemeColor 颜色值对象 |
library;

export 'theme_descriptor.dart';
export 'theme_store.dart';
export 'theme_loader.dart';
export 'theme_http_server.dart';
export 'render_rules.dart';
export 'src/color.dart';
