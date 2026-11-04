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

///|
fn focus_test_reader(
  events : Array[EditorEvent],
) -> (Int32) -> Result[EditorEvent?, @diagnostics.FrameworkError] {
  _timeout => {
    if events.length() == 0 {
      Ok(None)
    } else {
      Ok(Some(events.remove(0)))
    }
  }
}

///|
fn focus_test_route() -> (TextHostRoute, Array[EditorEvent]) {
  let events : Array[EditorEvent] = []
  let route : TextHostRoute = {
    host: { token: 0, stopped: false, },
    editor_reader: Some(focus_test_reader(events)),
    metrics_reader: Some(_ => Ok((800.0, 600.0, 2.0))),
    queue: @text_host.TextHostQueue::new(),
    native_epoch: 0,
    window: None,
    started: false,
  }
  (route, events)
}

///|
test "platform-first focus loss preserves preceding text and platform record" {
  let (route, events) = focus_test_route()
  let window = @platform.WindowId::new(1L)
  let epoch = route.begin_text_input(window, 1UL).unwrap()
  route.started = true
  route.native_epoch = 1
  let target : TextSessionTarget = {
    window,
    sequence: 1L,
    epoch: 1,
    seat: 1L,
    proxy_generation: 1,
    serial: 1,
  }
  for
    event in [
      TextSession(
        target,
        Preedit(text="a", fallback="", cursor_utf16=Some(1), styles=[]),
      ),
      TextSession(target, Commit(text="ab", deletion=None, position=None)),
      Platform(
        @platform.Event::new(window, 3L, 1.5, @platform.FocusChanged(false)),
      ),
    ] {
    events.push(event)
  }
  let platform = route.next_platform_event(timeout_ms=0).unwrap().unwrap()
  assert_eq(platform.window().value(), 1L)
  assert_eq(platform.sequence(), 3L)
  assert_eq(platform.scale(), 1.5)
  assert_true(platform.kind() is @platform.FocusChanged(false))
  let first = route.next_text_input(timeout_ms=0).unwrap().unwrap()
  assert_true(first.kind() is @text_host.Preedit(text="a", cursor=1))
  assert_eq(first.epoch(), epoch)
  assert_eq(first.sequence(), 1L)
  let commit = route.next_text_input(timeout_ms=0).unwrap().unwrap()
  assert_true(commit.kind() is @text_host.Commit(text="ab"))
  assert_eq(commit.epoch(), epoch)
  assert_eq(commit.sequence(), 2L)
  let focus = route.next_text_input(timeout_ms=0).unwrap().unwrap()
  assert_true(focus.kind() is @text_host.FocusLost)
  assert_eq(focus.window().value(), 1L)
  assert_eq(focus.epoch(), epoch)
  assert_eq(focus.sequence(), 3L)
  assert_true(route.next_text_input(timeout_ms=0) is Ok(None))
}

///|
test "text-first focus loss parks records once and preserves each observation" {
  let (route, events) = focus_test_route()
  let window = @platform.WindowId::new(1L)
  let epoch = route.begin_text_input(window, 1UL).unwrap()
  for
    event in [
      Platform(@platform.Event::new(window, 1L, 2.0, @platform.CloseRequested)),
      Platform(
        @platform.Event::new(window, 2L, 1.5, @platform.FocusChanged(false)),
      ),
      Platform(
        @platform.Event::new(window, 3L, 1.25, @platform.FocusChanged(false)),
      ),
    ] {
    events.push(event)
  }
  let first = route.next_text_input(timeout_ms=0).unwrap().unwrap()
  assert_true(first.kind() is @text_host.FocusLost)
  assert_eq(first.epoch(), epoch)
  assert_eq(first.sequence(), 1L)
  let close = route.next_platform_event(timeout_ms=0).unwrap().unwrap()
  assert_eq(close.sequence(), 1L)
  assert_eq(close.scale(), 2.0)
  assert_true(close.kind() is @platform.CloseRequested)
  let focus = route.next_platform_event(timeout_ms=0).unwrap().unwrap()
  assert_eq(focus.sequence(), 2L)
  assert_eq(focus.scale(), 1.5)
  assert_true(focus.kind() is @platform.FocusChanged(false))
  let second = route.next_text_input(timeout_ms=0).unwrap().unwrap()
  assert_true(second.kind() is @text_host.FocusLost)
  assert_eq(second.sequence(), 2L)
  let focus = route.next_platform_event(timeout_ms=0).unwrap().unwrap()
  assert_eq(focus.sequence(), 3L)
  assert_eq(focus.scale(), 1.25)
  assert_true(focus.kind() is @platform.FocusChanged(false))
  assert_true(route.next_text_input(timeout_ms=0) is Ok(None))
}

