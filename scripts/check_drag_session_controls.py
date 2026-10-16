#!/usr/bin/env python3
"""Isolated, retained portable controls for DragSession (never mutates the repo).

Usage: MOON_HOME=... python3 scripts/check_drag_session_controls.py --output PATH
PATH must not exist. Retains source copies, build outputs, logs, and JSON ledger.
No dependency downloads, browser, native build, or Git writes are performed.
"""
from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[1]
PACKAGES = ("primitives", "layout", "scene", "element")


def replace_once(source: str, old: str, new: str) -> str:
    assert source.count(old) == 1, (old, source.count(old))
    return source.replace(old, new, 1)


def mutations(source: str) -> dict[str, str]:
    result = {}
    result["inclusive-threshold"] = replace_once(source, "dx * dx + dy * dy > 4.0", "dx * dx + dy * dy >= 4.0")
    result["release-activation"] = replace_once(source, """        Pending(..) => {
          self.cell.val.state = Idle
          Ok(Cancelled)
        }""", """        Pending(..) => {
          match self.dispatch(tree, @primitives.PointerMoved(position~), sources, targets) {
            Err(error) => Err(error)
            Ok(_) => if self.cell.val.state is Active(..) {
              self.dispatch(tree, event, sources, targets)
            } else {
              self.cell.val.state = Idle
              Ok(Cancelled)
            }
          }
        }""")
    early = replace_once(source, "mut in_predicate : Bool", "mut in_predicate : Bool\n  mut press_payload : T?")
    early = replace_once(early, "state: Idle, in_predicate: false,", "state: Idle, in_predicate: false, press_payload: None,")
    early = replace_once(early, "self.cell.val.state = Pending(source=id, origin=position)", "self.cell.val.press_payload = Some(source.payload)\n              self.cell.val.state = Pending(source=id, origin=position)")
    early = replace_once(early, "payload=binding.payload,", "payload=self.cell.val.press_payload.unwrap(),")
    result["press-time-payload"] = early
    result["predicate-before-consumption"] = replace_once(replace_once(source,
        "self.cell.val.state = Idle\n          match selected {", "match selected {"),
        "self.cell.val.in_predicate = false\n              if accepted", "self.cell.val.state = Idle\n              self.cell.val.in_predicate = false\n              if accepted")
    result["reject-retries-ancestor"] = replace_once(source, "Ok(Rejected(target.id))", """for id in tree.dispatch_input(event).bubble() {
                  if id != target.id && tree.drag_session_eligible(id, position) {
                    for next in targets {
                      if next.id == id {
                        let retry = match next.can_drop { None => true; Some(predicate) => predicate(payload) }
                        if retry { return Ok(Dropped(next.id, payload)) }
                      }
                    }
                  }
                }
                Ok(Rejected(target.id))""")
    result["double-delivery"] = replace_once(source, "self.cell.val.state = Idle\n          match selected {", "match selected {")
    result["error-clears-state"] = replace_once(source, "return Err(UnknownTargetBinding(targets[i].id))", "self.cell.val.state = Idle\n      return Err(UnknownTargetBinding(targets[i].id))")
    result["clamped-offset"] = replace_once(source, "Err(_) => return Err(CursorOffsetOverflow(source))", "Err(_) => @primitives.Point::new(0, 0).unwrap()")
    return result


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=False)
    moon = Path(os.environ.get("MOON_HOME", Path.home() / ".moon")) / "bin" / "moon"
    env = dict(os.environ)
    env["PATH"] = str(moon.parent) + os.pathsep + env.get("PATH", "")
    source = (ROOT / "element/drag_session.mbt").read_text()
    records = []

    def run(case: Path, label: str, command: list[str]) -> dict:
        started = dt.datetime.now(dt.timezone.utc).isoformat()
        proc = subprocess.run(command, cwd=case, env=env, capture_output=True, text=True)
        (case / f"{label}.stdout.log").write_text(proc.stdout)
        (case / f"{label}.stderr.log").write_text(proc.stderr)
        record = {"label": label, "command": command, "cwd": str(case), "started_at": started,
                  "finished_at": dt.datetime.now(dt.timezone.utc).isoformat(), "exit_code": proc.returncode}
        records.append(record)
        return record

    def copy_case(name: str, content: str) -> Path:
        case = output / name
        case.mkdir()
        (case / "moon.mod").write_text('name = "f4ah6o/gpui"\nversion = "0.0.0"\nsource = "."\n')
        for package in PACKAGES:
            shutil.copytree(ROOT / package, case / package)
        (case / "element/drag_session.mbt").write_text(content)
        return case

    results = []
    for name, content in {"unchanged-control": source, **mutations(source)}.items():
        if shutil.disk_usage(output).free < 512 * 1024 * 1024:
            raise RuntimeError("Stopping before disk exhaustion; retained all prior evidence")
        case = copy_case(name, content)
        build = run(case, "build", [str(moon), "test", "--target", "js", "--build-only", "element"])
        if build["exit_code"] != 0:
            results.append({"case": name, "passed": False, "reason": "compile failure is not a runtime mutation kill"})
            continue
        execution = run(case, "test", [str(moon), "test", "--target", "js", "element"])
        expected = execution["exit_code"] == 0 if name == "unchanged-control" else execution["exit_code"] == 2
        results.append({"case": name, "passed": expected, "compiled": True,
                        "runtime_exit_code": execution["exit_code"],
                        "source_sha256": hashlib.sha256(content.encode()).hexdigest()})
        print(name, "PASS" if expected else "FAIL", flush=True)

    misuse = {
        "foreign-source-type": ("""let session : @element.DragSession[String] = @element.DragSession::new()
  let _ = session.dispatch(tree, event, [@element.DragSource::new(1, 7)], [])""", "String"),
        "foreign-predicate-type": ("""let target : @element.DropTarget[String] = @element.DropTarget::new(1, can_drop=(value : Int) => value > 0)
  let _ = target""", "String"),
        "snapshot-restore": ("""let session : @element.DragSession[String] = @element.DragSession::new()
  session.restore(session.snapshot())""", "restore"),
    }
    for name, (body, diagnostic) in misuse.items():
        case = copy_case(name, source)
        probe = case / "misuse"
        probe.mkdir()
        (probe / "moon.pkg").write_text('import { "f4ah6o/gpui/element", "f4ah6o/gpui/primitives" }\n')
        (probe / "probe.mbt").write_text("fn misuse(tree : @element.ElementTree, event : @primitives.InputEvent) -> Unit {\n  " + body + "\n}\n")
        check = run(case, "check", [str(moon), "check", "--target", "js", "misuse"])
        stderr = (case / "check.stderr.log").read_text()
        passed = check["exit_code"] != 0 and diagnostic in stderr and "Error:" in stderr
        results.append({"case": name, "passed": passed, "expected": "compile-time misuse rejection", "exit_code": check["exit_code"]})
        print(name, "PASS" if passed else "FAIL", flush=True)
    (output / "commands.json").write_text(json.dumps(records, indent=2) + "\n")
    summary = {"scope": "Portable source/API controls only; no browser, native, Rust or runtime Any evidence", "source_sha256": hashlib.sha256(source.encode()).hexdigest(),
               "legacy_drag_sha256": hashlib.sha256((ROOT / "element/drag.mbt").read_bytes()).hexdigest(),
               "tests_sha256": hashlib.sha256((ROOT / "element/drag_session_test.mbt").read_bytes()).hexdigest(),
               "closure_sha256": {str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest() for package in PACKAGES for p in sorted((ROOT / package).glob("*")) if p.is_file()},
               "results": results, "passed": all(r["passed"] for r in results)}
    (output / "summary.json").write_text(json.dumps(summary, indent=2) + "\n")
    return 0 if summary["passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
