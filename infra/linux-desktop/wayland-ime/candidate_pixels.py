"""Bounded two-row pixel diagnostic, not an IME candidate acceptance gate.

The panel rectangles and lookup values are supplied by the caller and are not
authenticated here. Two screenshots with opposite selections let OCR inspect
each row when it is *not* highlighted. The selected rows are checked from the
pixels independently of the lookup values. This cannot prove that either
screenshot is synchronized with the lookup message or that other rows match.
"""
import hashlib
import io
from pathlib import Path
import subprocess

from PIL import Image, ImageOps


class PixelEvidenceError(ValueError):
    pass


def require(value, message):
    if not value:
        raise PixelEvidenceError(message)


def _boxes(image, boxes):
    require(image.size == (960, 640), 'unexpected screenshot size')
    require(type(boxes) is list and len(boxes) == 2, 'two row boxes required')
    for box in boxes:
        require(type(box) is list and len(box) == 4 and
                all(type(x) is int for x in box), 'invalid row box')
        x0, y0, x1, y1 = box
        require(0 <= x0 < x1 <= image.width and 0 <= y0 < y1 <= image.height,
                'row box outside screenshot')
        require(24 <= x1-x0 <= 160 and 12 <= y1-y0 <= 48, 'unexpected row size')
    require(boxes[0][0] == boxes[1][0] and boxes[0][2] == boxes[1][2] and
            boxes[0][3] <= boxes[1][1], 'rows overlap or are not aligned')


def _lookup(value, selected):
    require(type(value) is dict and value.get('visible') is True and
            value.get('cursor_visible') is True, 'lookup is not visibly selected')
    rows = value.get('rows')
    require(type(rows) is list and len(rows) >= 2, 'lookup has fewer than two rows')
    first = rows[:2]
    require(all(type(row) is dict and type(row.get('text')) is str and
                type(row.get('selected')) is bool for row in first), 'invalid lookup rows')
    require([row['selected'] for row in first] == [selected == 0, selected == 1],
            'unexpected lookup selection')
    return [row['text'] for row in first]


def _blue_pixels(image, box):
    count = 0
    raw = image.crop(box).convert('RGB').tobytes()
    for r, g, b in zip(raw[0::3], raw[1::3], raw[2::3]):
        if b >= 160 and b >= r + 60 and b >= g + 35 and r < 125:
            count += 1
    return count


def _ocr_image(image, box):
    """Extract unselected dark text on light panel into a bounded binary PNG."""
    crop = image.crop(box).convert('L')
    require(sum(crop.histogram()[:160]) >= 12, 'row has no dark glyphs')
    binary = crop.point(lambda value: 0 if value < 160 else 255)
    padded = ImageOps.expand(binary, border=10, fill=255)
    scaled = padded.resize((padded.width * 4, padded.height * 4), Image.Resampling.BICUBIC)
    output = io.BytesIO()
    scaled.save(output, format='PNG')
    return output.getvalue()


def _normal(value):
    require(type(value) is str and len(value) <= 256, 'invalid OCR result')
    return ''.join(value.split())


def compare_two_rows(before, after, before_boxes, after_boxes,
                     before_lookup, after_lookup, ocr):
    """Compare two caller-cropped screenshots against decoded lookup rows.

    ``before`` selects row 2 and ``after`` selects row 1. The row text is OCR'd
    from the opposite, unselected screenshot. ``ocr`` consumes binary PNG bytes.
    Positive output only means these two manually bounded images matched; it
    does not qualify candidate_table_verified.
    """
    _boxes(before, before_boxes)
    _boxes(after, after_boxes)
    expected = _lookup(before_lookup, 1)
    require(_lookup(after_lookup, 0) == expected, 'lookup rows changed')
    require(all(text and not any(ch.isspace() for ch in text) for text in expected),
            'lookup text with whitespace is outside this diagnostic')
    before_blue = [_blue_pixels(before, b) for b in before_boxes]
    after_blue = [_blue_pixels(after, b) for b in after_boxes]
    require(before_blue[0] == 0 and before_blue[1] >= 25 and
            after_blue[0] >= 25 and after_blue[1] == 0, 'highlight differs from lookup')
    observed = [ocr(_ocr_image(before, before_boxes[0])),
                ocr(_ocr_image(after, after_boxes[1]))]
    require(all(_normal(a) == _normal(b) and _normal(a) for a, b in zip(observed, expected)),
            'OCR row differs from lookup')
    return {'status': 'partial', 'rows_checked': 2, 'observed': observed,
            'blue_pixels': [before_blue, after_blue], 'candidate_table_verified': False,
            'limitations': ['caller-supplied row boxes and lookup are unauthenticated',
                            'screen/lookup time and panel lifetime are not bound',
                            'remaining rows and disappearance are not checked']}


def compare_cleared_region(shown, after_commit, after_cancel, box, background):
    """Check one caller-selected panel region returns to an assumed background.

    This does not establish the panel's disappearance elsewhere on screen,
    authenticate a baseline, or bind any image to an input or panel frame.
    """
    require(all(im.size == (960, 640) for im in (shown, after_commit, after_cancel)),
            'unexpected screenshot size')
    require(type(box) is list and len(box) == 4 and all(type(v) is int for v in box),
            'invalid clear-region box')
    x0, y0, x1, y1 = box
    require(0 <= x0 < x1 <= 960 and 0 <= y0 < y1 <= 640 and
            64 <= x1-x0 <= 200 and 64 <= y1-y0 <= 200, 'invalid clear-region extent')
    require(type(background) is list and len(background) == 3 and
            all(type(v) is int and 0 <= v <= 255 for v in background), 'invalid background')
    reference = bytes(background) * ((x1-x0) * (y1-y0))
    active = shown.crop(box).convert('RGB').tobytes()
    changed = sum(active[i:i+3] != reference[i:i+3] for i in range(0, len(active), 3))
    require(changed >= 1000, 'shown region does not differ sufficiently from background')
    require(after_commit.crop(box).convert('RGB').tobytes() == reference and
            after_cancel.crop(box).convert('RGB').tobytes() == reference,
            'region did not return to the assumed background')
    return {'status': 'partial', 'candidate_table_verified': False,
            'region': box, 'shown_pixels_differing': changed,
            'limitations': ['region and background are caller-supplied',
                            'panel movement elsewhere is not excluded',
                            'captures are not bound to input or panel frames']}


class Tesseract:
    """Use an explicit local executable and exact traineddata; no network."""
    def __init__(self, executable, tessdata, model_sha256):
        self.executable = Path(executable)
        self.tessdata = Path(tessdata)
        require(self.executable.is_absolute() and self.executable.is_file(), 'OCR executable missing')
        model = self.tessdata / 'jpn.traineddata'
        require(self.tessdata.is_absolute() and model.is_file() and
                hashlib.sha256(model.read_bytes()).hexdigest() == model_sha256,
                'OCR model hash mismatch')

    def __call__(self, png):
        try:
            result = subprocess.run([str(self.executable), 'stdin', 'stdout', '--tessdata-dir',
                str(self.tessdata), '-l', 'jpn', '--psm', '7'], input=png,
                stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=10, check=True,
                env={'PATH': '/usr/bin:/bin', 'LC_ALL': 'C.UTF-8'})
            require(len(result.stdout) <= 1024, 'OCR output too long')
            return result.stdout.decode('utf-8', errors='strict').strip()
        except (OSError, subprocess.SubprocessError, UnicodeError) as error:
            raise PixelEvidenceError('OCR execution failed') from error
