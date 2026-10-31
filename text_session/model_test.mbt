///|
fn rect(x : Double, width : Double) -> @primitives.Rect {
  @primitives.Rect::new(x, 0.0, width, 16.0).unwrap()
}

///|
// Scripted scalar-boundary metrics for these fixtures, not a shaping engine.
fn measure(
  document : @text.TextDocument,
) -> Result[@text_layout.TextMeasurement, @text_field.TextFieldError] {
  let carets = []
  let mut offset = 0
  let mut x = 0.0
  carets.push(
    @text_layout.CaretGeometry::new(0, true, rect(x, 0.0), rect(x, 0.0)).unwrap(),
  )
  for scalar in document.text().iter() {
    offset += if scalar.to_int() > 0xFFFF { 2 } else { 1 }
    x += 8.0
    carets.push(
      @text_layout.CaretGeometry::new(offset, true, rect(x, 0.0), rect(x, 0.0)).unwrap(),
    )
  }
  Ok(
    @text_layout.TextMeasurement::new(
      document,
      rect(0.0, x),
      rect(0.0, x),
      12.0,
      1,
      0,
      carets,
    ).unwrap(),
  )
}

///|
fn admit(
  _ : @text.TextDocument,
  _ : @text_layout.TextMeasurement,
) -> Result[Unit, @text_field.TextFieldError] {
  Ok(())
}

///|
fn field(text : String, anchor : Int32, head : Int32) -> @text_field.TextField {
  @text_field.TextField::new(
    19UL,
    @primitives.Rect::new(0.0, 0.0, 100.0, 36.0).unwrap(),
    10.0,
    @text.TextDocument::new(text)
    .unwrap()
    .with_selection(@text.TextSelection::new(anchor, head).unwrap())
    .unwrap(),
    measure,
    admit,
  )
  .unwrap()
  .with_focus(true)
  .unwrap()
}

///|
fn owner() -> @text_session.TextSession {
  @text_session.TextSession::new(
    @platform.WindowId::new(1L),
    7UL,
    field("abcd", 3, 1),
  ).unwrap()
}

///|
fn preview(text : String) -> @text_session.SessionOperation {
  @text_session.Preview(
    text,
    @text.TextSelection::new(text.length(), text.length()).unwrap(),
  )
}

///|
fn apply(
  session : @text_session.TextSession,
  ops : Array[@text_session.SessionOperation],
) -> @text_session.BatchReceipt {
  session.apply_batch(session.target().unwrap(), ops, measure, admit).unwrap()
}

///|
fn assert_field(
  expected : @text_field.TextField,
  actual : @text_field.TextField,
) -> Unit raise {
  assert_true(expected.document() == actual.document())
  assert_true(expected.committed_document() == actual.committed_document())
  assert_true(expected.selection() == actual.selection())
  assert_true(expected.marked_range() == actual.marked_range())
  assert_eq(expected.revision(), actual.revision())
  assert_eq(expected.is_composing(), actual.is_composing())
  assert_eq(expected.is_focused(), actual.is_focused())
  assert_eq(expected.can_undo(), actual.can_undo())
  assert_eq(expected.can_redo(), actual.can_redo())
  assert_eq(expected.scroll_offset(), actual.scroll_offset())
  assert_true(expected.bounds() == actual.bounds())
  assert_true(
    expected.measurement().document() == actual.measurement().document(),
  )
  assert_true(
    expected.measurement().logical_rect() == actual.measurement().logical_rect(),
  )
  assert_true(
    expected.measurement().ink_rect() == actual.measurement().ink_rect(),
  )
  let left = expected.measurement().carets()
  let right = actual.measurement().carets()
  assert_eq(left.length(), right.length())
  for index in 0..<left.length() {
    assert_eq(left[index].utf16_offset(), right[index].utf16_offset())
    assert_eq(
      left[index].is_cursor_position(),
      right[index].is_cursor_position(),
    )
    assert_true(left[index].strong() == right[index].strong())
    assert_true(left[index].weak() == right[index].weak())
  }
}

///|
fn assert_snapshot(
  expected : @text_session.SessionSnapshot,
  actual : @text_session.SessionSnapshot,
) -> Unit raise {
  assert_field(expected.field(), actual.field())
  assert_true(expected.window() == actual.window())
  assert_eq(expected.root_id(), actual.root_id())
  assert_eq(expected.session_id(), actual.session_id())
  assert_eq(expected.published_revision(), actual.published_revision())
  assert_eq(
    expected.committed_document_revision(),
    actual.committed_document_revision(),
  )
  assert_eq(expected.delivery_watermark(), actual.delivery_watermark())
  assert_eq(expected.is_closed(), actual.is_closed())
  assert_eq(expected.has_pending_end(), actual.has_pending_end())
}

