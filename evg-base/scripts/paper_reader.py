#!/usr/bin/env python3
"""Paper Reader CLI — PDF 文本提取 + 文本级翻译（复用 pdf2zh_next 翻译引擎）。

不修改 pdf_translate.py，独立运行。
通信协议：stdin 读 JSON 命令 → stdout 写 JSON 响应（JSON Lines）。

支持命令：
  {"command":"extract",  "args":{"input":"/path/to/file.pdf"}}
  {"command":"translate","args":{"text":"...","api_key":"sk-...","model":"deepseek-v4-flash","lang_out":"zh"}}
  {"command":"exit"}
"""

import sys
import json
import os

THIS_DIR = os.path.dirname(os.path.abspath(__file__))

# —— 确保 pdf2zh_next 在 sys.path 中 ——
if THIS_DIR not in sys.path:
    sys.path.insert(0, THIS_DIR)


# ═══════════════════════════════════════════════════
# pymupdf PDF 文本提取
# ═══════════════════════════════════════════════════

def _extract_pdf_text(file_path: str) -> dict:
    """使用 pymupdf (fitz) 提取 PDF 纯文本并按段落分割。"""
    import fitz  # pymupdf

    doc = fitz.open(file_path)
    full_text_parts = []
    for page in doc:
        text = page.get_text()
        if text:
            full_text_parts.append(text)
    doc.close()

    full_text = '\n'.join(full_text_parts)

    # 按空行拆分为段落，过滤空白段落
    raw = full_text.split('\n\n')
    segments = [s.strip() for s in raw if s.strip() and len(s.strip()) > 10]

    return {
        'full_text': full_text,
        'segments': segments,
        'page_count': len(full_text_parts),
    }


# ═══════════════════════════════════════════════════
# pdf2zh_next 文本级翻译 (不碰 PDF)
# ═══════════════════════════════════════════════════

# —— 自定义翻译 System Prompt（覆盖 pdf2zh_next 默认 prompt） ——
#    默认 prompt 要求 "output translation ONLY. NO explanations. NO notes."
#    导致译文无导语、无分段、公式堆积。此 prompt 完全替代之。
PAPER_TRANSLATION_SYSTEM_PROMPT = """你是一位学术论文翻译专家，擅长将英文学术段落翻译为优雅、通顺的中文。请严格遵循以下翻译规范：

1. **AI 导语**：在最开头添加一句简短的 AI 导语（以「🤖 AI 导语」开头），用一句话通俗概括该段的核心思想或关键贡献。

2. **段落重排**：
   - 逐句直译，随后将原文重新组织为逻辑清晰、节奏优雅的中文段落。
   - 根据语义适当分段，确保中文阅读流畅自然。
   - 对于推导链条较长的内容，按推导步骤分段。
   - 但必须确保覆盖原文的所有信息，包括公式、表格等。

3. **数学公式处理**：
   - 所有数学公式使用 LaTeX 语法：行内公式用 $...$，独立展示公式用 $$...$$。
   - 保持原文公式的完整性与准确性，不要遗漏任何符号。
   - 公式密集的段落中，每个关键公式单独成行展示。

4. **术语规范**：
   - 专业术语首次出现时保留英文原文并标注中文。
   - 保持机器学习领域术语的一致性和准确性。

5. **输出格式**：直接输出翻译结果，使用 Markdown 格式。不要输出"以下是翻译"、"翻译如下"等多余文字。

---
**示例**：

输入英文段落：
```
The core idea of IRM is to learn representations that elicit invariant predictors across environments. Formally, the IRM penalty is L = sum_e ||∇_{w|w=1.0} R_e(Φ·w)||^2, where R_e denotes the empirical risk in environment e, and Φ is the feature extractor. By penalizing the gradient norm, IRM discourages the predictor from relying on spurious correlations that vary across environments. This can be seen as a form of causal regularization.
```

期望的中文输出：

🤖 AI 导语：本段定义 IRM 的核心思想与惩罚项形式，指出其本质上是一种因果正则化。

不变风险最小化（Invariant Risk Minimization，IRM）的核心思想是学习一种表征，使得基于该表征的预测器在不同环境中都能给出不变的预测。

形式化地，IRM 惩罚项定义为：

$$L = \sum_e \big\| \nabla_{w|_{w=1.0}} \, \mathcal{R}_e(\Phi \cdot w) \big\|^2$$

其中 $\mathcal{R}_e$ 为环境 $e$ 中的经验风险（empirical risk），$\Phi$ 为特征提取器（feature extractor）。IRM 通过惩罚梯度范数，迫使预测器避免依赖不同环境间变化的虚假相关（spurious correlations）。这一做法可视为一种因果正则化（causal regularization）。

（注意：AI 导语是导读，不是翻译。翻译部分逐句直译后按语义重组为流畅中文段落。）"""


class PaperTranslator:
    """论文翻译器 — 继承 OpenAITranslator，覆盖 prompt 方法以注入学术排版规范。

    绕过 pdf2zh_next 的默认 prompt（"NO explanations. NO notes."），
    改为支持 AI 导语、段落重排、LaTeX 公式格式化的定制 prompt。
    """
    # 惰性导入，避免模块加载时的循环依赖或提前导入问题
    _OpenAITranslator = None

    def __new__(cls, settings, rate_limiter):
        if cls._OpenAITranslator is None:
            from pdf2zh_next.translator.translator_impl.openai import OpenAITranslator
            cls._OpenAITranslator = OpenAITranslator

        # 动态创建子类，覆盖 prompt 方法
        BaseCls = cls._OpenAITranslator

        class _PaperTranslatorImpl(BaseCls):
            name = "paper-translator"

            def prompt(self, text):
                return [
                    {
                        "role": "system",
                        "content": PAPER_TRANSLATION_SYSTEM_PROMPT,
                    },
                    {
                        "role": "user",
                        "content": f"请将以下英文学术段落翻译为中文：\n\n{text}",
                    },
                ]

        return _PaperTranslatorImpl(settings, rate_limiter)


