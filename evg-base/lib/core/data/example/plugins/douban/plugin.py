"""
豆瓣电影 Top250 抓取插件 —— 真实爬虫示例。

==== 构建方法 ====
  pip install pyinstaller
  pyinstaller --onefile plugin.py
  cp dist/plugin.exe .
"""

import json
import ssl
import sys
from html.parser import HTMLParser
from http.server import HTTPServer, BaseHTTPRequestHandler
from urllib.request import Request, urlopen

DOUBAN_URL = "https://movie.douban.com/top250"
_HEADERS = {
    "User-Agent": (
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
        "AppleWebKit/537.36 (KHTML, like Gecko) "
        "Chrome/120.0.0.0 Safari/537.36"
    ),
}


class _DoubanParser(HTMLParser):
    """解析豆瓣 Top250 页面：排名、片名、评分、短评。"""

    def __init__(self):
        super().__init__()
        self.items = []
        self._depth = 0          # item 内 div 嵌套深度
        self._in_title = False   # <span class="title">
        self._in_rating = False  # <span class="rating_num">
        self._in_quote = False   # <p class="quote"> 内 <span>
        self._current = {}

    def handle_starttag(self, tag, attrs):
        a = dict(attrs)
        cls = a.get("class", "")

        # 追踪 item 嵌套深度（所有 div 都计数，不只是 item）
        if tag == "div":
            if cls == "item" and self._depth == 0:
                self._current = {}
            if self._depth > 0 or cls == "item":
                self._depth += 1
                return

        if self._depth == 0:
            return

        # 排名：<em>
        if tag == "em":
            self._expect_text = True

        # 片名：<span class="title">（取第一个 = 中文名）
        if tag == "span" and cls == "title" and "title" not in self._current:
            self._in_title = True

        # 评分：<span class="rating_num">
        if tag == "span" and cls == "rating_num":
            self._in_rating = True

        # 短评：<p class="quote"> → <span>
        if tag == "p" and cls == "quote":
            self._in_quote = True
        if self._in_quote and tag == "span":
            self._expect_text = True

    def handle_data(self, data):
        text = data.strip()
        if not text:
            return

        # 片名优先级最高
        if self._in_title:
            self._current["title"] = text
            self._in_title = False
        elif self._in_rating:
            try:
                self._current["rating"] = float(text)
            except ValueError:
                pass
            self._in_rating = False
        elif self._in_quote and "quote" not in self._current:
            self._current["quote"] = text
        elif getattr(self, "_expect_text", False) and text.isdigit():
            self._current["rank"] = int(text)
        self._expect_text = False

    def handle_endtag(self, tag):
        if tag == "div" and self._depth > 0:
            self._depth -= 1
            if self._depth == 0 and self._current:
                self.items.append(dict(self._current))
                self._current = {}
        if tag == "p" and self._in_quote:
            self._in_quote = False
        self._expect_text = False


def fetch_douban():
    """爬取豆瓣 Top250 首页。失败返回空列表。"""
    try:
        ctx = ssl._create_unverified_context()
        req = Request(DOUBAN_URL, headers=_HEADERS)
        with urlopen(req, timeout=15, context=ctx) as resp:
            html = resp.read().decode("utf-8")
        parser = _DoubanParser()
        parser.feed(html)
        print(f"爬取成功: {len(parser.items)} 条", file=sys.stderr, flush=True)
        return parser.items
    except Exception as e:
        print(f"ERROR: {e}", file=sys.stderr, flush=True)
        return []


class Handler(BaseHTTPRequestHandler):
    def log_message(self, format, *args):
        pass

    def do_GET(self):
        if self.path == "/health":
            self.send_response(200)
            self.end_headers()
        elif self.path == "/api/top250":
            try:
                items = fetch_douban()
                body = json.dumps(items, ensure_ascii=False).encode("utf-8")
                self.send_response(200)
                self.send_header("Content-Type", "application/json; charset=utf-8")
                self.end_headers()
                self.wfile.write(body)
            except Exception as e:
                self.send_response(500)
                self.end_headers()
        else:
            self.send_response(404)
            self.end_headers()


if __name__ == "__main__":
    server = HTTPServer(("127.0.0.1", 0), Handler)
    print(f"PORT:{server.server_port}", flush=True)
    server.serve_forever()