///|
test "directional repeated Japanese previews commit once with original history" {
  let session = owner()
  let original = session.snapshot().field()
  let ingress = session.target().unwrap()
  let receipt = session
    .apply_batch(
      ingress,
      [
        preview("に"),
        preview("にほん"),
        preview("日本"),
        @text_session.Commit("日本"),
      ],
      measure,
      admit,
    )
    .unwrap()
  assert_eq(receipt.outcomes().length(), 4)
  assert_true(receipt.acknowledges(ingress))
  let committed = session.snapshot().field()
  assert_eq(committed.document().text(), "a日本d")
  assert_true(committed.selection() == @text.TextSelection::new(3, 3).unwrap())
  assert_false(committed.is_composing())
  assert_eq(session.snapshot().published_revision(), 1UL)
  assert_eq(session.snapshot().committed_document_revision(), 1UL)
  assert_eq(session.snapshot().delivery_watermark(), 1UL)
  let undone = committed.undo(measure, admit).unwrap()
  assert_true(undone.document() == original.document())
  assert_false(undone.can_undo())
  assert_true(
    undone.redo(measure, admit).unwrap().document() == committed.document(),
  )
  // A detached immutable branch cannot update the live owner.
  assert_eq(session.snapshot().field().document().text(), "a日本d")
  assert_true(
    session.apply_batch(
      ingress,
      [@text_session.Commit("again")],
      measure,
      admit,
    )
    is Err(@text_session.Replay),
  )
  assert_true(
    session.apply_batch(
      session.target().unwrap(),
      [@text_session.Commit("again")],
      measure,
      admit,
    )
    is Err(@text_session.NoComposition),
  )
}

///|
test "empty preview retains composition and cancellation restores direction and redo" {
  let base = field("abcd", 3, 1)
  let edited = base.replace_selection("X", measure, admit).unwrap()
  let original = edited.undo(measure, admit).unwrap()
  let session = @text_session.TextSession::new(
    @platform.WindowId::new(1L),
    7UL,
    original,
  ).unwrap()
  let empty = apply(session, [preview("")])
  assert_false(empty.snapshot().field().is_composing())
  assert_eq(empty.snapshot().committed_document_revision(), 0UL)
  let _ = apply(session, [preview("日本"), preview("")])
  let hidden = session.snapshot().field()
  assert_true(hidden.is_composing())
  assert_true(hidden.marked_range() is None)
  assert_true(hidden.document() == original.document())
  assert_eq(session.snapshot().committed_document_revision(), 0UL)
  let _ = apply(session, [@text_session.Cancel])
  let cancelled = session.snapshot().field()
  assert_true(cancelled.document() == original.document())
  assert_true(cancelled.selection() == @text.TextSelection::new(3, 1).unwrap())
  assert_true(cancelled.can_redo())
  assert_true(
    cancelled.redo(measure, admit).unwrap().document() == edited.document(),
  )
  assert_eq(session.snapshot().committed_document_revision(), 0UL)
}

///|
test "strict UTF8 directional conversion keeps emoji endpoints and rejects malformed input" {
  let session = owner()
  let result = apply(session, [@text_session.PreviewUtf8("😀日本é", 10, 4)])
  let current = result.snapshot().field()
  assert_eq(current.document().text(), "a😀日本éd")
  assert_true(current.selection() == @text.TextSelection::new(5, 3).unwrap())
  let original = session.snapshot()
  let calls = [0]
  let count = fn(document) {
    calls[0] += 1
    measure(document)
  }
  for endpoint in [-1, 1, 2, 3, 5, 100] {
    assert_true(
      session.apply_batch(
        session.target().unwrap(),
        [@text_session.PreviewUtf8("😀", endpoint, 0)],
        count,
        admit,
      )
      is Err(@text_session.FieldFailure(@text_field.InvalidSelection)),
    )
  }
  assert_true(
    session.apply_batch(
      session.target().unwrap(),
      [@text_session.Preview("😀", @text.TextSelection::new(1, 0).unwrap())],
      count,
      admit,
    )
    is Err(@text_session.FieldFailure(@text_field.InvalidSelection)),
  )
  let malformed = "😀".unsafe_substring(start=0, end=1)
  assert_true(
    session.apply_batch(
      session.target().unwrap(),
      [@text_session.PreviewUtf8(malformed, 0, 0)],
      count,
      admit,
    )
    is Err(@text_session.FieldFailure(@text_field.MalformedText)),
  )
  assert_true(
    session.apply_batch(
      session.target().unwrap(),
      [@text_session.Commit(malformed)],
      count,
      admit,
    )
    is Err(@text_session.FieldFailure(@text_field.MalformedText)),
  )
  assert_eq(calls[0], 0)
  assert_snapshot(original, session.snapshot())
}

///|
test "commit only and unfocused deliveries reject before providers" {
  let session = owner()
  let before = session.snapshot()
  let calls = [0]
  let count = fn(document) {
    calls[0] += 1
    measure(document)
  }
  assert_true(
    session.apply_batch(
      session.target().unwrap(),
      [@text_session.Commit("X")],
      count,
      admit,
    )
    is Err(@text_session.NoComposition),
  )
  assert_true(
    session.apply_batch(session.target().unwrap(), [], count, admit)
    is Err(@text_session.EmptyBatch),
  )
  assert_snapshot(before, session.snapshot())
  let unfocused = @text_session.TextSession::new(
    @platform.WindowId::new(1L),
    7UL,
    before.field().with_focus(false).unwrap(),
  ).unwrap()
  assert_true(
    unfocused.apply_batch(
      unfocused.target().unwrap(),
      [preview("X")],
      count,
      admit,
    )
    is Err(@text_session.Unfocused),
  )
  assert_eq(calls[0], 0)
}

