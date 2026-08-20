/// Port of reasonix/internal/secrets/redact.go.
///
/// Masks credential-like values for explicit diagnostic, export, and cleanup
/// paths. Normal model content, tool output, session transcripts, and
/// background-job artifacts deliberately bypass this helper to retain the
/// original byte-preserving behavior.
library;

import 'dart:io';

import '../provider/message.dart' as provider;

final RegExp _secretKeyNamePattern = RegExp(
    r'(?i)((^|[_-])(api[_-]?key|access[_-]?key|private[_-]?key|secret|token|password|passwd)([_-]|$)|[_-]pwd([_-]|$))');
final RegExp _cookieHeaderPattern = RegExp(
    r'(?i)\b((?:set-)?cookie)(\s*[:=]\s*)([^=;\s]+=[^;\s]*(?:;\s*[^=;\s]+(?:=[^;\s]*)?)*)');
final RegExp _cookiePairPattern = RegExp(r'([^=;\s]+)=([^;\s]*)');
final RegExp _bearerTokenPattern =
    RegExp(r'(?i)\bBearer\s+([A-Za-z0-9._~+/=-]{16,})');
final RegExp _openAIKeyPattern =
    RegExp(r'\b((?:sk|rk)-(?:proj-)?[A-Za-z0-9_-]{12,})\b');
final RegExp _githubTokenPattern =
    RegExp(r'\b(gh[pousr]_[A-Za-z0-9_]{20,}|github_pat_[A-Za-z0-9_]{20,})\b');
final RegExp _slackTokenPattern = RegExp(r'\b(xox[baprs]-[A-Za-z0-9-]{16,})\b');
final RegExp _awsAccessKeyPattern =
    RegExp(r'\b(AKIA[0-9A-Z]{16}|ASIA[0-9A-Z]{16})\b');
final RegExp _jwtPattern =
    RegExp(r'\b(eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+)\b');
final RegExp _urlUserInfoPattern =
    RegExp(r'(?i)\b([a-z][a-z0-9+.-]*://)([^/\s]+)@');
final RegExp _maskedCredentialPattern =
    RegExp(r'[A-Za-z0-9._-]*\*{2,}[A-Za-z0-9._-]*');
final RegExp _credentialContextPattern = RegExp(
    r'''(?i)\b(api[ _-]?key|access[ _-]?key|secret|token|authorization|bearer|credential)s?\b(['\"]?\s*[:=]?\s*['\"]?)([A-Za-z0-9._~+/-]{12,})''');
final RegExp _credentialTokenPattern = RegExp(r'[A-Za-z0-9_-]{16,}');
final RegExp _digitPattern = RegExp(r'[0-9]');

const String redactedValue = '[redacted]';

bool _filterSubprocessEnvEnabled = false;
bool _protectSensitiveFilesEnabled = false;
final Set<String> _credentialEnvKeys = <String>{};

/// Enables or disables stripping credential-like variables from tool
/// subprocess environments.
void setFilterSubprocessEnv(bool enabled) {
  _filterSubprocessEnvEnabled = enabled;
}

/// Reports whether credential-like variables are stripped from subprocesses.
bool filterSubprocessEnv() => _filterSubprocessEnvEnabled;

/// Enables or disables the built-in credential-path read denylist.
void setProtectSensitiveFiles(bool enabled) {
  _protectSensitiveFilesEnabled = enabled;
}

/// Reports whether the built-in credential-path read denylist is active.
bool protectSensitiveFiles() => _protectSensitiveFilesEnabled;

/// Permanently marks names whose values came from Reasonix's credential store.
void registerCredentialEnvKeys(List<String> keys) {
  for (final key in keys) {
    final normalized = _credentialEnvKey(key);
    if (normalized.isNotEmpty) _credentialEnvKeys.add(normalized);
  }
}

String _credentialEnvKey(String key) => key.trim().toUpperCase();

bool _registeredCredentialEnvKey(String key) =>
    _credentialEnvKeys.contains(_credentialEnvKey(key));

/// Reports whether an environment variable name is likely to carry
/// credentials.
bool envKeySensitive(String key) {
  key = key.trim();
  if (key.isEmpty) return false;
  return _secretKeyNamePattern.hasMatch(key);
}

/// Removes sensitive KEY=value assignments from an environment vector.
List<String> filterEnv(List<String> env) {
  final out = <String>[];
  for (final item in env) {
    final eq = item.indexOf('=');
    if (eq < 0) {
      out.add(item);
      continue;
    }
    final key = item.substring(0, eq);
    if (envKeySensitive(key) || _registeredCredentialEnvKey(key)) continue;
    out.add(item);
  }
  return out;
}

