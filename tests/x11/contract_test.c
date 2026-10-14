#define _POSIX_C_SOURCE 200809L
#include <X11/Xlib.h>
#include <X11/XKBlib.h>
#include <assert.h>
#include <limits.h>
#include <pthread.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* Headless checks of the private queue and public native contract. No display
 * is opened and no fabricated Display pointer reaches an Xlib function. Real
 * X11/GLES integration is exercised separately by the Xvfb test suite. */
static Display *forbidden_open_display(const char *name) {
  (void)name;
  fputs("headless contract test attempted to open an X display\n", stderr);
  abort();
}
static KeySym mock_symbol;
static Window mock_selection_owner;
static int mock_selection_writes, mock_selection_reads, mock_flushes;
static int mock_syncs, mock_handler_changes, mock_forwarded_errors;
static int mock_error_code;
static XID mock_error_resource;
static XErrorHandler mock_error_handler;
static XEvent mock_events[16];
static int mock_event_count;
static Bool mock_lookup_key_sym(Display *display, KeyCode code,
                                unsigned state, unsigned *consumed,
                                KeySym *symbol) {
  (void)display;
  (void)code;
  (void)state;
  *consumed = 0;
  *symbol = mock_symbol;
  return mock_symbol != NoSymbol;
}
static int mock_set_selection_owner(Display *display, Atom selection,
                                    Window owner, Time time) {
  (void)display;
  (void)selection;
  (void)time;
  ++mock_selection_writes;
  mock_selection_owner = owner;
  return 1;
}
static Window mock_get_selection_owner(Display *display, Atom selection) {
  (void)display;
  (void)selection;
  ++mock_selection_reads;
  return mock_selection_owner;
}
static int mock_flush(Display *display) {
  (void)display;
  ++mock_flushes;
  return 1;
}
static int previous_error_handler(Display *display, XErrorEvent *event) {
  (void)display;
  (void)event;
  ++mock_forwarded_errors;
  return 0;
}
static XErrorHandler mock_set_error_handler(XErrorHandler handler) {
  XErrorHandler previous = mock_error_handler;
  mock_error_handler = handler;
  ++mock_handler_changes;
  return previous;
}
static int mock_sync(Display *display, Bool discard) {
  (void)discard;
  ++mock_syncs;
  if (mock_error_code) {
    XErrorEvent error = {0};
    error.error_code = (unsigned char)mock_error_code;
    error.resourceid = mock_error_resource;
    mock_error_code = 0;
    assert(mock_error_handler);
    mock_error_handler(display, &error);
  }
  return 1;
}
static int mock_pending(Display *display) {
  (void)display;
  return mock_event_count;
}
static void remove_mock_event(int index, XEvent *out) {
  assert(index >= 0 && index < mock_event_count);
  *out = mock_events[index];
  --mock_event_count;
  memmove(mock_events + index, mock_events + index + 1,
          (size_t)(mock_event_count - index) * sizeof(mock_events[0]));
}
static int mock_next_event(Display *display, XEvent *out) {
  (void)display;
  remove_mock_event(0, out);
  return 0;
}
static int mock_peek_event(Display *display, XEvent *out) {
  (void)display;
  assert(mock_event_count > 0);
  *out = mock_events[0];
  return 0;
}
static Bool mock_check_if_event(Display *display, XEvent *out,
                                Bool (*predicate)(Display *, XEvent *, XPointer),
                                XPointer data) {
  for (int i = 0; i < mock_event_count; ++i) {
    if (predicate(display, &mock_events[i], data)) {
      remove_mock_event(i, out);
      return True;
    }
  }
  return False;
}
#define XOpenDisplay forbidden_open_display
#define XkbLookupKeySym mock_lookup_key_sym
#define XSetSelectionOwner mock_set_selection_owner
#define XGetSelectionOwner mock_get_selection_owner
#define XFlush mock_flush
#define XSync mock_sync
#define XSetErrorHandler mock_set_error_handler
#define XPending mock_pending
#define XNextEvent mock_next_event
#define XPeekEvent mock_peek_event
#define XCheckIfEvent mock_check_if_event
#include "../../x11/backend.c"
#undef XOpenDisplay
#undef XkbLookupKeySym
#undef XSetSelectionOwner
#undef XGetSelectionOwner
#undef XFlush
#undef XSync
#undef XSetErrorHandler
#undef XPending
#undef XNextEvent
#undef XPeekEvent
#undef XCheckIfEvent

enum { TEST_HOST = 731, TEST_WINDOW = 47, EVENT_CAPACITY = 10 };

static void fixture_init(struct host *h) {
  memset(h, 0, sizeof(*h));
  h->token = TEST_HOST;
  h->window = TEST_WINDOW;
  h->xwindow = 2047;
  h->owner = pthread_self();
  h->wake_fd = -1;
  h->width = 640;
  h->height = 480;
  h->scale = 1;
  h->direct_epoch = 1;
  h->direct_enabled = 1;
  h->direct_ever_enabled = 1;
  h->keyboard_focus_current = 1;
  mock_symbol = NoSymbol;
  mock_selection_owner = None;
  mock_selection_writes = mock_selection_reads = mock_flushes = 0;
  mock_syncs = mock_handler_changes = mock_forwarded_errors = 0;
  mock_error_code = 0;
  mock_error_resource = 0;
  mock_error_handler = previous_error_handler;
  mock_event_count = 0;
  assert(active == NULL);
  active = h;
}

