///|
test "windows portable translation keeps preedit, insert, cancel and skips lifecycle" {
  let empty = @text.TextRange::new(0, 0).unwrap()
  match
    translate_editor_event(
      Marked(
        text="にほん",
        cursor_utf16=Some(3),
        attributes=[0],
        replacement_range=empty,
      ),
    ) {
    Emit(@text_host.Preedit(text~, cursor~)) => {
      assert_eq(text, "にほん")
      assert_eq(cursor, 3)
    }
    _ => fail("expected a preedit translation")
  }
  match
    translate_editor_event(
      Marked(
        text="に",
        cursor_utf16=None,
        attributes=[],
        replacement_range=empty,
      ),
    ) {
    Emit(@text_host.Preedit(cursor~, ..)) => assert_eq(cursor, -1)
    _ => fail("expected a hidden-cursor preedit")
  }
  match
    translate_editor_event(Inserted(text="日本語", replacement_range=empty)) {
    Emit(@text_host.Commit(text~)) => assert_eq(text, "日本語")
    _ => fail("expected an insertion commit")
  }
  let replaced = @text.TextRange::new(1, 2).unwrap()
  match
    translate_editor_event(Inserted(text="日本", replacement_range=replaced)) {
    Unsupported => ()
    _ => fail("replacement insert must not flatten to an insertion")
  }
  match translate_editor_event(Cancelled) {
    Emit(@text_host.Cancel) => ()
    _ => fail("expected a cancel translation")
  }
  match translate_editor_event(CompositionStarted(replacement_range=empty)) {
    Skip => ()
    _ => fail("composition start is not an observation")
  }
  match translate_editor_event(CompositionEnded) {
    Skip => ()
    _ => fail("composition end is not an observation")
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
  route.owner = 1
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
