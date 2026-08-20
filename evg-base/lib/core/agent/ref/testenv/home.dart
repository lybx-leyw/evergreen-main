/// Port of reasonix/internal/testenv/home.go.
library;

import 'dart:io';

import 'package:path/path.dart' as p;

/// Returns a cleanup function that redirects user-scoped paths to a temp
/// home and restores the previous environment when called.
Future<Future<void> Function()> isolateUserState() async {
  final originalHome = Platform.environment['HOME'] ??
      Platform.environment['USERPROFILE'];
  final home = await Directory.systemTemp.createTemp('.reasonix-test-home-');

  final set = {
    'HOME': home.path,
    'USERPROFILE': home.path,
    'XDG_CONFIG_HOME': p.join(home.path, '.config'),
    'XDG_CACHE_HOME': p.join(home.path, '.cache'),
    'XDG_STATE_HOME': p.join(home.path, '.local', 'state'),
    'AppData': p.join(home.path, 'AppData', 'Roaming'),
    'LocalAppData': p.join(home.path, 'AppData', 'Local'),
  };
  const unset = [
    'REASONIX_HOME',
    'REASONIX_STATE_HOME',
    'REASONIX_CACHE_HOME',
  ];

  final saved = <String, String? >{};
  for (final key in set.keys.followedBy(unset)) {
    saved[key] = Platform.environment[key];
  }

  for (final entry in set.entries) {
    Platform.environment[entry.key] = entry.value;
  }
  for (final key in unset) {
    Platform.environment.remove(key);
  }

  return () async {
    for (final entry in saved.entries) {
      if (entry.value != null) {
        Platform.environment[entry.key] = entry.value!;
      } else {
        Platform.environment.remove(entry.key);
      }
    }
    await home.delete(recursive: true);
  };
}
