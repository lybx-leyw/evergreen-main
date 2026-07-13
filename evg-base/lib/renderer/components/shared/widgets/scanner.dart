/// 扫码原子组件（M3 `scanner`）。
///
/// 设计（遵循 M3 规则 R5/R9）：
/// - 平台探测优先降级：非 Android/iOS/Web（如 Windows 桌面无摄像头）→ 直接走
///   手动输入占位，**绝不构造 `MobileScanner`**，保证 Windows 测试确定性不崩。
/// - 支持相机时再用 `mobile_scanner`；运行时相机异常由 `errorBuilder` 兜底。
/// - 识别成功后经 [onScan] 回调（由 ScannerSlot 转发到 pageEventBus）。
library;

import 'dart:io';

import 'package:evergreen_base/renderer/components/shared/widgets/empty_state.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

/// 是否具备摄像头能力（按平台类别判定）。
bool supportsCamera() {
  if (kIsWeb) return true;
  return Platform.isAndroid || Platform.isIOS;
}

class ScannerWidget extends StatelessWidget {
  final String mode;
  final List<String> formats;
  final bool continuous;
  final String hint;
  final void Function(String code, String? format)? onScan;

  const ScannerWidget({
    super.key,
    this.mode = 'qr',
    this.formats = const [],
    this.continuous = false,
    this.hint = '将镜头对准二维码 / 条码',
    this.onScan,
  });

  @override
  Widget build(BuildContext context) {
    if (!supportsCamera()) {
      return _manualFallback();
    }
    final controller = MobileScannerController(
      formats: _toBarcodeFormats(formats),
    );
    final theme = Theme.of(context);
    return Column(
      children: [
        Expanded(
          child: MobileScanner(
            controller: controller,
            errorBuilder: (ctx, error, child) => _manualFallback(error: error),
            onDetect: (capture) {
              final barcode = capture.barcodes
                  .where((b) => b.rawValue != null && b.rawValue!.isNotEmpty)
                  .firstOrNull;
              if (barcode == null) return;
              onScan?.call(barcode.rawValue!, barcode.format.name);
              if (!continuous) controller.stop();
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(8),
          child: Text(hint, style: theme.textTheme.bodySmall),
        ),
      ],
    );
  }

  Widget _manualFallback({Object? error}) {
    final controller = TextEditingController();
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.qr_code_2,
              size: 48, color: Colors.grey.shade500),
          const SizedBox(height: 8),
          Text(
            error != null ? '相机不可用，请手动输入' : '扫码需在带摄像头的移动端 / 设备',
            style: TextStyle(color: Colors.grey.shade600),
          ),
          const SizedBox(height: 4),
          Text(hint,
              style: TextStyle(
                  color: Colors.grey.shade500, fontSize: 12)),
          const SizedBox(height: 8),
          TextField(
            controller: controller,
            decoration: const InputDecoration(labelText: '手动输入编码'),
            onSubmitted: (v) {
              if (v.isNotEmpty) onScan?.call(v, null);
            },
          ),
        ],
      ),
    );
  }
}

List<BarcodeFormat> _toBarcodeFormats(List<String> formats) {
  const map = <String, BarcodeFormat>{
    'qr_code': BarcodeFormat.qrCode,
    'ean_13': BarcodeFormat.ean13,
    'ean_8': BarcodeFormat.ean8,
    'code_128': BarcodeFormat.code128,
    'code_39': BarcodeFormat.code39,
    'upc_a': BarcodeFormat.upcA,
    'upc_e': BarcodeFormat.upcE,
    'pdf417': BarcodeFormat.pdf417,
    'aztec': BarcodeFormat.aztec,
    'data_matrix': BarcodeFormat.dataMatrix,
  };
  return formats
      .where((f) => map.containsKey(f))
      .map((f) => map[f]!)
      .toList();
}
