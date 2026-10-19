/* Opt-in Win32 IMM32 composition transport. This is deliberately separate
 * from the private field editor session in text_input.inc: it publishes only
 * the four portable CompositionEvent states through the ordinary event ring.
 * Include this after text_input.inc and before gpui_window_proc. */
#define GPUI_COMPOSITION_MAX_PREEDIT_UNITS 16384
#define GPUI_COMPOSITION_MAX_COMMIT_UNITS 65536

typedef struct gpui_composition_state {
  int32_t window_id;
  BOOL armed;
  BOOL composing;
  BOOL commit_waiting_end;
  BOOL suppress_ime_char_until_end;
  BOOL suppress_ime_messages;
  BOOL awaiting_fresh_start;
  HIMC expected_himc;
  double caret_x;
  double caret_y;
  double caret_width;
  double caret_height;
  WCHAR *marked;
  int32_t marked_units;
} gpui_composition_state;

static gpui_composition_state g_gpui_composition;

static void gpui_composition_disarm_native(gpui_windows_host *host);
static void gpui_composition_clear_marked(void);
static int32_t gpui_composition_emit(gpui_windows_host *host, int32_t code,
                                     const WCHAR *text, int32_t units,
                                     int32_t cursor);
static int32_t gpui_composition_apply(gpui_windows_host *host, int32_t kind,
                                      const WCHAR *text, int32_t units,
                                      int32_t cursor);
static int32_t gpui_composition_end(gpui_windows_host *host);
static int32_t gpui_composition_compose_message(gpui_windows_host *host,
                                                HWND hwnd, LPARAM flags);

static BOOL gpui_composition_is_armed(void) {
  return g_gpui_composition.armed;
}

static void gpui_composition_zero_state(void) {
  ZeroMemory(&g_gpui_composition, sizeof(g_gpui_composition));
  g_gpui_composition.caret_width = 1.0;
  g_gpui_composition.caret_height = 18.0;
}

static void gpui_composition_clear_marked(void) {
  free(g_gpui_composition.marked);
  g_gpui_composition.marked = NULL;
  g_gpui_composition.marked_units = 0;
}

static BOOL gpui_composition_rect_valid(double x, double y, double width,
                                        double height) {
  return isfinite(x) && isfinite(y) && isfinite(width) && isfinite(height) &&
         fabs(x) <= 8192.0 && fabs(y) <= 8192.0 && width > 0.0 &&
         height > 0.0 && width <= 8192.0 && height <= 8192.0 &&
         floor(width) == width && floor(height) == height;
}

static int32_t gpui_composition_validate_wide(const WCHAR *text,
                                              int32_t units,
                                              int32_t limit) {
  if (units < 0 || units > limit || (units && !text))
    return GPUI_WINDOWS_INVALID;
  for (int32_t i = 0; i < units; ++i) {
    if (text[i] == 0)
      return GPUI_WINDOWS_INVALID;
    if (gpui_text_high_surrogate(text[i])) {
      if (i + 1 >= units || !gpui_text_low_surrogate(text[i + 1]))
        return GPUI_WINDOWS_CONVERSION;
      ++i;
    } else if (gpui_text_low_surrogate(text[i])) {
      return GPUI_WINDOWS_CONVERSION;
    }
  }
  return GPUI_WINDOWS_OK;
}

static int32_t gpui_composition_wide_to_utf8(const WCHAR *text,
                                             int32_t units, int32_t limit,
                                             uint8_t **output,
                                             int32_t *bytes) {
  if (!output || !bytes)
    return GPUI_WINDOWS_INVALID;
  *output = NULL;
  *bytes = 0;
  int32_t status = gpui_composition_validate_wide(text, units, limit);
  if (status != GPUI_WINDOWS_OK)
    return status;
  if (units == 0)
    return GPUI_WINDOWS_OK;
  int count = WideCharToMultiByte(CP_UTF8, WC_ERR_INVALID_CHARS, text, units,
                                  NULL, 0, NULL, NULL);
  if (count <= 0)
    return GPUI_WINDOWS_CONVERSION;
  if (count > GPUI_COMPOSITION_MAX_TEXT_BYTES)
    return GPUI_WINDOWS_RESOURCE;
  uint8_t *copy = (uint8_t *)malloc((size_t)count);
  if (!copy)
    return GPUI_WINDOWS_RESOURCE;
  if (WideCharToMultiByte(CP_UTF8, WC_ERR_INVALID_CHARS, text, units,
                          (LPSTR)copy, count, NULL, NULL) != count) {
    free(copy);
    return GPUI_WINDOWS_CONVERSION;
  }
  *output = copy;
  *bytes = count;
  return GPUI_WINDOWS_OK;
}

