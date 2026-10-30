/* Experimental Ubuntu v1 transport. Included after direct input helpers so
 * every producer uses the same owner-thread ordered event queue. */
static int ime_boundary(const uint8_t *bytes, int length, int offset) {
  return offset >= 0 && offset <= length &&
         (offset == length || (bytes[offset] & 0xc0) != 0x80);
}
static int ime_copy_string(uint8_t *out, const char *input, int *length) {
  if (!input)
    return GPUI_INVALID;
  size_t size = strnlen(input, GPUI_IME_MAX_BYTES + 1);
  if (size > GPUI_IME_MAX_BYTES)
    return GPUI_RESOURCE;
  if (!direct_utf8_valid((const uint8_t *)input, (int)size))
    return GPUI_INVALID;
  memcpy(out, input, size + 1);
  *length = (int)size;
  return GPUI_OK;
}
static void ime_clear_stage(struct host *h) {
  memset(&h->ime.stage, 0, sizeof(h->ime.stage));
}
static void ime_clear_preedit_stage(struct host *h) {
  h->ime.stage.cursor_present = h->ime.stage.cursor = 0;
  h->ime.stage.style_count = 0;
  memset(h->ime.stage.styles, 0, sizeof(h->ime.stage.styles));
}
static void ime_clear_commit_stage(struct host *h) {
  h->ime.stage.delete_present = h->ime.stage.delete_index = h->ime.stage.delete_length = 0;
  h->ime.stage.position_present = h->ime.stage.index = h->ime.stage.anchor = 0;
}
static void ime_free_slot(struct host *h, int slot) {
  if (h->ime_queue[slot]) {
    free(h->ime_queue[slot]);
    h->ime_queue[slot] = NULL;
    h->ime_queue_bytes -= sizeof(struct ime_payload);
  }
}
static int ime_advance_epoch(struct host *h) {
  cancel_key_repeat(h);
  reset_compose(h);
  ime_clear_stage(h);
  if (h->ime.exhausted || h->ime.epoch == INT_MAX) {
    h->ime.exhausted = 1;
    h->ime.requested = 0;
    return GPUI_RESOURCE;
  }
  ++h->ime.epoch;
  return GPUI_OK;
}
static int ime_record(struct host *h, struct ime_payload *data) {
  if (!h->window || h->count == QUEUE_CAPACITY || h->seq == INT_MAX ||
      h->ime_queue_bytes > GPUI_IME_QUEUE_BYTES - sizeof(*data))
    return input_failure(h, GPUI_RESOURCE);
  struct ime_payload *copy = malloc(sizeof(*copy));
  if (!copy)
    return input_failure(h, GPUI_RESOURCE);
  *copy = *data;
  copy->window = h->window;
  copy->epoch = h->ime.wire_epoch;
  copy->seat = h->ime.wire_seat;
  copy->proxy_generation = h->ime.proxy_generation;
  int slot = (h->read + h->count) % QUEUE_CAPACITY;
  event(h, copy->kind, 0, 0, 0);
  h->queue[slot][4] = h->queue[slot][5] = h->queue[slot][9] = 0;
  h->ime_queue[slot] = copy;
  h->ime_queue_bytes += sizeof(*copy);
  return GPUI_OK;
}
/* Convert at admission, not read time: each portable event receives its own
 * monotonic sequence and retains its captured window across lifecycle fences. */
static int composition_record(struct host *h, int kind,
                              const struct ime_payload *source) {
  struct ime_payload data = {0};
  data.kind = kind;
  if (source && (kind == 27 || kind == 28)) {
    data.text_length = source->text_length;
    memcpy(data.text, source->text, (size_t)data.text_length);
    if (kind == 27) {
      data.cursor_present = 1;
      data.cursor = source->cursor_present && source->cursor >= 0
          ? source->cursor : source->text_length;
    }
  }
  int slot = (h->read + h->count) % QUEUE_CAPACITY;
  int status = ime_record(h, &data);
  if (!status) h->ime_queue[slot]->epoch = h->ime.epoch;
  return status;
}
static int composition_resolve(struct host *h, int commit) {
  if (!h->ime.composition_preview)
    return GPUI_OK;
  int status = composition_record(h, commit ? 28 : 29,
                                  &h->ime.composition_cache);
  if (!status) {
    h->ime.composition_preview = 0;
    memset(&h->ime.composition_cache, 0, sizeof(h->ime.composition_cache));
  }
  return status;
}
/* An application cancel means the logical editor target may already have
 * changed while earlier pointer/command events were being handled. Retract
 * only unread composition records; natural focus callbacks retain FIFO. */
