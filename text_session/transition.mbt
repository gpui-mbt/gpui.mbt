///|
fn session_field_result(
  result : Result[@text_field.TextField, @text_field.TextFieldError],
) -> Result[@text_field.TextField, SessionError] {
  match result {
    Ok(field) => Ok(field)
    Err(error) => Err(FieldFailure(error))
  }
}

///|
fn stage_operation(
  field : @text_field.TextField,
  operation : SessionOperation,
  measure : (@text.TextDocument) -> Result[
    @text_layout.TextMeasurement,
    @text_field.TextFieldError,
  ],
  admit : (@text.TextDocument, @text_layout.TextMeasurement) -> Result[
    Unit,
    @text_field.TextFieldError,
  ],
) -> Result[(@text_field.TextField, SessionOutcome), SessionError] {
  let result = match operation {
    Preview(text, selection) =>
      field.update_composition(text, selection, measure, admit)
    PreviewUtf8(text, anchor, head) =>
      field.update_composition_utf8(text, anchor, head, measure, admit)
    Commit(text) => {
      if !field.is_composing() {
        return Err(NoComposition)
      }
      field.commit_composition(text, measure, admit)
    }
    Insert(text) => {
      if field.is_composing() {
        return Err(CompositionActive)
      }
      field.replace_selection(text, measure, admit)
    }
    Cancel => {
      if !field.is_composing() {
        return Err(NoComposition)
      }
      field.cancel_composition(measure, admit)
    }
  }
  let candidate = match session_field_result(result) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let outcome = match operation {
    Preview(_, _) | PreviewUtf8(_, _, _) => Previewed(candidate)
    Commit(_) | Insert(_) => Committed(candidate)
    Cancel => Cancelled(candidate)
  }
  Ok((candidate, outcome))
}

///|
fn receipt(
  target : SessionTarget,
  state : LiveState,
  outcomes : Array[SessionOutcome],
) -> BatchReceipt {
  { accepted_target: target, snapshot: snapshot(state), outcomes, }
}

