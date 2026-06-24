#!/usr/bin/env python3
"""
Evergreen Multi-Tools 工程流程状态机 (Agent Flow Controller)

管理 11 步完整交付流程，通过 .agent_state.json 持久化状态。
步骤 9 后强制锁定，等待人类反馈后才能继续。

用法:
  python agent_flow.py start --task="修复 Palace 溢出"
  python agent_flow.py check
  python agent_flow.py status
  python agent_flow.py feedback --result=pass [--note="不错"]
  python agent_flow.py feedback --result=fail --note="xxx 有 bug"
  python agent_flow.py reset --step=4
"""

import argparse
import json
import os
import sys
from datetime import datetime, timezone
from pathlib import Path


# ============================================================
# 配置
# ============================================================

# 状态文件路径（项目根目录）
SCRIPT_DIR = Path(__file__).resolve().parent
PROJECT_ROOT = SCRIPT_DIR.parent.parent  # agent_contributing/skill/ -> agent_contributing/ -> 项目根
STATE_FILE = PROJECT_ROOT / ".agent_state.json"

# 步骤定义
STEPS = {
    0:  {"id": "0_read_experience",   "name": "阅读经验库",         "next": 1},
    1:  {"id": "1_read_rules",        "name": "阅读规则文档",       "next": 2},
    2:  {"id": "2_read_code",         "name": "阅读核心代码",       "next": 3},
    3:  {"id": "3_confirm_requirements","name": "确认需求边界",      "next": 4},
    4:  {"id": "4_write_code",        "name": "修改代码",           "next": 5},
    5:  {"id": "5_write_tests",       "name": "写测试",             "next": 6},
    6:  {"id": "6_run_new_tests",     "name": "运行新增测试",       "next": 7},
    7:  {"id": "7_run_all_tests",     "name": "运行全量测试",       "next": 8},
    8:  {"id": "8_update_docs",       "name": "更新状态文档",       "next": 9},
    9:  {"id": "9_build_verify",      "name": "编译验证",           "next": None},  # 特殊：需要人类反馈
    10: {"id": "10_write_experience", "name": "写经验卡片",         "next": 11},
    11: {"id": "11_write_pr",         "name": "写 PR_history",      "next": None},  # 终止
}

# 步骤 9 的特殊后继：根据反馈决定
STEP9_PASS_NEXT = 10
STEP9_FAIL_NEXT = 4
STEP11_DONE = "done"


# ============================================================
# 状态管理
# ============================================================

def load_state() -> dict | None:
    """加载 .agent_state.json。不存在返回 None。"""
    if STATE_FILE.exists():
        with open(STATE_FILE, "r", encoding="utf-8") as f:
            return json.load(f)
    return None


def save_state(state: dict):
    """写入 .agent_state.json。"""
    state["updated"] = datetime.now(timezone.utc).isoformat()
    # 确保目录存在
    STATE_FILE.parent.mkdir(parents=True, exist_ok=True)
    with open(STATE_FILE, "w", encoding="utf-8") as f:
        json.dump(state, f, indent=2, ensure_ascii=False)
    print(f"✅ 状态已保存到 {STATE_FILE}")


def init_state(task: str) -> dict:
    """初始化一个全新的任务状态。"""
    return {
        "task": task,
        "current_step": 0,
        "steps": {},
        "feedback": None,
        "created": datetime.now(timezone.utc).isoformat(),
        "updated": datetime.now(timezone.utc).isoformat(),
    }


def require_state() -> dict:
    """加载状态，如果不存在则报错退出。"""
    state = load_state()
    if state is None:
        print("❌ 未找到 .agent_state.json，请先运行 start 命令初始化任务。")
        print(f"   运行: python {Path(__file__).name} start --task=\"你的任务描述\"")
        sys.exit(1)
    return state


# ============================================================
# 命令实现
# ============================================================

def cmd_start(task: str):
    """初始化新任务。"""
    if STATE_FILE.exists():
        print(f"⚠️  已存在 .agent_state.json，当前任务正在进行中：")
        cmd_status()
        print()
        resp = input("是否覆盖并开始新任务？[y/N] ").strip().lower()
        if resp != "y":
            print("已取消。")
            return

    state = init_state(task)
    save_state(state)
    print()
    print(f"🚀 任务已初始化: {task}")
    print(f"📍 当前步骤: 步骤 0 — {STEPS[0]['name']}")
    print()
    print("请按 SKILL.md 定义的流程逐步执行。")
    print("每完成一步，运行: python agent_contributing/skill/agent_flow.py check")


