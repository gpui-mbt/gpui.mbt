#ifndef GPUI_X11_BACKEND_H
#define GPUI_X11_BACKEND_H
#include <stdint.h>
/* Private, versioned ABI. All buffers are borrowed only for the call. Tokens
 * are monotonic integers resolved internally, never pointers. Owner-thread
 * only. Event buffer: kind, window, sequence, scale, width, height, x, y,
 * detail, mods. Key tags 11/12 use slot 6 for the Unicode scalar and
 * slot 7 for repeat (press: exact 0/1, release: 0). Text tag 13 uses zero
 * slots 6/7. Physical presses are 0; server repeats are 1, with no fake
 * release. Frame: viewport x/y/w/h/scale, followed by 19 doubles per quad:
 * bounds(4), RGBA(4), affine(6), opacity, intersected clip(4).
 */
#define GPUI_X11_ABI 1
#include "../platform/linux_renderer/abi.h"
int32_t gpui_x11_start(int32_t abi);
int32_t gpui_x11_stop(int32_t host);
int32_t gpui_x11_wake(int32_t host);
int32_t gpui_x11_exit(int32_t host);
int32_t gpui_x11_state(int32_t host);
int32_t gpui_x11_create(int32_t host, int32_t width, int32_t height,
                    const uint8_t *title, int32_t length);
int32_t gpui_x11_close(int32_t host, int32_t window);
int32_t gpui_x11_destroy(int32_t host, int32_t window);
int32_t gpui_x11_title(int32_t host, int32_t window, const uint8_t *title,
                   int32_t length);
int32_t gpui_x11_size(int32_t host, int32_t window, int32_t width, int32_t height);
int32_t gpui_x11_metrics(int32_t host, int32_t window, double *metrics);
int32_t gpui_x11_dispatch(int32_t host, int32_t timeout_ms);
int32_t gpui_x11_next(int32_t host, double *event);
/* Private copied direct-keyboard text ingress. `event` must be non-null and
 * have at least 10 doubles. Negative capacities, or NULL text with a positive
 * capacity, are invalid. NULL text with zero capacity admits non-text records;
 * a text record then returns Resource without consuming it. Text tag 13 stores
 * its 1..128 UTF-8 byte length in slot 8; only those bytes are copied (no NUL).
 * Invalid/insufficient buffers leave both outputs and the head untouched.
 * v1 next rejects active direct mode or any queued direct key/text record,
 * even after disarm, without consuming any record. */
int32_t gpui_x11_next_v2(int32_t abi, int32_t host, double *event,
                     int32_t event_capacity, uint8_t *text,
                     int32_t text_capacity);
/* An ever-armed host with an exhausted epoch cannot fall back to editor key
 * delivery: next v1/v2 report Resource and recovery requires a fresh host. */
int32_t gpui_x11_direct_keyboard_text_mode(int32_t host, int32_t window,
                                      int32_t enabled);
/* Positive nonwrapping epoch for a focused active target, negative status
 * otherwise. Active is 0/1 or negative status. No native handle is returned. */
int32_t gpui_x11_direct_keyboard_text_epoch(int32_t host, int32_t window);
int32_t gpui_x11_direct_keyboard_text_active(int32_t host);
/* IME/text-session composition is not supported by the X11 backend. */
int32_t gpui_x11_present(int32_t host, int32_t window, const double *data,
                     int32_t length);
/* v2 records: kind(0=quad,1=text), the same19 common fields as v1,
 * then UTF8 blob offset/length/font_size. Quad text fields are zero. Both
 * buffers are borrowed for this synchronous call; no pointers are retained. */
int32_t gpui_x11_present_v2(int32_t abi, int32_t host, int32_t window,
                        const double *data, int32_t length,
                        const uint8_t *text, int32_t text_length);
/* ABI3 keeps all23 existing fields and appends independent origin_x/y.
 * Kinds0quad/1legacyText require zero origin fields; kind2 is a plain run
 * clipped to common local bounds, with independent item-local text origin. */
int32_t gpui_x11_present_v3(int32_t abi, int32_t host, int32_t window,
                        const double *data, int32_t length,
                        const uint8_t *text, int32_t text_length);
/* Opt-in GPUI_NATIVE_E2E capture of the last completed native frame. */
int32_t gpui_x11_test_frame_metrics_v1(int32_t host, int32_t window,
                                   double *output);
int32_t gpui_x11_test_frame_copy_v1(int32_t host, int32_t window,
                                uint8_t *output, int32_t capacity);
int32_t gpui_x11_recover(int32_t host, int32_t window);
int32_t gpui_x11_capability(int32_t host, int32_t capability);
int32_t gpui_x11_read_clipboard(int32_t host);
int32_t gpui_x11_clipboard_length(int32_t host);
int32_t gpui_x11_clipboard_copy(int32_t host, uint8_t *bytes, int32_t capacity);
int32_t gpui_x11_write_clipboard(int32_t host, const uint8_t *bytes,
                             int32_t length);
int32_t gpui_x11_set_cursor(int32_t host, int32_t cursor);
#endif
