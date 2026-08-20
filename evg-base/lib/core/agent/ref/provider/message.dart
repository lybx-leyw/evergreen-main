/// Minimal provider message types used by P1/P2 stubs.
///
/// The full provider package is ported in P2; this file only defines the
/// surface needed by `secrets.RedactMessage(s)` until the main provider
/// migration lands.
library;

class Message {
  Role role = Role.user;
  String content = '';
  String rawContent = '';
  String providerContent = '';
  String reasoningContent = '';
  String reasoningId = '';
  String reasoningStatus = '';
  String reasoningSignature = '';
  List<ToolCall> toolCalls = [];
  String toolCallId = '';
  String name = '';
  List<MemoryCitation> memoryCitations = [];
  int workDurationMs = 0;
  int createdAt = 0;
  bool edited = false;

  String get original => rawContent.isEmpty ? providerContent : rawContent;
  set original(String v) => rawContent = v;
}

enum Role {
  system('system'),
  user('user'),
  assistant('assistant'),
  tool('tool');

  final String wire;
  const Role(this.wire);
}

class ToolCall {
  String id = '';
  String name = '';
  String arguments = '';
  String thoughtSignature = '';
  String diff = '';
  int added = 0;
  int removed = 0;
  String resolvedName = '';
  String capabilityId = '';
  bool? resolvedReadOnly;
}

class MemoryCitation {
  String id = '';
  String source = '';
  int lineStart = 0;
  int lineEnd = 0;
  String note = '';
  String kind = '';
}
