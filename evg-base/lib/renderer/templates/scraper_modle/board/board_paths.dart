/// Scraper 路径工具（多画板容器与工作区共用）。
library board_paths;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:evergreen_base/core/utils/greenix_path.dart';

/// 计算项目根目录（与 ScraperGeneratorView._findProjectRoot 一致）。
String findProjectRoot() {
  // 安卓：进程 CWD=/ 且无 pubspec.yaml，greenix 根 = 插件目录的父级
  //（与 AppBootstrap._stepGreenixPaths 一致：.config_port 写在这里）。
  if (Platform.isAndroid) {
    return p.dirname(androidPluginsDir);
  }
  var dir = Directory.current;
  while (true) {
    if (File(p.join(dir.path, 'pubspec.yaml')).existsSync()) {
      return dir.path;
    }
    final parent = dir.parent;
    if (parent.path == dir.path) break;
    dir = parent;
  }
  return Directory.current.path;
}

/// 计算 scraper 工作区目录（画板元数据/快照/会话落盘位置）。
String scraperWorkspaceDir(String moduleId) {
  final dir = greenixWorkspaceDir('$moduleId/scraper_output');
  Directory(dir).createSync(recursive: true);
  return dir;
}
