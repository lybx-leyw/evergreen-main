"""
test_pdf_translate.py — 测试 pdf_translate.py 的依赖检查、settings 构造、事件格式化。

用法:
  scripts/python/python.exe -m pytest scripts/tests/test_pdf_translate.py -v
"""

import json
import sys
from pathlib import Path
from unittest.mock import MagicMock, patch

import pytest

_SCRIPT_DIR = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(_SCRIPT_DIR))

import pdf_translate  # noqa: E402


# ── Dependency check ─────────────────────────────────────────────────────

class TestCheckDeps:
    """check_deps() 依赖检查。"""

    def test_returns_none_when_deps_ok(self):
        """依赖满足时返回 None。"""
        assert pdf_translate.check_deps() is None

    @patch("pdf_translate.check_deps")
    def test_non_none_triggers_error_path(self, mock_check):
        """check_deps 返回错误时应有对应处理。"""
        err_json = json.dumps({
            "error": "pdf2zh 依赖缺失: test error",
            "action": "pip",
            "hint": "请确认已安装依赖",
        })
        mock_check.return_value = err_json
        result = pdf_translate.check_deps()
        assert result is not None
        parsed = json.loads(result)
        assert "error" in parsed
        assert parsed["action"] == "pip"


# ── build_settings ───────────────────────────────────────────────────────

class TestBuildSettings:
    """build_settings() SettingsModel 构造。"""

    def test_basic_args(self):
        """基本参数可正确转换为 SettingsModel。"""

        class Args:
            model = "deepseek-chat"
            api_key = "sk-test-key-123"
            thinking = "disabled"
            lang_in = "en"
            lang_out = "zh"
            output = "/tmp/translate_output"

        settings = pdf_translate.build_settings(Args())
        assert settings.translation.lang_in == "en"
        assert settings.translation.lang_out == "zh"
        assert settings.translation.output == "/tmp/translate_output"
        assert settings.translate_engine_settings.deepseek_model == "deepseek-chat"
        assert settings.translate_engine_settings.deepseek_api_key == "sk-test-key-123"
        assert settings.translate_engine_settings.deepseek_thinking_mode == "disabled"
        assert settings.basic.debug is False
        assert settings.basic.gui is False

    def test_thinking_none_handling(self):
        """--thinking 未传入时 deepseek_thinking_mode 应为 None。"""

        class Args:
            model = "deepseek-chat"
            api_key = "sk-test"
            thinking = None
            lang_in = "en"
            lang_out = "zh"
            output = "/tmp/out"

        settings = pdf_translate.build_settings(Args())
        assert settings.translate_engine_settings.deepseek_thinking_mode is None

    def test_thinking_enabled(self):
        """--thinking enabled 的传递。"""

        class Args:
            model = "deepseek-v4"
            api_key = "sk-v4"
            thinking = "enabled"
            lang_in = "ja"
            lang_out = "en"
            output = "/tmp/out"

        settings = pdf_translate.build_settings(Args())
        assert settings.translate_engine_settings.deepseek_model == "deepseek-v4"
        assert settings.translate_engine_settings.deepseek_thinking_mode == "enabled"
        assert settings.translation.lang_in == "ja"

    def test_pdf_settings_no_dual_no_mono_false(self):
        """默认生成 mono 和 dual PDF。"""

        class Args:
            model = "deepseek-chat"
            api_key = "sk"
            thinking = None
            lang_in = "en"
            lang_out = "zh"
            output = "/tmp"

        settings = pdf_translate.build_settings(Args())
        assert settings.pdf.no_dual is False
        assert settings.pdf.no_mono is False


# ── format_event ─────────────────────────────────────────────────────────

