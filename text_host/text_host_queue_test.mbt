///|
test "text host queue owns one epoch and orders observations" {
  let queue = @text_host.TextHostQueue::new()
  let window = @platform.WindowId::new(1L)
  assert_false(queue.is_active())
  let epoch = queue.begin(window).unwrap()
  assert_eq(epoch, 1UL)
  assert_true(queue.is_active())
  let document = @text.TextDocument::new("abc").unwrap()
  let caret = @primitives.Rect::new(0.0, 0.0, 1.0, 16.0).unwrap()
  assert_eq(
    queue
    .update(epoch, @text_host.TextInputState::new(document, caret))
    .unwrap(),
    epoch,
  )
  assert_true(queue.state() is Some(_))
  assert_true(queue.emit(@text_host.Preedit(text="に", cursor=1)) is Ok(_))
  assert_true(queue.emit(@text_host.Commit(text="日本")) is Ok(_))
  let first = queue.take_text().unwrap()
  assert_eq(first.sequence(), 1L)
  assert_eq(first.epoch(), epoch)
  match first.kind() {
    @text_host.Preedit(text~, cursor~) => {
      assert_eq(text, "に")
      assert_eq(cursor, 1)
    }
    _ => fail("expected the first observation to be a preedit")
  }
  let second = queue.take_text().unwrap()
  assert_eq(second.sequence(), 2L)
  assert_true(queue.take_text() is None)
  assert_true(queue.emit(@text_host.Preedit(text="に", cursor=1)) is Ok(_))
  queue.discard_text()
  assert_true(queue.take_text() is None)
  assert_true(queue.has_parked() == false)
  let replaced = queue.cancel(epoch).unwrap()
  assert_eq(replaced, 2UL)
  assert_true(queue.state() is None)
  assert_true(
    queue.update(epoch, @text_host.TextInputState::new(document, caret))
    is Err(_),
  )
  assert_true(queue.end(replaced) is Ok(_))
  assert_false(queue.is_active())
}

///|
test "text host queue parks and drains platform events" {
  let queue = @text_host.TextHostQueue::new()
  let window = @platform.WindowId::new(1L)
  let epoch = queue.begin(window).unwrap()
  let first = @platform.Event::new(window, 1L, 1.0, @platform.Created)
  let second = @platform.Event::new(window, 2L, 1.0, @platform.FrameCompleted)
  assert_true(queue.park(first))
  assert_true(queue.park(second))
  assert_true(queue.has_parked())
  assert_eq(queue.take_parked().unwrap().sequence(), 1L)
  assert_eq(queue.take_parked().unwrap().sequence(), 2L)
  assert_true(queue.take_parked() is None)
  assert_true(queue.end(epoch) is Ok(_))
  assert_true(queue.park(first))
  assert_true(queue.take_parked() is Some(_))
}

///|
test "text host queue rejects stale and duplicate operations" {
  let queue = @text_host.TextHostQueue::new()
  let window = @platform.WindowId::new(1L)
  assert_true(queue.end(1UL) is Err(_))
  let epoch = queue.begin(window).unwrap()
  assert_true(queue.begin(window) is Err(_))
  assert_true(
    queue.update(
      epoch + 1UL,
      @text_host.TextInputState::new(
        @text.TextDocument::new("").unwrap(),
        @primitives.Rect::new(0.0, 0.0, 1.0, 16.0).unwrap(),
      ),
    )
    is Err(_),
  )
  assert_true(queue.emit(@text_host.Cancel) is Err(_) || queue.has_text())
  queue.fail(@diagnostics.UnsupportedCapability)
  match queue.failure() {
    Some(@diagnostics.UnsupportedCapability) => ()
    _ => fail("expected the unsupported-commit failure")
  }
  assert_true(queue.end(epoch) is Ok(_))
  assert_true(queue.failure() is None)
  let next = queue.begin(window).unwrap()
  assert_eq(next, epoch + 1UL)
  queue.reset()
  assert_false(queue.is_active())
  assert_true(queue.take_parked() is None)
  assert_true(queue.take_text() is None)
}