///|
test "foreign owners and copied handles cannot bypass stale replay or terminal revocation" {
  let session = owner()
  let copy = session
  let foreign = owner()
  let target = session.target().unwrap()
  let calls = [0]
  let count = fn(document) {
    calls[0] += 1
    measure(document)
  }
  assert_true(
    foreign.apply_batch(target, [preview("X")], count, admit)
    is Err(@text_session.ForeignOwner),
  )
  let _ = apply(copy, [preview("X")])
  assert_true(session.snapshot().field().is_composing())
  assert_true(
    session.apply_batch(target, [preview("Y")], count, admit)
    is Err(@text_session.Replay),
  )
  let current = session.target().unwrap()
  copy.close().unwrap()
  assert_true(session.snapshot().is_closed())
  assert_true(
    session.apply_batch(current, [@text_session.Commit("X")], count, admit)
    is Err(@text_session.Closed),
  )
  assert_eq(calls[0], 0)
}

///|
test "same numeric window root field and revision cannot revive replaced bindings" {
  let session = owner()
  let original = session.snapshot().field()
  let calls = [0]
  let count = fn(document) {
    calls[0] += 1
    measure(document)
  }
  for
    replacement in [
      (1L, 7UL, original),
      (1L, 8UL, original),
      (2L, 8UL, original),
    ] {
    let old = session.target().unwrap()
    session
    .rebind(
      @platform.WindowId::new(replacement.0),
      replacement.1,
      replacement.2,
    )
    .unwrap()
    assert_true(
      session.apply_batch(old, [preview("X")], count, admit)
      is Err(@text_session.StaleBinding),
    )
  }
  let old = session.target().unwrap()
  session.rearm().unwrap()
  assert_true(
    session.apply_batch(old, [preview("X")], count, admit)
    is Err(@text_session.StaleSession),
  )
  assert_eq(calls[0], 0)
}

///|
test "invalid second operation rolls back first including geometry and history" {
  let session = owner()
  let before = session.snapshot()
  let target = session.target().unwrap()
  let result = session.apply_batch(
    target,
    [preview("日本"), @text_session.PreviewUtf8("😀", 1, 0)],
    measure,
    admit,
  )
  assert_true(
    result is Err(@text_session.FieldFailure(@text_field.InvalidSelection)),
  )
  assert_snapshot(before, session.snapshot())
  // The rejected target is still usable: rejection did not acknowledge it.
  let receipt = session
    .apply_batch(target, [preview("日本")], measure, admit)
    .unwrap()
  assert_true(receipt.acknowledges(target))
  assert_eq(receipt.snapshot().delivery_watermark(), 1UL)
}

///|
test "measurement admission and unsupported cursor failures preserve full published state" {
  let session = owner()
  let _ = apply(session, [preview("日本")])
  for
    operation in [
      preview("次"),
      preview(""),
      @text_session.Commit("終"),
      @text_session.Cancel,
    ] {
    let before = session.snapshot()
    let target = session.target().unwrap()
    assert_true(
      session.apply_batch(
        target,
        [operation],
        _ => Err(@text_field.MeasurementFailed),
        admit,
      )
      is Err(@text_session.FieldFailure(@text_field.MeasurementFailed)),
    )
    assert_snapshot(before, session.snapshot())
    assert_true(
      session.apply_batch(target, [operation], measure, (_, _) => {
        Err(@text_field.AdmissionFailed)
      })
      is Err(@text_session.FieldFailure(@text_field.AdmissionFailed)),
    )
    assert_snapshot(before, session.snapshot())
  }
  let before = session.snapshot()
  let missing_stop = fn(document) {
    let base = measure(document).unwrap()
    let carets = base
      .carets()
      .map(fn(caret) {
        @text_layout.CaretGeometry::new(
          caret.utf16_offset(),
          caret.utf16_offset() != 2,
          caret.strong(),
          caret.weak(),
        ).unwrap()
      })
    Ok(
      @text_layout.TextMeasurement::new(
        document,
        base.logical_rect(),
        base.ink_rect(),
        base.first_line_baseline(),
        1,
        0,
        carets,
      ).unwrap(),
    )
  }
  assert_true(
    session.apply_batch(
      session.target().unwrap(),
      [preview("X")],
      missing_stop,
      admit,
    )
    is Err(@text_session.FieldFailure(@text_field.InvalidSelection)),
  )
  assert_true(
    session.apply_batch(
      session.target().unwrap(),
      [@text_session.Commit("X")],
      missing_stop,
      admit,
    )
    is Err(@text_session.FieldFailure(@text_field.InvalidSelection)),
  )
  assert_snapshot(before, session.snapshot())
}

///|
test "end request is distinct from observed commit then blur" {
  let session = owner()
  let _ = apply(session, [preview("にほん")])
  let before = session.snapshot()
  let old = session.target().unwrap()
  let pending = session.request_end(old, @text_session.Blur).unwrap()
  assert_field(before.field(), session.snapshot().field())
  assert_true(session.snapshot().field().is_composing())
  assert_eq(
    session.snapshot().delivery_watermark(),
    before.delivery_watermark(),
  )
  assert_true(session.target() is Err(@text_session.PendingResolution))
  assert_true(
    session.apply_batch(old, [@text_session.Cancel], measure, admit)
    is Err(@text_session.StaleRevision),
  )
  assert_true(
    session.apply_batch(
      pending.target(),
      [@text_session.Cancel],
      measure,
      admit,
    )
    is Err(@text_session.PendingResolution),
  )
  let receipt = session
    .complete_blur(pending, @text_session.Committed("日本"), measure, admit)
    .unwrap()
  assert_eq(receipt.outcomes().length(), 2)
  assert_true(
    receipt.outcomes()[0] is @text_session.SessionOutcome::Committed(_),
  )
  assert_true(receipt.outcomes()[1] is @text_session.Blurred(_))
  let result = session.snapshot().field()
  assert_eq(result.document().text(), "a日本d")
  assert_false(result.is_focused())
  assert_false(result.is_composing())
  assert_true(result.can_undo())
  assert_true(
    session.complete_blur(pending, @text_session.Cancelled, measure, admit)
    is Err(@text_session.StaleSession),
  )
}

