#!/usr/bin/env python3
"""Paper Vision V3 — 极简文本管线：OCR → 分章节 → 分段落+过渡语 → 段落翻译。

不依赖：DocLayout-YOLO, pymupdf 坐标, 图片裁切, pdf2zh.
只用：DeepSeek-OCR + DeepSeek LLM.
"""

import sys, json, os, base64, re
import requests
from pathlib import Path

THIS_DIR = Path(__file__).resolve().parent
if str(THIS_DIR) not in sys.path:
    sys.path.insert(0, str(THIS_DIR))

OCR_URL = 'https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions'


# ═══════════════ DeepSeek-OCR ═══════════════

def ocr_page(image_path: str, api_key: str) -> str:
    with open(image_path, 'rb') as f:
        img = base64.b64encode(f.read()).decode()
    r = requests.post(OCR_URL,
        headers={'Authorization': f'Bearer {api_key}', 'Content-Type': 'application/json'},
        json={'model': 'vanchin/deepseek-ocr', 'messages': [{'role': 'user', 'content': [
            {'type': 'image_url', 'image_url': {'url': f'data:image/png;base64,{img}'}},
            {'type': 'text', 'text': 'Read all text in this academic paper page. Preserve paragraph breaks.'},
        ]}]}, timeout=90)
    if r.status_code != 200:
        raise RuntimeError(f'OCR {r.status_code}')
    return r.json()['choices'][0]['message']['content'].strip()


def extract_text_pymupdf(pdf_path: str, on_progress=None) -> str:
    """pymupdf 原生文本提取——读 PDF 内嵌文本流，精度远超 OCR。"""
    import fitz
    doc = fitz.open(pdf_path)
    total = len(doc)
    parts = []
    for i in range(total):
        if on_progress: on_progress('extract', f'提取第{i+1}/{total}页', i+1, total)
        parts.append(doc[i].get_text())
    doc.close()
    return '\n\n'.join(parts)


# ═══════════════ LLM 分章节+段落+过渡语 ═══════════════

_REFORMAT_PROMPT = """The following text was extracted from a PDF. The formatting is broken — line breaks, paragraph breaks, and section headings may be wrong.

Your task: reconstruct the correct academic paper structure.
1. Merge broken lines back into proper paragraphs.
2. Detect section headings (numbered like "1.", "2.", or named like "Introduction", "Method", etc.).
3. Restore paragraph breaks between different topics.
4. Keep ALL original text — do not summarize or omit anything.

Output ONLY the reformatted plain text — no JSON, no markdown, no explanations.

Raw text:
{text}"""

_SPLIT_PROMPT = """You MUST split this academic paper into its logical sections.

FOR EACH SECTION:
1. Give it a title (e.g. "1. Introduction")
2. Split its content into individual paragraphs
3. Write a one-sentence Chinese study guide for each paragraph

Return ONLY a JSON array:
[{{"title":"1. Introduction","paragraphs":[{{"guide":"Chinese guide","content":"English text"}}]}}]

Paper text:
{text}"""


def reformat_text(text: str, api_key: str, model: str = 'deepseek-v4-flash') -> str:
    """LLM 重排：恢复 PDF 提取后丢失的段落和章节格式。"""
    from openai import OpenAI
    client = OpenAI(api_key=api_key, base_url='https://api.deepseek.com/v1')
    cap = min(len(text), 14000)
    response = client.chat.completions.create(
        model=model, max_tokens=8192, temperature=0.3,
        messages=[{'role': 'user', 'content': _REFORMAT_PROMPT.format(text=text[:cap])}],
    )
    return response.choices[0].message.content or text[:cap]


