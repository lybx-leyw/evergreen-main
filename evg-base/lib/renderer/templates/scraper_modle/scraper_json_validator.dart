/// scraper.py stdout JSON 格式验证器。
///
/// 在打包（导出 data 插件）前自动注入到生成的 scraper.py 中，
/// 确保 stdout 输出合法 JSON。
///
/// 使用方式：在生成的 scraper.py 的 `if __name__ == "__main__"` 之前插入:
///   from scraper_json_validator import validate_and_output
///   validate_and_output(data)
library scraper_json_validator;

import 'dart:convert';

/// 工具返回给 AI 的结果上限（字符）。
///
/// ⚠️ 2026-08-02 事故：AI 生成的诊断代码读取了 8MB 的 scraper_sessions.json，
/// `run_terminal_command` 把 2.1MB 输出全量回灌 Agent → DeepSeek API 400
/// → 流程死循环。所有回传 AI 的工具输出必须经 [truncateToolOutput] 截断。
const int maxToolResultChars = 8000;

/// 截断工具输出到 [maxToolResultChars]，保留头部 80% + 尾部 20%。
///
/// 校验类逻辑（如 [validateScraperStdout]）请使用原始完整输出，仅回传前截断。
String truncateToolOutput(String output) {
  if (output.length <= maxToolResultChars) return output;
  final headLen = (maxToolResultChars * 0.8).round();
  final tailLen = maxToolResultChars - headLen;
  return '${output.substring(0, headLen)}\n'
      '…[输出过长，已截断 ${output.length - maxToolResultChars} 字符]…\n'
      '${output.substring(output.length - tailLen)}';
}

// ═══════ Dart 侧 stdout JSON 校验（AI 调试循环用） ═══════
//
// 背景：skill 第 6 步与数据插件要求 scraper 的 stdout 必须是合法 JSON
// （平台会 `jsonDecode(stdout)` 解析）。但 AI 调试循环里的
// `run_python_scraper` / 终端 `run_terminal_command` 过去只检查 exitCode，
// 导致「脚本打印了人类可读文本却 exitCode=0」被误判为成功、提前 markDone，
// 而平台真正 jsonDecode 时才「检验失败」——AI 全程看不到校验日志，无法自我修正。
//
// 因此这里抽出一个与 `jsonDecode(stdout)` 行为一致的 Dart 校验器，
// 让 AI 的 run 循环跑和平台完全相同的检验，并把失败日志（含 ❌ 标记）回灌给 AI，
// 使其经既有 _onAgentEvent 逻辑进入调试分支自我修正。

/// scraper stdout 的 JSON 校验结果。
class ScraperStdoutValidation {
  final bool isValid;
  final String? error;
  final String stdout;

  ScraperStdoutValidation({
    required this.isValid,
    this.error,
    required this.stdout,
  });
}

/// 校验 scraper 的 stdout 是否为合法 JSON（与平台 `jsonDecode(stdout)` 行为一致）。
///
/// - 空输出 → 非法（未产出数据）
/// - 整体 `jsonDecode` 失败（含前缀文本、trailing 文本等）→ 非法
/// - 否则 → 合法
ScraperStdoutValidation validateScraperStdout(String stdout) {
  final trimmed = stdout.trim();
  if (trimmed.isEmpty) {
    return ScraperStdoutValidation(
      isValid: false,
      error: 'stdout 为空，scraper 未输出任何数据',
      stdout: stdout,
    );
  }
  try {
    jsonDecode(trimmed);
    return ScraperStdoutValidation(isValid: true, stdout: stdout);
  } catch (e) {
    return ScraperStdoutValidation(
      isValid: false,
      error: e.toString(),
      stdout: stdout,
    );
  }
}

/// 构造校验失败、回传给 AI 的工具结果字符串。
///
/// 故意包含 `❌` 标记：AI 面板 [_onAgentEvent] 的 success 启发式会把含 `❌`/
/// `Traceback` 的工具结果判定为失败并触发 `startDebugging()`，从而让 AI 看到
/// 校验日志并自我修正（修改代码输出合法 JSON 后重试）。
String buildJsonValidationFailureMessage(String stdout, {String? error}) {
  final preview = stdout.length > 800 ? '${stdout.substring(0, 800)}…' : stdout;
  final err = error != null ? '\n错误详情: $error' : '';
  return '❌ JSON 输出校验失败：平台要求 scraper 的 stdout 必须是合法 JSON'
      '（{...} 或 [...]），但当前输出不是合法 JSON。'
      '请修改代码使 main() 返回 dict/list 并用 json.dumps() 输出，'
      '不要把人类可读文本 / emoji / 进度提示输出到 stdout（调试信息请用 sys.stderr）。\n'
      '--- 你的 stdout 输出 ---\n$preview$err\n'
      '请根据以上校验错误修改代码后，再次调用工具重试。';
}