static int32_t gpui_composition_utf8_to_wide(const uint8_t *bytes,
                                             int32_t length, int32_t limit,
                                             WCHAR **output,
                                             int32_t *units) {
  if (!output || !units || length < 0 ||
      length > GPUI_COMPOSITION_MAX_TEXT_BYTES || (length && !bytes))
    return GPUI_WINDOWS_INVALID;
  *output = NULL;
  *units = 0;
  if (length && memchr(bytes, 0, (size_t)length))
    return GPUI_WINDOWS_INVALID;
  int count = 0;
  if (length) {
    count = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS,
                                (LPCCH)bytes, length, NULL, 0);
    if (count <= 0)
      return GPUI_WINDOWS_CONVERSION;
  }
  if (count > limit)
    return GPUI_WINDOWS_RESOURCE;
  WCHAR *copy = (WCHAR *)calloc((size_t)count + 1, sizeof(WCHAR));
  if (!copy)
    return GPUI_WINDOWS_RESOURCE;
  if (count && MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS,
                                   (LPCCH)bytes, length, copy, count) != count) {
    free(copy);
    return GPUI_WINDOWS_CONVERSION;
  }
  int32_t status = gpui_composition_validate_wide(copy, count, limit);
  if (status != GPUI_WINDOWS_OK) {
    free(copy);
    return status;
  }
  *output = copy;
  *units = count;
  return GPUI_WINDOWS_OK;
}

static int32_t gpui_composition_read_imm_string(HIMC context, DWORD index,
                                               int32_t max_units,
                                               WCHAR **output,
                                               int32_t *units) {
  *output = NULL;
  *units = 0;
  LONG byte_count =
      g_gpui_imm.get_composition_string_w(context, index, NULL, 0);
  if (byte_count < 0 || (byte_count & 1) != 0 ||
      byte_count > (LONG)max_units * (LONG)sizeof(WCHAR))
    return GPUI_WINDOWS_INVALID;
  int32_t count = (int32_t)(byte_count / (LONG)sizeof(WCHAR));
  WCHAR *buffer = (WCHAR *)calloc((size_t)count + 1, sizeof(WCHAR));
  if (!buffer)
    return GPUI_WINDOWS_RESOURCE;
  if (byte_count) {
    LONG copied = g_gpui_imm.get_composition_string_w(
        context, index, buffer, (DWORD)byte_count);
    if (copied != byte_count) {
      free(buffer);
      return copied < 0 ? GPUI_WINDOWS_NATIVE : GPUI_WINDOWS_STALE;
    }
  }
  int32_t status = gpui_composition_validate_wide(buffer, count, max_units);
  if (status != GPUI_WINDOWS_OK) {
    free(buffer);
    return status;
  }
  *output = buffer;
  *units = count;
  return GPUI_WINDOWS_OK;
}

static int32_t gpui_composition_store_marked(const WCHAR *text,
                                             int32_t units) {
  WCHAR *copy = NULL;
  if (units > 0) {
    copy = (WCHAR *)calloc((size_t)units + 1, sizeof(WCHAR));
    if (!copy)
      return GPUI_WINDOWS_RESOURCE;
    memcpy(copy, text, (size_t)units * sizeof(WCHAR));
  }
  free(g_gpui_composition.marked);
  g_gpui_composition.marked = copy;
  g_gpui_composition.marked_units = units;
  return GPUI_WINDOWS_OK;
}

static int32_t gpui_composition_resource_fail(gpui_windows_host *host) {
  if (!host->error)
    InterlockedExchange(&host->error, GPUI_WINDOWS_RESOURCE);
  InterlockedExchange(&host->state, 1);
  return GPUI_WINDOWS_RESOURCE;
}