///|
test "observed cancel precedes blur and pending tokens reject foreign completion" {
  let session = owner()
  let foreign = owner()
  let original = session.snapshot().field().document()
  let _ = apply(session, [preview("日本")])
  let pending = session
    .request_end(session.target().unwrap(), @text_session.Blur)
    .unwrap()
  let calls = [0]
  let count = fn(document) {
    calls[0] += 1
    measure(document)
  }
  assert_true(
    foreign.complete_blur(
      pending,
      @text_session.Committed("日本"),
      count,
      admit,
    )
    is Err(@text_session.ForeignOwner),
  )
  assert_eq(calls[0], 0)
  let receipt = session
    .complete_blur(pending, @text_session.Cancelled, measure, admit)
    .unwrap()
  assert_true(
    receipt.outcomes()[0] is @text_session.SessionOutcome::Cancelled(_),
  )
  assert_true(receipt.outcomes()[1] is @text_session.Blurred(_))
  assert_true(session.snapshot().field().document() == original)
  assert_false(session.snapshot().field().is_focused())
  assert_eq(session.snapshot().committed_document_revision(), 0UL)
}

///|
test "explicit owner discard preserves earlier observed commit and is not an OS cancel" {
  let session = owner()
  ignore(apply(session, [preview("にほん")]))
  ignore(apply(session, [@text_session.Commit("日本")]))
  let committed = session.snapshot().field()
  assert_eq(committed.committed_document().text(), "a日本d")
  assert_true(committed.can_undo())
  ignore(apply(session, [preview("よみ")]))
  let target = session.target().unwrap()
  let pending = session.request_end(target, @text_session.Blur).unwrap()
  let before = session.snapshot()
  let rejecting_admit = fn(_document, _measurement) {
    Err(@text_field.AdmissionFailed)
  }
  assert_true(
    session.complete_blur_by_owner_discard(pending, measure, rejecting_admit)
    is Err(@text_session.FieldFailure(@text_field.AdmissionFailed)),
  )
  assert_snapshot(before, session.snapshot())
  let receipt = session
    .complete_blur_by_owner_discard(pending, measure, admit)
    .unwrap()
  assert_true(receipt.outcomes()[0] is @text_session.OwnerDiscarded(_))
  assert_true(receipt.outcomes()[1] is @text_session.Blurred(_))
  let result = session.snapshot().field()
  assert_eq(result.committed_document().text(), "a日本d")
  assert_false(result.is_composing())
  assert_false(result.is_focused())
  assert_true(result.can_undo())
  assert_eq(
    result
    .with_focus(true)
    .unwrap()
    .undo(measure, admit)
    .unwrap()
    .document()
    .text(),
    "abcd",
  )
  assert_true(
    session.complete_blur_by_owner_discard(pending, measure, admit)
    is Err(@text_session.StaleSession),
  )
  assert_true(
    session.apply_batch(
      target,
      [@text_session.Commit("遅延")],
      measure,
      admit,
    )
    is Err(_),
  )
}

///|
test "owner discard requires active composition and a blur request" {
  let session = owner()
  let pending = session
    .request_end(session.target().unwrap(), @text_session.Blur)
    .unwrap()
  let before = session.snapshot()
  assert_true(
    session.complete_blur_by_owner_discard(pending, measure, admit)
    is Err(@text_session.NoComposition),
  )
  assert_snapshot(before, session.snapshot())
  let replacement = owner()
  ignore(apply(replacement, [preview("未確定")]))
  let pending = replacement
    .request_end(
      replacement.target().unwrap(),
      @text_session.ExternalReplacement,
    )
    .unwrap()
  assert_true(
    replacement.complete_blur_by_owner_discard(pending, measure, admit)
    is Err(@text_session.WrongEndReason),
  )
}

///|
test "uncomposed blur retains the observed commit without inventing a cancellation" {
  let session = owner()
  ignore(apply(session, [preview("にほん")]))
  ignore(apply(session, [@text_session.Commit("日本")]))
  let target = session.target().unwrap()
  let pending = session.request_end(target, @text_session.Blur).unwrap()
  let receipt = session.complete_blur_if_uncomposed(pending).unwrap()
  assert_eq(receipt.outcomes().length(), 1)
  assert_true(receipt.outcomes()[0] is @text_session.Blurred(_))
  let field = session.snapshot().field()
  assert_eq(field.committed_document().text(), "a日本d")
  assert_false(field.is_composing())
  assert_false(field.is_focused())
  assert_eq(
    field
    .with_focus(true)
    .unwrap()
    .undo(measure, admit)
    .unwrap()
    .document()
    .text(),
    "abcd",
  )
  assert_true(
    session.complete_blur_if_uncomposed(pending)
    is Err(@text_session.StaleSession),
  )
  assert_true(
    session.apply_batch(
      target,
      [@text_session.Commit("遅延")],
      measure,
      admit,
    )
    is Err(_),
  )
}