/// 生成 stdout 为合法 JSON 时的成功提示（含「JSON 校验通过」让 AI 明确已完成）。
String buildJsonValidationSuccessMessage(String stdout, String stderr) {
  return '✅ 爬虫执行成功 (exitCode=0) 且 JSON 输出校验通过\n'
      '--- STDOUT ---\n$stdout\n'
      '${stderr.isNotEmpty ? '--- STDERR ---\n$stderr\n' : ''}';
}

/// 生成 stdout 为合法 JSON 时的成功提示（终端路径，不含 exitCode 外的冗余）。
String buildJsonValidationSuccessMessageForTerminal(String stdout, String stderr) {
  return '✅ 命令执行成功 (exitCode=0) 且 JSON 输出校验通过\n'
      '--- STDOUT ---\n$stdout\n'
      '${stderr.isNotEmpty ? '--- STDERR ---\n$stderr\n' : ''}';
}

/// 生成 stdout 校验失败时的终端回传结果（含 ❌ 以触发 AI 调试分支）。
String buildJsonValidationFailureMessageForTerminal(String stdout, {String? error}) {
  final preview = stdout.length > 800 ? '${stdout.substring(0, 800)}…' : stdout;
  final err = error != null ? '\n错误详情: $error' : '';
  return '❌ JSON 输出校验失败：scraper 的 stdout 必须是合法 JSON（{...} 或 [...]），'
      '但当前输出不是。`run_terminal_command` 仅执行命令，请改用 '
      '`run_python_scraper` 或在代码中确保输出合法 JSON 后重试。\n'
      '--- 你的 stdout 输出 ---\n$preview$err\n'
      '请根据以上校验错误修改代码后重试。';
}

/// 判断一条终端命令是否在执行 scraper（用于决定是否做 JSON 校验）。
bool isScraperRunCommand(String command) =>
    command.toLowerCase().contains('scraper.py');

/// 判断导出/热注册日志是否包含「检验失败」标记。
///
/// 背景（root cause B）：导出插件（.py 打包）、热注册、数据中心 orch.get 验证
/// 的失败（如 `scraper.py 打包失败`、`lastError`、`拉取异常`、`返回 null`）过去只弹在 UI，
/// AI 永远看不到、无法自修。此纯函数用于判定日志中是否存在失败，
/// 命中则把完整日志回灌给隔离 Agent 让其自我修正。
///
/// 命中任一失败标记即返回 true：❌ / lastError / 拉取异常 / 返回 null。
bool exportRegisterLogHasFailure(String log) {
  return log.contains('❌') ||
      log.contains('lastError') ||
      log.contains('拉取异常') ||
      log.contains('返回 null');
}

