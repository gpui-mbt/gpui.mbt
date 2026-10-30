///|
fn remeasure_test_measure(
  document : @text.TextDocument,
) -> Result[@text_layout.TextMeasurement, TextFieldError] {
  let carets = []
  let length = document.utf16_length()
  for offset in 0..<=length {
    let bounds = @primitives.Rect::new(
      offset.to_double() * 10.0,
      0.0,
      0.0,
      20.0,
    ).unwrap()
    carets.push(
      @text_layout.CaretGeometry::new(offset, true, bounds, bounds).unwrap(),
    )
  }
  let bounds = @primitives.Rect::new(0.0, 0.0, length.to_double() * 10.0, 20.0).unwrap()
  match
    @text_layout.TextMeasurement::new(
      document, bounds, bounds, 15.0, 1, 0, carets,
    ) {
    Ok(value) => Ok(value)
    Err(_) => Err(MeasurementFailed)
  }
}

///|
test "remeasure keeps preview and rollback under the new environment" {
  let admit = fn(_, _) { Ok(()) }
  let start = composition_private_field()
  let edited = start
    .replace_selection("X", undo_revision_measure, admit)
    .unwrap()
  let original = edited.undo(undo_revision_measure, admit).unwrap()
  let preview = original
    .update_composition_utf8("PRE", 3, 3, undo_revision_measure, admit)
    .unwrap()
  let bounds = @primitives.Rect::new(4.0, 5.0, 180.0, 48.0).unwrap()
  let measured : Array[String] = []
  let measure = fn(document : @text.TextDocument) {
    measured.push(document.text())
    remeasure_test_measure(document)
  }
  let next = preview.remeasure(bounds, 18.0, measure, admit).unwrap()
  assert_eq(measured.length(), 2)
  assert_eq(measured[0], preview.document().text())
  assert_eq(measured[1], original.document().text())
  assert_true(next.is_composing())
  assert_true(next.document() == preview.document())
  assert_true(next.committed_document() == original.document())
  assert_eq(next.font_size(), 18.0)
  assert_true(next.bounds() == bounds)
  assert_eq(next.measurement().logical_rect().size().height(), 20.0)
  assert_eq(
    next.composition.unwrap().measurement.logical_rect().size().height(),
    20.0,
  )
  assert_eq(next.revision(), preview.revision() + 1)
  // Explicit observed cancellation resolves the preview; resize itself does not.
  let restored = next.cancel_composition(remeasure_test_measure, admit).unwrap()
  assert_true(restored.document() == original.document())
  assert_eq(restored.measurement().logical_rect().size().height(), 20.0)
  assert_true(restored.can_redo())
  let redone = restored.redo(remeasure_test_measure, admit).unwrap()
  assert_true(redone.document() == edited.document())
  let committed = next
    .commit_composition("日本", remeasure_test_measure, admit)
    .unwrap()
  assert_true(
    committed.undo(remeasure_test_measure, admit).unwrap().document() ==
    original.document(),
  )
}

///|
test "remeasure failure retains original composition and history" {
  let admit = fn(_, _) { Ok(()) }
  let preview = composition_private_field()
    .update_composition_utf8("PRE", 3, 3, undo_revision_measure, admit)
    .unwrap()
  let snapshot = undo_field_snapshot(preview)
  let bounds = @primitives.Rect::new(4.0, 5.0, 180.0, 48.0).unwrap()
  let calls = [0]
  let fail_second = fn(document) {
    calls[0] += 1
    if calls[0] == 2 {
      Err(MeasurementFailed)
    } else {
      remeasure_test_measure(document)
    }
  }
  assert_true(
    preview.remeasure(bounds, 18.0, fail_second, admit)
    is Err(MeasurementFailed),
  )
  let admissions = [0]
  let reject_second = fn(_, _) {
    admissions[0] += 1
    if admissions[0] == 2 {
      Err(AdmissionFailed)
    } else {
      Ok(())
    }
  }
  assert_true(
    preview.remeasure(bounds, 18.0, remeasure_test_measure, reject_second)
    is Err(AdmissionFailed),
  )
  let validation_calls = [0]
  let invalid_original = fn(document : @text.TextDocument) {
    validation_calls[0] += 1
    if validation_calls[0] == 2 {
      undo_measure_without_cursor_stop(document, 1)
    } else {
      remeasure_test_measure(document)
    }
  }
  assert_true(
    preview.remeasure(bounds, 18.0, invalid_original, admit)
    is Err(InvalidSelection),
  )
  composition_assert_same_snapshot(snapshot, preview)
  let committed = preview
    .commit_composition("日本", undo_revision_measure, admit)
    .unwrap()
  assert_true(
    committed.undo(undo_revision_measure, admit).unwrap().document() ==
    preview.committed_document(),
  )
}

///|
test "remeasure validates before admission and preserves a plain field" {
  let field = composition_private_field()
  let bounds = @primitives.Rect::new(0.0, 0.0, 180.0, 48.0).unwrap()
  let calls = [0]
  let counted = fn(_, _) {
    calls[0] += 1
    Ok(())
  }
  assert_true(
    field.remeasure(bounds, 0.0, remeasure_test_measure, counted)
    is Err(InvalidFontSize),
  )
  let narrow = @primitives.Rect::new(0.0, 0.0, 180.0, 12.0).unwrap()
  assert_true(
    field.remeasure(narrow, 18.0, remeasure_test_measure, counted)
    is Err(InvalidBounds),
  )
  let exhausted = { ..field, revision: @int.MAX_VALUE, }
  assert_true(
    exhausted.remeasure(bounds, 18.0, remeasure_test_measure, counted)
    is Err(RevisionExhausted),
  )
  assert_eq(calls[0], 0)
  let next = field
    .remeasure(bounds, 18.0, remeasure_test_measure, counted)
    .unwrap()
  assert_eq(calls[0], 1)
  assert_true(next.document() == field.document())
  assert_false(next.is_composing())
  assert_eq(next.measurement().logical_rect().size().height(), 20.0)
}