static void fixture_drop(struct host *h) {
  assert(active == h);
  assert(mock_error_handler == previous_error_handler);
  assert(xerror_depth == 0 && error_host == NULL);
  xkb_compose_state_unref(h->compose);
  xkb_compose_table_unref(h->compose_table);
  xkb_context_unref(h->xkb);
  free(h->clipboard_owned);
  free(h->clipboard_result);
  active = NULL;
}

static void fixture_keyboard(struct host *h) {
  static const char compose[] = "<dead_acute> <e> : \"é\" eacute\n";
  h->xkb = xkb_context_new(XKB_CONTEXT_NO_FLAGS);
  assert(h->xkb);
  h->compose_table = xkb_compose_table_new_from_buffer(
      h->xkb, compose, sizeof(compose) - 1, "C.UTF-8",
      XKB_COMPOSE_FORMAT_TEXT_V1, XKB_COMPOSE_COMPILE_NO_FLAGS);
  assert(h->compose_table);
  h->compose = xkb_compose_state_new(h->compose_table,
                                    XKB_COMPOSE_STATE_NO_FLAGS);
  assert(h->compose);
}

static void emit_key(struct host *h, unsigned key, KeySym symbol,
                      int pressed, unsigned state) {
  XKeyEvent e = {0};
  e.keycode = key;
  e.state = state;
  mock_symbol = symbol;
  keyboard_key(h, &e, pressed);
}

static int next_v2(double *out, uint8_t *text, int capacity) {
  return gpui_x11_next_v2(GPUI_DIRECT_TEXT_ABI, TEST_HOST, out,
                          EVENT_CAPACITY, text, capacity);
}

static void enqueue_text(struct host *h, const uint8_t *bytes, int length,
                         int epoch) {
  assert(length >= 0 && length <= GPUI_DIRECT_TEXT_MAX_BYTES);
  int slot = (h->read + h->count) % QUEUE_CAPACITY;
  int before = h->count;
  event(h, 13, length, 0, 0);
  assert(h->count == before + 1);
  h->direct_queue[slot].epoch = epoch;
  h->direct_queue[slot].direct_origin = 1;
  h->direct_queue[slot].text_length = length;
  if (length)
    memcpy(h->direct_queue[slot].text, bytes, (size_t)length);
}

static void test_stale_handles(void) {
  double out[EVENT_CAPACITY] = {0};
  uint8_t text[1] = {'x'};
  assert(active == NULL);
  assert(gpui_x11_start(0) == -GPUI_INVALID);
  assert(gpui_x11_state(TEST_HOST) == 2);
  assert(gpui_x11_stop(TEST_HOST) == GPUI_OK);
  assert(gpui_x11_wake(TEST_HOST) == GPUI_STALE);
  assert(gpui_x11_exit(TEST_HOST) == GPUI_STALE);
  assert(gpui_x11_create(TEST_HOST, 640, 480, text, 1) == -GPUI_STALE);
  assert(gpui_x11_close(TEST_HOST, TEST_WINDOW) == GPUI_STALE);
  assert(gpui_x11_destroy(TEST_HOST, TEST_WINDOW) == GPUI_STALE);
  assert(gpui_x11_title(TEST_HOST, TEST_WINDOW, text, 1) == GPUI_STALE);
  assert(gpui_x11_size(TEST_HOST, TEST_WINDOW, 640, 480) == GPUI_STALE);
  assert(gpui_x11_metrics(TEST_HOST, TEST_WINDOW, out) == GPUI_STALE);
  assert(gpui_x11_dispatch(TEST_HOST, 0) == GPUI_STALE);
  assert(gpui_x11_next(TEST_HOST, out) == -GPUI_STALE);
  assert(next_v2(out, text, 1) == -GPUI_STALE);
  assert(gpui_x11_direct_keyboard_text_mode(TEST_HOST, TEST_WINDOW, 1) ==
         GPUI_STALE);
  assert(gpui_x11_direct_keyboard_text_epoch(TEST_HOST, TEST_WINDOW) ==
         -GPUI_STALE);
  assert(gpui_x11_direct_keyboard_text_active(TEST_HOST) == -GPUI_STALE);
  assert(gpui_x11_present(TEST_HOST, TEST_WINDOW, out, 5) == GPUI_STALE);
  assert(gpui_x11_present_v2(GPUI_MIXED_FRAME_ABI, TEST_HOST, TEST_WINDOW,
                            out, 5, NULL, 0) == GPUI_STALE);
  assert(gpui_x11_present_v3(GPUI_ORIGIN_FRAME_ABI, TEST_HOST, TEST_WINDOW,
                            out, 5, NULL, 0) == GPUI_STALE);
  assert(gpui_x11_recover(TEST_HOST, TEST_WINDOW) == GPUI_STALE);
  assert(gpui_x11_capability(TEST_HOST, 1) == GPUI_STALE);
  assert(gpui_x11_read_clipboard(TEST_HOST) == GPUI_STALE);
  assert(gpui_x11_clipboard_length(TEST_HOST) == -GPUI_STALE);
  assert(gpui_x11_clipboard_copy(TEST_HOST, text, 1) == GPUI_STALE);
  assert(gpui_x11_write_clipboard(TEST_HOST, text, 1) == GPUI_STALE);
  assert(gpui_x11_set_cursor(TEST_HOST, 0) == GPUI_STALE);
}

