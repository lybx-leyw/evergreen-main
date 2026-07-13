/// HTML render: renderScanner（M3 `scanner`）。
///
/// 渲染扫码视图占位 + 手动输入框；运行时 JS（独立注入）尝试 getUserMedia +
/// BarcodeDetector，不支持则保留手动输入（R5/R9）。
library;

import 'dart:convert';

import '../shared/html_helpers.dart';

String renderScanner(Map<String, dynamic> comp) {
  final rawCfg = comp['config'];
  final cfg = rawCfg is Map ? rawCfg.cast<String, dynamic>() : <String, dynamic>{};
  final hint = esc(cfg['hint'] as String? ?? '将镜头对准二维码 / 条码');
  final mode = esc(cfg['mode'] as String? ?? 'qr');
  final emit = esc(cfg['emitEvent'] as String? ?? 'code_scanned');

  return '''
<div class="evg-comp evg-comp-scanner">
  <div class="evg-scanner-view" id="evg-scan">
    <div class="evg-scanner-placeholder">📷</div>
  </div>
  <div class="evg-scanner-hint">$hint（模式：$mode）</div>
  <input class="evg-scanner-input" data-emit="$emit" placeholder="无相机时手动输入编码" />
</div>''';
}
