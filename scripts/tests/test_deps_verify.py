"""
test_deps_verify.py — 验证所有 Python 脚本的依赖完整性和版本兼容性。

用法:
  scripts/python/python.exe -m pytest scripts/tests/test_deps_verify.py -v
"""

import importlib
import sys
from pathlib import Path

import pytest

# Ensure scripts/ is on sys.path so we can import pdf2zh_next
_SCRIPT_DIR = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(_SCRIPT_DIR))


# ── Direct dependencies for each script ───────────────────────────────────

# ocr_file.py & ocr_slides.py 依赖
OCR_DEPS = {
    "pytesseract": "0.3.10",
    "PIL": "10.0.0",          # Pillow
    "requests": "2.28.0",
    "pdf2image": "1.16.0",
}

# pdf_translate.py + pdf2zh_next 依赖
PDF_TRANSLATE_DEPS = {
    "babeldoc": "0.6.0",
    "fitz": "1.27.0",         # pymupdf
    "openai": "2.0.0",
    "pydantic": "2.0.0",
    "tomlkit": "0.12.0",
    "rich": "13.0.0",
    "peewee": "4.0.0",
    "tenacity": "9.0.0",
    "yaml": "6.0.0",          # PyYAML
}

# 所有脚本都需要的开发/测试依赖
DEV_DEPS = {
    "pytest": "7.0.0",
}

ALL_DEPS = {}
ALL_DEPS.update(OCR_DEPS)
ALL_DEPS.update(PDF_TRANSLATE_DEPS)
ALL_DEPS.update(DEV_DEPS)


def _parse_version(version_str: str) -> tuple:
    """将版本字符串解析为可比较的元组。"""
    return tuple(int(x) for x in version_str.split("."))


class TestDependencyImports:
    """验证所有必要依赖都可以正常导入。"""

    @pytest.mark.parametrize("module_name", sorted(OCR_DEPS.keys()))
    def test_ocr_dep_importable(self, module_name):
        """OCR 脚本的依赖必须可导入。"""
        mod = importlib.import_module(module_name)
        assert mod is not None, f"{module_name} 导入失败"

    @pytest.mark.parametrize("module_name", sorted(PDF_TRANSLATE_DEPS.keys()))
    def test_pdf_translate_dep_importable(self, module_name):
        """pdf_translate 依赖必须可导入。"""
        mod = importlib.import_module(module_name)
        assert mod is not None, f"{module_name} 导入失败"


class TestDependencyVersions:
    """验证关键依赖的版本满足最低要求。"""

    @pytest.mark.parametrize("module_name,min_version", [
        ("pytesseract", "0.3.10"),
        ("PIL", "10.0.0"),
        ("requests", "2.28.0"),
        ("pdf2image", "1.16.0"),
        ("babeldoc", "0.6.0"),
        ("pydantic", "2.0.0"),
        ("rich", "13.0.0"),
        ("peewee", "4.0.0"),
        ("tenacity", "9.0.0"),
        ("yaml", "6.0.0"),
    ])
    def test_version_meets_minimum(self, module_name, min_version):
        """验证模块版本 >= 最低要求。"""
        mod = importlib.import_module(module_name)
        version = getattr(mod, "__version__", None)
        if version is None:
            # 有些包把版本放在 VERSION 或 version 属性
            version = getattr(mod, "VERSION", None)
            if isinstance(version, tuple):
                version = ".".join(str(x) for x in version)

        if version is None:
            pytest.skip(f"{module_name} 无 __version__ 属性，跳过版本检查")

        # 清理版本号（去掉后缀如 'a1', 'b2', 'rc1' 等）
        clean_version = version.split("a")[0].split("b")[0].split("rc")[0].split("dev")[0]
        clean_version = clean_version.strip().split("+")[0]

        try:
            actual = _parse_version(clean_version)
        except ValueError:
            pytest.skip(f"{module_name} 版本号无法解析: {version}")
            return

        required = _parse_version(min_version)
        assert actual >= required, (
            f"{module_name} 版本 {version} < 最低要求 {min_version}"
        )

    def test_pymupdf_version(self):
        """PyMuPDF 通过 fitz 导入，版本 >= 1.27.0。"""
        import fitz
        version = fitz.version[0] if hasattr(fitz, "version") else None
        if version is None:
            pytest.skip("pymupdf 版本号获取失败")
        actual = _parse_version(version)
        required = _parse_version("1.27.0")
        assert actual >= required, f"PyMuPDF 版本 {version} < 1.27.0"

    def test_tomlkit_version(self):
        import tomlkit
        version = getattr(tomlkit, "__version__", None)
        if version is None:
            pytest.skip("tomlkit 版本号获取失败")
        actual = _parse_version(version.split("a")[0].split("b")[0])
        required = _parse_version("0.12.0")
        assert actual >= required, f"tomlkit 版本 {version} < 0.12.0"