///|
test "uncomposed blur refuses an active preview without changing the pending state" {
  let session = owner()
  ignore(apply(session, [preview("にほん")]))
  let pending = session
    .request_end(session.target().unwrap(), @text_session.Blur)
    .unwrap()
  let before = session.snapshot()
  assert_true(
    session.complete_blur_if_uncomposed(pending)
    is Err(@text_session.CompositionActive),
  )
  assert_snapshot(before, session.snapshot())
  // A real observed ending can still resolve the same request.
  ignore(
    session
    .complete_blur(pending, @text_session.Committed("日本"), measure, admit)
    .unwrap(),
  )
}

///|
test "direct observed commit preserves its owner and rejects replay" {
  let session = owner()
  let target = session.target().unwrap()
  let receipt = session
    .apply_batch(target, [@text_session.Insert("日本")], measure, admit)
    .unwrap()
  assert_true(
    receipt.outcomes()[0] is @text_session.SessionOutcome::Committed(_),
  )
  assert_eq(session.snapshot().field().committed_document().text(), "a日本d")
  assert_eq(session.snapshot().committed_document_revision(), 1UL)
  let before = session.snapshot()
  assert_true(
    session.apply_batch(
      target,
      [@text_session.Insert("日本")],
      measure,
      admit,
    )
    is Err(_),
  )
  assert_snapshot(before, session.snapshot())
  assert_eq(
    session.snapshot().field().undo(measure, admit).unwrap().document().text(),
    "abcd",
  )
}

///|
test "direct commit rejects active composition and failed admission atomically" {
  let session = owner()
  ignore(apply(session, [preview("にほん")]))
  let before = session.snapshot()
  assert_true(
    session.apply_batch(
      session.target().unwrap(),
      [@text_session.Insert("日本")],
      measure,
      admit,
    )
    is Err(@text_session.CompositionActive),
  )
  assert_snapshot(before, session.snapshot())
  let fresh = owner()
  let before = fresh.snapshot()
  let reject = fn(
    _ : @text.TextDocument,
    _ : @text_layout.TextMeasurement,
  ) -> Result[Unit, @text_field.TextFieldError] {
    Err(@text_field.AdmissionFailed)
  }
  assert_true(
    fresh.apply_batch(
      fresh.target().unwrap(),
      [@text_session.Insert("日本")],
      measure,
      reject,
    )
    is Err(@text_session.FieldFailure(@text_field.AdmissionFailed)),
  )
  assert_snapshot(before, fresh.snapshot())
}

///|
test "external replacement retains observed old commit before validated rebind" {
  let session = owner()
  let _ = apply(session, [preview("にほん")])
  let pending = session
    .request_end(session.target().unwrap(), @text_session.ExternalReplacement)
    .unwrap()
  let before = session.snapshot()
  assert_true(
    session.complete_blur(pending, @text_session.Cancelled, measure, admit)
    is Err(@text_session.WrongEndReason),
  )
  assert_snapshot(before, session.snapshot())
  let replacement = field("external", 8, 8)
  let receipt = session
    .complete_replacement(
      pending,
      @text_session.Committed("日本"),
      @platform.WindowId::new(1L),
      7UL,
      replacement,
      measure,
      admit,
    )
    .unwrap()
  match receipt.outcomes()[0] {
    @text_session.SessionOutcome::Committed(old) => {
      assert_eq(old.document().text(), "a日本d")
      assert_true(old.can_undo())
    }
    _ => fail("observed commit must remain the first outcome")
  }
  assert_true(receipt.outcomes()[1] is @text_session.Rebound(_))
  assert_eq(session.snapshot().field().document().text(), "external")
  assert_true(
    session.apply_batch(pending.target(), [preview("late")], measure, admit)
    is Err(@text_session.StaleBinding),
  )
}

///|
test "failed observed commit keeps pending request resolvable without ACK" {
  let session = owner()
  let _ = apply(session, [preview("日本")])
  let pending = session
    .request_end(session.target().unwrap(), @text_session.Blur)
    .unwrap()
  let before = session.snapshot()
  assert_true(
    session.complete_blur(pending, @text_session.Committed("日本"), measure, (
      _,
      _,
    ) => Err(@text_field.AdmissionFailed))
    is Err(@text_session.FieldFailure(@text_field.AdmissionFailed)),
  )
  assert_snapshot(before, session.snapshot())
  let receipt = session
    .complete_blur(pending, @text_session.Committed("日本"), measure, admit)
    .unwrap()
  assert_true(receipt.acknowledges(pending.target()))
  assert_eq(session.snapshot().field().document().text(), "a日本d")
}

///|
test "reentrant providers cannot publish through handle copies or mutate captured arrays" {
  let session = owner()
  let copy = session
  let before = session.snapshot()
  let target = session.target().unwrap()
  let operations = [preview("日本")]
  let admission_calls = [0]
  let nested = fn(document) {
    assert_reentrant(copy.close())
    operations[0] = @text_session.Commit("rewritten")
    measure(document)
  }
  assert_true(
    session.apply_batch(target, operations, nested, fn(_, _) {
      admission_calls[0] += 1
      Ok(())
    })
    is Err(@text_session.Reentrant),
  )
  assert_eq(admission_calls[0], 0)
  assert_snapshot(before, session.snapshot())
  let operations = [preview("日本"), @text_session.Commit("日本")]
  let rewrite = fn(document) {
    operations[1] = @text_session.Commit("wrong")
    measure(document)
  }
  let receipt = session.apply_batch(target, operations, rewrite, admit).unwrap()
  assert_eq(receipt.snapshot().field().document().text(), "a日本d")
}