static int32_t gpui_composition_emit(gpui_windows_host *host, int32_t code,
                                     const WCHAR *text, int32_t units,
                                     int32_t cursor) {
  if (!host || code < 0 || code > 3)
    return GPUI_WINDOWS_INVALID;
  if (host->state != 0)
    return GPUI_WINDOWS_STOPPING;
  if (!g_gpui_composition.armed ||
      g_gpui_composition.window_id != host->window_id)
    return GPUI_WINDOWS_STALE;
  int32_t limit = code == 2 ? GPUI_COMPOSITION_MAX_COMMIT_UNITS
                            : GPUI_COMPOSITION_MAX_PREEDIT_UNITS;
  if (code == 1 || code == 2) {
    int32_t status = gpui_composition_validate_wide(text, units, limit);
    if (status != GPUI_WINDOWS_OK)
      return status;
    if (code == 1 &&
        (cursor < 0 || cursor > units ||
         !gpui_text_wide_boundary(text, units, cursor)))
      return GPUI_WINDOWS_INVALID;
  } else {
    if (units != 0)
      return GPUI_WINDOWS_INVALID;
    cursor = 0;
  }
  uint8_t *utf8 = NULL;
  int32_t bytes = 0;
  if (units > 0) {
    int32_t status =
        gpui_composition_wide_to_utf8(text, units, limit, &utf8, &bytes);
    if (status != GPUI_WINDOWS_OK)
      return status;
  }
  if (bytes > GPUI_TEXT_MAX_PENDING_BYTES - host->editor_payload_total) {
    free(utf8);
    return gpui_composition_resource_fail(host);
  }
  if (host->event_count >= GPUI_EVENT_CAPACITY) {
    free(utf8);
    return gpui_composition_resource_fail(host);
  }
  if (host->sequence < 0 ||
      host->sequence > INT64_C(9007199254740991) - 1) {
    free(utf8);
    return gpui_composition_resource_fail(host);
  }
  int32_t slot =
      (host->event_read + host->event_count) % GPUI_EVENT_CAPACITY;
  gpui_text_session_set_platform_slot(host, slot);
  double *event = host->events[slot];
  event[0] = 17.0;
  event[1] = host->window_id;
  event[2] = (double)++host->sequence;
  event[3] = host->scale > 0.0 ? host->scale : 1.0;
  event[4] = (double)cursor;
  event[5] = (double)units;
  event[6] = 0.0;
  event[7] = 0.0;
  event[8] = (double)code;
  event[9] = 0.0;
  host->editor_events[slot] = FALSE;
  host->editor_payloads[slot] = utf8;
  host->editor_payload_bytes[slot] = bytes;
  host->editor_payload_total += bytes;
  host->event_count++;
  return GPUI_WINDOWS_OK;
}

