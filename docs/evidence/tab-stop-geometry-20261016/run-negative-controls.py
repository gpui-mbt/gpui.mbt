#!/usr/bin/env python3
"""Compile bounded refresh mutants in a preserved non-Git copy below _build.

No product checkout files are mutated. Raw diagnostics are escaped JSON strings
so git diff --check can validate the complete committed evidence unchanged.
"""
from __future__ import annotations

import datetime as dt
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile


def sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def main() -> int:
    source = Path(__file__).resolve().parents[3]
    output = Path(__file__).resolve().parent
    (source / "_build").mkdir(exist_ok=True)
    work = Path(tempfile.mkdtemp(prefix="layout-bounds-controls-", dir=source / "_build")) / "source"
    shutil.copytree(source, work, ignore=shutil.ignore_patterns(".git", "_build", "node_modules", ".mooncakes", "__pycache__"))
    command = ["moon", "test", "element", "--target", "js", "--deny-warn", "-j", "2"]

    def run(name: str, argv: list[str] = command) -> dict:
        started = dt.datetime.now(dt.timezone.utc).isoformat()
        result = subprocess.run(argv, cwd=work, env=os.environ.copy(), text=True, capture_output=True)
        return {"name": name, "started_at_utc": started, "command": argv, "exit_code": result.returncode, "stdout": result.stdout, "stderr": result.stderr, "summaries": re.findall(r"Total tests:.*", result.stdout)}

    baseline = run("unmutated")
    if baseline["exit_code"]:
        raise SystemExit(json.dumps(baseline, indent=2))
    product = work / "element/layout_bounds.mbt"
    original = product.read_bytes()
    text = original.decode()
    mutations = [
        ("freeze-retained-bounds", "bounds: fresh[index].bounds", "bounds: self.nodes[index].bounds"),
        ("mint-fresh-tree-identity", "Ok({ ..self, nodes, })", "ElementTree::new(nodes)"),
        ("reacquire-same-focus-id", "Ok({ ..self, nodes, })", "let next : ElementTree = { ..self, nodes, }\n  match self.focused { None => Ok(next); Some(id) => next.with_focus(id) }"),
        ("skip-positional-id", "if retained.id != next.id ||", "if false ||"),
        ("skip-parent", "      retained.parent != next.parent ||\n", ""),
        ("skip-focusable", "      retained.focusable != next.focusable ||\n", ""),
        ("skip-tab-index", "      retained.tab_index != next.tab_index ||\n", ""),
        ("skip-tab-group-index", "      retained.tab_group_index != next.tab_group_index ||\n", ""),
        ("skip-tab-stop", "      retained.tab_stop != next.tab_stop ||\n", ""),
        ("skip-pointer-events", "      retained.pointer_events != next.pointer_events {", "      false {"),
        ("skip-root-viewport", "  if self.nodes[0].bounds != prepainted.viewport_bounds {\n    return Err(LayoutBoundsMismatch)\n  }\n", ""),
        ("allow-scroll", "    if retained.scroll_viewport is Some(_) || next.scroll_viewport is Some(_) {", "    if (retained.scroll_viewport is Some(_) || next.scroll_viewport is Some(_)) && retained.id != next.id {"),
        ("copy-fresh-background", "bounds: fresh[index].bounds,", "bounds: fresh[index].bounds, background: fresh[index].background,"),
        ("reject-paint-only-background-change", "    if retained.id != next.id ||", "    if retained.background != next.background { return Err(LayoutBoundsMismatch) }\n    if retained.id != next.id ||"),
        ("mutate-before-validation", "  for index = 0; index < self.nodes.length(); index = index + 1 {", "  self.nodes[1] = { ..self.nodes[1], bounds: fresh[1].bounds, }\n  for index = 0; index < self.nodes.length(); index = index + 1 {"),
    ]
    controls = []
    for name, old, new in mutations:
        count = text.count(old)
        expected = 2 if name == "mutate-before-validation" else 1
        if count != expected:
            raise SystemExit(f"{name}: expected {expected} replacement sites, found {count}")
        mutated = text.replace(old, new, 1).encode()
        try:
            product.write_bytes(mutated)
            record = run(name)
            record.update({"source": "element/layout_bounds.mbt", "original_sha256": sha(original), "mutated_sha256": sha(mutated), "replacement_from": old, "replacement_to": new, "compiled_and_tests_failed": record["exit_code"] == 2 and any("failed: 0" not in line for line in record["summaries"])})
            controls.append(record)
            print(name, record["exit_code"], record["summaries"], flush=True)
        finally:
            product.write_bytes(original)
    restored = run("restored")
    # Negative API controls prove callers cannot pass arbitrary rectangles or
    # fabricate a Prepainted value rather than running layout/prepaint.
    api_controls = []
    probe = work / "element/layout_bounds_external_probe_test.mbt"
    for name, body in [
        ("arbitrary-rectangles", "fn rejected(tree : @element.ElementTree, rectangles : Array[@primitives.Rect]) -> Result[@element.ElementTree, @element.ElementError] { tree.with_layout_bounds(rectangles) }\n"),
        ("fabricated-prepainted", "fn rejected(tree : @element.ElementTree, viewport : @primitives.Size, bounds : @primitives.Rect) -> @element.Prepainted { { tree, viewport, viewport_bounds: bounds, overflow: false } }\n"),
    ]:
        try:
            probe.write_text(body)
            record = run(name, ["moon", "test", "element", "--target", "js", "--build-only"])
            record["source"] = body
            record["rejected_at_compile_time"] = record["exit_code"] != 0 and "Error:" in record["stderr"]
            api_controls.append(record)
        finally:
            probe.unlink()
    manifest = {"kind": "compiled mutated-implementation controls and rejected API misuse, not an upstream execution oracle", "source_copy": str(work.relative_to(source)), "source_copy_is_git_checkout": False, "source_sha256": sha(original), "unmutated": baseline, "mutants": controls, "restored": restored, "api_controls": api_controls, "all_compiled_mutants_detected": all(x["compiled_and_tests_failed"] for x in controls), "all_api_misuse_rejected": all(x["rejected_at_compile_time"] for x in api_controls), "restored_passed": restored["exit_code"] == 0}
    (output / "negative-controls.json").write_text(json.dumps(manifest, indent=2) + "\n")
    return 0 if manifest["all_compiled_mutants_detected"] and manifest["all_api_misuse_rejected"] and manifest["restored_passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
