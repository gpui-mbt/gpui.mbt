/* Opt-in, test-build-only chronology for NSTextInputClient and owner ACKs. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define GPUI_TEST_IME_TRACE_MAX 256U
#define GPUI_TEST_IME_TRACE_ORDINARY_BUDGET 180U
static unsigned gpui_test_ime_trace_count = 0;
static unsigned gpui_test_ime_trace_ordinary_count = 0;
static BOOL gpui_test_ime_trace_ordinary_truncated = NO;

static void gpui_test_ime_trace(GPWindow *w, NSString *phase, int key_code,
                                NSNumber *handled, BOOL fallback) {
  const char *flag = getenv("GPUI_FIELD_MACOS_IME_DISPATCH_TRACE");
  if (!flag || strcmp(flag, "1") || !w) return;
  // Reserve slots for the actual Return route, commit callbacks, owner ACKs
  // and restoration even if geometry callbacks arrive in large bursts.
  BOOL critical = (key_code == 36 &&
                   ([phase isEqualToString:@"route_begin"] ||
                    [phase isEqualToString:@"route_result"] ||
                    [phase isEqualToString:@"key_up_done"])) ||
                  [phase isEqualToString:@"callback_insert"] ||
                  [phase isEqualToString:@"callback_unmark"] ||
                  [phase isEqualToString:@"batch_enqueued"] ||
                  [phase isEqualToString:@"batch_delivered"] ||
                  [phase isEqualToString:@"batch_acknowledged"] ||
                  [phase isEqualToString:@"source_restored"] ||
                  [phase isEqualToString:@"session_fence"];
  if (!critical && gpui_test_ime_trace_ordinary_count >= GPUI_TEST_IME_TRACE_ORDINARY_BUDGET) {
    if (!gpui_test_ime_trace_ordinary_truncated &&
        gpui_test_ime_trace_count < GPUI_TEST_IME_TRACE_MAX - 1) {
      fprintf(stderr,
        "GPUI_MACOS_IME_TRACE {\"schema_version\":1,\"index\":%u,\"phase\":\"truncated_ordinary\",\"limit\":180}\n",
        gpui_test_ime_trace_count++);
      fflush(stderr);
      gpui_test_ime_trace_ordinary_truncated = YES;
    }
    return;
  }
  if (gpui_test_ime_trace_count >= GPUI_TEST_IME_TRACE_MAX) return;
  if (gpui_test_ime_trace_count == GPUI_TEST_IME_TRACE_MAX - 1) {
    fprintf(stderr,
      "GPUI_MACOS_IME_TRACE {\"schema_version\":1,\"index\":%u,\"phase\":\"truncated\",\"limit\":256}\n",
      gpui_test_ime_trace_count++);
    fflush(stderr);
    return;
  }
  if (!critical) gpui_test_ime_trace_ordinary_count++;
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