static void *wrong_thread(void *unused) {
  (void)unused;
  double out[EVENT_CAPACITY];
  uint8_t text[1];
  assert(gpui_x11_state(TEST_HOST) == 2);
  assert(gpui_x11_dispatch(TEST_HOST, 0) == GPUI_WRONG_THREAD);
  assert(gpui_x11_next(TEST_HOST, out) == -GPUI_WRONG_THREAD);
  assert(next_v2(out, text, 1) == -GPUI_WRONG_THREAD);
  assert(gpui_x11_direct_keyboard_text_mode(TEST_HOST, TEST_WINDOW, 0) ==
         GPUI_WRONG_THREAD);
  assert(gpui_x11_stop(TEST_HOST) == GPUI_WRONG_THREAD);
  return NULL;
}

static void test_owner_and_window_validation(void) {
  struct host h;
  fixture_init(&h);
  pthread_t thread;
  assert(pthread_create(&thread, NULL, wrong_thread, NULL) == 0);
  assert(pthread_join(thread, NULL) == 0);
  assert(gpui_x11_state(TEST_HOST + 1) == 2);
  assert(gpui_x11_direct_keyboard_text_epoch(TEST_HOST, TEST_WINDOW + 1) ==
         -GPUI_STALE);
  assert(gpui_x11_direct_keyboard_text_mode(TEST_HOST, TEST_WINDOW, 2) ==
         GPUI_INVALID);
  assert(gpui_x11_direct_keyboard_text_epoch(TEST_HOST, TEST_WINDOW) == 1);
  assert(gpui_x11_direct_keyboard_text_active(TEST_HOST) == 1);
  assert(h.direct_epoch == 1 && h.direct_enabled && !h.count);
  fixture_drop(&h);
}

static void test_buffer_validation_is_atomic(void) {
  struct host h;
  fixture_init(&h);
  uint8_t sample[] = {0xe6, 0x97, 0xa5};
  enqueue_text(&h, sample, sizeof(sample), h.direct_epoch);
  double out[EVENT_CAPACITY + 1];
  uint8_t text[GPUI_DIRECT_TEXT_MAX_BYTES + 1];
  memset(out, 0x5a, sizeof(out));
  memset(text, 0xa5, sizeof(text));
  unsigned char before_out[sizeof(out)], before_text[sizeof(text)];
  memcpy(before_out, out, sizeof(out));
  memcpy(before_text, text, sizeof(text));
  assert(gpui_x11_next_v2(1, TEST_HOST, out, EVENT_CAPACITY, text,
                          sizeof(text)) == -GPUI_UNSUPPORTED);
  assert(gpui_x11_next_v2(GPUI_DIRECT_TEXT_ABI, TEST_HOST, NULL,
                          EVENT_CAPACITY, text, sizeof(text)) == -GPUI_INVALID);
  assert(gpui_x11_next_v2(GPUI_DIRECT_TEXT_ABI, TEST_HOST, out, -1, text,
                          sizeof(text)) == -GPUI_INVALID);
  assert(gpui_x11_next_v2(GPUI_DIRECT_TEXT_ABI, TEST_HOST, out, 9, text,
                          sizeof(text)) == -GPUI_RESOURCE);
  assert(next_v2(out, NULL, 1) == -GPUI_INVALID);
  assert(next_v2(out, text, -1) == -GPUI_INVALID);
  assert(next_v2(out, NULL, 0) == -GPUI_RESOURCE);
  assert(next_v2(out, text, 2) == -GPUI_RESOURCE);
  assert(gpui_x11_next(TEST_HOST, out) == -GPUI_UNSUPPORTED);
  assert(h.count == 1 && h.read == 0);
  assert(memcmp(out, before_out, sizeof(out)) == 0);
  assert(memcmp(text, before_text, sizeof(text)) == 0);
  assert(next_v2(out, text, 3) == 1);
  assert(out[0] == 13 && out[6] == 0 && out[7] == 0 && out[8] == 3);
  assert(memcmp(text, sample, sizeof(sample)) == 0);
  assert(text[3] == 0xa5);
  assert(memcmp(&out[10], before_out + 10 * sizeof(double),
                sizeof(out[10])) == 0);
  assert(h.count == 0 && h.read == 1);
  memcpy(before_out, out, sizeof(out));
  memcpy(before_text, text, sizeof(text));
  assert(next_v2(out, text, sizeof(text)) == 0);
  assert(memcmp(out, before_out, sizeof(out)) == 0);
  assert(memcmp(text, before_text, sizeof(text)) == 0);
  fixture_drop(&h);
}

static void test_direct_payload_boundaries(void) {
  struct host h;
  fixture_init(&h);
  uint8_t sample[GPUI_DIRECT_TEXT_MAX_BYTES];
  memset(sample, 'x', sizeof(sample));
  enqueue_text(&h, sample, sizeof(sample), h.direct_epoch);
  double out[EVENT_CAPACITY];
  uint8_t text[GPUI_DIRECT_TEXT_MAX_BYTES + 1];
  memset(text, 0xa5, sizeof(text));
  assert(next_v2(out, text, GPUI_DIRECT_TEXT_MAX_BYTES) == 1);
  assert(out[8] == GPUI_DIRECT_TEXT_MAX_BYTES);
  assert(memcmp(text, sample, sizeof(sample)) == 0);
  assert(text[GPUI_DIRECT_TEXT_MAX_BYTES] == 0xa5);

  /* Corrupt private metadata is rejected without exposing partial bytes. */
  enqueue_text(&h, sample, 1, h.direct_epoch);
  int slot = h.read;
  h.direct_queue[slot].text_length = GPUI_DIRECT_TEXT_MAX_BYTES + 1;
  assert(next_v2(out, text, sizeof(text)) == -GPUI_INVALID);
  h.direct_queue[slot].text_length = 0;
  assert(next_v2(out, text, sizeof(text)) == -GPUI_INVALID);
  h.direct_queue[slot].text_length = 1;
  h.queue[slot][8] = 2;
  assert(next_v2(out, text, sizeof(text)) == -GPUI_INVALID);
  h.queue[slot][8] = 1;
  h.direct_queue[slot].text[0] = 0xc0;
  assert(next_v2(out, text, sizeof(text)) == -GPUI_INVALID);
  assert(h.count == 1 && h.read == slot);
  h.direct_queue[slot].text[0] = 'x';
  assert(next_v2(out, text, sizeof(text)) == 1);
  fixture_drop(&h);
}

