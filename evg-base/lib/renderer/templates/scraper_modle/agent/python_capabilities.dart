/// 工具能力事实源（P2-1 · tool-index，移植自 reverse-skill skills/config/tool-index.md）。
///
/// 运行时扫描本机嵌入式 Python 的 site-packages，把**实际可用**的第三方模块
/// 清单注入 prompt，替代硬编码「只允许标准库 + requests」，从源头消除
/// 「AI 反复尝试 bs4/lxml 被 lint 拦截」的浪费。
///
/// 纯 Dart + dart:io，无 Flutter 依赖，可独立单测。
library python_capabilities;

import 'dart:io';

import 'package:path/path.dart' as p;

/// 危险顶层包名黑名单（与 scraper_guard `_dangerousImports` 对齐，只影响清单展示；
/// 真正拦截仍由 lint 硬拒）。
const Set<String> blockedTopLevelModules = {
  'subprocess',
  'socket',
  'ctypes',
  'pickle',
  'pty',
  'importlib',
  'paramiko',
  'selenium',
  'scrapy',
  'playwright',
};

/// 扫描嵌入式 Python 的 site-packages，返回可用第三方顶层模块名（排序去重）。
///
/// [pythonDir] 为嵌入式 Python 根目录（`.greenix/python`），内部探测：
/// `Lib/site-packages`（Windows 嵌入版）与 `site-packages` 两种布局；
/// 目录不存在 → 返回空列表（无第三方模块，仅标准库）。
///
/// 识别规则：目录 = 包名；`x.py` → `x`；`x.dist-info`/`x.egg-info` → `x`；
/// 隐藏项（`.`/`_` 开头）与黑名单跳过。
List<String> scanPythonSitePackages(String pythonDir) {
  final candidates = [
    p.join(pythonDir, 'Lib', 'site-packages'),
    p.join(pythonDir, 'site-packages'),
  ];
  for (final candidate in candidates) {
    final dir = Directory(candidate);
    if (!dir.existsSync()) continue;
    final names = <String>{};
    try {
      for (final e in dir.listSync(followLinks: false)) {
        final base = p.basename(e.path);
        if (base.startsWith('.') || base.startsWith('_')) continue;
        String? name;
        if (e is Directory) {
          name = base;
        } else if (e is File && base.endsWith('.py')) {
          name = base.substring(0, base.length - 3);
        } else if (base.endsWith('.dist-info') ||
            base.endsWith('.egg-info') ||
            base.endsWith('.egg-link')) {
          name = base.split('-').first;
        }
        if (name == null || name.isEmpty) continue;
        if (blockedTopLevelModules.contains(name.toLowerCase())) continue;
        names.add(name);
      }
    } catch (_) {
      // 目录扫描失败（权限等）→ 保守返回空清单
      return const [];
    }
    final out = names.toList()..sort();
    return out;
  }
  return const [];
}

/// 生成 prompt 注入文本（运行时事实源：可用模块清单）。
String pythonCapabilitiesPrompt(List<String> packages) {
  if (packages.isEmpty) {
    return '可用第三方模块：无（仅 Python 标准库）。'
        '未列出的模块禁止 import（会被 lint 拦截）。';
  }
  return '可用第三方模块：${packages.join(', ')}。'
      '仅上述模块 + Python 标准库可 import；未列出的模块禁止 import（会被 lint 拦截）。';
}
