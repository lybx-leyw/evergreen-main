/// Port of reasonix/internal/ablation.
library;

import 'dart:collection';

enum Module {
  evidence,
  planner,
  subagent,
  retrieval,
  compaction,
  fullFold,
}

const _moduleOrder = [
  Module.evidence,
  Module.planner,
  Module.subagent,
  Module.retrieval,
  Module.compaction,
  Module.fullFold,
];

List<Module> modules() => List.unmodifiable(_moduleOrder);

class Set {
  final HashSet<Module> _off;

  Set._(this._off);

  factory Set([List<Module> mods = const []]) {
    return Set._(HashSet.of(mods));
  }

  static Set none = Set();

  bool off(Module m) => _off.contains(m);
  bool get empty => _off.isEmpty;

  String arm() {
    if (empty) return 'full';
    final parts = disabled().map((m) => 'no-${_name(m)}').toList();
    return parts.join('+');
  }

  @override
  String toString() {
    if (empty) return 'none';
    return disabled().map(_name).join(',');
  }

  List<Module> disabled() {
    final out = _moduleOrder.where(_off.contains).toList();
    return out;
  }
}

String _name(Module m) => m.name.toLowerCase();

Set parse(String spec) {
  final trimmed = spec.trim();
  if (trimmed.isEmpty || trimmed.toLowerCase() == 'none') {
    return Set();
  }
  if (trimmed.toLowerCase() == 'all') {
    return Set(modules());
  }
  final known = HashSet<Module>.of(modules());
  final mods = <Module>[];
  for (final field in trimmed.split(RegExp(r'[,
]'))) {
    final raw = field.trim().toLowerCase();
    if (raw.isEmpty) continue;
    final found = known.firstWhere(
      (m) => _name(m) == raw,
      orElse: () => throw FormatException(
          'unknown ablation module "$raw" (want ${modules().map(_name).join(", ")}, or none/all)'),
    );
    mods.add(found);
  }
  return Set(mods);
}
