"""notes 模块 manifest 校验（R3 可运行测试，无需网络）。"""
import json, os, sys
_HERE = os.path.dirname(os.path.abspath(__file__))
_ROOT = os.path.abspath(os.path.join(_HERE, "..", "..", ".."))
_MANIFEST = os.path.join(_HERE, "..", "module", "manifest.json")

REQUIRED = ["schemaVersion", "type", "id", "route", "pages"]
SUPPORTED = {"ai-assistant","chat","form","settings","data-dashboard","code-editor",
    "data-table","card-list","chart","stat-tile","kanban","tree","timeline","map",
    "doc-viewer","doc-editor","document","video-player","video","audio-player",
    "image-gallery","presentation","nav-button","button","timetable","markdown",
    "spreadsheet","notepad","whiteboard","mindmap","diff-viewer","terminal",
    "type-check","flashcards","quiz","crossword","pronunciation","custom",
    "webview","divider","lottery-wheel","calendar"}

def test_manifest_structure():
    assert os.path.isfile(_MANIFEST), "manifest.json 缺失"
    with open(_MANIFEST, encoding="utf-8") as f:
        m = json.load(f)
    for k in REQUIRED:
        assert k in m, f"manifest 缺少字段 {k}"
    assert m["type"] == "module"
    assert isinstance(m["pages"], list) and m["pages"]
    for p in m["pages"]:
        slots = p.get("layout", {}).get("slots", {})
        assert slots, f"页面 {p.get('id')} 无 slots"
        for sk, sv in slots.items():
            comp = sv.get("component") if isinstance(sv, dict) else sv
            if isinstance(comp, dict):
                t = comp.get("type")
            else:
                t = comp
            assert t in SUPPORTED, f"slot {sk} 类型不支持: {t}"

if __name__ == "__main__":
    test_manifest_structure()
    print("[PASS] notes manifest 结构合法")
