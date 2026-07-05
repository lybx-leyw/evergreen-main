"""Super App 数据源——为 DataOrchestrator 提供 super_grades 成绩数据。

启动后：
  1. 绑定 localhost:0（平台自动分配）→ stdout 输出 PORT:<N>
  2. 读取 .core_port 发现平台 Core 服务
  3. 提供 /health、/data、/ocr（转发到 Core）端点

这就是微服务网格：插件不捆绑 OCR 引擎，转发给平台即可。
"""
import json
import os
import sys
import urllib.parse
import urllib.request
from http.server import HTTPServer, BaseHTTPRequestHandler

# ═══════ 端口发现 ═══════

def _read_port_file(name):
    """读取平台端口文件，返回端口号或 None。"""
    try:
        path = os.path.join(os.getcwd(), name)
        if os.path.exists(path):
            with open(path) as f:
                return f.read().strip()
    except Exception:
        pass
    return None


def _discover_core():
    """发现 Core 微服务地址。"""
    port = _read_port_file(".core_port")
    if port:
        return f"http://127.0.0.1:{port}"
    return None


# ═══════ 数据 ═══════

GRADES = [
    {"id":"1","name":"张三","score":95,"grade":"A"},
    {"id":"2","name":"李四","score":87,"grade":"B"},
    {"id":"3","name":"王五","score":92,"grade":"A"},
    {"id":"4","name":"赵六","score":78,"grade":"C"},
    {"id":"5","name":"孙七","score":88,"grade":"B"},
]

CORE_BASE = _discover_core()


# ═══════ HTTP Handler ═══════

class Handler(BaseHTTPRequestHandler):
    def _json(self, data, code=200):
        body = json.dumps(data, ensure_ascii=False).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Access-Control-Allow-Origin", "*")
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *args):
        sys.stderr.write(f"[super_app] {args[0]}\n")

    def do_GET(self):
        qs = urllib.parse.parse_qs(urllib.parse.urlparse(self.path).query)
        path = urllib.parse.urlparse(self.path).path

        if path == "/health":
            self._json({"status": "ok", "core_discovered": CORE_BASE is not None})

        elif path == "/data":
            sort = qs.get("sort", ["name"])[0]
            order = qs.get("order", ["asc"])[0]
            q = qs.get("q", [""])[0].lower()
            data = sorted(GRADES, key=lambda x: x.get(sort, ""), reverse=order == "desc")
            if q:
                data = [d for d in data if q in d["name"].lower() or q in str(d["score"])]
            self._json(data)

        elif path == "/ocr":
            # 将 OCR 请求转发给 Core 微服务
            image = qs.get("path", [""])[0]
            if not image:
                self._json({"error": "缺少 path 参数"}, 400)
                return
            if CORE_BASE is None:
                self._json({"error": "Core 服务未发现（.core_port 不存在）"}, 503)
                return

            try:
                body = json.dumps({"path": image}).encode()
                req = urllib.request.Request(
                    f"{CORE_BASE}/core/ocr",
                    data=body,
                    headers={"Content-Type": "application/json"},
                    method="POST",
                )
                resp = urllib.request.urlopen(req, timeout=10)
                result = json.loads(resp.read())
                self._json({"source": "core", "text": result.get("text")})
            except Exception as e:
                self._json({"error": f"Core OCR 调用失败: {e}"}, 502)

        else:
            self._json({"error": "not found"}, 404)


if __name__ == "__main__":
    # 绑定 0 → 平台自动分配端口
    server = HTTPServer(("127.0.0.1", 0), Handler)
    port = server.server_port
    print(f"PORT:{port}", flush=True)  # 平台通过此行发现端口
    sys.stderr.write(f"[super_app] http://127.0.0.1:{port}\n")
    if CORE_BASE:
        sys.stderr.write(f"[super_app] 已发现 Core 服务: {CORE_BASE}\n")
    else:
        sys.stderr.write(f"[super_app] 未发现 Core 服务（.core_port 不存在）\n")
    server.serve_forever()