///|
fn assert_reentrant(result : Result[Unit, @text_session.SessionError]) -> Unit {
  if !(result is Err(@text_session.Reentrant)) {
    abort("nested mutation was not rejected")
  }
}

///|
test "all lifecycle mutation attempts poison reentrant admission atomically" {
  for mode in 0..<5 {
    let session = owner()
    let before = session.snapshot()
    let target = session.target().unwrap()
    let nested = fn(_, _) {
      match mode {
        0 => assert_reentrant(session.rearm())
        1 =>
          assert_reentrant(
            session.rebind(@platform.WindowId::new(1L), 7UL, before.field()),
          )
        2 =>
          if !(session.request_end(target, @text_session.Blur)
            is Err(@text_session.Reentrant)) {
            abort("request reentered")
          }
        3 =>
          if !(session.apply_batch(target, [preview("nested")], measure, admit)
            is Err(@text_session.Reentrant)) {
            abort("batch reentered")
          }
        _ => assert_reentrant(session.close())
      }
      Ok(())
    }
    assert_true(
      session.apply_batch(target, [preview("日本")], measure, nested)
      is Err(@text_session.Reentrant),
    )
    assert_snapshot(before, session.snapshot())
    let _ = session
      .apply_batch(target, [preview("日本")], measure, admit)
      .unwrap()
  }
}

///|
test "active compositions and invalid replacement candidates cannot bypass resolution" {
  let session = owner()
  let initial = session.snapshot()
  assert_true(
    session.rebind(@platform.WindowId::new(0L), 7UL, initial.field())
    is Err(@text_session.InvalidBinding),
  )
  assert_true(
    session.rebind(@platform.WindowId::new(1L), 0UL, initial.field())
    is Err(@text_session.InvalidBinding),
  )
  assert_snapshot(initial, session.snapshot())
  let _ = apply(session, [preview("日本")])
  let active = session.snapshot()
  assert_true(session.rearm() is Err(@text_session.CompositionActive))
  assert_true(
    session.rebind(@platform.WindowId::new(1L), 7UL, initial.field())
    is Err(@text_session.CompositionActive),
  )
  assert_snapshot(active, session.snapshot())
  let pending = session
    .request_end(session.target().unwrap(), @text_session.ExternalReplacement)
    .unwrap()
  let before = session.snapshot()
  let calls = [0]
  let count = fn(document) {
    calls[0] += 1
    measure(document)
  }
  assert_true(
    session.complete_replacement(
      pending,
      @text_session.Committed("日本"),
      @platform.WindowId::new(1L),
      7UL,
      active.field(),
      count,
      admit,
    )
    is Err(@text_session.CompositionActive),
  )
  assert_eq(calls[0], 0)
  assert_snapshot(before, session.snapshot())
  let receipt = session
    .complete_replacement(
      pending,
      @text_session.Cancelled,
      @platform.WindowId::new(1L),
      7UL,
      initial.field(),
      measure,
      admit,
    )
    .unwrap()
  assert_true(
    receipt.outcomes()[0] is @text_session.SessionOutcome::Cancelled(_),
  )
  assert_true(receipt.outcomes()[1] is @text_session.Rebound(_))
}

///|
test "failed cancellation and replacement resolution retain undo redo and pending state" {
  let original = field("abcd", 3, 1)
  let edited = original.replace_selection("X", measure, admit).unwrap()
  let undone = edited.undo(measure, admit).unwrap()
  let session = @text_session.TextSession::new(
    @platform.WindowId::new(1L),
    7UL,
    undone,
  ).unwrap()
  let _ = apply(session, [preview("日本")])
  let pending = session
    .request_end(session.target().unwrap(), @text_session.ExternalReplacement)
    .unwrap()
  let before = session.snapshot()
  for
    observation in [
      @text_session.ObservedEnd::Committed("日本"),
      @text_session.ObservedEnd::Cancelled,
    ] {
    assert_true(
      session.complete_replacement(
        pending,
        observation,
        @platform.WindowId::new(1L),
        7UL,
        original,
        _ => Err(@text_field.MeasurementFailed),
        admit,
      )
      is Err(@text_session.FieldFailure(@text_field.MeasurementFailed)),
    )
    assert_snapshot(before, session.snapshot())
    assert_true(
      session.complete_replacement(
        pending,
        observation,
        @platform.WindowId::new(1L),
        7UL,
        original,
        measure,
        (_, _) => Err(@text_field.AdmissionFailed),
      )
      is Err(@text_session.FieldFailure(@text_field.AdmissionFailed)),
    )
    assert_snapshot(before, session.snapshot())
  }
  let receipt = session
    .complete_replacement(
      pending,
      @text_session.Cancelled,
      @platform.WindowId::new(1L),
      7UL,
      original,
      measure,
      admit,
    )
    .unwrap()
  match receipt.outcomes()[0] {
    @text_session.SessionOutcome::Cancelled(old) => {
      assert_true(old.document() == undone.document())
      assert_true(old.can_redo())
      assert_true(
        old.redo(measure, admit).unwrap().document() == edited.document(),
      )
    }
    _ => fail("cancel must precede replacement")
  }
}

