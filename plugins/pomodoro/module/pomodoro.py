"""Pomodoro Timer 内置模块 — HTTP 服务后端。

提供 REST API 供 Flutter 前端调用：
  GET  /health           → 健康检查
  GET  /status           → 当前状态（运行中/暂停/空闲，剩余秒数）
  POST /start            → 启动计时（body: {work: 25, break: 5}）
  POST /pause            → 暂停
  POST /resume           → 继续
  POST /stop             → 停止
  GET  /history          → 历史记录
  GET  /stats            → 今日统计
"""
import argparse
import json
import os
import sys
import threading
import time
from datetime import datetime
from http.server import HTTPServer, BaseHTTPRequestHandler

# ═══════ 项目根 ═══════

_PROJECT_ROOT = ""

def _port_path(name):
    # type: (str) -> str
    return os.path.join(_PROJECT_ROOT, name) if _PROJECT_ROOT else name

def _read_port(name):
    try:
        path = _port_path(name)
        if os.path.isfile(path):
            with open(path) as f:
                return f.read().strip()
    except Exception:
        pass
    return None

# ═══════ 番茄钟状态机 ═══════

class PomodoroState:
    IDLE = "idle"
    WORKING = "working"
    BREAK = "break"
    PAUSED = "paused"

class PomodoroTimer:
    def __init__(self):
        self.state = PomodoroState.IDLE
        self.work_duration = 25 * 60  # 25 minutes
        self.break_duration = 5 * 60  # 5 minutes
        self.remaining = 0
        self.total_elapsed = 0
        self.session_count = 0
        self._timer = None
        self._start_time = 0
        self._lock = threading.Lock()
        self.history = []  # [{session, started, ended, work_min, break_min}]
        self._current_session = None
        self._pre_pause_state = None

    def start(self, work_min=25, break_min=5):
        with self._lock:
            self.work_duration = work_min * 60
            self.break_duration = break_min * 60
            self.remaining = self.work_duration
            self.state = PomodoroState.WORKING
            self._start_time = time.time()
            self.session_count += 1
            self._current_session = {
                "session": self.session_count,
                "started": datetime.now().isoformat(),
                "work_min": work_min,
                "break_min": break_min,
                "phases": []
            }
            self._start_timer()

    def pause(self):
        with self._lock:
            if self.state in (PomodoroState.WORKING, PomodoroState.BREAK):
                self._pre_pause_state = self.state
                self.state = PomodoroState.PAUSED
                self._cancel_timer()
                self.total_elapsed += time.time() - self._start_time

    def resume(self):
        with self._lock:
            if self.state == PomodoroState.PAUSED and self.remaining > 0:
                self.state = self._pre_pause_state
                self._pre_pause_state = None
                self._start_time = time.time()
                self._start_timer()

    def stop(self):
        with self._lock:
            self._cancel_timer()
            if self._current_session:
                elapsed = int(self.total_elapsed + (time.time() - self._start_time if self.state != PomodoroState.PAUSED else 0))
                self._current_session["ended"] = datetime.now().isoformat()
                self._current_session["total_seconds"] = elapsed
                self.history.append(self._current_session)
                if len(self.history) > 100:
                    self.history = self.history[-100:]
                self._current_session = None
            self.state = PomodoroState.IDLE
            self.remaining = 0
            self.total_elapsed = 0

    def get_status(self):
        with self._lock:
            return {
                "state": self.state,
                "remaining_seconds": max(0, int(self.remaining)),
                "elapsed_seconds": int(self.total_elapsed + (
                    0 if self.state == PomodoroState.PAUSED else (time.time() - self._start_time)
                )),
                "session": self.session_count,
                "work_duration_min": self.work_duration // 60,
                "break_duration_min": self.break_duration // 60,
            }

    def get_stats(self):
        today = datetime.now().strftime("%Y-%m-%d")
        today_sessions = [s for s in self.history if s.get("started", "").startswith(today)]
        total_seconds = sum(s.get("total_seconds", 0) for s in today_sessions)
        return {
            "today_sessions": len(today_sessions),
            "today_minutes": total_seconds // 60,
            "total_sessions": len(self.history),
            "current_streak": self._calculate_streak(),
        }

    def _calculate_streak(self):
        # Simple: count consecutive days with at least one session
        days = set()
        for s in self.history:
            d = s.get("started", "")[:10]
            days.add(d)
        days = sorted(days, reverse=True)
        if not days:
            return 0
        streak = 1
        for i in range(len(days) - 1):
            d1 = datetime.strptime(days[i], "%Y-%m-%d")
            d2 = datetime.strptime(days[i + 1], "%Y-%m-%d")
            if (d1 - d2).days == 1:
                streak += 1
            else:
                break
        return streak

    def _on_tick(self):
        with self._lock:
            self.remaining -= 1
            if self.remaining <= 0:
                self._on_phase_end()

    def _on_phase_end(self):
        was_working = (self.state == PomodoroState.WORKING)
        if was_working:
            self.state = PomodoroState.BREAK
            self.remaining = self.break_duration
            if self._current_session:
                self._current_session["phases"].append({
                    "type": "work_end",
                    "time": datetime.now().isoformat(),
                })
        else:
            # Break ended → go to idle
            self.state = PomodoroState.IDLE
            self.remaining = 0
            if self._current_session:
                self._current_session["ended"] = datetime.now().isoformat()
                self._current_session["total_seconds"] = int(self.total_elapsed + time.time() - self._start_time)
                self.history.append(self._current_session)
                self._current_session = None

        self._cancel_timer()
        if self.state != PomodoroState.IDLE:
            self._start_time = time.time()
            self._start_timer()

    def _start_timer(self):
        if self._timer:
            self._timer.cancel()
        self._timer = threading.Timer(1.0, self._tick_loop)
        self._timer.start()

    def _tick_loop(self):
        self._on_tick()
        if self.remaining > 0 and self.state not in (PomodoroState.IDLE, PomodoroState.PAUSED):
            self._start_timer()

    def _cancel_timer(self):
        if self._timer:
            self._timer.cancel()
            self._timer = None