static int32_t gpui_composition_apply(gpui_windows_host *host, int32_t kind,
                                      const WCHAR *text, int32_t units,
                                      int32_t cursor) {
  if (!host || !g_gpui_composition.armed)
    return GPUI_WINDOWS_STALE;
  if (kind == 0) {
    if (g_gpui_composition.composing)
      return GPUI_WINDOWS_OK;
    int32_t status = gpui_composition_emit(host, 0, NULL, 0, 0);
    if (status == GPUI_WINDOWS_OK) {
      g_gpui_composition.composing = TRUE;
      g_gpui_composition.commit_waiting_end = FALSE;
      g_gpui_composition.suppress_ime_char_until_end = FALSE;
      g_gpui_composition.awaiting_fresh_start = FALSE;
      gpui_composition_clear_marked();
    }
    return status;
  }
  if (kind == 1) {
    int32_t status =
        gpui_composition_validate_wide(text, units,
                                       GPUI_COMPOSITION_MAX_PREEDIT_UNITS);
    if (status != GPUI_WINDOWS_OK)
      return status;
    if (units == 0) {
      if (g_gpui_composition.composing)
        status = gpui_composition_emit(host, 3, NULL, 0, 0);
      if (status == GPUI_WINDOWS_OK) {
        g_gpui_composition.composing = FALSE;
        g_gpui_composition.commit_waiting_end = FALSE;
        g_gpui_composition.suppress_ime_char_until_end = FALSE;
        g_gpui_composition.awaiting_fresh_start = TRUE;
        gpui_composition_clear_marked();
      }
      return status;
    }
    if (cursor < 0 || cursor > units ||
        !gpui_text_wide_boundary(text, units, cursor))
      return GPUI_WINDOWS_INVALID;
    if (!g_gpui_composition.composing) {
      status = gpui_composition_emit(host, 0, NULL, 0, 0);
      if (status != GPUI_WINDOWS_OK)
        return status;
      g_gpui_composition.composing = TRUE;
      g_gpui_composition.commit_waiting_end = FALSE;
      g_gpui_composition.suppress_ime_char_until_end = FALSE;
      g_gpui_composition.awaiting_fresh_start = FALSE;
    }
    status = gpui_composition_store_marked(text, units);
    if (status != GPUI_WINDOWS_OK)
      return status;
    return gpui_composition_emit(host, 1, text, units, cursor);
  }
  if (kind == 2) {
    int32_t status =
        gpui_composition_validate_wide(text, units,
                                       GPUI_COMPOSITION_MAX_COMMIT_UNITS);
    if (status != GPUI_WINDOWS_OK)
      return status;
    status = gpui_composition_emit(host, 2, text, units, 0);
    if (status == GPUI_WINDOWS_OK) {
      gpui_composition_clear_marked();
      g_gpui_composition.composing = FALSE;
      g_gpui_composition.commit_waiting_end = TRUE;
      g_gpui_composition.suppress_ime_char_until_end = TRUE;
      g_gpui_composition.awaiting_fresh_start = FALSE;
    }
    return status;
  }
  if (kind == 3) {
    int32_t status = GPUI_WINDOWS_OK;
    if (g_gpui_composition.composing)
      status = gpui_composition_emit(host, 3, NULL, 0, 0);
    if (status == GPUI_WINDOWS_OK) {
      gpui_composition_clear_marked();
      g_gpui_composition.composing = FALSE;
      g_gpui_composition.commit_waiting_end = FALSE;
      g_gpui_composition.suppress_ime_char_until_end = FALSE;
      g_gpui_composition.awaiting_fresh_start = TRUE;
    }
    return status;
  }
  return GPUI_WINDOWS_INVALID;
}

static int32_t gpui_composition_end(gpui_windows_host *host) {
  int32_t status = GPUI_WINDOWS_OK;
  if (g_gpui_composition.composing)
    status = gpui_composition_emit(host, 3, NULL, 0, 0);
  if (status == GPUI_WINDOWS_OK) {
    gpui_composition_clear_marked();
    g_gpui_composition.composing = FALSE;
    g_gpui_composition.commit_waiting_end = FALSE;
    g_gpui_composition.suppress_ime_char_until_end = FALSE;
    g_gpui_composition.awaiting_fresh_start = TRUE;
  }
  return status;
}

static int32_t gpui_composition_set_rect(gpui_windows_host *host,
                                         HIMC context) {
  return gpui_text_session_set_ime_rect(
      context, host->scale, g_gpui_composition.caret_x,
      g_gpui_composition.caret_y, g_gpui_composition.caret_width,
      g_gpui_composition.caret_height);
}

static HIMC gpui_composition_acquire_context(gpui_windows_host *host,
                                             HWND hwnd) {
  if (!g_gpui_composition.armed || !g_gpui_imm.module || !host || !hwnd ||
      !host->api.get_focus || host->api.get_focus() != hwnd)
    return NULL;
  HIMC context = g_gpui_imm.get_context(hwnd);
  if (!context)
    return NULL;
  if (context != g_gpui_composition.expected_himc) {
    g_gpui_imm.release_context(hwnd, context);
    return NULL;
  }
  return context;
}

static void gpui_composition_disarm_native(gpui_windows_host *host) {
  if (!host)
    return;
  g_gpui_composition.suppress_ime_messages = TRUE;
  if (host->hwnd && g_gpui_imm.module &&
      g_gpui_composition.expected_himc) {
    HIMC context = g_gpui_imm.get_context(host->hwnd);
    if (context) {
      if (context == g_gpui_composition.expected_himc)
        g_gpui_imm.notify_ime(context, NI_COMPOSITIONSTR, CPS_CANCEL, 0);
      g_gpui_imm.release_context(host->hwnd, context);
    }
  }
  if (host->hwnd && g_gpui_imm.module)
    gpui_text_session_flush_ime_messages(host, host->hwnd);
  g_gpui_composition.expected_himc = NULL;
  g_gpui_composition.suppress_ime_messages = FALSE;
}

