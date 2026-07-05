/// Skill 系统 — 对应 reasonix/internal/skill/。
library;

import 'dart:io';
import 'dart:convert';

enum SkillScope {
  builtin,
  global,
  custom,
  project;

  int get priority => index;
}

enum SkillRunAs { inline, subagent }

// ═══════ Skill ═══════

class Skill {
  /// 规范标识符，匹配目录/文件名。
  final String name;

  /// 一行描述，显示在索引中。
  final String description;

  /// 完整 Markdown body（frontmatter 之后的内容）。
  final String body;

  /// 来源作用域。
  final SkillScope scope;

  /// 文件路径。
  final String path;

  /// 子 Agent 的允许工具列表（空=继承全部）。
  final List<String> allowedTools;

  /// 执行方式。
  final SkillRunAs runAs;

  const Skill({
    required this.name,
    required this.description,
    required this.body,
    required this.scope,
    required this.path,
    this.allowedTools = const [],
    this.runAs = SkillRunAs.inline,
  });
}

// ═══════ SkillIndex ═══════

/// 管理所有已发现技能。
class SkillIndex {
  final List<Skill> _skills = [];

  void add(Skill skill) {
    // 同名高优先级覆盖低优先级
    _skills.removeWhere((s) => s.name == skill.name && s.scope.priority <= skill.scope.priority);
    _skills.add(skill);
  }

  void addAll(List<Skill> skills) {
    for (final s in skills) {
      add(s);
    }
  }

  Skill? get(String name) {
    try {
      return _skills.firstWhere((s) => s.name == name);
    } catch (_) {
      return null;
    }
  }

  List<Skill> all() => List.unmodifiable(_skills);

  /// 生成 system prompt 中的技能索引文本。
  String indexText() {
    if (_skills.isEmpty) return '';
    final buf = StringBuffer();
    buf.writeln('\n## 可用技能');
    buf.writeln('你可以通过 run_skill 工具调用以下技能：');
    buf.writeln();
    for (final skill in _skills) {
      final tag = skill.runAs == SkillRunAs.subagent ? ' 🧬 subagent' : '';
      buf.writeln('- **${skill.name}**$tag — ${skill.description}');
    }
    return buf.toString();
  }
}

// ═══════ SkillLoader ═══════

/// 从文件系统发现并加载 Skill。
class SkillLoader {
  final List<String> searchPaths;

  SkillLoader(this.searchPaths);

  /// 从所有搜索路径加载技能。
  List<Skill> loadAll() {
    final skills = <Skill>[];
    for (final path in searchPaths) {
      skills.addAll(_loadFromDir(path));
    }
    return skills;
  }

  List<Skill> _loadFromDir(String dirPath) {
    final skills = <Skill>[];
    final dir = Directory(dirPath);
    if (!dir.existsSync()) return skills;

    for (final entry in dir.listSync()) {
      if (entry is File && entry.path.endsWith('.md')) {
        final skill = _parseSkillFile(entry);
        if (skill != null) skills.add(skill);
      }
      if (entry is Directory) {
        // 目录布局 A：<name>/SKILL.md
        final skillFile = File('${entry.path}${Platform.pathSeparator}SKILL.md');
        if (skillFile.existsSync()) {
          final skill = _parseSkillFile(skillFile);
          if (skill != null) skills.add(skill);
        }
        // 目录布局 B：<plugin>/skill/*.md（插件 skill 子目录）
        final skillDir = Directory('${entry.path}${Platform.pathSeparator}skill');
        if (skillDir.existsSync()) {
          for (final sf in skillDir.listSync()) {
            if (sf is File && sf.path.endsWith('.md')) {
              final skill = _parseSkillFile(sf);
              if (skill != null) skills.add(skill);
            }
          }
        }
      }
    }

    return skills;
  }

