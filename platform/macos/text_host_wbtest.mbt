///|
/// Headless transport fixture. It records the same five operations the AppKit
/// route performs, so epoch, ordering and focus rules stay testable without a
/// window or a native library.
priv struct FakeTextRoute {
  calls : Array[String]
  frames : Array[(@primitives.CompositionEvent, Int64)]
  carets : Array[@primitives.Rect]
  finishes : Array[Bool]
  mut key : Bool
  fail_enable : Ref[Bool]
  fail_caret : Ref[Bool]
}

///|
fn FakeTextRoute::new() -> FakeTextRoute {
  {
    calls: [],
    frames: [],
    carets: [],
    finishes: [],
    key: true,
    fail_enable: Ref(false),
    fail_caret: Ref(false),
  }
}

///|
fn fake_error(operation : String) -> @diagnostics.FrameworkError {
  @diagnostics.FrameworkError::new(
    @diagnostics.InvalidInput,
    operation,
    subsystem="platform",
    backend="test",
  )
}

///|
impl TextRoute for FakeTextRoute with fn enable(
  self,
  window,
  enabled,
  operation,
) {
  ignore(window)
  self.calls.push(if enabled { "enable" } else { "disable" })
  if self.fail_enable.val {
    Err(fake_error(operation))
  } else {
    Ok(())
  }
}

///|
impl TextRoute for FakeTextRoute with fn set_caret(
  self,
  window,
  caret,
  operation,
) {
  ignore(window)
  self.calls.push("caret")
  if self.fail_caret.val {
    return Err(fake_error(operation))
  }
  self.carets.push(caret)
  Ok(())
}

///|
impl TextRoute for FakeTextRoute with fn finish(self, window, commit, operation) {
  ignore(window)
  ignore(operation)
  self.calls.push(if commit { "commit" } else { "cancel" })
  self.finishes.push(commit)
  Ok(())
}

///|
impl TextRoute for FakeTextRoute with fn take(
  self,
  window,
  timeout_ms,
  operation,
) {
  ignore(window)
  ignore(timeout_ms)
  ignore(operation)
  self.calls.push("take")
  if self.frames.is_empty() {
    Ok((None, 0L))
  } else {
    let (kind, sequence) = self.frames.remove(0)
    Ok((Some(kind), sequence))
  }
}

///|
impl TextRoute for FakeTextRoute with fn is_key(self, window, operation) {
  ignore(window)
  ignore(operation)
  Ok(self.key)
}

///|
fn fake_window() -> @platform.WindowId {
  @platform.WindowId::new(7)
}

///|
fn fake_caret() -> @primitives.Rect {
  @primitives.Rect::new(4.0, 2.0, 1.0, 18.0).unwrap()
}

///|
fn fake_state(route : FakeTextRoute) -> (TextHostState, UInt64) {
  match begin_text_route(TextHostState::empty(), route, fake_window(), 1UL) {
    Ok(value) => value
    Err(_) => abort("fake begin failed")
  }
}

///|
test "text host epochs increase and stale commands are rejected" {
  let route = FakeTextRoute::new()
  let (state, epoch) = fake_state(route)
  assert_eq(epoch, 1UL)
  assert_true(route.calls[0] == "enable")
  assert_true(begin_text_route(state, route, fake_window(), 1UL) is Err(_))
  let document = @text.TextDocument::new("日本").unwrap()
  let value = @text_host.TextInputState::new(document, fake_caret())
  let state = match update_text_route(state, route, epoch, value) {
    Ok(next) => next
    Err(_) => abort("update rejected a live epoch")
  }
  assert_eq(route.carets.length(), 1)
  assert_eq(route.carets[0].left(), 4.0)
  assert_true(update_text_route(state, route, epoch + 1UL, value) is Err(_))
  let state = match cancel_text_route(state, route, epoch) {
    Ok(next) => next
    Err(_) => abort("cancel rejected a live epoch")
  }
  assert_eq(route.finishes.length(), 1)
  assert_true(!route.finishes[0])
  let state = match end_text_route(state, route, epoch) {
    Ok(next) => next
    Err(_) => abort("end rejected a live epoch")
  }
  assert_true(end_text_route(state, route, epoch) is Err(_))
  let (_, second) = match begin_text_route(state, route, fake_window(), 1UL) {
    Ok(value) => value
    Err(_) => abort("a closed session blocked the next begin")
  }
  assert_eq(second, 2UL)
}

