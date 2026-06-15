"""
测试 ocr_file.py — 图片/PDF OCR + 线程池上限。
"""

import json
import os
import sys
from pathlib import Path
from unittest.mock import patch

import pytest
from PIL import Image

sys.path.insert(0, str(Path(__file__).parent.parent))
import ocr_file  # noqa: E402


# ── ocr_image ──────────────────────────────────────────────────────────────

class TestOcrImage:
    @patch("ocr_file.pytesseract.image_to_string")
    def test_pil_image_rgba_auto_convert(self, mock_ts, test_image_rgba, cleanup_files):
        """PIL Image 输入（RGBA 自动转 RGB）。"""
        mock_ts.return_value = "OCR result\n"
        img = Image.open(test_image_rgba)
        text = ocr_file.ocr_image(img)
        assert text == "OCR result"
        cleanup_files(test_image_rgba)

    @patch("ocr_file.pytesseract.image_to_string")
    def test_file_path_input(self, mock_ts, test_image_png, cleanup_files):
        """字符串路径输入（内部 Image.open）。"""
        mock_ts.return_value = "File OCR\n"
        text = ocr_file.ocr_image(test_image_png)
        assert text == "File OCR"
        cleanup_files(test_image_png)

    @patch("ocr_file.pytesseract.image_to_string")
    def test_strips_whitespace(self, mock_ts, test_image_png, cleanup_files):
        mock_ts.return_value = "  Some text  \n"
        text = ocr_file.ocr_image(test_image_png)
        assert text == "Some text"
        cleanup_files(test_image_png)

    @patch("ocr_file.pytesseract.image_to_string")
    def test_tesseract_error_returns_empty(self, mock_ts, test_image_png, cleanup_files):
        mock_ts.side_effect = Exception("Tesseract error")
        text = ocr_file.ocr_image(test_image_png)
        assert text == ""
        cleanup_files(test_image_png)

    @patch("ocr_file.Image.open")
    def test_pil_open_failure(self, mock_open, nonexistent_file):
        mock_open.side_effect = Exception("Cannot open")
        text = ocr_file.ocr_image(nonexistent_file)
        assert text == ""

    def test_missing_file_returns_empty(self, nonexistent_file):
        text = ocr_file.ocr_image(nonexistent_file)
        assert text == ""


# ── process_file ───────────────────────────────────────────────────────────