static int32_t gpui_composition_reassociate(gpui_windows_host *host) {
  if (!host || !host->hwnd || !g_gpui_imm.module)
    return GPUI_WINDOWS_UNSUPPORTED;
  g_gpui_composition.suppress_ime_messages = TRUE;
  HIMC prior = g_gpui_imm.associate_context(host->hwnd, NULL);
  if (!prior) {
    g_gpui_composition.suppress_ime_messages = FALSE;
    return GPUI_WINDOWS_UNSUPPORTED;
  }
  g_gpui_imm.notify_ime(prior, NI_COMPOSITIONSTR, CPS_CANCEL, 0);
  gpui_text_session_flush_ime_messages(host, host->hwnd);
  HIMC detached = g_gpui_imm.associate_context(host->hwnd, prior);
  if (detached != NULL) {
    g_gpui_imm.associate_context(host->hwnd, detached);
    g_gpui_composition.suppress_ime_messages = FALSE;
    return GPUI_WINDOWS_STALE;
  }
  HIMC current = g_gpui_imm.get_context(host->hwnd);
  if (!current) {
    g_gpui_composition.suppress_ime_messages = FALSE;
    return GPUI_WINDOWS_STALE;
  }
  BOOL same = current == prior;
  g_gpui_imm.release_context(host->hwnd, current);
  if (!same) {
    g_gpui_composition.suppress_ime_messages = FALSE;
    return GPUI_WINDOWS_STALE;
  }
  g_gpui_composition.expected_himc = prior;
  g_gpui_composition.suppress_ime_messages = FALSE;
  return GPUI_WINDOWS_OK;
}

static void gpui_composition_fail(gpui_windows_host *host, int32_t status) {
  if (!host || status == GPUI_WINDOWS_OK)
    return;
  if (!host->error)
    InterlockedExchange(&host->error, status);
  g_gpui_composition.composing = FALSE;
  g_gpui_composition.commit_waiting_end = FALSE;
  g_gpui_composition.suppress_ime_char_until_end = FALSE;
  g_gpui_composition.suppress_ime_messages = TRUE;
  g_gpui_composition.awaiting_fresh_start = FALSE;
  gpui_composition_clear_marked();
  gpui_composition_disarm_native(host);
  g_gpui_composition.armed = FALSE;
}

static void gpui_composition_focus_lost(gpui_windows_host *host) {
  if (!host || !g_gpui_composition.armed)
    return;
  if (g_gpui_composition.composing)
    (void)gpui_composition_emit(host, 3, NULL, 0, 0);
  g_gpui_composition.composing = FALSE;
  g_gpui_composition.commit_waiting_end = FALSE;
  g_gpui_composition.suppress_ime_char_until_end = FALSE;
  g_gpui_composition.awaiting_fresh_start = FALSE;
  gpui_composition_clear_marked();
  gpui_composition_disarm_native(host);
  g_gpui_composition.armed = FALSE;
  g_gpui_composition.window_id = 0;
}

static void gpui_composition_forget_window(gpui_windows_host *host,
                                           int32_t window) {
  if (!host || g_gpui_composition.window_id != window)
    return;
  g_gpui_composition.composing = FALSE;
  g_gpui_composition.commit_waiting_end = FALSE;
  g_gpui_composition.suppress_ime_char_until_end = FALSE;
  gpui_composition_clear_marked();
  gpui_composition_disarm_native(host);
  gpui_composition_zero_state();
}

static void gpui_composition_shutdown(gpui_windows_host *host) {
  if (g_gpui_composition.armed)
    gpui_composition_disarm_native(host);
  gpui_composition_clear_marked();
  gpui_composition_zero_state();
}

static void gpui_composition_reset(void) {
  gpui_composition_clear_marked();
  gpui_composition_zero_state();
}

