"""translate_data.exe — PDF/文本翻译（DeepSeek API，真实调用）。

复刻参考：`.reference/.../scripts/pdf_translate.py`（DeepSeek 翻译 PDF）
复刻目标：`.refer_ui/.../features/translate/`（PDF 翻译进度）
实现（R6 换法复刻）：原参考用 DeepSeek 翻译 PDF。此处暴露真实文本翻译端点，
供插件 form 调用；R10 用 `--type translate_text --text` 真实调用 DeepSeek 验证。
PDF 整文件翻译（pdf2zh_next 重依赖）在运行时由用户触发，此处不打包重型依赖。
"""
import argparse
import json
import os
import sys
import urllib.request
import urllib.error

_PROJECT_ROOT = ""


def _get_config(key):
    p = os.path.join(_PROJECT_ROOT, ".config_port")
    if os.path.isfile(p):
        try:
            with open(p) as f:
                port = f.read().strip()
            req = urllib.request.Request(f"http://127.0.0.1:{port}/config/settings/{key}")
            with urllib.request.urlopen(req, timeout=5) as resp:
                data = json.loads(resp.read().decode("utf-8"))
                return data.get("value") if isinstance(data, dict) else None
        except Exception:
            return None
    return os.environ.get(key)


def translate_text(text, lang_out="zh", api_key=None):
    api_key = api_key or _get_config("DeepSeekAPI")
    if not api_key:
        return {"translated": "", "ok": False,
                "note": "未配置 DeepSeekAPI，请在设置中粘贴 DeepSeek API Key"}
    if not text or not text.strip():
        return {"translated": "", "ok": True, "note": "空文本"}
    payload = json.dumps({
        "model": "deepseek-chat",
        "messages": [
            {"role": "system", "content": f"你是一个翻译助手，把用户内容翻译为{lang_out}，只输出译文。"},
            {"role": "user", "content": text},
        ],
        "temperature": 0.3,
    }).encode("utf-8")
    req = urllib.request.Request(
        "https://api.deepseek.com/v1/chat/completions", data=payload)
    req.add_header("Content-Type", "application/json")
    req.add_header("Authorization", f"Bearer {api_key}")
    try:
        with urllib.request.urlopen(req, timeout=60) as resp:
            data = json.loads(resp.read().decode("utf-8"))
        out = data["choices"][0]["message"]["content"].strip()
        return {"translated": out, "ok": True}
    except urllib.error.HTTPError as e:
        return {"translated": "", "ok": False, "note": f"DeepSeek HTTP {e.code}"}
    except Exception as e:
        return {"translated": "", "ok": False, "note": f"翻译失败: {e}"}


HANDLERS = {"translate_text": lambda: translate_text(os.environ.get("TEXT", ""))}


if __name__ == "__main__":
    p = argparse.ArgumentParser()
    p.add_argument("--type", required=True)
    p.add_argument("--text", default=os.environ.get("TEXT", ""))
    p.add_argument("--lang-out", default="zh")
    p.add_argument("--project-root", default=os.getcwd())
    args = p.parse_args()
    _PROJECT_ROOT = os.path.abspath(args.project_root)
    h = HANDLERS.get(args.type)
    if not h:
        print(json.dumps({"error": f"unknown type: {args.type}"}, ensure_ascii=False))
        sys.exit(1)
    try:
        if args.type == "translate_text":
            result = translate_text(args.text, args.lang_out)
        else:
            result = h()
        print(json.dumps(result, ensure_ascii=False))
    except Exception as e:
        sys.stderr.write(f"[translate] {args.type}: {e}\n")
        print(json.dumps({"error": str(e)}, ensure_ascii=False))
        sys.exit(1)
