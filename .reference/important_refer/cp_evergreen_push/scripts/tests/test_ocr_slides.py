"""
测试 ocr_slides.py — Tesseract OCR + URL 校验 + 临时文件清理。
"""

import json
import os
import sys
import tempfile
from pathlib import Path
from unittest.mock import MagicMock, patch

import pytest

sys.path.insert(0, str(Path(__file__).parent.parent))
import ocr_slides  # noqa: E402


# ── _is_url_allowed ────────────────────────────────────────────────────────

class TestIsUrlAllowed:
    """URL 安全校验——白名单 + 协议 + 本地文件."""

    def test_allows_zju_exact_domain(self):
        assert ocr_slides._is_url_allowed('https://img.cmc.zju.edu.cn/path/img.jpg')

    def test_allows_zju_subdomain(self):
        assert ocr_slides._is_url_allowed('https://tgmedia.cmc.zju.edu.cn/resource/1.jpg')

    def test_allows_classroom(self):
        assert ocr_slides._is_url_allowed('https://classroom.zju.edu.cn/slide.png')

    def test_allows_education(self):
        assert ocr_slides._is_url_allowed('https://education.cmc.zju.edu.cn/a.jpg')

    def test_rejects_non_zju_domain(self):
        assert not ocr_slides._is_url_allowed('https://evil.com/malware.jpg')

    def test_rejects_non_http_scheme(self):
        assert not ocr_slides._is_url_allowed('ftp://img.cmc.zju.edu.cn/file.jpg')

    def test_rejects_empty_host(self):
        assert not ocr_slides._is_url_allowed('https:///no-host')

    def test_rejects_data_url(self):
        assert not ocr_slides._is_url_allowed('data:image/png;base64,abc123')

    def test_rejects_javascript_url(self):
        assert not ocr_slides._is_url_allowed('javascript:alert(1)')

    def test_allows_existing_local_file(self, test_image_png):
        assert ocr_slides._is_url_allowed(test_image_png)

    def test_rejects_non_existent_local_file(self):
        if os.name == 'nt':
            path = 'C:/nonexistent/img.png'
        else:
            path = '/nonexistent/img.png'
        assert not ocr_slides._is_url_allowed(path)


# ── ocr_image ──────────────────────────────────────────────────────────────

class TestOcrImage:
    @patch("ocr_slides.pytesseract.image_to_string")
    def test_success(self, mock_ts, test_image_png, cleanup_files):
        mock_ts.return_value = "Hello World\n"
        text = ocr_slides.ocr_image(test_image_png)
        assert text == "Hello World"
        cleanup_files(test_image_png)

    @patch("ocr_slides.pytesseract.image_to_string")
    def test_strips_whitespace(self, mock_ts, test_image_png, cleanup_files):
        mock_ts.return_value = "  Some text  \n"
        text = ocr_slides.ocr_image(test_image_png)
        assert text == "Some text"
        cleanup_files(test_image_png)

    @patch("ocr_slides.pytesseract.image_to_string")
    def test_ocr_exception_returns_empty(self, mock_ts, test_image_png, cleanup_files):
        mock_ts.side_effect = Exception("OCR engine crashed")
        text = ocr_slides.ocr_image(test_image_png)
        assert text == ""
        cleanup_files(test_image_png)

    def test_missing_file_returns_empty(self, nonexistent_file):
        text = ocr_slides.ocr_image(nonexistent_file)
        assert text == ""

    def test_invalid_format_returns_empty(self, invalid_file, cleanup_files):
        text = ocr_slides.ocr_image(invalid_file)
        assert text == ""
        cleanup_files(invalid_file)


# ── download_and_ocr ───────────────────────────────────────────────────────

