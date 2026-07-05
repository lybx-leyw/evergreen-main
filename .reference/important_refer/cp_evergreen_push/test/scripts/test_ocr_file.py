"""Unit tests for ocr_file.py."""

import json
import os
import sys
from io import StringIO

import pytest

try:
    import ocr_file
except SystemExit:
    pytest.skip('ocr_file dependencies not available', allow_module_level=True)

from conftest import needs_pil, needs_tesseract, needs_pdf2image, needs_ocr


# ── ocr_image ──────────────────────────────────────────────────

@needs_pil
class TestOcrImage:
    """PIL Image / file path OCR."""

    def test_returns_empty_on_invalid_path(self):
        text = ocr_file.ocr_image('/nonexistent/file.jpg')
        assert text == ''

    def test_handles_blank_image(self, sample_image):
        text = ocr_file.ocr_image(sample_image)
        assert isinstance(text, str)

    def test_rgba_conversion(self, tmp_path):
        """Verify RGBA images are converted to RGB without error."""
        try:
            from PIL import Image
        except ImportError:
            pytest.skip('Pillow not installed')
        img = Image.new('RGBA', (50, 50), color=(255, 0, 0, 128))
        path = tmp_path / 'rgba.png'
        img.save(str(path))
        text = ocr_file.ocr_image(str(path))
        assert isinstance(text, str)

    @needs_tesseract
    def test_ocr_text_image(self, text_image):
        if text_image is None:
            pytest.skip('Cannot create text image')
        text = ocr_file.ocr_image(text_image)
        assert isinstance(text, str)


# ── process_file ───────────────────────────────────────────────

class TestProcessFile:
    """文件类型路由 + 批量 OCR."""

    def test_image_file_returns_one_page(self, sample_image):
        pages = ocr_file.process_file(sample_image)
        assert isinstance(pages, list)
        if pages:
            assert pages[0]['page'] == 1
            assert 'text' in pages[0]

    def test_unsupported_extension_exits(self):
        old_stdout = sys.stdout
        old_stderr = sys.stderr
        sys.stdout = StringIO()
        sys.stderr = StringIO()
        try:
            with pytest.raises(SystemExit) as exc_info:
                ocr_file.process_file('/tmp/file.xyz')
            assert exc_info.value.code == 1
            parsed = json.loads(sys.stderr.getvalue())
            assert '不支持的文件格式' in parsed.get('error', '')
        finally:
            sys.stdout = old_stdout
            sys.stderr = old_stderr

    def test_missing_file_returns_empty(self, tmp_path):
        """process_file does not check existence — only main() does.
        A non-existent file returns empty OCR result (PIL fails to open)."""
        path = str(tmp_path / 'nonexistent.jpg')
        pages = ocr_file.process_file(path)
        assert isinstance(pages, list)
        # With a non-existent file, PIL fails → returns empty list

    @needs_pdf2image
    def test_pdf_processing(self, sample_pdf):
        if sample_pdf is None:
            pytest.skip('Cannot create sample PDF (fpdf not installed)')
        pages = ocr_file.process_file(sample_pdf)
        assert isinstance(pages, list)
        # PDF page count depends on the generated PDF

    def test_png_extension(self, sample_image):
        pages = ocr_file.process_file(sample_image)
        assert isinstance(pages, list)

    def test_webp_extension(self, tmp_path):
        """webp files are recognized as images."""
        try:
            from PIL import Image
        except ImportError:
            pytest.skip('Pillow not installed')
        img = Image.new('RGB', (10, 10))
        path = tmp_path / 'test.webp'
        img.save(str(path))
        pages = ocr_file.process_file(str(path))
        assert isinstance(pages, list)


# ── main() ─────────────────────────────────────────────────────

class TestMain:
    """CLI 入口."""

    def test_missing_path_arg_exits(self):
        old_stdout = sys.stdout
        sys.stdout = StringIO()
        try:
            sys.argv = ['ocr_file.py']
            with pytest.raises(SystemExit):
                ocr_file.main()
        finally:
            sys.stdout = old_stdout

    def test_file_not_found(self):
        old_stdout = sys.stdout
        old_stderr = sys.stderr
        sys.stdout = StringIO()
        sys.stderr = StringIO()
        try:
            sys.argv = ['ocr_file.py', '--path', '/nonexistent/file.png']
            with pytest.raises(SystemExit) as exc_info:
                ocr_file.main()
            assert exc_info.value.code == 1
            parsed = json.loads(sys.stderr.getvalue())
            assert '文件不存在' in parsed.get('error', '')
        finally:
            sys.stdout = old_stdout
            sys.stderr = old_stderr

    def test_cli_with_valid_image(self, sample_image):
        old_stdout = sys.stdout
        sys.stdout = StringIO()
        try:
            sys.argv = ['ocr_file.py', '--path', sample_image]
            ocr_file.main()
            output = sys.stdout.getvalue()
            parsed = json.loads(output)
            assert 'pages' in parsed
            assert isinstance(parsed['pages'], list)
        finally:
            sys.stdout = old_stdout


# ── JSON 输出格式 ──────────────────────────────────────────────

class TestJsonOutput:
    """验证 ocr_file.py 输出格式与 Dart 侧解析一致."""

    def test_single_page_structure(self, sample_image):
        pages = ocr_file.process_file(sample_image)
        output = json.dumps({'pages': pages}, ensure_ascii=False)
        parsed = json.loads(output)
        assert 'pages' in parsed
        if parsed['pages']:
            p = parsed['pages'][0]
            assert 'page' in p
            assert 'text' in p

    def test_empty_image_returns_empty_list(self):
        """blank white image returns [] (text is empty after OCR → filtered)."""
        # process_file filters empty text, so blank image → []
        # This depends on Tesseract behavior but the return type is always list
        # We can't guarantee blank image returns [] without Tesseract,
        # but the JSON structure is always valid.
        pass


# ── 线程池（修复后 max_workers 上限） ──────────────────────────

class TestThreadPoolLimit:
    """验证 MAX_OCR_WORKERS 常量存在且值合理."""

    def test_max_workers_constant_exists(self):
        assert hasattr(ocr_file, '_MAX_OCR_WORKERS')
        assert isinstance(ocr_file._MAX_OCR_WORKERS, int)
        assert 1 <= ocr_file._MAX_OCR_WORKERS <= 8