///|
test "inactive and foreign focus loss never reaches the text consumer" {
  let (route, events) = focus_test_route()
  let window = @platform.WindowId::new(1L)
  let foreign = @platform.WindowId::new(2L)
  for
    event in [
      Platform(
        @platform.Event::new(window, 1L, 1.0, @platform.FocusChanged(false)),
      ),
    ] {
    events.push(event)
  }
  assert_true(route.next_text_input(timeout_ms=0) is Ok(None))
  assert_eq(
    route.next_platform_event(timeout_ms=0).unwrap().unwrap().sequence(),
    1L,
  )
  let epoch = route.begin_text_input(window, 1UL).unwrap()
  for
    event in [
      Platform(
        @platform.Event::new(foreign, 2L, 1.0, @platform.FocusChanged(false)),
      ),
      Platform(
        @platform.Event::new(foreign, 3L, 1.0, @platform.FocusChanged(false)),
      ),
      Platform(
        @platform.Event::new(window, 4L, 1.0, @platform.FocusChanged(true)),
      ),
    ] {
    events.push(event)
  }
  assert_eq(
    route.next_platform_event(timeout_ms=0).unwrap().unwrap().sequence(),
    2L,
  )
  assert_true(route.next_text_input(timeout_ms=0) is Ok(None))
  assert_eq(
    route.next_platform_event(timeout_ms=0).unwrap().unwrap().sequence(),
    3L,
  )
  assert_eq(
    route.next_platform_event(timeout_ms=0).unwrap().unwrap().sequence(),
    4L,
  )
  assert_true(route.next_text_input(timeout_ms=0) is Ok(None))
  assert_true(route.end_text_input(epoch) is Ok(_))
}

///|
test "cancel and end clear focus text while parked events survive rebegin" {
  let (route, events) = focus_test_route()
  let window = @platform.WindowId::new(1L)
  let epoch = route.begin_text_input(window, 1UL).unwrap()
  for
    event in [
      Platform(
        @platform.Event::new(window, 1L, 1.0, @platform.FocusChanged(false)),
      ),
      Platform(
        @platform.Event::new(window, 2L, 1.0, @platform.FocusChanged(false)),
      ),
      Platform(
        @platform.Event::new(window, 3L, 1.0, @platform.FocusChanged(false)),
      ),
    ] {
    events.push(event)
  }
  assert_eq(
    route.next_platform_event(timeout_ms=0).unwrap().unwrap().sequence(),
    1L,
  )
  let replacement = route.cancel_text_input(epoch).unwrap()
  let focus = route.next_text_input(timeout_ms=0).unwrap().unwrap()
  assert_true(focus.kind() is @text_host.FocusLost)
  assert_eq(focus.epoch(), replacement)
  assert_eq(focus.sequence(), 2L)
  assert_true(route.end_text_input(replacement) is Ok(_))
  let next = route.begin_text_input(window, 1UL).unwrap()
  assert_eq(
    route.next_platform_event(timeout_ms=0).unwrap().unwrap().sequence(),
    2L,
  )
  assert_eq(
    route.next_platform_event(timeout_ms=0).unwrap().unwrap().sequence(),
    3L,
  )
  assert_true(route.end_text_input(next) is Ok(_))
  let final_epoch = route.begin_text_input(window, 1UL).unwrap()
  assert_true(route.next_text_input(timeout_ms=0) is Ok(None))
  assert_true(route.end_text_input(final_epoch) is Ok(_))
}