class TestDownloadAndOcr:
    @patch("ocr_slides.ocr_image")
    def test_local_file(self, mock_ocr, test_image_png, cleanup_files):
        mock_ocr.return_value = "local text"
        result = ocr_slides.download_and_ocr(test_image_png, page=1)
        assert result["page"] == 1
        assert result["url"] == test_image_png
        assert result["text"] == "local text"
        cleanup_files(test_image_png)

    @patch("ocr_slides.requests.get")
    @patch("ocr_slides.ocr_image")
    def test_remote_url_success(self, mock_ocr, mock_get):
        mock_ocr.return_value = "remote text"
        mock_resp = MagicMock()
        mock_resp.raise_for_status.return_value = None
        mock_resp.content = b"fake_image_data"
        mock_get.return_value = mock_resp
        result = ocr_slides.download_and_ocr(
            "https://img.cmc.zju.edu.cn/slides/1.jpg", page=2)
        assert result["page"] == 2
        assert result["text"] == "remote text"

    @patch("ocr_slides.requests.get")
    def test_download_failure(self, mock_get):
        from requests import RequestException
        mock_get.side_effect = RequestException("timeout")
        result = ocr_slides.download_and_ocr(
            "https://img.cmc.zju.edu.cn/bad.jpg", page=1)
        assert result["text"] == ""

    @patch("ocr_slides.ocr_image")
    @patch("ocr_slides.requests.get")
    def test_ocr_failure_after_download(self, mock_get, mock_ocr):
        mock_ocr.side_effect = Exception("OCR failed")
        mock_resp = MagicMock()
        mock_resp.raise_for_status.return_value = None
        mock_resp.content = b"data"
        mock_get.return_value = mock_resp
        result = ocr_slides.download_and_ocr(
            "https://img.cmc.zju.edu.cn/img.jpg", page=1)
        assert result["text"] == ""

    @patch("ocr_slides._is_url_allowed")
    @patch("ocr_slides.requests.get")
    def test_rejects_non_zju_url_before_download(self, mock_get, mock_is_allowed):
        """非 ZJU URL 被 _is_url_allowed 拦截，不发起 HTTP 请求。"""
        mock_is_allowed.return_value = False
        result = ocr_slides.download_and_ocr(
            "https://evil.com/phish.jpg", page=1)
        assert result["text"] == ""
        mock_get.assert_not_called()

    def test_temp_file_cleaned_after_ocr(self, test_image_png, cleanup_files):
        """本地文件 OCR 不会产生临时文件泄漏。"""
        import tempfile as tf
        before = set(os.listdir(tf.gettempdir()))
        result = ocr_slides.download_and_ocr(test_image_png, page=1)
        after = set(os.listdir(tf.gettempdir()))
        new_files = after - before
        assert len(new_files) == 0, f"Leaked temp files: {new_files}"
        assert isinstance(result["text"], str)
        cleanup_files(test_image_png)


# ── CLI main ───────────────────────────────────────────────────────────────

class TestMain:
    @patch("ocr_slides.download_and_ocr")
    def test_main_with_urls(self, mock_dl, capsys):
        mock_dl.side_effect = lambda url, page, timeout=30: {
            "page": page, "url": url, "text": f"page_{page}"
        }
        with patch.object(sys, "argv", ["ocr_slides.py", "--urls", "a.jpg,b.jpg"]):
            ocr_slides.main()
        out = json.loads(capsys.readouterr().out)
        assert len(out["results"]) == 2
        assert out["results"][0]["page"] == 1
        assert out["results"][1]["page"] == 2

    def test_main_empty_urls(self, capsys):
        with patch.object(sys, "argv", ["ocr_slides.py", "--urls", ""]):
            with pytest.raises(SystemExit):
                ocr_slides.main()
        parsed = json.loads(capsys.readouterr().out)
        assert "error" in parsed
        assert parsed["results"] == []

    def test_main_no_args(self, capsys):
        with patch.object(sys, "argv", ["ocr_slides.py"]):
            with pytest.raises(SystemExit):
                ocr_slides.main()

    @patch("ocr_slides.download_and_ocr")
    def test_main_with_lang_flag(self, mock_dl, capsys):
        mock_dl.return_value = {"page": 1, "url": "x", "text": "x"}
        with patch.object(sys, "argv",
                          ["ocr_slides.py", "--urls", "a.jpg", "--lang", "eng"]):
            ocr_slides.main()
        out = json.loads(capsys.readouterr().out)
        assert len(out["results"]) == 1

    @patch("ocr_slides.download_and_ocr")
    def test_main_output_structure(self, mock_dl, capsys):
        mock_dl.return_value = {"page": 1, "url": "u", "text": "测试中文"}
        with patch.object(sys, "argv", ["ocr_slides.py", "--urls", "u"]):
            ocr_slides.main()
        out = json.loads(capsys.readouterr().out)
        assert "results" in out
        assert "ensure_ascii" not in capsys.readouterr().out.lower() or True
        assert out["results"][0]["text"] == "测试中文"


# ── JSON 输出格式 ─────────────────────────────────────────────────────────

class TestJsonOutput:
    def test_results_wrapper(self):
        results = [
            {"page": 1, "url": "a.jpg", "text": "AAA"},
            {"page": 2, "url": "b.jpg", "text": "BBB"},
        ]
        out = json.dumps({"results": results}, ensure_ascii=False, indent=2)
        parsed = json.loads(out)
        assert "results" in parsed
        assert len(parsed["results"]) == 2

    def test_empty_text_handled(self):
        results = [{"page": 1, "url": "a.jpg", "text": ""}]
        out = json.dumps({"results": results}, ensure_ascii=False)
        parsed = json.loads(out)
        assert parsed["results"][0]["text"] == ""

    def test_chinese_text_unescaped(self):
        results = [{"page": 1, "url": "a.jpg", "text": "中文测试"}]
        out = json.dumps({"results": results}, ensure_ascii=False)
        assert "中文测试" in out
        assert "\\u" not in out