static void test_utf8_scalar_validation(void) {
  static const struct {
    uint8_t bytes[4];
    int length, valid;
  } cases[] = {
      {{0x00}, 1, 1}, /* UTF8 validity is separate from clipboard NUL policy. */
      {{0x7f}, 1, 1},
      {{0xc2, 0x80}, 2, 1},
      {{0xdf, 0xbf}, 2, 1},
      {{0xe0, 0xa0, 0x80}, 3, 1},
      {{0xed, 0x9f, 0xbf}, 3, 1},
      {{0xee, 0x80, 0x80}, 3, 1},
      {{0xef, 0xbf, 0xbf}, 3, 1},
      {{0xf0, 0x90, 0x80, 0x80}, 4, 1},
      {{0xf4, 0x8f, 0xbf, 0xbf}, 4, 1},
      {{0x80}, 1, 0},
      {{0xbf}, 1, 0},
      {{0xc0, 0x80}, 2, 0},
      {{0xc1, 0xbf}, 2, 0},
      {{0xc2}, 1, 0},
      {{0xc2, 0x7f}, 2, 0},
      {{0xe0, 0x80, 0x80}, 3, 0},
      {{0xe0, 0x9f, 0xbf}, 3, 0},
      {{0xe1, 0x80}, 2, 0},
      {{0xed, 0xa0, 0x80}, 3, 0},
      {{0xed, 0xbf, 0xbf}, 3, 0},
      {{0xf0, 0x80, 0x80, 0x80}, 4, 0},
      {{0xf0, 0x8f, 0xbf, 0xbf}, 4, 0},
      {{0xf1, 0x80, 0x80}, 3, 0},
      {{0xf4, 0x90, 0x80, 0x80}, 4, 0},
      {{0xf5, 0x80, 0x80, 0x80}, 4, 0},
      {{0xff}, 1, 0},
  };
  assert(direct_utf8_valid(NULL, 0));
  for (size_t i = 0; i < sizeof(cases) / sizeof(cases[0]); ++i)
    assert(direct_utf8_valid(cases[i].bytes, cases[i].length) ==
           cases[i].valid);
}

static void test_stale_prefix_and_ring_order(void) {
  struct host h;
  fixture_init(&h);
  h.read = QUEUE_CAPACITY - 1;
  uint8_t stale[] = {'s'}, live[] = {0xc3, 0xa9};
  enqueue_text(&h, stale, sizeof(stale), h.direct_epoch);
  assert(advance_direct_epoch(&h) == GPUI_OK);
  enqueue_text(&h, live, sizeof(live), h.direct_epoch);
  event(&h, 7, 0, 12.5, 20.0);
  double out[EVENT_CAPACITY];
  uint8_t text[3];
  memset(out, 0x3c, sizeof(out));
  memset(text, 0xa5, sizeof(text));
  unsigned char before_out[sizeof(out)], before_text[sizeof(text)];
  memcpy(before_out, out, sizeof(out));
  memcpy(before_text, text, sizeof(text));
  assert(next_v2(out, text, 1) == -GPUI_RESOURCE);
  assert(h.read == QUEUE_CAPACITY - 1 && h.count == 3);
  assert(memcmp(out, before_out, sizeof(out)) == 0);
  assert(memcmp(text, before_text, sizeof(text)) == 0);
  assert(next_v2(out, text, 2) == 1);
  assert(out[0] == 13 && out[2] == 2 && out[8] == 2);
  assert(memcmp(text, live, sizeof(live)) == 0 && text[2] == 0xa5);
  assert(h.read == 1 && h.count == 1);
  assert(next_v2(out, NULL, 0) == 1);
  assert(out[0] == 7 && out[2] == 3 && out[6] == 12.5 && out[7] == 20.0);
  assert(h.count == 0);
  fixture_drop(&h);
}

static void test_disarm_and_legacy_guard(void) {
  struct host h;
  fixture_init(&h);
  double out[EVENT_CAPACITY];
  uint8_t text[1] = {'x'};
  event(&h, 7, 0, 8, 9);
  enqueue_text(&h, text, 1, h.direct_epoch);
  int epoch = h.direct_epoch;
  assert(gpui_x11_direct_keyboard_text_mode(TEST_HOST, TEST_WINDOW, 0) ==
         GPUI_OK);
  assert(h.direct_epoch > epoch);
  assert(gpui_x11_direct_keyboard_text_active(TEST_HOST) == 0);
  assert(gpui_x11_direct_keyboard_text_epoch(TEST_HOST, TEST_WINDOW) ==
         -GPUI_UNSUPPORTED);
  /* The guard scans past an ordinary head to queued direct-origin records. */
  assert(gpui_x11_next(TEST_HOST, out) == -GPUI_UNSUPPORTED);
  assert(h.count == 2 && h.read == 0);
  assert(next_v2(out, NULL, 0) == 1 && out[0] == 7);
  assert(next_v2(out, NULL, 0) == 0 && h.count == 0);
  event(&h, 3, 0, 0, 0);
  assert(gpui_x11_next(TEST_HOST, out) == 1 && out[0] == 3);
  assert(gpui_x11_next(TEST_HOST, out) == 0);
  fixture_drop(&h);
}