  Skill? _parseSkillFile(File file) {
    try {
      final content = file.readAsStringSync();
      final path = file.path;

      // 解析 frontmatter
      final fmMatch = RegExp(r'^---\n([\s\S]*?)\n---\n([\s\S]*)').firstMatch(content);

      String body;
      String name = '';
      String description = '';
      String runAs = 'inline';
      final allowedTools = <String>[];

      if (fmMatch != null) {
        body = fmMatch.group(2) ?? '';
        final fm = fmMatch.group(1)!;
        for (final line in fm.split('\n')) {
          final colon = line.indexOf(':');
          if (colon <= 0) continue;
          final key = line.substring(0, colon).trim();
          final value = line.substring(colon + 1).trim().replaceAll(RegExp(r'^"|"$'), '');
          switch (key) {
            case 'name':
              name = value;
            case 'description':
              description = value;
            case 'run_as':
            case 'runAs':
              runAs = value;
            case 'allowed_tools':
            case 'allowedTools':
              if (value.startsWith('[')) {
                try {
                  final parsed = jsonDecode(value);
                  if (parsed is List) {
                    allowedTools.addAll(parsed.cast<String>());
                  }
                } catch (_) {}
              }
          }
        }
      } else {
        body = content;
      }

      if (name.isEmpty) {
        name = path.split(RegExp(r'[/\\]')).last.replaceAll('.md', '');
      }

      if (description.isEmpty) return null;

      return Skill(
        name: name,
        description: description,
        body: body.trim(),
        scope: _inferScope(path),
        path: path,
        allowedTools: allowedTools,
        runAs: runAs == 'subagent' ? SkillRunAs.subagent : SkillRunAs.inline,
      );
    } catch (_) {
      return null;
    }
  }

  SkillScope _inferScope(String path) {
    final normalized = path.replaceAll('\\', '/');
    // 旧版 .greenix/skills/ 路径
    if (normalized.contains('.greenix/skills/')) {
      final isGlobal = normalized.contains('AppData') ||
          normalized.contains('.config/greenix');
      return isGlobal ? SkillScope.global : SkillScope.project;
    }
    // 新版 plugins/<name>/skill/*.md 路径
    if (normalized.contains('/plugins/') && normalized.contains('/skill/')) {
      return SkillScope.custom;
    }
    return SkillScope.custom;
  }

  /// 将预置 Skill 从 APK assets 提取到文件系统（首次运行时调用）。
  /// [files] 为 (文件名, 内容) 的列表。
  static void extractBundledSkills(String targetDir, List<(String, String)> files) {
    final dir = Directory(targetDir);
    if (!dir.existsSync()) dir.createSync(recursive: true);
    for (final (name, content) in files) {
      final f = File('$targetDir/$name');
      if (!f.existsSync()) f.writeAsStringSync(content);
    }
  }

  /// 扫描 plugins/<name>/skill/*.md 发现插件技能。
  ///
  /// 与 loadAll() 的区别：此方法专门扫描 plugins/ 目录下的 skill/ 子目录，
  /// 用于 S1 迁移后从 .greenix/skills/ 到 plugins/<name>/skill/*.md 的路径变更。
  static List<Skill> discoverPluginSkills(String pluginsDir) {
    final loader = SkillLoader([pluginsDir]);
    return loader.loadAll();
  }
}

// ═══════ BuiltinSkills ═══════

/// 编译时定义的 playbook。
class BuiltinSkills {
  static final List<Skill> _builtins = [];

  static void register(Skill skill) {
    _builtins.add(skill);
  }

  static List<Skill> all() => List.unmodifiable(_builtins);

  static void loadInto(SkillIndex index, {SkillScope scope = SkillScope.builtin}) {
    for (final s in _builtins) {
      index.add(Skill(
        name: s.name,
        description: s.description,
        body: s.body,
        scope: scope,
        path: '(builtin)',
        allowedTools: s.allowedTools,
        runAs: s.runAs,
      ));
    }
  }
}
