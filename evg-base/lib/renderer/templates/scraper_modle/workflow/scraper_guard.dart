/// Scraper 守卫纯函数库（Phase 1 harness 核心）。
///
/// 全部为纯函数，无 Flutter 依赖，可独立单测。
/// 移植参考：
/// - 命令分类：`reasonix/internal/permission/bash_approval.go` + `shellsafe/shellsafe.go`
/// - 间接执行识别：bash_approval.go 的 isIndirectExecution 语义
///
/// 职责：
/// - [isTerminalCommandBlocked]：黑名单硬拒（破坏性/拼接/读取/外联/间接执行）
/// - [isTerminalCommandAllowed]：白名单自动放行
/// - [lintScraperCode]：Python 代码静态审查（violations block / warnings 假数据启发式）
/// - [validateCredentialArgs]：save_credential 参数校验
library scraper_guard;

// ═══════ 终端命令守卫 ═══════

/// 破坏性/危险命令基名黑名单（硬拒，不进弹窗）。
const Set<String> _destructiveCommands = {
  'rm', 'del', 'rmdir', 'rd', 'format', 'shutdown', 'reboot', 'taskkill',
  'kill', 'mkfs', 'dd', 'mv', 'truncate',
};

/// 读取命令（AI 应使用 read_workspace_file / read_request_snapshot 而非终端读文件）。
const Set<String> _readCommands = {
  'type', 'cat', 'get-content', 'more', 'less',
};

/// 外联命令。
const Set<String> _networkCommands = {
  'curl', 'wget', 'nc', 'ncat', 'telnet', 'ssh', 'ftp',
};

/// 命令拼接/重定向/管道符号（走私检测）。
final RegExp _shellSyntaxPattern = RegExp(r'[;&|><`]');

/// 间接执行基名（eval/source/env/python -c 等——可走私任意命令）。
const Set<String> _indirectBases = {
  'eval', 'source', 'xargs', 'builtin', 'command', 'exec', 'nohup', 'sudo',
  'bash', 'dash', 'sh', 'zsh', 'powershell', 'pwsh', 'cmd', 'node', 'bun',
  'deno', 'python', 'python3', 'py', 'perl', 'ruby', 'lua',
};

/// 取命令基名（去路径、去 .exe、小写）。
String _executableBase(String command) {
  var c = command.trim();
  final slash = c.lastIndexOf(RegExp(r'[/\\]'));
  if (slash >= 0) c = c.substring(slash + 1);
  c = c.toLowerCase();
  if (c.endsWith('.exe')) c = c.substring(0, c.length - 4);
  return c;
}

/// 白名单安全命令模式（自动放行，不弹窗）。
final RegExp _allowedPythonRun = RegExp(r'^python(?:3|3\.\d+)?\s+scraper\.py\s*$', caseSensitive: false);
final RegExp _allowedPipInstall = RegExp(r'^(?:python(?:3|3\.\d+)?\s+-m\s+)?pip\s+install\s+[\w\-\.]+(?:\s+[\w\-\.]+)*\s*$', caseSensitive: false);
final RegExp _allowedPipShow = RegExp(r'^(?:python(?:3|3\.\d+)?\s+-m\s+)?pip\s+(?:show|list)\s*$', caseSensitive: false);
final RegExp _allowedCd = RegExp(r'^cd\s+[\w\-\.\\/]+$');

/// 命令是否命中黑名单（硬拒，不进弹窗）。
bool isTerminalCommandBlocked(String command) {
  final trimmed = command.trim();
  if (trimmed.isEmpty) return true;

  // 拼接/重定向/管道/反引号走私检测
  if (_shellSyntaxPattern.hasMatch(trimmed)) {
    return true;
  }

  final firstWord = trimmed.split(RegExp(r'\s+')).first;
  final base = _executableBase(firstWord);

  if (_destructiveCommands.contains(base)) return true;
  if (_readCommands.contains(base)) return true;
  if (_networkCommands.contains(base)) return true;

  // 间接执行（python -c / eval / sh -c 等走私）
  if (_indirectBases.contains(base)) {
    // python 的 --version / -V 是安全的（读版本）
    if (base == 'python' || base == 'python3' || base == 'py') {
      final args = trimmed.split(RegExp(r'\s+')).skip(1).toList();
      final hasC = args.any((a) {
        final l = a.toLowerCase();
        return l == '-c' || (l.startsWith('-') && l.contains('c') && !l.startsWith('--') && l.length > 1);
      });
      if (hasC) return true; // python -c 走私 → 硬拒
      // python 非 -c 场景（如 python --version）交给白名单判定
      return false;
    }
    return true; // eval/sh -c/powershell -c 等一律硬拒
  }

  return false;
}