def split_into_chapters(text: str, api_key: str, model: str = 'deepseek-v4-flash') -> list[dict]:
    from openai import OpenAI
    client = OpenAI(api_key=api_key, base_url='https://api.deepseek.com/v1')
    cap = min(len(text), 14000)
    response = client.chat.completions.create(
        model=model, max_tokens=8192, temperature=0.3,
        messages=[{'role': 'user', 'content': _SPLIT_PROMPT.format(text=text[:cap])}],
    )
    content = response.choices[0].message.content or '[]'
    # 去掉 markdown 代码块标记
    content = re.sub(r'```(?:json)?\s*', '', content)
    content = re.sub(r'```\s*$', '', content)
    # 提取第一个完整 JSON 数组
    m = re.search(r'\[.*\]', content, re.DOTALL)
    if m:
        try: return json.loads(m.group(0))
        except json.JSONDecodeError: pass
    # fallback: 按双换行拆段落，再按自然中断分节
    raw_paras = [p.strip() for p in text.split('\n\n') if len(p.strip()) > 30]
    chunk_size = max(1, len(raw_paras) // 4)  # 约4节
    sections = []
    for i in range(0, len(raw_paras), chunk_size):
        batch = raw_paras[i:i+chunk_size]
        sections.append({
            'title': f'Section {len(sections)+1}',
            'paragraphs': [{'guide': '段落', 'content': p} for p in batch],
        })
    return sections if sections else [{'title': '全文', 'paragraphs': [{'guide': '全文', 'content': text[:2000]}]}]


# ═══════════════ 翻译 (deepseek-v4-flash) ═══════════════

# —— 自定义翻译 System Prompt（与 paper_reader.py 保持同步） ——
_TRANSLATE_SYSTEM_PROMPT = """你是一位学术论文翻译专家，擅长将英文学术段落翻译为优雅、通顺的中文。请严格遵循以下翻译规范：

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


def translate_paragraphs(paragraphs: list[str], api_key: str,
                         lang_out: str = 'zh', model: str = 'deepseek-v4-flash',
                         on_progress=None) -> list[str]:
    from openai import OpenAI
    client = OpenAI(api_key=api_key, base_url='https://api.deepseek.com/v1')
    results = []
    for i, p in enumerate(paragraphs):
        if on_progress: on_progress(i+1, len(paragraphs))
        try:
            r = client.chat.completions.create(
                model=model, max_tokens=4096, temperature=0.3,
                messages=[
                    {'role': 'system', 'content': _TRANSLATE_SYSTEM_PROMPT},
                    {'role': 'user', 'content': f'请将以下英文学术段落翻译为中文：\n\n{p}'},
                ],
            )
            results.append(r.choices[0].message.content or '')
        except Exception as e:
            results.append(f'[翻译失败: {e}]')
    return results


# ═══════════════ 全流程 ═══════════════

def full_pipeline(pdf_path: str, work_dir: str, api_key: str,
                  model: str = 'deepseek-v4-flash',
                  on_progress=None) -> dict:
    # Step 1: pymupdf 原生文本提取（不依赖 OCR，精度远高于 DeepSeek-OCR）
    if on_progress: on_progress('extract', '提取文本', 0, 1)
    full_text = extract_text_pymupdf(pdf_path, on_progress)
    if on_progress: on_progress('extract', '提取完成', 1, 1)

    # Step 2: LLM 重排——恢复 PDF 提取后丢失的段落和格式
    if on_progress: on_progress('reformat', 'LLM 重排版面', 0, 1)
    full_text = reformat_text(full_text, api_key, model)
    if on_progress: on_progress('reformat', '重排完成', 1, 1)

    # Step 3: 分章节+段落+过渡语
    if on_progress: on_progress('split', 'LLM 分章节段落+过渡语', 0, 1)
    chapters = split_into_chapters(full_text, api_key, model)
    if chapters and isinstance(chapters[0], list):
        chapters = chapters[0]
    total_paras = sum(len(c.get('paragraphs', [])) for c in chapters)
    if on_progress: on_progress('split', f'完成: {len(chapters)}章, {total_paras}段', 1, 1)

    # 翻译改为懒加载——不在管线中执行，用户浏览段落时才触发
    if on_progress: on_progress('done', f'{len(chapters)}章 · {total_paras}段 (翻译按需)', total_paras, total_paras)

    return {'chapters': chapters, 'full_text': full_text, 'total_paragraphs': total_paras}


# ═══════════════ CLI ═══════════════

def _write(data: dict):
    sys.stdout.write(json.dumps(data, ensure_ascii=False) + '\n')
    sys.stdout.flush()


def main():
    for line in sys.stdin:
        line = line.strip()
        if not line: continue
        try: msg = json.loads(line)
        except: continue
        cmd = msg.get('command', '')
        if cmd == 'exit': break
        args = msg.get('args', {})

        if cmd == 'full_pipeline':
            def prog(stage, msg_text, cur, tot):
                _write({'type': 'progress', 'stage': stage, 'message': msg_text, 'current': cur, 'total': tot})
            try:
                result = full_pipeline(args['input'], args['work_dir'], args['api_key'],
                                       model=args.get('model', 'deepseek-v4-flash'),
                                       on_progress=prog)
                _write({'type': 'result', 'data': result})
            except Exception as e:
                _write({'type': 'error', 'message': str(e)})

        elif cmd == 'translate_text':
            from openai import OpenAI
            client = OpenAI(api_key=args['api_key'], base_url='https://api.deepseek.com/v1')
            r = client.chat.completions.create(
                model=args.get('model', 'deepseek-v4-flash'), max_tokens=8192, temperature=0.3,
                messages=[
                    {'role': 'system', 'content': _TRANSLATE_SYSTEM_PROMPT},
                    {'role': 'user', 'content': f"请将以下英文学术段落翻译为中文：\n\n{args['text']}"},
                ],
            )
            _write({'type': 'result', 'data': {'translated': r.choices[0].message.content or ''}})
    sys.exit(0)


if __name__ == '__main__':
    main()
