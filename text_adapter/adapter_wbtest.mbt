///|
/// Scripted transport fixture for the portable adapter. It records every
/// command and replays queued observations in order; it is not a native host.
struct AdapterTestHost {
  epoch : Ref[UInt64]
  open : Ref[Bool]
  events : Array[@text_host.TextInputEvent]
  begins : Array[(@platform.WindowId, UInt64)]
  updates : Array[(@text.TextDocument, @primitives.Rect)]
  ends : Array[UInt64]
}

///|
fn AdapterTestHost::new() -> AdapterTestHost {
  {
    epoch: Ref(7UL),
    open: Ref(false),
    events: [],
    begins: [],
    updates: [],
    ends: [],
  }
}

///|
fn adapter_test_error(operation : String) -> @diagnostics.FrameworkError {
  @diagnostics.FrameworkError::new(
    @diagnostics.UnsupportedCapability,
    operation,
  )
}

///|
impl @text_host.TextInputHost for AdapterTestHost with fn begin_text_input(
  self,
  window,
  root,
) {
  self.begins.push((window, root))
  if self.open.val {
    return Err(adapter_test_error("begin_text_input"))
  }
  self.open.val = true
  Ok(self.epoch.val)
}

///|
impl @text_host.TextInputHost for AdapterTestHost with fn update_text_input(
  self,
  epoch,
  value,
) {
  if !self.open.val || epoch != self.epoch.val {
    return Err(adapter_test_error("update_text_input"))
  }
  self.updates.push((value.document(), value.caret()))
  Ok(self.epoch.val)
}

///|
impl @text_host.TextInputHost for AdapterTestHost with fn cancel_text_input(
  self,
  epoch,
) {
  if !self.open.val || epoch != self.epoch.val {
    return Err(adapter_test_error("cancel_text_input"))
  }
  Ok(self.epoch.val)
}

///|
impl @text_host.TextInputHost for AdapterTestHost with fn end_text_input(
  self,
  epoch,
) {
  if !self.open.val || epoch != self.epoch.val {
    return Err(adapter_test_error("end_text_input"))
  }
  self.open.val = false
  self.ends.push(epoch)
  Ok(())
}

