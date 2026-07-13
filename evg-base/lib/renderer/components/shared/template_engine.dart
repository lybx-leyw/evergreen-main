/// 轻量、安全的 HTML 模板引擎（M1 系统性修复：替代手写字符串拼接）。
///
/// 设计目标：
/// - 消除内联 HTML 拼接错误与 XSS 隐患；
/// - `{{ expr }}` 默认 HTML 转义（XSS 安全），`{{{ expr }}}` 仅限受信任内部片段；
/// - 不 eval 任意 Dart 代码：表达式仅支持「标识符链(. / [n]) + 过滤器」，
///   动态值统一从上下文解析，杜绝代码注入；
/// - 控制结构 `for` / `if`（含 `else`、`if not`）满足列表/条件渲染；
/// - 模板编译一次并按源码缓存复用（render 仅做 AST 遍历，性能不降级）。
library;

import 'dart:convert';

String _esc(String s) => s
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#39;');

// ── AST ──────────────────────────────────────────────
sealed class _Node {}

class _Text implements _Node {
  final String text;
  _Text(this.text);
}

class _Out implements _Node {
  final String expr;
  final bool raw;
  _Out(this.expr, this.raw);
}

class _For implements _Node {
  final String varName;
  final String iterable;
  final List<_Node> body;
  _For(this.varName, this.iterable, this.body);
}

class _If implements _Node {
  final String cond;
  final bool negated;
  final List<_Node> thenBody;
  final List<_Node>? elseBody;
  _If(this.cond, this.negated, this.thenBody, this.elseBody);
}

// ── 模板 ──────────────────────────────────────────────
class Template {
  final List<_Node> nodes;
  Template(this.nodes);

  static final Map<String, Template> _cache = {};

  /// 编译（按源码缓存复用）。
  static Template compile(String src) => _cache[src] ??= Template(_parse(src));

  String render(Map<String, dynamic> ctx) {
    final buf = StringBuffer();
    for (final n in nodes) _renderNode(n, ctx, buf);
    return buf.toString();
  }

  void _renderNode(_Node n, Map<String, dynamic> ctx, StringBuffer buf) {
    if (n is _Text) {
      buf.write(n.text);
    } else if (n is _Out) {
      final v = _evalExpr(n.expr, ctx);
      final s = _format(v);
      buf.write(n.raw ? s : _esc(s));
    } else if (n is _For) {
      final iterable = _evalExpr(n.iterable, ctx);
      final items = iterable is List ? iterable : const [];
      for (var i = 0; i < items.length; i++) {
        final scope = <String, dynamic>{
          ...ctx,
          n.varName: items[i],
          'loop': {
            'index': i,
            'first': i == 0,
            'last': i == items.length - 1,
          },
        };
        for (final b in n.body) _renderNode(b, scope, buf);
      }
    } else if (n is _If) {
      var ok = _truthy(_evalExpr(n.cond, ctx));
      if (n.negated) ok = !ok;
      final body = ok ? n.thenBody : (n.elseBody ?? const []);
      for (final b in body) _renderNode(b, ctx, buf);
    }
  }
}

/// 顶层便捷入口：解析（缓存）+ 渲染。
String renderTemplate(String src, Map<String, dynamic> ctx) =>
    Template.compile(src).render(ctx);

// ── 表达式求值 ───────────────────────────────────────
dynamic _evalExpr(String expr, Map<String, dynamic> ctx) {
  expr = expr.trim();
  final pipe = expr.split('|');
  dynamic value = _resolvePath(pipe[0].trim(), ctx);
  for (var i = 1; i < pipe.length; i++) {
    value = _applyFilter(pipe[i].trim(), value, ctx);
  }
  return value;
}

dynamic _resolvePath(String path, Map<String, dynamic> ctx) {
  final parts = path.split('.');
  dynamic value = ctx[parts[0]];
  for (var i = 1; i < parts.length; i++) {
    final part = parts[i];
    if (value == null) return null;
    if (value is Map) {
      value = value[part];
    } else if (value is List && int.tryParse(part) != null) {
      final idx = int.parse(part);
      value = idx >= 0 && idx < value.length ? value[idx] : null;
    } else {
      return null;
    }
  }
  return value;
}