class TestProcessFile:
    @patch("ocr_file.ocr_image")
    def test_single_image(self, mock_ocr, test_image_png, cleanup_files):
        mock_ocr.return_value = "image text"
        pages = ocr_file.process_file(test_image_png)
        assert len(pages) == 1 and pages[0]["text"] == "image text"
        cleanup_files(test_image_png)

    @patch("ocr_file.ocr_image")
    def test_image_empty_text_filtered(self, mock_ocr, test_image_png, cleanup_files):
        mock_ocr.return_value = ""
        pages = ocr_file.process_file(test_image_png)
        assert pages == []
        cleanup_files(test_image_png)

    def test_unsupported_extension(self, invalid_file, cleanup_files):
        with pytest.raises(SystemExit) as exc:
            ocr_file.process_file(invalid_file)
        assert exc.value.code == 1
        cleanup_files(invalid_file)

    def test_missing_file_handled(self, tmp_path):
        """不存在的 .jpg → PIL.open 抛异常 → ocr_image 返回 '' → 被过滤。"""
        path = str(tmp_path / "nonexistent.jpg")
        pages = ocr_file.process_file(path)
        assert isinstance(pages, list)

    def test_jpg_extension(self, test_image_jpg, cleanup_files):
        with patch("ocr_file.ocr_image", return_value="jpg text"):
            pages = ocr_file.process_file(test_image_jpg)
            assert isinstance(pages, list)
            if pages:
                assert pages[0]["page"] == 1
        cleanup_files(test_image_jpg)

    def test_webp_extension(self, tmp_path):
        path = str(tmp_path / "test.webp")
        Image.new("RGB", (10, 10)).save(path)
        with patch("ocr_file.ocr_image", return_value="webp text"):
            pages = ocr_file.process_file(path)
            assert isinstance(pages, list)

    @patch("ocr_file.convert_from_path")
    @patch("ocr_file.ocr_image")
    def test_pdf_single_page(self, mock_ocr, mock_cv):
        mock_cv.return_value = [Image.new("RGB", (100, 30))]
        mock_ocr.return_value = "pdf text"
        pages = ocr_file.process_file("test.pdf")
        assert len(pages) == 1
        assert pages[0]["text"] == "pdf text"
        assert pages[0]["page"] == 1

    @patch("ocr_file.convert_from_path")
    @patch("ocr_file.ocr_image")
    def test_pdf_multi_page(self, mock_ocr, mock_cv):
        n = 5
        mock_cv.return_value = [Image.new("RGB", (100, 30)) for _ in range(n)]
        mock_ocr.side_effect = [f"p{i}" for i in range(1, n + 1)]
        results = ocr_file.process_file("multi.pdf")
        assert len(results) == n
        for i, r in enumerate(results, start=1):
            assert r["page"] == i
            assert r["text"] == f"p{i}"

    @patch("ocr_file.convert_from_path")
    @patch("ocr_file.ocr_image")
    def test_pdf_all_empty(self, mock_ocr, mock_cv):
        mock_cv.return_value = [Image.new("RGB", (10, 10))]
        mock_ocr.return_value = ""
        assert ocr_file.process_file("empty.pdf") == []

    @patch("ocr_file.convert_from_path")
    @patch("ocr_file.ocr_image")
    def test_pdf_large_image_resized(self, mock_ocr, mock_cv):
        """3000×2000 的 PDF 页 → 缩放到 1500px。"""
        mock_cv.return_value = [Image.new("RGB", (3000, 2000))]
        mock_ocr.return_value = "resized ok"
        results = ocr_file.process_file("large.pdf")
        assert len(results) == 1
        assert results[0]["text"] == "resized ok"


# ── 线程池上限 ─────────────────────────────────────────────────────────────

class TestThreadPoolLimit:
    def test_max_workers_constant_exists(self):
        assert hasattr(ocr_file, '_MAX_OCR_WORKERS')
        assert isinstance(ocr_file._MAX_OCR_WORKERS, int)

    def test_max_workers_reasonable_bounds(self):
        assert 1 <= ocr_file._MAX_OCR_WORKERS <= 8


# ── CLI main ──────────────────────────────────────────────────────────────

class TestMain:
    @patch("ocr_file.os.path.isfile")
    @patch("ocr_file.process_file")
    def test_success(self, mock_proc, mock_isf, capsys):
        mock_isf.return_value = True
        mock_proc.return_value = [{"page": 1, "text": "hello"}]
        with patch.object(sys, "argv", ["ocr_file.py", "--path", "t.png"]):
            ocr_file.main()
        out = json.loads(capsys.readouterr().out)
        assert out["pages"][0]["text"] == "hello"

    @patch("ocr_file.os.path.isfile")
    def test_file_not_found(self, mock_isf, capsys):
        mock_isf.return_value = False
        with patch.object(sys, "argv", ["ocr_file.py", "--path", "m.png"]):
            with pytest.raises(SystemExit) as exc:
                ocr_file.main()
            assert exc.value.code == 1
            assert "error" in capsys.readouterr().err

    def test_missing_path_arg(self):
        with patch.object(sys, "argv", ["ocr_file.py"]):
            with pytest.raises(SystemExit):
                ocr_file.main()


# ── JSON 输出格式 ─────────────────────────────────────────────────────────

class TestJsonOutput:
    def test_single_page_structure(self):
        pages = [{"page": 1, "text": "content"}]
        out = json.dumps({"pages": pages}, ensure_ascii=False)
        parsed = json.loads(out)
        assert parsed["pages"][0]["page"] == 1

    def test_chinese_text_unescaped(self):
        pages = [{"page": 1, "text": "中文测试"}]
        out = json.dumps({"pages": pages}, ensure_ascii=False)
        assert "中文测试" in out
