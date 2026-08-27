/// 皮肤包注册框架——外部插件通过 `plugins/<id>/skin/manifest.json` 提供
/// AI 视图 DIY 皮肤（背景 / 按钮显隐 / 思考栏配色 / 气泡样式 / 头像 / 空状态）。
///
/// 镜像 core/theme 的机制：SkinStore(ChangeNotifier) + SkinLoader 扫描 +
/// builtin_skins 内置默认包；设置面板下拉切换 → `active_skin_id` 持久化 →
/// ChangeNotifier 通知 → AI 视图热切换（与主题切换体验一致）。
///
/// # 导出模块
///
/// | 模块 | 职责 |
/// |------|------|
/// | `skin_descriptor.dart` | SkinDescriptor 数据模型（type 校验 + 各 DIY 段解析） |
/// | `skin_store.dart` | SkinStore 响应式存储器（镜像 ThemeStore） |
/// | `skin_loader.dart` | scanSkins / loadSkins / scanSkinFile（镜像 theme_loader） |
/// | `builtin_skins.dart` | 内置默认皮肤包（skin-default，代码注册） |
library;

export 'skin_descriptor.dart';
export 'skin_store.dart';
export 'skin_loader.dart';
export 'builtin_skins.dart';