/// 生成注入到 scraper.py 的 Python 验证器代码。
///
/// 注入后 scraper.py 的结构变为：
/// ```python
/// # --- 原始 scraper 代码 ---
/// data = {...}  # 原始抓取逻辑产生的数据
///
/// # --- 自动注入的验证器 ---
/// <injectJsonValidator() 的返回值>
///
/// if __name__ == "__main__":
///     validate_and_output(data)
/// ```
///
/// validate_and_output 确保 stdout 是合法 JSON，并支持简单数据处理。
String injectJsonValidator() {
  return '''
# ==== EVERGREEN JSON VALIDATOR (auto-injected) ====
# DO NOT MODIFY — generated by scraper_json_validator.dart

import json, sys, re
from typing import Any

def validate_and_output(data: Any):
    """验证并输出数据为合法 JSON 到 stdout。

    规则：
    1. data 必须是 dict 或 list（顶层容器）
    2. 所有值必须是 JSON 可序列化类型
    3. 若 data 含 __json_ops__ 键，执行声明式数据处理（过滤/计算等）
    4. 输出到 stdout 的必须是合法 JSON 字符串
    """
    # 1) 验证顶层类型
    if not isinstance(data, (dict, list)):
        print(json.dumps({"error": f"scraper 输出类型错误: {type(data).__name__}，必须是 dict 或 list"}, ensure_ascii=False))
        sys.exit(1)

    # 2) 执行声明式数据处理（如果存在 __json_ops__）
    if isinstance(data, dict) and "__json_ops__" in data:
        ops = data.pop("__json_ops__")
        data = _apply_ops(data, ops)

    # 3) 序列化验证
    try:
        result = json.dumps(data, ensure_ascii=False, default=str)
        # 二次解析确认可逆
        json.loads(result)
        print(result)
    except (TypeError, json.JSONDecodeError) as e:
        print(json.dumps({"error": f"JSON 序列化失败: {e}"}, ensure_ascii=False))
        sys.exit(1)


def _apply_ops(data: dict, ops: dict) -> dict:
    """声明式数据处理管道。

    支持的 ops:
      - filter: {"field": "name", "keep": ["value1", "value2"]}  保留匹配项
      - filter: {"field": "name", "regex": "pattern"}            正则匹配保留
      - filter: {"field": "name", "min": 0, "max": 100}         数值范围
      - compute: {"field": "new_field", "op": "add|sub|mul|div", "a": "field1", "b": 100}  四则运算
      - compute: {"field": "new_field", "op": "concat", "a": "field1", "b": "field2"}      字符串拼接
      - sort: {"field": "name", "reverse": false}                排序
      - limit: 10                                                截取前 N 条
      - map: {"field": "name", "to": "new_name"}                 重命名字段
    """
    items = data if isinstance(data, list) else [data]
    is_single = not isinstance(data, list)

    for op_key, op_val in ops.items():
        if op_key == "filter" and isinstance(op_val, list):
            for f in op_val:
                items = _apply_filter(items, f)
        elif op_key == "compute" and isinstance(op_val, list):
            for c in op_val:
                items = _apply_compute(items, c)
        elif op_key == "sort" and isinstance(op_val, dict):
            items = sorted(items, key=lambda x: x.get(op_val.get("field", ""), ""), reverse=op_val.get("reverse", False))
        elif op_key == "limit" and isinstance(op_val, int):
            items = items[:op_val]
        elif op_key == "map" and isinstance(op_val, list):
            for m in op_val:
                items = _apply_map(items, m)

    return items[0] if is_single and items else items


def _apply_filter(items: list, f: dict) -> list:
    field = f.get("field", "")
    if not field: return items
    if "keep" in f:
        keep_vals = set(f["keep"])
        return [item for item in items if str(item.get(field, "")) in keep_vals]
    if "regex" in f:
        pattern = re.compile(f["regex"])
        return [item for item in items if pattern.search(str(item.get(field, "")))]
    if "min" in f or "max" in f:
        result = []
        for item in items:
            val = item.get(field)
            if val is None: continue
            try:
                num = float(val)
                if "min" in f and num < float(f["min"]): continue
                if "max" in f and num > float(f["max"]): continue
                result.append(item)
            except (ValueError, TypeError):
                continue
        return result
    return items


def _apply_compute(items: list, c: dict) -> list:
    field = c.get("field", "")
    op = c.get("op", "")
    a = c.get("a", "")
    b = c.get("b", "")
    if not field or not op: return items
    for item in items:
        va = item.get(a, a) if isinstance(a, str) else a
        vb = item.get(b, b) if isinstance(b, str) else b
        try:
            if op == "add": item[field] = float(va) + float(vb)
            elif op == "sub": item[field] = float(va) - float(vb)
            elif op == "mul": item[field] = float(va) * float(vb)
            elif op == "div": item[field] = float(va) / float(vb) if float(vb) != 0 else 0
            elif op == "concat": item[field] = str(va) + str(vb)
        except (ValueError, TypeError):
            item[field] = None
    return items


def _apply_map(items: list, m: dict) -> list:
    old_field = m.get("field", "")
    new_field = m.get("to", "")
    if not old_field or not new_field: return items
    for item in items:
        if old_field in item:
            item[new_field] = item.pop(old_field)
    return items


# ==== END VALIDATOR ====
''';
}

/// 从 scraper.py 源码中移除已注入的验证器（重新注入前清理）。
String stripValidator(String pythonCode) {
  const marker = '# ==== EVERGREEN JSON VALIDATOR (auto-injected) ====';
  const endMarker = '# ==== END VALIDATOR ====';
  final start = pythonCode.indexOf(marker);
  if (start < 0) return pythonCode;
  final end = pythonCode.indexOf(endMarker, start);
  if (end < 0) return pythonCode.substring(0, start);
  return pythonCode.substring(0, start) + pythonCode.substring(end + endMarker.length);
}

/// 注入验证器到 scraper.py 源码，并替换 __main__ 块。
///
/// 原始 scraper.py 的 `if __name__ == "__main__":` 块被替换为：
///   if __name__ == "__main__":
///       data = original_main_logic()
///       validate_and_output(data)
String injectValidatorIntoCode(String pythonCode) {
  final cleaned = stripValidator(pythonCode);
  final validatorCode = injectJsonValidator();

  // 把原始 __main__ 块包装成函数 original_main()
  final mainStart = cleaned.lastIndexOf('if __name__ == "__main__"');
  if (mainStart < 0) {
    // 没有 __main__ 块 — 追加验证器到末尾
    return '$cleaned\n$validatorCode\n';
  }

  final mainEnd = cleaned.lastIndexOf('if __name__ == "__main__"');
  // 提取 __main__ 块的内容（从下一行到文件末尾）
  final beforeMain = cleaned.substring(0, mainStart);
  final mainBody = cleaned.substring(mainStart);

  // 替换 __main__ 块
  final mainLines = mainBody.split('\n');
  final indentPrefix = '    '; // def 体内缩进
  final indentedBody = mainLines.skip(1).map((l) => '$indentPrefix$l').join('\n');

  final newMain = '''
${validatorCode}

def _original_main():
$indentedBody

if __name__ == "__main__":
    data = _original_main()
    validate_and_output(data)
''';

  return '$beforeMain$newMain';
}