bool _truthy(dynamic v) {
  if (v == null) return false;
  if (v is bool) return v;
  if (v is String) return v.isNotEmpty;
  if (v is List) return v.isNotEmpty;
  if (v is Map) return v.isNotEmpty;
  if (v is num) return v != 0;
  return true;
}

dynamic _applyFilter(String spec, dynamic input, Map<String, dynamic> ctx) {
  final lp = spec.indexOf('(');
  final name = lp < 0 ? spec.trim() : spec.substring(0, lp).trim();
  final args =
      lp < 0 ? <dynamic>[] : _parseArgs(spec.substring(lp + 1, spec.lastIndexOf(')')), ctx);
  switch (name) {
    case 'esc':
      return _esc(_format(input));
    case 'raw':
      return _format(input);
    case 'default':
      if (input == null ||
          (input is String && input.isEmpty) ||
          (input is List && input.isEmpty) ||
          (input is Map && input.isEmpty)) {
        return args.isNotEmpty ? args[0] : '';
      }
      return input;
    case 'allow':
      // allow(input, allowed..., fallback)：末位为 fallback，前位为允许值白名单。
      if (args.length < 2) return input;
      final allowed = args.sublist(0, args.length - 1);
      final fallback = args.last;
      return allowed.contains(input) ? input : fallback;
    case 'upper':
      return _format(input).toUpperCase();
    case 'lower':
      return _format(input).toLowerCase();
    case 'len':
      if (input is List) return input.length;
      if (input is Map) return input.length;
      if (input is String) return input.length;
      return 0;
    case 'json':
      return jsonEncode(input);
    case 'get':
      // 按动态键取值：input[args[0]]，用于表格按列 key 取单元格。
      if (input is Map && args.isNotEmpty) return input[args[0]];
      return null;
    case 'hex':
      // 校验十六进制颜色（如 #58a6ff），非法则回退，杜绝 style 属性注入。
      final s = _format(input);
      return RegExp(r'^#[0-9a-fA-F]{3,8}$').hasMatch(s) ? s : '#c9d1d9';
    default:
      return input;
  }
}

List<dynamic> _parseArgs(String inner, Map<String, dynamic> ctx) {
  inner = inner.trim();
  if (inner.isEmpty) return [];
  final args = <dynamic>[];
  final buf = StringBuffer();
  var quote = '';
  var sawQuote = false;
  void flushArg() {
    final tok = buf.toString().trim();
    if (tok.isNotEmpty) {
      // 加引号的参数保持为字符串字面量；未加引号的视为路径表达式。
      args.add(sawQuote ? tok : _resolvePathOrLit(tok, ctx));
    }
    buf.clear();
    sawQuote = false;
  }

  for (var i = 0; i < inner.length; i++) {
    final c = inner[i];
    if (quote.isNotEmpty) {
      if (c == quote) {
        quote = '';
        sawQuote = true;
      } else {
        buf.write(c);
      }
    } else if (c == "'" || c == '"') {
      quote = c;
    } else if (c == ',') {
      flushArg();
    } else {
      buf.write(c);
    }
  }
  flushArg();
  return args;
}

dynamic _resolvePathOrLit(String raw, Map<String, dynamic> ctx) {
  final n = num.tryParse(raw);
  if (n != null) return n;
  if (raw == 'true') return true;
  if (raw == 'false') return false;
  // 未加引号的参数 → 视为路径表达式（安全：仅从上下文解析，绝不 eval）。
  return _resolvePath(raw, ctx);
}

String _format(dynamic v) {
  if (v == null) return '';
  if (v is List || v is Map) return jsonEncode(v);
  return v.toString();
}