static int composition_cancel_unread(struct host *h) {
  int revoked = 0;
  for (int i = 0; i < h->count; ++i) {
    int slot = (h->read + i) % QUEUE_CAPACITY;
    struct ime_payload *data = h->ime_queue[slot];
    if (data && data->kind >= 26 && data->window == h->window &&
        !data->composition_revoked) {
      data->composition_revoked = 1;
      revoked = 1;
    }
  }
  if (h->ime.composition_preview) return composition_resolve(h, 0);
  return revoked ? composition_record(h, 29, NULL) : GPUI_OK;
}
static int composition_transaction(struct host *h, struct ime_payload *data) {
  if (data->kind == 20) {
    if (!data->text_length)
      return composition_resolve(h, 0);
    if (!h->ime.composition_preview) {
      /* Reserve both records before publishing Start. */
      if (h->count > QUEUE_CAPACITY - 2 || h->seq > INT_MAX - 2 ||
          h->ime_queue_bytes > GPUI_IME_QUEUE_BYTES - 2 * sizeof(*data))
        return input_failure(h, GPUI_RESOURCE);
      int status = composition_record(h, 26, NULL);
      if (status) return status;
    }
    int status = composition_record(h, 27, data);
    if (!status) {
      h->ime.composition_cache = *data;
      h->ime.composition_preview = 1;
    }
    return status;
  }
  /* Bounded composers never apply surrounding deletion or cursor movement.
   * Reject the complete transaction and cancel the preview explicitly. */
  if (data->delete_present || data->position_present)
    return composition_resolve(h, 0);
  int status = data->text_length ? composition_record(h, 28, data)
                               : composition_resolve(h, 0);
  if (!status) h->ime.composition_preview = 0;
  return status;
}
static int ime_lifecycle_record(struct host *h, int kind) {
  if (h->ime.composition_enabled) {
    if (kind == 23 && h->terminal_retention && h->ime.composition_preview) {
      /* Retain an unresolved owner obligation; Left is not an OS Cancel. */
      if (!h->terminal_preview_pending) {
        h->terminal_preview = h->ime.composition_cache;
        h->terminal_preview.kind = 27;
        h->terminal_preview.window = h->window;
        h->terminal_preview.epoch = h->ime.epoch;
        h->terminal_preview.seat = h->ime.wire_seat;
        h->terminal_preview.proxy_generation = h->ime.proxy_generation;
        h->terminal_preview_watermark = h->seq;
        h->terminal_preview_pending = 1;
      }
      return GPUI_OK;
    }
    return kind == 23 ? composition_resolve(h, 0) : GPUI_OK;
  }
  if (h->ime.wire_epoch <= 0 || !h->ime.wire_seat || !h->window)
    return GPUI_OK;
  struct ime_payload data = {0};
  data.kind = kind;
  return ime_record(h, &data);
}
static int ime_pending_left_record(struct host *h) {
  int slot = (h->read + h->count) % QUEUE_CAPACITY;
  int status = ime_lifecycle_record(h, 23);
  if (!status && h->ime_queue[slot])
    h->ime_queue[slot]->epoch = h->ime.epoch;
  return status;
}
static int ime_current(struct host *h, struct zwp_text_input_v1 *proxy) {
  return proxy == h->ime.proxy && h->ime.proxy && h->state == 0 && !h->error &&
         !h->ime.exhausted && h->ime.requested &&
         h->ime.phase == IME_ACTIVE && h->window && h->seat_name &&
         h->ime.wire_window == h->window &&
         h->ime.wire_seat == h->seat_name &&
         h->ime.wire_epoch == h->ime.epoch;
}
static int ime_serial_current(struct host *h, uint32_t serial) {
  return serial && serial <= INT_MAX && h->ime.serial_floor > 0 &&
         serial >= (uint32_t)h->ime.serial_floor &&
         serial <= (uint32_t)h->ime.latest_serial;
}
static int ime_send_state(struct host *h) {
  if (h->ime.latest_serial == INT_MAX) {
    h->ime.exhausted = 1;
    h->ime.requested = 0;
    ime_clear_stage(h);
    return input_failure(h, GPUI_RESOURCE);
  }
  int serial = ++h->ime.latest_serial;
  zwp_text_input_v1_set_surrounding_text(h->ime.proxy,
      (const char *)h->ime.document, (uint32_t)h->ime.cursor,
      (uint32_t)h->ime.anchor);
  zwp_text_input_v1_set_cursor_rectangle(h->ime.proxy, h->ime.rect[0],
      h->ime.rect[1], h->ime.rect[2], h->ime.rect[3]);
  zwp_text_input_v1_set_content_type(h->ime.proxy,
      ZWP_TEXT_INPUT_V1_CONTENT_HINT_NONE, ZWP_TEXT_INPUT_V1_CONTENT_PURPOSE_NORMAL);
  zwp_text_input_v1_commit_state(h->ime.proxy, (uint32_t)serial);
  return GPUI_OK;
}
static int ime_activate(struct host *h) {
  if (!h->ime.requested || h->ime.phase != IME_INACTIVE)
    return GPUI_OK;
  if (!h->seat || !h->seat_name || !h->surface || !h->window ||
      !h->keyboard_focus_current || !h->ime.proxy)
    return GPUI_UNSUPPORTED;
  if (h->ime.latest_serial == INT_MAX) {
    h->ime.exhausted = 1;
    h->ime.requested = 0;
    return input_failure(h, GPUI_RESOURCE);
  }
  h->ime.serial_floor = h->ime.latest_serial + 1;
  h->ime.wire_epoch = h->ime.epoch;
  h->ime.wire_window = h->window;
  h->ime.wire_seat = h->seat_name;
  h->ime.phase = IME_ACTIVATING;
  ime_clear_stage(h);
  h->ime.modifiers_valid = h->ime.forwarded_modifiers = 0;
  h->ime.known_modifier_mask = 0;
  memset(h->ime.modifier_masks, 0, sizeof(h->ime.modifier_masks));
  zwp_text_input_v1_activate(h->ime.proxy, h->seat, h->surface);
  if (h->ime.panel_requested)
    zwp_text_input_v1_show_input_panel(h->ime.proxy);
  else
    zwp_text_input_v1_hide_input_panel(h->ime.proxy);
  return ime_send_state(h);
}
static void ime_clear_modifier_drain(struct host *h) {
  h->ime.drain_modifiers_sequence = h->ime.drain_release_sequence = 0;
  h->ime.drain_release_seen = 0;
  h->ime.drain_serial_floor = h->ime.drain_latest_serial = 0;
}
static int ime_modifier_symbol(xkb_keysym_t symbol) {
  switch (symbol) {
  case XKB_KEY_Shift_L: case XKB_KEY_Shift_R:
  case XKB_KEY_Control_L: case XKB_KEY_Control_R:
  case XKB_KEY_Alt_L: case XKB_KEY_Alt_R:
  case XKB_KEY_Meta_L: case XKB_KEY_Meta_R:
  case XKB_KEY_Super_L: case XKB_KEY_Super_R:
  case XKB_KEY_Hyper_L: case XKB_KEY_Hyper_R:
  case XKB_KEY_Mode_switch: case XKB_KEY_ISO_Level3_Shift:
  case XKB_KEY_ISO_Level5_Shift:
  case XKB_KEY_Caps_Lock: case XKB_KEY_Shift_Lock:
  case XKB_KEY_Num_Lock: case XKB_KEY_Scroll_Lock:
  case XKB_KEY_ISO_Level3_Latch: case XKB_KEY_ISO_Level3_Lock:
  case XKB_KEY_ISO_Level5_Latch: case XKB_KEY_ISO_Level5_Lock:
    return 1;
  default:
    return 0;
  }
}
static void ime_deactivate(struct host *h) {
  if (h->ime.proxy && h->seat && h->ime.phase != IME_INACTIVE &&
      h->ime.phase != IME_DEACTIVATING) {
    /* Stock IBus1.5.32 reset does nothing. Re-enter is the verified fence.
     * Never send another activate until this exact proxy's leave arrives. */
    ime_clear_modifier_drain(h);
    h->ime.phase = IME_DEACTIVATING;
    zwp_text_input_v1_deactivate(h->ime.proxy, h->seat);
    zwp_text_input_v1_hide_input_panel(h->ime.proxy);
  }
}
static void ime_finish_modifier_drain(struct host *h) {
  if (h->ime.phase != IME_DRAINING_MODIFIERS || !h->ime.requested ||
      !h->ime.proxy || !h->keyboard || !h->seat || !h->surface ||
      !h->keyboard_focus_current || h->state || h->error ||
      h->ime.wire_window != h->window || h->ime.wire_seat != h->seat_name ||
      !h->ime.drain_release_seen || !h->ime.keyboard_modifiers_known ||
      h->ime.keyboard_modifiers_sequence <= h->ime.drain_modifiers_sequence ||
      h->ime.keyboard_modifiers_sequence <= h->ime.drain_release_sequence ||
      h->ime.keyboard_depressed || h->ime.keyboard_latched)
    return;
  /* This fresh current-keyboard clear traversed the still-live old grab after
   * the genuine modifier release. Never synthesize a key or modifiers event. */
  h->ime.forwarded_modifiers = 0;
  ime_deactivate(h);
}
static void ime_observe_modifier_release(struct host *h, uint32_t state,
                                         xkb_keysym_t symbol) {
  if (h->ime.phase == IME_DRAINING_MODIFIERS && h->ime.requested &&
      h->ime.proxy && h->keyboard_focus_current && !h->state && !h->error &&
      h->ime.wire_window == h->window && h->ime.wire_seat == h->seat_name &&
      state == WL_KEYBOARD_KEY_STATE_RELEASED && ime_modifier_symbol(symbol)) {
    h->ime.drain_release_seen = 1;
    h->ime.drain_release_sequence = h->ime.keyboard_modifiers_sequence;
  }
}
static void ime_observe_keyboard_modifiers(struct host *h, uint32_t depressed,
                                           uint32_t latched) {
  if (!h->ime.ever_enabled) {
    h->ime.keyboard_modifiers_known = 1;
    h->ime.keyboard_depressed = depressed;
    h->ime.keyboard_latched = latched;
    return; /* Never change non-opt-in keyboard failure behavior. */
  }
  if (h->ime.keyboard_modifiers_sequence == INT_MAX) {
    (void)input_failure(h, GPUI_RESOURCE);
    return;
  }
  ++h->ime.keyboard_modifiers_sequence;
  h->ime.keyboard_modifiers_known = 1;
  h->ime.keyboard_depressed = depressed;
  h->ime.keyboard_latched = latched;
  if (!depressed && !latched)
    h->ime.forwarded_modifiers = 0;
  ime_finish_modifier_drain(h);
}
static void ime_request_external_deactivate(struct host *h, int prior_floor) {
  if (h->ime.phase == IME_DRAINING_MODIFIERS)
    return; /* Coalesce replacement documents without resetting the barrier. */
  if ((h->ime.phase == IME_ACTIVE || h->ime.phase == IME_ACTIVATING) &&
      (h->ime.keyboard_depressed || h->ime.keyboard_latched ||
       h->modifiers || h->ime.forwarded_modifiers)) {
    h->ime.phase = IME_DRAINING_MODIFIERS;
    h->ime.drain_modifiers_sequence = h->ime.keyboard_modifiers_sequence;
    h->ime.drain_release_sequence = h->ime.keyboard_modifiers_sequence;
    h->ime.drain_release_seen = 0;
    h->ime.drain_serial_floor = prior_floor;
    h->ime.drain_latest_serial = h->ime.latest_serial;
    /* Hide canceled candidates but retain the old keyboard grab until its
     * real release/clear has been processed by the input method. */
    zwp_text_input_v1_hide_input_panel(h->ime.proxy);
    return;
  }
  ime_deactivate(h);
}
/* A natural focus loss follows callbacks already admitted on this owner thread.
 * Retain that exact prefix until its captured Left, without accepting new
 * callbacks or transferring it to a replacement session. */