/// Removes only registered credential keys, preserving other sensitive keys.
List<String> _filterRegisteredCredentialEnv(List<String> env) {
  final out = <String>[];
  for (final item in env) {
    final eq = item.indexOf('=');
    if (eq < 0) {
      out.add(item);
      continue;
    }
    final key = item.substring(0, eq);
    if (_registeredCredentialEnvKey(key)) continue;
    out.add(item);
  }
  return out;
}

/// Returns the environment for shell/tool subprocesses.
List<String> processEnv() {
  final env =
      Platform.environment.entries.map((e) => '${e.key}=${e.value}').toList();
  if (!_filterSubprocessEnvEnabled) {
    return _filterRegisteredCredentialEnv(env);
  }
  return filterEnv(env);
}

/// Masks credential-like values for explicit diagnostic, export, and cleanup
/// paths.
String redact(String s) {
  if (s.isEmpty) return s;
  s = _urlUserInfoPattern.replaceAllMapped(
      s, (m) => '${m.group(1)}$redactedValue@');
  s = _redactKeyValues(s);
  s = _cookieHeaderPattern.replaceAllMapped(s, (m) {
    final header = m.group(1)!;
    final sep = m.group(2)!;
    final pairs = m.group(3)!;
    return '$header$sep${_cookiePairPattern.replaceAllMapped(pairs, (pm) => '${pm.group(1)}=$redactedValue')}';
  });
  s = _bearerTokenPattern.replaceAllMapped(
      s, (m) => 'Bearer ${_mask(m.group(1)!)}');
  for (final rx in [
    _openAIKeyPattern,
    _githubTokenPattern,
    _slackTokenPattern,
    _awsAccessKeyPattern,
    _jwtPattern,
  ]) {
    s = rx.replaceAllMapped(s, (m) => _mask(m.group(1)!));
  }
  return s;
}

/// Applies the stronger credential scrub used at external error/logging
/// boundaries.
String redactCredentials(String s) {
  if (s.isEmpty) return s;
  s = redact(s);
  s = _credentialContextPattern.replaceAllMapped(
      s, (m) => '${m.group(1)}${m.group(2)}****');
  s = _maskedCredentialPattern.replaceAll(s, '****');
  return _credentialTokenPattern.replaceAllMapped(s, (m) {
    final token = m.group(0)!;
    final mixedCase =
        token.toLowerCase() != token && token.toUpperCase() != token;
    if (_digitPattern.hasMatch(token) || mixedCase) return '****';
    return token;
  });
}

/// Returns an error string safe for an external log/diagnostic boundary.
String redactError(Object? error) {
  if (error == null) return '';
  return redactCredentials(error.toString());
}

String _redactKeyValues(String s) {
  final out = StringBuffer();
  var last = 0;
  var sep = 0;
  while (sep < s.length) {
    if (s.codeUnitAt(sep) != 0x3A && s.codeUnitAt(sep) != 0x3D) {
      sep++;
      continue;
    }
    var keyEnd = sep;
    while (keyEnd > 0 && _asciiSpace(s.codeUnitAt(keyEnd - 1))) {
      keyEnd--;
    }
    if (keyEnd > 0 &&
        (s.codeUnitAt(keyEnd - 1) == 0x27 ||
            s.codeUnitAt(keyEnd - 1) == 0x22)) {
      keyEnd--;
    }
    var keyStart = keyEnd;
    while (keyStart > 0 && _credentialKeyByte(s.codeUnitAt(keyStart - 1))) {
      keyStart--;
    }
    final key = s.substring(keyStart, keyEnd);
    if (!_credentialTextKeySensitive(key)) {
      sep++;
      continue;
    }

    var valueStart = sep + 1;
    while (valueStart < s.length && _asciiSpace(s.codeUnitAt(valueStart))) {
      valueStart++;
    }
    if (valueStart < s.length &&
        (s.codeUnitAt(valueStart) == 0x27 ||
            s.codeUnitAt(valueStart) == 0x22)) {
      valueStart++;
    }
    final schemeStart = valueStart;
    while (
        valueStart < s.length && _credentialKeyByte(s.codeUnitAt(valueStart))) {
      valueStart++;
    }
    if (valueStart < s.length &&
        _asciiSpace(s.codeUnitAt(valueStart)) &&
        _authorizationScheme(s.substring(schemeStart, valueStart))) {
      while (valueStart < s.length && _asciiSpace(s.codeUnitAt(valueStart))) {
        valueStart++;
      }
      if (valueStart < s.length &&
          (s.codeUnitAt(valueStart) == 0x27 ||
              s.codeUnitAt(valueStart) == 0x22)) {
        valueStart++;
      }
    } else {
      valueStart = schemeStart;
    }

    var valueEnd = valueStart;
    while (valueEnd < s.length &&
        !_asciiSpace(s.codeUnitAt(valueEnd)) &&
        s.codeUnitAt(valueEnd) != 0x27 &&
        s.codeUnitAt(valueEnd) != 0x22 &&
        s.codeUnitAt(valueEnd) != 0x2C &&
        s.codeUnitAt(valueEnd) != 0x3B) {
      valueEnd++;
    }
    if (valueEnd == valueStart) {
      sep++;
      continue;
    }
    out.write(s.substring(last, valueStart));
    final value = s.substring(valueStart, valueEnd);
    if (_authorizationKey(key)) {
      out.write(redactedValue);
    } else if (value == '****' || value == redactedValue) {
      out.write(value);
    } else {
      out.write(_mask(value));
    }
    last = valueEnd;
    sep = valueEnd - 1;
    sep++;
  }
  if (last == 0) return s;
  out.write(s.substring(last));
  return out.toString();
}

