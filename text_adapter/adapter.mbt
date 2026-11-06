///|
/// Typed failure of the transport-to-session adapter. A host failure is kept
/// distinct from a model rejection so callers do not retag one as the other.
pub(all) enum HostTextError {
  /// The portable session or field rejected the operation.
  Session(@text_session.SessionError)
  /// The host transport rejected the operation.
  Host(@diagnostics.FrameworkError)
  /// The bound session is already closed.
  Closed
  /// An observation belongs to a different session epoch.
  StaleEpoch
  /// An observation belongs to a different window.
  StaleWindow
  /// A host value is outside the portable text contract.
  InvalidEvent
}

///|
/// The host-issued epoch of one live transport binding. It is not a session
/// identity; the portable `TextSession` remains the editing authority.
pub struct HostTextSession {
  priv epoch : UInt64
  priv window : @platform.WindowId
}

///|
pub fn HostTextSession::epoch(self : HostTextSession) -> UInt64 {
  self.epoch
}

///|
pub fn HostTextSession::window(self : HostTextSession) -> @platform.WindowId {
  self.window
}

///|
/// One accepted transport step. `Idle` means no observation was available;
/// `Applied` carries the session receipt; `FocusLost` reports that the host
/// revoked keyboard focus and the binding must be dropped.
pub(all) enum HostTextOutcome {
  Idle
  Applied(@text_session.BatchReceipt)
  FocusLost
}

///|
/// Start one host text session for the window and root already owned by the
/// portable session. The committed document and caret are published before the
/// binding is returned; a rejected handoff ends the transport again.
pub fn[T : @text_host.TextInputHost] start_host_text(
  session : @text_session.TextSession,
  host : T,
  caret : @primitives.Rect,
) -> Result[HostTextSession, HostTextError] {
  let snapshot = session.snapshot()
  if snapshot.is_closed() {
    return Err(Closed)
  }
  let window = snapshot.window()
  let root = snapshot.root_id()
  let epoch = match host.begin_text_input(window, root) {
    Err(failure) => return Err(Host(failure))
    Ok(value) => value
  }
  let binding = { epoch, window, }
  let field = snapshot.field()
  match
    host.update_text_input(
      epoch,
      @text_host.TextInputState::new(field.committed_document(), caret),
    ) {
    Err(failure) => {
      ignore(host.end_text_input(epoch))
      Err(Host(failure))
    }
    Ok(_) => Ok(binding)
  }
}

///|
/// Apply one ordered host observation through the existing `TextSession`
/// transaction. The observation is validated against the binding before it can
/// reach the document. After an accepted model step the committed document and
/// the painted caret are published back to the host.
fn[T : @text_host.TextInputHost] apply_host_operation(
  session : @text_session.TextSession,
  host : T,
  binding : HostTextSession,
  operation : @text_session.SessionOperation,
  measure : (@text.TextDocument) -> Result[
    @text_layout.TextMeasurement,
    @text_field.TextFieldError,
  ],
  admit : (@text.TextDocument, @text_layout.TextMeasurement) -> Result[
    Unit,
    @text_field.TextFieldError,
  ],
) -> Result[HostTextOutcome, HostTextError] {
  let target = match session.target() {
    Err(failure) => return Err(Session(failure))
    Ok(value) => value
  }
  let receipt = match session.apply_batch(target, [operation], measure, admit) {
    Err(failure) => return Err(Session(failure))
    Ok(value) => value
  }
  let field = receipt.snapshot().field()
  match field.caret_rect() {
    // A field without a paintable caret keeps the last host geometry; the
    // accepted document is still returned to the caller.
    Err(_) => ()
    Ok(caret) =>
      match
        host.update_text_input(
          binding.epoch,
          @text_host.TextInputState::new(field.committed_document(), caret),
        ) {
        Err(failure) => return Err(Host(failure))
        Ok(_) => ()
      }
  }
  Ok(Applied(receipt))
}

