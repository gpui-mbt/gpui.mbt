#!/usr/bin/env python3
"""Evidence-only interpretation of native AppKit/IME event ordering.

Every gate requires an observed witness; an absent stage is never a pass.
Diagnostic-preview-first runs NEVER qualify product acceptance.
"""
import argparse
import json
from pathlib import Path

PREFIX = "GPUI_MACOS_IME_DIAGNOSTIC_TRACE "
ABORT_PREFIX = "GPUI_MACOS_IME_ABORTED "
FAIL_PREFIX = "GPUI_MACOS_IME_ACCEPTANCE_FAIL"


class TraceError(ValueError):
    pass


def strict_json(line):
    def pairs(items):
        result = {}
        for key, value in items:
            if key in result:
                raise TraceError("duplicate JSON property: " + key)
            result[key] = value
        return result

    def constant(value):
        raise TraceError("non-finite JSON number: " + value)

    return json.loads(line, object_pairs_hook=pairs, parse_constant=constant)


def read_log(path):
    events, aborted, failed = [], [], []
    for line in Path(path).read_text(encoding="utf-8").splitlines():
        if line.startswith(PREFIX):
            obj = strict_json(line[len(PREFIX):])
            if type(obj) is not dict or obj.get("schema_version") != 1 or type(obj.get("sequence")) is not int \
                    or obj["sequence"] <= 0 or type(obj.get("monotonic_seconds")) not in (float, int) \
                    or not isinstance(obj.get("phase"), str):
                raise TraceError("malformed native trace observation")
            if events and (obj["sequence"] <= events[-1]["sequence"] or
                           obj["monotonic_seconds"] < events[-1]["monotonic_seconds"]):
                raise TraceError("native trace sequence or monotonic clock went backwards")
            events.append(obj)
        elif line.startswith(ABORT_PREFIX):
            aborted.append(strict_json(line[len(ABORT_PREFIX):]))
        elif FAIL_PREFIX in line:
            failed.append(line)
    return events, aborted, failed


def gate(result, detail):
    return {"status": result, "detail": detail}