int32_t gpui_windows_set_text_composition(int32_t token, int32_t window,
                                          int32_t enabled) {
  int32_t status = check_window(token, window);
  if (status != GPUI_WINDOWS_OK)
    return status;
  if (enabled != 0 && enabled != 1)
    return GPUI_WINDOWS_INVALID;
  if (enabled) {
    if (g_gpui_composition.armed)
      return g_gpui_composition.window_id == window ? GPUI_WINDOWS_OK
                                                    : GPUI_WINDOWS_STALE;
    if (g_gpui_text_session.armed)
      return GPUI_WINDOWS_BUSY;
    status = gpui_text_imm_init();
    if (status != GPUI_WINDOWS_OK)
      return status;
    g_gpui_composition.window_id = window;
    if (!gpui_composition_rect_valid(
            g_gpui_composition.caret_x, g_gpui_composition.caret_y,
            g_gpui_composition.caret_width,
            g_gpui_composition.caret_height)) {
      g_gpui_composition.caret_x = 0.0;
      g_gpui_composition.caret_y = 0.0;
      g_gpui_composition.caret_width = 1.0;
      g_gpui_composition.caret_height = 18.0;
    }
    g_gpui_composition.expected_himc = NULL;
    status = gpui_composition_reassociate(&g_host);
    if (status != GPUI_WINDOWS_OK) {
      g_gpui_composition.window_id = 0;
      return status;
    }
    g_gpui_composition.armed = TRUE;
    g_gpui_composition.composing = FALSE;
    g_gpui_composition.commit_waiting_end = FALSE;
    g_gpui_composition.suppress_ime_char_until_end = FALSE;
    g_gpui_composition.suppress_ime_messages = FALSE;
    g_gpui_composition.awaiting_fresh_start = TRUE;
    gpui_composition_clear_marked();
    return GPUI_WINDOWS_OK;
  }
  if (!g_gpui_composition.armed)
    return GPUI_WINDOWS_OK;
  if (g_gpui_composition.window_id != window)
    return GPUI_WINDOWS_STALE;
  if (g_gpui_composition.composing) {
    status = gpui_composition_emit(&g_host, 3, NULL, 0, 0);
    if (status != GPUI_WINDOWS_OK)
      return status;
  }
  g_gpui_composition.composing = FALSE;
  g_gpui_composition.commit_waiting_end = FALSE;
  g_gpui_composition.suppress_ime_char_until_end = FALSE;
  gpui_composition_clear_marked();
  gpui_composition_disarm_native(&g_host);
  g_gpui_composition.armed = FALSE;
  g_gpui_composition.awaiting_fresh_start = FALSE;
  g_gpui_composition.window_id = 0;
  return GPUI_WINDOWS_OK;
}

int32_t gpui_windows_set_text_composition_caret(int32_t token, int32_t window,
                                                double x, double y,
                                                double width, double height) {
  int32_t status = check_window(token, window);
  if (status != GPUI_WINDOWS_OK)
    return status;
  if (!gpui_composition_rect_valid(x, y, width, height))
    return GPUI_WINDOWS_INVALID;
  g_gpui_composition.caret_x = x;
  g_gpui_composition.caret_y = y;
  g_gpui_composition.caret_width = width;
  g_gpui_composition.caret_height = height;
  if (g_gpui_composition.armed &&
      g_gpui_composition.window_id == window) {
    HIMC context = gpui_composition_acquire_context(&g_host, g_host.hwnd);
    if (context) {
      (void)gpui_composition_set_rect(&g_host, context);
      g_gpui_imm.release_context(g_host.hwnd, context);
    }
  }
  return GPUI_WINDOWS_OK;
}

int32_t gpui_windows_finish_text_composition(int32_t token, int32_t window,
                                             int32_t commit) {
  int32_t status = check_window(token, window);
  if (status != GPUI_WINDOWS_OK)
    return status;
  if (commit != 0 && commit != 1)
    return GPUI_WINDOWS_INVALID;
  if (!g_gpui_composition.armed ||
      g_gpui_composition.window_id != window)
    return GPUI_WINDOWS_STALE;
  if (commit) {
    if (g_gpui_composition.composing &&
        g_gpui_composition.marked_units > 0) {
      status = gpui_composition_emit(
          &g_host, 2, g_gpui_composition.marked,
          g_gpui_composition.marked_units, 0);
      if (status != GPUI_WINDOWS_OK)
        return status;
    }
  } else if (g_gpui_composition.composing) {
    status = gpui_composition_emit(&g_host, 3, NULL, 0, 0);
    if (status != GPUI_WINDOWS_OK)
      return status;
  }
  g_gpui_composition.composing = FALSE;
  g_gpui_composition.commit_waiting_end = FALSE;
  g_gpui_composition.suppress_ime_char_until_end = FALSE;
  gpui_composition_clear_marked();
  gpui_composition_disarm_native(&g_host);
  g_gpui_composition.awaiting_fresh_start = TRUE;
  return GPUI_WINDOWS_OK;
}

