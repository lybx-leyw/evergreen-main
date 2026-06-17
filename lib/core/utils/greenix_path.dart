import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Cached Greenix writable base directory.
/// Desktop: `.greenix` (current working dir)
/// Android/iOS: `<app documents>/.greenix`
String _greenixBaseDir = '.greenix';

/// Initialize Greenix paths — called once from main.dart at startup.
///
/// On Android/iOS, this resolves the app's writable documents directory.
/// On desktop, defaults to the current working directory.
Future<void> initGreenixPaths() async {
  if (Platform.isAndroid || Platform.isIOS) {
    final appDir = await getApplicationDocumentsDirectory();
    _greenixBaseDir = p.join(appDir.path, '.greenix');
  }
}

/// Writable Greenix memories directory (synchronous after [initGreenixPaths]).
String get greenixMemoriesDir => p.join(_greenixBaseDir, 'memories');

/// Writable Greenix skills directory (synchronous after [initGreenixPaths]).
String get greenixSkillsDir => p.join(_greenixBaseDir, 'skills');

/// Writable cookie storage path (synchronous after [initGreenixPaths]).
String get cookieJarPath => p.join(_greenixBaseDir, '.cookies');