///|
/// Prepare a bounds-only field candidate without publishing it or consuming a
/// text observation. The exact session target must still be live. The candidate
/// retains any composing preview and its original rollback snapshot.
///
/// This operation does not measure fonts, update a native host, publish a
/// scene, or establish atomicity with those owners. Use it only when the
/// existing measurements remain valid (for example, a bounds-only resize).
pub fn TextSession::prepare_bounds(
  self : TextSession,
  target : SessionTarget,
  bounds : @primitives.Rect,
) -> Result[BoundsProposal, SessionError] {
  if self.mutation_guard.busy {
    self.mutation_guard.violated = true
    return Err(Reentrant)
  }
  let state = self.state.val
  match validate_target(state, target) {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  if state.pending is Some(_) {
    return Err(PendingResolution)
  }
  if !state.field.is_focused() {
    return Err(Unfocused)
  }
  let field = match session_field_result(state.field.with_bounds(bounds)) {
    Err(error) => return Err(error)
    Ok(value) => value
  }
  Ok({ publication: state.publication, target, field, })
}

///|
/// Publish a still-current bounds-only proposal on this owner. This changes
/// field geometry without changing the session revision, the text delivery
/// watermark or the committed-document revision. A previously captured text
/// target stays valid for the same owner and next observation; no OS record is
/// acknowledged or retagged. The field's own revision advances on a real resize.
/// Stale, foreign, or reused proposals are rejected before publication.
///
/// This commits only the TextSession state. It is not an atomic commit of a
/// scene, focus scope, runtime action, or native host geometry.
pub fn TextSession::publish_bounds(
  self : TextSession,
  proposal : BoundsProposal,
) -> Result[SessionSnapshot, SessionError] {
  self.mutate(fn(state) {
    match validate_target(state, proposal.target) {
      Err(error) => return Err(error)
      Ok(_) => ()
    }
    if !same_identity(state.publication, proposal.publication) {
      return Err(StaleRevision)
    }
    if state.pending is Some(_) {
      return Err(PendingResolution)
    }
    if !state.field.is_focused() {
      return Err(Unfocused)
    }
    let candidate = { ..state, field: proposal.field, }
    Ok((candidate, snapshot(candidate)))
  })
}

///|
/// Apply an ordered batch against its original ingress target. Providers may
/// prepare measurements/resources only; their external effects cannot roll back.
/// A rejection returns no receipt and changes no field, revision or watermark.
pub fn TextSession::apply_batch(
  self : TextSession,
  target : SessionTarget,
  operations : Array[SessionOperation],
  measure : (@text.TextDocument) -> Result[
    @text_layout.TextMeasurement,
    @text_field.TextFieldError,
  ],
  admit : (@text.TextDocument, @text_layout.TextMeasurement) -> Result[
    Unit,
    @text_field.TextFieldError,
  ],
) -> Result[BatchReceipt, SessionError] {
  // Copy before invoking user code: callbacks cannot rewrite the queued batch.
  let operations = operations.copy()
  self.mutate(fn(state) {
    match validate_target(state, target) {
      Err(error) => return Err(error)
      Ok(_) => ()
    }
    if state.pending is Some(_) {
      return Err(PendingResolution)
    }
    if !state.field.is_focused() {
      return Err(Unfocused)
    }
    if operations.is_empty() {
      return Err(EmptyBatch)
    }
    let revision = match advance(state.revision) {
      Ok(value) => value
      Err(error) => return Err(error)
    }
    let guarded_measure = fn(document) {
      let result = measure(document)
      if self.mutation_guard.violated {
        Err(@text_field.MeasurementFailed)
      } else {
        result
      }
    }
    let guarded_admit = fn(document, measurement) {
      let result = admit(document, measurement)
      if self.mutation_guard.violated {
        Err(@text_field.AdmissionFailed)
      } else {
        result
      }
    }
    let mut field = state.field
    let mut committed_changed = false
    let outcomes = []
    for operation in operations {
      let (next, outcome) = match
        stage_operation(field, operation, guarded_measure, guarded_admit) {
        Ok(value) => value
        Err(error) => return Err(error)
      }
      committed_changed = committed_changed ||
        field.committed_document() != next.committed_document()
      field = next
      outcomes.push(outcome)
    }
    let document_revision = if committed_changed {
      match advance(state.document_revision) {
        Ok(value) => value
        Err(error) => return Err(error)
      }
    } else {
      state.document_revision
    }
    let candidate = {
      ..state,
      field,
      revision,
      document_revision,
      sequence: target.sequence,
    }
    Ok((candidate, receipt(target, candidate, outcomes)))
  })
}

///|
/// Request only. The field, composition and delivery watermark are unchanged.
/// The new pending token is the sole authority to deliver the observed ending.
pub fn TextSession::request_end(
  self : TextSession,
  target : SessionTarget,
  reason : EndReason,
) -> Result[PendingEnd, SessionError] {
  self.mutate(fn(state) {
    match validate_target(state, target) {
      Err(error) => return Err(error)
      Ok(_) => ()
    }
    if state.pending is Some(_) {
      return Err(PendingResolution)
    }
    let revision = match advance(state.revision) {
      Ok(value) => value
      Err(error) => return Err(error)
    }
    let candidate = { ..state, revision, }
    let target = match capture_target(candidate) {
      Ok(value) => value
      Err(error) => return Err(error)
    }
    let pending = { identity: identity(), target, reason, }
    Ok(({ ..candidate, pending: Some(pending), }, pending))
  })
}

///|
priv enum EndResolution {
  Observed(ObservedEnd)
  OwnerDiscard
  Uncomposed
}

///|
fn TextSession::finish_end(
  self : TextSession,
  pending : PendingEnd,
  resolution : EndResolution,
  replacement : (@platform.WindowId, UInt64, @text_field.TextField)?,
  measure : (@text.TextDocument) -> Result[
    @text_layout.TextMeasurement,
    @text_field.TextFieldError,
  ],
  admit : (@text.TextDocument, @text_layout.TextMeasurement) -> Result[
    Unit,
    @text_field.TextFieldError,
  ],
) -> Result[BatchReceipt, SessionError] {
  self.mutate(fn(state) {
    // Check identity before providers, including same-number foreign requests.
    match validate_target(state, pending.target) {
      Err(error) => return Err(error)
      Ok(_) => ()
    }
    match state.pending {
      Some(current) if same_identity(current.identity, pending.identity) => ()
      _ => return Err(InvalidPending)
    }
    match (pending.reason, replacement) {
      (Blur, None) => ()
      (ExternalReplacement, Some((window, root_id, field))) =>
        match validate_binding(window, root_id, field) {
          Err(error) => return Err(error)
          Ok(_) => ()
        }
      _ => return Err(WrongEndReason)
    }
    let revision = match advance(state.revision) {
      Ok(value) => value
      Err(error) => return Err(error)
    }
    let session = match advance(state.session) {
      Ok(value) => value
      Err(error) => return Err(error)
    }
    let guarded_measure = fn(document) {
      let result = measure(document)
      if self.mutation_guard.violated {
        Err(@text_field.MeasurementFailed)
      } else {
        result
      }
    }
    let guarded_admit = fn(document, measurement) {
      let result = admit(document, measurement)
      if self.mutation_guard.violated {
        Err(@text_field.AdmissionFailed)
      } else {
        result
      }
    }
    let resolved = match resolution {
      Observed(Committed(text)) => {
        if !state.field.is_focused() {
          return Err(Unfocused)
        }
        if !state.field.is_composing() {
          return Err(NoComposition)
        }
        state.field.commit_composition(text, guarded_measure, guarded_admit)
      }
      Observed(Cancelled) =>
        state.field.cancel_composition(guarded_measure, guarded_admit)
      OwnerDiscard => {
        if !state.field.is_composing() {
          return Err(NoComposition)
        }
        state.field.cancel_composition(guarded_measure, guarded_admit)
      }
      Uncomposed => {
        if state.field.is_composing() {
          return Err(CompositionActive)
        }
        Ok(state.field)
      }
    }
    let resolved = match session_field_result(resolved) {
      Ok(value) => value
      Err(error) => return Err(error)
    }
    let outcomes : Array[SessionOutcome] = []
    match resolution {
      Observed(Committed(_)) => outcomes.push(Committed(resolved))
      Observed(Cancelled) => outcomes.push(Cancelled(resolved))
      OwnerDiscard => outcomes.push(OwnerDiscarded(resolved))
      Uncomposed => ()
    }
    let changed = state.field.committed_document() !=
      resolved.committed_document() ||
      replacement is Some(_)
    let document_revision = if changed {
      match advance(state.document_revision) {
        Ok(value) => value
        Err(error) => return Err(error)
      }
    } else {
      state.document_revision
    }
    let candidate = {
      ..state,
      field: resolved,
      revision,
      session,
      document_revision,
      sequence: pending.target.sequence,
      pending: None,
    }
    let candidate = match replacement {
      None => {
        // with_focus(false) may cancel a composition internally, so it is used
        // only after successful explicit resolution above.
        let field = match session_field_result(resolved.with_focus(false)) {
          Ok(value) => value
          Err(error) => return Err(error)
        }
        outcomes.push(Blurred(field))
        { ..candidate, field, }
      }
      Some((window, root_id, field)) => {
        outcomes.push(Rebound(field))
        {
          ..candidate,
          window,
          root_id,
          field,
          window_instance: identity(),
          root_instance: identity(),
          field_instance: identity(),
        }
      }
    }
    Ok((candidate, receipt(pending.target, candidate, outcomes)))
  })
}

///|
/// Commit/cancel is observed before blur. Admission failure leaves the pending
/// request live; the caller must resynchronize any already-observed OS commit.
pub fn TextSession::complete_blur(
  self : TextSession,
  pending : PendingEnd,
  observed : ObservedEnd,
  measure : (@text.TextDocument) -> Result[
    @text_layout.TextMeasurement,
    @text_field.TextFieldError,
  ],
  admit : (@text.TextDocument, @text_layout.TextMeasurement) -> Result[
    Unit,
    @text_field.TextFieldError,
  ],
) -> Result[BatchReceipt, SessionError] {
  self.finish_end(pending, Observed(observed), None, measure, admit)
}

///|
/// Resolve a blur by deliberately discarding the active preedit at an
/// application owner's explicit request. This does not assert that the OS
/// canceled composition. The owner must first process every accepted text
/// observation for this binding and establish its own host-specific cutoff;
/// this portable method cannot verify either condition. A plain Tab or focus
/// change is not by itself permission to discard. If resolution fails the
/// pending end remains live and the old field is unchanged.
pub fn TextSession::complete_blur_by_owner_discard(
  self : TextSession,
  pending : PendingEnd,
  measure : (@text.TextDocument) -> Result[
    @text_layout.TextMeasurement,
    @text_field.TextFieldError,
  ],
  admit : (@text.TextDocument, @text_layout.TextMeasurement) -> Result[
    Unit,
    @text_field.TextFieldError,
  ],
) -> Result[BatchReceipt, SessionError] {
  self.finish_end(pending, OwnerDiscard, None, measure, admit)
}

///|
/// Complete a pending blur when no preview remains, without reporting an OS
/// cancellation. The owner must first process accepted old-binding records and
/// establish its host-specific cutoff. Active composition is rejected and the
/// pending request stays live; no provider is called on this path.
pub fn TextSession::complete_blur_if_uncomposed(
  self : TextSession,
  pending : PendingEnd,
) -> Result[BatchReceipt, SessionError] {
  self.finish_end(
    pending,
    Uncomposed,
    None,
    _ => Err(@text_field.MeasurementFailed),
    (_, _) => Err(@text_field.AdmissionFailed),
  )
}

///|
/// Resolve first, then install a prevalidated noncomposing field. Both ordered
/// outcomes are returned, including the resolved old document and its history.
pub fn TextSession::complete_replacement(
  self : TextSession,
  pending : PendingEnd,
  observed : ObservedEnd,
  window : @platform.WindowId,
  root_id : UInt64,
  field : @text_field.TextField,
  measure : (@text.TextDocument) -> Result[
    @text_layout.TextMeasurement,
    @text_field.TextFieldError,
  ],
  admit : (@text.TextDocument, @text_layout.TextMeasurement) -> Result[
    Unit,
    @text_field.TextFieldError,
  ],
) -> Result[BatchReceipt, SessionError] {
  self.finish_end(
    pending,
    Observed(observed),
    Some((window, root_id, field)),
    measure,
    admit,
  )
}

///|
fn require_idle(state : LiveState) -> Result[Unit, SessionError] {
  if state.closed {
    return Err(Closed)
  }
  if state.pending is Some(_) {
    return Err(PendingResolution)
  }
  if state.field.is_composing() {
    return Err(CompositionActive)
  }
  Ok(())
}

///|
/// Explicit window/root/field replacement. Even equal IDs and field values
/// receive new incarnations. Active composition must first use an end request.
pub fn TextSession::rebind(
  self : TextSession,
  window : @platform.WindowId,
  root_id : UInt64,
  field : @text_field.TextField,
) -> Result[Unit, SessionError] {
  self.mutate(fn(state) {
    match require_idle(state) {
      Err(error) => return Err(error)
      Ok(_) => ()
    }
    match validate_binding(window, root_id, field) {
      Err(error) => return Err(error)
      Ok(_) => ()
    }
    let session = match advance(state.session) {
      Ok(value) => value
      Err(error) => return Err(error)
    }
    let revision = match advance(state.revision) {
      Ok(value) => value
      Err(error) => return Err(error)
    }
    let document_revision = match advance(state.document_revision) {
      Ok(value) => value
      Err(error) => return Err(error)
    }
    Ok(
      (
        {
          ..state,
          window,
          root_id,
          field,
          session,
          revision,
          document_revision,
          window_instance: identity(),
          root_instance: identity(),
          field_instance: identity(),
        },
        (),
      ),
    )
  })
}

///|
/// Refocus a resolved binding and start a fresh session without resetting the
/// delivery watermark. Does not adopt an arbitrary edited snapshot.
pub fn TextSession::rearm(self : TextSession) -> Result[Unit, SessionError] {
  self.mutate(fn(state) {
    match require_idle(state) {
      Err(error) => return Err(error)
      Ok(_) => ()
    }
    let session = match advance(state.session) {
      Ok(value) => value
      Err(error) => return Err(error)
    }
    let revision = match advance(state.revision) {
      Ok(value) => value
      Err(error) => return Err(error)
    }
    let field = match session_field_result(state.field.with_focus(true)) {
      Ok(value) => value
      Err(error) => return Err(error)
    }
    Ok(({ ..state, field, session, revision, }, ()))
  })
}

///|
/// Terminal revocation, also available at counter exhaustion. Preserves the
/// last field and counters for diagnostics; does not claim an OS cancellation.
pub fn TextSession::close(self : TextSession) -> Result[Unit, SessionError] {
  self.mutate(fn(state) {
    // Repeated teardown through any shared handle is successful and preserves
    // the last visible snapshot. The mutation guard still rejects reentrancy.
    if state.closed {
      return Ok((state, ()))
    }
    Ok(({ ..state, closed: true, pending: None, }, ()))
  })
}