static int32_t gpui_composition_compose_message(gpui_windows_host *host,
                                                HWND hwnd, LPARAM flags) {
  DWORD composition_flags = (DWORD)flags;
  BOOL result_present = (composition_flags & GCS_RESULTSTR) != 0;
  BOOL marked_present = (composition_flags & GCS_COMPSTR) != 0;
  if (composition_flags == 0)
    return gpui_composition_end(host);
  if (!result_present && !marked_present)
    return GPUI_WINDOWS_OK;
  HIMC context = gpui_composition_acquire_context(host, hwnd);
  if (!context)
    return GPUI_WINDOWS_STALE;
  (void)gpui_composition_set_rect(host, context);
  WCHAR *result = NULL;
  WCHAR *marked = NULL;
  int32_t result_units = 0;
  int32_t marked_units = 0;
  int32_t status = GPUI_WINDOWS_OK;
  if (result_present)
    status = gpui_composition_read_imm_string(
        context, GCS_RESULTSTR, GPUI_COMPOSITION_MAX_COMMIT_UNITS, &result,
        &result_units);
  if (status == GPUI_WINDOWS_OK && marked_present)
    status = gpui_composition_read_imm_string(
        context, GCS_COMPSTR, GPUI_COMPOSITION_MAX_PREEDIT_UNITS, &marked,
        &marked_units);
  int32_t cursor = marked_units;
  if (status == GPUI_WINDOWS_OK && marked_present) {
    LONG position = g_gpui_imm.get_composition_string_w(
        context, GCS_CURSORPOS, NULL, 0);
    if (position >= 0 && position <= marked_units &&
        gpui_text_wide_boundary(marked, marked_units, (int32_t)position))
      cursor = (int32_t)position;
  }
  g_gpui_imm.release_context(hwnd, context);
  if (status == GPUI_WINDOWS_OK && result_present)
    status = gpui_composition_apply(host, 2, result, result_units, 0);
  if (status == GPUI_WINDOWS_OK && marked_present)
    status = gpui_composition_apply(host, 1, marked, marked_units, cursor);
  free(result);
  free(marked);
  return status;
}

static BOOL gpui_composition_wndproc(gpui_windows_host *host, HWND hwnd,
                                     UINT message, WPARAM wparam,
                                     LPARAM lparam, LRESULT *result) {
  if (!host || !result)
    return FALSE;
  if (!g_gpui_composition.armed ||
      g_gpui_composition.window_id != host->window_id)
    return FALSE;
  BOOL ime_message = message == WM_IME_STARTCOMPOSITION ||
                     message == WM_IME_ENDCOMPOSITION ||
                     message == WM_IME_COMPOSITION ||
                     message == WM_IME_CHAR ||
                     message == WM_IME_SETCONTEXT ||
                     message == WM_IME_NOTIFY ||
                     message == WM_IME_CONTROL ||
                     message == WM_IME_COMPOSITIONFULL ||
                     message == WM_IME_SELECT ||
                     message == WM_IME_REQUEST ||
                     message == WM_IME_KEYDOWN || message == WM_IME_KEYUP;
  if (g_gpui_composition.suppress_ime_messages &&
      (ime_message || message == WM_CHAR || message == WM_UNICHAR)) {
    *result = 0;
    return TRUE;
  }
  if (message == WM_IME_SETCONTEXT) {
    if (wparam)
      lparam &= ~((LPARAM)ISC_SHOWUICOMPOSITIONWINDOW);
    *result = host->api.def_window_proc_w(hwnd, message, wparam, lparam);
    return TRUE;
  }
  BOOL active = g_gpui_composition.composing ||
                g_gpui_composition.commit_waiting_end;
  if (active && (message == WM_KEYDOWN || message == WM_SYSKEYDOWN ||
                 message == WM_KEYUP || message == WM_SYSKEYUP)) {
    if (wparam == VK_RETURN || wparam == VK_ESCAPE) {
      *result = 0;
      return TRUE;
    }
    int32_t mods = modifiers_from_message(host, 0);
    BOOL command_shortcut =
        shortcut_key_candidate(wparam) && (mods & (2 | 4 | 8)) &&
        !((mods & 2) && (mods & 4));
    if (command_shortcut)
      return FALSE;
    *result = host->api.def_window_proc_w(hwnd, message, wparam, lparam);
    return TRUE;
  }
  if (active && (message == WM_IME_KEYDOWN || message == WM_IME_KEYUP)) {
    if (wparam == VK_RETURN || wparam == VK_ESCAPE) {
      *result = 0;
      return TRUE;
    }
    return FALSE;
  }
  if (active && (message == WM_CHAR || message == WM_IME_CHAR ||
                 message == WM_UNICHAR)) {
    *result = 0;
    return TRUE;
  }
  int32_t status = GPUI_WINDOWS_OK;
  switch (message) {
  case WM_IME_STARTCOMPOSITION: {
    *result = 0;
    if (g_gpui_composition.composing)
      return TRUE;
    HIMC context = gpui_composition_acquire_context(host, hwnd);
    if (context) {
      (void)gpui_composition_set_rect(host, context);
      g_gpui_imm.release_context(hwnd, context);
    }
    status = gpui_composition_apply(host, 0, NULL, 0, 0);
    if (status != GPUI_WINDOWS_OK)
      gpui_composition_fail(host, status);
    return TRUE;
  }
  case WM_IME_COMPOSITION:
    *result = 0;
    status = gpui_composition_compose_message(host, hwnd, lparam);
    if (status != GPUI_WINDOWS_OK && status != GPUI_WINDOWS_STALE)
      gpui_composition_fail(host, status);
    return TRUE;
  case WM_IME_ENDCOMPOSITION:
    *result = 0;
    status = gpui_composition_end(host);
    if (status != GPUI_WINDOWS_OK)
      gpui_composition_fail(host, status);
    return TRUE;
  default:
    return FALSE;
  }
}

