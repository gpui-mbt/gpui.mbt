#!/usr/bin/python3
"""Replay a caller-selected two-row visual diagnostic; never sets a gate."""
import argparse
import hashlib
import json
from pathlib import Path

from PIL import Image
import candidate_pixels
import lookup_table


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def table_at(lines, number):
    if type(number) is not int or number < 12 or number > len(lines):
        raise ValueError('lookup line out of range')
    header = lines[number-12:number-1]
    body = lines[number-1].strip()
    if not body.startswith('Body: ') or not any("member -> 'UpdateLookupTable'" in x for x in header):
        raise ValueError('selected line is not a lookup body')
    return lookup_table.decode_gdbus_body(body.removeprefix('Body: '))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--dbus-log', type=Path, required=True)
    parser.add_argument('--body-lines', nargs=2, type=int, required=True)
    parser.add_argument('--before', type=Path, required=True)
    parser.add_argument('--after', type=Path, required=True)
    parser.add_argument('--before-boxes', required=True, help='two JSON [x0,y0,x1,y1] boxes')
    parser.add_argument('--after-boxes', required=True, help='two JSON [x0,y0,x1,y1] boxes')
    parser.add_argument('--after-commit', type=Path)
    parser.add_argument('--after-cancel', type=Path)
    parser.add_argument('--clear-box', help='JSON [x0,y0,x1,y1] box')
    parser.add_argument('--clear-background', help='JSON RGB triplet assumed by caller')
    parser.add_argument('--tesseract', type=Path, required=True)
    parser.add_argument('--tessdata', type=Path, required=True)
    parser.add_argument('--model-sha256', required=True)
    args = parser.parse_args()
    if args.dbus_log.stat().st_size > 64 * 1024 * 1024:
        raise ValueError('D-Bus log exceeds diagnostic bound')
    if args.body_lines[0] >= args.body_lines[1]:
        raise ValueError('lookup order reversed')
    clear_args = (args.after_commit, args.after_cancel, args.clear_box, args.clear_background)
    if any(value is not None for value in clear_args) and not all(value is not None for value in clear_args):
        raise ValueError('clear-region arguments must be supplied together')
    lines = args.dbus_log.read_text(encoding='utf-8').splitlines()
    ocr = candidate_pixels.Tesseract(args.tesseract, args.tessdata, args.model_sha256)
    with Image.open(args.before) as before, Image.open(args.after) as after:
        result = candidate_pixels.compare_two_rows(before, after,
            json.loads(args.before_boxes), json.loads(args.after_boxes),
            table_at(lines, args.body_lines[0]), table_at(lines, args.body_lines[1]), ocr)
        if args.after_commit is not None:
            with Image.open(args.after_commit) as commit, Image.open(args.after_cancel) as cancel:
                result['clear_region'] = candidate_pixels.compare_cleared_region(before, commit, cancel,
                    json.loads(args.clear_box), json.loads(args.clear_background))
    result['inputs_sha256'] = {'dbus_log': digest(args.dbus_log),
        'before': digest(args.before), 'after': digest(args.after),
        'tesseract': digest(args.tesseract), 'jpn.traineddata': args.model_sha256}
    if args.after_commit is not None:
        result['inputs_sha256'].update(after_commit=digest(args.after_commit),
                                       after_cancel=digest(args.after_cancel))
    result['body_lines'] = args.body_lines
    print(json.dumps(result, ensure_ascii=False, indent=2))


if __name__ == '__main__':
    main()
