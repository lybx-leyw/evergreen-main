import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import '../log.dart';
import '../result.dart';
import '../errors.dart';

/// DeepSeek-OCR 服务——通过 DashScope API 识别图片文字。
///
/// 协议：POST https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions
/// 模型：vanchin/deepseek-ocr
/// 输入：单张图片文件（jpg/png/bmp/webp/tiff）
class DeepSeekOcrService {
  final Dio _dio;
  final String _apiKey;

  DeepSeekOcrService(this._dio, this._apiKey);

  static const _baseUrl = 'https://dashscope.aliyuncs.com/compatible-mode/v1';

  /// 根据文件扩展名返回 MIME 类型（公开以便测试）。
  static String mimeFromPath(String path) {
    final ext = path.split('.').last.toLowerCase();
    switch (ext) {
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      case 'bmp':
        return 'image/bmp';
      case 'webp':
        return 'image/webp';
      case 'tiff':
      case 'tif':
        return 'image/tiff';
      default:
        return 'image/png'; // 保守回退
    }
  }

  /// OCR 识别单张图片文件。成功返回文本，失败返回 null。
  ///
  /// [imageFile] 必须是图片文件（jpg/png/bmp/webp/tiff），不支持 PDF。
  /// PDF 应由调用方先用 [pdf_to_images.py] 拆分为图片后逐页传入。
  Future<String?> recognize(File imageFile) async {
    try {
      final bytes = await imageFile.readAsBytes();
      final base64 = base64Encode(bytes);
      final mime = mimeFromPath(imageFile.path);
      final dataUrl = 'data:$mime;base64,$base64';

      final response = await _dio.post(
        '$_baseUrl/chat/completions',
        options: Options(
          headers: {
            'Authorization': 'Bearer $_apiKey',
            'Content-Type': 'application/json',
          },
          receiveTimeout: const Duration(seconds: 60),
        ),
        data: {
          'model': 'vanchin/deepseek-ocr',
          'messages': [
            {
              'role': 'user',
              'content': [
                {'type': 'image_url', 'image_url': {'url': dataUrl, 'detail': 'high'}},
                {'type': 'text', 'text': 'Read all the text in the image.'},
              ],
            },
          ],
        },
      );

      final text = response.data?['choices']?[0]?['message']?['content'] as String?;
      if (text != null && text.isNotEmpty) {
        Log().info('DeepSeek-OCR succeeded', data: {'length': text.length});
        return text.trim();
      }
      return null;
    } on DioException catch (e) {
      Log().warn('DeepSeek-OCR API error', data: {'status': e.response?.statusCode});
      return null;
    } catch (e) {
      Log().warn('DeepSeek-OCR failed', error: e);
      return null;
    }
  }

  /// 测试 API 连接——用 1×1 像素图片验证 API Key 是否有效。
  ///
  /// 返回 Ok(模型名) 或 Err(AppError)。
  Future<Result<String>> testConnection() async {
    try {
      // 1×1 白色 PNG（最小有效图片）
      const minimalPngBase64 =
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==';

      final response = await _dio.post(
        '$_baseUrl/chat/completions',
        options: Options(
          headers: {
            'Authorization': 'Bearer $_apiKey',
            'Content-Type': 'application/json',
          },
          receiveTimeout: const Duration(seconds: 15),
        ),
        data: {
          'model': 'vanchin/deepseek-ocr',
          'max_tokens': 10,
          'messages': [
            {
              'role': 'user',
              'content': [
                {
                  'type': 'image_url',
                  'image_url': {
                    'url': 'data:image/png;base64,$minimalPngBase64',
                    'detail': 'low',
                  },
                },
                {'type': 'text', 'text': 'Say OK'},
              ],
            },
          ],
        },
      );

      final model = response.data?['model']?.toString() ??
          response.data?['choices']?[0]?['message']?['content']?.toString() ??
          'vanchin/deepseek-ocr';
      Log().info('DeepSeek-OCR connection test succeeded', data: {'model': model});
      return Ok('连接成功 (模型: $model)');
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      final kind = status == 401 || status == 403 ? 'auth'
          : status != null && status >= 500 ? 'server'
          : e.type == DioExceptionType.connectionTimeout ||
            e.type == DioExceptionType.receiveTimeout ? 'timeout'
          : 'network';
      Log().warn('DeepSeek-OCR connection test failed',
          data: {'status': status, 'kind': kind});
      return Err(AppError.aiModelError('DashScope OCR', status));
    } catch (e) {
      Log().warn('DeepSeek-OCR connection test error', error: e);
      return Err(AppError.unknown(e));
    }
  }
}