int32_t gpui_windows_composition_text_size(int32_t token) {
  int32_t status = check_host(token, TRUE);
  if (status != GPUI_WINDOWS_OK)
    return -status;
  if (!g_host.composition_text_valid)
    return -GPUI_WINDOWS_STALE;
  return g_host.composition_text_bytes;
}

int32_t gpui_windows_composition_text_copy(int32_t token, uint8_t *output,
                                           int32_t capacity) {
  int32_t status = check_host(token, TRUE);
  if (status != GPUI_WINDOWS_OK)
    return -status;
  if (!g_host.composition_text_valid)
    return -GPUI_WINDOWS_STALE;
  int32_t bytes = g_host.composition_text_bytes;
  if (capacity < 0 || (capacity > 0 && !output) || capacity < bytes)
    return -GPUI_WINDOWS_RESOURCE;
  if (bytes > 0)
    memcpy(output, g_host.composition_text, (size_t)bytes);
  return bytes;
}

int32_t gpui_windows_test_post_composition(int32_t token, int32_t window,
                                           int32_t kind, int32_t cursor,
                                           const uint8_t *text,
                                           int32_t text_length) {
  int32_t status = check_window(token, window);
  if (status != GPUI_WINDOWS_OK)
    return status;
  if (!native_e2e_enabled())
    return GPUI_WINDOWS_UNSUPPORTED;
  if (kind < 0 || kind > 3 || text_length < 0 ||
      (text_length > 0 && !text))
    return GPUI_WINDOWS_INVALID;
  if (kind == 0 || kind == 3) {
    if (text_length != 0 || cursor != 0)
      return GPUI_WINDOWS_INVALID;
    return gpui_composition_apply(&g_host, kind, NULL, 0, 0);
  }
  int32_t limit = kind == 1 ? GPUI_COMPOSITION_MAX_PREEDIT_UNITS
                            : GPUI_COMPOSITION_MAX_COMMIT_UNITS;
  WCHAR *wide = NULL;
  int32_t units = 0;
  status =
      gpui_composition_utf8_to_wide(text, text_length, limit, &wide, &units);
  if (status != GPUI_WINDOWS_OK)
    return status;
  if (kind == 1 && (cursor < 0 || cursor > units ||
                    !gpui_text_wide_boundary(wide, units, cursor))) {
    free(wide);
    return GPUI_WINDOWS_INVALID;
  }
  status = gpui_composition_apply(&g_host, kind, wide, units,
                                  kind == 1 ? cursor : 0);
  free(wide);
  return status;
}