// ── 解析器（tokenize + 递归下降）──────────────────────
List<_Node> _parse(String src) {
  final tokens = _tokenize(src);
  var pos = 0;

  List<_Node> parseBlock(String endTag) {
    final nodes = <_Node>[];
    while (pos < tokens.length) {
      final t = tokens[pos];
      if (t is _TEnd) {
        if (t.tag == endTag) {
          pos++;
          return nodes;
        }
        pos++;
        continue; // 游离 end 标签：跳过
      }
      if (t is _TText) {
        nodes.add(_Text(t.text));
        pos++;
        continue;
      }
      if (t is _TOut) {
        nodes.add(_Out(t.expr, t.raw));
        pos++;
        continue;
      }
      if (t is _TDir) {
        if (t.name == 'else') {
          if (endTag == 'if') {
            pos++;
            return nodes;
          }
          pos++;
          continue; // for 体内的游离 else：跳过
        }
        if (t.name == 'for') {
          pos++;
          final body = parseBlock('for');
          nodes.add(_For(t.arg1, t.arg2, body));
          continue;
        }
        if (t.name == 'if') {
          pos++;
          final thenBody = parseBlock('if');
          List<_Node>? elseBody;
          if (pos < tokens.length &&
              tokens[pos] is _TDir &&
              (tokens[pos] as _TDir).name == 'else') {
            pos++;
            elseBody = parseBlock('if');
          }
          nodes.add(_If(t.arg2, t.negated, thenBody, elseBody));
          continue;
        }
        pos++; // 未知指令：跳过
        continue;
      }
    }
    return nodes;
  }

  return parseBlock('');
}

// ── Token ─────────────────────────────────────────────
sealed class _T {}

class _TText implements _T {
  final String text;
  _TText(this.text);
}

class _TOut implements _T {
  final String expr;
  final bool raw;
  _TOut(this.expr, this.raw);
}

class _TDir implements _T {
  final String name; // for / if / else
  final String arg1; // for: varName
  final String arg2; // for: iterable ; if: cond
  final bool negated;
  _TDir(this.name, this.arg1, this.arg2, this.negated);
}

class _TEnd implements _T {
  final String tag; // for / if
  _TEnd(this.tag);
}

List<_T> _tokenize(String src) {
  final tokens = <_T>[];
  var i = 0;
  final n = src.length;
  final text = StringBuffer();

  void flush() {
    if (text.isNotEmpty) {
      tokens.add(_TText(text.toString()));
      text.clear();
    }
  }

  while (i < n) {
    if (src.startsWith('{{{', i)) {
      flush();
      var j = i + 3;
      while (j < n && !src.startsWith('}}}', j)) j++;
      tokens.add(_TOut(src.substring(i + 3, j).trim(), true));
      i = j + 3;
    } else if (src.startsWith('{{', i)) {
      flush();
      var j = i + 2;
      while (j < n && !src.startsWith('}}', j)) j++;
      tokens.add(_TOut(src.substring(i + 2, j).trim(), false));
      i = j + 2;
    } else if (src.startsWith('{%', i)) {
      flush();
      var j = i + 2;
      while (j < n && !src.startsWith('%}', j)) j++;
      final inner = src.substring(i + 2, j).trim();
      i = j + 2;
      if (inner.startsWith('end')) {
        tokens.add(_TEnd(inner.substring(3).trim()));
      } else if (inner.startsWith('for ')) {
        final body = inner.substring(4).trim();
        final sp = body.split(' in ');
        tokens.add(_TDir('for', sp[0].trim(),
            sp.length > 1 ? sp.sublist(1).join(' in ').trim() : '', false));
      } else if (inner.startsWith('if not ')) {
        tokens.add(_TDir('if', '', inner.substring(7).trim(), true));
      } else if (inner.startsWith('if ')) {
        tokens.add(_TDir('if', '', inner.substring(3).trim(), false));
      } else if (inner == 'else') {
        tokens.add(_TDir('else', '', '', false));
      } else {
        tokens.add(_TText('{%$inner%}'));
      }
    } else {
      text.write(src[i]);
      i++;
    }
  }
  flush();
  return tokens;
}
