/* Opt-in, test-build-only chronology for NSTextInputClient and owner ACKs. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static unsigned gpui_test_ime_trace_count = 0;

static void gpui_test_ime_trace(GPWindow *w, NSString *phase, int key_code,
                                NSNumber *handled, BOOL fallback) {
  const char *flag = getenv("GPUI_FIELD_MACOS_IME_DISPATCH_TRACE");
  if (!flag || strcmp(flag, "1") || !w) return;
  if (gpui_test_ime_trace_count >= 256) return;
  if (gpui_test_ime_trace_count == 255) {
    fputs("GPUI_MACOS_IME_TRACE {\"schema_version\":1,\"phase\":\"truncated\",\"limit\":256}\n", stderr);
    fflush(stderr);
    gpui_test_ime_trace_count++;
    return;
  }
  GPView *view = (GPView *)w.window.contentView;
  NSMutableDictionary *row = [@{
    @"schema_version": @1, @"index": @(gpui_test_ime_trace_count++),
    @"phase": phase, @"uptime_ms": @((int64_t)(NSProcessInfo.processInfo.systemUptime * 1000.0)),
    @"window_id": @(w.token), @"host_epoch": @(host_epoch),
    @"session_epoch": @(w.sessionEpoch), @"dispatch_id": @(w.testingDispatchId),
    @"key_code": @(key_code), @"session_active": @(w.sessionActive),
    @"text_dispatch_active": @(w.textDispatchActive),
    @"input_context_present": @((view != nil) && (view.inputContext != nil)),
    @"marked": @(w.hasMarkedText), @"pending_unmark": @(w.pendingUnmark),
    @"awaiting_ack": @(w.sessionAwaitingAck), @"batch_delivered": @(w.batchDelivered),
    @"awaiting_sequence": @(w.awaitingSequence), @"last_batch_sequence": @(w.lastBatchSequence),
    @"last_presented_batch_sequence": @(w.lastPresentedBatchSequence),
    @"owner_revision": @(w.ownerRevision), @"callback_count": @(w.textCallbacks.count),
    @"deferred_text_error": @(w.deferredTextError), @"fallback_invoked": @(fallback),
    @"handled": handled ?: (id)NSNull.null,
  } mutableCopy];
  NSData *json = [NSJSONSerialization dataWithJSONObject:row options:NSJSONWritingSortedKeys error:nil];
  if (!json) return;
  fputs("GPUI_MACOS_IME_TRACE ", stderr);
  fwrite(json.bytes, 1, json.length, stderr);
  fputc('\n', stderr);
  fflush(stderr);
}
