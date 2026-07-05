"""示例插件后端——演示 .exe 协议的最小实现。

启动后向 stdout 输出 PORT:<N>，提供 /health 端点。
实现了 manifest 中声明的所有交互端点。
"""
import json
import sys
import urllib.parse
from http.server import HTTPServer, BaseHTTPRequestHandler

PORT = 8080


class Handler(BaseHTTPRequestHandler):
    # ── 内存数据 ──
    _items = [
        {"id": "1", "name": "张三", "score": 95},
        {"id": "2", "name": "李四", "score": 87},
        {"id": "3", "name": "王五", "score": 92},
    ]
    _news = [
        {"id": "1", "title": "期末考试安排已发布", "date": "2026-07-01"},
        {"id": "2", "title": "图书馆暑假开放时间调整", "date": "2026-06-28"},
    ]
    _next_id = 4

    def _json(self, data, code=200):
        body = json.dumps(data, ensure_ascii=False).encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Access-Control-Allow-Origin", "*")
        self.end_headers()
        self.wfile.write(body)

    def _read_body(self):
        length = int(self.headers.get("Content-Length", 0))
        if length == 0:
            return {}
        return json.loads(self.rfile.read(length))

    def _parse_qs(self):
        parsed = urllib.parse.urlparse(self.path)
        return urllib.parse.parse_qs(parsed.query), parsed.path

    def log_message(self, *args):
        """重定向到 stderr，避免污染 stdout（PORT: 行之后只用 stderr）"""
        sys.stderr.write(f"[plugin] {args[0]}\n")

    # ── 路由 ──

    def do_GET(self):
        qs, path = self._parse_qs()

        if path == "/health":
            self._json({"status": "ok"})

        elif path == "/data":
            sort_by = qs.get("sort", [None])[0]
            order = qs.get("order", ["asc"])[0]
            data = sorted(self._items, key=lambda x: x.get(sort_by, "") if sort_by else 0,
                          reverse=(order == "desc"))
            self._json(data)

        elif path == "/search":
            q = qs.get("q", [""])[0].lower()
            results = [i for i in self._items if q in i["name"].lower() or q in str(i.get("score", ""))]
            self._json(results)

        elif path.startswith("/items/") or path == "/items":
            item_id = path.split("/")[-1] if path != "/items" else None
            if item_id and item_id.isdigit():
                item = next((i for i in self._items if i["id"] == item_id), None)
                if item:
                    self._json(item)
                else:
                    self._json({"error": "not found"}, 404)
            else:
                self._json(self._items)

        elif path == "/export":
            fmt = qs.get("format", ["json"])[0]
            if fmt == "csv":
                csv = "id,name,score\n" + "\n".join(f'{i["id"]},{i["name"]},{i["score"]}' for i in self._items)
                self.send_response(200)
                self.send_header("Content-Type", "text/csv; charset=utf-8")
                self.end_headers()
                self.wfile.write(csv.encode("utf-8"))
            else:
                self._json(self._items)

        else:
            self._json({"error": "not found"}, 404)

    def do_POST(self):
        qs, path = self._parse_qs()
        body = self._read_body()

        if path == "/items":
            item = {"id": str(self._next_id), **body}
            self._next_id += 1
            self._items.append(item)
            self._json(item, 201)

        else:
            self._json({"error": "not found"}, 404)

    def do_PUT(self):
        _, path = self._parse_qs()
        body = self._read_body()

        if path.startswith("/items/"):
            item_id = path.split("/")[-1]
            item = next((i for i in self._items if i["id"] == item_id), None)
            if item:
                item.update(body)
                self._json(item)
            else:
                self._json({"error": "not found"}, 404)
        else:
            self._json({"error": "not found"}, 404)

    def do_DELETE(self):
        _, path = self._parse_qs()

        if path == "/items/batch":
            body = self._read_body()
            ids = set(body.get("ids", []))
            self._items = [i for i in self._items if i["id"] not in ids]
            self._json({"deleted": len(ids)})

        elif path.startswith("/items/"):
            item_id = path.split("/")[-1]
            before = len(self._items)
            self._items = [i for i in self._items if i["id"] != item_id]
            if len(self._items) < before:
                self._json({"deleted": item_id})
            else:
                self._json({"error": "not found"}, 404)
        else:
            self._json({"error": "not found"}, 404)

    def do_OPTIONS(self):
        self.send_response(200)
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "GET,POST,PUT,DELETE,OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type")
        self.end_headers()


if __name__ == "__main__":
    # 第一步：向 stdout 输出端口号
    print(f"PORT:{PORT}", flush=True)
    # 之后全部用 stderr
    sys.stderr.write(f"[plugin] 启动在 http://localhost:{PORT}\n")
    sys.stderr.flush()

    server = HTTPServer(("127.0.0.1", PORT), Handler)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        server.shutdown()
