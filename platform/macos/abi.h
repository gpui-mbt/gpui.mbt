#ifndef GPUI_MACOS_ABI_H
#define GPUI_MACOS_ABI_H
#include <stdint.h>
// Versioned function table, borrowed only by the native loader. Payload bytes
// are borrowed for one call. No MoonBit address is retained by the dylib.
typedef struct {
  uint32_t abi_version, struct_size;
  int32_t (*call)(int32_t, int64_t, double, double, const uint8_t *, int32_t);
  int64_t (*integer)(int32_t);
  double (*number)(int32_t);
} GpuiApi;
// 0 success; otherwise diagnostics.ErrorCode ordinal + 1.
// Ops: 0 validate host epoch, 1 start, 2 stop, 3 create, 4 title, 5 size, 6 pump,
// 7 request-close, 8 destroy, 9 present, 10 wake, 11 request-exit,
// 12 cursor, 13 read clipboard, 14 write clipboard, 15 window metrics,
// 16 explicit renderer recreation, 17 accessory/background start (hidden windows),
// 18 order a background-host window behind others without activation,
// 19 enable/disable text composition, 20 set the logical caret rectangle
// (x/y arguments, width/height as little-endian uint32 bytes), 21 finish a
// composition (x != 0 commits, otherwise cancels).
// Integer fields: 0 result token, 1 event kind, 2 event token, 3 sequence,
// 4 modifiers, 5 button/key, 6 repeat, 7 ABI version, 8 UTF-8 output length, 9 host epoch,
// 100+i UTF-8 output byte i. Output remains owned by the shim until the next call.
// Number fields: 0 scale, 1 x, 2 y, 3 width, 4 height.
// Event kind 16 is scroll: x/y are logical pointer coordinates, width/height
// carry AppKit scrollingDeltaX/Y values (points for precise events, lines/rows
// otherwise), with no cross-platform unit normalization.
// Event kind 17 is text composition: code 0=start, 1=update, 2=commit,
// 3=cancel; width is the UTF-16 cursor inside the text payload.
// Test-only E2E exports (GPUI_TESTING + GPUI_NATIVE_E2E=1): read metadata and
// copy the last completed Metal frame as top-left RGBA8.
int32_t gpui_macos_test_frame_meta_v1(int64_t window, double *output);
int32_t gpui_macos_test_frame_copy_v1(int64_t window, uint8_t *output,
                                      int32_t capacity);
int32_t gpui_macos_test_post_click_v1(int64_t window, double x, double y);
int32_t gpui_macos_text_caret_screen_v1(int64_t window, double *output);
int32_t gpui_macos_test_post_escape_v1(int64_t window);
int32_t gpui_macos_test_post_key_v1(int64_t window, int32_t key_code,
                                    int32_t modifiers, const uint8_t *text,
                                    int32_t text_length);
int32_t gpui_macos_test_post_composition_v1(int64_t window, int32_t kind,
                                            int32_t cursor,
                                            const uint8_t *text,
                                            int32_t text_length);
// Copies bounded AppKit/CoreGraphics screen metadata into caller-owned storage.
// Returns a display count, or the negative diagnostics.ErrorCode ordinal + 1.
int32_t gpui_macos_display_snapshot_v1(int64_t host, double *records,
                                       int32_t capacity);
int32_t gpui_macos_display_snapshot(int64_t host, double *records,
                                    int32_t capacity);
// Portable text-input session. Op 1 begins and returns the epoch in fields[0],
// 2 replaces the logical caret rectangle from fields[0..3], 3 cancels the
// composition and returns a replacement epoch in fields[0], 4 ends the session.
// Records are ordered per session and tagged with the host-issued epoch.
int32_t gpui_macos_text_session_v1(int32_t op, int64_t window, int64_t epoch,
                                   double *fields, const uint8_t *bytes,
                                   int32_t length);
// One ordered record for an armed session: fields[0] present, [1] kind
// (1 preedit, 2 commit, 3 cancel, 5 focus lost), [2] sequence, [3] epoch,
// [4] UTF-16 cursor, [5] UTF-8 length; payload receives the text.
int32_t gpui_macos_text_next_v1(int64_t window, int64_t epoch,
                                int32_t timeout_ms, double *fields,
                                uint8_t *payload, int32_t capacity);
int32_t gpui_macos_text_available_v1(void);
#endif