static void ime_preserve_before_focus_loss(struct host *h) {
  if (!ime_current(h, h->ime.proxy)) return;
  for (int i = 0; i < h->count; ++i) {
    int slot = (h->read + i) % QUEUE_CAPACITY;
    struct ime_payload *data = h->ime_queue[slot];
    if (data && data->kind >= 20 && data->kind <= 22 &&
        data->epoch == h->ime.epoch && data->window == h->window &&
        data->seat == h->seat_name &&
        data->proxy_generation == h->ime.proxy_generation &&
        (data->kind == 22 || ime_serial_current(h, (uint32_t)data->serial)))
      data->focus_loss_delivery = 1;
  }
}
/* Legacy close semantics revoke the focus-loss delivery exception. */
static void ime_revoke_focus_loss_delivery(struct host *h) {
  for (int i = 0; i < h->count; ++i) {
    int slot = (h->read + i) % QUEUE_CAPACITY;
    if (h->ime_queue[slot]) h->ime_queue[slot]->focus_loss_delivery = 0;
  }
}
/* Pin only records already valid for the old owner at terminal admission.
 * The reader exposes their captured window and epoch, even after teardown;
 * callers must route or retain them for that owner, never a replacement. */
static void ime_preserve_before_terminal(struct host *h) {
  for (int i = 0; i < h->count; ++i) {
    int slot = (h->read + i) % QUEUE_CAPACITY;
    struct ime_payload *data = h->ime_queue[slot];
    if (!data || data->kind < 20 || data->kind > 22 ||
        data->window != h->window || data->seat != h->seat_name ||
        data->proxy_generation != h->ime.proxy_generation ||
        !h->ime.proxy || !h->seat || !h->surface || h->state || h->error)
      continue;
    int current = h->ime.requested && data->epoch == h->ime.epoch &&
        (data->kind == 22 || ime_serial_current(h, (uint32_t)data->serial));
    int prior_focus = data->focus_loss_delivery && !h->ime.requested &&
        data->epoch < INT_MAX && data->epoch + 1 == h->ime.epoch;
    if (current || prior_focus) data->terminal_delivery = 1;
  }
}
static void ime_invalidate(struct host *h, int emit_leave, int deactivate) {
  if (!h->ime.requested && h->ime.phase != IME_ACTIVE &&
      h->ime.phase != IME_ACTIVATING)
    return;
  if (emit_leave && (h->ime.phase == IME_ACTIVE ||
                     h->ime.phase == IME_ACTIVATING) &&
      h->ime.wire_epoch == h->ime.epoch)
    (void)ime_lifecycle_record(h, 23);
  else if (emit_leave && h->ime.requested &&
           h->ime.wire_epoch != h->ime.epoch)
    (void)ime_pending_left_record(h);
  h->ime.requested = 0;
  memset(h->ime.composition_keys, 0, sizeof(h->ime.composition_keys));
  memset(h->ime.composition_raw_symbols, 0, sizeof(h->ime.composition_raw_symbols));
  (void)ime_advance_epoch(h);
  h->ime.serial_floor = 0;
  if (deactivate)
    ime_deactivate(h);
  else {
    ime_clear_modifier_drain(h);
    h->ime.phase = IME_INACTIVE;
  }
}
static void ime_drop_proxy(struct host *h) {
  ime_invalidate(h, 1, 0);
  ime_clear_stage(h);
  h->ime.requested = 0;
  h->ime.phase = IME_INACTIVE;
  h->ime.serial_floor = 0;
  h->ime.modifiers_valid = h->ime.forwarded_modifiers = 0;
  h->ime.keyboard_depressed = h->ime.keyboard_latched = 0;
  h->ime.keyboard_modifiers_known = 0;
  ime_clear_modifier_drain(h);
  if (h->ime.proxy)
    zwp_text_input_v1_destroy(h->ime.proxy);
  h->ime.proxy = NULL;
}
static void ime_enter(void *data, struct zwp_text_input_v1 *proxy,
                      struct wl_surface *surface) {
  struct host *h = data;
  if (proxy != h->ime.proxy || !h->ime.proxy ||
      h->ime.phase != IME_ACTIVATING || !h->ime.requested ||
      surface != h->surface || !h->surface || h->state ||
      h->ime.wire_window != h->window ||
      h->ime.wire_seat != h->seat_name ||
      h->ime.wire_epoch != h->ime.epoch)
    return;
  h->ime.phase = IME_ACTIVE;
  /* Raw input can arrive while the old text-input session leaves. Retain
   * only replacement-epoch owners so forwarded delivery cannot repeat them. */
  for (int i = 0; i < 256; ++i)
    if (h->ime.composition_key_epochs[i] != h->ime.epoch) {
      h->ime.composition_keys[i] = 0;
      h->ime.composition_key_consumed[i] = 0;
    }
  for (int i = 0; i < GPUI_DIRECT_KEY_CAPACITY; ++i)
    if (h->ime.composition_raw_epochs[i] != h->ime.epoch)
      h->ime.composition_raw_symbols[i] = 0;
  (void)ime_lifecycle_record(h, 22);
}
static void ime_leave(void *data, struct zwp_text_input_v1 *proxy) {
  struct host *h = data;
  if (proxy != h->ime.proxy || !h->ime.proxy)
    return;
  if (h->ime.phase == IME_DEACTIVATING) {
    h->ime.phase = IME_INACTIVE;
    ime_clear_stage(h);
    if (h->ime.requested)
      (void)ime_activate(h);
    else if (h->ime.composition_direct_pending) {
      h->ime.composition_direct_pending = 0;
      h->ime.composition_stopping = 0;
      int status = gpui_direct_keyboard_text_mode(h->token, h->window, 1);
      if (status) (void)input_failure(h, status);
    } else {
      h->ime.composition_stopping = 0;
    }
  } else if (h->ime.phase == IME_ACTIVE || h->ime.phase == IME_ACTIVATING ||
             h->ime.phase == IME_DRAINING_MODIFIERS) {
    /* Unexpected focus loss supersedes the pending drain/reactivation. */
    ime_preserve_before_focus_loss(h);
    ime_invalidate(h, 1, 0);
  }
}
static void ime_modifiers_map(void *data, struct zwp_text_input_v1 *proxy,
                              struct wl_array *map) {
  struct host *h = data;
  if (proxy != h->ime.proxy || !h->ime.proxy ||
      (h->ime.phase != IME_ACTIVE && h->ime.phase != IME_ACTIVATING))
    return;
  h->ime.modifiers_valid = 0;
  h->ime.known_modifier_mask = 0;
  memset(h->ime.modifier_masks, 0, sizeof(h->ime.modifier_masks));
  if (!map || map->size > GPUI_IME_MAX_BYTES || (!map->data && map->size)) {
    (void)input_failure(h, GPUI_INVALID);
    return;
  }
  const char *names[4] = {"Shift", "Control", "Mod1", "Mod4"};
  size_t offset = 0;
  unsigned index = 0;
  while (offset < map->size) {
    const char *name = (const char *)map->data + offset;
    size_t remaining = map->size - offset;
    const char *end = memchr(name, 0, remaining);
    if (!end || index >= 32) {
      (void)input_failure(h, GPUI_INVALID);
      return;
    }
    uint32_t bit = UINT32_C(1) << index;
    h->ime.known_modifier_mask |= bit;
    for (int i = 0; i < 4; ++i)
      if (!strcmp(name, names[i]))
        h->ime.modifier_masks[i] |= bit;
    offset += (size_t)(end - name) + 1;
    ++index;
  }
  h->ime.modifiers_valid = 1;
}
static void ime_panel_state(void *data, struct zwp_text_input_v1 *proxy,
                            uint32_t state) {
  UNUSED(data); UNUSED(proxy); UNUSED(state);
}
static void ime_preedit_styling(void *data, struct zwp_text_input_v1 *proxy,
                               uint32_t index, uint32_t length, uint32_t style) {
  struct host *h = data;
  if (!ime_current(h, proxy))
    return;
  struct ime_payload *stage = &h->ime.stage;
  if (stage->style_count == GPUI_IME_MAX_STYLES ||
      index > GPUI_IME_MAX_BYTES || length > GPUI_IME_MAX_BYTES - index ||
      style > ZWP_TEXT_INPUT_V1_PREEDIT_STYLE_INCORRECT) {
    ime_clear_stage(h);
    (void)input_failure(h, GPUI_INVALID);
    return;
  }
  stage->styles[stage->style_count++] =
      (struct ime_style){(int)index, (int)length, (int)style};
}
static void ime_preedit_cursor(void *data, struct zwp_text_input_v1 *proxy,
                              int32_t index) {
  struct host *h = data;
  if (!ime_current(h, proxy))
    return;
  h->ime.stage.cursor_present = 1;
  h->ime.stage.cursor = index;
}
static int ime_payload_valid(const struct ime_payload *data) {
  if (data->kind < 20 || data->kind > 29 || data->window <= 0 ||
      (data->composition_revoked != 0 && data->composition_revoked != 1) ||
      (data->composition_revoked && data->kind < 26) ||
      (data->focus_loss_delivery != 0 && data->focus_loss_delivery != 1) ||
      (data->focus_loss_delivery && data->kind > 22) ||
      (data->terminal_delivery != 0 && data->terminal_delivery != 1) ||
      (data->terminal_delivery && data->kind > 22) ||
      data->epoch <= 0 || !data->seat || data->proxy_generation <= 0 ||
      data->text_length < 0 || data->text_length > GPUI_IME_MAX_BYTES ||
      data->fallback_length < 0 || data->fallback_length > GPUI_IME_MAX_BYTES ||
      data->style_count < 0 || data->style_count > GPUI_IME_MAX_STYLES ||
      (data->cursor_present != 0 && data->cursor_present != 1) ||
      (data->delete_present != 0 && data->delete_present != 1) ||
      (data->position_present != 0 && data->position_present != 1) ||
      (!data->cursor_present && data->cursor != 0) ||
      (!data->delete_present && (data->delete_index || data->delete_length)) ||
      (!data->position_present && (data->index || data->anchor)) ||
      !direct_utf8_valid(data->text, data->text_length) ||
      !direct_utf8_valid(data->fallback, data->fallback_length) ||
      memchr(data->text, 0, (size_t)data->text_length) ||
      memchr(data->fallback, 0, (size_t)data->fallback_length))
    return 0;
  if (data->kind >= 26) {
    if (data->serial || data->fallback_length || data->delete_present ||
        data->position_present || data->style_count)
      return 0;
    if (data->kind == 27)
      return data->text_length > 0 && data->cursor_present &&
             ime_boundary(data->text, data->text_length, data->cursor);
    return !data->cursor_present &&
           (data->kind == 28 || data->text_length == 0);
  }
  if (data->kind == 22 || data->kind == 23)
    return data->serial == 0 && data->text_length == 0 &&
           data->fallback_length == 0 && !data->cursor_present &&
           !data->delete_present && !data->position_present && !data->style_count;
  if (data->serial <= 0)
    return 0;
  if (data->kind == 24 || data->kind == 25)
    return data->text_length == 0 && data->fallback_length == 0 &&
           !data->cursor_present && !data->delete_present &&
           !data->position_present && !data->style_count;
  if (data->kind == 21)
    return data->fallback_length == 0 && !data->cursor_present &&
           !data->style_count && data->delete_length >= 0 &&
           data->delete_length <= GPUI_IME_MAX_BYTES;
  if (data->delete_present || data->position_present ||
      (data->cursor_present && data->cursor >= 0 &&
       !ime_boundary(data->text, data->text_length, data->cursor)))
    return 0;
  for (int i = 0; i < data->style_count; ++i) {
    const struct ime_style *style = &data->styles[i];
    if (style->length < 0 || style->style < 0 || style->style > 7 ||
        style->index < 0 || style->index > data->text_length ||
        style->length > data->text_length - style->index ||
        !ime_boundary(data->text, data->text_length, style->index) ||
        !ime_boundary(data->text, data->text_length, style->index + style->length))
      return 0;
  }
  return 1;
}
static void ime_preedit_string(void *data, struct zwp_text_input_v1 *proxy,
                              uint32_t serial, const char *text,
                              const char *fallback) {
  struct host *h = data;
  if (proxy != h->ime.proxy || !h->ime.proxy)
    return;
  if (!ime_current(h, proxy) || !ime_serial_current(h, serial)) {
    ime_clear_preedit_stage(h);
    return;
  }
  struct ime_payload transaction = h->ime.stage;
  /* Commit staging is independent: a preedit must never consume deletion. */
  transaction.delete_present = transaction.delete_index = transaction.delete_length = 0;
  transaction.position_present = transaction.index = transaction.anchor = 0;
  transaction.kind = 20;
  transaction.serial = (int)serial;
  transaction.window = h->window;
  transaction.epoch = h->ime.wire_epoch;
  transaction.seat = h->ime.wire_seat;
  transaction.proxy_generation = h->ime.proxy_generation;
  int status = ime_copy_string(transaction.text, text, &transaction.text_length);
  if (!status)
    status = ime_copy_string(transaction.fallback, fallback, &transaction.fallback_length);
  ime_clear_preedit_stage(h);
  if (!status && !ime_payload_valid(&transaction))
    status = GPUI_INVALID;
  if (status)
    (void)input_failure(h, status);
  else
    (void)(h->ime.composition_enabled ? composition_transaction(h, &transaction)
                                       : ime_record(h, &transaction));
}
static void ime_cursor_position(void *data, struct zwp_text_input_v1 *proxy,
                               int32_t index, int32_t anchor) {
  struct host *h = data;
  if (!ime_current(h, proxy))
    return;
  h->ime.stage.position_present = 1;
  h->ime.stage.index = index;
  h->ime.stage.anchor = anchor;
}
static void ime_delete_surrounding(void *data, struct zwp_text_input_v1 *proxy,
                                  int32_t index, uint32_t length) {
  struct host *h = data;
  if (!ime_current(h, proxy))
    return;
  if (length > GPUI_IME_MAX_BYTES || h->ime.stage.delete_present) {
    ime_clear_stage(h);
    (void)input_failure(h, GPUI_INVALID);
    return;
  }
  h->ime.stage.delete_present = 1;
  h->ime.stage.delete_index = index;
  h->ime.stage.delete_length = (int)length;
}
static void ime_commit_string(void *data, struct zwp_text_input_v1 *proxy,
                             uint32_t serial, const char *text) {
  struct host *h = data;
  if (proxy != h->ime.proxy || !h->ime.proxy)
    return;
  if (!ime_current(h, proxy) || !ime_serial_current(h, serial)) {
    ime_clear_commit_stage(h);
    return;
  }
  struct ime_payload transaction = h->ime.stage;
  transaction.cursor_present = transaction.cursor = 0;
  transaction.style_count = 0;
  memset(transaction.styles, 0, sizeof(transaction.styles));
  transaction.kind = 21;
  transaction.serial = (int)serial;
  transaction.window = h->window;
  transaction.epoch = h->ime.wire_epoch;
  transaction.seat = h->ime.wire_seat;
  transaction.proxy_generation = h->ime.proxy_generation;
  int status = ime_copy_string(transaction.text, text, &transaction.text_length);
  ime_clear_commit_stage(h);
  if (!status && !ime_payload_valid(&transaction))
    status = GPUI_INVALID;
  if (status)
    (void)input_failure(h, status);
  else
    (void)(h->ime.composition_enabled ? composition_transaction(h, &transaction)
                                       : ime_record(h, &transaction));
}
/* text-input-v1 forwards a keysym, not a physical keycode. A modifier change
 * can change its release symbol. Resolve only a unique held key, using case
 * identity or the current bounded keyboard map's levels within one layout. */