# ═══════ HTTP Handler ═══════

timer = PomodoroTimer()

class Handler(BaseHTTPRequestHandler):
    def _json(self, data, code=200):
        body = json.dumps(data, ensure_ascii=False).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Access-Control-Allow-Origin", "*")
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, fmt, *args):
        sys.stderr.write(f"[pomodoro] {fmt % args if args else fmt}\n")

    def do_GET(self):
        path = self.path.split("?")[0]
        if path == "/health":
            self._json({"status": "ok", "module": "pomodoro"})
        elif path == "/status":
            self._json(timer.get_status())
        elif path == "/history":
            self._json(timer.history[-20:])
        elif path == "/stats":
            self._json(timer.get_stats())
        else:
            self._json({"error": "not found"}, 404)

    def do_POST(self):
        path = self.path.split("?")[0]
        raw = self.rfile.read(int(self.headers.get("Content-Length", 0))) if self.headers.get("Content-Length") else b""
        body = json.loads(raw) if raw else {}

        if path == "/start":
            work = int(body.get("work", 25))
            brk = int(body.get("break", 5))
            timer.start(max(1, min(120, work)), max(1, min(30, brk)))
            self._json(timer.get_status())
        elif path == "/pause":
            timer.pause()
            self._json(timer.get_status())
        elif path == "/resume":
            timer.resume()
            self._json(timer.get_status())
        elif path == "/stop":
            timer.stop()
            self._json(timer.get_status())
        else:
            self._json({"error": "not found"}, 404)


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--project-root", default=os.getcwd(), help="Flutter project root")
    args = parser.parse_args()
    _PROJECT_ROOT = os.path.abspath(args.project_root)

    server = HTTPServer(("127.0.0.1", 0), Handler)
    port = server.server_port
    print(f"PORT:{port}", flush=True)
    sys.stderr.write(f"[pomodoro] http://127.0.0.1:{port}\n")
    sys.stderr.write(f"[pomodoro] project-root={_PROJECT_ROOT}\n")

    # 写入调试文件
    with open(".pomodoro_debug.txt", "w") as f:
        f.write(f"port={port}\n")
        f.write(f"root={_PROJECT_ROOT}\n")
        f.write(f"cwd={os.getcwd()}\n")

    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