/// 命令是否命中白名单（自动放行，不弹窗）。
bool isTerminalCommandAllowed(String command) {
  final trimmed = command.trim();
  if (trimmed.isEmpty) return false;
  if (isTerminalCommandBlocked(trimmed)) return false;

  if (_allowedPythonRun.hasMatch(trimmed)) return true;
  if (_allowedPipInstall.hasMatch(trimmed)) return true;
  if (_allowedPipShow.hasMatch(trimmed)) return true;
  if (_allowedCd.hasMatch(trimmed)) return true;

  return false;
}

/// 命令守卫分级结果：block（硬拒）/ auto（自动放行）/ confirm（需弹窗确认）。
enum CommandVerdict { block, auto, confirm }

/// 对命令做完整分级（Gate pendingCallback 使用）。
CommandVerdict classifyTerminalCommand(String command) {
  if (isTerminalCommandBlocked(command)) return CommandVerdict.block;
  if (isTerminalCommandAllowed(command)) return CommandVerdict.auto;
  return CommandVerdict.confirm;
}

/// 生成拒绝消息（回灌 AI）。
String blockedCommandMessage(String command, String reason) {
  return '[error: 命令被守卫拒绝: $reason — "$command"'
      '（允许：python scraper.py / pip install <pkg> / cd <dir>）]';
}

// ═══════ Python 代码静态审查 ═══════

/// lint 结果：violations（block）/ warnings（假数据启发式，放行 + guardFlags）。
class LintResult {
  final List<String> violations;
  final List<String> warnings;

  const LintResult({this.violations = const [], this.warnings = const []});

  bool get hasViolations => violations.isNotEmpty;
  bool get hasWarnings => warnings.isNotEmpty;

  /// 是否命中"疑似假数据"warning（G5 门禁判定）。
  bool get suspectedFakeData =>
      warnings.any((w) => w.startsWith('假数据'));

  String toMessage() {
    final buf = StringBuffer();
    if (violations.isNotEmpty) {
      buf.writeln('❌ 代码审查未通过（violation）：');
      for (final v in violations) {
        buf.writeln('- $v');
      }
    }
    if (warnings.isNotEmpty) {
      buf.writeln('⚠️ 代码审查警告（warning）：');
      for (final w in warnings) {
        buf.writeln('- $w');
      }
    }
    return buf.toString().trimRight();
  }
}

/// 白名单 import 前缀：标准库常用子集 + requests（严格 stdlib+requests，A6）。
const Set<String> _allowedImportPrefixes = {
  'json', 'os', 're', 'sys', 'time', 'math', 'random', 'datetime',
  'collections', 'itertools', 'functools', 'urllib', 'http', 'ssl',
  'hashlib', 'hmac', 'base64', 'string', 'typing', 'pathlib', 'io',
  'requests', 'urllib3', 'decimal', 'enum', 'copy', 'traceback',
  'warnings', 'logging',
};

/// 危险 import 黑名单（硬拒）。
const Set<String> _dangerousImports = {
  'subprocess', 'socket', 'ctypes', 'pickle', 'pty', 'importlib',
  'paramiko', 'selenium', 'scrapy', 'playwright',
};

/// 模板完整性检查（scraper_exporter.dart 锁定模板的契约标志）。
const String _templateDef = 'def _get_config(key)';
const String _templateFlag = 'GREENIX_CONFIG_PATH';
const String _placeholder = '{CREDENTIAL_PLACEHOLDER}';

