#!/usr/bin/env python3
"""Compare two actual public Button APIs in an isolated, test-only workspace.

No package/runtime dependency from GPUI to Yami is added. Fixtures and expected
observations are versioned inputs; this runner never updates their expectations.
"""
from __future__ import annotations
import argparse
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import platform
import math
import re
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
DATA = ROOT / "tests/shared-ui-host"


def run(command, cwd):
    return subprocess.run(command, cwd=cwd, text=True, capture_output=True, check=False)


def revision(path):
    result = run(["git", "rev-parse", "HEAD"], path)
    if result.returncode:
        raise ValueError(f"not a Git checkout: {path}")
    return result.stdout.strip()


def validate_fixtures(document):
    if document.get("fixture_version") != "gp00-button-v1":
        raise ValueError("unsupported fixture version")
    fixtures = document.get("fixtures")
    if not isinstance(fixtures, list) or not fixtures:
        raise ValueError("fixtures must be nonempty")
    ids = set()
    for fixture in fixtures:
        name = fixture.get("id", "")
        if not re.fullmatch(r"[a-z][a-z0-9-]*", name) or name in ids:
            raise ValueError("fixture IDs must be unique lowercase identifiers")
        ids.add(name)
        if type(fixture.get("disabled")) is not bool:
            raise ValueError(f"{name}: disabled must be boolean")
        def check_bounds(bounds):
            if (
                not isinstance(bounds, list)
                or len(bounds) != 4
                or any(type(n) not in (int, float) or not math.isfinite(n) for n in bounds)
                or min(bounds[2:]) < 0
            ):
                raise ValueError(f"{name}: invalid geometry")
        check_bounds(fixture["bounds"])
        for step in fixture["steps"]:
            op = step.get("op")
            if op in ("down", "up"):
                if step.get("key") not in ("Enter", "Space", "Escape"):
                    raise ValueError(f"{name}: unsupported fixture key")
                if op == "down" and type(step.get("repeat", False)) is not bool:
                    raise ValueError(f"{name}: repeat must be boolean")
            elif op in ("pointer_down", "pointer_up"):
                if step.get("button", "Primary") not in ("Primary", "Secondary"):
                    raise ValueError(f"{name}: unsupported fixture mouse button")
                point = step.get("point", [10, 10])
                if (
                    not isinstance(point, list)
                    or len(point) != 2
                    or any(type(n) not in (int, float) or not math.isfinite(n) for n in point)
                ):
                    raise ValueError(f"{name}: invalid pointer geometry")
            elif op == "bounds":
                check_bounds(step["bounds"])
            elif op in ("focus", "loading"):
                if type(step.get("value")) is not bool:
                    raise ValueError(f"{name}: state must be boolean")
            elif op != "cancel":
                raise ValueError(f"{name}: unknown fixture operation {op}")
        for model in ("yami", "gpui"):
            expected = fixture["expected"][model]
            admitted = model == "yami" or min(fixture["bounds"][2:]) >= 24
            count = 1 + len(fixture["steps"]) if admitted else 1
            if len(expected) != count:
                raise ValueError(f"{name}: missing/extra {model} expectations")
            for row in expected:
                statuses = (
                    "accepted", "ok", "invalid-bounds", "caller-bounds",
                    "caller-focus", "unsupported",
                )
                if (
                    len(row) != 4
                    or type(row[0]) is not bool
                    or type(row[1]) is not bool
                    or row[2] not in statuses
                    or (row[3] is not None if model == "yami" else type(row[3]) is not bool)
                ):
                    raise ValueError(f"{name}: invalid {model} observation")
    return fixtures


def expression(step):
    op = step["op"]
    key = lambda: "@primitives." + step["key"]
    if op == "down":
        return f'Down({key()}, {str(step.get("repeat", False)).lower()})'
    if op == "up":
        return f"Up({key()})"
    if op in ("pointer_down", "pointer_up"):
        method = "PointerDown" if op == "pointer_down" else "PointerUp"
        x, y = step.get("point", [10, 10])
        return f'{method}(point({float(x)}, {float(y)}), @primitives.{step.get("button", "Primary")})'
    if op == "bounds":
        return "Bounds(rect(" + ", ".join(str(float(n)) for n in step["bounds"]) + "))"
    if op == "cancel":
        return "Cancel"
    if op in ("focus", "loading"):
        return f'{op.title()}({str(step["value"]).lower()})'
    raise ValueError(f"unknown fixture operation: {op}")


def parse_trace(stdout):
    rows = []
    for line in stdout.splitlines():
        parts = line.split("|")
        if len(parts) != 7:
            raise ValueError(f"unexpected probe output: {line!r}")
        case, model, index, activated, pressed, status, focused = parts
        if model not in ("yami", "gpui") or activated not in ("true", "false") or pressed not in ("true", "false") or focused not in ("true", "false", "unowned"):
            raise ValueError(f"invalid probe output: {line!r}")
        rows.append({"fixture": case, "model": model, "step": int(index), "activated": activated == "true", "pressed": pressed == "true", "status": status, "focused": None if focused == "unowned" else focused == "true"})
    return rows


