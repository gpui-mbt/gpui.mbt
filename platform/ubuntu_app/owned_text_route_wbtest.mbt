///|
fn measure(
  document : @text.TextDocument,
) -> Result[@text_layout.TextMeasurement, @text_field.TextFieldError] {
  let rect = fn(x : Double, width : Double) {
    @primitives.Rect::new(x, 0.0, width, 16.0).unwrap()
  }
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
fn owner() -> @text_session.TextSession {
  let field = @text_field.TextField::new(
      19UL,
      @primitives.Rect::new(0.0, 0.0, 100.0, 36.0).unwrap(),
      10.0,
      @text.TextDocument::new("").unwrap(),
      measure,
      admit,
    )
    .unwrap()
    .with_focus(true)
    .unwrap()
  @text_session.TextSession::new(@platform.WindowId::new(51L), 9UL, field).unwrap()
}

///|
test "only original owner explicitly resolved blur authorizes release" {
  let original = owner()
  let binding = original.target().unwrap()
  let foreign = owner()
  let foreign_pending = foreign
    .request_end(foreign.target().unwrap(), @text_session.Blur)
    .unwrap()
  let foreign_resolution = foreign
    .complete_blur_if_uncomposed(foreign_pending)
    .unwrap()
  assert_false(valid_resolution(original, binding, foreign_resolution))
  let _ = original
    .apply_batch(
      original.target().unwrap(),
      [@text_session.Preview("に", @text.TextSelection::new(1, 1).unwrap())],
      measure,
      admit,
    )
    .unwrap()
  let pending = original
    .request_end(original.target().unwrap(), @text_session.Blur)
    .unwrap()
  assert_true(original.complete_blur_if_uncomposed(pending) is Err(_))
  assert_false(valid_resolution(original, binding, foreign_resolution))
  let resolution = original
    .complete_blur_by_owner_discard(pending, measure, admit)
    .unwrap()
  assert_true(valid_resolution(original, binding, resolution))
  assert_false(valid_resolution(foreign, foreign.target().unwrap(), resolution))
  original.rearm().unwrap()
  assert_false(valid_resolution(original, binding, resolution))
}

///|
test "a text commit receipt is not a completed blur" {
  let session = owner()
  let binding = session.target().unwrap()
  let _ = session
    .apply_batch(
      session.target().unwrap(),
      [@text_session.Preview("に", @text.TextSelection::new(1, 1).unwrap())],
      measure,
      admit,
    )
    .unwrap()
  let commit = session
    .apply_batch(
      session.target().unwrap(),
      [@text_session.Commit("日本")],
      measure,
      admit,
    )
    .unwrap()
  assert_eq(commit.snapshot().field().committed_document().text(), "日本")
  assert_false(valid_resolution(session, binding, commit))
  let pending = session
    .request_end(session.target().unwrap(), @text_session.Blur)
    .unwrap()
  let blur = session.complete_blur_if_uncomposed(pending).unwrap()
  assert_true(valid_resolution(session, binding, blur))
  assert_eq(blur.snapshot().field().committed_document().text(), "日本")
}
