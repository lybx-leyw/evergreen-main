/// 扫码 slot——委托 [ScannerWidget]，识别后经 [PageEventBus] 发事件（M3 `scanner`）。
library;
import 'package:evergreen_base/core/module/module_descriptor.dart';
import 'package:evergreen_base/core/module/page_event_bus.dart';
import 'package:evergreen_base/renderer/components/shared/widgets/scanner.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 将一次扫码结果经 [PageEventBus] 发出（抽离为可单测的纯逻辑，与 UI 解耦）。
void emitScannerEvent({
  required PageEventBus? bus,
  required String slotKey,
  required String defaultEvent,
  required String code,
  required String? format,
}) {
  bus?.emit(
    defaultEvent,
    sourceSlot: slotKey,
    data: {'code': code, 'format': format},
  );
}

class ScannerSlot extends ConsumerStatefulWidget {
  final String slotKey;
  final ComponentDescriptor config;
  final PageEventBus? pageEventBus;
  final String moduleId;

  const ScannerSlot({
    required this.slotKey,
    required this.config,
    this.pageEventBus,
    required this.moduleId,
  });

  @override
  ConsumerState<ScannerSlot> createState() => _ScannerSlotState();
}

class _ScannerSlotState extends ConsumerState<ScannerSlot> {
  void _onScan(String code, String? format) {
    final event =
        widget.config.config['emitEvent'] as String? ?? 'code_scanned';
    emitScannerEvent(
      bus: widget.pageEventBus,
      slotKey: widget.slotKey,
      defaultEvent: event,
      code: code,
      format: format,
    );
  }

  @override
  Widget build(BuildContext context) {
    final cfg = widget.config.config;
    return ScannerWidget(
      mode: cfg['mode'] as String? ?? 'qr',
      formats: (cfg['formats'] as List?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      continuous: cfg['continuous'] as bool? ?? false,
      hint: cfg['hint'] as String? ?? '将镜头对准二维码 / 条码',
      onScan: _onScan,
    );
  }
}
