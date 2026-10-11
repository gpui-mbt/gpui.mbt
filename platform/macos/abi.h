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
// 16 explicit renderer recreation, 17 toggle direct keyboard text,
// 18 query direct text epoch, 19 begin editor session, 20 update/ACK session,
// 21 cancel and rearm editor session, 22 end editor session, 23 read editor
// event, 24-27 test-only native input/source/frame/candidate queries,
// 28 publish accepted direct text mirror, 29 test dispatch receipt,
// 30 renderer grayscale text capability, 31-32 test input-source select/restore,
// 33 test text-window focus/session state.
// Integer fields: 0 result token, 1 event kind, 2 event token, 3 sequence,
// 4 modifiers, 5 button/key, 6 repeat, 7 ABI version, 8 UTF-8 output length, 9 host epoch,
// 100+i UTF-8 output byte i. Output remains owned by the shim until the next call.
// Number fields: 0 scale, 1 x, 2 y, 3 width, 4 height.
// Event kind 16 is scroll: x/y are logical pointer coordinates, width/height
// carry AppKit scrollingDeltaX/Y values (points for precise events, lines/rows
// otherwise), with no cross-platform unit normalization.
// Test-only E2E exports (GPUI_TESTING + GPUI_NATIVE_E2E=1): read metadata and
// copy the last completed Metal frame as top-left RGBA8.
int32_t gpui_macos_test_frame_meta_v1(int64_t window, double *output);
int32_t gpui_macos_test_frame_copy_v1(int64_t window, uint8_t *output,
                                      int32_t capacity);
int32_t gpui_macos_test_post_click_v1(int64_t window, double x, double y);
int32_t gpui_macos_test_post_escape_v1(int64_t window);
int32_t gpui_macos_test_post_key_v1(int64_t window, int32_t key_code,
                                    int32_t modifiers, const uint8_t *text,
                                    int32_t text_length);
// Copies bounded AppKit/CoreGraphics screen metadata into caller-owned storage.
// Returns a display count, or the negative diagnostics.ErrorCode ordinal + 1.
int32_t gpui_macos_display_snapshot_v1(int64_t host, double *records,
                                       int32_t capacity);
int32_t gpui_macos_display_snapshot(int64_t host, double *records,
                                    int32_t capacity);
#endif