bool _credentialKeyByte(int b) =>
    (b >= 0x61 && b <= 0x7A) ||
    (b >= 0x41 && b <= 0x5A) ||
    (b >= 0x30 && b <= 0x39) ||
    b == 0x5F ||
    b == 0x2D ||
    b == 0x2E;

bool _asciiSpace(int b) =>
    b == 0x20 || b == 0x09 || b == 0x0A || b == 0x0D || b == 0x0C;

bool _authorizationKey(String key) {
  final upper = key.toUpperCase();
  return upper == 'AUTHORIZATION' ||
      upper.endsWith('-AUTHORIZATION') ||
      upper.endsWith('_AUTHORIZATION') ||
      upper.endsWith('.AUTHORIZATION');
}

bool _credentialTextKeySensitive(String key) {
  final upper = key.toUpperCase();
  final compact = upper.replaceAll('_', '').replaceAll('-', '');
  return _authorizationKey(key) ||
      compact.contains('APIKEY') ||
      compact.contains('ACCESSKEY') ||
      compact.contains('PRIVATEKEY') ||
      upper.contains('SECRET') ||
      upper.contains('TOKEN') ||
      upper.contains('PASSWORD') ||
      upper.contains('PASSWD') ||
      upper.contains('_PWD') ||
      upper.contains('-PWD');
}

bool _authorizationScheme(String s) {
  switch (s.toLowerCase()) {
    case 'bearer':
    case 'basic':
    case 'digest':
    case 'negotiate':
    case 'ntlm':
    case 'token':
    case 'bot':
    case 'apikey':
      return true;
    default:
      return false;
  }
}

String _mask(String value) {
  value = value.trim();
  if (value.isEmpty) return redactedValue;
  if (value.length <= 12) return redactedValue;
  var head = 4;
  var tail = 4;
  if (value.startsWith('sk-') || value.startsWith('rk-')) head = 6;
  if (value.length <= head + tail) return redactedValue;
  final stars = '*' * (value.length - head - tail);
  return value.substring(0, head) +
      stars +
      value.substring(value.length - tail);
}

/// Returns a storage-safe copy of [m] with textual secret surfaces masked.
provider.Message redactMessage(provider.Message m) {
  final out = provider.Message()
    ..role = m.role
    ..content = redact(m.content)
    ..rawContent = redact(m.rawContent)
    ..providerContent = redact(m.providerContent)
    ..reasoningContent = redact(m.reasoningContent)
    ..reasoningId = m.reasoningId
    ..reasoningStatus = m.reasoningStatus
    ..reasoningSignature = m.reasoningSignature
    ..toolCallId = m.toolCallId
    ..name = m.name
    ..workDurationMs = m.workDurationMs
    ..createdAt = m.createdAt
    ..edited = m.edited;
  if (m.toolCalls.isNotEmpty) {
    out.toolCalls = [
      for (final c in m.toolCalls)
        provider.ToolCall()
          ..id = c.id
          ..name = c.name
          ..arguments = redact(c.arguments)
          ..thoughtSignature = c.thoughtSignature
          ..diff = redact(c.diff)
          ..added = c.added
          ..removed = c.removed
          ..resolvedName = c.resolvedName
          ..capabilityId = c.capabilityId
          ..resolvedReadOnly = c.resolvedReadOnly,
    ];
  }
  if (m.memoryCitations.isNotEmpty) {
    out.memoryCitations = [
      for (final c in m.memoryCitations)
        provider.MemoryCitation()
          ..id = c.id
          ..source = c.source
          ..lineStart = c.lineStart
          ..lineEnd = c.lineEnd
          ..note = redact(c.note)
          ..kind = c.kind,
    ];
  }
  return out;
}

/// Returns a redacted copy of [msgs]. The input list and its messages are
/// never mutated.
List<provider.Message> redactMessages(List<provider.Message> msgs) {
  return [for (final m in msgs) redactMessage(m)];
}