///|
test "pending completion itself cannot be reentered through provider callbacks" {
  let session = owner()
  let _ = apply(session, [preview("日本")])
  let pending = session
    .request_end(session.target().unwrap(), @text_session.Blur)
    .unwrap()
  let before = session.snapshot()
  let nested = fn(document) {
    if !(session.complete_blur(pending, @text_session.Cancelled, measure, admit)
      is Err(@text_session.Reentrant)) {
      abort("completion reentered")
    }
    measure(document)
  }
  assert_true(
    session.complete_blur(
      pending,
      @text_session.Committed("日本"),
      nested,
      admit,
    )
    is Err(@text_session.Reentrant),
  )
  assert_snapshot(before, session.snapshot())
  let _ = session
    .complete_blur(pending, @text_session.Committed("日本"), measure, admit)
    .unwrap()
}

///|
test "published revision differs from whole field and committed document revisions" {
  let session = owner()
  let initial_field_revision = session.snapshot().field().revision()
  let _ = apply(session, [preview("に"), preview("日本"), preview("")])
  assert_eq(session.snapshot().published_revision(), 1UL)
  assert_eq(session.snapshot().field().revision(), initial_field_revision + 3)
  assert_eq(session.snapshot().committed_document_revision(), 0UL)
  // Same committed text with a new directional selection changes the committed
  // document value, but still uses TextField's no-new-history behavior.
  let _ = apply(session, [@text_session.Commit("bc")])
  assert_eq(session.snapshot().field().document().text(), "abcd")
  assert_eq(session.snapshot().committed_document_revision(), 1UL)
  assert_false(session.snapshot().field().can_undo())
  assert_eq(session.snapshot().published_revision(), 2UL)
  let pending = session
    .request_end(session.target().unwrap(), @text_session.Blur)
    .unwrap()
  assert_eq(session.snapshot().published_revision(), 3UL)
  assert_eq(session.snapshot().delivery_watermark(), 2UL)
  let _ = session
    .complete_blur(pending, @text_session.Cancelled, measure, admit)
    .unwrap()
  assert_eq(session.snapshot().published_revision(), 4UL)
  assert_eq(session.snapshot().committed_document_revision(), 1UL)
  session.rearm().unwrap()
  assert_eq(session.snapshot().published_revision(), 5UL)
  assert_eq(session.snapshot().delivery_watermark(), 3UL)
}

///|
test "terminal close is idempotent across copied handles and preserves the final snapshot" {
  let session = owner()
  let copy = session
  let _ = apply(session, [preview("日本")])
  let pending = session
    .request_end(session.target().unwrap(), @text_session.Blur)
    .unwrap()
  session.close().unwrap()
  let closed = session.snapshot()
  assert_true(closed.is_closed())
  assert_false(closed.has_pending_end())
  assert_true(closed.field().is_composing())
  copy.close().unwrap()
  session.close().unwrap()
  assert_snapshot(closed, session.snapshot())
  assert_snapshot(closed, copy.snapshot())
  assert_true(session.target() is Err(@text_session.Closed))
  assert_true(session.rearm() is Err(@text_session.Closed))
  assert_true(
    session.rebind(@platform.WindowId::new(1L), 7UL, field("new", 3, 3))
    is Err(@text_session.Closed),
  )
  assert_true(
    session.request_end(pending.target(), @text_session.Blur)
    is Err(@text_session.Closed),
  )
  let calls = [0]
  let count = fn(document) {
    calls[0] += 1
    measure(document)
  }
  assert_true(
    session.apply_batch(
      pending.target(),
      [@text_session.Commit("日本")],
      count,
      admit,
    )
    is Err(@text_session.Closed),
  )
  assert_true(
    session.complete_blur(
      pending,
      @text_session.Committed("日本"),
      count,
      admit,
    )
    is Err(@text_session.Closed),
  )
  assert_eq(calls[0], 0)
  assert_snapshot(closed, session.snapshot())
}

///|
/// Characterization: this intentionally demonstrates different history, not
/// a passing undo-compatibility contract for direct keyboard delivery.
test "direct session insert and platform typing currently group undo differently" {
  for (first, second) in [("a", "b"), ("日", "本")] {
    let initial = field("", 0, 0)
    let hit = fn(
      _ : @text.TextDocument,
      _ : @primitives.Point,
    ) -> Result[@text_layout.TextHit, @text_field.TextFieldError] {
      Err(@text_field.HitTestFailed)
    }
    let (typed_a, _) = initial
      .handle_input(@primitives.TextInput(text=first), measure, admit, hit)
      .unwrap()
    let (typed_ab, _) = typed_a
      .handle_input(@primitives.TextInput(text=second), measure, admit, hit)
      .unwrap()
    let session = @text_session.TextSession::new(
      @platform.WindowId::new(1L),
      7UL,
      initial,
    ).unwrap()
    ignore(
      session
      .apply_batch(
        session.target().unwrap(),
        [@text_session.Insert(first)],
        measure,
        admit,
      )
      .unwrap(),
    )
    ignore(
      session
      .apply_batch(
        session.target().unwrap(),
        [@text_session.Insert(second)],
        measure,
        admit,
      )
      .unwrap(),
    )
    let inserted_ab = session.snapshot().field()
    assert_eq(typed_ab.document().text(), first + second)
    assert_eq(inserted_ab.document().text(), first + second)
    let typed_undo = typed_ab.undo(measure, admit).unwrap()
    let insert_undo = inserted_ab.undo(measure, admit).unwrap()
    assert_eq(typed_undo.document().text(), "")
    assert_eq(insert_undo.document().text(), first)
    assert_eq(insert_undo.undo(measure, admit).unwrap().document().text(), "")
    assert_eq(
      typed_undo.redo(measure, admit).unwrap().document().text(),
      first + second,
    )
    assert_eq(
      insert_undo.redo(measure, admit).unwrap().document().text(),
      first + second,
    )
  }
}

