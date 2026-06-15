"""Unit tests for pdf_to_images.py."""

import json
import os
import sys
from io import StringIO

import pytest

try:
    import pdf_to_images
except SystemExit:
    pytest.skip('pdf_to_images dependencies not available', allow_module_level=True)

from conftest import needs_pdf2image


class TestMain:
    """CLI 入口 + 参数解析."""

    def test_missing_path_arg_exits(self):
        old_stdout = sys.stdout
        old_stderr = sys.stderr
        sys.stdout = StringIO()
        sys.stderr = StringIO()
        try:
            sys.argv = ['pdf_to_images.py']
            with pytest.raises(SystemExit):
                pdf_to_images.main()
        finally:
            sys.stdout = old_stdout
            sys.stderr = old_stderr

    def test_file_not_found(self):
        old_stdout = sys.stdout
        old_stderr = sys.stderr
        sys.stdout = StringIO()
        sys.stderr = StringIO()
        try:
            sys.argv = ['pdf_to_images.py', '--path', '/nonexistent/file.pdf']
            with pytest.raises(SystemExit) as exc_info:
                pdf_to_images.main()
            assert exc_info.value.code == 1
            parsed = json.loads(sys.stderr.getvalue())
            assert '文件不存在' in parsed.get('error', '')
        finally:
            sys.stdout = old_stdout
            sys.stderr = old_stderr

    @needs_pdf2image
    def test_converts_pdf_to_jpeg(self, sample_pdf, tmp_path):
        if sample_pdf is None:
            pytest.skip('Cannot create sample PDF (fpdf not installed)')
        old_stdout = sys.stdout
        sys.stdout = StringIO()
        try:
            out_dir = str(tmp_path / 'output')
            sys.argv = [
                'pdf_to_images.py', '--path', sample_pdf,
                '--output_dir', out_dir, '--dpi', '72',
            ]
            pdf_to_images.main()
            output = sys.stdout.getvalue()
            parsed = json.loads(output)
            assert 'pages' in parsed
            assert len(parsed['pages']) > 0
            # Verify image files were created
            for page in parsed['pages']:
                assert os.path.isfile(page['path'])
                assert page['path'].endswith('.jpg')
        finally:
            sys.stdout = old_stdout

    def test_skip_ocr_flag_accepted(self, sample_pdf, tmp_path):
        """--skip-ocr 标志被接受（保留参数）。"""
        if sample_pdf is None:
            pytest.skip('Cannot create sample PDF')
        old_stdout = sys.stdout
        sys.stdout = StringIO()
        try:
            out_dir = str(tmp_path / 'output2')
            sys.argv = [
                'pdf_to_images.py', '--path', sample_pdf,
                '--output_dir', out_dir, '--skip-ocr',
            ]
            pdf_to_images.main()
            output = sys.stdout.getvalue()
            parsed = json.loads(output)
            assert 'pages' in parsed
        finally:
            sys.stdout = old_stdout


class TestJsonOutput:
    """验证输出格式."""

    @needs_pdf2image
    def test_page_structure(self, sample_pdf, tmp_path):
        if sample_pdf is None:
            pytest.skip('Cannot create sample PDF')
        old_stdout = sys.stdout
        sys.stdout = StringIO()
        try:
            out_dir = str(tmp_path / 'output3')
            sys.argv = [
                'pdf_to_images.py', '--path', sample_pdf,
                '--output_dir', out_dir, '--dpi', '72',
            ]
            pdf_to_images.main()
            output = sys.stdout.getvalue()
            parsed = json.loads(output)
            for page in parsed['pages']:
                assert 'page' in page
                assert 'path' in page
                assert isinstance(page['page'], int)
                assert page['page'] >= 1
        finally:
            sys.stdout = old_stdout


class TestOutputDir:
    """输出目录处理."""

    @needs_pdf2image
    def test_creates_output_dir(self, sample_pdf, tmp_path):
        if sample_pdf is None:
            pytest.skip('Cannot create sample PDF')
        out_dir = str(tmp_path / 'nested' / 'output')
        old_stdout = sys.stdout
        sys.stdout = StringIO()
        try:
            sys.argv = [
                'pdf_to_images.py', '--path', sample_pdf,
                '--output_dir', out_dir, '--dpi', '72',
            ]
            pdf_to_images.main()
            assert os.path.isdir(out_dir)
            # Pages should be generated
            output = sys.stdout.getvalue()
            parsed = json.loads(output)
            for page in parsed['pages']:
                assert out_dir in page['path']
        finally:
            sys.stdout = old_stdout

    @needs_pdf2image
    def test_default_temp_dir(self, sample_pdf):
        """不指定 --output_dir 时使用临时目录."""
        if sample_pdf is None:
            pytest.skip('Cannot create sample PDF')
        old_stdout = sys.stdout
        sys.stdout = StringIO()
        try:
            sys.argv = [
                'pdf_to_images.py', '--path', sample_pdf, '--dpi', '72',
            ]
            pdf_to_images.main()
            output = sys.stdout.getvalue()
            parsed = json.loads(output)
            for page in parsed['pages']:
                assert os.path.isfile(page['path'])
                # Clean up temp files
                try:
                    os.remove(page['path'])
                except OSError:
                    pass
        finally:
            sys.stdout = old_stdout
