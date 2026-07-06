"""showcase_page_code.exe — 页面级后端，代码页数据拉取和代码执行模拟。"""
import argparse
import json
import os
import sys
import random
from http.server import HTTPServer, BaseHTTPRequestHandler

_PROJECT_ROOT = ""

CODE_SAMPLES = {
    "hello": '''# Hello World
print("🎭 欢迎来到 Evergreen 展示大厅！")
name = "开发者"
print(f"你好，{name}！")''',

    "loop": '''# 循环演示
for i in range(5):
    print(f"第 {i+1} 次迭代: {'⭐' * (i+1)}")''',

    "calc": '''# 简单计算
a, b = 42, 7
print(f"{a} + {b} = {a + b}")
print(f"{a} - {b} = {a - b}")
print(f"{a} * {b} = {a * b}")
print(f"{a} / {b} = {a / b}")''',
}


class Handler(BaseHTTPRequestHandler):
    def _json(self, data, code=200):
        body = json.dumps(data, ensure_ascii=False).encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Access-Control-Allow-Origin", "*")
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, fmt, *args):
        sys.stderr.write(f"[showcase_page_code] {fmt % args}\n")

    def do_GET(self):
        path = self.path.split("?")[0]

        if path == "/health":
            return self._json({"status": "ok", "module": "showcase_page_code"})

        if path == "/api/samples":
            return self._json({
                "samples": [
                    {"id": "hello", "name": "Hello World", "description": "经典入门"},
                    {"id": "loop", "name": "循环演示", "description": "for 循环示例"},
                    {"id": "calc", "name": "简单计算", "description": "四则运算"},
                ]
            })

        if path.startswith("/api/samples/"):
            sample_id = path.rsplit("/", 1)[-1]
            code = CODE_SAMPLES.get(sample_id, CODE_SAMPLES["hello"])
            return self._json({"id": sample_id, "code": code})

        return self._json({"error": "not found"}, 404)

    def do_POST(self):
        path = self.path.split("?")[0]
        cl = self.headers.get("Content-Length")
        raw = self.rfile.read(int(cl)) if cl else b""
        body = json.loads(raw) if raw and raw.strip() else {}

        if path == "/api/execute":
            code = body.get("code", "")
            lines = code.strip().split("\n")
            results = []
            for i, line in enumerate(lines):
                stripped = line.strip()
                if not stripped:
                    results.append({"line": i + 1, "type": "empty", "message": ""})
                elif stripped.startswith("#"):
                    results.append({"line": i + 1, "type": "comment", "message": f"💬 {stripped[1:].strip()}"})
                elif "print(" in stripped:
                    # 提取 print 内容
                    import re
                    m = re.search(r'print\((.*?)\)', stripped)
                    msg = m.group(1).strip('"\'') if m else stripped
                    results.append({"line": i + 1, "type": "output", "message": f"🖨️ {msg}"})
                elif "=" in stripped and not any(kw in stripped for kw in ["==", "!=", "<=", ">="]):
                    results.append({"line": i + 1, "type": "assign", "message": f"📝 {stripped}"})
                elif "for " in stripped:
                    results.append({"line": i + 1, "type": "loop", "message": f"🔄 {stripped}"})
                elif "if " in stripped:
                    results.append({"line": i + 1, "type": "condition", "message": f"🔀 {stripped}"})
                else:
                    results.append({"line": i + 1, "type": "exec", "message": f"⚡ {stripped}"})

            return self._json({
                "results": results,
                "total_lines": len(lines),
                "execution_time": f"{random.randint(1, 50)}ms",
            })

        return self._json({"error": "not found"}, 404)


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--project-root", default=os.getcwd())
    args = parser.parse_args()
    _PROJECT_ROOT = os.path.abspath(args.project_root)

    server = HTTPServer(("127.0.0.1", 0), Handler)
    port = server.server_port
    print(f"PORT:{port}", flush=True)
    sys.stderr.write(f"[showcase_page_code] http://127.0.0.1:{port}\n")
    server.serve_forever()
