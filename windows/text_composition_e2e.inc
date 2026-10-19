/* Production-path staging for the opt-in portable composition transport. The
 * fake IMM layer records forms and notifies; no physical IME is involved. */
static int32_t gpui_composition_test_slot(gpui_windows_host *host,
                                          int32_t offset) {
  return (host->event_read + offset) % GPUI_EVENT_CAPACITY;
}

static int32_t gpui_composition_test_code(gpui_windows_host *host,
                                          int32_t offset) {
  return (int32_t)host->events[gpui_composition_test_slot(host, offset)][8];
}

static int32_t gpui_composition_test_units(gpui_windows_host *host,
                                           int32_t offset) {
  return (int32_t)host->events[gpui_composition_test_slot(host, offset)][5];
}

static int32_t gpui_composition_test_cursor(gpui_windows_host *host,
                                            int32_t offset) {
  return (int32_t)host->events[gpui_composition_test_slot(host, offset)][4];
}

static BOOL gpui_composition_test_text_is(gpui_windows_host *host,
                                          int32_t offset,
                                          const uint8_t *expected,
                                          int32_t bytes) {
  int32_t slot = gpui_composition_test_slot(host, offset);
  return host->editor_payload_bytes[slot] == bytes &&
         (bytes == 0 ||
          (host->editor_payloads[slot] &&
           memcmp(host->editor_payloads[slot], expected, (size_t)bytes) == 0));
}

