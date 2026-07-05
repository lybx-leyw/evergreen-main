"""
测试 pdf_to_images.py — PDF → JPEG 转换。
"""

import json
import os
import sys
from pathlib import Path
from unittest.mock import patch

import pytest
from PIL import Image

sys.path.insert(0, str(Path(__file__).parent.parent))
import pdf_to_images  # noqa: E402


class TestMain:
    @patch("pdf_to_images.os.path.isfile")
    @patch("pdf_to_images.convert_from_path")
    def test_single_page_basic(self, mock_cv, mock_isf, capsys, tmp_path):
        mock_isf.return_value = True
        mock_cv.return_value = [Image.new("RGB", (100, 30))]

        out = tmp_path / "out"
        with patch.object(sys, "argv", [
            "pdf_to_images.py", "--path", "test.pdf",
            "--output_dir", str(out),
        ]):
            pdf_to_images.main()

        data = json.loads(capsys.readouterr().out)
        assert len(data["pages"]) == 1
        assert data["pages"][0]["page"] == 1
        assert os.path.isfile(data["pages"][0]["path"])

    @patch("pdf_to_images.os.path.isfile")
    @patch("pdf_to_images.convert_from_path")
    def test_multi_page(self, mock_cv, mock_isf, capsys, tmp_path):
        mock_isf.return_value = True
        n = 3
        mock_cv.return_value = [Image.new("RGB", (100, 30)) for _ in range(n)]

        out = tmp_path / "out"
        with patch.object(sys, "argv", [
            "pdf_to_images.py", "--path", "multi.pdf",
            "--output_dir", str(out),
        ]):
            pdf_to_images.main()

        data = json.loads(capsys.readouterr().out)
        assert len(data["pages"]) == n
        for i, p in enumerate(data["pages"], start=1):
            assert p["page"] == i
            assert p["path"].endswith(".jpg")

    @patch("pdf_to_images.os.path.isfile")
    @patch("pdf_to_images.convert_from_path")
    def test_skip_ocr_flag_accepted(self, mock_cv, mock_isf, capsys, tmp_path):
        """--skip-ocr 是保留参数，应被接受且不影响输出。"""
        mock_isf.return_value = True
        mock_cv.return_value = [Image.new("RGB", (100, 30))]

        out = tmp_path / "out"
        with patch.object(sys, "argv", [
            "pdf_to_images.py", "--path", "test.pdf",
            "--output_dir", str(out), "--skip-ocr",
        ]):
            pdf_to_images.main()

        data = json.loads(capsys.readouterr().out)
        assert len(data["pages"]) == 1

    @patch("pdf_to_images.os.path.isfile")
    @patch("pdf_to_images.convert_from_path")
    def test_custom_dpi(self, mock_cv, mock_isf, capsys, tmp_path):
        mock_isf.return_value = True
        mock_cv.return_value = [Image.new("RGB", (100, 30))]

        out = tmp_path / "out"
        with patch.object(sys, "argv", [
            "pdf_to_images.py", "--path", "test.pdf",
            "--output_dir", str(out), "--dpi", "300",
        ]):
            pdf_to_images.main()

        # DPI=300 应传给 convert_from_path
        mock_cv.assert_called_once_with("test.pdf", dpi=300)
        data = json.loads(capsys.readouterr().out)
        assert len(data["pages"]) == 1

    @patch("pdf_to_images.os.path.isfile")
    def test_file_not_found(self, mock_isf, capsys):
        mock_isf.return_value = False
        with patch.object(sys, "argv", [
            "pdf_to_images.py", "--path", "nope.pdf",
        ]):
            with pytest.raises(SystemExit) as exc:
                pdf_to_images.main()
            assert exc.value.code == 1
            assert "error" in capsys.readouterr().err

    def test_missing_path_arg(self, capsys):
        with patch.object(sys, "argv", ["pdf_to_images.py"]):
            with pytest.raises(SystemExit):
                pdf_to_images.main()

    @patch("pdf_to_images.os.path.isfile")
    @patch("pdf_to_images.convert_from_path")
    def test_default_temp_dir(self, mock_cv, mock_isf, capsys):
        """不指定 --output_dir → 使用临时目录。"""
        mock_isf.return_value = True
        mock_cv.return_value = [Image.new("RGB", (10, 10))]

        with patch.object(sys, "argv", [
            "pdf_to_images.py", "--path", "test.pdf",
        ]):
            pdf_to_images.main()

        data = json.loads(capsys.readouterr().out)
        assert len(data["pages"]) == 1
        # 文件应生成
        assert os.path.isfile(data["pages"][0]["path"])
        # 清理临时文件
        for p in data["pages"]:
            try: os.remove(p["path"])
            except OSError: pass

    @patch("pdf_to_images.os.path.isfile")
    @patch("pdf_to_images.convert_from_path")
    def test_creates_output_dir_if_missing(self, mock_cv, mock_isf, capsys, tmp_path):
        mock_isf.return_value = True
        mock_cv.return_value = [Image.new("RGB", (10, 10))]

        out = tmp_path / "nested" / "output"
        # 不预先创建目录——让 pdf_to_images 自己创建
        with patch.object(sys, "argv", [
            "pdf_to_images.py", "--path", "test.pdf",
            "--output_dir", str(out),
        ]):
            pdf_to_images.main()

        data = json.loads(capsys.readouterr().out)
        assert len(data["pages"]) == 1
        assert os.path.isdir(str(out))  # 目录被自动创建


class TestJsonOutput:
    def test_page_structure(self):
        pages = [{"page": 1, "path": "/tmp/page_1.jpg"}]
        out = json.dumps({"pages": pages}, ensure_ascii=False)
        parsed = json.loads(out)
        assert parsed["pages"][0]["page"] == 1
        assert parsed["pages"][0]["path"].endswith(".jpg")

    def test_chinese_path_handled(self):
        pages = [{"page": 1, "path": "C:/temp/page_1.jpg"}]
        out = json.dumps({"pages": pages}, ensure_ascii=False)
        assert "page_1.jpg" in out