///|
test "typed session insert matches platform typing undo and redo grouping" {
  for (first, second) in [("a", "b"), ("日", "本"), ("🙂", "a")] {
    let initial = field("", 0, 0)
    let hit = fn(
      _ : @text.TextDocument,
      _ : @primitives.Point,
    ) -> Result[@text_layout.TextHit, @text_field.TextFieldError] {
      Err(@text_field.HitTestFailed)
    }
    let (typed_a, _) = initial
      .handle_input(@primitives.TextInput(text=first), measure, admit, hit)
      .unwrap()
    let (typed_ab, _) = typed_a
      .handle_input(@primitives.TextInput(text=second), measure, admit, hit)
      .unwrap()
    let session = @text_session.TextSession::new(
      @platform.WindowId::new(1L),
      7UL,
      initial,
    ).unwrap()
    let first_target = session.target().unwrap()
    let first_receipt = session
      .apply_typed_insert(first_target, first, measure, admit)
      .unwrap()
    assert_true(first_receipt.acknowledges(first_target))
    let after_first = session.snapshot()
    assert_true(
      session.apply_typed_insert(first_target, first, measure, admit) is Err(_),
    )
    assert_snapshot(after_first, session.snapshot())
    ignore(
      session
      .apply_typed_insert(session.target().unwrap(), second, measure, admit)
      .unwrap(),
    )
    let result = session.snapshot().field()
    assert_eq(result.document().text(), first + second)
    assert_eq(typed_ab.document().text(), first + second)
    let platform_undo = typed_ab.undo(measure, admit).unwrap()
    let session_undo = result.undo(measure, admit).unwrap()
    assert_eq(platform_undo.document().text(), "")
    assert_eq(session_undo.document().text(), "")
    assert_eq(
      platform_undo.redo(measure, admit).unwrap().document().text(),
      first + second,
    )
    assert_eq(
      session_undo.redo(measure, admit).unwrap().document().text(),
      first + second,
    )
  }
}

///|
test "typed session insert retains navigation boundary established on field" {
  let initial = field("", 0, 0)
  let hit = fn(
    _ : @text.TextDocument,
    _ : @primitives.Point,
  ) -> Result[@text_layout.TextHit, @text_field.TextFieldError] {
    Err(@text_field.HitTestFailed)
  }
  let (typed, _) = initial
    .handle_input(@primitives.TextInput(text="a"), measure, admit, hit)
    .unwrap()
  let (moved, _) = typed
    .handle_input(
      @primitives.KeyPressed(
        key=@primitives.ArrowRight,
        modifiers=@primitives.Modifiers::none(),
        repeat=false,
      ),
      measure,
      admit,
      hit,
    )
    .unwrap()
  let (platform, _) = moved
    .handle_input(@primitives.TextInput(text="b"), measure, admit, hit)
    .unwrap()
  let session = @text_session.TextSession::new(
    @platform.WindowId::new(1L),
    7UL,
    moved,
  ).unwrap()
  ignore(
    session
    .apply_typed_insert(session.target().unwrap(), "b", measure, admit)
    .unwrap(),
  )
  assert_eq(platform.undo(measure, admit).unwrap().document().text(), "a")
  assert_eq(
    session.snapshot().field().undo(measure, admit).unwrap().document().text(),
    "a",
  )
}

///|
test "typed session insert rejects preview pending and failed admission atomically" {
  let composing = owner()
  ignore(apply(composing, [preview("にほん")]))
  let before = composing.snapshot()
  assert_true(
    composing.apply_typed_insert(
      composing.target().unwrap(),
      "日",
      measure,
      admit,
    )
    is Err(@text_session.CompositionActive),
  )
  assert_snapshot(before, composing.snapshot())
  let pending_session = owner()
  let pending = pending_session
    .request_end(pending_session.target().unwrap(), @text_session.Blur)
    .unwrap()
  let pending_before = pending_session.snapshot()
  assert_true(
    pending_session.apply_typed_insert(pending.target(), "日", measure, admit)
    is Err(@text_session.PendingResolution),
  )
  assert_snapshot(pending_before, pending_session.snapshot())
  let fresh = owner()
  let fresh_before = fresh.snapshot()
  let reject = fn(
    _ : @text.TextDocument,
    _ : @text_layout.TextMeasurement,
  ) -> Result[Unit, @text_field.TextFieldError] {
    Err(@text_field.AdmissionFailed)
  }
  assert_true(
    fresh.apply_typed_insert(fresh.target().unwrap(), "日", measure, reject)
    is Err(@text_session.FieldFailure(@text_field.AdmissionFailed)),
  )
  assert_snapshot(fresh_before, fresh.snapshot())
  let target = fresh.target().unwrap()
  let nested = fn(document) {
    assert_reentrant(fresh.close())
    measure(document)
  }
  assert_true(
    fresh.apply_typed_insert(target, "日", nested, admit)
    is Err(@text_session.Reentrant),
  )
  assert_snapshot(fresh_before, fresh.snapshot())
  ignore(fresh.apply_typed_insert(target, "日", measure, admit).unwrap())
}