/// 审查 Python 爬虫代码。
///
/// [capturedUrls]：捕获日志中的 URL 集合（假数据启发式用，可空）。
LintResult lintScraperCode(String code, {Set<String>? capturedUrls}) {
  final violations = <String>[];
  final warnings = <String>[];

  // ── 模板完整性（violation）──
  if (!code.contains(_templateDef)) {
    violations.add('缺少锁定模板 `def _get_config(key)`（必须逐字包含）');
  } else if (!code.contains(_templateFlag)) {
    violations.add('模板 `_get_config` 缺少三级降级标志（GREENIX_CONFIG_PATH）');
  }
  if (code.contains(_placeholder)) {
    violations.add('残留占位符 {CREDENTIAL_PLACEHOLDER}（必须替换为凭证变量声明）');
  }

  // ── import 白名单（violation）──
  final importRe = RegExp(r'^\s*(?:import|from)\s+([a-zA-Z_][a-zA-Z0-9_]*)', multiLine: true);
  for (final m in importRe.allMatches(code)) {
    final mod = m.group(1)!;
    if (_dangerousImports.contains(mod)) {
      violations.add('危险 import: `$mod`（黑名单硬拒）');
      continue;
    }
    if (!_allowedImportPrefixes.contains(mod)) {
      violations.add('非白名单 import: `$mod`（仅允许标准库 + requests，A6）');
    }
  }

  // ── 危险调用（violation）──
  final dangerousCalls = [
    ('os.system', RegExp(r'os\.system\s*\(')),
    ('eval(', RegExp(r'\beval\s*\(')),
    ('exec(', RegExp(r'\bexec\s*\(')),
    ('__import__(', RegExp(r'\b__import__\s*\(')),
    ('compile(', RegExp(r'\bcompile\s*\(')),
  ];
  for (final (label, re) in dangerousCalls) {
    if (re.hasMatch(code)) {
      violations.add('危险调用: `$label`（禁止）');
    }
  }

  // ── open() 路径逃逸（violation）──
  final openRe = RegExp("open\\s*\\(\\s*['\"]([^'\"]+)['\"]");
  for (final m in openRe.allMatches(code)) {
    final path = m.group(1)!;
    if (path.startsWith('/') || path.contains('..') ||
        path.contains(':') || path.contains('scraper_sessions')) {
      violations.add('open() 路径越界: `$path`（禁止读取工作区外/会话文件）');
    }
  }

  // ── 凭证硬编码（violation）──
  final credHardcode = RegExp(
      "(USERNAME|PASSWORD|PASSWD|TOKEN|COOKIE|API_KEY|SECRET|AUTH)\\s*=\\s*['\"](?!\\s*\$)",
      caseSensitive: false);
  if (credHardcode.hasMatch(code)) {
    violations.add('凭证硬编码：禁止 `VAR = "字面量"`，必须用 `_get_config(\'KEY\')`');
  }

  // ── 结构预检（violation）──
  if (!code.contains('if __name__ == "__main__"') &&
      !code.contains("if __name__ == '__main__'")) {
    violations.add('缺少 `if __name__ == "__main__":` 入口');
  }
  if (!code.contains('json.dumps')) {
    violations.add('main 必须用 json.dumps 输出合法 JSON（平台 jsonDecode(stdout) 契约）');
  }

  // ── 假数据启发式（warning，G5 门禁）──
  // 网络库检测用 import 语句正则（覆盖 `import json, requests` 同语句多 import）
  final importStmt = RegExp(r'^\s*import\s+([a-zA-Z0-9_\.]+)', multiLine: true);
  final hasNetworkImport = importStmt.allMatches(code).any((m) {
    final mod = m.group(1)!;
    return mod == 'requests' || mod == 'urllib' || mod == 'urllib3' ||
        mod.startsWith('urllib.');
  }) || code.contains('from requests') || code.contains('urllib.request');
  final hasPrintData = RegExp(r'print\s*\(\s*json\.dumps\s*\(\s*\[?\{').hasMatch(code);

  if (!hasNetworkImport && hasPrintData) {
    warnings.add('假数据嫌疑：无网络库（requests/urllib）却直接 print 数据字面量');
  }
  if (hasPrintData) {
    warnings.add('假数据嫌疑：`print(json.dumps([{...}]))` 字面量直出（无变量/函数调用）');
  }
  if (capturedUrls != null && capturedUrls.isNotEmpty) {
    final codeUrls = RegExp(r'https?://[a-zA-Z0-9\.\-_/:%\?&=#]+').allMatches(code)
        .map((m) => m.group(0)!.split('?').first)
        .toSet();
    final hasOverlap = codeUrls.any((u) =>
        capturedUrls.any((c) => c.split('?').first == u));
    if (codeUrls.isNotEmpty && !hasOverlap) {
      warnings.add('假数据嫌疑：代码内 URL 与捕获日志 URL 无交集（可能抓错接口或伪造）');
    }
  }
  const placeholderData = [
    'example.com', 'lorem ipsum', '张三', '李四', '"test"', '"fake"',
    'placeholder', 'dummy',
  ];
  for (final p in placeholderData) {
    if (code.toLowerCase().contains(p.toLowerCase())) {
      warnings.add('假数据嫌疑：数据含占位符 `$p`');
      break;
    }
  }

  return LintResult(violations: violations, warnings: warnings);
}

// ═══════ save_credential 校验 ═══════

/// 校验 save_credential 参数（A8：允许任意 key，但校验合法性 + 长度）。
///
/// 返回错误消息；null 表示通过。
String? validateCredentialArgs(String key, String value) {
  if (key.isEmpty) return 'key 不能为空';
  if (key.length > 128) return 'key 过长（>128）';
  // 拒绝路径/换行/控制字符/等号（防注入与格式破坏）
  if (key.contains('/') || key.contains('\\') ||
      key.contains('\n') || key.contains('\r') ||
      key.contains('=') || key.contains(' ')) {
    return 'key 含非法字符（禁止路径/空白/等号/换行）';
  }
  // 控制字符
  for (final c in key.codeUnits) {
    if (c < 0x20) return 'key 含控制字符';
  }
  if (value.length > 8192) return 'value 过长（>8KB）';
  return null;
}

/// 生成凭证校验拒绝消息（回灌 AI）。
String blockedCredentialMessage(String reason) {
  return '[error: 凭证保存被守卫拒绝: $reason'
      '（key 建议含功能简写，如 ZJU_USERNAME / COURSE_COOKIE）]';
}
