/* Mock protocol requests and controlled callback injection only. The host,
 * retained FIFO, editor decoder and exact ACK below are production code. */
static int review207_fail_ack;
int32_t gpui_ack_retained_editor(int32_t token, int32_t window, int32_t sequence) {
  if (review207_fail_ack) { review207_fail_ack = 0; return GPUI_BUSY; }
  return gpui_review207_real_ack(token, window, sequence);
}
int32_t gpui_review207_setup(void) {
  if (active) return -1;
  struct host *h = calloc(1, sizeof(*h)); if (!h) return -1;
  h->token = 741; h->window = 51; h->owner = pthread_self(); h->wake_fd = -1;
  h->width = 640; h->height = 480; h->scale = 1;
  h->seat = (struct wl_seat *)(uintptr_t)101; h->seat_name = 117;
  h->surface = (struct wl_surface *)(uintptr_t)103;
  h->keyboard = (struct wl_keyboard *)(uintptr_t)102;
  h->keyboard_focus_current = 1;
  h->ime.manager = (struct zwp_text_input_manager_v1 *)(uintptr_t)104;
  h->ime.manager_name = 118;
  h->ime.proxy = (struct zwp_text_input_v1 *)(uintptr_t)105;
  h->ime.proxy_generation = 4;
  call_count = 0; review207_fail_ack = 0; review206_activate_hook = NULL;
  active = h; return h->token;
}
void gpui_review207_enter(void) { ime_enter(active, active->ime.proxy, active->surface); }
void gpui_review207_make_inactive(void) { active->ime.phase = IME_INACTIVE; active->keyboard_focus_current = 0; }
void gpui_review207_make_active(void) { active->ime.phase = IME_ACTIVE; active->keyboard_focus_current = 1; }
void gpui_review207_commit(void) { ime_commit_string(active, active->ime.proxy, 1, "日本"); }
void gpui_review207_commit_next(void) { ime_commit_string(active, active->ime.proxy, 1, "次"); }
void gpui_review207_nontext(void) { event(active, 1, 10, 20, 0); }
void gpui_review207_fail_next_ack(void) { review207_fail_ack = 1; }
void gpui_review207_wrong_seat(void) {
  int slot = active->read; assert(active->count && active->ime_queue[slot]);
  ++active->ime_queue[slot]->seat;
}
void gpui_review207_wrong_epoch(void) {
  int slot = active->read; assert(active->count && active->ime_queue[slot]);
  ++active->ime_queue[slot]->epoch;
}
int32_t gpui_review207_state(int32_t *fields, int32_t capacity, uint8_t *bytes, int32_t bytes_capacity) {
  struct host *h = active;
  if (!h || capacity < 8 || bytes_capacity <= h->ime.document_length) return -1;
  fields[0] = h->ime.document_length; fields[1] = h->ime.epoch;
  fields[2] = h->ime.phase; fields[3] = h->ime.latest_serial;
  fields[4] = h->count; fields[5] = h->seq; fields[6] = h->ime.rect[0]; fields[7] = h->error;
  memcpy(bytes, h->ime.document, (size_t)h->ime.document_length + 1);
  return 0;
}
void gpui_review207_finish(void) {
  struct host *h = active; if (!h) return;
  for (int i = 0; i < QUEUE_CAPACITY; ++i) ime_free_slot(h, i);
  active = NULL; free(h);
}
/* Fixture only: bind fake native host to the synthetic consumer window. */
void gpui_fixture_intent_set_window(int32_t window) { assert(active && window > 0); active->window = window; }
/* Fixture only: simulate native binding loss and restoration around reserve. */
void gpui_fixture_intent_set_requested(int32_t value) { assert(active); active->ime.requested = value; }
