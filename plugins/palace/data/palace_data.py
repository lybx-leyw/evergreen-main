"""palace.exe — 认知事件仓库（本地 YAML-frontmatter Markdown 事件读取，无需联网）。

复刻参考：`.reference/.../features/palace/`（EventStore：.greenix/palace/events/{YYYY}/{MM}/{id}.md）
复刻目标：`.refer_ui/.../features/palace/`（三层树状视图 event_tree_view）

实现（R6 换法复刻）：renderer 无 tree 组件（_UnknownSlot），故本插件将事件以
data-table 列表呈现（类型/标题/时间/标签），复刻"浏览全部认知事件"的核心价值。
树状层级折叠由 data-table 的 filter 近似。事件文件格式：YAML frontmatter + Markdown 正文。
"""
import argparse
import glob
import json
import os
import re
import sys


_PROJECT_ROOT = ""


def _parse_frontmatter(text):
    if not text.lstrip().startswith("---"):
        return {}, text.strip()
    m = re.match(r"^---\s*\n(.*?)\n---\s*\n?(.*)$", text, re.DOTALL)
    if not m:
        return {}, text.strip()
    fm_text, body = m.group(1), m.group(2)
    fm = {}
    for line in fm_text.splitlines():
        if ":" in line:
            k, v = line.split(":", 1)
            fm[k.strip()] = v.strip()
    return fm, body.strip()


def _event_id(path, root):
    rel = os.path.relpath(path, root)
    return os.path.splitext(rel)[0].replace(os.sep, "/")


def fetch_palace_events():
    root = os.path.join(_PROJECT_ROOT, ".greenix", "palace", "events")
    events = []
    if not os.path.isdir(root):
        return {"events": [], "total": 0}
    for path in glob.glob(os.path.join(root, "**", "*.md"), recursive=True):
        try:
            with open(path, encoding="utf-8") as f:
                text = f.read()
        except Exception:
            continue
        fm, body = _parse_frontmatter(text)
        events.append({
            "id": _event_id(path, root),
            "type": fm.get("type", "thought"),
            "title": fm.get("title", os.path.splitext(os.path.basename(path))[0]),
            "capturedAt": fm.get("capturedAt", fm.get("date", "")),
            "tags": fm.get("tags", ""),
            "summary": (body[:120] if body else ""),
        })
    # 按时间倒序
    events.sort(key=lambda e: e.get("capturedAt") or "", reverse=True)
    return {"events": events, "total": len(events)}


HANDLERS = {"palace_events": fetch_palace_events}


if __name__ == "__main__":
    p = argparse.ArgumentParser()
    p.add_argument("--type", required=True)
    p.add_argument("--project-root", default=os.getcwd())
    args = p.parse_args()
    _PROJECT_ROOT = os.path.abspath(args.project_root)

    h = HANDLERS.get(args.type)
    if not h:
        print(json.dumps({"error": f"unknown type: {args.type}"}, ensure_ascii=False))
        sys.exit(1)
    try:
        result = h()
        print(json.dumps(result, ensure_ascii=False))
    except Exception as e:
        sys.stderr.write(f"[palace] {args.type}: {e}\n")
        print(json.dumps({"error": str(e)}, ensure_ascii=False))
        sys.exit(1)
