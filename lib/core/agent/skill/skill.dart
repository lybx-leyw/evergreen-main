/// Skill 系统 — 可调用的教学剧本。
///
/// 对应 reasonix/internal/skill/。
/// Skill 是命名的可调用 prompt 体——inline 展开到当前对话，subagent 跑子 Agent。
library;

import 'dart:io';
import 'dart:convert';

/// Skill 的作用域（高优先级覆盖低优先级）。
enum SkillScope {
  builtin,
  global,
  custom,
  project;

  int get priority => index;
}

/// Skill 的执行方式。
enum SkillRunAs {
  /// 内联：body 作为工具结果展开到当前对话。
  inline,

  /// 子 Agent：在隔离的子循环中运行，只返回最终答案。
  subagent;
}

/// 一个可调用的 playbook。
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

// ─── 索引 ──────────────────────────────────────────────────

/// Skill 索引——管理所有已发现的技能。
class SkillIndex {
  final List<Skill> _skills = [];

  /// 注册一个技能。
  void add(Skill skill) {
    // 同名高优先级覆盖低优先级
    _skills.removeWhere((s) => s.name == skill.name && s.scope.priority <= skill.scope.priority);
    _skills.add(skill);
  }

  /// 批量注册。
  void addAll(List<Skill> skills) {
    for (final s in skills) {
      add(s);
    }
  }

  /// 按名称查找技能。
  Skill? get(String name) {
    try {
      return _skills.firstWhere((s) => s.name == name);
    } catch (_) {
      return null;
    }
  }

  /// 所有技能。
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

// ─── 加载器 ────────────────────────────────────────────────

/// Skill 加载器——从文件系统发现并加载技能。
///
/// 搜索路径（优先级升序）：
///   1. 内置技能（编译时）
///   2. 全局 ~/.greenix/skills/
///   3. 项目 .greenix/skills/
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
        // 目录布局：<name>/SKILL.md
        final skillFile = File('${entry.path}${Platform.pathSeparator}SKILL.md');
        if (skillFile.existsSync()) {
          final skill = _parseSkillFile(skillFile);
          if (skill != null) skills.add(skill);
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
    if (normalized.contains('.greenix/skills/')) {
      final isGlobal = normalized.contains('AppData') ||
          normalized.contains('.config/greenix');
      return isGlobal ? SkillScope.global : SkillScope.project;
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
}

// ─── 内置技能 ──────────────────────────────────────────────

/// 内置技能——编译时定义的 playbook。
class BuiltinSkills {
  static final List<Skill> _builtins = [];

  /// 注册一个内置技能。
  static void register(Skill skill) {
    _builtins.add(skill);
  }

  /// 获取所有内置技能。
  static List<Skill> all() => List.unmodifiable(_builtins);

  /// 将内置技能加载到索引中。
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