def expected_trace(fixtures):
    rows = []
    for fixture in fixtures:
        for model in ("yami", "gpui"):
            expected = fixture["expected"][model]
            for i, observation in enumerate(expected):
                activated, pressed, status, focused = observation
                rows.append({"fixture": fixture["id"], "model": model, "step": i - 1, "activated": activated, "pressed": pressed, "status": status, "focused": focused})
    return rows


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--yami-source", required=True, type=Path)
    parser.add_argument("--target", choices=["js", "native", "wasm", "wasm-gc"], default="js")
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    yami = args.yami_source.resolve()
    for path in (yami / "moon.mod", yami / "native/moon.mod", ROOT / "moon.mod"):
        if not path.is_file():
            parser.error(f"missing source manifest: {path}")
    fixtures_doc = json.loads((DATA / "button-fixtures.json").read_text())
    fixtures = validate_fixtures(fixtures_doc)
    source = (DATA / "button_probe.mbt").read_text()
    calls = []
    for fixture in fixtures:
        bounds = ", ".join(str(float(n)) for n in fixture.get("bounds", [0, 0, 100, 40]))
        steps = ", ".join(expression(step) for step in fixture["steps"])
        calls.append(f'  run({json.dumps(fixture["id"])}, rect({bounds}), {str(fixture.get("disabled", False)).lower()}, [{steps}])')
    source += "\nfn main {\n" + "\n".join(calls) + "\n}\n"
    args.output.mkdir(parents=True, exist_ok=True)
    output = args.output.resolve()
    with tempfile.TemporaryDirectory(prefix="gpui-button-audit-") as directory:
        workspace = Path(directory)
        module = workspace / "probe"
        module.mkdir()
        (workspace / "moon.work").write_text("members = " + json.dumps([str(ROOT), str(yami), str(yami / "native"), str(module)]) + "\n")
        shutil.copytree(ROOT / "script", workspace / "script")
        (module / "moon.mod").write_text('name = "audit/shared_ui_buttons"\nversion = "0.0.0"\nimport { "f4ah6o/gpui@0.7.2", "f4ah6o/yami_kumo@0.1.1", "f4ah6o/yami_kumo_native@0.2.5", }\n')
        (module / "moon.pkg").write_text('import { "f4ah6o/gpui/controls/button", "f4ah6o/gpui/primitives", "f4ah6o/gpui/diagnostics", "f4ah6o/gpui/text", "f4ah6o/gpui/text_layout", "f4ah6o/yami_kumo", "f4ah6o/yami_kumo_native/components", }\noptions("is-main": true)\n')
        (module / "main.mbt").write_text(source)
        (output / "generated-probe.mbt").write_text(source)
        command = ["moon", "run", str(module), "--target", args.target, "--deny-warn"]
        started_at = datetime.now(timezone.utc).isoformat()
        result = run(command, workspace)
        finished_at = datetime.now(timezone.utc).isoformat()
    (output / "stdout.log").write_text(result.stdout)
    (output / "stderr.log").write_text(result.stderr)
    parse_error = None
    try:
        rows = parse_trace(result.stdout) if result.returncode == 0 else []
    except ValueError as error:
        rows = []
        parse_error = str(error)
    expected = expected_trace(fixtures)
    passed = result.returncode == 0 and rows == expected
    report = {
        "schema_version": 1,
        "fixture_version": fixtures_doc["fixture_version"],
        "profile": f"headless-button-public-api-{args.target}",
        "compiler_target": args.target,
        "backend_kind": "headless-model",
        "result": "PASS" if passed else "FAIL",
        "gpui_candidate_sha": revision(ROOT),
        "gpui_worktree_status": run(["git", "status", "--porcelain"], ROOT).stdout,
        "yami_worktree_status": run(["git", "status", "--porcelain"], yami).stdout,
        "gpui_tracked_diff_sha256": hashlib.sha256(run(["git", "diff", "HEAD"], ROOT).stdout.encode()).hexdigest(),
        "yami_dependency_sha": revision(yami),
        "fixture_sha256": hashlib.sha256((DATA / "button-fixtures.json").read_bytes()).hexdigest(),
        "probe_sha256": hashlib.sha256(source.encode()).hexdigest(),
        "runner_sha256": hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
        "toolchain": run(["moon", "version", "--all"], ROOT).stdout.strip(),
        "os": platform.platform(),
        "architecture": platform.machine(),
        "command": command,
        "started_at": started_at,
        "finished_at": finished_at,
        "exit_code": result.returncode,
        "parse_error": parse_error,
        "observations": rows,
        "expected_observations": expected,
        "runtime_gui": "NOT_RUN",
        "native_ime": "NOT_RUN",
        "assistive_technology": "NOT_RUN",
        "note": "Unsupported Yami loading is recorded, not treated as a supported capability. Bounds and focus are explicit caller adapters; no gesture state is reimplemented.",
    }
    (output / "report.json").write_text(json.dumps(report, indent=2) + "\n")
    print(f'{report["result"]}: {len(fixtures)} fixtures, {len(rows)} observations; {output / "report.json"}')
    if not passed:
        print(result.stderr)
        if parse_error:
            print(parse_error)
        for i, (actual, wanted) in enumerate(zip(rows, expected)):
            if actual != wanted:
                print(f"first mismatch {i}: actual={actual}; expected={wanted}")
                break
    return 0 if passed else 1


if __name__ == "__main__":
    raise SystemExit(main())
