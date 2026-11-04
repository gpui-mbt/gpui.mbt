///|
test "ubuntu portable translation keeps preedit, insert, cancel and keys" {
  match
    translate_editor_event(
      Preedit(text="にほん", fallback="", cursor_utf16=Some(3), styles=[]),
    ) {
    Emit(@text_host.Preedit(text~, cursor~)) => {
      assert_eq(text, "にほん")
      assert_eq(cursor, 3)
    }
    _ => fail("expected a preedit translation")
  }
  match
    translate_editor_event(
      Preedit(text="に", fallback="", cursor_utf16=None, styles=[]),
    ) {
    Emit(@text_host.Preedit(cursor~, ..)) => assert_eq(cursor, -1)
    _ => fail("expected a hidden-cursor preedit")
  }
  match
    translate_editor_event(
      Commit(text="日本語", deletion=None, position=None),
    ) {
    Emit(@text_host.Commit(text~)) => assert_eq(text, "日本語")
    _ => fail("expected an insertion commit")
  }
  match
    translate_editor_event(
      Commit(
        text="日本",
        deletion=Some({ index_bytes: 0, length_bytes: 0, }),
        position=None,
      ),
    ) {
    Emit(@text_host.Commit(_)) => ()
    _ => fail("an empty deletion is still an insertion")
  }
  match
    translate_editor_event(
      Commit(
        text="日本",
        deletion=Some({ index_bytes: -3, length_bytes: 3, }),
        position=None,
      ),
    ) {
    Unsupported => ()
    _ => fail("deleting surrounding text must not flatten to an insertion")
  }
  match translate_editor_event(Entered) {
    Skip => ()
    _ => fail("Entered is protocol focus, not an observation")
  }
  match translate_editor_event(Left) {
    Skip => ()
    _ => fail("Left is a protocol fence, not an observation")
  }
  match
    translate_editor_event(
      ForwardedPressed(
        keysym=0xff51,
        key=Some(@primitives.ArrowLeft),
        modifiers=@primitives.Modifiers::none(),
      ),
    ) {
    Forward(@primitives.ArrowLeft, true, _) => ()
    _ => fail("expected a forwarded ArrowLeft press")
  }
  match
    translate_editor_event(
      ForwardedReleased(
        keysym=0xffff,
        key=None,
        modifiers=@primitives.Modifiers::none(),
      ),
    ) {
    Skip => ()
    _ => fail("an unmapped forwarded key has no portable event")
  }
}

///|
test "portable end rejects stale epochs and preserves adapter state on native failure" {
  let host : Host = { token: 0, stopped: false, }
  let route = TextHostRoute::new(host)
  let window = @platform.WindowId::new(1L)
  let old = route.queue.begin(window).unwrap()
  let current = route.queue.cancel(old).unwrap()
  let document = @text.TextDocument::new("abc").unwrap()
  let caret = @primitives.Rect::new(0.0, 0.0, 1.0, 16.0).unwrap()
  ignore(
    route.queue
    .update(current, @text_host.TextInputState::new(document, caret))
    .unwrap(),
  )
  assert_true(
    route.queue.emit(@text_host.Preedit(text="に", cursor=1)) is Ok(_),
  )
  assert_true(
    route.queue.park(
      @platform.Event::new(window, 1L, 1.0, @platform.FocusChanged(false)),
    ),
  )
  route.window = Some(window)
  route.native_epoch = 1
  route.started = true
  for stale in [0UL, old, current + 1UL] {
    match route.end_text_input(stale) {
      Err(error) => {
        assert_eq(error.code().label(), "stale_handle")
        assert_eq(error.operation(), "end_text_input")
      }
      Ok(_) => fail("stale end must fail")
    }
    assert_true(route.started)
    assert_eq(route.native_epoch, 1)
    assert_true(route.queue.is_active())
    assert_eq(route.queue.epoch(), current)
    assert_true(route.queue.state() is Some(_))
    assert_true(route.queue.has_text())
    assert_true(route.queue.has_parked())
  }
  match route.end_text_input(current) {
    Err(error) => assert_eq(error.operation(), "end_text_session")
    Ok(_) => fail("disconnected native host must fail")
  }
  assert_true(route.started)
  assert_eq(route.native_epoch, 1)
  assert_true(route.queue.is_active())
  assert_eq(route.queue.epoch(), current)
  assert_true(route.queue.state() is Some(_))
  assert_true(route.queue.has_text())
  assert_true(route.queue.has_parked())
  route.queue.reset()
  match route.end_text_input(current) {
    Err(error) => {
      assert_eq(error.code().label(), "stale_handle")
      assert_eq(error.operation(), "end_text_input")
    }
    Ok(_) => fail("inactive end must fail")
  }
  assert_true(route.started)
  assert_eq(route.native_epoch, 1)
}

///|
test "portable end keeps parked platform events through a new session" {
  let host : Host = { token: 0, stopped: false, }
  let route = TextHostRoute::new(host)
  let first_window = @platform.WindowId::new(1L)
  let next_window = @platform.WindowId::new(2L)
  let original = route.begin_text_input(first_window, 1UL).unwrap()
  let current = route.cancel_text_input(original).unwrap()
  assert_true(route.end_text_input(original) is Err(_))
  assert_true(
    route.queue.emit(@text_host.Preedit(text="に", cursor=1)) is Ok(_),
  )
  assert_true(
    route.queue.park(
      @platform.Event::new(first_window, 3L, 1.0, @platform.FocusChanged(false)),
    ),
  )
  assert_true(
    route.queue.park(
      @platform.Event::new(first_window, 4L, 1.0, @platform.CloseRequested),
    ),
  )
  assert_true(route.end_text_input(current) is Ok(_))
  assert_false(route.queue.is_active())
  assert_true(route.queue.take_text() is None)
  assert_true(route.end_text_input(current) is Err(_))
  let first = match route.next_platform_event(timeout_ms=0) {
    Ok(Some(event)) => event
    _ => fail("expected the parked focus event")
  }
  assert_eq(first.window().value(), 1L)
  assert_eq(first.sequence(), 3L)
  assert_true(first.kind() is @platform.FocusChanged(false))
  let next = route.begin_text_input(next_window, 2UL).unwrap()
  assert_true(next != current)
  assert_true(route.end_text_input(current) is Err(_))
  let second = match route.next_platform_event(timeout_ms=0) {
    Ok(Some(event)) => event
    _ => fail("expected the parked close event")
  }
  assert_eq(second.window().value(), 1L)
  assert_eq(second.sequence(), 4L)
  assert_true(second.kind() is @platform.CloseRequested)
  assert_true(route.end_text_input(next) is Ok(_))
}
