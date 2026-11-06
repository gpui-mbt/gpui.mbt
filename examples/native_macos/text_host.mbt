///|
/// Fail the process with a stable label; the E2E runner treats any abort as a
/// failed case rather than a skipped one.
fn text_host_fail(label : String, error : @diagnostics.FrameworkError) -> Unit {
  abort(label + ": " + error.operation() + ": " + error.code().label())
}

///|
fn text_host_expect(
  result : Result[Unit, @diagnostics.FrameworkError],
  label : String,
) -> Unit {
  match result {
    Ok(_) => ()
    Err(error) => text_host_fail(label, error)
  }
}

///|
fn text_host_expect_window(
  result : Result[@platform.WindowId, @diagnostics.FrameworkError],
  label : String,
) -> @platform.WindowId {
  match result {
    Ok(value) => value
    Err(error) => {
      text_host_fail(label, error)
      abort("unreachable")
    }
  }
}

///|
/// Real AppKit text-host proof. Synthetic `NSTextInputClient` frames exercise the
/// same callbacks an input method uses; this is transport evidence, not real
/// Japanese IME qualification, which stays `NOT_RUN`.
fn native_text_host_e2e(host : @macos.Host) -> Unit {
  match host.require_capability(@platform.TextInput) {
    Ok(_) => ()
    Err(error) => text_host_fail("text input capability", error)
  }
  match host.require_capability(@platform.TextInputGeometry) {
    Ok(_) =>
      abort("text input geometry was advertised without a portable report")
    Err(_) => ()
  }
  let window = text_host_expect_window(
    host.create_window("gpui.mbt — native text host", 640.0, 360.0),
    "create window",
  )
  let document = match @text.TextDocument::new("") {
    Ok(value) => value
    Err(_) => abort("empty document rejected")
  }
  let helper = match
    @macos_app.MacosTextFieldHost::start(
      2UL,
      window,
      1UL,
      @primitives.Rect::new(8.0, 8.0, 320.0, 44.0).unwrap(),
      18.0,
      document,
      host,
    ) {
    Ok(value) => value
    Err(_) => abort("the reusable text host helper rejected the window")
  }
  let binding = helper.binding()
  let caret = match helper.field().caret_rect() {
    Ok(value) => value
    Err(_) => abort("TextField refused caret geometry")
  }
  if binding.window() != window || binding.epoch() == 0UL {
    abort("start published an invalid binding")
  }
  text_host_expect(
    host.post_test_composition(window, @primitives.Start),
    "post start",
  )
  text_host_expect(
    host.post_test_composition(
      window,
      @primitives.Update(text="にほんご", cursor_utf16=4),
    ),
    "post preedit",
  )
  match helper.pump(host) {
    Ok(@text_adapter.Applied(_)) => {
      if !helper.field().is_composing() {
        abort("preedit did not enter composition")
      }
      if helper.field().committed_document().text() != "" {
        abort("preedit changed the committed document")
      }
    }
    Ok(@text_adapter.Idle) => abort("preedit was not applied: idle")
    Ok(@text_adapter.FocusLost) => abort("preedit was not applied: focus lost")
    Err(@macos_app.Adapter(@text_adapter.Host(error))) =>
      text_host_fail("preedit host", error)
    Err(_) => abort("preedit was not applied")
  }
  text_host_expect(
    host.post_test_composition(window, @primitives.Commit(text="日本語")),
    "post commit",
  )
  match helper.pump(host) {
    Ok(@text_adapter.Applied(_)) =>
      if helper.field().committed_document().text() != "日本語" {
        abort("commit did not reach the committed document")
      }
    _ => abort("commit was not applied")
  }
  // A synthetic double click must decode its AppKit click count and select the
  // committed word through the shared TextField.
  text_host_expect(
    host.post_test_click_count(
      window,
      @primitives.Point::new(12.0, 20.0).unwrap(),
      2,
    ),
    "post double click",
  )
  let mut multi_click : @primitives.InputEvent? = None
  for _ in 0..<32 {
    if multi_click is Some(_) {
      break
    }
    match host.next_event(timeout_ms=16) {
      Ok(Some(event)) =>
        match event.kind() {
          @platform.Input(input) =>
            if input is @primitives.PointerButtonMultiClick(..) {
              multi_click = Some(input)
            }
          _ => ()
        }
      _ => ()
    }
  }
  let click = match multi_click {
    Some(value) => value
    None => abort("native double click did not reach the portable event")
  }
  match click {
    @primitives.PointerButtonMultiClick(click_count~, ..) =>
      if click_count != 2 {
        abort("native double click reported the wrong count")
      }
    _ => abort("unreachable")
  }
  match
    helper
    .field()
    .handle_input(
      click,
      fn(candidate) { helper.adapter().measure(candidate) },
      fn(candidate, measurement) {
        helper.adapter().admit(candidate, measurement)
      },
      fn(candidate, point) { helper.adapter().hit(candidate, point) },
    ) {
    Ok((selected, _)) =>
      if selected.selection().anchor() != 0 || selected.selection().head() != 3 {
        abort("double click did not select the committed word")
      }
    Err(_) => abort("field rejected the double-click event")
  }
  // A stale epoch is rejected by the host before any native call.
  match
    host.update_text_input(
      binding.epoch() + 1UL,
      @text_host.TextInputState::new(document, caret),
    ) {
    Err(error) =>
      match error.code() {
        @diagnostics.StaleHandle => ()
        _ => text_host_fail("stale epoch", error)
      }
    Ok(_) => abort("stale epoch was accepted")
  }
  // Cancelling a composition restores the committed value.
  text_host_expect(
    host.post_test_composition(window, @primitives.Start),
    "post cancel start",
  )
  text_host_expect(
    host.post_test_composition(
      window,
      @primitives.Update(text="あ", cursor_utf16=1),
    ),
    "post cancel preedit",
  )
  ignore(helper.pump(host))
  text_host_expect(
    host.finish_text_composition(window, false),
    "finish composition",
  )
  match helper.pump(host) {
    Ok(@text_adapter.Applied(_)) => {
      if helper.field().committed_document().text() != "日本語" {
        abort("cancel changed the committed document")
      }
      if helper.field().is_composing() {
        abort("cancel left the field composing")
      }
    }
    _ => abort("cancel was not applied")
  }
  // This automation context cannot take real keyboard focus, so the key state
  // is forced through the test hook. Real window-activation loss stays NOT_RUN.
  text_host_expect(host.post_test_focus(Some(true)), "force focus")
  match helper.pump(host) {
    Ok(@text_adapter.Idle) => ()
    _ => abort("a focused transport was not idle")
  }
  text_host_expect(host.post_test_focus(Some(false)), "drop focus")
  match helper.pump(host) {
    Ok(@text_adapter.FocusLost) => ()
    _ => abort("focus loss was not reported")
  }
  text_host_expect(host.post_test_focus(None), "restore focus")
  if !helper.is_ended() {
    abort("focus loss did not end the helper")
  }
  // The adapter ends the transport when focus is lost.
  match
    host.update_text_input(
      binding.epoch(),
      @text_host.TextInputState::new(document, caret),
    ) {
    Err(error) =>
      match error.code() {
        @diagnostics.StaleHandle => ()
        _ => text_host_fail("ended transport", error)
      }
    Ok(_) => abort("the transport stayed live after focus loss")
  }
  println(
    "GPUI_MACOS_TEXT_HOST {\"epoch\":\{binding.epoch()},\"preedit\":true,\"commit\":true,\"cancel\":true,\"double_click\":true,\"multi_click_source\":\"appkit\",\"stale_epoch\":true,\"focus_lost\":true,\"focus_source\":\"test_hook\",\"real_window_focus\":\"NOT_RUN\",\"capability\":\"text_input_only\",\"synthetic_input\":true,\"real_ime\":\"NOT_RUN\"}",
  )
}

///|
fn run_text_host_mode() -> Unit {
  let host = match @macos.Host::start() {
    Ok(value) => value
    Err(error) => {
      text_host_fail("startup", error)
      abort("unreachable")
    }
  }
  native_text_host_e2e(host)
  match host.stop() {
    Ok(_) => ()
    Err(error) => text_host_fail("stop", error)
  }
}
