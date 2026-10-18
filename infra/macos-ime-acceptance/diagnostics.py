#!/usr/bin/env python3
"""Classify an observed AppKit/owner trace without inferring an IME root cause."""

import argparse
import json
from pathlib import Path

PREFIXES = {
    "GPUI_MACOS_IME_TRACE ": "native",
    "GPUI_MACOS_IME_DIAGNOSTIC_TRACE ": "legacy_route",
    "GPUI_MACOS_IME_DISPATCH_TRACE ": "legacy_dispatch",
    "GPUI_MACOS_IME_CALLBACK_DIAGNOSTIC_TRACE ": "legacy_callback",
    "GPUI_MACOS_IME_ACCEPTANCE ": "acceptance",
    "GPUI_MACOS_IME_ABORTED ": "abort",
}
MAX_EVENTS = 4096
MAX_LINE = 64 * 1024
RETURN_KEY = 36


def strict_json(payload):
    def unique(pairs):
        output = {}
        for name, value in pairs:
            if name in output:
                raise ValueError("duplicate trace JSON key: " + name)
            output[name] = value
        return output

    def finite_only(value):
        raise ValueError("non-finite trace number: " + value)

    return json.loads(payload, object_pairs_hook=unique, parse_constant=finite_only)


def collect_log(log):
    records, errors, failures = [], [], []
    for line_no, line in enumerate(Path(log).read_text(encoding="utf-8", errors="replace").splitlines(), 1):
        if line.startswith("GPUI_MACOS_IME_ACCEPTANCE_FAIL "):
            failures.append({"line": line_no, "message": line[:1024]})
        for prefix, kind in PREFIXES.items():
            if not line.startswith(prefix):
                continue
            if len(line) > MAX_LINE or len(records) >= MAX_EVENTS:
                errors.append("line " + str(line_no) + ": exceeded diagnostic bound")
                break
            try:
                value = strict_json(line[len(prefix):])
                if type(value) is not dict:
                    raise ValueError("record is not an object")
                records.append({"kind": kind, "line": line_no, "data": value})
            except (ValueError, TypeError) as error:
                errors.append("line " + str(line_no) + ": " + str(error))
            break
    return records, errors, failures


def _observed_return(records):
    native = [r for r in records if r["kind"] == "native"]
    route = [r for r in native if r["data"].get("key_code") == RETURN_KEY and
             r["data"].get("phase") in ("route_begin", "route_result", "key_up_done")]
    legacy = [r for r in records if r["kind"] == "legacy_route" and
              r["data"].get("key_code") == RETURN_KEY]
    legacy_dispatch = [r for r in records if r["kind"] == "legacy_dispatch" and
                       r["data"].get("key_code") == RETURN_KEY and
                       r["data"].get("phase") == "dispatch"]
    route_begin = next((r for r in route if r["data"]["phase"] == "route_begin"), None)
    route_result = next((r for r in route if r["data"]["phase"] == "route_result"), None)
    key_up = next((r for r in route if r["data"]["phase"] == "key_up_done"), None)
    if not route_begin:
        route_begin = next((r for r in legacy if r["data"].get("phase") == "return_route_begin"), None)
    if not route_result:
        route_result = next((r for r in legacy if r["data"].get("phase") == "return_route_result"), None)
    if not key_up:
        key_up = next((r for r in legacy_dispatch if r["data"].get("up_dispatched") is True), None)
    return route_begin, route_result, key_up