///|
impl @text_host.TextInputHost for AdapterTestHost with fn next_text_input(
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
fn adapter_rect(
  x : Double,
  y : Double,
  width : Double,
  height : Double,
) -> @primitives.Rect {
  @primitives.Rect::new(x, y, width, height).unwrap()
}

///|
fn adapter_offsets(document : @text.TextDocument) -> Array[Int32] {
  let offsets = [0]
  let mut current = 0
  for scalar in document.text().iter() {
    current += if scalar.to_int() > 0xFFFF { 2 } else { 1 }
    offsets.push(current)
  }
  offsets
}

///|
fn adapter_test_measure(
  document : @text.TextDocument,
) -> Result[@text_layout.TextMeasurement, @text_field.TextFieldError] {
  let offsets = adapter_offsets(document)
  let carets = []
  for i = 0; i < offsets.length(); i = i + 1 {
    let x = i.to_double() * 8.0
    let caret = @text_layout.CaretGeometry::new(
      offsets[i],
      true,
      adapter_rect(x, 0.0, 1.0, 16.0),
      adapter_rect(x, 0.0, 1.0, 16.0),
    ).unwrap()
    carets.push(caret)
  }
  match
    @text_layout.TextMeasurement::new(
      document,
      adapter_rect(0.0, 0.0, 320.0, 16.0),
      adapter_rect(0.0, 0.0, 320.0, 16.0),
      12.0,
      1,
      0,
      carets,
    ) {
    Err(_) => Err(@text_field.MeasurementFailed)
    Ok(value) => Ok(value)
  }
}

///|
fn adapter_test_admit(
  document : @text.TextDocument,
  measurement : @text_layout.TextMeasurement,
) -> Result[Unit, @text_field.TextFieldError] {
  if measurement.document() != document {
    Err(@text_field.AdmissionFailed)
  } else {
    Ok(())
  }
}

///|
fn adapter_test_fail_measure(
  document : @text.TextDocument,
) -> Result[@text_layout.TextMeasurement, @text_field.TextFieldError] {
  ignore(document)
  Err(@text_field.MeasurementFailed)
}

///|
fn adapter_test_field(text : String) -> @text_field.TextField {
  let document = @text.TextDocument::new(text).unwrap()
  let field = @text_field.TextField::new(
    1UL,
    adapter_rect(0.0, 0.0, 320.0, 24.0),
    16.0,
    document,
    adapter_test_measure,
    adapter_test_admit,
  ).unwrap()
  field.with_focus(true).unwrap()
}

///|
fn adapter_test_session(
  text : String,
) -> (@text_session.TextSession, @text_field.TextField) {
  let field = adapter_test_field(text)
  let session = @text_session.TextSession::new(
    @platform.WindowId::new(7),
    1UL,
    field,
  ).unwrap()
  (session, field)
}

///|
fn adapter_event(
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
test "start publishes the committed document and caret" {
  let (session, field) = adapter_test_session("")
  let host = AdapterTestHost::new()
  let binding = match
    start_host_text(session, host, field.caret_rect().unwrap()) {
    Ok(value) => value
    Err(_) => abort("start rejected a valid session")
  }
  assert_eq(binding.epoch(), 7UL)
  assert_eq(binding.window().value(), 7L)
  assert_eq(host.begins.length(), 1)
  assert_eq(host.begins[0].0.value(), 7L)
  assert_eq(host.begins[0].1, 1UL)
  assert_eq(host.updates.length(), 1)
  assert_eq(host.updates[0].0.text(), "")
  assert_eq(host.updates[0].1.left(), field.caret_rect().unwrap().left())
}

///|
test "preedit, commit and cancel reach the field in order" {
  let (session, field) = adapter_test_session("")
  let host = AdapterTestHost::new()
  let binding = start_host_text(session, host, field.caret_rect().unwrap()).unwrap()
  host.events.push(
    adapter_event(
      1L,
      binding.epoch(),
      @text_host.Preedit(text="にほん", cursor=2),
    ),
  )
  match
    receive_host_text(
      session, host, binding, adapter_test_measure, adapter_test_admit,
    ) {
    Ok(Applied(receipt)) => {
      assert_true(receipt.snapshot().field().is_composing())
      assert_eq(receipt.snapshot().field().committed_document().text(), "")
    }
    _ => abort("preedit was not applied")
  }
  assert_eq(host.updates.length(), 2)
  assert_eq(host.updates[1].0.text(), "")
  host.events.push(
    adapter_event(2L, binding.epoch(), @text_host.Commit(text="日本語")),
  )
  match
    receive_host_text(
      session, host, binding, adapter_test_measure, adapter_test_admit,
    ) {
    Ok(Applied(receipt)) => {
      assert_eq(
        receipt.snapshot().field().committed_document().text(),
        "日本語",
      )
      assert_true(!receipt.snapshot().field().is_composing())
    }
    _ => abort("commit was not applied")
  }
  assert_eq(host.updates[2].0.text(), "日本語")
  host.events.push(
    adapter_event(3L, binding.epoch(), @text_host.Preedit(text="あ", cursor=1)),
  )
  ignore(
    receive_host_text(
      session, host, binding, adapter_test_measure, adapter_test_admit,
    ),
  )
  host.events.push(adapter_event(4L, binding.epoch(), @text_host.Cancel))
  match
    receive_host_text(
      session, host, binding, adapter_test_measure, adapter_test_admit,
    ) {
    Ok(Applied(receipt)) => {
      assert_eq(
        receipt.snapshot().field().committed_document().text(),
        "日本語",
      )
      assert_true(!receipt.snapshot().field().is_composing())
    }
    _ => abort("cancel was not applied")
  }
}

///|
test "stale window and epoch are rejected before the document changes" {
  let (session, field) = adapter_test_session("a")
  let host = AdapterTestHost::new()
  let binding = start_host_text(session, host, field.caret_rect().unwrap()).unwrap()
  let before = session.snapshot().field().committed_document()
  host.events.push(
    @text_host.TextInputEvent::new(
      @platform.WindowId::new(8),
      1L,
      binding.epoch(),
      @text_host.Commit(text="x"),
    ),
  )
  assert_true(
    receive_host_text(
      session, host, binding, adapter_test_measure, adapter_test_admit,
    )
    is Err(StaleWindow),
  )
  host.events.push(
    adapter_event(2L, binding.epoch() + 1UL, @text_host.Commit(text="x")),
  )
  assert_true(
    receive_host_text(
      session, host, binding, adapter_test_measure, adapter_test_admit,
    )
    is Err(StaleEpoch),
  )
  assert_eq(
    session.snapshot().field().committed_document().text(),
    before.text(),
  )
  assert_eq(host.updates.length(), 1)
}

///|
test "focus loss ends the transport and geometry republishes the caret" {
  let (session, field) = adapter_test_session("")
  let host = AdapterTestHost::new()
  let binding = start_host_text(session, host, field.caret_rect().unwrap()).unwrap()
  host.events.push(
    adapter_event(
      1L,
      binding.epoch(),
      @text_host.Geometry(
        caret=adapter_rect(3.0, 4.0, 1.0, 16.0),
        candidate=None,
      ),
    ),
  )
  assert_true(
    receive_host_text(
      session, host, binding, adapter_test_measure, adapter_test_admit,
    )
    is Ok(Idle),
  )
  assert_eq(host.updates.length(), 2)
  assert_eq(host.updates[1].1.left(), 3.0)
  host.events.push(adapter_event(2L, binding.epoch(), @text_host.FocusLost))
  assert_true(
    receive_host_text(
      session, host, binding, adapter_test_measure, adapter_test_admit,
    )
    is Ok(FocusLost),
  )
  assert_eq(host.ends.length(), 1)
  assert_eq(host.ends[0], binding.epoch())
}

///|
test "invalid preedit and measurement failures keep the model unchanged" {
  let (session, field) = adapter_test_session("ab")
  let host = AdapterTestHost::new()
  let binding = start_host_text(session, host, field.caret_rect().unwrap()).unwrap()
  let before = session.snapshot().field().committed_document()
  host.events.push(
    adapter_event(1L, binding.epoch(), @text_host.Preedit(text="あ", cursor=5)),
  )
  assert_true(
    receive_host_text(
      session, host, binding, adapter_test_measure, adapter_test_admit,
    )
    is Err(InvalidEvent),
  )
  host.events.push(
    adapter_event(2L, binding.epoch(), @text_host.Preedit(text="い", cursor=1)),
  )
  match
    receive_host_text(
      session, host, binding, adapter_test_fail_measure, adapter_test_admit,
    ) {
    Err(Session(@text_session.FieldFailure(@text_field.MeasurementFailed))) =>
      ()
    _ => abort("a measurement failure was retagged")
  }
  assert_eq(
    session.snapshot().field().committed_document().text(),
    before.text(),
  )
  assert_eq(host.updates.length(), 1)
}

///|
test "idle drains return no outcome and end revokes the binding" {
  let (session, field) = adapter_test_session("")
  let host = AdapterTestHost::new()
  let binding = start_host_text(session, host, field.caret_rect().unwrap()).unwrap()
  assert_true(
    receive_host_text(
      session, host, binding, adapter_test_measure, adapter_test_admit,
    )
    is Ok(Idle),
  )
  assert_true(end_host_text(session, host, binding) is Ok(_))
  assert_eq(host.ends.length(), 1)
}

///|
test "already-fetched observations can be applied without draining" {
  let (session, field) = adapter_test_session("")
  let host = AdapterTestHost::new()
  let binding = start_host_text(session, host, field.caret_rect().unwrap()).unwrap()
  let preview = adapter_event(
    1L,
    binding.epoch(),
    @text_host.Preedit(text="plain", cursor=5),
  )
  match
    apply_host_text_event(
      session, host, binding, preview, adapter_test_measure, adapter_test_admit,
    ) {
    Ok(Applied(_)) => assert_true(session.snapshot().field().is_composing())
    _ => abort("a provided preview was not applied")
  }
  let commit = adapter_event(
    2L,
    binding.epoch(),
    @text_host.Commit(text="plain"),
  )
  match
    apply_host_text_event(
      session, host, binding, commit, adapter_test_measure, adapter_test_admit,
    ) {
    Ok(Applied(receipt)) =>
      assert_eq(receipt.snapshot().field().committed_document().text(), "plain")
    _ => abort("a provided commit was not applied")
  }
  assert_eq(host.events.length(), 0)
  assert_eq(host.updates.length(), 3)
  assert_eq(host.updates[2].0.text(), "plain")
}

///|
test "apply validates the binding before touching the field" {
  let (session, field) = adapter_test_session("before")
  let host = AdapterTestHost::new()
  let binding = start_host_text(session, host, field.caret_rect().unwrap()).unwrap()
  let updates = host.updates.length()
  let stale = adapter_event(
    1L,
    binding.epoch() + 1UL,
    @text_host.Commit(text="x"),
  )
  assert_true(
    apply_host_text_event(
      session, host, binding, stale, adapter_test_measure, adapter_test_admit,
    )
    is Err(StaleEpoch),
  )
  let foreign = @text_host.TextInputEvent::new(
    @platform.WindowId::new(8),
    2L,
    binding.epoch(),
    @text_host.Commit(text="x"),
  )
  assert_true(
    apply_host_text_event(
      session, host, binding, foreign, adapter_test_measure, adapter_test_admit,
    )
    is Err(StaleWindow),
  )
  assert_eq(host.updates.length(), updates)
  assert_eq(session.snapshot().field().committed_document().text(), "before")
}

///|
test "apply reports focus loss and ends the transport" {
  let (session, field) = adapter_test_session("")
  let host = AdapterTestHost::new()
  let binding = start_host_text(session, host, field.caret_rect().unwrap()).unwrap()
  let lost = adapter_event(1L, binding.epoch(), @text_host.FocusLost)
  match
    apply_host_text_event(
      session, host, binding, lost, adapter_test_measure, adapter_test_admit,
    ) {
    Ok(FocusLost) => ()
    _ => abort("focus loss was not reported by apply")
  }
  assert_eq(host.ends.length(), 1)
}

///|
test "closed sessions reject every adapter step" {
  let (session, field) = adapter_test_session("")
  let host = AdapterTestHost::new()
  let binding = start_host_text(session, host, field.caret_rect().unwrap()).unwrap()
  ignore(session.close())
  assert_true(
    receive_host_text(
      session, host, binding, adapter_test_measure, adapter_test_admit,
    )
    is Err(Closed),
  )
  assert_true(end_host_text(session, host, binding) is Err(Closed))
}
