"""showcase_export.exe — 动作级后端，模拟数据导出功能。"""
import argparse
import json
import os
import sys
import random
from http.server import HTTPServer, BaseHTTPRequestHandler
from datetime import datetime

_PROJECT_ROOT = ""

EXPORT_FORMATS = ["json", "csv", "md", "html", "pdf", "xlsx"]


class Handler(BaseHTTPRequestHandler):
    def _json(self, data, code=200):
        body = json.dumps(data, ensure_ascii=False).encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Access-Control-Allow-Origin", "*")
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, fmt, *args):
        sys.stderr.write(f"[showcase_export] {fmt % args}\n")

    def do_GET(self):
        if self.path == "/health":
            return self._json({
                "status": "ok",
                "module": "showcase_export",
                "formats": EXPORT_FORMATS,
            })
        return self._json({"error": "not found"}, 404)

    def do_POST(self):
        path = self.path.split("?")[0]
        cl = self.headers.get("Content-Length")
        raw = self.rfile.read(int(cl)) if cl else b""
        body = json.loads(raw) if raw and raw.strip() else {}

        if path == "/export":
            fmt = body.get("format", "json")
            if fmt not in EXPORT_FORMATS:
                return self._json({"error": f"不支持的格式: {fmt}，支持: {EXPORT_FORMATS}"}, 400)

            filename = f"showcase_export_{datetime.now().strftime('%Y%m%d_%H%M%S')}.{fmt}"

            # 模拟导出数据
            export_data = {
                "exported_at": datetime.now().isoformat(),
                "format": fmt,
                "filename": filename,
                "records": random.randint(10, 500),
                "size_kb": random.randint(1, 500),
                "message": f"✅ 成功导出 {filename} ({random.randint(10,500)} 条记录)",
            }
            return self._json(export_data)

        if path == "/export-formats":
            return self._json({
                "formats": [
                    {"id": "json", "name": "JSON", "icon": "code", "description": "结构化数据"},
                    {"id": "csv", "name": "CSV", "icon": "table_chart", "description": "表格数据"},
                    {"id": "md", "name": "Markdown", "icon": "article", "description": "文档格式"},
                    {"id": "html", "name": "HTML", "icon": "web", "description": "网页格式"},
                    {"id": "pdf", "name": "PDF", "icon": "picture_as_pdf", "description": "便携文档"},
                    {"id": "xlsx", "name": "Excel", "icon": "grid_on", "description": "电子表格"},
                ]
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
    sys.stderr.write(f"[showcase_export] http://127.0.0.1:{port}\n")
    server.serve_forever()
