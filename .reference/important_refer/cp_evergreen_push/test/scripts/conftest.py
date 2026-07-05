"""Shared fixtures and dependency checks for OCR script tests."""

import os
import sys

import pytest

# Add the scripts directory to sys.path so test modules can import the scripts
_scripts_dir = os.path.join(os.path.dirname(__file__), '..', '..', 'scripts')
sys.path.insert(0, os.path.abspath(_scripts_dir))

# ── Dependency probes ──────────────────────────────────────────

_HAS_PIL = False
_HAS_PYTESSERACT = False
_HAS_TESSERACT_BIN = False
_HAS_REQUESTS = False
_HAS_PDF2IMAGE = False

try:
    from PIL import Image  # noqa: F401
    _HAS_PIL = True
except ImportError:
    pass

try:
    import pytesseract  # noqa: F401
    _HAS_PYTESSERACT = True
except ImportError:
    pass

if _HAS_PYTESSERACT:
    try:
        pytesseract.get_tesseract_version()
        _HAS_TESSERACT_BIN = True
    except Exception:
        pass

try:
    import requests  # noqa: F401
    _HAS_REQUESTS = True
except ImportError:
    pass

try:
    from pdf2image import convert_from_path  # noqa: F401
    _HAS_PDF2IMAGE = True
except ImportError:
    pass

# ── pytest markers ──────────────────────────────────────────────

needs_pil = pytest.mark.skipif(not _HAS_PIL, reason='Pillow not installed')
needs_tesseract = pytest.mark.skipif(
    not (_HAS_PYTESSERACT and _HAS_TESSERACT_BIN),
    reason='Tesseract OCR engine not available',
)
needs_requests = pytest.mark.skipif(not _HAS_REQUESTS, reason='requests not installed')
needs_pdf2image = pytest.mark.skipif(not _HAS_PDF2IMAGE, reason='pdf2image not installed')

# Combined markers
needs_ocr = pytest.mark.skipif(
    not (_HAS_PIL and _HAS_PYTESSERACT and _HAS_TESSERACT_BIN),
    reason='Full OCR stack (Pillow + pytesseract + tesseract binary) not available',
)

# ── Fixtures ────────────────────────────────────────────────────

@pytest.fixture
def sample_image(tmp_path):
    """Create a minimal valid PNG image for OCR testing."""
    from PIL import Image
    img = Image.new('RGB', (100, 30), color='white')
    path = tmp_path / 'sample.png'
    img.save(str(path))
    return str(path)


@pytest.fixture
def sample_pdf(tmp_path):
    """Create a minimal single-page PDF (requires reportlab or similar).
    Returns None if PDF generation is not available."""
    try:
        from fpdf import FPDF
    except ImportError:
        return None
    pdf = FPDF()
    pdf.add_page()
    pdf.set_font('Helvetica', size=12)
    pdf.cell(text='Hello PDF Test')
    path = tmp_path / 'sample.pdf'
    pdf.output(str(path))
    return str(path)


@pytest.fixture
def text_image(tmp_path):
    """Create a PNG with text that Tesseract can read."""
    try:
        from PIL import Image, ImageDraw, ImageFont
    except ImportError:
        return None
    img = Image.new('RGB', (300, 50), color='white')
    draw = ImageDraw.Draw(img)
    try:
        font = ImageFont.truetype('arial.ttf', 24)
    except OSError:
        font = ImageFont.load_default()
    draw.text((10, 10), 'Hello OCR Test', fill='black', font=font)
    path = tmp_path / 'text_image.png'
    img.save(str(path))
    return str(path)
