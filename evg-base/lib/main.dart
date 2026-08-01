/// Evergreen 2.0 启动入口。
///
/// 职责（2026-08-01 起精简，见 docs/基线盘点-2026-07-25.md）：
/// 1. 注册全局错误处理（FlutterError.onError / ErrorWidget / runZonedGuarded）
/// 2. 构造 [AppBootstrap] 并运行 23 个启动步骤（步骤明细见 app_bootstrap.dart）
/// 3. Web 环境提前退出（Evergreen 仅支持桌面）
///
/// 启动步骤拆解到 [AppBootstrap] 后，任意步骤失败均可凭
/// `[BOOT] ❌ N/23 <step-id> ... 失败` 一行日志 + errorId 定位。
///
/// 日志约定（见 docs/错误排查契约-v1.md）：
/// - 所有诊断走 Log()（单一通道），禁止裸 stderr/debugPrint；
/// - 安卓 release 靠 logcat 排障 → 启动时开启 Log.mirrorToStderr；
/// - ERROR 日志自动携带 errorId（EVG-xxxxxxxx），凭 id 检索整条链路。
library;

import 'dart:async';
import 'dart:io';

import 'package:evergreen_base/app_bootstrap.dart';
import 'package:evergreen_base/core/log.dart';
import 'package:flutter/foundation.dart'
    show FlutterError, FlutterErrorDetails, kIsWeb;
import 'package:flutter/material.dart';

// ═══════ 路径常量 ═══════

/// 文本模式下各 HttpServer 实际端口（AppBootstrap 填充，app.dart 读取）。
final textModeServerPorts = <String, int>{};

/// 注册全局 Flutter 框架错误处理（overflow / layout / paint / build 等）。
///
/// - [FlutterError.onError]：统一进入 Log()（文件轮转 + 内存缓冲 + 自动 errorId），
///   mirrorToStderr 保证安卓 logcat 可见；
/// - [ErrorWidget.builder]：build 阶段异常用占位 Widget 替代崩溃红屏
///   （异常本身仍由 onError → Log 记录，此处只负责 UI 兜底）。
void _installGlobalErrorHandlers() {
  FlutterError.onError = (FlutterErrorDetails details) {
    Log().error(
      'Flutter 框架错误: ${details.exceptionAsString()}',
      error: details.exception,
      stack: details.stack,
    );
    // 保留默认行为（debug 模式红黄条纹，release 模式灰屏）
    FlutterError.presentError(details);
  };
  ErrorWidget.builder = (FlutterErrorDetails details) {
    return Container(
      color: const Color(0xFF1A1A2E),
      alignment: Alignment.center,
      padding: const EdgeInsets.all(12),
      child: Text(
        '⚠ 组件渲染失败: ${details.exceptionAsString().split('\n').first}',
        style: const TextStyle(color: Colors.white70, fontSize: 12),
        textAlign: TextAlign.center,
      ),
    );
  };
  Log().info('[BOOT] 全局错误捕获已注册 (FlutterError.onError / ErrorWidget / zone)');
}

void main() {
  // 全局 zone：捕获所有未处理的异步异常（非 Flutter 框架路径），统一进日志通道
  runZonedGuarded(() async {
    // 统一日志通道：诊断全部走 Log()。安卓 release 无文件日志入口，
    // 开启 stderr 镜像保证 logcat 可见（logcat 是安卓唯一排障通道）。
    Log.mirrorToStderr = true;
    Log().info('[BOOT] ═══════ Evergreen 启动 ═══════');
    WidgetsFlutterBinding.ensureInitialized();
    _installGlobalErrorHandlers();

    // ── Web 不支持 dart:io（HttpServer / Process / File），提前退出 ──
    if (kIsWeb) {
      runApp(const MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          body: Center(
            child: Text(
              'Evergreen 需要桌面环境运行\n\n不支持 Web / Chrome',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16, color: Colors.white54),
            ),
          ),
        ),
      ));
      return;
    }

    // ── 23 个启动步骤（AppBootstrap）──
    // 每步输出 [BOOT] N/23 进度；失败输出 ❌ + errorId；结束输出总览一行。
    // 项目根/插件目录在 bootstrap 的 greenix-paths 步骤内解析（安卓必须先
    // initGreenixPaths 再 resolvePluginsRoot，否则相对路径写只读文件系统）。
    final bootstrap = AppBootstrap(
      ports: textModeServerPorts,
    );
    final report = await bootstrap.run();

    // 致命步骤（greenix-paths）失败：后续步骤无意义，明确退出
    if (report.fatalFailed != null) {
      Log().error('[BOOT] ❌ 致命步骤 ${report.fatalFailed} 失败，启动中止');
      exit(1);
    }
  }, (error, stack) {
    // 兜底：未捕获的异步异常（非 Flutter 框架路径）统一进日志通道
    Log().error('[BOOT] 未捕获异步异常', error: error, stack: stack);
  });
}
