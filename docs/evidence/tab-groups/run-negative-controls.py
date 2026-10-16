#!/usr/bin/env python3
"""Reproduce bounded group-order mutation controls in a fresh non-Git copy.

No product source is mutated. Each compiled mutant must fail assertions (exit 2),
then restoring exact source bytes must pass. This is not an upstream oracle.
"""
from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile


def timestamp() -> str:
    return dt.datetime.now(dt.timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z")


def sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, default=Path(__file__).resolve().parents[3])
    parser.add_argument("--output-dir", type=Path, default=Path(__file__).resolve().parent)
    args = parser.parse_args()
    source = args.source.resolve()
    output = args.output_dir.resolve()
    output.mkdir(parents=True, exist_ok=True)
    work = Path(tempfile.mkdtemp(prefix="gpui-tab-group-controls-")) / "source"
    shutil.copytree(source, work, ignore=shutil.ignore_patterns(".git", "_build", "node_modules", ".mooncakes", "__pycache__"))
    command = ["moon", "test", "element", "--target", "js", "--deny-warn", "-j", "2"]
    records = []

    def run(name: str) -> dict:
        started = timestamp()
        result = subprocess.run(command, cwd=work, env=os.environ.copy(), text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, check=False)
        ended = timestamp()
        logfile = output / f"control-{name}.log"
        logfile.write_text(f"start={started}\ncommand={' '.join(command)}\n{result.stdout}exit_status={result.returncode}\nend={ended}\n")
        return {"name": name, "started_at": started, "ended_at": ended, "exit_code": result.returncode, "summary": re.findall(r"Total tests:.*", result.stdout), "log": logfile.name, "log_sha256": sha(logfile.read_bytes())}

    baseline = run("unmutated")
    if baseline["exit_code"] != 0:
        raise SystemExit("Unmutated copy failed; refusing to run controls")
    mutations = [
        ("flatten-group-paths", "element/focus_traversal.mbt", "  tab_path(order, left, order.left_path)\n  tab_path(order, right, order.right_path)", "  tab_path(order, left, order.left_path)\n  tab_path(order, right, order.right_path)\n  order.left_path.clear()\n  order.left_path.push(order.keys[left].index)\n  order.right_path.clear()\n  order.right_path.push(order.keys[right].index)"),
        ("omit-groups-own-prefix", "element/focus_traversal.mbt", "keys.push({ prefix, index: node.tab_index, })", "keys.push({ prefix: inherited, index: node.tab_index, })"),
        ("reverse-signed-component", "element/focus_traversal.mbt", "order.left_path[left_index] < order.right_path[right_index]", "order.left_path[left_index] > order.right_path[right_index]"),
        ("reverse-equal-path-preorder", "element/focus_traversal.mbt", "    left < right", "    left > right"),
        ("reverse-proper-prefix", "element/focus_traversal.mbt", "    left_index < right_index", "    left_index > right_index"),
        ("conflate-group-and-handle-index", "element/focus_traversal.mbt", "Some(index) => {\n        let slot = prefixes.length()\n        prefixes.push({ parent: inherited, index, })", "Some(_) => {\n        let slot = prefixes.length()\n        prefixes.push({ parent: inherited, index: node.tab_index, })"),
        ("retain-closed-group-prefix", "element/focus_traversal.mbt", "    let inherited = if ancestors.length() > 0 {\n      ancestors[ancestors.length() - 1].1\n    } else {\n      None\n    }", "    let inherited = if prefixes.length() > 0 {\n      Some(prefixes.length() - 1)\n    } else {\n      None\n    }"),
        ("drop-group-in-prepaint", "element/lifecycle.mbt", ".with_tab_group_index(element.tab_group_index)", ".with_tab_group_index(None)"),
        ("drop-group-in-scroll-reconstruction", "element/scroll_viewport.mbt", "tab_group_index: original.tab_group_index", "tab_group_index: None"),
    ]
    for name, relative, old, new in mutations:
        path = work / relative
        original = path.read_bytes()
        text = original.decode()
        if text.count(old) != 1:
            raise SystemExit(f"{name}: expected one exact replacement, found {text.count(old)}")
        mutated = text.replace(old, new).encode()
        try:
            path.write_bytes(mutated)
            record = run(name)
            record.update({"source": relative, "source_sha256": sha(original), "mutated_source_sha256": sha(mutated), "replacement_from": old, "replacement_to": new, "compiled_and_assertions_failed": record["exit_code"] == 2})
            records.append(record)
        finally:
            path.write_bytes(original)
    restored = run("restored")
    manifest = {"kind": "independent compiled mutated-implementation controls, not an upstream oracle", "target": "js", "command": command, "source_copy": str(work), "source_copy_is_git_checkout": False, "unmutated": baseline, "controls": records, "restored": restored, "all_compiled_controls_detected": all(item["compiled_and_assertions_failed"] for item in records), "restored_passed": restored["exit_code"] == 0}
    (output / "negative-controls.json").write_text(json.dumps(manifest, indent=2) + "\n")
    print(json.dumps({"unmutated": baseline["summary"], "controls": [{"name": item["name"], "exit_code": item["exit_code"], "summary": item["summary"]} for item in records], "restored": restored["summary"], "work_preserved_at": str(work)}, indent=2))
    return 0 if manifest["all_compiled_controls_detected"] and manifest["restored_passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