static void test_exhaustion_fails_closed(void) {
  struct host h;
  fixture_init(&h);
  uint8_t text[1] = {'x'};
  double out[EVENT_CAPACITY];
  enqueue_text(&h, text, 1, h.direct_epoch);
  h.direct_epoch = INT_MAX;
  assert(gpui_x11_direct_keyboard_text_mode(TEST_HOST, TEST_WINDOW, 0) ==
         GPUI_RESOURCE);
  assert(h.direct_exhausted && !h.direct_enabled);
  assert(gpui_x11_direct_keyboard_text_active(TEST_HOST) == 0);
  assert(gpui_x11_direct_keyboard_text_epoch(TEST_HOST, TEST_WINDOW) ==
         -GPUI_RESOURCE);
  assert(gpui_x11_direct_keyboard_text_mode(TEST_HOST, TEST_WINDOW, 1) ==
         GPUI_RESOURCE);
  assert(gpui_x11_next(TEST_HOST, out) == -GPUI_RESOURCE);
  assert(next_v2(out, text, sizeof(text)) == -GPUI_RESOURCE);
  assert(h.count == 1 && h.read == 0 && h.direct_epoch == INT_MAX);
  fixture_drop(&h);
}

static void test_queue_resource_bounds(void) {
  struct host h;
  fixture_init(&h);
  h.count = QUEUE_CAPACITY;
  event(&h, 7, 0, 0, 0);
  assert(h.count == QUEUE_CAPACITY && h.seq == 0 && h.error == GPUI_RESOURCE);
  h.count = 0;
  h.seq = INT_MAX;
  h.error = 0;
  event(&h, 7, 0, 0, 0);
  assert(h.count == 0 && h.seq == INT_MAX && h.error == GPUI_RESOURCE);
  fixture_drop(&h);
}

static void test_keyboard_repeat_and_rearm(void) {
  struct host h;
  fixture_init(&h);
  fixture_keyboard(&h);
  double out[EVENT_CAPACITY];
  uint8_t text[GPUI_DIRECT_TEXT_MAX_BYTES];
  emit_key(&h, 38, XKB_KEY_a, 1, 0);
  emit_key(&h, 38, XKB_KEY_a, 1, 0);
  emit_key(&h, 38, XKB_KEY_a, 0, 0);
  assert(next_v2(out, text, sizeof(text)) == 1);
  assert(out[0] == 11 && out[6] == 'a' && out[7] == 0);
  assert(next_v2(out, text, sizeof(text)) == 1);
  assert(out[0] == 13 && out[8] == 1 && text[0] == 'a');
  assert(next_v2(out, text, sizeof(text)) == 1);
  assert(out[0] == 11 && out[6] == 'a' && out[7] == 1);
  assert(next_v2(out, text, sizeof(text)) == 1 && out[0] == 13);
  assert(next_v2(out, text, sizeof(text)) == 1);
  assert(out[0] == 12 && out[7] == 0);
  assert(next_v2(out, text, sizeof(text)) == 0);

  /* No key, text or release from the old target crosses a re-arm boundary. */
  emit_key(&h, 38, XKB_KEY_a, 1, 0);
  assert(next_v2(out, text, sizeof(text)) == 1 && out[0] == 11);
  int epoch = h.direct_epoch;
  assert(gpui_x11_direct_keyboard_text_mode(TEST_HOST, TEST_WINDOW, 1) ==
         GPUI_OK);
  assert(h.direct_epoch > epoch);
  emit_key(&h, 38, XKB_KEY_a, 1, 0);
  emit_key(&h, 38, XKB_KEY_a, 0, 0);
  assert(next_v2(out, text, sizeof(text)) == 0);
  emit_key(&h, 38, XKB_KEY_a, 1, 0);
  assert(next_v2(out, text, sizeof(text)) == 1 && out[0] == 11 && out[7] == 0);
  assert(next_v2(out, text, sizeof(text)) == 1 && out[0] == 13);
  fixture_drop(&h);
}

static void test_keyboard_compose_and_controls(void) {
  struct host h;
  fixture_init(&h);
  fixture_keyboard(&h);
  double out[EVENT_CAPACITY];
  uint8_t text[GPUI_DIRECT_TEXT_MAX_BYTES];
  emit_key(&h, 48, XKB_KEY_dead_acute, 1, 0);
  emit_key(&h, 48, XKB_KEY_dead_acute, 0, 0);
  assert(next_v2(out, text, sizeof(text)) == 0);
  emit_key(&h, 26, XKB_KEY_e, 1, 0);
  assert(next_v2(out, text, sizeof(text)) == 1);
  assert(out[0] == 13 && out[8] == 2 && text[0] == 0xc3 && text[1] == 0xa9);
  emit_key(&h, 26, XKB_KEY_e, 1, 0); /* A consumed compose key stays consumed. */
  emit_key(&h, 26, XKB_KEY_e, 0, 0);
  assert(next_v2(out, text, sizeof(text)) == 0);

  unsigned shortcuts[] = {ControlMask, Mod4Mask};
  for (size_t i = 0; i < sizeof(shortcuts) / sizeof(shortcuts[0]); ++i) {
    emit_key(&h, 48, XKB_KEY_dead_acute, 1, 0);
    emit_key(&h, 48, XKB_KEY_dead_acute, 0, 0);
    emit_key(&h, 26, XKB_KEY_e, 1, shortcuts[i]);
    emit_key(&h, 26, XKB_KEY_e, 0, shortcuts[i]);
    assert(xkb_compose_state_get_status(h.compose) == XKB_COMPOSE_NOTHING);
    assert(next_v2(out, text, sizeof(text)) == 1 && out[0] == 11);
    assert(out[9] == (shortcuts[i] == ControlMask ? 2 : 8));
    assert(next_v2(out, text, sizeof(text)) == 1 && out[0] == 12);
    assert(next_v2(out, text, sizeof(text)) == 0);
  }

  emit_key(&h, 36, XKB_KEY_Return, 1, 0);
  emit_key(&h, 36, XKB_KEY_Return, 0, 0);
  assert(next_v2(out, text, sizeof(text)) == 1 && out[0] == 11);
  assert(next_v2(out, text, sizeof(text)) == 1 && out[0] == 12);
  assert(next_v2(out, text, sizeof(text)) == 0);
  emit_key(&h, 38, XKB_KEY_A, 1, ShiftMask);
  assert(next_v2(out, text, sizeof(text)) == 1 && out[0] == 11 && out[9] == 1);
  assert(next_v2(out, text, sizeof(text)) == 1 && out[0] == 13 && text[0] == 'A');
  fixture_drop(&h);
}

