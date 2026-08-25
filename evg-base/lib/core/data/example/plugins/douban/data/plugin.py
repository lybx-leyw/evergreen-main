"""
豆瓣电影 Top250 抓取插件 —— 模型 A（CLI 一次性脚本）示例。

==== 平台契约 ====
  平台执行: python plugin.py --type <typeArg> --project-root <projectRoot> --greenix-config <greenixConfigPath>
  工作目录: <plugin>/data/
  stdout : 单个 JSON 对象（UTF-8），顶层必须是 Map —— 列表型数据包 {"items": [...]}
  失败   : 非零退出码，或 stdout JSON 含 "error" 字段（平台保留旧缓存）

==== 网络库选择 ====
  仅用 Python 标准库（urllib + html.parser），零第三方依赖：
  - 跨平台一致（桌面解释器 / 安卓 Chaquopy 均可直接运行，无需 PyInstaller 打包 .exe）
  - 同步中心导出/导入友好：迁移单元只有 manifest.json + 本脚本，无平台二进制
  - 豆瓣 Top250 抓取无需 requests 的会话/代理能力，urllib 足够

==== 独立测试 ====
  python plugin.py --type douban_top250 --project-root . --greenix-config .greenix/config.json
  # stdout 应输出 {"items": [...]}（或 {"error": "..."}）
"""

import argparse
import json
import ssl
import sys
from html.parser import HTMLParser
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


def main():
    """模型 A 入口：解析平台参数 → 抓取 → stdout 输出顶层 Map JSON。

    失败约定（任一即视为拉取失败，平台保留旧缓存）：
      - 非零退出码
      - stdout JSON 含 "error" 字段
    """
    parser = argparse.ArgumentParser(description="豆瓣电影 Top250 数据源（模型 A CLI）")
    parser.add_argument("--type", default="douban_top250",
                        help="平台 dataType 的 typeArg（当前固定抓取 douban_top250）")
    parser.add_argument("--project-root", default=".",
                        help="平台项目根目录（本示例未使用，按契约接收）")
    parser.add_argument("--greenix-config", default=None,
                        help=".greenix/config.json 路径（本示例无凭证需求，按契约接收）")
    args = parser.parse_args()

    items = fetch_douban()
    if not items:
        # 空数据视为失败（平台空数据门控也不覆写缓存），显式 error 便于排查
        print(json.dumps(
            {"error": "豆瓣 Top250 抓取失败（网络不可达或页面结构变化），请查看 stderr"},
            ensure_ascii=False))
        sys.exit(1)

    # 平台统一契约：stdout 顶层必须是 Map（列表型包 {"items": [...]}）
    print(json.dumps({"items": items}, ensure_ascii=False))


if __name__ == "__main__":
    main()
