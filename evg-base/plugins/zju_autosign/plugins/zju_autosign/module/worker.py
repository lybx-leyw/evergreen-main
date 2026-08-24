#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
worker.py — 学在浙大自动签到 · 长驻监控进程（stdio 常驻终端）

Evergreen HTML 插件通过 `platform.process.start('autosign-worker')` 拉起本进程，
协议为 stdio 双向流（scope=long, protocol=stdio, runtime=python）：

  - stdout 逐行输出**状态/事件 JSON**，平台 bridge 逐行推送给页面
    （process:output 事件），页面据此实时渲染仪表盘。
  - stdin 逐行读取**命令**：
        status   → 立即输出一行当前状态 JSON
        checkin  → 触发一轮即时检查（等价于页面「立即签到」按钮）
        stop     → 优雅退出
  - 后台线程持续轮询 /api/radar/rollcalls，发现点名自动应答，结果逐行输出。

与旧版（protocol=http）的差异：
  - 不再自起 HTTP server / 输出 PORT: 行 —— HTML 模板不经过 ProcessManager，
    常驻进程必须由页面经 platform.process 主动拉起，走 stdio 才可双向交互。
  - 状态通过 stdout 逐行推送，而非写 state.json 等数据源读取。

凭证读取仍走 _get_config 三级降级，日志全走 stderr（stdout 只输出 JSON 行）。
"""
import argparse
import json
import os
import sys
import threading
import time
import traceback

import autosign_core as core

# ═══════════ 共享状态 ═══════════

_state = {
    "history": [],
    "pollCount": 0,
    "pid": os.getpid(),
    "startedAt": core._now(),
    "worker": True,
}
_state_lock = threading.Lock()
_stop = threading.Event()
_session = {"obj": None}          # 登录会话（失效后置 None 强制重登）
_manual_check = threading.Event()  # checkin 命令触发一轮即时检查


def _snapshot():
    with _state_lock:
        return dict(_state)


def _set_state(**kw):
    with _state_lock:
        _state.update(kw)


def _emit(obj):
    """向 stdout 输出一行 JSON（平台 process:output 事件逐行推送）。"""
    try:
        sys.stdout.write(json.dumps(obj, ensure_ascii=False) + "\n")
        sys.stdout.flush()
    except Exception:
        pass


def _emit_state():
    """输出一行当前状态快照。"""
    snap = _snapshot()
    # history 精简为最近 30 条，避免每行过大
    snap["history"] = (snap.get("history") or [])[-30:]
    _emit({"type": "state", "data": snap})


def _emit_event(entry):
    """输出一行签到事件（供页面追加到历史记录）。"""
    _emit({"type": "event", "data": entry})


# ═══════════ 监控循环 ═══════════

def monitor_loop():
    while not _stop.is_set():
        cfg = core.load_config()
        _set_state(
            enabled=cfg["enabled"],
            location=cfg["location"],
            interval=cfg["interval"],
            updatedAt=core._now(),
        )

        if not cfg["username"] or not cfg["password"]:
            _set_state(
                running=False,
                error="请先在设置面板配置 ZJU_USERNAME / ZJU_PASSWORD（统一认证账号密码）",
            )
            _emit_state()
            _stop.wait(10)
            continue

        try:
            if _session["obj"] is None:
                _session["obj"] = core.ZJUCoursesSession(
                    cfg["username"], cfg["password"])
                _session["obj"].login()
            sess = _session["obj"]

            if _manual_check.is_set():
                _manual_check.clear()
                snap = core.run_cycle(sess, cfg, _snapshot())
                _set_state(**snap)

            if cfg["enabled"]:
                snap = core.run_cycle(sess, cfg, _snapshot())
                _set_state(**snap)
                _set_state(running=True)
            else:
                _set_state(running=False,
                           note="自动签到已暂停（AUTOSIGN_ENABLED=false）")
            _emit_state()
        except Exception as e:
            _session["obj"] = None  # 强制下次重登
            _set_state(running=False, error=str(e))
            _emit_state()
            core._log("监控循环异常: %s\n%s" % (e, traceback.format_exc()))
            _stop.wait(5)

        _stop.wait(max(2, min(60, cfg["interval"])))


# ═══════════ stdin 命令循环 ═══════════

def command_loop():
    """逐行读取 stdin 命令并处理。"""
    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        cmd = line.split(None, 1)[0].lower()
        if cmd in ("stop", "quit", "exit"):
            _stop.set()
            break
        elif cmd == "status":
            _emit_state()
        elif cmd == "checkin":
            _manual_check.set()
            _emit({"type": "notice", "data": "已触发一轮即时检查"})
        else:
            _emit({"type": "notice", "data": "未知命令: %s" % line})
    _stop.set()


# ═══════════ 入口 ═══════════

def main():
    ap = argparse.ArgumentParser(description="学在浙大自动签到 worker（stdio）")
    ap.add_argument("--project-root", default="", help="平台注入的项目根目录")
    ap.add_argument("--port", type=int, default=0, help="兼容旧参数，忽略")
    ap.add_argument("--type", default="", help="兼容数据源参数，忽略")
    ap.add_argument("--greenix-config", default="", help="兼容数据源参数，忽略")
    args, _ = ap.parse_known_args()

    core._log("worker（stdio）已启动 pid=%d" % os.getpid())

    threading.Thread(target=monitor_loop, daemon=True).start()
    try:
        command_loop()
    except KeyboardInterrupt:
        _stop.set()
    finally:
        _stop.set()
    return 0


if __name__ == "__main__":
    sys.exit(main())
