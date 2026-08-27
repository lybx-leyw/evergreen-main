#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""vision — 多模态视觉 Agent 工具插件（Task R3-5）。

stdin JSON 参数：{"mode": "ocr|describe|generate", "file_path": "..."}

模式：
- ocr      ：提取图片 / PDF / PPT 中的文字（OCR_API_* 配置，OpenAI 兼容 chat/completions）
- describe ：详细描述图片内容（VISION_API_* 配置）
- generate ：生图（占位，即将上线——不调 API、不进设置）

API 配置从平台设置读取（.greenix/config.json 镜像机制，GREENIX_CONFIG_PATH
环境变量桌面/安卓已注入；三级降级：config.json → CWD/PROJECT_ROOT 搜索 → 环境变量）：
  OCR_API_BASE_URL / OCR_API_KEY / OCR_API_MODEL
  VISION_API_BASE_URL / VISION_API_KEY / VISION_API_MODEL

输出约定：stdout 纯文本（Agent 工具可解析）；错误统一 `[error: vision: ...]`
前缀，不崩溃。PDF 经 pymupdf(fitz) 渲染；PPT/PPTX 经 zipfile 纯标准库解包
内嵌图片（不引 python-pptx）；多页并发调 API（max_workers=4，429 退避，
单页失败不阻塞整篇，汇总标注页码）。

