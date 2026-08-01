#!/usr/bin/env python3
"""paper_vision.py 全覆盖测试 —— 不依赖 API Key / PDF / 网络。"""

import sys, os, json, unittest, io, builtins
from unittest.mock import patch, MagicMock
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from paper_vision import (
    ocr_page, split_into_chapters, translate_paragraphs,
    full_pipeline, _TRANSLATE_PROMPT, _SPLIT_PROMPT, _write,
)

VALID_CHAPTERS = [
    {"title": "1. Introduction",
     "paragraphs": [{"guide": "开篇", "content": "Deep learning."},
                    {"guide": "承上启下", "content": "Challenges remain."}]},
    {"title": "2. Method",
     "paragraphs": [{"guide": "方法概述", "content": "We propose."}]},
]

def _mock_chat(content):
    m = MagicMock()
    m.choices = [MagicMock()]
    m.choices[0].message.content = content
    return m

class TestOcr(unittest.TestCase):
    @patch('paper_vision.requests.post')
    @patch.object(builtins, 'open')
    def test_ocr_ok(self, mock_open, mock_post):
        mock_post.return_value.status_code = 200
        mock_post.return_value.json.return_value = {'choices': [{'message': {'content': 'OK'}}]}
        mock_open.return_value.__enter__.return_value.read.return_value = b'fake'
        r = ocr_page('/f.png', 'sk')
        self.assertEqual(r, 'OK')

    @patch('paper_vision.requests.post')
    @patch.object(builtins, 'open')
    def test_ocr_400(self, mock_open, mock_post):
        mock_post.return_value.status_code = 400
        mock_open.return_value.__enter__.return_value.read.return_value = b'fake'
        with self.assertRaises(RuntimeError):
            ocr_page('/f.png', 'sk')


class TestSplitChapters(unittest.TestCase):
    def _mock_openai(self, mock_cls, content):
        m = MagicMock()
        m.chat.completions.create.return_value = _mock_chat(content)
        mock_cls.return_value = m

    @patch('openai.OpenAI')
    def test_valid(self, mock_cls):
        self._mock_openai(mock_cls, json.dumps(VALID_CHAPTERS))
        r = split_into_chapters('text', 'sk')
        self.assertEqual(len(r), 2)

    @patch('openai.OpenAI')
    def test_markdown_fence(self, mock_cls):
        raw = '```json\n' + json.dumps(VALID_CHAPTERS) + '\n```'
        self._mock_openai(mock_cls, raw)
        r = split_into_chapters('x', 'sk')
        self.assertEqual(len(r), 2)

    @patch('openai.OpenAI')
    def test_extra_text(self, mock_cls):
        raw = 'Here:\n' + json.dumps(VALID_CHAPTERS) + '\nDone.'
        self._mock_openai(mock_cls, raw)
        r = split_into_chapters('x', 'sk')
        self.assertEqual(len(r), 2)

    @patch('openai.OpenAI')
    def test_invalid_fallback(self, mock_cls):
        self._mock_openai(mock_cls, 'Not JSON!')
        r = split_into_chapters('A.\n\nB.\n\nC.', 'sk')
        self.assertGreater(len(r), 0)

    @patch('openai.OpenAI')
    def test_empty_fallback(self, mock_cls):
        self._mock_openai(mock_cls, '')
        r = split_into_chapters(
            'Paragraph A with enough content to pass the thirty character minimum filter for the fallback path.\n\n'
            'Paragraph B also with sufficient length to pass the filter test in the callback.', 'sk')
        self.assertGreater(len(r), 0, 'Empty LLM response should trigger fallback')


class TestTranslate(unittest.TestCase):
    @patch('openai.OpenAI')
    def test_single(self, mock_cls):
        m = MagicMock()
        m.chat.completions.create.return_value = _mock_chat('TR')
        mock_cls.return_value = m
        r = translate_paragraphs(['Hello'], 'sk')
        self.assertEqual(r, ['TR'])

    @patch('openai.OpenAI')
    def test_progress(self, mock_cls):
        m = MagicMock()
        m.chat.completions.create.return_value = _mock_chat('x')
        mock_cls.return_value = m
        p = []
        r = translate_paragraphs(['a', 'b'], 'sk', on_progress=lambda c, t: p.append(c))
        self.assertEqual(p, [1, 2])

    @patch('openai.OpenAI')
    def test_api_error(self, mock_cls):
        m = MagicMock()
        m.chat.completions.create.side_effect = Exception('fail')
        mock_cls.return_value = m
        r = translate_paragraphs(['H'], 'sk')
        self.assertIn('翻译失败', r[0])


class TestFullPipeline(unittest.TestCase):
    @patch('paper_vision.split_into_chapters')
    @patch('paper_vision.reformat_text')
    @patch('paper_vision.extract_text_pymupdf')
    def test_happy(self, mock_extract, mock_reformat, mock_split):
        mock_extract.return_value = 'full text'
        mock_reformat.return_value = 'reformatted text'
        mock_split.return_value = VALID_CHAPTERS
        stages = []
        r = full_pipeline('/f.pdf', '/tmp', 'sk', on_progress=lambda s, m, c, t: stages.append(s))
        self.assertIn('chapters', r)
        self.assertEqual(r['total_paragraphs'], 3)
        for s in ['extract', 'reformat', 'split', 'done']:
            self.assertIn(s, stages)

    @patch('paper_vision.extract_text_pymupdf')
    def test_extract_fails(self, mock_extract):
        mock_extract.side_effect = Exception('no pymupdf')
        with self.assertRaises(Exception):
            full_pipeline('/f.pdf', '/tmp', 'sk')


class TestProgress(unittest.TestCase):
    def test_format(self):
        buf = io.StringIO()
        old, sys.stdout = sys.stdout, buf
        try:
            _write({'type': 'progress', 'stage': 'o', 'message': 'm', 'current': 1, 'total': 10})
        finally:
            sys.stdout = old
        p = json.loads(buf.getvalue().strip())
        self.assertEqual(p['type'], 'progress')

    def test_result(self):
        buf = io.StringIO()
        old, sys.stdout = sys.stdout, buf
        try:
            _write({'type': 'result', 'data': {'k': 1}})
        finally:
            sys.stdout = old
        p = json.loads(buf.getvalue().strip())
        self.assertEqual(p['type'], 'result')


class TestPrompts(unittest.TestCase):
    def test_translate_prompt(self):
        f = _TRANSLATE_PROMPT.format(lang_in='en', lang_out='zh', text='Hi')
        self.assertIn('Hi', f)
        self.assertIn('$$', f)

    def test_split_prompt(self):
        f = _SPLIT_PROMPT.format(text='hello')
        self.assertIn('hello', f)
        self.assertIn('JSON', f)


if __name__ == '__main__':
    unittest.main(verbosity=2)
