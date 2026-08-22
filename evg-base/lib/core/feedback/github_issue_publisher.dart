/// GitHub Issue 一键发布 —— 反馈面板「发 Issue」后端。
///
/// 用用户自填的 PAT（[GITHUB_FEEDBACK_TOKEN] 设置项）调 GitHub REST API
/// 在目标仓库创建 Issue，正文含专业反馈模板 + 截图 base64 内嵌。
///
/// 设计原则：
/// - 绝不抛异常到调用方：任何网络/解析错误都收敛为 [IssueResult.failure]。
/// - 默认 15s 超时，避免卡死 UI。
/// - token 只在本模块内存使用，不落盘、不打印。
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:evergreen_base/core/log.dart';

/// 目标仓库（与 update_service 同源）。
const String kFeedbackRepo = 'lybx-leyw/evergreen-main';

/// 反馈设置项 key。
const String kGithubFeedbackTokenKey = 'GITHUB_FEEDBACK_TOKEN';

/// 发布失败的分类——用于 UI 给出针对性提示。
enum IssueFailureKind {
  /// 未填写令牌 / 令牌为空。
  noToken,
  /// 网络不可达（DNS / 连接被拒 / 离线）。
  network,
  /// 请求超时。
  timeout,
  /// 鉴权失败（401 / 403），通常是令牌无效或权限不足。
  auth,
  /// GitHub 返回其他 4xx/5xx。
  api,
  /// 未知异常。
  unknown,
}

/// 发布结果。
sealed class IssueResult {
  const IssueResult();

  factory IssueResult.success(String htmlUrl) = IssueSuccess;
  factory IssueResult.failure(
    String reason, {
    IssueFailureKind kind = IssueFailureKind.unknown,
    int? statusCode,
    String? rawMessage,
  }) => IssueFailure(reason, kind: kind, statusCode: statusCode, rawMessage: rawMessage);
}

class IssueSuccess extends IssueResult {
  final String htmlUrl;
  const IssueSuccess(this.htmlUrl);
}

class IssueFailure extends IssueResult {
  final String reason;
  final IssueFailureKind kind;
  /// HTTP 状态码（若有）。
  final int? statusCode;
  /// GitHub 返回的原始错误信息（若有），便于透传给用户。
  final String? rawMessage;
  const IssueFailure(
    this.reason, {
    this.kind = IssueFailureKind.unknown,
    this.statusCode,
    this.rawMessage,
  });
}