///|
/// Validate and apply one already-fetched host observation. The caller can
/// therefore choose a session that matches the current field before applying a
/// preview, without consuming the transport itself.
pub fn[T : @text_host.TextInputHost] apply_host_text_event(
  session : @text_session.TextSession,
  host : T,
  binding : HostTextSession,
  event : @text_host.TextInputEvent,
  measure : (@text.TextDocument) -> Result[
    @text_layout.TextMeasurement,
    @text_field.TextFieldError,
  ],
  admit : (@text.TextDocument, @text_layout.TextMeasurement) -> Result[
    Unit,
    @text_field.TextFieldError,
  ],
) -> Result[HostTextOutcome, HostTextError] {
  let snapshot = session.snapshot()
  if snapshot.is_closed() {
    return Err(Closed)
  }
  if snapshot.window() != binding.window {
    return Err(StaleWindow)
  }
  if event.window() != binding.window {
    return Err(StaleWindow)
  }
  if event.epoch() != binding.epoch {
    return Err(StaleEpoch)
  }
  match event.kind() {
    @text_host.FocusLost => {
      ignore(host.end_text_input(binding.epoch))
      Ok(FocusLost)
    }
    @text_host.Geometry(caret~, candidate~) => {
      ignore(candidate)
      let field = snapshot.field()
      match
        host.update_text_input(
          binding.epoch,
          @text_host.TextInputState::new(field.committed_document(), caret),
        ) {
        Err(failure) => Err(Host(failure))
        Ok(_) => Ok(Idle)
      }
    }
    @text_host.Preedit(text~, cursor~) => {
      if cursor < 0 || cursor > text.length() {
        return Err(InvalidEvent)
      }
      let selection = match @text.TextSelection::new(cursor, cursor) {
        Err(_) => return Err(InvalidEvent)
        Ok(value) => value
      }
      apply_host_operation(
        session,
        host,
        binding,
        @text_session.Preview(text, selection),
        measure,
        admit,
      )
    }
    @text_host.Commit(text~) =>
      apply_host_operation(
        session,
        host,
        binding,
        @text_session.Commit(text),
        measure,
        admit,
      )
    @text_host.Cancel =>
      apply_host_operation(
        session,
        host,
        binding,
        @text_session.Cancel,
        measure,
        admit,
      )
  }
}

///|
/// Drain one host observation and apply it. The caller owns the measurement and
/// admission policy; this adapter never fabricates layout or a document.
pub fn[T : @text_host.TextInputHost] receive_host_text(
  session : @text_session.TextSession,
  host : T,
  binding : HostTextSession,
  measure : (@text.TextDocument) -> Result[
    @text_layout.TextMeasurement,
    @text_field.TextFieldError,
  ],
  admit : (@text.TextDocument, @text_layout.TextMeasurement) -> Result[
    Unit,
    @text_field.TextFieldError,
  ],
  timeout_ms~ : Int32 = 16,
) -> Result[HostTextOutcome, HostTextError] {
  let snapshot = session.snapshot()
  if snapshot.is_closed() {
    return Err(Closed)
  }
  if snapshot.window() != binding.window {
    return Err(StaleWindow)
  }
  let event = match host.next_text_input(timeout_ms~) {
    Err(failure) => return Err(Host(failure))
    Ok(None) => return Ok(Idle)
    Ok(Some(value)) => value
  }
  apply_host_text_event(session, host, binding, event, measure, admit)
}

///|
/// Revoke the transport binding. The portable session stays bound to its field;
/// callers re-arm with a fresh `start_host_text` after the next real focus.
pub fn[T : @text_host.TextInputHost] end_host_text(
  session : @text_session.TextSession,
  host : T,
  binding : HostTextSession,
) -> Result[Unit, HostTextError] {
  let snapshot = session.snapshot()
  if snapshot.is_closed() {
    return Err(Closed)
  }
  if snapshot.window() != binding.window {
    return Err(StaleWindow)
  }
  match host.end_text_input(binding.epoch) {
    Err(failure) => Err(Host(failure))
    Ok(_) => Ok(())
  }
}
