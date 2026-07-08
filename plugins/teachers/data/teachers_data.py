"""teachers_data.exe — 查老师（本地评分数据集搜索，无网络依赖）。

复刻参考：`.reference/.../features/teachers`（search_teacher 工具）
复刻目标：`.refer_ui/.../features/teachers/`（教师评分列表）
实现（R6 换法复刻）：chalaoshi.top 评分数据集已本地化（teacher_ratings.json，
含 10104 位教师 + 学院映射），无需实时访问外部站点，毫秒级本地搜索。
支持按姓名 / 拼音 / 拼音缩写搜索，返回评分 + 学院 + 热度。
"""
import argparse
import json
import os
import sys


def _resource_path(rel):
    """兼容开发态(__file__)与 PyInstaller 打包态(sys._MEIPASS)。"""
    base = getattr(sys, "_MEIPASS", os.path.dirname(os.path.abspath(__file__)))
    return os.path.join(base, rel)


_DATA_FILE = _resource_path("teacher_ratings.json")


def _load():
    with open(_DATA_FILE, encoding="utf-8") as f:
        return json.load(f)


def search(query, limit=50):
    """按姓名/拼音(py)/缩写(sx)模糊搜索教师。无 query 时返回热度榜（默认展示）。"""
    q = (query or "").strip().lower()
    data = _load()
    colleges = {c["id"]: c["name"] for c in data.get("colleges", [])}
    teachers = data.get("teachers", [])
    if not q:
        # 默认展示：按热度取前 limit 位（真实数据，非空态）
        top = sorted(teachers, key=lambda t: t.get("hot", 0), reverse=True)[:limit]
        return [{
            "id": t.get("id"),
            "name": t.get("name"),
            "college": colleges.get(t.get("xy"), ""),
            "rate": t.get("rate", ""),
            "hot": t.get("hot", 0),
            "py": t.get("py", ""),
        } for t in top]

    data = _load()
    colleges = {c["id"]: c["name"] for c in data.get("colleges", [])}
    teachers = data.get("teachers", [])
    scored = []
    for t in teachers:
        name = t.get("name", "") or ""
        py = (t.get("py") or "").lower()
        sx = (t.get("sx") or "").lower()
        if q == name or q == py or q == sx:
            match = 2  # 精确
        elif q in name or q in py or q in sx:
            match = 1  # 包含
        else:
            continue
        scored.append((match, t))
    # 精确优先，其次按热度
    scored.sort(key=lambda x: (x[0], x[1].get("hot", 0)), reverse=True)
    out = []
    for _, t in scored[:limit]:
        out.append({
            "id": t.get("id"),
            "name": t.get("name"),
            "college": colleges.get(t.get("xy"), ""),
            "rate": t.get("rate", ""),
            "hot": t.get("hot", 0),
            "py": t.get("py", ""),
        })
    return out


HANDLERS = {"teachers": lambda: search(os.environ.get("QUERY", ""))}


if __name__ == "__main__":
    p = argparse.ArgumentParser()
    p.add_argument("--type", required=True)
    p.add_argument("--query", default=os.environ.get("QUERY", ""))
    p.add_argument("--project-root", default=os.getcwd())
    args = p.parse_args()

    h = HANDLERS.get(args.type)
    if not h:
        print(json.dumps({"error": f"unknown type: {args.type}"}, ensure_ascii=False))
        sys.exit(1)
    try:
        # teachers 处理时把 --query 注入环境，复用于搜索
        if args.query:
            os.environ["QUERY"] = args.query
        result = h() if args.type != "teachers" else search(args.query)
        print(json.dumps({"teachers": result, "total": len(result)}, ensure_ascii=False))
    except Exception as e:
        sys.stderr.write(f"[teachers] {args.type}: {e}\n")
        print(json.dumps({"error": str(e)}, ensure_ascii=False))
        sys.exit(1)