/// 发布一个 GitHub Issue。
///
/// [token] 用户 PAT（repo scope）。[title] / [body] 已构造好的 issue 内容。
/// 返回 [IssueResult]，调用方据此提示用户，永不抛。
Future<IssueResult> publishGithubIssue({
  required String token,
  required String title,
  required String body,
  String repo = kFeedbackRepo,
  Dio? dio,
}) async {
  if (token.trim().isEmpty) {
    return IssueResult.failure(
      '未填写 GitHub 令牌（设置 → GitHub 反馈令牌）',
      kind: IssueFailureKind.noToken,
    );
  }

  final client = dio ?? Dio();

  // GitHub 对 issue body 有约 65536 字符硬上限，内嵌大图 base64 极易触发 422。
  // 发送前若超长，剥离截图段（保留文字反馈），避免请求被拒。
  final fitted = _fitBody(body);

  try {
    final resp = await client.post(
      'https://api.github.com/repos/$repo/issues',
      options: Options(
        headers: {
          'Authorization': 'Bearer ${token.trim()}',
          'Accept': 'application/vnd.github+json',
          'X-GitHub-Api-Version': '2022-11-28',
          'Content-Type': 'application/json',
        },
        receiveTimeout: const Duration(seconds: 15),
        sendTimeout: const Duration(seconds: 15),
      ),
      data: jsonEncode({'title': title, 'body': fitted.body}),
    );

    if (resp.statusCode == 201 || resp.statusCode == 200) {
      final htmlUrl = resp.data is Map
          ? (resp.data['html_url'] as String? ?? '')
          : '';
      if (htmlUrl.isEmpty) {
        return IssueResult.failure(
          '创建成功但未返回链接',
          kind: IssueFailureKind.unknown,
          statusCode: resp.statusCode,
        );
      }
      Log().info('FEEDBACK: issue created', data: {'url': htmlUrl});
      return IssueResult.success(htmlUrl);
    }

    // 4xx/5xx：尝试解析 GitHub 错误信息
    final raw = _extractErrorMessage(resp);
    final kind = (resp.statusCode == 401 || resp.statusCode == 403)
        ? IssueFailureKind.auth
        : IssueFailureKind.api;
    final extra = (resp.statusCode == 422)
        ? '（GitHub 拒绝：正文可能仍超长或格式非法，可尝试缩短描述）'
        : (fitted.strippedScreenshot
            ? '（截图已因体积过大自动省略）'
            : '');
    return IssueResult.failure(
      'GitHub 返回 ${resp.statusCode}: $raw$extra',
      kind: kind,
      statusCode: resp.statusCode,
      rawMessage: raw,
    );
  } on DioException catch (e) {
    final (kind, msg) = switch (e.type) {
      DioExceptionType.connectionTimeout ||
      DioExceptionType.sendTimeout ||
      DioExceptionType.receiveTimeout =>
        (
          IssueFailureKind.timeout,
          '网络超时（15s），请检查网络后重试',
        ),
      DioExceptionType.connectionError => (
          IssueFailureKind.network,
          '无法连接 GitHub（网络不可达 / 离线 / 被拦截）',
        ),
      _ =>
        e.response != null
            ? (
                (e.response!.statusCode == 401 || e.response!.statusCode == 403)
                    ? IssueFailureKind.auth
                    : IssueFailureKind.api,
                'GitHub 返回 ${e.response!.statusCode}: ${_extractErrorMessage(e.response!)}',
              )
            : (IssueFailureKind.unknown, e.message ?? '网络请求失败'),
    };
    final raw = e.response != null ? _extractErrorMessage(e.response!) : null;
    Log().warn('FEEDBACK: issue publish failed [$kind]', error: e);
    return IssueResult.failure(
      msg,
      kind: kind,
      statusCode: e.response?.statusCode,
      rawMessage: raw,
    );
  } catch (e) {
    Log().warn('FEEDBACK: issue publish unexpected error', error: e);
    return IssueResult.failure(
      '未知错误: $e',
      kind: IssueFailureKind.unknown,
    );
  }
}

/// GitHub issue body 约 65536 字符上限。返回裁剪后的 body 与是否被截断。
///
/// 裁剪策略：从 `### 📸 截图` 段开始到文末（即 base64 内嵌图）整体剥离，
/// 仅当 body 仍超长时才进一步截断文字（极少发生）。
class _FittedBody {
  final String body;
  final bool strippedScreenshot;
  const _FittedBody(this.body, this.strippedScreenshot);
}

_FittedBody _fitBody(String body, {int limit = 64000}) {
  var stripped = false;
  var out = body;
  const marker = '### 📸 截图';
  if (out.length > limit && out.contains(marker)) {
    final idx = out.indexOf(marker);
    out = '${out.substring(0, idx)}'
        '\n\n### 📸 截图\n\n（截图过大已省略——原图保存在本地反馈目录的 screenshot.png）\n';
    stripped = true;
  }
  if (out.length > limit) {
    // 极端情况：纯文字也超长，硬截断并标注
    out = '${out.substring(0, limit)}\n\n…（正文过长已截断）';
  }
  return _FittedBody(out, stripped);
}

String _extractErrorMessage(Response? resp) {
  if (resp == null) return '请求失败';
  try {
    final data = resp.data;
    if (data is Map && data['message'] is String) return data['message'] as String;
    if (data is String) {
      final decoded = jsonDecode(data) as Map?;
      if (decoded != null && decoded['message'] is String) {
        return decoded['message'] as String;
      }
    }
  } catch (_) {
    // 忽略解析失败
  }
  return '请求失败';
}

/// 把截图文件读为内嵌 Markdown 的 base64 data-uri 片段。
///
/// 失败返回空字符串（不影响文字 issue 发布）。
String buildScreenshotMarkdown(String? screenshotPath) {
  if (screenshotPath == null || screenshotPath.isEmpty) return '';
  try {
    final file = File(screenshotPath);
    if (!file.existsSync()) return '';
    final bytes = file.readAsBytesSync();
    final b64 = base64Encode(bytes as Uint8List);
    // GitHub 渲染 data:image/png;base64 内嵌图
    return '\n\n### 📸 截图\n\n![screenshot](data:image/png;base64,$b64)\n';
  } catch (_) {
    return '';
  }
}