static void test_keyboard_pair_admission(void) {
  struct host h;
  fixture_init(&h);
  fixture_keyboard(&h);
  h.count = QUEUE_CAPACITY - 1;
  emit_key(&h, 38, XKB_KEY_a, 1, 0);
  assert(h.count == QUEUE_CAPACITY - 1 && h.seq == 0 &&
         h.error == GPUI_RESOURCE);
  fixture_drop(&h);

  fixture_init(&h);
  fixture_keyboard(&h);
  h.seq = INT_MAX - 1;
  emit_key(&h, 38, XKB_KEY_a, 1, 0);
  assert(h.count == 0 && h.seq == INT_MAX - 1 && h.error == GPUI_RESOURCE);
  fixture_drop(&h);
}

static void test_focus_revokes_direct_text(void) {
  struct host h;
  fixture_init(&h);
  fixture_keyboard(&h);
  emit_key(&h, 38, XKB_KEY_a, 1, 0);
  emit_key(&h, 48, XKB_KEY_dead_acute, 1, 0);
  assert(xkb_compose_state_get_status(h.compose) == XKB_COMPOSE_COMPOSING);
  int epoch = h.direct_epoch;
  XEvent focus = {0};
  focus.xfocus.type = FocusOut;
  focus.xfocus.window = h.xwindow;
  focus.xfocus.mode = NotifyNormal;
  focus.xfocus.detail = NotifyNonlinear;
  handle_event(&h, &focus);
  assert(!h.keyboard_focus_current && !h.direct_enabled);
  assert(h.direct_epoch > epoch);
  assert(xkb_compose_state_get_status(h.compose) == XKB_COMPOSE_NOTHING);
  assert(gpui_x11_direct_keyboard_text_epoch(TEST_HOST, TEST_WINDOW) ==
         -GPUI_UNSUPPORTED);
  double out[EVENT_CAPACITY];
  uint8_t text[GPUI_DIRECT_TEXT_MAX_BYTES];
  assert(next_v2(out, text, sizeof(text)) == 1 && out[0] == 6 && out[8] == 0);
  assert(next_v2(out, text, sizeof(text)) == 0);

  /* Native child/grab focus notifications must not manufacture editor focus. */
  focus.xfocus.type = FocusIn;
  focus.xfocus.detail = NotifyInferior;
  handle_event(&h, &focus);
  assert(!h.keyboard_focus_current && !h.count);
  focus.xfocus.detail = NotifyNonlinear;
  focus.xfocus.mode = NotifyGrab;
  handle_event(&h, &focus);
  assert(!h.keyboard_focus_current && !h.count);
  focus.xfocus.mode = NotifyNormal;
  handle_event(&h, &focus);
  assert(h.keyboard_focus_current && !h.direct_enabled);
  assert(next_v2(out, text, sizeof(text)) == 1 && out[0] == 6 && out[8] == 1);
  assert(gpui_x11_direct_keyboard_text_mode(TEST_HOST, TEST_WINDOW, 1) ==
         GPUI_OK);
  emit_key(&h, 38, XKB_KEY_a, 0, 0);
  emit_key(&h, 48, XKB_KEY_dead_acute, 0, 0);
  assert(next_v2(out, text, sizeof(text)) == 0);
  emit_key(&h, 26, XKB_KEY_e, 1, 0);
  assert(next_v2(out, text, sizeof(text)) == 1 && out[0] == 11);
  assert(next_v2(out, text, sizeof(text)) == 1 && out[0] == 13 && text[0] == 'e');
  fixture_drop(&h);
}

