import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'services/plugin_installer.dart';
import 'services/core_http_server.dart';
import 'services/ocr_pipeline.dart';
import 'services/update_service.dart';

void main() async {
  final dio = Dio();
  final installer = PluginInstaller(pluginsDir: '.test_plugins', dio: dio);
  final server = CoreHttpServer(installer, OcrPipeline(dio), UpdateService(dio));
  final port = await server.start();
  print('CoreHttpServer → http://127.0.0.1:$port\n');

  final client = HttpClient();
  final imagePath = '${Directory.systemTemp.path.replaceAll('\\', '/')}/test_ocr.png';
  print('Image: $imagePath (exists: ${File(imagePath).existsSync()})\n');

  var req = await client.postUrl(Uri.parse('http://127.0.0.1:$port/core/ocr'));
  req.headers.contentType = ContentType.json;
  final bytes = utf8.encode(jsonEncode({'path': imagePath}));
  req.contentLength = bytes.length;
  req.add(bytes);
  var resp = await req.close();
  var body = jsonDecode(await resp.transform(utf8.decoder).join());
  final text = body['text'];
  print('POST /core/ocr → text: $text');

  if (text != null && text.toString().isNotEmpty) {
    print('\n✅ OCR 真实输出 (${text.toString().length} 字符)');
  } else {
    print('\n❌ OCR 返回 null/空');
  }

  client.close();
  await server.stop();
  try { Directory('.test_plugins').deleteSync(recursive: true); } catch (_) {}
  exit(text != null && text.toString().isNotEmpty ? 0 : 1);
}