int32_t gpui_windows_test_composition_staging(int32_t *failed_stage) {
  if (!failed_stage)
    return GPUI_WINDOWS_INVALID;
  *failed_stage = 0;
  gpui_windows_host *saved_host =
      (gpui_windows_host *)malloc(sizeof(gpui_windows_host));
  if (!saved_host)
    return GPUI_WINDOWS_RESOURCE;
  memcpy(saved_host, &g_host, sizeof(g_host));
  gpui_text_session_state saved_session = g_gpui_text_session;
  gpui_composition_state saved_composition = g_gpui_composition;
  gpui_imm_api saved_imm = g_gpui_imm;
  HWND saved_focus = gpui_text_review_focus_hwnd;
  LONG saved_claimed = InterlockedCompareExchange(&g_host_claimed, 0, 0);
  InterlockedExchange(&g_host_claimed, 1);
  ZeroMemory(&g_gpui_text_session, sizeof(g_gpui_text_session));
  ZeroMemory(&g_gpui_imm, sizeof(g_gpui_imm));
  gpui_text_review_setup_host();
  g_gpui_imm.module = (HMODULE)(uintptr_t)1;
  g_gpui_imm.get_context = gpui_text_review_ime_get_context;
  g_gpui_imm.release_context = gpui_text_review_release_context;
  g_gpui_imm.associate_context = gpui_text_review_associate_context;
  g_gpui_imm.get_composition_string_w =
      gpui_text_review_get_composition_string;
  g_gpui_imm.set_composition_window =
      gpui_text_review_set_composition_window;
  g_gpui_imm.set_candidate_window = gpui_text_review_set_candidate_window;
  g_gpui_imm.notify_ime = gpui_text_review_notify_ime;
  g_gpui_text_session.epoch_counter = 300;
  ZeroMemory(&g_gpui_composition, sizeof(g_gpui_composition));
  g_gpui_composition.window_id = 5;
  g_gpui_composition.armed = TRUE;
  g_gpui_composition.expected_himc = gpui_text_review_associated_context;
  g_gpui_composition.awaiting_fresh_start = TRUE;
  g_gpui_composition.caret_x = 10.0;
  g_gpui_composition.caret_y = 20.0;
  g_gpui_composition.caret_width = 2.0;
  g_gpui_composition.caret_height = 18.0;

  int32_t result = GPUI_WINDOWS_OK;
  const WCHAR japanese[] = {0x306b, 0x307b, 0x3093, 0x3054};
  const WCHAR kanji[] = {0x65e5, 0x672c, 0x8a9e};
  const uint8_t japanese_utf8[] = {0xe3, 0x81, 0xab, 0xe3, 0x81, 0xbb,
                                   0xe3, 0x82, 0x93, 0xe3, 0x81, 0x94};
  const uint8_t kanji_utf8[] = {0xe6, 0x97, 0xa5, 0xe6, 0x9c, 0xac,
                                0xe8, 0xaa, 0x9e};
  double event[10];

#define GPUI_COMPOSITION_TEST_REQUIRE(condition, stage)                       \
  do {                                                                        \
    if (!(condition)) {                                                       \
      *failed_stage = (stage);                                                \
      result = GPUI_WINDOWS_NATIVE;                                           \
      goto composition_cleanup;                                               \
    }                                                                         \
  } while (0)

  gpui_text_test_clear_ring(&g_host);
  GPUI_COMPOSITION_TEST_REQUIRE(
      gpui_composition_apply(&g_host, 1, japanese, 4, 4) ==
          GPUI_WINDOWS_OK,
      1);
  GPUI_COMPOSITION_TEST_REQUIRE(
      g_host.event_count == 2 &&
          gpui_composition_test_code(&g_host, 0) == 0 &&
          gpui_composition_test_code(&g_host, 1) == 1 &&
          gpui_composition_test_units(&g_host, 1) == 4 &&
          gpui_composition_test_cursor(&g_host, 1) == 4 &&
          gpui_composition_test_text_is(&g_host, 1, japanese_utf8,
                                        (int32_t)sizeof(japanese_utf8)) &&
          g_gpui_composition.composing,
      2);
  GPUI_COMPOSITION_TEST_REQUIRE(
      gpui_composition_apply(&g_host, 2, kanji, 3, 0) ==
          GPUI_WINDOWS_OK,
      3);
  GPUI_COMPOSITION_TEST_REQUIRE(
      g_host.event_count == 3 &&
          gpui_composition_test_code(&g_host, 2) == 2 &&
          gpui_composition_test_units(&g_host, 2) == 3 &&
          gpui_composition_test_text_is(&g_host, 2, kanji_utf8,
                                        (int32_t)sizeof(kanji_utf8)) &&
          !g_gpui_composition.composing &&
          g_gpui_composition.commit_waiting_end,
      4);
  GPUI_COMPOSITION_TEST_REQUIRE(gpui_composition_end(&g_host) ==
                                   GPUI_WINDOWS_OK &&
                                   g_host.event_count == 3 &&
                                   !g_gpui_composition.commit_waiting_end,
                               5);

  gpui_text_test_clear_ring(&g_host);
  GPUI_COMPOSITION_TEST_REQUIRE(
      gpui_composition_apply(&g_host, 1, japanese, 4, 4) ==
              GPUI_WINDOWS_OK &&
          gpui_composition_apply(&g_host, 3, NULL, 0, 0) ==
              GPUI_WINDOWS_OK,
      6);
  GPUI_COMPOSITION_TEST_REQUIRE(
      g_host.event_count == 3 &&
          gpui_composition_test_code(&g_host, 2) == 3 &&
          !g_gpui_composition.composing,
      7);

  gpui_text_test_clear_ring(&g_host);
  GPUI_COMPOSITION_TEST_REQUIRE(
      gpui_composition_apply(&g_host, 0, NULL, 0, 0) ==
              GPUI_WINDOWS_OK &&
          gpui_composition_apply(&g_host, 1, NULL, 0, 0) ==
              GPUI_WINDOWS_OK &&
          g_host.event_count == 2 &&
          gpui_composition_test_code(&g_host, 0) == 0 &&
          gpui_composition_test_code(&g_host, 1) == 3 &&
          !g_gpui_composition.composing,
      8);

  WCHAR *large = (WCHAR *)calloc(16385, sizeof(WCHAR));
  GPUI_COMPOSITION_TEST_REQUIRE(large != NULL, 9);
  for (int32_t i = 0; i < 16385; ++i)
    large[i] = L'a';
  gpui_text_test_clear_ring(&g_host);
  int32_t oversized =
      gpui_composition_apply(&g_host, 1, large, 16385, 16385);
  free(large);
  GPUI_COMPOSITION_TEST_REQUIRE(
      oversized == GPUI_WINDOWS_INVALID && g_host.event_count == 0,
      10);

  WCHAR *huge = (WCHAR *)calloc(65537, sizeof(WCHAR));
  GPUI_COMPOSITION_TEST_REQUIRE(huge != NULL, 11);
  for (int32_t i = 0; i < 65537; ++i)
    huge[i] = L'a';
  oversized = gpui_composition_apply(&g_host, 2, huge, 65537, 0);
  free(huge);
  GPUI_COMPOSITION_TEST_REQUIRE(
      oversized == GPUI_WINDOWS_INVALID && g_host.event_count == 0,
      12);

  const WCHAR smile[] = {0xd83d, 0xde00};
  GPUI_COMPOSITION_TEST_REQUIRE(
      gpui_composition_apply(&g_host, 1, smile, 2, 1) ==
              GPUI_WINDOWS_INVALID &&
          g_host.event_count == 0,
      13);

  gpui_text_test_clear_ring(&g_host);
  GPUI_COMPOSITION_TEST_REQUIRE(
      gpui_composition_apply(&g_host, 0, NULL, 0, 0) ==
              GPUI_WINDOWS_OK &&
          gpui_composition_apply(&g_host, 1, japanese, 4, 4) ==
              GPUI_WINDOWS_OK,
      14);
  int32_t notify_before = gpui_text_review_notify_calls;
  GPUI_COMPOSITION_TEST_REQUIRE(
      gpui_windows_finish_text_composition(77, 5, 1) ==
              GPUI_WINDOWS_OK &&
          g_host.event_count == 3 &&
          gpui_composition_test_code(&g_host, 2) == 2 &&
          gpui_composition_test_units(&g_host, 2) == 4 &&
          gpui_composition_test_text_is(&g_host, 2, japanese_utf8,
                                        (int32_t)sizeof(japanese_utf8)) &&
          !g_gpui_composition.composing &&
          gpui_text_review_notify_calls > notify_before,
      15);
  GPUI_COMPOSITION_TEST_REQUIRE(
      gpui_text_review_notify_action == NI_COMPOSITIONSTR &&
          gpui_text_review_notify_index == CPS_CANCEL,
      16);

  gpui_text_test_clear_ring(&g_host);
  g_gpui_composition.expected_himc = gpui_text_review_associated_context;
  GPUI_COMPOSITION_TEST_REQUIRE(
      gpui_composition_apply(&g_host, 1, japanese, 4, 4) ==
              GPUI_WINDOWS_OK &&
          gpui_windows_finish_text_composition(77, 5, 0) ==
              GPUI_WINDOWS_OK &&
          g_host.event_count == 3 &&
          gpui_composition_test_code(&g_host, 2) == 3,
      17);
  gpui_text_test_clear_ring(&g_host);
  GPUI_COMPOSITION_TEST_REQUIRE(
      gpui_windows_finish_text_composition(77, 5, 0) ==
              GPUI_WINDOWS_OK &&
          g_host.event_count == 0,
      18);

  /* WndProc must suppress committed text and terminal keys while active. */
  gpui_text_test_clear_ring(&g_host);
  g_gpui_composition.expected_himc = gpui_text_review_associated_context;
  GPUI_COMPOSITION_TEST_REQUIRE(
      gpui_composition_apply(&g_host, 1, japanese, 4, 4) ==
          GPUI_WINDOWS_OK,
      19);
  int32_t before = g_host.event_count;
  (void)gpui_window_proc(g_host.hwnd, WM_CHAR, (WPARAM)L'a', 0);
  (void)gpui_window_proc(g_host.hwnd, WM_KEYDOWN, VK_RETURN, 0);
  (void)gpui_window_proc(g_host.hwnd, WM_KEYDOWN, VK_ESCAPE, 0);
  (void)gpui_window_proc(g_host.hwnd, WM_IME_CHAR, (WPARAM)L'a', 0);
  GPUI_COMPOSITION_TEST_REQUIRE(g_host.event_count == before, 20);

  gpui_text_review_result_text[0] = kanji[0];
  gpui_text_review_result_text[1] = kanji[1];
  gpui_text_review_result_text[2] = kanji[2];
  gpui_text_review_result_units = 3;
  GPUI_COMPOSITION_TEST_REQUIRE(
      gpui_window_proc(g_host.hwnd, WM_IME_COMPOSITION, 0,
                       GCS_RESULTSTR) == 0 &&
          g_host.event_count == before + 1 &&
          gpui_composition_test_code(&g_host, before) == 2 &&
          g_gpui_composition.commit_waiting_end,
      21);
  (void)gpui_window_proc(g_host.hwnd, WM_CHAR, (WPARAM)L'a', 0);
  GPUI_COMPOSITION_TEST_REQUIRE(g_host.event_count == before + 1, 22);
  (void)gpui_window_proc(g_host.hwnd, WM_IME_ENDCOMPOSITION, 0, 0);
  GPUI_COMPOSITION_TEST_REQUIRE(
      g_host.event_count == before + 1 &&
          !g_gpui_composition.commit_waiting_end,
      23);
  (void)gpui_window_proc(g_host.hwnd, WM_CHAR, (WPARAM)L'a', 0);
  GPUI_COMPOSITION_TEST_REQUIRE(
      g_host.event_count == before + 2 &&
          (int32_t)g_host.events[gpui_composition_test_slot(
              &g_host, before + 1)][0] == 16,
      24);

  /* WM_IME_COMPOSITION marked and result+marked paths. */
  gpui_text_test_clear_ring(&g_host);
  g_gpui_composition.expected_himc = gpui_text_review_associated_context;
  gpui_text_review_marked_text = japanese;
  gpui_text_review_marked_units = 4;
  gpui_text_review_cursor_position = 4;
  GPUI_COMPOSITION_TEST_REQUIRE(
      gpui_window_proc(g_host.hwnd, WM_IME_COMPOSITION, 0,
                       GCS_COMPSTR | GCS_CURSORPOS) == 0 &&
          g_host.event_count == 2 &&
          gpui_composition_test_code(&g_host, 0) == 0 &&
          gpui_composition_test_code(&g_host, 1) == 1 &&
          gpui_composition_test_cursor(&g_host, 1) == 4,
      25);
  gpui_text_review_marked_text = NULL;
  gpui_text_review_marked_units = 0;
  gpui_text_test_clear_ring(&g_host);
  g_gpui_composition.expected_himc = gpui_text_review_associated_context;
  gpui_text_review_marked_text = japanese;
  gpui_text_review_marked_units = 4;
  gpui_text_review_cursor_position = 4;
  GPUI_COMPOSITION_TEST_REQUIRE(
      gpui_window_proc(g_host.hwnd, WM_IME_COMPOSITION, 0,
                       GCS_RESULTSTR | GCS_COMPSTR |
                           GCS_CURSORPOS) == 0 &&
          g_host.event_count == 3 &&
          gpui_composition_test_code(&g_host, 0) == 2 &&
          gpui_composition_test_code(&g_host, 1) == 0 &&
          gpui_composition_test_code(&g_host, 2) == 1 &&
          g_gpui_composition.composing &&
          !g_gpui_composition.commit_waiting_end,
      26);

  /* Candidate placement uses the window scale and floor rounding. */
  gpui_text_review_composition_form_valid = FALSE;
  gpui_text_review_candidate_form_valid = FALSE;
  g_host.scale = 1.5;
  GPUI_COMPOSITION_TEST_REQUIRE(
      gpui_windows_set_text_composition_caret(77, 5, 10.0, 20.0, 2.0,
                                              18.0) == GPUI_WINDOWS_OK &&
          gpui_text_review_composition_form_valid &&
          gpui_text_review_candidate_form_valid &&
          gpui_text_review_composition_form.ptCurrentPos.x == 15 &&
          gpui_text_review_composition_form.ptCurrentPos.y == 30 &&
          gpui_text_review_candidate_form.ptCurrentPos.x == 15 &&
          gpui_text_review_candidate_form.ptCurrentPos.y == 57,
      27);
  g_host.scale = 1.0;

  /* The field IMM session and the portable composer are mutually exclusive. */
  gpui_composition_clear_marked();
  g_gpui_composition.armed = FALSE;
  g_gpui_composition.window_id = 5;
  g_gpui_text_session.armed = TRUE;
  GPUI_COMPOSITION_TEST_REQUIRE(
      gpui_windows_set_text_composition(77, 5, 1) ==
          GPUI_WINDOWS_BUSY,
      28);
  g_gpui_text_session.armed = FALSE;
  GPUI_COMPOSITION_TEST_REQUIRE(
      gpui_windows_set_text_composition(77, 5, 1) ==
          GPUI_WINDOWS_OK,
      29);
  GPUI_COMPOSITION_TEST_REQUIRE(
      gpui_windows_session_begin(77, 5, 1, (const uint8_t *)"a", 1, 0, 0,
                                 0.0, 0.0, 1.0, 18.0) ==
          -GPUI_WINDOWS_BUSY,
      30);
  GPUI_COMPOSITION_TEST_REQUIRE(
      gpui_windows_set_text_composition(77, 5, 0) ==
          GPUI_WINDOWS_OK,
      31);

  /* Public next_event must copy the sidecar for that exact event. */
  gpui_text_test_clear_ring(&g_host);
  g_gpui_composition.armed = TRUE;
  g_gpui_composition.window_id = 5;
  g_gpui_composition.expected_himc = gpui_text_review_associated_context;
  g_gpui_composition.composing = FALSE;
  g_gpui_composition.commit_waiting_end = FALSE;
  g_gpui_composition.suppress_ime_char_until_end = FALSE;
  GPUI_COMPOSITION_TEST_REQUIRE(
      gpui_composition_apply(&g_host, 2, kanji, 3, 0) ==
          GPUI_WINDOWS_OK,
      32);
  GPUI_COMPOSITION_TEST_REQUIRE(
      gpui_windows_next(77, event) == 1 && (int32_t)event[0] == 17 &&
          gpui_windows_composition_text_size(77) ==
              (int32_t)sizeof(kanji_utf8),
      33);
  uint8_t copy[16];
  GPUI_COMPOSITION_TEST_REQUIRE(
      gpui_windows_composition_text_copy(77, copy, (int32_t)sizeof(copy)) ==
              (int32_t)sizeof(kanji_utf8) &&
          memcmp(copy, kanji_utf8, sizeof(kanji_utf8)) == 0 &&
          gpui_windows_composition_text_copy(77, copy, 1) ==
              -GPUI_WINDOWS_RESOURCE,
      34);

  /* Queue exhaustion fails closed and keeps no partial record. */
  gpui_text_test_clear_ring(&g_host);
  g_gpui_composition.armed = TRUE;
  g_host.event_count = GPUI_EVENT_CAPACITY;
  GPUI_COMPOSITION_TEST_REQUIRE(
      gpui_composition_apply(&g_host, 1, japanese, 4, 4) ==
              GPUI_WINDOWS_RESOURCE &&
          g_host.error == GPUI_WINDOWS_RESOURCE,
      35);

composition_cleanup:
  gpui_composition_clear_marked();
  g_gpui_text_session = saved_session;
  g_gpui_composition = saved_composition;
  g_gpui_imm = saved_imm;
  gpui_text_review_focus_hwnd = saved_focus;
  InterlockedExchange(&g_host_claimed, saved_claimed);
  memcpy(&g_host, saved_host, sizeof(g_host));
  free(saved_host);
#undef GPUI_COMPOSITION_TEST_REQUIRE
  return result;
}