static void test_clipboard_copy_and_validation(void) {
  struct host h;
  fixture_init(&h);
  uint8_t original[] = {'a', '\n', 0xc3, 0xa9, 0xf0, 0x9f, 0x98, 0x80};
  uint8_t input[sizeof(original)], output[sizeof(original) + 1];
  memcpy(input, original, sizeof(input));
  assert(gpui_x11_write_clipboard(TEST_HOST, input, sizeof(input)) == GPUI_OK);
  assert(mock_selection_writes == 1 && mock_selection_reads == 1);
  assert(mock_selection_owner == h.xwindow);
  memset(input, 'z', sizeof(input));
  assert(gpui_x11_read_clipboard(TEST_HOST) == GPUI_OK);
  assert(gpui_x11_clipboard_length(TEST_HOST) == (int)sizeof(original));
  memset(output, 0xa5, sizeof(output));
  assert(gpui_x11_clipboard_copy(TEST_HOST, NULL, 1) == GPUI_INVALID);
  assert(gpui_x11_clipboard_copy(TEST_HOST, output, -1) == GPUI_INVALID);
  assert(gpui_x11_clipboard_copy(TEST_HOST, NULL, 0) == GPUI_RESOURCE);
  assert(gpui_x11_clipboard_copy(TEST_HOST, output, sizeof(original) - 1) ==
         GPUI_RESOURCE);
  for (size_t i = 0; i < sizeof(output); ++i) assert(output[i] == 0xa5);
  assert(gpui_x11_clipboard_copy(TEST_HOST, output, sizeof(original)) == GPUI_OK);
  assert(memcmp(output, original, sizeof(original)) == 0);
  assert(output[sizeof(original)] == 0xa5);

  uint8_t invalid[] = {0xed, 0xa0, 0x80};
  assert(gpui_x11_write_clipboard(TEST_HOST, invalid, sizeof(invalid)) ==
         GPUI_INVALID);
  assert(gpui_x11_write_clipboard(TEST_HOST, NULL, 1) == GPUI_INVALID);
  assert(gpui_x11_write_clipboard(TEST_HOST, original, -1) == GPUI_INVALID);
  uint8_t nul[] = {'a', 0, 'b'};
  assert(gpui_x11_write_clipboard(TEST_HOST, nul, sizeof(nul)) == GPUI_INVALID);
  /* Oversized lengths are rejected before scanning the supplied bytes. */
  uint8_t oversized = 0xff;
  assert(gpui_x11_write_clipboard(TEST_HOST, &oversized, CLIPBOARD_LIMIT + 1) ==
         GPUI_RESOURCE);
  assert(mock_selection_writes == 1);
  assert(h.clipboard_owned_length == sizeof(original));
  assert(memcmp(h.clipboard_owned, original, sizeof(original)) == 0);
  assert(gpui_x11_write_clipboard(TEST_HOST, NULL, 0) == GPUI_OK);
  assert(gpui_x11_read_clipboard(TEST_HOST) == GPUI_OK);
  assert(gpui_x11_clipboard_length(TEST_HOST) == 0);
  assert(gpui_x11_clipboard_copy(TEST_HOST, NULL, 0) == GPUI_OK);
  fixture_drop(&h);
}

static void test_selection_reacquisition(void) {
  struct host h;
  fixture_init(&h);
  h.clipboard = 3001;
  uint8_t text[] = {'a'};
  assert(gpui_x11_write_clipboard(TEST_HOST, text, sizeof(text)) == GPUI_OK);
  XEvent cleared = {0};
  cleared.xselectionclear.type = SelectionClear;
  cleared.xselectionclear.window = h.xwindow;
  cleared.xselectionclear.selection = h.clipboard;
  /* A delayed old clear event cannot undo a newer acquisition. */
  handle_event(&h, &cleared);
  assert(h.owns_clipboard && mock_selection_owner == h.xwindow);
  mock_selection_owner = h.xwindow + 1;
  handle_event(&h, &cleared);
  assert(!h.owns_clipboard);
  assert(gpui_x11_write_clipboard(TEST_HOST, text, sizeof(text)) == GPUI_OK);
  cleared.xselectionclear.selection = h.clipboard + 1;
  mock_selection_owner = None;
  handle_event(&h, &cleared);
  assert(h.owns_clipboard); /* An unrelated selection does not change CLIPBOARD. */
  fixture_drop(&h);
}

static void test_xerror_scope_restoration(void) {
  struct host h;
  fixture_init(&h);
  uint8_t original[] = {'a'}, replacement[] = {'b'};
  assert(gpui_x11_write_clipboard(TEST_HOST, original, 1) == GPUI_OK);
  assert(mock_syncs == 1 && mock_handler_changes == 2);
  assert(mock_error_handler == previous_error_handler && !xerror_depth);

  mock_error_code = BadWindow;
  mock_error_resource = h.xwindow;
  assert(gpui_x11_write_clipboard(TEST_HOST, replacement, 1) == GPUI_NATIVE);
  assert(h.error == GPUI_NATIVE && h.clipboard_owned[0] == 'a');
  assert(mock_error_handler == previous_error_handler && !xerror_depth);

  h.error = 0;
  mock_error_code = BadWindow;
  mock_error_resource = h.xwindow + 1;
  assert(gpui_x11_write_clipboard(TEST_HOST, replacement, 1) == GPUI_OK);
  assert(!h.error && h.clipboard_owned[0] == 'b');
  begin_xerror_scope(&h);
  XErrorEvent unrelated = {0};
  unrelated.error_code = BadAtom;
  xerror((Display *)(uintptr_t)0x1234, &unrelated);
  assert(mock_forwarded_errors == 1 && !h.error);
  end_xerror_scope(&h);
  assert(mock_error_handler == previous_error_handler && !xerror_depth);
  fixture_drop(&h);
}