def _build_translator(api_key: str, model: str = 'deepseek-v4-flash',
                      lang_in: str = 'en', lang_out: str = 'zh'):
    """创建论文翻译器（PaperTranslator），使用自定义学术排版 prompt。

    直接构造 SettingsModel → PaperTranslator，
    不经过 pdf_translate.py 的 PDF 翻译管线。"""
    from pdf2zh_next.settings import (
        BasicSettings, TranslationSettings, SettingsModel,
        OpenAISettings,
    )
    from pdf2zh_next.translator.rate_limiter.qps_rate_limiter import QPSRateLimiter

    basic = BasicSettings()
    translate = TranslationSettings(
        translate_engine='DeepSeek',
        lang_in=lang_in,
        lang_out=lang_out,
    )
    engine = OpenAISettings(
        openai_model=model,
        openai_api_key=api_key,
        openai_base_url='https://api.deepseek.com/v1',
    )
    settings = SettingsModel(
        basic_settings=basic,
        translation_settings=translate,
        translate_engine_settings=engine,
    )

    # 直接使用 OpenAISettings，validate 检查 api_key + model 等
    settings.validate_settings()

    rate_limiter = QPSRateLimiter(1)
    translator = PaperTranslator(settings, rate_limiter)
    return translator


def _translate_text(text: str, api_key: str, model: str = 'deepseek-v4-flash',
                    lang_in: str = 'en', lang_out: str = 'zh') -> dict:
    """翻译单段文本。"""
    translator = _build_translator(api_key, model, lang_in, lang_out)
    result = translator.translate(text)
    return {'translated': result}


# ═══════════════════════════════════════════════════
# 批量翻译（一批段落，复用翻译器实例提高效率）
# ═══════════════════════════════════════════════════

def _translate_batch(segments: list, api_key: str, model: str = 'deepseek-v4-flash',
                     lang_in: str = 'en', lang_out: str = 'zh') -> dict:
    """批量翻译多个段落，复用翻译器实例和缓存。"""
    translator = _build_translator(api_key, model, lang_in, lang_out)
    results = []
    for i, seg in enumerate(segments):
        try:
            translated = translator.translate(seg)
        except Exception as e:
            translated = f'[翻译失败] {e}'
        results.append({'index': i, 'original': seg, 'translated': translated})
    return {'translations': results}


# ═══════════════════════════════════════════════════
# 主循环 — JSON Lines 协议
# ═══════════════════════════════════════════════════

def main():
    handlers = {
        'extract': _handle_extract,
        'translate': _handle_translate,
        'translate_batch': _handle_translate_batch,
    }

    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        try:
            msg = json.loads(line)
        except json.JSONDecodeError as e:
            _write_error(f'Invalid JSON: {e}')
            continue

        cmd = msg.get('command', '')
        if cmd == 'exit':
            break

        if cmd in handlers:
            handlers[cmd](msg.get('args', {}))
        else:
            _write_error(f'Unknown command: {cmd}')

    sys.exit(0)


def _handle_extract(args: dict):
    file_path = args.get('input', '')
    if not file_path or not os.path.isfile(file_path):
        _write_error(f'File not found: {file_path}')
        return
    try:
        result = _extract_pdf_text(file_path)
        _write_result(result)
    except Exception as e:
        _write_error(f'Extract failed: {e}')


def _handle_translate(args: dict):
    text = args.get('text', '')
    api_key = args.get('api_key', '')
    model = args.get('model', 'deepseek-v4-flash')
    lang_in = args.get('lang_in', 'en')
    lang_out = args.get('lang_out', 'zh')

    if not text:
        _write_error('Missing required arg: text')
        return
    if not api_key:
        _write_error('Missing required arg: api_key')
        return

    try:
        result = _translate_text(text, api_key, model, lang_in, lang_out)
        _write_result(result)
    except Exception as e:
        _write_error(f'Translate failed: {e}')


def _handle_translate_batch(args: dict):
    segments = args.get('segments', [])
    api_key = args.get('api_key', '')
    model = args.get('model', 'deepseek-v4-flash')
    lang_in = args.get('lang_in', 'en')
    lang_out = args.get('lang_out', 'zh')

    if not segments:
        _write_error('Missing required arg: segments')
        return
    if not api_key:
        _write_error('Missing required arg: api_key')
        return

    try:
        result = _translate_batch(segments, api_key, model, lang_in, lang_out)
        _write_result(result)
    except Exception as e:
        _write_error(f'Translate batch failed: {e}')


def _write_result(data: dict):
    msg = json.dumps({'type': 'result', 'data': data}, ensure_ascii=False)
    sys.stdout.write(msg + '\n')
    sys.stdout.flush()


def _write_error(message: str):
    msg = json.dumps({'type': 'error', 'message': message}, ensure_ascii=False)
    sys.stdout.write(msg + '\n')
    sys.stdout.flush()


if __name__ == '__main__':
    main()