static int composition_same_key(struct host *h, xkb_keysym_t a, xkb_keysym_t b) {
  if (!h->keymap) return 0;
  xkb_keycode_t first = xkb_keymap_min_keycode(h->keymap);
  xkb_keycode_t last = xkb_keymap_max_keycode(h->keymap);
  if (last >= GPUI_DIRECT_KEY_CAPACITY + 8) return 0;
  for (xkb_keycode_t key = first; key <= last; ++key) {
    xkb_layout_index_t layouts = xkb_keymap_num_layouts_for_key(h->keymap, key);
    for (xkb_layout_index_t layout = 0; layout < layouts; ++layout) {
      int found_a = 0, found_b = 0;
      xkb_level_index_t levels = xkb_keymap_num_levels_for_key(h->keymap, key, layout);
      for (xkb_level_index_t level = 0; level < levels; ++level) {
        const xkb_keysym_t *symbols = NULL;
        int count = xkb_keymap_key_get_syms_by_level(h->keymap, key, layout, level, &symbols);
        for (int i = 0; i < count; ++i) {
          found_a |= symbols[i] == a;
          found_b |= symbols[i] == b;
        }
      }
      if (found_a && found_b) return 1;
    }
  }
  return 0;
}
static void composition_key(struct host *h, uint32_t state,
                            xkb_keysym_t symbol, int modifiers) {
  int slot = -1, empty = -1;
  for (int i = 0; i < 256; ++i) {
    if (h->ime.composition_keys[i] == symbol && symbol) slot = i;
    if (!h->ime.composition_keys[i]) empty = i;
  }
  if (state == WL_KEYBOARD_KEY_STATE_RELEASED) {
    for (int pass = 0; slot < 0 && pass < 2; ++pass) {
      for (int i = 0; i < 256; ++i) {
        uint32_t held = h->ime.composition_keys[i];
        if (held && (pass == 0
              ? xkb_keysym_to_lower(held) == xkb_keysym_to_lower(symbol)
              : composition_same_key(h, held, symbol))) {
          if (slot >= 0) {
            /* Ambiguous release cannot safely mutate either key owner. */
            (void)input_failure(h, GPUI_INVALID);
            return;
          }
          slot = i;
        }
      }
    }
    if (slot < 0) return;
    symbol = h->ime.composition_keys[slot];
    h->ime.composition_keys[slot] = 0;
    if (h->ime.composition_key_consumed[slot]) {
      h->ime.composition_key_consumed[slot] = 0;
      return;
    }
  } else {
    if (slot >= 0 && h->ime.composition_key_epochs[slot] == h->ime.epoch)
      return; /* Raw and forwarded delivery share current-epoch ownership. */
    if (slot >= 0) empty = slot; /* A fresh press supersedes an old owner. */
    if (empty < 0 || !symbol) {
      (void)input_failure(h, GPUI_RESOURCE); return;
    }
    h->ime.composition_keys[empty] = symbol;
    h->ime.composition_key_epochs[empty] = h->ime.epoch;
    h->ime.composition_key_consumed[empty] = 0;
  }
  uint32_t scalar = xkb_keysym_to_utf32(symbol);
  int printable = scalar >= 32 && scalar != 127 && !(modifiers & 14);
  if (state == WL_KEYBOARD_KEY_STATE_PRESSED && printable) {
    h->ime.composition_key_consumed[empty] = 1;
    char text[8] = {0};
    int length = xkb_keysym_to_utf8(symbol, text, sizeof(text));
    if (length > 1) {
      struct ime_payload data = {0};
      data.text_length = length - 1;
      memcpy(data.text, text, (size_t)data.text_length);
      (void)composition_record(h, 28, &data);
      h->ime.composition_preview = 0;
    }
    return;
  }
  if (state == WL_KEYBOARD_KEY_STATE_PRESSED && h->ime.composition_preview &&
      (symbol == XKB_KEY_Return || symbol == XKB_KEY_KP_Enter ||
       symbol == XKB_KEY_Escape)) {
    if (composition_resolve(h, symbol != XKB_KEY_Escape)) return;
    /* Reset the old native transaction before its delayed commit arrives. */
    h->ime.composition_key_consumed[empty] = 2;
    (void)gpui_text_session_cancel(h->token, h->window, h->ime.epoch);
    return; /* resolving Enter/Escape is consumed, including its release */
  }
  int queue_slot = (h->read + h->count) % QUEUE_CAPACITY;
  int previous_count = h->count;
  int previous_modifiers = h->modifiers;
  h->modifiers = modifiers;
  direct_key_record(h, state == WL_KEYBOARD_KEY_STATE_PRESSED ? 11 : 12,
                    symbol, scalar, h->direct_epoch, 0, 0);
  h->modifiers = previous_modifiers;
  if (h->count != previous_count)
    h->direct_queue[queue_slot].composition_epoch = h->ime.epoch;
}
static int composition_pending_release(struct host *h, uint32_t state,
                                       xkb_keysym_t symbol) {
  if (!h->ime.composition_enabled || state != WL_KEYBOARD_KEY_STATE_RELEASED ||
      !h->keyboard_focus_current || h->state || h->error)
    return 0;
  for (int i = 0; i < 256; ++i)
    if (symbol && h->ime.composition_keys[i] == symbol &&
        h->ime.composition_key_consumed[i] == 2) {
      composition_key(h, state, symbol, h->modifiers);
      return 1;
    }
  return 0;
}
static void ime_raw_keyboard_key(struct host *h, uint32_t state,
                                  xkb_keysym_t symbol) {
  ime_observe_modifier_release(h, state, symbol);
  if (composition_pending_release(h, state, symbol)) return;
  /* wl_keyboard callbacks belong to the current physical focus, not the
   * canceled text-input wire epoch. Keep fresh bounded-composer input during
   * its leave/rearm handshake; forwarded callbacks remain fully fenced. */
  int composition_rearming = h->ime.composition_enabled &&
      (h->ime.phase == IME_DEACTIVATING ||
       h->ime.phase == IME_DRAINING_MODIFIERS);
  if (!h->ime.requested || h->ime.exhausted || h->state || h->error ||
      !h->keyboard_focus_current || !h->ime.proxy || !h->window ||
      !h->seat_name || (!composition_rearming &&
                       h->ime.phase != IME_ACTIVE &&
                       h->ime.phase != IME_ACTIVATING) ||
      (!composition_rearming && h->ime.wire_epoch != h->ime.epoch) ||
      h->ime.wire_window != h->window || h->ime.wire_seat != h->seat_name)
    return;
  if (state > WL_KEYBOARD_KEY_STATE_PRESSED || symbol > 0x1fffffff ||
      h->modifiers < 0 || h->modifiers > 15) {
    (void)input_failure(h, GPUI_INVALID);
    return;
  }
  if (h->ime.composition_enabled) {
    composition_key(h, state, symbol, h->modifiers);
    return;
  }
  struct ime_payload transaction = {0};
  transaction.kind = state == WL_KEYBOARD_KEY_STATE_PRESSED ? 24 : 25;
  transaction.serial = h->ime.latest_serial;
  int slot = (h->read + h->count) % QUEUE_CAPACITY;
  if (!ime_record(h, &transaction)) {
    h->queue[slot][8] = symbol;
    h->queue[slot][9] = h->modifiers;
  }
}
static void ime_keysym(void *data, struct zwp_text_input_v1 *proxy,
                       uint32_t serial, uint32_t time, uint32_t symbol,
                       uint32_t state, uint32_t modifiers) {
  UNUSED(time);
  struct host *h = data;
  /* Forwarded releases must pass the same current-target/serial checks as
   * presses. An old release must never clear a replacement epoch owner. */
  if (proxy == h->ime.proxy && h->ime.proxy &&
      h->ime.phase == IME_DRAINING_MODIFIERS) {
    /* Only an issued serial of the captured old wire target can mark a
     * genuine release. It is never enqueued or admitted as replacement input. */
    if (serial && serial <= INT_MAX && h->ime.drain_serial_floor > 0 &&
        serial >= (uint32_t)h->ime.drain_serial_floor &&
        serial <= (uint32_t)h->ime.drain_latest_serial &&
        h->ime.modifiers_valid && !(modifiers & ~h->ime.known_modifier_mask))
      ime_observe_modifier_release(h, state, symbol);
    return;
  }
  if (!ime_current(h, proxy) || !ime_serial_current(h, serial))
    return;
  if (!h->ime.modifiers_valid || (modifiers & ~h->ime.known_modifier_mask) ||
      symbol > 0x1fffffff || state > WL_KEYBOARD_KEY_STATE_PRESSED) {
    (void)input_failure(h, GPUI_INVALID);
    return;
  }
  if (h->ime.composition_enabled) {
    int bits = 0;
    for (int i = 0; i < 4; ++i)
      if (modifiers & h->ime.modifier_masks[i]) bits |= 1 << i;
    h->ime.forwarded_modifiers = bits;
    composition_key(h, state, symbol, bits);
    return;
  }
  struct ime_payload transaction = {0};
  transaction.kind = state == WL_KEYBOARD_KEY_STATE_PRESSED ? 24 : 25;
  transaction.serial = (int)serial;
  int slot = (h->read + h->count) % QUEUE_CAPACITY;
  int status = ime_record(h, &transaction);
  if (status)
    return;
  h->queue[slot][8] = symbol;
  int bits = 0;
  for (int i = 0; i < 4; ++i)
    if (modifiers & h->ime.modifier_masks[i])
      bits |= 1 << i;
  h->ime.forwarded_modifiers = bits;
  h->queue[slot][9] = bits;
}
static void ime_language(void *data, struct zwp_text_input_v1 *proxy,
                         uint32_t serial, const char *language) {
  UNUSED(data); UNUSED(proxy); UNUSED(serial); UNUSED(language);
}
static void ime_direction(void *data, struct zwp_text_input_v1 *proxy,
                          uint32_t serial, uint32_t direction) {
  UNUSED(data); UNUSED(proxy); UNUSED(serial); UNUSED(direction);
}
static const struct zwp_text_input_v1_listener ime_listener = {
  .enter = ime_enter, .leave = ime_leave, .modifiers_map = ime_modifiers_map,
  .input_panel_state = ime_panel_state, .preedit_string = ime_preedit_string,
  .preedit_styling = ime_preedit_styling, .preedit_cursor = ime_preedit_cursor,
  .commit_string = ime_commit_string, .cursor_position = ime_cursor_position,
  .delete_surrounding_text = ime_delete_surrounding, .keysym = ime_keysym,
  .language = ime_language, .text_direction = ime_direction
};
static int ime_require_proxy(struct host *h) {
  if (!h->ime.manager || !h->ime.manager_name || !h->seat || !h->seat_name ||
      !h->keyboard || !h->surface || !h->keyboard_focus_current)
    return GPUI_UNSUPPORTED;
  if (h->ime.exhausted)
    return GPUI_RESOURCE;
  if (!h->ime.proxy) {
    if (h->ime.proxy_generation == INT_MAX) {
      h->ime.exhausted = 1;
      return GPUI_RESOURCE;
    }
    h->ime.proxy = zwp_text_input_manager_v1_create_text_input(h->ime.manager);
    if (!h->ime.proxy)
      return GPUI_RESOURCE;
    ++h->ime.proxy_generation;
    if (zwp_text_input_v1_add_listener(h->ime.proxy, &ime_listener, h) < 0) {
      zwp_text_input_v1_destroy(h->ime.proxy);
      h->ime.proxy = NULL;
      return GPUI_NATIVE;
    }
  }
  return GPUI_OK;
}
static int ime_document_valid(const uint8_t *text, int length, int cursor,
                              int anchor, int width, int height) {
  return length >= 0 && length <= GPUI_IME_MAX_BYTES &&
         (text || length == 0) && width > 0 && height > 0 &&
         (length == 0 || !memchr(text, 0, (size_t)length)) &&
         direct_utf8_valid(text, length) &&
         ime_boundary(text, length, cursor) && ime_boundary(text, length, anchor);
}
static void ime_set_document(struct host *h, const uint8_t *text, int length,
                             int cursor, int anchor, int x, int y,
                             int width, int height) {
  if (length)
    memmove(h->ime.document, text, (size_t)length);
  h->ime.document[length] = 0;
  h->ime.document_length = length;
  h->ime.cursor = cursor;
  h->ime.anchor = anchor;
  h->ime.rect[0] = x; h->ime.rect[1] = y;
  h->ime.rect[2] = width; h->ime.rect[3] = height;
}
int32_t gpui_text_session_begin(int32_t token, int32_t window,
    const uint8_t *text, int32_t length, int32_t cursor, int32_t anchor,
    int32_t x, int32_t y, int32_t width, int32_t height) {
  struct host *h;
  int status = window_check(token, window, &h);
  if (status)
    return -status;
  if (h->terminal_retention && h->terminal_preview_pending)
    return -GPUI_BUSY;
  if (h->state)
    return -GPUI_STOPPING;
  if (h->error)
    return -h->error;
  if (h->direct_exhausted && h->direct_ever_enabled)
    return -GPUI_RESOURCE;
  if (!ime_document_valid(text, length, cursor, anchor, width, height))
    return -GPUI_INVALID;
  if (h->ime.composition_enabled || h->ime.requested || h->direct_enabled ||
      (!h->ime.composition_begin_internal && gpui_text_composition_active(token) > 0))
    return -GPUI_BUSY;
  status = ime_require_proxy(h);
  if (status)
    return -status;
  status = ime_advance_epoch(h);
  if (status)
    return -status;
  ime_set_document(h, text, length, cursor, anchor, x, y, width, height);
  h->ime.requested = h->ime.ever_enabled = 1;
  h->ime.composition_direct_pending = 0;
  h->ime.composition_stopping = 0;
  h->ime.panel_requested = 1;
  status = ime_activate(h);
  if (!status) {
    /* Pre-opt-in keyboard records cannot later be reinterpreted as character
     * commands for this target, even if the owner ends before draining. */
    for (int i = 0; i < h->count; ++i) {
      int slot = (h->read + i) % QUEUE_CAPACITY;
      double kind = h->queue[slot][0];
      if (kind == 11 || kind == 12 || kind == 13)
        h->direct_queue[slot].revoked = 1;
    }
  }
  return status ? -status : h->ime.epoch;
}
static int ime_session_check(int token, int window, int epoch, struct host **out) {
  int status = window_check(token, window, out);
  if (status)
    return status;
  if ((*out)->ime.exhausted)
    return GPUI_RESOURCE;
  if ((*out)->state)
    return GPUI_STOPPING;
  if ((*out)->error)
    return (*out)->error;
  return epoch > 0 && (*out)->ime.requested && epoch == (*out)->ime.epoch
             ? GPUI_OK : GPUI_STALE;
}
int32_t gpui_text_session_update(int32_t token, int32_t window, int32_t epoch,
    const uint8_t *text, int32_t length, int32_t cursor, int32_t anchor,
    int32_t x, int32_t y, int32_t width, int32_t height, int32_t external_edit) {
  struct host *h;
  int status = ime_session_check(token, window, epoch, &h);
  if (status)
    return -status;
  if ((external_edit != 0 && external_edit != 1) ||
      !ime_document_valid(text, length, cursor, anchor, width, height))
    return -GPUI_INVALID;
  /* The host cannot acknowledge records already handed to the caller; this
   * fence only prevents invalidating records still in the native queue. */
  if (h->terminal_retention && external_edit && h->count)
    return -GPUI_BUSY;
  if (h->ime.latest_serial == INT_MAX ||
      (external_edit && h->ime.epoch == INT_MAX)) {
    h->ime.exhausted = 1;
    h->ime.requested = 0;
    h->ime.serial_floor = 0;
    ime_clear_stage(h);
    ime_deactivate(h);
    return -GPUI_RESOURCE;
  }
  if (external_edit) {
    if ((h->ime.phase == IME_ACTIVE || h->ime.phase == IME_ACTIVATING) &&
        h->ime.wire_epoch == h->ime.epoch) {
      status = ime_lifecycle_record(h, 23);
      if (status)
        return -status;
    }
    int prior_floor = h->ime.serial_floor;
    status = ime_advance_epoch(h);
    h->ime.serial_floor = 0;
    ime_request_external_deactivate(h, prior_floor);
  }
  if (status)
    return -status;
  ime_set_document(h, text, length, cursor, anchor, x, y, width, height);
  if (h->ime.phase == IME_ACTIVE || h->ime.phase == IME_ACTIVATING)
    status = ime_send_state(h);
  else if (h->ime.phase == IME_INACTIVE)
    status = ime_activate(h);
  return status ? -status : h->ime.epoch;
}
int32_t gpui_text_session_cancel(int32_t token, int32_t window, int32_t epoch) {
  struct host *h;
  int status = ime_session_check(token, window, epoch, &h);
  if (status)
    return -status;
  return gpui_text_session_update(token, window, epoch, h->ime.document,
      h->ime.document_length, h->ime.cursor, h->ime.anchor, h->ime.rect[0],
      h->ime.rect[1], h->ime.rect[2], h->ime.rect[3], 1);
}
int32_t gpui_text_session_end(int32_t token, int32_t window, int32_t epoch) {
  struct host *h;
  int status = ime_session_check(token, window, epoch, &h);
  if (status)
    return status;
  if (h->terminal_retention && h->count) return GPUI_BUSY;
  ime_invalidate(h, 1, 1);
  return h->ime.exhausted ? GPUI_RESOURCE : h->error;
}
int32_t gpui_text_session_end_when_drained(int32_t token, int32_t window,
                                          int32_t epoch) {
  struct host *h;
  int status = ime_session_check(token, window, epoch, &h);
  if (status) return status;
  if (h->count) return GPUI_BUSY;
  if (h->ime.epoch == INT_MAX) return GPUI_RESOURCE;
  /* Publish the old target's lifecycle record before invalidating. Failure to
   * allocate it must not be hidden behind a successful end. */
  if ((h->ime.phase == IME_ACTIVE || h->ime.phase == IME_ACTIVATING) &&
      h->ime.wire_epoch == h->ime.epoch)
    status = ime_lifecycle_record(h, 23);
  else if (h->ime.wire_epoch != h->ime.epoch)
    status = ime_pending_left_record(h);
  if (status) return status;
  ime_invalidate(h, 0, 1);
  return h->ime.exhausted ? GPUI_RESOURCE : h->error;
}
/* Reader implementation is placed after ABI2 consume helpers below. */
int32_t gpui_text_session_panel(int32_t token, int32_t window, int32_t epoch,
                                int32_t visible) {
  struct host *h;
  int status = ime_session_check(token, window, epoch, &h);
  if (status)
    return status;
  if (visible != 0 && visible != 1)
    return GPUI_INVALID;
  h->ime.panel_requested = visible;
  if (h->ime.phase == IME_ACTIVE || h->ime.phase == IME_ACTIVATING) {
    if (visible)
      zwp_text_input_v1_show_input_panel(h->ime.proxy);
    else
      zwp_text_input_v1_hide_input_panel(h->ime.proxy);
  }
  return GPUI_OK;
}

