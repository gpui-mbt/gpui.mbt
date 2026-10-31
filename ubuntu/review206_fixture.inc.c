static int review206_nested_status;
static void review206_reentrant_native(void) {
  struct host *h = active;
  assert(h && h->retained_route_call && h->ime.phase == IME_ACTIVATING);
  review206_nested_status = gpui_retained_route_update(h->token, h->window,
      h->ime.epoch, (const uint8_t *)"replacement", 11, 11, 11, 90, 90, 1, 1);
  assert(review206_nested_status == -GPUI_BUSY);
}
int32_t gpui_review206_setup(void) {
  if (active) return -1;
  struct host *h = calloc(1, sizeof(*h)); if (!h) return -1;
  h->token = 741; h->window = 51; h->owner = pthread_self(); h->wake_fd = -1;
  h->width = 640; h->height = 480; h->scale = 1;
  h->terminal_retention = h->retained_route_claimed = h->retained_route_bound = 1;
  h->seat = (struct wl_seat *)(uintptr_t)101; h->seat_name = 117;
  h->surface = (struct wl_surface *)(uintptr_t)103;
  h->ime.proxy = (struct zwp_text_input_v1 *)(uintptr_t)105;
  h->ime.requested = h->ime.ever_enabled = 1; h->ime.epoch = 7;
  h->ime.phase = IME_INACTIVE; h->ime.panel_requested = 1;
  ime_set_document(h, (const uint8_t *)"old", 3, 3, 3, 1, 2, 3, 4);
  call_count = 0; review206_nested_status = 0; review206_activate_hook = NULL;
  active = h; return h->token;
}
void gpui_review206_focus(void) { active->keyboard_focus_current = 1; }
void gpui_review206_hook(void) { review206_activate_hook = review206_reentrant_native; }
void gpui_review206_enqueue(void) { event(active, 1, 10, 20, 0); }
int32_t gpui_review206_state(int32_t *fields, int32_t capacity, uint8_t *bytes, int32_t bytes_capacity) {
  struct host *h = active;
  if (!h || capacity < 13 || bytes_capacity <= h->ime.document_length) return -1;
  fields[0] = h->ime.document_length; fields[1] = h->ime.epoch;
  fields[2] = h->ime.phase; fields[3] = h->ime.latest_serial;
  fields[4] = h->count; fields[5] = h->seq; fields[6] = h->retained_route_call;
  for (int i = 0; i < 4; ++i) fields[7+i] = h->ime.rect[i];
  fields[11] = call_count; fields[12] = review206_nested_status;
  memcpy(bytes, h->ime.document, (size_t)h->ime.document_length + 1);
  return 0;
}
void gpui_review206_finish(void) {
  struct host *h = active; if (!h) return;
  for (int i = 0; i < QUEUE_CAPACITY; ++i) ime_free_slot(h, i);
  active = NULL; review206_activate_hook = NULL; free(h);
}
