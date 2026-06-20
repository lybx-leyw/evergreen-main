import 'package:flutter/foundation.dart';

/// 标记敏感字段——toString() / Log() 自动脱敏为 `***`。
///
/// 目前作为文档标记，未来可接 lint 规则强制脱敏。
class Secure {
  const Secure();
}

/// 应用配置——不可变值对象。
///
/// 优先级（高→低）：env vars → .env 文件 → SharedPreferences。
/// 所有字段通过构造函数注入，由 [AppConfigNotifier] 管理生命周期。
class AppConfigData {
  // ── 认证 ──
  final String? zjuUsername;
  @Secure() final String? zjuPassword;

  // ── AI ──
  @Secure() final String? deepseekApiKey;
  final String deepseekModel;
  final bool deepseekThinking;

  // ── 第三方 ──
  @Secure() final String? ptaSession;
  final String? dingtalkWebhook;

  // ── 路径 ──
  final String? downloadPath;
  final String? videoPlayerPath;

  // ── PDF 翻译 ──
  final String translateLangOut;
  final String translateLangIn;
  final String? pythonExe;

  const AppConfigData({
    this.zjuUsername,
    this.zjuPassword,
    this.deepseekApiKey,
    this.deepseekModel = 'deepseek-v4-flash',
    this.deepseekThinking = true,
    this.ptaSession,
    this.dingtalkWebhook,
    this.downloadPath,
    this.videoPlayerPath,
    this.translateLangOut = 'zh',
    this.translateLangIn = 'en',
    this.pythonExe,
  });

  // ── 派生属性 ──

  bool get hasZjuCredentials =>
      zjuUsername != null &&
      zjuUsername!.isNotEmpty &&
      zjuPassword != null &&
      zjuPassword!.isNotEmpty;

  bool get hasDeepSeekApiKey =>
      deepseekApiKey != null && deepseekApiKey!.isNotEmpty;

  bool get hasPtaSession => ptaSession != null && ptaSession!.isNotEmpty;

  /// 复制并覆盖指定字段。
  AppConfigData copyWith({
    String? zjuUsername,
    String? zjuPassword,
    String? deepseekApiKey,
    String? deepseekModel,
    bool? deepseekThinking,
    String? ptaSession,
    String? dingtalkWebhook,
    String? downloadPath,
    String? videoPlayerPath,
    String? translateLangOut,
    String? translateLangIn,
    String? pythonExe,
  }) {
    return AppConfigData(
      zjuUsername: zjuUsername ?? this.zjuUsername,
      zjuPassword: zjuPassword ?? this.zjuPassword,
      deepseekApiKey: deepseekApiKey ?? this.deepseekApiKey,
      deepseekModel: deepseekModel ?? this.deepseekModel,
      deepseekThinking: deepseekThinking ?? this.deepseekThinking,
      ptaSession: ptaSession ?? this.ptaSession,
      dingtalkWebhook: dingtalkWebhook ?? this.dingtalkWebhook,
      downloadPath: downloadPath ?? this.downloadPath,
      videoPlayerPath: videoPlayerPath ?? this.videoPlayerPath,
      translateLangOut: translateLangOut ?? this.translateLangOut,
      translateLangIn: translateLangIn ?? this.translateLangIn,
      pythonExe: pythonExe ?? this.pythonExe,
    );
  }

  // ── 安全 toString ──

  @override
  String toString() {
    return 'AppConfigData('
        'zjuUsername: $zjuUsername, '
        'zjuPassword: ${mask(zjuPassword)}, '
        'deepseekApiKey: ${mask(deepseekApiKey)}, '
        'deepseekModel: $deepseekModel, '
        'deepseekThinking: $deepseekThinking, '
        'ptaSession: ${mask(ptaSession)}, '
        'downloadPath: $downloadPath, '
        'translateLangOut: $translateLangOut, '
        'translateLangIn: $translateLangIn, '
        'pythonExe: $pythonExe'
        ')';
  }

  /// 脱敏：私密值的前 3 字符 + `***`，短路处理 null/空/短字符串。
  @visibleForTesting
  static String mask(String? value) {
    if (value == null || value.isEmpty) return '(null)';
    if (value.length <= 6) return '***';
    return '${value.substring(0, 3)}***';
  }
}