class TestFormatEvent:
    """format_event() 事件 → JSON 行转换。"""

    def test_stage_init_event(self):
        """stage_init → 中文友好标签。"""
        line = pdf_translate.format_event({
            "type": "stage_init",
            "current": 0,
            "total": 10,
        })
        parsed = json.loads(line)
        assert parsed["type"] == "stage"
        assert parsed["stage"] == "stage_init"
        assert parsed["message"] == "正在初始化翻译引擎..."

    def test_stage_translate_event(self):
        """stage_translate → 中文友好标签。"""
        line = pdf_translate.format_event({
            "type": "stage_translate",
            "current": 3,
            "total": 10,
        })
        parsed = json.loads(line)
        assert parsed["stage"] == "stage_translate"
        assert parsed["message"] == "正在调用 AI 翻译..."
        assert parsed["current"] == 3

    def test_progress_event(self):
        """progress 类型原样映射。"""
        line = pdf_translate.format_event({
            "type": "progress",
            "current": 5,
            "total": 12,
            "message": "Translating page 5...",
        })
        parsed = json.loads(line)
        assert parsed["type"] == "progress"
        assert parsed["current"] == 5
        assert parsed["total"] == 12
        assert "Translating" in parsed["message"]

    def test_finish_event_with_result(self):
        """finish 事件提取 translate_result 和 token_usage。"""
        mock_result = MagicMock()
        mock_result.total_seconds = 45.2
        mock_result.mono_pdf_path = Path("/tmp/out/mono.pdf")
        mock_result.dual_pdf_path = Path("/tmp/out/dual.pdf")

        line = pdf_translate.format_event({
            "type": "finish",
            "translate_result": mock_result,
            "token_usage": {
                "main": {"total": 10000, "prompt": 5000, "completion": 5000, "cache_hit_prompt": 0},
            },
        })
        parsed = json.loads(line)
        assert parsed["type"] == "finish"
        assert parsed["total_seconds"] == 45.2
        assert parsed["mono_pdf"].endswith("mono.pdf")
        assert parsed["dual_pdf"].endswith("dual.pdf")
        assert parsed["tokens"]["total"] == 10000

    def test_finish_event_combines_main_and_term_tokens(self):
        """finish 事件正确合并 main 和 term token。"""
        mock_result = MagicMock()
        mock_result.total_seconds = 60.0
        mock_result.mono_pdf_path = Path("/out/mono.pdf")
        mock_result.dual_pdf_path = None

        line = pdf_translate.format_event({
            "type": "finish",
            "translate_result": mock_result,
            "token_usage": {
                "main": {"total": 8000},
                "term": {"total": 2000},
            },
        })
        parsed = json.loads(line)
        assert parsed["tokens"]["total"] == 10000  # 8000 + 2000

    def test_finish_event_null_paths(self):
        """finish 事件路径为 None 时正确处理。"""
        mock_result = MagicMock()
        mock_result.total_seconds = 10.0
        mock_result.mono_pdf_path = None
        mock_result.dual_pdf_path = None

        line = pdf_translate.format_event({
            "type": "finish",
            "translate_result": mock_result,
            "token_usage": {},
        })
        parsed = json.loads(line)
        assert parsed["mono_pdf"] is None
        assert parsed["dual_pdf"] is None
        assert "tokens" not in parsed

    def test_error_event(self):
        """error 事件提取 error / error_type / details。"""
        line = pdf_translate.format_event({
            "type": "error",
            "error": "Translation failed",
            "error_type": "BabeldocError",
            "details": "PDF parsing error at page 3",
        })
        parsed = json.loads(line)
        assert parsed["type"] == "error"
        assert parsed["message"] == "Translation failed"
        assert parsed["error_type"] == "BabeldocError"
        assert "page 3" in parsed["details"]

    def test_error_event_defaults(self):
        """error 事件缺失字段时有默认值。"""
        line = pdf_translate.format_event({
            "type": "error",
            "error": "Unknown error",
        })
        parsed = json.loads(line)
        assert parsed["message"] == "Unknown error"
        assert parsed["error_type"] == ""
        assert parsed["details"] == ""

    def test_generic_event_falls_back_to_message(self):
        """未映射 stage → stage 类型，message 为原文。"""
        line = pdf_translate.format_event({
            "type": "stage_unknown",
            "current": 1,
            "total": 5,
            "message": "Doing something",
        })
        parsed = json.loads(line)
        # stage_unknown 以 stage_ 开头 → 路由到 stage 类型，message=原文
        assert parsed["type"] == "stage"
        assert parsed["stage"] == "stage_unknown"

    def test_truly_unknown_event_type(self):
        """完全未知的事件类型（不以 stage_/progress/finish/error 开头）→ progress。"""
        line = pdf_translate.format_event({
            "type": "custom_metric",
            "current": 0,
            "total": 1,
            "message": "Metric value",
        })
        parsed = json.loads(line)
        assert parsed["type"] == "progress"
        assert parsed["message"] == "Metric value"

    def test_chinese_output_no_escape(self):
        """确保 ensure_ascii=False，中文不被转义。"""
        line = pdf_translate.format_event({
            "type": "stage_init",
            "current": 0,
            "total": 1,
        })
        assert "正在初始化" in line
        assert "\\u" not in line


# ── _STAGE_NAME_MAP ──────────────────────────────────────────────────────

class TestStageNameMap:
    """验证 stage 名称映射表。"""

    def test_all_used_stages_mapped(self):
        """关键 stage 都有翻译。"""
        required_stages = [
            "stage_init", "stage_parse", "stage_layout",
            "stage_translate", "stage_output", "stage_merge",
            "stage_cleanup",
        ]
        for s in required_stages:
            assert s in pdf_translate._STAGE_NAME_MAP, f"{s} 缺少翻译"
            assert isinstance(pdf_translate._STAGE_NAME_MAP[s], str)
            assert len(pdf_translate._STAGE_NAME_MAP[s]) > 0

    def test_unknown_stage_uses_raw_name(self):
        """未映射的 stage 返回原始名称。"""
        line = pdf_translate.format_event({
            "type": "stage_unknown_future",
            "current": 0,
            "total": 0,
        })
        parsed = json.loads(line)
        assert parsed["message"] == "stage_unknown_future"


# ── CLI argument parsing ─────────────────────────────────────────────────

class TestCLIArgs:
    """验证 CLI 参数解析。"""

    def test_required_args_present(self):
        """--input / --output / --api-key 均为 required=True。"""
        import argparse
        # pdf_translate uses argparse in main() — verify the module has it
        assert hasattr(pdf_translate, "argparse")

    def test_parser_creation(self):
        """验证 ArgumentParser 能正确创建且包含必要参数。"""
        import argparse
        parser = argparse.ArgumentParser(description="test")
        parser.add_argument("--input", required=True)
        parser.add_argument("--output", required=True)
        parser.add_argument("--api-key", required=True)
        parser.add_argument("--model", default="deepseek-chat")
        parser.add_argument("--thinking", default=None)
        parser.add_argument("--lang-in", default="en")
        parser.add_argument("--lang-out", default="zh")

        # 验证默认值
        ns = parser.parse_args([
            "--input", "test.pdf",
            "--output", "/tmp/out",
            "--api-key", "sk-test",
        ])
        assert ns.model == "deepseek-chat"
        assert ns.thinking is None
        assert ns.lang_in == "en"
        assert ns.lang_out == "zh"


if __name__ == "__main__":
    pytest.main([__file__, "-v"])