int32_t gpui_text_composition_active(int32_t token) {
  struct host *h;
  int status = check(token, &h);
  if (status) return -status;
  if (h->ime.composition_enabled) return 1;
  for (int i = 0; i < h->count; ++i) {
    int slot = (h->read + i) % QUEUE_CAPACITY;
    if ((h->ime_queue[slot] && h->ime_queue[slot]->kind >= 26) ||
        h->direct_queue[slot].composition_epoch ||
        (h->ime.composition_ever_enabled && !h->ime.requested &&
         h->direct_queue[slot].revoked)) return 1;
  }
  return 0;
}
int32_t gpui_text_composition_finish(int32_t token, int32_t window, int32_t commit) {
  struct host *h;
  int status = window_check(token, window, &h);
  if (status) return status;
  if (commit != 0 && commit != 1) return GPUI_INVALID;
  if (!h->ime.composition_enabled) return GPUI_OK;
  if (h->state) return GPUI_STOPPING;
  if (h->ime.exhausted) return GPUI_RESOURCE;
  if (h->error) return h->error;
  if (h->terminal_retention && h->count) return GPUI_BUSY;
  /* Resolving a preview itself admits a record. The existing finish operation
   * has no receipt with which to acknowledge it before epoch invalidation. */
  if (h->terminal_retention && h->ime.composition_preview)
    return GPUI_UNSUPPORTED;
  status = commit ? composition_resolve(h, 1) : composition_cancel_unread(h);
  if (status) return status;
  if (!h->ime.requested) return GPUI_OK;
  int epoch = gpui_text_session_cancel(token, window, h->ime.epoch);
  return epoch < 0 ? -epoch : GPUI_OK;
}
int32_t gpui_text_composition_mode(int32_t token, int32_t window, int32_t enabled) {
  struct host *h;
  int status = window_check(token, window, &h);
  if (status) return status;
  if (enabled != 0 && enabled != 1) return GPUI_INVALID;
  if (!enabled) {
    if (!h->ime.composition_enabled) return GPUI_OK;
    if (h->terminal_retention && h->count) return GPUI_BUSY;
    status = composition_cancel_unread(h);
    if (status) return status;
    ime_invalidate(h, 0, 1);
    h->ime.composition_enabled = 0;
    h->ime.composition_stopping = h->ime.phase == IME_DEACTIVATING;
    memset(h->ime.composition_keys, 0, sizeof(h->ime.composition_keys));
  memset(h->ime.composition_raw_symbols, 0, sizeof(h->ime.composition_raw_symbols));
    return h->ime.exhausted ? GPUI_RESOURCE : h->error;
  }
  if (h->ime.composition_enabled && h->ime.requested) return GPUI_OK;
  h->ime.composition_direct_pending = 0;
  h->ime.composition_stopping = 0;
  if (h->state) return GPUI_STOPPING;
  if (h->error) return h->error;
  if (h->ime.requested) return GPUI_BUSY;
  if (h->ime.exhausted || h->ime.epoch == INT_MAX ||
      h->ime.latest_serial == INT_MAX || h->direct_exhausted ||
      (h->direct_enabled && h->direct_epoch == INT_MAX))
    return GPUI_RESOURCE;
  /* Initial opt-in may precede wl_keyboard.enter. Arm without protocol
   * requests; keyboard_enter starts the empty session after focus is proven. */
  if (!h->keyboard_focus_current) {
    if (!h->ime.manager || !h->ime.manager_name || !h->surface)
      return GPUI_UNSUPPORTED;
    h->ime.composition_enabled = h->ime.composition_ever_enabled = 1;
    if (h->ime.rect[2] <= 0 || h->ime.rect[3] <= 0) {
      h->ime.rect[2] = h->ime.rect[3] = 1;
    }
    return GPUI_OK;
  }
  /* Only disarm direct input after capability validation. */
  status = ime_require_proxy(h);
  if (status) return status;
  if (h->direct_enabled) {
    status = advance_direct_epoch(h);
    if (status) return status;
    h->direct_enabled = 0;
  }
  h->ime.composition_enabled = 0;
  int width = h->ime.rect[2] > 0 ? h->ime.rect[2] : 1;
  int height = h->ime.rect[3] > 0 ? h->ime.rect[3] : 1;
  h->ime.composition_begin_internal = 1;
  int epoch = gpui_text_session_begin(token, window, NULL, 0, 0, 0,
      h->ime.rect[0], h->ime.rect[1], width, height);
  h->ime.composition_begin_internal = 0;
  if (epoch < 0) return -epoch;
  h->ime.composition_enabled = h->ime.composition_ever_enabled = 1;
  return GPUI_OK;
}
int32_t gpui_text_composition_caret(int32_t token, int32_t window,
    int32_t x, int32_t y, int32_t width, int32_t height) {
  struct host *h;
  int status = window_check(token, window, &h);
  if (status) return status;
  if (width <= 0 || height <= 0) return GPUI_INVALID;
  if (!h->ime.composition_enabled) return GPUI_STALE;
  if (h->state) return GPUI_STOPPING;
  if (h->error) return h->error;
  if (!h->ime.requested) {
    h->ime.rect[0] = x; h->ime.rect[1] = y;
    h->ime.rect[2] = width; h->ime.rect[3] = height;
    return GPUI_OK;
  }
  int epoch = gpui_text_session_update(token, window, h->ime.epoch,
      NULL, 0, 0, 0, x, y, width, height, 0);
  return epoch < 0 ? -epoch : GPUI_OK;
}
/* Synthetic acceptance ingress only; no protocol or physical IME claim. */
int32_t gpui_test_post_composition(int32_t token, int32_t window, int32_t kind,
    const uint8_t *text, int32_t length, int32_t cursor_utf16) {
  const char *gate = getenv("GPUI_NATIVE_E2E");
  if (!gate || strcmp(gate, "1")) return GPUI_UNSUPPORTED;
  struct host *h;
  int status = window_check(token, window, &h);
  if (status) return status;
  if (h->state) return GPUI_STOPPING;
  if (h->error) return h->error;
  if (!h->ime.composition_enabled || !h->ime.requested) return GPUI_UNSUPPORTED;
  if (kind < 0 || kind > 3 || length < 0 || length > GPUI_IME_MAX_BYTES ||
      (!text && length) || !direct_utf8_valid(text, length) ||
      (length && memchr(text, 0, (size_t)length)) ||
      ((kind == 0 || kind == 3) && length) || cursor_utf16 < -1)
    return GPUI_INVALID;
  struct ime_payload data = {0};
  data.text_length = length;
  if (length) memcpy(data.text, text, (size_t)length);
  if (kind == 1) {
    int units = 0, cursor = -1;
    for (int i = 0; i < length;) {
      if (units == cursor_utf16) cursor = i;
      unsigned byte = text[i];
      int width = byte < 0x80 ? 1 : byte < 0xe0 ? 2 : byte < 0xf0 ? 3 : 4;
      units += width == 4 ? 2 : 1;
      i += width;
    }
    if (units == cursor_utf16 || cursor_utf16 == -1) cursor = length;
    if (cursor < 0) return GPUI_INVALID;
    data.kind = 20; data.cursor_present = 1; data.cursor = cursor;
    return composition_transaction(h, &data);
  }
  if (cursor_utf16 != -1) return GPUI_INVALID;
  if (kind == 0) {
    if (h->ime.composition_preview) return GPUI_OK;
    status = composition_record(h, 26, NULL);
    if (!status) {
      memset(&h->ime.composition_cache, 0, sizeof(h->ime.composition_cache));
      h->ime.composition_preview = 1;
    }
    return status;
  }
  if (kind == 3) return composition_resolve(h, 0);
  data.kind = 21;
  return composition_transaction(h, &data);
}