def evaluate(summary, events, aborted, failed):
    result = {}
    final = summary.get("final_acceptance") or {}
    composition = summary.get("composition_checkpoint") or {}
    return_down = next((i for i, e in enumerate(events) if e["phase"] == "key_down_entry" and e.get("key_code") == 36), None)
    return_up = any(e["phase"] == "key_up_entry" and e.get("key_code") == 36 for e in events)
    route = [e for e in events[return_down or 0:] if e["phase"] == "input_interpret_result" and
             e.get("key_code") == 36] if return_down is not None else []
    commit = next(((i, e) for i, e in enumerate(events) if return_down is not None and i > return_down and
                   e["phase"] == "callback_enqueued" and e.get("callback_kind") == "commit"), None)
    ack = any(e["phase"] == "revision_ack" and type(e.get("ack_sequence")) is int and
              e["ack_sequence"] > 0 and commit is not None and i > commit[0]
              for i, e in enumerate(events))
    result["appkit_return_route"] = (
        gate("PASS", "Return down/up reached GPView and inputContext.handleEvent returned")
        if route and return_up else
        gate("FAIL", "Return arrived without a completed input-context route and key-up")
        if return_down is not None else gate("UNRUN", "no native Return delivery recorded")
    )
    result["return_commit"] = (
        gate("PASS", "real commit callback, queued native batch and revision ACK observed")
        if commit is not None and ack and final.get("commit_callbacks") == 1 and final.get("commit_count") == 1 else
        gate("FAIL", "Return was dispatched but callback/ACK/final commit proof is incomplete")
        if return_down is not None else gate("UNRUN", "Return was not observed")
    )
    escape_down = any(e["phase"] == "key_down_entry" and e.get("key_code") == 53 for e in events)
    cancelled = any(e["phase"] == "callback_enqueued" and e.get("callback_kind") == "cancelled" for e in events)
    result["escape_cancel"] = (
        gate("PASS", "Escape cancellation callback and final cancellation count observed")
        if escape_down and cancelled and final.get("cancel_callbacks", 0) >= 1 else
        gate("FAIL", "Escape arrived but cancellation was not proven") if escape_down else
        gate("UNRUN", "Escape not reached")
    )
    final_identity = final.get("final_frame_identity") or {}
    comp_identity = composition.get("frame_identity") or {}
    blur_ok = (final.get("focused") is False and final.get("composing") is False and
               type(final_identity.get("frame_revision")) is int and
               type(comp_identity.get("frame_revision")) is int and
               final_identity["frame_revision"] > comp_identity["frame_revision"] and
               final.get("final_frame_revision") == final_identity["frame_revision"])
    result["final_blur_frame"] = (
        gate("PASS", "blurred final frame was presented after composition")
        if blur_ok else gate("FAIL", "final frame did not satisfy presentation fence")
        if final else gate("UNRUN", "no final accepted frame")
    )
    restored = any(e["phase"] == "input_source_restored" and e.get("restored") is True for e in events)
    restored_abort = any(type(row) is dict and row.get("restored") is True and
                         row.get("session_closed") is True for row in aborted)
    result["input_source_restoration"] = (
        gate("PASS", "native input context restored (normal or bounded abort)")
        if restored or restored_abort else gate("FAIL", "restoration receipt explicitly failed")
        if aborted else gate("UNRUN", "no restoration receipt")
    )
    normal_cleanup = (summary.get("app_exit_code") == 0 and summary.get("status") == "passed"
                      and not failed and not aborted and restored)
    result["normal_cleanup"] = (
        gate("PASS", "app exited normally with restored input context")
        if normal_cleanup else gate("FAIL", "abnormal exit or acceptance failure")
        if aborted or failed or summary.get("cleanup") else gate("UNRUN", "no complete app exit proof")
    )
    screens = summary.get("screenshots") or {}
    pixels_ok = (set(screens) == {"initial", "composition", "final"} and
                 set(summary.get("text_roi_differences") or {}) ==
                 {"initial_to_composition", "composition_to_final", "initial_to_final"} and
                 summary.get("status") == "passed")
    result["window_pixel_frames"] = (
        gate("PASS", "all three own-window captures and ROI comparisons retained")
        if pixels_ok else gate("UNRUN", "three retained, validated pixel frames unavailable")
    )
    result["revision_ack"] = (
        gate("PASS", "commit callback precedes positive revision ACK")
        if ack else gate("FAIL", "commit callback has no later ACK") if commit else
        gate("UNRUN", "no committed batch to ACK")
    )
    if summary.get("diagnostic_preview_first"):
        for item in result.values():
            if item["status"] == "PASS":
                item["status"] = "DIAGNOSTIC_ONLY"
        qualification = "DIAGNOSTIC_ONLY"
    else:
        qualification = ("PASS" if all(item["status"] == "PASS" for item in result.values())
                         else "FAIL" if any(item["status"] == "FAIL" for item in result.values())
                         else "UNRUN")
    return {"schema_version": 1, "source": summary.get("source_before"),
            "qualification": qualification, "gates": result,
            "event_count": len(events), "historical_pr45_result": "FAIL_NOT_REUSED"}


def require_native_trace(path, final):
    events, _, _ = read_log(path)
    trial = evaluate({"final_acceptance": final, "status": "passed"}, events, [], [])
    for name in ("appkit_return_route", "return_commit", "revision_ack"):
        if trial["gates"][name]["status"] != "PASS":
            raise TraceError("native trace missing required witness for " + name)


def summarize(summary_path):
    summary_path = Path(summary_path)
    summary = strict_json(summary_path.read_text(encoding="utf-8"))
    log_path = summary_path.parent / "app.stdout.log"
    events, aborted, failed = read_log(log_path) if log_path.is_file() else ([], [], [])
    return evaluate(summary, events, aborted, failed)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--summary", required=True, type=Path)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args(argv)
    try:
        report = summarize(args.summary)
    except (OSError, ValueError, TypeError) as error:
        parser.exit(2, "trace contract failed: " + str(error) + "\n")
    output = args.output or args.summary.with_name("gates.json")
    output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print("qualification=" + report["qualification"] + " gates=" + str(output))
    return 0 if report["qualification"] == "PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())
