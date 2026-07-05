"""Test pomodoro module server."""
import subprocess, time, json, urllib.request, sys, pathlib

PROJECT = str(pathlib.Path(__file__).resolve().parents[1])
EXE = str(pathlib.Path(__file__).resolve().parents[1] / 'lib' / 'core' / 'builtins' / 'pomodoro' / 'module' / 'pomodoro.exe')

p = subprocess.Popen([EXE, '--project-root', PROJECT], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
port_line = p.stdout.readline().strip()
port = int(port_line.split(':')[1])
print(f'Pomodoro started on port {port}')

time.sleep(0.3)

# Health check
resp = json.loads(urllib.request.urlopen(f'http://127.0.0.1:{port}/health', timeout=5).read())
assert resp["status"] == "ok", f"Health failed: {resp}"
print(f'Health: OK')

# Start a 1-min work session
req = urllib.request.Request(f'http://127.0.0.1:{port}/start', data=json.dumps({"work":1,"break":1}).encode(), headers={"Content-Type":"application/json"}, method="POST")
resp = json.loads(urllib.request.urlopen(req, timeout=5).read())
assert resp["state"] == "working", f"Start failed: {resp}"
assert resp["remaining_seconds"] > 0, f"Remaining should be >0: {resp}"
print(f'Start: state={resp["state"]}, remaining={resp["remaining_seconds"]}s')

# Get status
resp = json.loads(urllib.request.urlopen(f'http://127.0.0.1:{port}/status', timeout=5).read())
assert resp["state"] == "working", f"Status failed: {resp}"
print(f'Status: {resp["state"]}')

# Pause
req = urllib.request.Request(f'http://127.0.0.1:{port}/pause', data=b'{}', headers={"Content-Type":"application/json"}, method="POST")
resp = json.loads(urllib.request.urlopen(req, timeout=5).read())
assert resp["state"] == "paused", f"Pause failed: {resp}"
print(f'Pause: state={resp["state"]}')

# Resume
req = urllib.request.Request(f'http://127.0.0.1:{port}/resume', data=b'{}', headers={"Content-Type":"application/json"}, method="POST")
resp = json.loads(urllib.request.urlopen(req, timeout=5).read())
assert resp["state"] == "working", f"Resume failed: {resp}"
print(f'Resume: state={resp["state"]}')

# Stop
req = urllib.request.Request(f'http://127.0.0.1:{port}/stop', data=b'{}', headers={"Content-Type":"application/json"}, method="POST")
resp = json.loads(urllib.request.urlopen(req, timeout=5).read())
assert resp["state"] == "idle", f"Stop failed: {resp}"
print(f'Stop: state={resp["state"]}')

# Stats
resp = json.loads(urllib.request.urlopen(f'http://127.0.0.1:{port}/stats', timeout=5).read())
print(f'Stats: total_sessions={resp["total_sessions"]}, today={resp["today_sessions"]}')

# History
resp = json.loads(urllib.request.urlopen(f'http://127.0.0.1:{port}/history', timeout=5).read())
print(f'History: {len(resp)} entries')

p.terminate()
print('ALL POMODORO TESTS PASSED')