class TestScriptModuleImports:
    """验证实际脚本的导入链完整。"""

    def test_ocr_file_module_loads(self):
        """ocr_file.py 导入链可用。"""
        import ocr_file
        assert hasattr(ocr_file, "ocr_image")
        assert hasattr(ocr_file, "process_file")
        assert hasattr(ocr_file, "main")

    def test_ocr_slides_module_loads(self):
        """ocr_slides.py 导入链可用。"""
        import ocr_slides
        assert hasattr(ocr_slides, "ocr_image")
        assert hasattr(ocr_slides, "download_and_ocr")
        assert hasattr(ocr_slides, "_is_url_allowed")

    def test_pdf_to_images_module_loads(self):
        """pdf_to_images.py 导入链可用。"""
        import pdf_to_images
        assert hasattr(pdf_to_images, "main")

    def test_pdf2zh_next_full_chain_loads(self):
        """pdf2zh_next 完整导入链：
        config.main → model → translate_engine_model → high_level → translator
        """
        from pdf2zh_next.config.main import ConfigManager
        from pdf2zh_next.config.model import BasicSettings, PDFSettings, SettingsModel, TranslationSettings
        from pdf2zh_next.config.translate_engine_model import DeepSeekSettings
        from pdf2zh_next.high_level import do_translate_async_stream, create_babeldoc_config
        assert ConfigManager is not None
        assert SettingsModel is not None
        assert DeepSeekSettings is not None
        assert do_translate_async_stream is not None
        assert create_babeldoc_config is not None

    def test_pdf_translate_check_deps_returns_none(self):
        """pdf_translate.check_deps() 在所有依赖满足时返回 None。"""
        import pdf_translate
        err = pdf_translate.check_deps()
        assert err is None, f"check_deps 应返回 None，实际: {err}"

    def test_pdf_translate_build_settings(self):
        """pdf_translate.build_settings() 能正确构造 SettingsModel。"""
        import pdf_translate

        class Args:
            model = "deepseek-chat"
            api_key = "sk-test"
            thinking = "disabled"
            lang_in = "en"
            lang_out = "zh"
            output = "/tmp/test_output"

        settings = pdf_translate.build_settings(Args())
        assert settings.translation.lang_in == "en"
        assert settings.translation.lang_out == "zh"
        assert settings.translate_engine_settings.deepseek_model == "deepseek-chat"
        assert settings.translate_engine_settings.deepseek_api_key == "sk-test"
        assert settings.translate_engine_settings.deepseek_thinking_mode == "disabled"


class TestBabeldocIntegration:
    """验证 babeldoc 核心 API 可用。"""

    def test_babeldoc_translation_config(self):
        """BabelDOC TranslationConfig 可构造。"""
        from babeldoc.format.pdf.translation_config import TranslationConfig
        assert TranslationConfig is not None

    def test_babeldoc_glossary(self):
        """BabelDOC Glossary 可导入。"""
        from babeldoc.glossary import Glossary
        assert Glossary is not None

    def test_babeldoc_watermark_mode(self):
        """BabelDOC WatermarkOutputMode 枚举可用。"""
        from babeldoc.format.pdf.translation_config import WatermarkOutputMode
        assert WatermarkOutputMode.NoWatermark is not None
        assert WatermarkOutputMode.Both is not None
        assert WatermarkOutputMode.Watermarked is not None


class TestPythonVersion:
    """验证 Python 版本 >= 3.10。"""

    def test_python_version(self):
        vi = sys.version_info
        assert vi.major == 3 and vi.minor >= 10, (
            f"需要 Python >= 3.10，当前: {vi.major}.{vi.minor}.{vi.micro}"
        )

    def test_architecture(self):
        """验证是 64 位 Python。"""
        import struct
        assert struct.calcsize("P") == 8, "需要 64 位 Python"


if __name__ == "__main__":
    pytest.main([__file__, "-v"])
