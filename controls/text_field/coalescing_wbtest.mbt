///|
fn coalescing_wb_admit(
  document : @text.TextDocument,
  measurement : @text_layout.TextMeasurement,
) -> Result[Unit, TextFieldError] {
  if measurement.document() == document {
    Ok(())
  } else {
    Err(AdmissionFailed)
  }
}

///|
fn coalescing_wb_hit(
  document : @text.TextDocument,
  _point : @primitives.Point,
) -> Result[@text_layout.TextHit, TextFieldError] {
  let head = document.selection().head()
  match @text_layout.TextHit::new(document, head, 0, head, true, true) {
    Ok(value) => Ok(value)
    Err(_) => Err(HitTestFailed)
  }
}

///|
fn coalescing_wb_field() -> TextField {
  TextField::new(
      781UL,
      @primitives.Rect::new(0.0, 0.0, 120.0, 28.0).unwrap(),
      10.0,
      @text.TextDocument::new("").unwrap(),
      undo_revision_measure,
      coalescing_wb_admit,
    )
    .unwrap()
    .with_focus(true)
    .unwrap()
}

///|
fn coalescing_wb_event(
  field : TextField,
  event : @primitives.InputEvent,
) -> Result[(TextField, TextFieldAction?), TextFieldError] {
  field.handle_input(
    event,
    undo_revision_measure,
    coalescing_wb_admit,
    coalescing_wb_hit,
  )
}

///|
test "no-op cursor boundary revisions only when closing a private run" {
  let first = coalescing_wb_event(
      coalescing_wb_field(),
      @primitives.TextInput(text="a"),
    )
    .unwrap()
    .0
  let second = coalescing_wb_event(
      first,
      @primitives.TextInput(text="b"),
    )
    .unwrap()
    .0
  assert_true(second.history.open_group == Some(Typing))
  assert_eq(second.history.undo.length(), 1)
  assert_eq(second.history.payload_bytes, 2)

  let at_end = coalescing_wb_event(
      second,
      @primitives.KeyPressed(
        key=@primitives.ArrowRight,
        modifiers=@primitives.Modifiers::none(),
        repeat=false,
      ),
    )
    .unwrap()
    .0
  assert_true(at_end.document == second.document)
  assert_true(at_end.history.open_group is None)
  assert_eq(at_end.revision, second.revision + 1)
  assert_eq(at_end.history.payload_bytes, second.history.payload_bytes)
  assert_true(second.history.open_group == Some(Typing))

  let no_open_group = coalescing_wb_event(
      at_end,
      @primitives.KeyPressed(
        key=@primitives.ArrowRight,
        modifiers=@primitives.Modifiers::none(),
        repeat=false,
      ),
    )
    .unwrap()
    .0
  assert_true(no_open_group.document == at_end.document)
  assert_eq(no_open_group.revision, at_end.revision)
}

///|
test "revision exhaustion preserves the run for a retryable boundary" {
  let first = coalescing_wb_event(
      coalescing_wb_field(),
      @primitives.TextInput(text="a"),
    )
    .unwrap()
    .0
  let exhausted = { ..first, revision: @int.MAX_VALUE, }
  let blocked = coalescing_wb_event(
    exhausted,
    @primitives.KeyPressed(
      key=@primitives.ArrowRight,
      modifiers=@primitives.Modifiers::none(),
      repeat=false,
    ),
  )
  assert_true(blocked is Err(RevisionExhausted))
  assert_true(exhausted.history.open_group == Some(Typing))
  assert_eq(exhausted.history.undo.length(), first.history.undo.length())
  assert_eq(exhausted.history.payload_bytes, first.history.payload_bytes)

  let retryable = { ..exhausted, revision: first.revision, }
  let appended = coalescing_wb_event(
      retryable,
      @primitives.TextInput(text="b"),
    )
    .unwrap()
    .0
  assert_eq(appended.document.text(), "ab")
  assert_eq(appended.history.undo.length(), 1)
  assert_true(appended.history.open_group == Some(Typing))
  assert_eq(appended.history.payload_bytes, 2)
  assert_eq(
    appended
      .undo(undo_revision_measure, coalescing_wb_admit)
      .unwrap()
      .document.text(),
    "",
  )
}
