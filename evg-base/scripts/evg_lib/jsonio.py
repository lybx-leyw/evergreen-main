# -*- coding: utf-8 -*-
"""evg_lib.jsonio — stdout JSON 输出契约助手 + 声明式校验管道。

供数据插件统一输出契约（对齐 data 插件行为契约：stdout 顶层必须是 Map/list，
`exitCode != 0` 或 stdout JSON 含 `error` 字段视为拉取失败）：

  - `emit(data)`              顶层 Map/list 序列化到 stdout（成功路径）
  - `fail(msg)`               向 stdout 写 `{"error": msg}` 并 `sys.exit(1)`
  - `validate_and_output(data)` 声明式校验 + 输出（提取自 scraper_json_validator.dart
                              生成的注入代码，语义逐字一致）

退出码约定：成功 = 0；失败 = 1（非零）。数据走 stdout（UTF-8，ensure_ascii=False），
人类可读诊断信息请走 sys.stderr，避免污染 JSON 输出。

声明式数据处理（`__json_ops__`，`validate_and_output` 内执行）：
  - filter: {"field": "name", "keep": ["v1","v2"]} | {"regex": "..."} | {"min":0,"max":100}
  - compute: {"field":"new","op":"add|sub|mul|div|concat","a":"f1","b":100}
  - sort: {"field":"name","reverse":false}
  - limit: 10
  - map: {"field":"name","to":"new_name"}

仅标准库（json/sys/re/typing），零新第三方依赖。
"""

import json
import re
import sys
from typing import Any


def emit(data: Any):
    """把顶层 dict/list 序列化为合法 JSON 写到 stdout（成功路径，不退出）。"""
    print(json.dumps(data, ensure_ascii=False, default=str))
    sys.stdout.flush()


def fail(msg: str, exit_code: int = 1):
    """向 stdout 写 `{"error": msg}` 并以非零退出码结束（对齐平台失败契约）。"""
    print(json.dumps({'error': msg}, ensure_ascii=False))
    sys.stdout.flush()
    sys.exit(exit_code)


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
