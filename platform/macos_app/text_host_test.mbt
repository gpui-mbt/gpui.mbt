///|
/// Scripted transport for the reusable helper. It records commands and replays
/// queued observations; it is not a native host.
struct MacHostTestTransport {
  epoch : Ref[UInt64]
  open : Ref[Bool]
  events : Array[@text_host.TextInputEvent]
  updates : Array[UInt64]
  ends : Array[UInt64]
}

///|
fn MacHostTestTransport::new() -> MacHostTestTransport {
  { epoch: Ref(7UL), open: Ref(false), events: [], updates: [], ends: [], }
}

///|
fn mac_host_test_error(operation : String) -> @diagnostics.FrameworkError {
  @diagnostics.FrameworkError::new(
    @diagnostics.UnsupportedCapability,
    operation,
  )
}

///|
impl @text_host.TextInputHost for MacHostTestTransport with fn begin_text_input(
  self,
  window,
  root,
) {
  ignore(window)
  ignore(root)
  if self.open.val {
    return Err(mac_host_test_error("begin_text_input"))
  }
  self.open.val = true
  Ok(self.epoch.val)
}

///|
impl @text_host.TextInputHost for MacHostTestTransport with fn update_text_input(
  self,
  epoch,
  value,
) {
  if !self.open.val || epoch != self.epoch.val {
    return Err(mac_host_test_error("update_text_input"))
  }
  ignore(value)
  self.updates.push(epoch)
  Ok(epoch)
}

///|
impl @text_host.TextInputHost for MacHostTestTransport with fn cancel_text_input(
  self,
  epoch,
) {
  if !self.open.val || epoch != self.epoch.val {
    return Err(mac_host_test_error("cancel_text_input"))
  }
  Ok(epoch)
}

///|
impl @text_host.TextInputHost for MacHostTestTransport with fn end_text_input(
  self,
  epoch,
) {
  if !self.open.val || epoch != self.epoch.val {
    return Err(mac_host_test_error("end_text_input"))
  }
  self.open.val = false
  self.ends.push(epoch)
  Ok(())
}

///|
impl @text_host.TextInputHost for MacHostTestTransport with fn next_text_input(
  self,
  timeout_ms~ : Int32 = 16,
) {
  ignore(timeout_ms)
  if self.events.is_empty() {
    Ok(None)
  } else {
    Ok(Some(self.events.remove(0)))
  }
}

///|
fn mac_host_test_event(
  sequence : Int64,
  epoch : UInt64,
  kind : @text_host.TextInputEventKind,
) -> @text_host.TextInputEvent {
  @text_host.TextInputEvent::new(
    @platform.WindowId::new(7),
    sequence,
    epoch,
    kind,
  )
}

///|
fn mac_host_test_start(
  host : MacHostTestTransport,
  text : String,
) -> @macos_app.MacosTextFieldHost raise {
  let document = @text.TextDocument::new(text).unwrap()
  match
    @macos_app.MacosTextFieldHost::start(
      3UL,
      @platform.WindowId::new(7),
      1UL,
      macos_app_rect(0.0, 0.0, 320.0, 44.0),
      18.0,
      document,
      host,
    ) {
    Ok(value) => value
    Err(_) => fail("valid helper start should succeed")
  }
}

///|
test "macOS text host helper applies preedit and commit" {
  if !macos_app_coretext_available() {
    return
  }
  let host = MacHostTestTransport::new()
  let helper = mac_host_test_start(host, "")
  assert_eq(helper.binding().epoch(), 7UL)
  assert_true(!helper.is_ended())
  assert_eq(host.updates.length(), 1)
  host.events.push(
    mac_host_test_event(
      1L,
      7UL,
      @text_host.Preedit(text="にほんご", cursor=4),
    ),
  )
  match helper.pump(host) {
    Ok(@text_adapter.Applied(_)) => ()
    _ => fail("preedit should apply through the helper")
  }
  assert_true(helper.field().is_composing())
  host.events.push(
    mac_host_test_event(2L, 7UL, @text_host.Commit(text="日本語")),
  )
  match helper.pump(host) {
    Ok(@text_adapter.Applied(_)) => ()
    _ => fail("commit should apply through the helper")
  }
  assert_true(!helper.field().is_composing())
  assert_eq(helper.field().committed_document().text(), "日本語")
  assert_true(helper.pump(host) is Ok(@text_adapter.Idle))
}

///|
test "macOS text host helper ends on focus loss and rejects later pumps" {
  if !macos_app_coretext_available() {
    return
  }
  let host = MacHostTestTransport::new()
  let helper = mac_host_test_start(host, "")
  host.events.push(mac_host_test_event(1L, 7UL, @text_host.FocusLost))
  match helper.pump(host) {
    Ok(@text_adapter.FocusLost) => ()
    _ => fail("focus loss should end the helper")
  }
  assert_true(helper.is_ended())
  assert_eq(host.ends.length(), 1)
  assert_true(helper.pump(host) is Err(@macos_app.Ended))
  assert_true(helper.end(host) is Ok(_))
}

///|
test "macOS text host helper revokes the transport explicitly" {
  if !macos_app_coretext_available() {
    return
  }
  let host = MacHostTestTransport::new()
  let helper = mac_host_test_start(host, "")
  assert_true(helper.end(host) is Ok(_))
  assert_true(helper.is_ended())
  assert_eq(host.ends.length(), 1)
  assert_true(helper.end(host) is Ok(_))
}
