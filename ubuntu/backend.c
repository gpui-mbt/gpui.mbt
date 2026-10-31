#define _POSIX_C_SOURCE 200809L
#include <assert.h>
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <wayland-client.h>
#include "text-input-v1-client-protocol.h"
/* Protocol requests are mocked, never invoked on the fixture's fake handles.
 * Actual callback/staging/queue/serial logic below is the production code. */
static void (*review206_activate_hook)(void);
static int calls[256], call_count, sent_serial, sent_cursor, sent_anchor;
static int sent_rectangle[4], destroyed_proxies;
static char sent_document[4097];
static struct zwp_text_input_v1 *new_proxy;
static void call(int operation) { assert(call_count < 256); calls[call_count++] = operation; }
static void mock_activate(struct zwp_text_input_v1 *p, struct wl_seat *s,
                          struct wl_surface *surface) { assert(p && s && surface); call(1); if (review206_activate_hook) review206_activate_hook(); }
static void mock_deactivate(struct zwp_text_input_v1 *p, struct wl_seat *s) { assert(p && s); call(2); }
static void mock_show(struct zwp_text_input_v1 *p) { assert(p); call(3); }
static void mock_hide(struct zwp_text_input_v1 *p) { assert(p); call(4); }
static void mock_surrounding(struct zwp_text_input_v1 *p, const char *text,
                             uint32_t cursor, uint32_t anchor) {
  assert(p); strcpy(sent_document, text); sent_cursor = (int)cursor;
  sent_anchor = (int)anchor; call(5);
}
static void mock_rectangle(struct zwp_text_input_v1 *p, int32_t x, int32_t y,
                           int32_t w, int32_t h) {
  assert(p); sent_rectangle[0] = x; sent_rectangle[1] = y;
  sent_rectangle[2] = w; sent_rectangle[3] = h; call(6);
}
static void mock_content(struct zwp_text_input_v1 *p, uint32_t hint, uint32_t purpose) {
  assert(p); assert(!hint && !purpose); call(7);
}
static void mock_commit(struct zwp_text_input_v1 *p, uint32_t serial) { assert(p); sent_serial = (int)serial; call(8); }
static void mock_destroy(struct zwp_text_input_v1 *p) { assert(p); ++destroyed_proxies; call(9); }
static struct zwp_text_input_v1 *mock_create(struct zwp_text_input_manager_v1 *p) { assert(p); call(10); return new_proxy; }
static int mock_listener(struct zwp_text_input_v1 *p,
                          const struct zwp_text_input_v1_listener *listener,
                          void *data) { assert(p && listener && data); call(11); return 0; }
static void mock_manager_destroy(struct zwp_text_input_manager_v1 *p) { assert(p); call(12); }
static void mock_keyboard_release(struct wl_keyboard *p) { assert(p); call(13); }
static void mock_keyboard_destroy(struct wl_keyboard *p) { assert(p); call(14); }
static void mock_seat_destroy(struct wl_seat *p) { assert(p); call(15); }
static void mock_surface_destroy(struct wl_surface *p) { assert(p); call(16); }
#define zwp_text_input_v1_activate mock_activate
#define zwp_text_input_v1_deactivate mock_deactivate
#define zwp_text_input_v1_show_input_panel mock_show
#define zwp_text_input_v1_hide_input_panel mock_hide
#define zwp_text_input_v1_set_surrounding_text mock_surrounding
#define zwp_text_input_v1_set_cursor_rectangle mock_rectangle
#define zwp_text_input_v1_set_content_type mock_content
#define zwp_text_input_v1_commit_state mock_commit
#define zwp_text_input_v1_destroy mock_destroy
#define zwp_text_input_manager_v1_create_text_input mock_create
#define zwp_text_input_v1_add_listener mock_listener
#define zwp_text_input_manager_v1_destroy mock_manager_destroy
#define wl_keyboard_release mock_keyboard_release
#define wl_keyboard_destroy mock_keyboard_destroy
#define wl_seat_destroy mock_seat_destroy
#define wl_surface_destroy mock_surface_destroy

#include "review206_backend_original.inc.c"
#include "review206_fixture.inc.c"