///|
test "composition start frames are skipped and observations keep order" {
  let route = FakeTextRoute::new()
  let (state, epoch) = fake_state(route)
  route.frames.push((@primitives.Start, 1L))
  route.frames.push(
    (@primitives.Update(text="にほんご", cursor_utf16=4), 2L),
  )
  route.frames.push((@primitives.Commit(text="日本語"), 3L))
  route.frames.push((@primitives.Cancel, 4L))
  let (state, first) = match next_text_route(state, route, 16) {
    Ok(value) => value
    Err(_) => abort("next rejected the session")
  }
  match first {
    Some(event) => {
      assert_eq(event.epoch(), epoch)
      assert_eq(event.window().value(), 7L)
      assert_eq(event.sequence(), 2L)
      assert_true(
        event.kind() is @text_host.Preedit(text="にほんご", cursor=4),
      )
    }
    None => abort("preedit observation missing")
  }
  let (_, second) = match next_text_route(state, route, 16) {
    Ok(value) => value
    Err(_) => abort("next rejected the session")
  }
  match second {
    Some(event) =>
      assert_true(event.kind() is @text_host.Commit(text="日本語"))
    None => abort("commit observation missing")
  }
  let (_, third) = match next_text_route(state, route, 16) {
    Ok(value) => value
    Err(_) => abort("next rejected the session")
  }
  match third {
    Some(event) => assert_true(event.kind() is @text_host.Cancel)
    None => abort("cancel observation missing")
  }
  assert_true(next_text_route(state, route, 16).unwrap().1 is None)
}

///|
test "key loss is reported once and recovers after refocus" {
  let route = FakeTextRoute::new()
  let (state, _) = fake_state(route)
  // A session that never held key focus cannot report a loss.
  route.key = false
  assert_true(next_text_route(state, route, 16).unwrap().1 is None)
  route.key = true
  let (state, _) = next_text_route(state, route, 16).unwrap()
  route.key = false
  let (state, lost) = next_text_route(state, route, 16).unwrap()
  match lost {
    Some(event) => {
      assert_true(event.kind() is @text_host.FocusLost)
      assert_true(event.sequence() < 0L)
    }
    None => abort("focus loss missing")
  }
  assert_true(next_text_route(state, route, 16).unwrap().1 is None)
  route.key = true
  route.frames.push((@primitives.Commit(text="a"), 9L))
  let (state, committed) = next_text_route(state, route, 16).unwrap()
  match committed {
    Some(event) => assert_true(event.kind() is @text_host.Commit(text="a"))
    None => abort("commit after refocus missing")
  }
  route.key = false
  let (_, lost_again) = next_text_route(state, route, 16).unwrap()
  match lost_again {
    Some(event) => assert_eq(event.sequence(), -2L)
    None => abort("second focus loss missing")
  }
}

///|
test "invalid input is rejected before a session starts" {
  let route = FakeTextRoute::new()
  assert_true(
    begin_text_route(
      TextHostState::empty(),
      route,
      @platform.WindowId::new(0),
      1UL,
    )
    is Err(_),
  )
  assert_true(
    begin_text_route(TextHostState::empty(), route, fake_window(), 0UL)
    is Err(_),
  )
  let (state, _) = fake_state(route)
  assert_true(next_text_route(state, route, -1) is Err(_))
  assert_true(next_text_route(state, route, 251) is Err(_))
  assert_true(
    next_text_route(TextHostState::empty(), route, 16).unwrap().1 is None,
  )
}

///|
test "a rejected caret keeps the live session" {
  let route = FakeTextRoute::new()
  let (state, epoch) = fake_state(route)
  let document = @text.TextDocument::new("x").unwrap()
  let value = @text_host.TextInputState::new(document, fake_caret())
  route.fail_caret.val = true
  assert_true(update_text_route(state, route, epoch, value) is Err(_))
  assert_eq(route.carets.length(), 0)
  route.fail_caret.val = false
  assert_true(update_text_route(state, route, epoch, value) is Ok(_))
  assert_true(begin_text_route(state, route, fake_window(), 1UL) is Err(_))
}

///|
test "end drains leftover composition frames" {
  let route = FakeTextRoute::new()
  let (state, epoch) = fake_state(route)
  route.frames.push((@primitives.Start, 1L))
  route.frames.push((@primitives.Update(text="あ", cursor_utf16=1), 2L))
  route.frames.push((@primitives.Cancel, 3L))
  let state = match end_text_route(state, route, epoch) {
    Ok(next) => next
    Err(_) => abort("end rejected a live epoch")
  }
  assert_eq(route.frames.length(), 0)
  assert_true(next_text_route(state, route, 16).unwrap().1 is None)
}

///|
test "update after end is stale and a failed enable issues no session" {
  let route = FakeTextRoute::new()
  let document = @text.TextDocument::new("").unwrap()
  let value = @text_host.TextInputState::new(document, fake_caret())
  route.fail_enable.val = true
  assert_true(
    begin_text_route(TextHostState::empty(), route, fake_window(), 1UL)
    is Err(_),
  )
  route.fail_enable.val = false
  let (state, epoch) = fake_state(route)
  let state = match end_text_route(state, route, epoch) {
    Ok(next) => next
    Err(_) => abort("end rejected a live epoch")
  }
  assert_true(update_text_route(state, route, epoch, value) is Err(_))
}
