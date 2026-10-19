///|
/// Test-only host that records the ordered transport contract without a native
/// window. This is a transport fixture, not IME qualification.
struct TestHost {
  mut epoch : UInt64
  mut closed : Bool
  events : Array[@text_host.TextInputEvent]
}

///|
fn TestHost::new() -> TestHost {
  { epoch: 0UL, closed: false, events: [], }
}

///|
fn test_host_error(operation : String) -> @diagnostics.FrameworkError {
  @diagnostics.FrameworkError::new(
    @diagnostics.UnsupportedCapability,
    operation,
  )
}

///|
impl @text_host.TextInputHost for TestHost with fn begin_text_input(
  self,
  window,
  root,
) {
  ignore(window)
  ignore(root)
  if self.closed {
    Err(test_host_error("begin_text_input"))
  } else {
    self.epoch = 1UL
    Ok(self.epoch)
  }
}

///|
impl @text_host.TextInputHost for TestHost with fn update_text_input(
  self,
  epoch,
  state,
) {
  if self.closed || epoch != self.epoch {
    Err(test_host_error("update_text_input"))
  } else {
    ignore(state)
    Ok(self.epoch)
  }
}

///|
impl @text_host.TextInputHost for TestHost with fn cancel_text_input(
  self,
  epoch,
) {
  if self.closed || epoch != self.epoch {
    Err(test_host_error("cancel_text_input"))
  } else {
    self.epoch = self.epoch + 1UL
    Ok(())
  }
}

///|
impl @text_host.TextInputHost for TestHost with fn end_text_input(self, epoch) {
  if self.closed || epoch != self.epoch {
    Err(test_host_error("end_text_input"))
  } else {
    self.closed = true
    Ok(())
  }
}

///|
impl @text_host.TextInputHost for TestHost with fn next_text_input(
  self,
  timeout_ms~ : Int32 = 16,
) {
  ignore(timeout_ms)
  if self.events.is_empty() {
    Ok(None)
  } else {
    let event = self.events.remove(0)
    Ok(Some(event))
  }
}

///|
extend TestHost with @text_host.TextInputHost::{
  begin_text_input,
  cancel_text_input,
  end_text_input,
  next_text_input,
}

///|
test "text input state preserves the committed document and optional preedit" {
  let document = @text.TextDocument::new("日本").unwrap()
  let selection = @text.TextSelection::new(0, 2).unwrap()
  let document = document.with_selection(selection).unwrap()
  let caret = @primitives.Rect::new(4.0, 6.0, 1.0, 18.0).unwrap()
  let state = @text_host.TextInputState::new(document, caret)
  assert_eq(state.document().text(), "日本")
  assert_true(state.preedit() is None)
  let preedit = @text_host.TextPreedit::new("にほん", selection)
  let state = state.with_preedit(Some(preedit))
  assert_eq(state.preedit().unwrap().text(), "にほん")
  assert_eq(state.caret().left(), 4.0)
  assert_eq(state.caret().bottom(), 24.0)
}

///|
test "text input host owns the session epoch and ordered events" {
  let host = TestHost::new()
  let window = @platform.WindowId::new(7)
  let epoch = host.begin_text_input(window, 1UL).unwrap()
  assert_eq(epoch, 1UL)
  host.events.push(
    @text_host.TextInputEvent::new(
      window,
      1L,
      epoch,
      @text_host.Preedit(text="に", cursor=1),
    ),
  )
  host.events.push(
    @text_host.TextInputEvent::new(
      window,
      2L,
      epoch,
      @text_host.Commit(text="日本"),
    ),
  )
  let preedit = host.next_text_input().unwrap().unwrap()
  assert_true(preedit.kind() is @text_host.Preedit(text="に", cursor=1))
  assert_eq(preedit.sequence(), 1L)
  let committed = host.next_text_input().unwrap().unwrap()
  assert_true(committed.kind() is @text_host.Commit(text="日本"))
  assert_true(host.next_text_input() is Ok(None))
  host.cancel_text_input(epoch).unwrap()
  assert_true(host.end_text_input(2UL) is Ok(_))
  assert_true(host.begin_text_input(window, 1UL) is Err(_))
}
