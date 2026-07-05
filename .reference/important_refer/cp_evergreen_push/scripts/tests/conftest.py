"""
pytest 共享 fixtures — OCR 脚本测试。
"""

import os
import tempfile
from pathlib import Path

import pytest
from PIL import Image


# ── 共享 fixture ──────────────────────────────────────────────────────────

@pytest.fixture(autouse=True)
def setup_env():
    """测试前确保环境干净。"""
    yield


@pytest.fixture
def test_image_png() -> str:
    """生成一张带文字的测试 PNG 图片，返回路径。"""
    with tempfile.NamedTemporaryFile(suffix=".png", delete=False) as f:
        img = Image.new("RGB", (100, 30), color="white")
        img.save(f, format="PNG")
        return f.name


@pytest.fixture
def test_image_jpg() -> str:
    """生成一张测试 JPG 图片，返回路径。"""
    with tempfile.NamedTemporaryFile(suffix=".jpg", delete=False) as f:
        img = Image.new("RGB", (100, 30), color="white")
        img.save(f, format="JPEG")
        return f.name


@pytest.fixture
def test_image_rgba() -> str:
    """生成一张 RGBA 模式的测试图片，返回路径。"""
    with tempfile.NamedTemporaryFile(suffix=".png", delete=False) as f:
        img = Image.new("RGBA", (100, 30), color=(255, 0, 0, 128))
        img.save(f, format="PNG")
        return f.name


@pytest.fixture
def test_image_large() -> str:
    """生成一张超大的测试图片（用于测试缩放逻辑）。"""
    with tempfile.NamedTemporaryFile(suffix=".png", delete=False) as f:
        img = Image.new("RGB", (3000, 2000), color="white")
        img.save(f, format="PNG")
        return f.name


@pytest.fixture
def invalid_file() -> str:
    """生成一个非图片文件。"""
    with tempfile.NamedTemporaryFile(suffix=".txt", delete=False, mode="w") as f:
        f.write("not an image")
        return f.name


@pytest.fixture
def nonexistent_file() -> str:
    """一个不存在的文件路径。"""
    return "C:/nonexistent/file_that_does_not_exist.jpg"


@pytest.fixture
def cleanup_files():
    """收集测试中创建的文件并在结束时清理。"""
    files = []

    def _collect(path: str):
        files.append(path)
        return path

    yield _collect

    for f in files:
        try:
            os.unlink(f)
        except OSError:
            try:
                os.rmdir(f)
            except OSError:
                pass