static void test_pump_focus_delivery_barrier(void) {
  struct host h;
  fixture_init(&h);
  fixture_keyboard(&h);
  h.keyboard_focus_current = h.direct_enabled = 0;
  h.detectable_repeat = 1;
  memset(mock_events, 0, sizeof(mock_events));
  mock_events[0].xfocus.type = FocusIn;
  mock_events[0].xfocus.window = h.xwindow;
  mock_events[0].xfocus.mode = NotifyNormal;
  mock_events[0].xfocus.detail = NotifyNonlinear;
  mock_events[1].xkey.type = KeyPress;
  mock_events[1].xkey.window = h.xwindow;
  mock_events[1].xkey.keycode = 38;
  mock_events[2] = mock_events[1];
  mock_events[2].xkey.type = KeyRelease;
  mock_event_count = 3;
  mock_symbol = XKB_KEY_a;
  assert(pump(&h, 0) == GPUI_OK);
  assert(mock_event_count == 2 && h.count == 1);
  /* Repeated dispatch cannot pass already-queued focus notification. */
  assert(pump(&h, 0) == GPUI_OK && mock_event_count == 2 && h.count == 1);
  double out[EVENT_CAPACITY];
  uint8_t text[8];
  assert(next_v2(out, text, sizeof(text)) == 1 && out[0] == 6 && out[8] == 1);
  assert(gpui_x11_direct_keyboard_text_mode(TEST_HOST, TEST_WINDOW, 1) == GPUI_OK);
  assert(pump(&h, 0) == GPUI_OK && mock_event_count == 1 && h.count == 2);
  assert(next_v2(out, text, sizeof(text)) == 1 && out[0] == 11);
  assert(next_v2(out, text, sizeof(text)) == 1 && out[0] == 13 && text[0] == 'a');
  assert(pump(&h, 0) == GPUI_OK && mock_event_count == 0 && h.count == 1);
  assert(next_v2(out, text, sizeof(text)) == 1 && out[0] == 12);
  fixture_drop(&h);
}

static void test_clipboard_pump_preserves_input(void) {
  struct host h;
  fixture_init(&h);
  h.clipboard = 3001;
  h.owns_clipboard = 1;
  h.selection_wait = 1;
  mock_selection_owner = h.xwindow;
  memset(mock_events, 0, sizeof(mock_events));
  mock_events[0].xfocus.type = FocusOut;
  mock_events[0].xfocus.window = h.xwindow;
  mock_events[0].xfocus.mode = NotifyNormal;
  mock_events[0].xfocus.detail = NotifyNonlinear;
  mock_events[1].xselectionclear.type = SelectionClear;
  mock_events[1].xselectionclear.selection = h.clipboard;
  mock_events[1].xselectionclear.window = h.xwindow;
  mock_event_count = 2;
  assert(pump(&h, 0) == GPUI_OK);
  assert(mock_event_count == 1 && mock_events[0].type == FocusOut);
  assert(h.owns_clipboard && h.keyboard_focus_current && h.direct_enabled);
  assert(h.count == 0);
  h.selection_wait = 0;
  assert(pump(&h, 0) == GPUI_OK);
  assert(mock_event_count == 0 && h.count == 1);
  assert(!h.keyboard_focus_current && !h.direct_enabled);
  fixture_drop(&h);
}

static void test_destroy_notify_invalidates_window(void) {
  struct host h;
  fixture_init(&h);
  h.configured = h.owns_clipboard = 1;
  h.frame_pixels = malloc(4);
  assert(h.frame_pixels);
  h.frame_width = h.frame_height = h.frame_scale = 1;
  uint8_t text[] = {'a'};
  enqueue_text(&h, text, sizeof(text), h.direct_epoch);
  XEvent destroyed = {0};
  destroyed.xdestroywindow.type = DestroyNotify;
  destroyed.xdestroywindow.event = h.xwindow;
  destroyed.xdestroywindow.window = h.xwindow;
  handle_event(&h, &destroyed);
  assert(h.state == 1 && !h.window && !h.xwindow && !h.configured);
  assert(!h.direct_enabled && !h.keyboard_focus_current && !h.owns_clipboard);
  assert(!h.frame_pixels && !h.frame_width && !h.frame_height && !h.frame_scale);
  double out[EVENT_CAPACITY];
  assert(next_v2(out, text, sizeof(text)) == 1 && out[0] == 4 && out[1] == TEST_WINDOW);
  assert(next_v2(out, text, sizeof(text)) == 0);
  assert(gpui_x11_metrics(TEST_HOST, TEST_WINDOW, out) == GPUI_STALE);
  assert(gpui_x11_title(TEST_HOST, TEST_WINDOW, text, sizeof(text)) == GPUI_STALE);
  assert(gpui_x11_size(TEST_HOST, TEST_WINDOW, 640, 480) == GPUI_STALE);
  assert(gpui_x11_direct_keyboard_text_epoch(TEST_HOST, TEST_WINDOW) == -GPUI_STALE);
  handle_event(&h, &destroyed); /* Duplicate native destruction is inert. */
  assert(!h.count);
  fixture_drop(&h);
}

int main(void) {
  test_stale_handles();
  test_owner_and_window_validation();
  test_buffer_validation_is_atomic();
  test_direct_payload_boundaries();
  test_utf8_scalar_validation();
  test_stale_prefix_and_ring_order();
  test_disarm_and_legacy_guard();
  test_exhaustion_fails_closed();
  test_queue_resource_bounds();
  test_keyboard_repeat_and_rearm();
  test_keyboard_compose_and_controls();
  test_keyboard_pair_admission();
  test_focus_revokes_direct_text();
  test_clipboard_copy_and_validation();
  test_selection_reacquisition();
  test_xerror_scope_restoration();
  test_pump_focus_delivery_barrier();
  test_clipboard_pump_preserves_input();
  test_destroy_notify_invalidates_window();
  puts("GPUI_X11_CONTRACT status=passed display=none");
  return 0;
}
