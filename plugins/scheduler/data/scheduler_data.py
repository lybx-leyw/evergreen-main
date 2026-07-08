"""scheduler.exe — 智能调度（纯本地贪心算法，无外部依赖，无需联网）。

复刻参考：`.reference/.../features/scheduler/`（FlowScheduler.greedy deadline-first）
复刻目标：`.refer_ui/.../features/scheduler/`（任务输入表单 + 调度结果块列表）

用法:
  scheduler.exe --type=scheduler_plan --project-root <root>  → stdout JSON → exit

数据来源：插件自身 config/config.json 中的 tasks[]（由 manifest form 写入），
若为空则使用内置演示任务，保证本地自检可运行。
"""
import argparse
import json
import os
import sys


_PROJECT_ROOT = ""


def _load_tasks():
    cfg = os.path.join(_PROJECT_ROOT, "plugins", "scheduler", "config", "config.json")
    try:
        with open(cfg, encoding="utf-8") as f:
            data = json.load(f)
        tasks = data.get("tasks", [])
    except Exception:
        tasks = []
    if not tasks:
        tasks = [
            {"id": "d1", "description": "复习高等数学（第七章）", "timeNeededMinutes": 90,
             "deadline": "2026-07-10T22:00", "location": "图书馆"},
            {"id": "d2", "description": "完成操作系统实验报告", "timeNeededMinutes": 120,
             "deadline": "2026-07-09T20:00", "location": "自习室"},
            {"id": "d3", "description": "背单词 50 个", "timeNeededMinutes": 30,
             "deadline": "2026-07-08T23:00"},
            {"id": "d4", "description": "阅读论文并写摘要", "timeNeededMinutes": 60,
             "deadline": "2026-07-11T18:00", "location": "咖啡厅"},
        ]
    return tasks


def _fmt(mins):
    h = mins // 60
    m = mins % 60
    return f"{h:02d}:{m:02d}"


def _schedule(tasks):
    """贪心 deadline-first：按截止时间升序，把任务顺序排进 08:00–22:00 可用时段，
    每两个任务间插入不超过 10 分钟休息。跨天则滚动到次日 08:00。"""
    work_default = 25
    max_rest = 10
    avail_start = 8 * 60
    avail_end = 22 * 60
    blocks = []
    cursor = avail_start
    sorted_tasks = sorted(tasks, key=lambda t: t.get("deadline") or "9999-12-31T23:59")

    for t in sorted_tasks:
        need = int(t.get("timeNeededMinutes", work_default))
        start = cursor
        end = start + need
        if end > avail_end:  # 跨天，滚动到次日
            start = avail_start
            end = start + need
            cursor = avail_start
        blocks.append({
            "taskId": t.get("id"),
            "description": t.get("description", "未命名任务"),
            "startTime": _fmt(start),
            "endTime": _fmt(end),
            "location": t.get("location", ""),
            "deadline": t.get("deadline", ""),
            "isRest": False,
        })
        cursor = end
        if cursor + max_rest <= avail_end:
            blocks.append({
                "taskId": None,
                "description": "休息",
                "startTime": _fmt(cursor),
                "endTime": _fmt(cursor + max_rest),
                "location": "",
                "deadline": "",
                "isRest": True,
            })
            cursor += max_rest

    return {
        "blocks": blocks,
        "isValid": True,
        "taskCount": len(sorted_tasks),
        "restTimeMinutes": sum(b["endTime"] and 0 for b in blocks if b["isRest"]),
    }


def fetch_scheduler_plan():
    tasks = _load_tasks()
    return _schedule(tasks)


HANDLERS = {"scheduler_plan": fetch_scheduler_plan}


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
        sys.stderr.write(f"[scheduler] {args.type}: {e}\n")
        print(json.dumps({"error": str(e)}, ensure_ascii=False))
        sys.exit(1)
