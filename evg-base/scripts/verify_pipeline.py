#!/usr/bin/env python3
"""真实 OCR Key 验证：从 .greenix/config.json 加载，测试 paper_vision pipeline 返回格式。"""
import sys, os, json, traceback, time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from paper_vision import split_into_chapters, translate_paragraphs, full_pipeline

# 1. 加载配置
config_path = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '.greenix', 'config.json')
with open(config_path, 'r', encoding='utf-8') as f:
    cfg = json.load(f)

ocr_key = cfg.get('DEEPSEEK_OCR_API_KEY', '') or cfg.get('ocr_api_key', '')
llm_key = cfg.get('DEEPSEEK_API_KEY', '') or cfg.get('llm_api_key', '')
model = cfg.get('DEEPSEEK_MODEL', 'deepseek-v4-flash')

print(f'Config loaded: OCR key={len(ocr_key)} chars, LLM key={len(llm_key)} chars, model={model}')

if not ocr_key or not llm_key:
    print('FAIL: Missing API keys')
    sys.exit(1)

# 2. 创建测试 PDF（单页，包含章节结构文本）
import fitz
test_pdf = os.path.join(os.path.dirname(__file__), '_test_paper.pdf')
doc = fitz.open()
page = doc.new_page()
TEST_TEXT = """1. Introduction

Deep learning has revolutionized computer vision in recent years.
Convolutional neural networks have achieved state-of-the-art results
on many benchmark datasets including ImageNet and COCO.

However, current approaches still face significant challenges.
Domain shift remains a major obstacle to real-world deployment.

2. Method

We propose a novel architecture called Residual Attention Network.
Our method combines skip connections with channel-wise attention
mechanisms to improve feature representation.

The key insight is that different channels encode different
semantic information, which should be weighted differently.

3. Experiments

We evaluate on ImageNet, CIFAR-100, and fine-grained datasets.
Results show 2.3% improvement over ResNet-50 baseline.
Ablation studies confirm the effectiveness of attention modules.
"""
page.insert_text(fitz.Point(50, 50), TEST_TEXT, fontsize=11)
doc.save(test_pdf)
doc.close()
print(f'Test PDF created: {test_pdf}')

# 3. 测试 full_pipeline
work_dir = os.path.join(os.path.dirname(__file__), '_test_work')
os.makedirs(work_dir, exist_ok=True)

start = time.time()
print('\n=== Running full_pipeline ===')

try:
    result = full_pipeline(test_pdf, work_dir, llm_key, model=model,
                           on_progress=lambda s, m, c, t: print(f'  [{s}] {m} ({c}/{t})'))

    elapsed = time.time() - start
    chapters = result.get('chapters', [])
    total_paras = result.get('total_paragraphs', 0)
    full_text_len = len(result.get('full_text', ''))

    print(f'\n=== Results ({elapsed:.1f}s) ===')
    print(f'Full text length: {full_text_len}')
    print(f'Chapters: {len(chapters)}')
    print(f'Total paragraphs: {total_paras}')

    # 4. 验证返回格式
    errors = []
    if not isinstance(chapters, list):
        errors.append('chapters is not a list')
    if total_paras == 0:
        errors.append('total_paragraphs is 0')

    for i, ch in enumerate(chapters):
        if not isinstance(ch, dict):
            errors.append(f'chapter[{i}] is not dict')
            continue
        if 'title' not in ch:
            errors.append(f'chapter[{i}] missing title')
        if 'paragraphs' not in ch:
            errors.append(f'chapter[{i}] missing paragraphs')
            continue
        for j, p in enumerate(ch.get('paragraphs', [])):
            if 'guide' not in p:
                errors.append(f'chapter[{i}].paragraphs[{j}] missing guide')
            if 'content' not in p:
                errors.append(f'chapter[{i}].paragraphs[{j}] missing content')
            # translated is lazy-filled on demand — skip check

    if errors:
        print(f'\nFAIL: {len(errors)} format errors:')
        for e in errors:
            print(f'  - {e}')
    else:
        print('\nPASS: All format checks passed.')

    # 5. 打印一个示例段落
    if chapters:
        ch = chapters[0]
        title = ch.get('title', '?')
        print('\n--- Sample: ' + str(title) + ' ---')
        for p in ch.get('paragraphs', [])[:2]:
            g = (p.get('guide', '') or '')[:80]
            c = (p.get('content', '') or '')[:100]
            t = (p.get('translated', '') or '')[:100]
            print('  Guide: ' + g)
            print('  Content: ' + c)
            print('  Translated: ' + t)
            print()

except Exception as e:
    print(f'\nFAIL: Exception: {e}')
    traceback.print_exc()
    sys.exit(1)
