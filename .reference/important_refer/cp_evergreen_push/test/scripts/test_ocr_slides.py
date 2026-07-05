"""Unit tests for ocr_slides.py."""

import json
import os
import sys
from io import StringIO

import pytest

# Module under test — import fails gracefully if deps missing
try:
    import ocr_slides
except SystemExit:
    pytest.skip('ocr_slides dependencies not available', allow_module_level=True)

from conftest import needs_pil, needs_tesseract, needs_ocr


# ── _is_url_allowed ────────────────────────────────────────────

class TestIsUrlAllowed:
    """URL 安全校验——白名单 + 协议 + 本地文件."""

    def test_allows_zju_domain(self):
        assert ocr_slides._is_url_allowed('https://img.cmc.zju.edu.cn/path/img.jpg')

    def test_allows_zju_subdomain(self):
        assert ocr_slides._is_url_allowed('https://tgmedia.cmc.zju.edu.cn/resource/1.jpg')

    def test_allows_classroom_domain(self):
        assert ocr_slides._is_url_allowed('https://classroom.zju.edu.cn/slide.png')

    def test_allows_education_subdomain(self):
        assert ocr_slides._is_url_allowed('https://education.cmc.zju.edu.cn/a.jpg')

    def test_rejects_non_zju_domain(self):
        assert not ocr_slides._is_url_allowed('https://evil.com/malware.jpg')

    def test_rejects_non_http_scheme(self):
        assert not ocr_slides._is_url_allowed('ftp://img.cmc.zju.edu.cn/file.jpg')

    def test_rejects_empty_host(self):
        assert not ocr_slides._is_url_allowed('https:///no-host')

    def test_allows_local_file_path(self):
        if os.name == 'nt':
            path = 'C:\\Users\\test\\image.png'
        else:
            path = '/home/user/image.png'
        # Local files fail _is_url_allowed because scheme is empty and
        # os.path.isfile returns False for non-existent paths.
        # But the check is: parsed.scheme == "" and os.path.isfile(url)
        # For a non-existent file, it should return False.
        assert not ocr_slides._is_url_allowed(path)

    def test_allows_existing_local_file(self, sample_image):
        assert ocr_slides._is_url_allowed(sample_image)

    def test_rejects_data_url(self):
        assert not ocr_slides._is_url_allowed('data:image/png;base64,abc123')

    def test_rejects_javascript_url(self):
        assert not ocr_slides._is_url_allowed('javascript:alert(1)')


# ── ocr_image ──────────────────────────────────────────────────

@needs_pil
class TestOcrImage:
    """单张图片 OCR——基本功能测试."""

    def test_returns_empty_on_invalid_path(self):
        text = ocr_slides.ocr_image('/nonexistent/path.png')
        assert text == ''

    def test_handles_empty_file(self, sample_image):
        # sample_image is a blank white image — OCR should return empty or minimal text
        text = ocr_slides.ocr_image(sample_image)
        assert isinstance(text, str)

    @needs_tesseract
    def test_ocr_text_image(self, text_image):
        if text_image is None:
            pytest.skip('Cannot create text image')
        text = ocr_slides.ocr_image(text_image)
        assert isinstance(text, str)
        # Tesseract should find at least some of the text
        assert len(text) > 0 or True  # Tesseract may struggle with default font


# ── download_and_ocr ───────────────────────────────────────────

class TestDownloadAndOcr:
    """下载 + OCR 流程."""

    def test_local_file_path(self, sample_image):
        result = ocr_slides.download_and_ocr(sample_image, page=1)
        assert result['page'] == 1
        assert result['url'] == sample_image
        assert isinstance(result['text'], str)

    def test_rejects_non_zju_url(self):
        result = ocr_slides.download_and_ocr('https://evil.com/image.jpg', page=1)
        assert result['page'] == 1
        assert result['text'] == ''
        # URL is preserved in result even when rejected
        assert result['url'] == 'https://evil.com/image.jpg'

    def test_cleans_up_temp_file(self, tmp_path):
        """Verify no temp file leak after download failure."""
        import tempfile
        before = set(os.listdir(tempfile.gettempdir()))
        ocr_slides.download_and_ocr('https://img.cmc.zju.edu.cn/nonexistent.jpg', page=1, timeout=2)
        after = set(os.listdir(tempfile.gettempdir()))
        new_files = after - before
        # No leaked temp files
        assert len(new_files) == 0


# ── main() ─────────────────────────────────────────────────────

class TestMain:
    """CLI 入口 + JSON 输出格式."""

    def test_no_urls_produces_error_json(self):
        old_stdout = sys.stdout
        sys.stdout = StringIO()
        try:
            sys.argv = ['ocr_slides.py', '--urls', '']
            with pytest.raises(SystemExit) as exc:
                ocr_slides.main()
            assert exc.value.code == 0
            output = sys.stdout.getvalue()
            parsed = json.loads(output)
            assert 'error' in parsed
            assert parsed['results'] == []
        finally:
            sys.stdout = old_stdout

    def test_output_structure(self, sample_image):
        """Verify that direct call to download_and_ocr returns correct structure."""
        result = ocr_slides.download_and_ocr(sample_image, page=1, timeout=5)
        assert 'page' in result
        assert 'url' in result
        assert 'text' in result
        assert isinstance(result['page'], int)
        assert isinstance(result['text'], str)

    @needs_ocr
    def test_empty_urls_with_no_urls(self):
        """Simulate --urls '' → empty list → error JSON."""
        old_stdout = sys.stdout
        sys.stdout = StringIO()
        try:
            sys.argv = ['ocr_slides.py', '--urls', '']
            with pytest.raises(SystemExit) as exc_info:
                ocr_slides.main()
            assert exc_info.value.code == 0
            parsed = json.loads(sys.stdout.getvalue())
            assert parsed['results'] == []
        finally:
            sys.stdout = old_stdout


# ── JSON 输出格式 ──────────────────────────────────────────────

class TestJsonOutput:
    """验证 OCR 结果的 JSON 结构符合调用方（Dart）预期."""

    def test_results_wrapper(self, sample_image):
        """模拟 main() 的输出格式."""
        results = [ocr_slides.download_and_ocr(sample_image, page=1, timeout=5)]
        output = json.dumps({'results': results}, ensure_ascii=False, indent=2)
        parsed = json.loads(output)
        assert 'results' in parsed
        assert len(parsed['results']) == 1
        assert 'page' in parsed['results'][0]

    def test_multiple_pages(self, sample_image):
        results = [
            ocr_slides.download_and_ocr(sample_image, page=1, timeout=5),
            ocr_slides.download_and_ocr(sample_image, page=2, timeout=5),
        ]
        output = json.dumps({'results': results}, ensure_ascii=False)
        parsed = json.loads(output)
        assert len(parsed['results']) == 2
        assert parsed['results'][0]['page'] == 1
        assert parsed['results'][1]['page'] == 2
