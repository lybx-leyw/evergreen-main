import 'dart:io';

import 'package:evergreen_base/core/agent/ref/testenv/home.dart' as testenv;
import 'package:test/test.dart';

void main() {
  test('isolate user state creates temp home and restores env', () async {
    final original = Platform.environment['HOME'];
    final cleanup = await testenv.isolateUserState();
    final isolated = Platform.environment['HOME'];
    expect(isolated, isNot(original));
    await cleanup();
    expect(Platform.environment['HOME'], original);
  });
}
