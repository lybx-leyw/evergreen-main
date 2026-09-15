/// 平台级「打开本地文件」服务——供文件型数据源 UI 的「播放/打开」使用。
///
/// 方案：`docs/plugin-registry/file-source-plugin-plan-v1.md` §8.5 未接线项。
///
/// # 为什么放 renderer 而非 core
/// `url_launcher` 是 **renderer 包**的依赖（`data_list_slot.dart` 已在用），
/// `lib/core` 包未声明它。且「打开文件」本质是 UI 关切，与数据中枢无关——
/// 放 renderer 既符合分层，也避免给 core 引入新依赖。
///
/// # 为什么不需要写平台分支
/// `launchUrl(Uri.file(path))` 会走各平台原生机制（Windows ShellExecute /
/// macOS `open` / Linux `xdg-open` / **Android Intent**），仓库已含
/// `url_launcher_windows`。故无需自定义 MethodChannel，也无需改 `MainActivity.kt`。
///
/// # 沙箱
/// 本服务只「打开」不写入，故不经 `PathSandbox`；调用方应只传平台校验过的
/// 缓存路径（协议 §7）。
library;

import 'dart:io';

import 'package:url_launcher/url_launcher.dart';

import 'package:evergreen_base/core/errors.dart';
import 'package:evergreen_base/core/result.dart';

/// 打开本地文件（交给系统默认应用）；成功返回 `Ok(<绝对路径>)`。
Future<Result<String>> openLocalFile(String path) async {
  if (path.trim().isEmpty) {
    return Err(AppError.validationError('路径为空'));
  }
  final file = File(path);
  if (!file.existsSync()) {
    return Err(AppError.validationError('文件不存在: $path'));
  }
  final abs = file.absolute.path;
  try {
    final ok = await launchUrl(Uri.file(abs));
    if (!ok) {
      return Err(AppError.unknown('系统未能打开该文件（可能无默认应用）: $abs'));
    }
    return Ok(abs);
  } catch (e) {
    return Err(AppError.unknown('打开文件失败: $e'));
  }
}
