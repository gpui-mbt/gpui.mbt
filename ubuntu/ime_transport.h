#ifndef GPUI_IME_TRANSPORT_PRIVATE_H
#define GPUI_IME_TRANSPORT_PRIVATE_H
/* Private state, bounded copies only. No caller/protocol string is retained. */
struct ime_style { int index, length, style; };
struct ime_payload {
  int kind, window, epoch, proxy_generation, serial;
  int composition_revoked, focus_loss_delivery;
  uint32_t seat;
  int text_length, fallback_length, cursor_present, cursor;
  int delete_present, delete_index, delete_length;
  int position_present, index, anchor, style_count;
  struct ime_style styles[GPUI_IME_MAX_STYLES];
  uint8_t text[GPUI_IME_MAX_BYTES + 1];
  uint8_t fallback[GPUI_IME_MAX_BYTES + 1];
};
enum ime_phase { IME_INACTIVE, IME_ACTIVATING, IME_ACTIVE, IME_DEACTIVATING,
                 IME_DRAINING_MODIFIERS };
struct ime_state {
  struct zwp_text_input_manager_v1 *manager;
  struct zwp_text_input_v1 *proxy;
  uint32_t manager_name;
  int proxy_generation, epoch, exhausted, requested, ever_enabled;
  int phase, wire_epoch, wire_window, panel_requested;
  uint32_t wire_seat;
  int latest_serial, serial_floor;
  int document_length, cursor, anchor, rect[4];
  uint8_t document[GPUI_IME_MAX_BYTES + 1];
  struct ime_payload stage;
  int composition_enabled, composition_preview, composition_ever_enabled;
  int composition_stopping, composition_direct_pending, composition_begin_internal;
  struct ime_payload composition_cache;
  uint32_t composition_keys[256];
  int composition_key_epochs[256];
  uint32_t composition_raw_symbols[GPUI_DIRECT_KEY_CAPACITY];
  int composition_raw_epochs[GPUI_DIRECT_KEY_CAPACITY];
  uint8_t composition_key_consumed[256];
  uint32_t modifier_masks[4], known_modifier_mask;
  int modifiers_valid, forwarded_modifiers;
  /* A logical fence may retain the old grab solely to drain genuine held
   * modifier release/clear before physical deactivate. None of its text or
   * keys can be admitted into the replacement epoch. */
  uint32_t keyboard_depressed, keyboard_latched;
  int keyboard_modifiers_known, keyboard_modifiers_sequence;
  int drain_modifiers_sequence, drain_release_sequence, drain_release_seen;
  int drain_serial_floor, drain_latest_serial;
};
#endif