请求库：优先使用已打包的 requests（嵌入式 Python / 安卓 Chaquopy 均内置），
缺失时回退标准库 urllib——零新增依赖。
"""
import base64
import concurrent.futures
import json
import mimetypes
import os
import sys
import time
import urllib.error
import urllib.request
import zipfile
from pathlib import Path

# ═══════ 配置读取（三级降级，对齐 evg_lib.config） ═══════


def _get_config(key):
    """读取平台设置。

    策略1：GREENIX_CONFIG_PATH 指向的 `.greenix/config.json`（Key 镜像机制，
    桌面/安卓已注入该环境变量）。
    策略2：CWD / PROJECT_ROOT 下的 `.greenix/config.json`（桌面安装场景兜底）。
    策略3：系统环境变量。
    """
    gp = os.environ.get('GREENIX_CONFIG_PATH')
    if gp:
        try:
            p = Path(gp)
            if p.is_file():
                cfg = json.loads(p.read_text(encoding='utf-8'))
                val = cfg.get(key, '')
                if val:
                    return val
        except Exception:
            pass
    for base in (Path.cwd(), Path(os.environ.get('PROJECT_ROOT', '.'))):
        try:
            p = base / '.greenix' / 'config.json'
            if p.is_file():
                cfg = json.loads(p.read_text(encoding='utf-8'))
                val = cfg.get(key, '')
                if val:
                    return val
        except Exception:
            pass
    return os.environ.get(key, '')


# ═══════ HTTP（requests 优先，stdlib urllib 兜底） ═══════

try:
    import requests as _requests
except ImportError:
    _requests = None


def _post_json(url, headers, payload, timeout=120):
    """POST JSON，返回解析后的响应 dict；非 2xx 抛 HTTPError。"""
    if _requests is not None:
        resp = _requests.post(url, headers=headers, json=payload, timeout=timeout)
        if resp.status_code != 200:
            raise urllib.error.HTTPError(
                url, resp.status_code, resp.text[:300], {}, None)
        return resp.json()
    req = urllib.request.Request(
        url,
        data=json.dumps(payload).encode('utf-8'),
        headers=headers,
    )
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        return json.loads(resp.read().decode('utf-8'))


def _chat_completions(base_url, api_key, model, image_b64, mime, prompt, timeout=120):
    """OpenAI 兼容 chat/completions 单图调用。"""
    url = base_url.rstrip('/') + '/chat/completions'
    payload = {
        'model': model,
        'messages': [
            {
                'role': 'user',
                'content': [
                    {'type': 'image_url',
                     'image_url': {'url': f'data:{mime};base64,{image_b64}',
                                   'detail': 'high'}},
                    {'type': 'text', 'text': prompt},
                ],
            }
        ],
    }
    headers = {'Authorization': f'Bearer {api_key}',
               'Content-Type': 'application/json'}
    data = _post_json(url, headers, payload, timeout=timeout)
    try:
        return data['choices'][0]['message']['content'] or ''
    except (KeyError, IndexError, TypeError):
        raise RuntimeError(
            f'API 响应缺少 choices[0].message.content: {json.dumps(data)[:300]}')


def _call_with_retry(base_url, api_key, model, image_b64, mime, prompt, timeout=120):
    """429 退避重试（最多 3 次，1s/2s 间隔），其余异常直接抛。"""
    for attempt in range(3):
        try:
            return _chat_completions(base_url, api_key, model, image_b64, mime,
                                     prompt, timeout)
        except urllib.error.HTTPError as e:
            if e.code == 429 and attempt < 2:
                time.sleep(2 ** attempt)
                continue
            raise RuntimeError(f'API 错误 {e.code}: {e.reason}')
        except Exception:
            raise


# ═══════ 文件处理 ═══════

_PPT_MEDIA_EXTS = {'.png', '.jpg', '.jpeg', '.bmp', '.gif', '.webp', '.tiff'}


def _image_to_data(path):
    """单图 → (label, 图片字节)。"""
    mime = mimetypes.guess_type(path)[0] or 'image/png'
    return Path(path).name, Path(path).read_bytes(), mime


def _pdf_to_pages(path):
    """pymupdf(fitz) 逐页渲染 PNG 字节。返回 ([(label, bytes)], error)。"""
    try:
        import fitz
    except ImportError:
        return None, ('PDF 需要 pymupdf（fitz）：桌面嵌入式 Python 已含'
                      '（scripts/requirements.txt 声明）；安卓需在 '
                      'android/app/build.gradle.kts 的 chaquopy.pip 加装 '
                      'pymupdf（构建期打包，安卓 wheel 待真机验证）')
    try:
        pages = []
        doc = fitz.open(path)
        try:
            for page in doc:
                pix = page.get_pixmap(dpi=150)
                pages.append((page.number + 1, pix.tobytes('png')))
        finally:
            doc.close()
        return pages, None
    except Exception as e:
        return None, f'PDF 渲染失败: {e}'


def _pptx_to_pages(path):
    """zipfile 纯标准库解包 ppt/slides/media/* 内嵌图片。返回 ([(label, bytes)], error)。"""
    try:
        pages = []
        with zipfile.ZipFile(path) as zf:
            for name in zf.namelist():
                if name.startswith('ppt/slides/media/') and not name.endswith('/'):
                    ext = Path(name).suffix.lower()
                    if ext in _PPT_MEDIA_EXTS:
                        pages.append((name.rsplit('/', 1)[-1], zf.read(name)))
        return pages, None
    except Exception as e:
        return None, f'PPT 解析失败: {e}'


def _mime_for_label(label):
    return 'image/jpeg' if label.lower().endswith(('.jpg', '.jpeg')) else 'image/png'


def _run_pages(pages, cfg, prompt):
    """并发调 API（max_workers=4）。返回 ([(label, text)], [(label, err)])。"""
    texts, failures = [], []

    def work(item):
        label, data = item
        try:
            b64 = base64.b64encode(data).decode('ascii')
            text = _call_with_retry(cfg['base_url'], cfg['api_key'], cfg['model'],
                                    b64, _mime_for_label(str(label)), prompt)
            return label, (text or '').strip(), None
        except Exception as e:
            return label, None, str(e)

    with concurrent.futures.ThreadPoolExecutor(max_workers=4) as ex:
        for label, text, err in ex.map(work, pages):
            if err is not None:
                failures.append((label, err))
            elif text:
                texts.append((label, text))
    return texts, failures


def _compose_output(items, cfg, prompt, empty_msg):
    """多页/单图统一组装输出；items 为 [(label, bytes)]。"""
    if not items:
        return f'[error: vision: 文件中没有可识别的图片内容]'
    texts, failures = _run_pages(items, cfg, prompt)
    if not texts:
        base = f'[error: vision: {empty_msg}'
        if failures:
            base += '；' + _summarize_failures(failures)
        return base + ']'
    if len(items) == 1 and not failures:
        return texts[0][1]
    buf = []
    for label, text in texts:
        buf.append(f'--- {label} ---')
        buf.append(text)
        buf.append('')
    if failures:
        buf.append(f'[vision: {len(failures)} 项失败：{_summarize_failures(failures)}]')
    return '\n'.join(buf).strip()


def _summarize_failures(failures):
    return '；'.join(f'{l}: {e}' for l, e in failures)


# ═══════ 自检 / 用法 ═══════

_USAGE = """vision — 多模态视觉工具（OCR / 读图描述 / 生图占位）

用法（Agent 经 PluginBridge stdin JSON 调用，或命令行直接测试）：
  echo '{"mode":"ocr","file_path":"scan.png"}' | python3 vision.py
  python3 vision.py --help        # 本帮助
  python3 vision.py --self-check  # 环境自检（fitz/requests/API 配置）

模式：
  ocr      提取图片/PDF/PPT 中的文字（OCR_API_BASE_URL/OCR_API_KEY/OCR_API_MODEL）
  describe 详细描述图片内容（VISION_API_BASE_URL/VISION_API_KEY/VISION_API_MODEL）
  generate 生图（占位，即将上线）

输出：stdout 纯文本；错误统一 `[error: vision: ...]` 前缀，退出码 0。
"""


def _self_check():
    info = ['vision 自检:']
    try:
        import fitz
        info.append('  pymupdf(fitz): 可用')
    except ImportError:
        info.append('  pymupdf(fitz): 未安装（PDF 模式不可用——桌面 requirements.txt 已声明，'
                    '安卓需 chaquopy.pip 打包）')
    info.append('  requests: ' + ('可用' if _requests is not None
                                  else '未安装（使用 stdlib urllib 兜底）'))
    for k in ('OCR_API_BASE_URL', 'OCR_API_KEY', 'OCR_API_MODEL',
              'VISION_API_BASE_URL', 'VISION_API_KEY', 'VISION_API_MODEL'):
        info.append(f'  {k}: {"已配置" if _get_config(k) else "未配置"}')
    print('\n'.join(info))
    return 0


def main():
    if '--help' in sys.argv or '-h' in sys.argv:
        print(_USAGE)
        return 0
    if '--self-check' in sys.argv:
        return _self_check()

    raw = sys.stdin.read() if not sys.stdin.isatty() else '{}'
    try:
        args = json.loads(raw) if raw.strip() else {}
    except json.JSONDecodeError:
        print('[error: vision: stdin 不是合法 JSON]')
        return 0

    mode = str(args.get('mode') or 'ocr').strip().lower()
    path = str(args.get('file_path') or '').strip()

    if mode == 'generate':
        print('生图功能即将上线，敬请期待')
        return 0
    if mode not in ('ocr', 'describe'):
        print(f'[error: vision: 未知模式 "{mode}"，支持 ocr/describe/generate]')
        return 0
    if not path:
        print('[error: vision: file_path 必填。示例: {"mode":"ocr","file_path":"scan.png"}]')
        return 0
    if not Path(path).is_file():
        cand = Path.cwd() / path
        if cand.is_file():
            path = str(cand)
        else:
            print(f'[error: vision: 文件不存在: {path}]')
            return 0

    if mode == 'ocr':
        keys = ('OCR_API_BASE_URL', 'OCR_API_KEY', 'OCR_API_MODEL')
        prompt = '提取图片中所有文字，原样输出。'
        empty_msg = '未识别到任何文字'
    else:
        keys = ('VISION_API_BASE_URL', 'VISION_API_KEY', 'VISION_API_MODEL')
        prompt = '详细描述这张图片的内容。'
        empty_msg = '未能获取图片描述'

    base_url, api_key, model = (_get_config(k) for k in keys)
    missing = [k for k, v in zip(keys, (base_url, api_key, model)) if not v]
    if missing:
        api_name = 'OCR API' if mode == 'ocr' else 'Vision API'
        print(f'[error: vision: 请先在设置中配置 {api_name}'
              f'（base_url/api_key/model），缺失: {", ".join(missing)}]')
        return 0

    cfg = {'base_url': base_url, 'api_key': api_key, 'model': model}

    ext = Path(path).suffix.lower()
    if ext == '.pdf':
        pages, err = _pdf_to_pages(path)
        if err:
            print(f'[error: vision: {err}]')
            return 0
        print(_compose_output(pages or [], cfg, prompt, empty_msg))
    elif ext in ('.ppt', '.pptx'):
        pages, err = _pptx_to_pages(path)
        if err:
            print(f'[error: vision: {err}]')
            return 0
        print(_compose_output(pages or [], cfg, prompt, empty_msg))
    else:
        try:
            label, data, mime = _image_to_data(path)
        except Exception as e:
            print(f'[error: vision: 图片读取失败: {e}]')
            return 0
        print(_compose_output([(label, data)], cfg, prompt, empty_msg))
    return 0


if __name__ == '__main__':
    sys.exit(main())
