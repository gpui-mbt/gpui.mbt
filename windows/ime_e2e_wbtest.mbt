///|
#borrow(failed_stage)
extern "C" fn native_test_composition_staging(
  failed_stage : FixedArray[Int32],
) -> Int32 = "gpui_windows_test_composition_staging"

///|
fn ime_e2e_composition_events(
  events : Array[@platform.Event],
) -> Array[@primitives.CompositionEvent] {
  let compositions : Array[@primitives.CompositionEvent] = []
  for event in events {
    if event.kind() is @platform.Composition(value) {
      compositions.push(value)
    }
  }
  compositions
}

///|
test "Windows IME composition staging suppresses duplicates" {
  if @env.get_env_var("GPUI_WINDOWS_E2E") != Some("1") {
    return
  }
  let original = @env.get_env_var("GPUI_NATIVE_E2E")
  @env.set_env_var("GPUI_NATIVE_E2E", "1")
  let failed_stage = FixedArray::make(1, 0)
  let status = native_test_composition_staging(failed_stage)
  match original {
    Some(value) => @env.set_env_var("GPUI_NATIVE_E2E", value)
    None => @env.unset_env_var("GPUI_NATIVE_E2E")
  }
  if status != 0 {
    fail("composition staging failed at stage \{failed_stage[0]}")
  }
}

///|
test "Windows synthetic IME composition preserves event order" {
  if @env.get_env_var("GPUI_WINDOWS_E2E") != Some("1") {
    return
  }
  let original = @env.get_env_var("GPUI_NATIVE_E2E")
  @env.set_env_var("GPUI_NATIVE_E2E", "1")
  let host = input_hook_required(Host::start())
  let window = input_hook_required(
    host.create_window(320, 120, "synthetic IME composition"),
  )
  input_hook_required(host.set_text_composition(window, true))
  let caret = match @primitives.Rect::new(10.0, 20.0, 2.0, 18.0) {
    Ok(value) => value
    Err(_) => abort("fixture caret")
  }
  input_hook_required(host.set_text_composition_caret(window, caret))
  // Drop creation/focus/frame events before checking composition order.
  ignore(input_hook_required(host.dispatch(0)))

  input_hook_required(
    host.post_test_composition(
      window,
      @primitives.Update(text="にほんご", cursor_utf16=4),
    ),
  )
  let started = match input_hook_required(host.next_event(timeout_ms=0)) {
    Some(event) =>
      match event.kind() {
        @platform.Composition(@primitives.Start) => true
        _ => false
      }
    None => false
  }
  assert_true(started)
  let updated = match input_hook_required(host.next_event(timeout_ms=0)) {
    Some(event) =>
      match event.kind() {
        @platform.Composition(@primitives.Update(text~, cursor_utf16~)) =>
          text == "にほんご" && cursor_utf16 == 4
        _ => false
      }
    None => false
  }
  assert_true(updated)

  input_hook_required(
    host.post_test_composition(window, @primitives.Commit(text="日本語")),
  )
  let commit_events = ime_e2e_composition_events(
    input_hook_required(host.dispatch(0)),
  )
  assert_eq(commit_events.length(), 1)
  match commit_events[0] {
    @primitives.Commit(text~) => assert_eq(text, "日本語")
    _ => fail("expected composition commit")
  }

  input_hook_required(
    host.post_test_composition(
      window,
      @primitives.Update(text="にほんご", cursor_utf16=4),
    ),
  )
  input_hook_required(host.post_test_composition(window, @primitives.Cancel))
  let cancel_events = ime_e2e_composition_events(
    input_hook_required(host.dispatch(0)),
  )
  assert_eq(cancel_events.length(), 3)
  assert_true(cancel_events[0] is @primitives.Start)
  assert_true(cancel_events[1] is @primitives.Update(..))
  assert_true(cancel_events[2] is @primitives.Cancel)

  let invalid_caret = match @primitives.Rect::new(0.0, 0.0, 8193.0, 18.0) {
    Ok(value) => value
    Err(_) => abort("fixture oversized caret")
  }
  assert_true(host.set_text_composition_caret(window, invalid_caret) is Err(_))
  assert_true(
    host.post_test_composition(
      window,
      @primitives.Update(text="あ", cursor_utf16=2),
    )
    is Err(_),
  )
  input_hook_required(host.set_text_composition(window, false))
  input_hook_required(host.destroy_window(window))
  input_hook_required(host.stop())
  match original {
    Some(value) => @env.set_env_var("GPUI_NATIVE_E2E", value)
    None => @env.unset_env_var("GPUI_NATIVE_E2E")
  }
}