def cmd_check():
    """验证当前步骤完成，推进到下一步。"""
    state = require_state()
    current = state["current_step"]

    # 特殊处理：步骤 9 标记完成但阻塞，等待人类反馈
    if current == 9:
        step_id = STEPS[9]["id"]
        # 如果已经完成过，说明在等待反馈中
        if state.get("steps", {}).get(step_id, {}).get("done"):
            print("⛔ 步骤 9 已完成，仍在等待人类反馈。")
            print()
            print("   等待人类运行以下命令之一：")
            print(f"   python agent_contributing/skill/agent_flow.py feedback --result=pass")
            print(f"   python agent_contributing/skill/agent_flow.py feedback --result=fail --note=\"理由\"")
            return
        # 首次到达步骤 9：标记完成
        state["steps"][step_id] = {
            "done": True,
            "ts": datetime.now(timezone.utc).isoformat(),
        }
        save_state(state)
        print(f"✅ 步骤 9 (编译验证) 已完成")
        print("⛔ 此步骤后需要人类反馈，不能自动进入步骤 10。")
        print()
        print("   等待人类运行以下命令之一：")
        print(f"   python agent_contributing/skill/agent_flow.py feedback --result=pass")
        print(f"   python agent_contributing/skill/agent_flow.py feedback --result=fail --note=\"理由\"")
        return

    # 特殊处理：步骤 11 之后标记完成
    if current == 11:
        state["current_step"] = STEP11_DONE
        step_id = STEPS[11]["id"]
        state["steps"][step_id] = {
            "done": True,
            "ts": datetime.now(timezone.utc).isoformat(),
        }
        save_state(state)
        print("🎉 全部 11 步流程已完成！项目交付。")
        return

    # 特殊情况：已完成
    if current == STEP11_DONE:
        print("🎉 流程已完成，无需操作。")
        return

    # 正常推进
    step_info = STEPS[current]
    step_id = step_info["id"]
    next_step = step_info.get("next")

    # 标记当前步骤完成
    state["steps"][step_id] = {
        "done": True,
        "ts": datetime.now(timezone.utc).isoformat(),
    }

    if next_step is not None:
        state["current_step"] = next_step
        next_info = STEPS[next_step]
        save_state(state)
        print(f"✅ 步骤 {current} ({step_info['name']}) 已完成")
        print(f"➡️  进入步骤 {next_step} — {next_info['name']}")
        if next_step == 9:
            print()
            print("⚠️  注意：步骤 9 完成后将等待人类反馈，不能自动进入步骤 10。")
    else:
        save_state(state)
        print(f"✅ 步骤 {current} ({step_info['name']}) 已完成")
        print(f"⚠️  此步骤无自动后继，请按 SKILL.md 指引继续。")


def cmd_status():
    """显示当前任务状态。"""
    state = load_state()
    if state is None:
        print("📭 当前无进行中的任务。")
        print(f"   运行: python {Path(__file__).name} start --task=\"你的任务描述\"")
        return

    current = state["current_step"]
    task = state.get("task", "未知任务")
    feedback = state.get("feedback")

    print(f"📋 任务: {task}")
    print(f"📅 创建于: {state.get('created', '未知')}")
    print(f"🕐 更新于: {state.get('updated', '未知')}")
    print()

    # 流程图
    for step_num in sorted(STEPS.keys()):
        step_id = STEPS[step_num]["id"]
        step_name = STEPS[step_num]["name"]
        step_data = state.get("steps", {}).get(step_id, {})

        if step_num == current:
            symbol = "📍"  # 当前步骤
        elif step_data.get("done"):
            symbol = "✅"  # 已完成
        else:
            symbol = "⬜"  # 未完成

        done_ts = step_data.get("ts", "")
        ts_str = f" ({done_ts[:19]})" if done_ts else ""

        if step_num == 9 and step_data.get("done"):
            print(f"   {symbol} 步骤 {step_num}: {step_name}{ts_str} ⏸️  等待人类反馈")
        else:
            print(f"   {symbol} 步骤 {step_num}: {step_name}{ts_str}")

    if current == STEP11_DONE:
        print(f"\n🎉 全部步骤已完成！")

    if feedback:
        print(f"\n💬 人类反馈: {feedback.get('result')} — {feedback.get('note', '(无备注)')}")