def analyze_log(path):
    path = Path(path)
    if not path.is_file():
        return {"integrity": "FAIL", "errors": ["log missing"], "return_dispatched_without_commit": False}
    records, errors, failures = collect_log(path)
    native = [r for r in records if r["kind"] == "native"]
    indices = [r["data"].get("index") for r in native if r["data"].get("phase") != "truncated"]
    if any(type(i) is not int or i < 0 for i in indices) or indices != sorted(set(indices)):
        errors.append("native diagnostic indices are absent, duplicated or out of order")
    return_begin, return_result, return_up = _observed_return(records)
    route_handled = return_result is not None and return_result["data"].get(
        "handled", return_result["data"].get("input_context_handled")) is True
    fallback = None if not return_result else return_result["data"].get(
        "fallback_invoked", return_result["data"].get("interpret_fallback_invoked"))
    if return_begin and return_result:
        begin_identity = return_begin["data"].get("session_epoch"), return_begin["data"].get("dispatch_id")
        result_identity = return_result["data"].get("session_epoch"), return_result["data"].get("dispatch_id")
        if begin_identity != result_identity or return_result["line"] <= return_begin["line"]:
            errors.append("Return input-context trace is reordered or has mismatched owner identity")
    callback_records = [r for r in native if r["data"].get("phase") in
                        ("callback_insert", "callback_unmark", "callback_marked", "callback_command")]
    legacy_callbacks = [r for r in records if r["kind"] == "legacy_callback" and
                        r["data"].get("callback_kind") in ("insert_text", "unmark_text") and
                        r["data"].get("stage") == "entry"]
    return_callbacks = [r for r in callback_records if return_begin and
                        r["line"] > return_begin["line"] and
                        r["data"].get("phase") in ("callback_insert", "callback_unmark")]
    return_callbacks += [r for r in legacy_callbacks if return_begin and r["line"] > return_begin["line"]]
    timeouts = [r for r in records if r["kind"] == "legacy_route" and
                r["data"].get("phase") == "operation_timeout" and
                r["data"].get("key_code") == RETURN_KEY]
    text_timeout = any("timed out waiting for the accepted IME operation observation" in
                       row["message"] for row in failures)
    timed_out = bool(timeouts) or text_timeout
    # A handled Return without a native callback is an observation, not proof
    # whether IMK, our pump, the producer or the client caused the omission.
    return_dispatched_without_commit = bool(
        return_begin and return_up and route_handled and timed_out and not return_callbacks
    )
    final = next((r["data"] for r in records if r["kind"] == "acceptance"), None)
    abort = next((r["data"] for r in records if r["kind"] == "abort"), None)
    acknowledged = [r["data"] for r in native if r["data"].get("phase") == "batch_acknowledged"]
    enqueued = [r["data"] for r in native if r["data"].get("phase") == "batch_enqueued"]
    limit = next((r["data"].get("iteration_limit") for r in timeouts), None)
    iterations = next((r["data"].get("loop_iterations") for r in timeouts), None)
    route_uptime = None if not return_begin else return_begin["data"].get("uptime_ms")
    end_uptime = next((r["data"].get("uptime_ms") for r in native
                       if r["data"].get("phase") == "key_up_done" and r["data"].get("key_code") == RETURN_KEY), None)
    timeline = path.with_name("timeline.ndjson")
    elapsed_return_to_failure_ms = None
    if timeline.is_file() and return_begin and failures:
        try:
            moments = {
                row["line"]: row["monotonic_ns"]
                for row in (strict_json(line) for line in timeline.read_text().splitlines())
                if type(row) is dict and type(row.get("line")) is int and
                   type(row.get("monotonic_ns")) is int
            }
            end = next((row["line"] for row in failures if row["line"] in moments), None)
            if end is not None and return_begin["line"] in moments:
                elapsed = moments[end] - moments[return_begin["line"]]
                if elapsed >= 0:
                    elapsed_return_to_failure_ms = round(elapsed / 1_000_000, 3)
                else:
                    errors.append("non-monotonic Return-to-timeout line timestamps")
        except (OSError, ValueError, TypeError, KeyError) as error:
            errors.append("invalid timeline evidence: " + str(error))
    return {
        "schema_version": 1,
        "integrity": "FAIL" if errors or any(r["data"].get("phase") in ("truncated", "truncated_ordinary") for r in native) else "PASS",
        "errors": errors,
        "trace_records": len(records),
        "native_callback_order": [{"phase": r["data"]["phase"], "line": r["line"],
                                   "index": r["data"].get("index"),
                                   "session_epoch": r["data"].get("session_epoch"),
                                   "owner_revision": r["data"].get("owner_revision"),
                                   "awaiting_ack": r["data"].get("awaiting_ack")}
                                  for r in callback_records],
        "return_route_observed": return_begin is not None,
        "return_key_up_observed": return_up is not None,
        "input_context_handled": route_handled if return_result else None,
        "interpret_fallback_invoked": fallback,
        "return_callback_observations": len(return_callbacks),
        "return_dispatched_without_commit": return_dispatched_without_commit,
        "return_timed_out": timed_out,
        "operation_loop_iterations": iterations,
        "operation_iteration_limit": limit,
        "return_route_uptime_ms": route_uptime,
        "return_keyup_uptime_ms": end_uptime,
        "elapsed_return_to_failure_ms": elapsed_return_to_failure_ms,
        "batch_enqueue_count": len(enqueued),
        "ack_count": len(acknowledged),
        "last_enqueue": enqueued[-1] if enqueued else None,
        "last_ack": acknowledged[-1] if acknowledged else None,
        "final_acceptance_observed": final is not None,
        "app_reported_commit_callbacks": None if not final else final.get("commit_callbacks"),
        "app_reported_cancel_callbacks": None if not final else final.get("cancel_callbacks"),
        "source_restored_observed": bool(
            any(r["data"].get("phase") == "source_restore_result" and
                r["data"].get("handled") is True for r in native) or
            (abort and abort.get("restored") is True and abort.get("session_closed") is True)
        ),
        "abort_receipt": abort,
        "failure_messages": failures,
        "root_cause": "undetermined",
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("app_log", type=Path)
    args = parser.parse_args()
    print(json.dumps(analyze_log(args.app_log), ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