///|
test "both pumps propagate reader errors and requested timeouts" {
  let calls : Array[Int32] = []
  let route : TextHostRoute = {
    host: { token: 0, stopped: false, },
    editor_reader: Some(timeout => {
      calls.push(timeout)
      Err(
        @diagnostics.FrameworkError::new(
          @diagnostics.InvalidInput,
          "fixture_reader",
          subsystem="fixture",
        ),
      )
    }),
    metrics_reader: None,
    queue: @text_host.TextHostQueue::new(),
    native_epoch: 0,
    window: None,
    started: false,
  }
  let epoch = route.begin_text_input(@platform.WindowId::new(1L), 1UL).unwrap()
  match route.next_platform_event(timeout_ms=7) {
    Err(error) => assert_eq(error.operation(), "fixture_reader")
    _ => fail("platform pump must propagate the reader error")
  }
  match route.next_text_input(timeout_ms=9) {
    Err(error) => assert_eq(error.operation(), "fixture_reader")
    _ => fail("text pump must propagate the reader error")
  }
  assert_eq(calls.length(), 2)
  assert_eq(calls[0], 7)
  assert_eq(calls[1], 9)
  assert_true(route.end_text_input(epoch) is Ok(_))
}

///|
test "forwarded keys are delivered before the later focus record" {
  let (route, events) = focus_test_route()
  let window = @platform.WindowId::new(1L)
  let epoch = route.begin_text_input(window, 1UL).unwrap()
  route.started = true
  route.native_epoch = 1
  let first : TextSessionTarget = {
    window,
    sequence: 1L,
    epoch: 1,
    seat: 1L,
    proxy_generation: 1,
    serial: 1,
  }
  let second : TextSessionTarget = {
    window,
    sequence: 2L,
    epoch: 1,
    seat: 1L,
    proxy_generation: 1,
    serial: 2,
  }
  for
    event in [
      TextSession(
        first,
        ForwardedPressed(
          keysym=0xff51,
          key=Some(@primitives.ArrowLeft),
          modifiers=@primitives.Modifiers::none(),
        ),
      ),
      TextSession(
        second,
        ForwardedReleased(
          keysym=0xff51,
          key=Some(@primitives.ArrowLeft),
          modifiers=@primitives.Modifiers::none(),
        ),
      ),
      Platform(
        @platform.Event::new(window, 3L, 1.5, @platform.FocusChanged(false)),
      ),
    ] {
    events.push(event)
  }
  let pressed = route.next_platform_event(timeout_ms=0).unwrap().unwrap()
  assert_eq(pressed.sequence(), 1L)
  assert_eq(pressed.scale(), 2.0)
  assert_true(
    pressed.kind()
    is @platform.Input(
      @primitives.KeyPressed(key=@primitives.ArrowLeft, repeat=false, ..)
    ),
  )
  let released = route.next_platform_event(timeout_ms=0).unwrap().unwrap()
  assert_eq(released.sequence(), 2L)
  assert_eq(released.scale(), 2.0)
  assert_true(
    released.kind()
    is @platform.Input(@primitives.KeyReleased(key=@primitives.ArrowLeft, ..)),
  )
  let platform = route.next_platform_event(timeout_ms=0).unwrap().unwrap()
  assert_eq(platform.sequence(), 3L)
  assert_eq(platform.scale(), 1.5)
  assert_true(platform.kind() is @platform.FocusChanged(false))
  let focus = route.next_text_input(timeout_ms=0).unwrap().unwrap()
  assert_true(focus.kind() is @text_host.FocusLost)
  assert_eq(focus.epoch(), epoch)
  assert_eq(focus.sequence(), 1L)
  assert_true(route.next_text_input(timeout_ms=0) is Ok(None))
}