///|
test "text host queue bounds parking and survives cancel" {
  let queue = @text_host.TextHostQueue::new()
  let window = @platform.WindowId::new(1L)
  let epoch = queue.begin(window).unwrap()
  let first = @platform.Event::new(window, 1L, 1.0, @platform.Created)
  assert_true(queue.park(first))
  let second = @platform.Event::new(window, 2L, 1.0, @platform.FrameCompleted)
  assert_true(queue.park(second))
  let replaced = queue.cancel(epoch).unwrap()
  assert_eq(replaced, epoch + 1UL)
  // Cancel drops text observations but keeps ordinary platform records.
  assert_eq(queue.take_parked().unwrap().sequence(), 1L)
  assert_eq(queue.take_parked().unwrap().sequence(), 2L)
  let bounded = @text_host.TextHostQueue::new()
  let bounded_epoch = bounded.begin(window).unwrap()
  let mut accepted = 0
  for sequence in 1L..<1200L {
    let event = @platform.Event::new(
      window,
      sequence,
      1.0,
      @platform.FrameCompleted,
    )
    if bounded.park(event) {
      accepted += 1
    }
  }
  assert_eq(accepted, 1024)
  assert_true(bounded.end(bounded_epoch) is Ok(_))
  let reused = bounded.begin(window).unwrap()
  assert_true(reused > bounded_epoch)
  assert_false(bounded.park(first))
  for sequence in 1L..<1025L {
    assert_eq(bounded.take_parked().unwrap().sequence(), sequence)
  }
  assert_true(bounded.take_parked() is None)
  assert_true(bounded.park(first))
  bounded.reset()
  assert_true(bounded.take_parked() is None)
}

///|
test "end preserves parked focus and input events across replacement sessions" {
  let queue = @text_host.TextHostQueue::new()
  let first_window = @platform.WindowId::new(1L)
  let next_window = @platform.WindowId::new(2L)
  let epoch = queue.begin(first_window).unwrap()
  let document = @text.TextDocument::new("abc").unwrap()
  let caret = @primitives.Rect::new(0.0, 0.0, 1.0, 16.0).unwrap()
  ignore(
    queue
    .update(epoch, @text_host.TextInputState::new(document, caret))
    .unwrap(),
  )
  assert_true(queue.emit(@text_host.Preedit(text="に", cursor=1)) is Ok(_))
  assert_true(
    queue.park(
      @platform.Event::new(first_window, 8L, 1.0, @platform.FocusChanged(false)),
    ),
  )
  assert_true(
    queue.park(
      @platform.Event::new(first_window, 9L, 1.0, @platform.CloseRequested),
    ),
  )
  queue.fail(@diagnostics.UnsupportedCapability)
  assert_true(queue.end(epoch) is Ok(_))
  assert_false(queue.is_active())
  assert_true(queue.state() is None)
  assert_true(queue.failure() is None)
  assert_true(queue.take_text() is None)
  assert_true(queue.end(epoch) is Err(_))
  let next = queue.begin(next_window).unwrap()
  assert_true(next != epoch)
  assert_true(queue.end(epoch) is Err(_))
  assert_true(
    queue.park(@platform.Event::new(next_window, 1L, 1.0, @platform.Created)),
  )
  let first = queue.take_parked().unwrap()
  assert_eq(first.window().value(), 1L)
  assert_eq(first.sequence(), 8L)
  assert_true(first.kind() is @platform.FocusChanged(false))
  let second = queue.take_parked().unwrap()
  assert_eq(second.window().value(), 1L)
  assert_eq(second.sequence(), 9L)
  assert_true(second.kind() is @platform.CloseRequested)
  let third = queue.take_parked().unwrap()
  assert_eq(third.window().value(), 2L)
  assert_eq(third.sequence(), 1L)
  assert_true(queue.take_parked() is None)
  assert_true(queue.end(next) is Ok(_))
}

///|
test "parked events survive beginning sessions after inactive periods" {
  let queue = @text_host.TextHostQueue::new()
  let window = @platform.WindowId::new(1L)
  assert_true(
    queue.park(@platform.Event::new(window, 1L, 1.0, @platform.Created)),
  )
  let first = queue.begin(window).unwrap()
  assert_true(
    queue.park(
      @platform.Event::new(window, 2L, 1.0, @platform.FocusChanged(false)),
    ),
  )
  assert_true(queue.end(first) is Ok(_))
  assert_true(
    queue.park(@platform.Event::new(window, 3L, 1.0, @platform.CloseRequested)),
  )
  let second = queue.begin(window).unwrap()
  for sequence in 1L..<4L {
    assert_eq(queue.take_parked().unwrap().sequence(), sequence)
  }
  assert_true(queue.take_parked() is None)
  assert_true(queue.end(second) is Ok(_))
}