def cmd_feedback(result: str, note: str | None = None):
    """人类给出反馈（仅在步骤 9 后有效）。"""
    state = require_state()
    current = state["current_step"]

    if current != 9:
        print(f"❌ 当前在步骤 {current}，不是步骤 9，不需要反馈。")
        print(f"   如果确实需要回退，请用 reset 命令。")
        return

    step9_id = STEPS[9]["id"]
    if not state.get("steps", {}).get(step9_id, {}).get("done"):
        print("⚠️  步骤 9 尚未标记完成，请先运行 check 完成编译验证步骤。")
        return

    # 记录反馈
    state["feedback"] = {
        "result": result,
        "note": note or "",
        "ts": datetime.now(timezone.utc).isoformat(),
    }

    if result == "pass":
        state["current_step"] = STEP9_PASS_NEXT
        next_name = STEPS[STEP9_PASS_NEXT]["name"]
        save_state(state)
        print(f"✅ 人类反馈通过！")
        print(f"➡️  进入步骤 {STEP9_PASS_NEXT} — {next_name}")
        print()
        print("   现在请写经验卡片（步骤 10），然后写 PR_history（步骤 11）。")

    elif result == "fail":
        state["current_step"] = STEP9_FAIL_NEXT
        next_name = STEPS[STEP9_FAIL_NEXT]["name"]
        save_state(state)
        print(f"❌ 人类反馈未通过。")
        print(f"⏪ 回退到步骤 {STEP9_FAIL_NEXT} — {next_name}")
        print()
        print("   🚨 回退前必须先做：")
        print("   1. 立即写失败经验卡片（不要等到步骤 10）")
        print("   2. 更新 agent_contributing/EXPERIENCE.md 索引")
        print("   3. 然后带着教训回到步骤 4（修改代码）")
        print()
        print(f"   state 已自动回退，请从步骤 4 重新开始。")

    else:
        print(f"❌ 无效的 feedback result: {result}，请使用 pass 或 fail。")


def cmd_reset(step: int):
    """强制回退到指定步骤（人类指令或故障恢复）。"""
    state = require_state()
    if step not in STEPS:
        print(f"❌ 无效的步骤号: {step}。有效步骤: {sorted(STEPS.keys())}")
        return

    old_step = state["current_step"]
    state["current_step"] = step
    state["feedback"] = None  # 清除旧反馈

    # 清除目标步骤及其之后的所有步骤状态
    steps_to_clear = [s for s in sorted(STEPS.keys()) if s >= step]
    for s in steps_to_clear:
        sid = STEPS[s]["id"]
        if sid in state.get("steps", {}):
            del state["steps"][sid]

    save_state(state)
    print(f"⏪ 已从步骤 {old_step} 回退到步骤 {step} — {STEPS[step]['name']}")
    print(f"   步骤 {step} 及之后的完成状态已被清除。")


# ============================================================
# CLI 入口
# ============================================================

def main():
    parser = argparse.ArgumentParser(
        description="Evergreen Multi-Tools 工程流程状态机",
        epilog="详见 agent_contributing/skill/SKILL.md",
    )
    subparsers = parser.add_subparsers(dest="command", help="命令")

    # start
    sp_start = subparsers.add_parser("start", help="初始化新任务")
    sp_start.add_argument("--task", required=True, help="任务描述")

    # check
    subparsers.add_parser("check", help="验证当前步骤完成并推进")

    # status
    subparsers.add_parser("status", help="查看当前任务状态")

    # feedback
    sp_fb = subparsers.add_parser("feedback", help="人类反馈（步骤 9 后）")
    sp_fb.add_argument("--result", required=True, choices=["pass", "fail"],
                       help="pass=通过继续步骤10, fail=回退步骤4")
    sp_fb.add_argument("--note", default=None, help="反馈备注")

    # reset
    sp_reset = subparsers.add_parser("reset", help="强制回退到指定步骤")
    sp_reset.add_argument("--step", type=int, required=True, help="目标步骤号 (0-11)")

    args = parser.parse_args()

    if args.command == "start":
        cmd_start(args.task)
    elif args.command == "check":
        cmd_check()
    elif args.command == "status":
        cmd_status()
    elif args.command == "feedback":
        cmd_feedback(args.result, args.note)
    elif args.command == "reset":
        cmd_reset(args.step)
    else:
        parser.print_help()


if __name__ == "__main__":
    main()
