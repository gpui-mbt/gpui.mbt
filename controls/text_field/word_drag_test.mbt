///|
fn word_test_field(text : String) -> @text_field.TextField raise {
  field_test_focused(
    field_test_create(text, field_test_rect(0.0, 0.0, 200.0, 28.0)),
  )
}

///|
fn word_test_alt(shift : Bool) -> @primitives.Modifiers {
  @primitives.Modifiers::new(shift~, control=false, alt=true, meta=false)
}

///|
fn word_test_ctrl(shift : Bool) -> @primitives.Modifiers {
  @primitives.Modifiers::new(shift~, control=true, alt=false, meta=false)
}

///|
fn word_test_point(
  field : @text_field.TextField,
  offset : Int32,
) -> @primitives.Point {
  @primitives.Point::new(
    field.content_bounds().left() + offset.to_double() * 8.0,
    12.0,
  ).unwrap()
}

///|
test "option word navigation moves between word boundaries" {
  let field = word_test_field("hello world")
  assert_eq(field.selection().head(), 0)
  let (right, _) = field_test_key(
    field,
    @primitives.ArrowRight,
    word_test_alt(false),
  )
  assert_eq(right.selection().head(), 5)
  let (right2, _) = field_test_key(
    right,
    @primitives.ArrowRight,
    word_test_alt(false),
  )
  assert_eq(right2.selection().head(), 11)
  let (right_end, _) = field_test_key(
    right2,
    @primitives.ArrowRight,
    word_test_alt(false),
  )
  assert_eq(right_end.selection().head(), 11)
  let (left, _) = field_test_key(
    right_end,
    @primitives.ArrowLeft,
    word_test_alt(false),
  )
  assert_eq(left.selection().head(), 6)
  let (left2, _) = field_test_key(
    left,
    @primitives.ArrowLeft,
    word_test_alt(false),
  )
  assert_eq(left2.selection().head(), 0)
}

///|
test "shift option extends and collapses word selections" {
  let field = word_test_field("hello world")
  let (extended, _) = field_test_key(
    field,
    @primitives.ArrowRight,
    word_test_alt(true),
  )
  assert_eq(extended.selection().anchor(), 0)
  assert_eq(extended.selection().head(), 5)
  let (extended_more, _) = field_test_key(
    extended,
    @primitives.ArrowRight,
    word_test_alt(true),
  )
  assert_eq(extended_more.selection().anchor(), 0)
  assert_eq(extended_more.selection().head(), 11)
  let (collapsed, _) = field_test_key(
    extended_more,
    @primitives.ArrowRight,
    word_test_alt(false),
  )
  assert_true(collapsed.selection().is_collapsed())
  assert_eq(collapsed.selection().head(), 11)
}

///|
test "ctrl word navigation works for Windows and Linux style chords" {
  let field = word_test_field("hello world")
  let (right, _) = field_test_key(
    field,
    @primitives.ArrowRight,
    word_test_ctrl(false),
  )
  assert_eq(right.selection().head(), 5)
  let (right2, _) = field_test_key(
    right,
    @primitives.ArrowRight,
    word_test_ctrl(false),
  )
  assert_eq(right2.selection().head(), 11)
}

///|
test "word deletion removes a word and keeps the history group" {
  let field = word_test_field("hello world")
  let (at_end, _) = field_test_key(
    field,
    @primitives.End,
    @primitives.Modifiers::none(),
  )
  assert_eq(at_end.selection().head(), 11)
  let (after_backspace, _) = field_test_key(
    at_end,
    @primitives.Backspace,
    word_test_alt(false),
  )
  assert_eq(after_backspace.document().text(), "hello ")
  assert_eq(after_backspace.selection().head(), 6)
  let after_undo = match
    after_backspace.undo(field_test_measure, field_test_admit) {
    Ok(value) => value
    Err(_) => fail("word deletion should be undoable")
  }
  assert_eq(after_undo.document().text(), "hello world")

  let (at_start, _) = field_test_key(
    field,
    @primitives.Home,
    @primitives.Modifiers::none(),
  )
  let (after_delete, _) = field_test_key(
    at_start,
    @primitives.Delete,
    word_test_alt(false),
  )
  assert_eq(after_delete.document().text(), " world")
  assert_eq(after_delete.selection().head(), 0)
}

///|
test "word deletion handles CJK word runs" {
  let field = word_test_field("日本語、テスト")
  let (at_end, _) = field_test_key(
    field,
    @primitives.End,
    @primitives.Modifiers::none(),
  )
  assert_eq(at_end.selection().head(), 7)
  let (after_backspace, _) = field_test_key(
    at_end,
    @primitives.Backspace,
    word_test_alt(false),
  )
  assert_eq(after_backspace.document().text(), "日本語、")
  assert_eq(after_backspace.selection().head(), 4)
}

///|
test "pointer drag extends the selection and release ends it" {
  let field = word_test_field("abcdef")
  let press = field_test_event(
      field,
      @primitives.PointerButtonPressed(
        position=word_test_point(field, 1),
        button=@primitives.Primary,
        modifiers=@primitives.Modifiers::none(),
      ),
    ).0
  assert_eq(press.selection().head(), 1)
  let dragged = field_test_event(
      press,
      @primitives.PointerMoved(position=word_test_point(press, 4)),
    ).0
  assert_eq(dragged.selection().anchor(), 1)
  assert_eq(dragged.selection().head(), 4)
  let released = field_test_event(
      dragged,
      @primitives.PointerButtonReleased(
        position=word_test_point(dragged, 4),
        button=@primitives.Primary,
        modifiers=@primitives.Modifiers::none(),
      ),
    ).0
  let hover = field_test_event(
      released,
      @primitives.PointerMoved(position=word_test_point(released, 5)),
    ).0
  assert_eq(hover.selection().anchor(), 1)
  assert_eq(hover.selection().head(), 4)
}

///|
test "hover without a pressed primary button does not select" {
  let field = word_test_field("abcdef")
  let (moved, _) = field_test_event(
    field,
    @primitives.PointerMoved(position=word_test_point(field, 3)),
  )
  assert_eq(moved.selection().head(), 0)
  assert_true(moved.selection().is_collapsed())
}

///|
test "double click selects a word and triple click selects all" {
  let field = word_test_field("hello world")
  let double = field_test_event(
      field,
      @primitives.PointerButtonMultiClick(
        position=word_test_point(field, 8),
        button=@primitives.Primary,
        modifiers=@primitives.Modifiers::none(),
        click_count=2,
      ),
    ).0
  assert_eq(double.selection().anchor(), 6)
  assert_eq(double.selection().head(), 11)
  let triple = field_test_event(
      double,
      @primitives.PointerButtonMultiClick(
        position=word_test_point(double, 8),
        button=@primitives.Primary,
        modifiers=@primitives.Modifiers::none(),
        click_count=3,
      ),
    ).0
  assert_eq(triple.selection().anchor(), 0)
  assert_eq(triple.selection().head(), 11)
}

///|
test "shift double click extends the existing selection" {
  let field = word_test_field("hello world")
  let (first, _) = field_test_key(
    field,
    @primitives.ArrowRight,
    @primitives.Modifiers::new(shift=true, control=false, alt=false, meta=false),
  )
  let (selected, _) = field_test_key(
    first,
    @primitives.ArrowRight,
    @primitives.Modifiers::new(shift=true, control=false, alt=false, meta=false),
  )
  assert_eq(selected.selection().anchor(), 0)
  assert_eq(selected.selection().head(), 2)
  let extended = field_test_event(
      selected,
      @primitives.PointerButtonMultiClick(
        position=word_test_point(selected, 8),
        button=@primitives.Primary,
        modifiers=@primitives.Modifiers::new(
          shift=true,
          control=false,
          alt=false,
          meta=false,
        ),
        click_count=2,
      ),
    ).0
  assert_eq(extended.selection().anchor(), 0)
  assert_eq(extended.selection().head(), 11)
}

///|
test "double click selects a CJK word run" {
  let field = word_test_field("日本語 テスト")
  let double = field_test_event(
      field,
      @primitives.PointerButtonMultiClick(
        position=word_test_point(field, 1),
        button=@primitives.Primary,
        modifiers=@primitives.Modifiers::none(),
        click_count=2,
      ),
    ).0
  assert_eq(double.selection().anchor(), 0)
  assert_eq(double.selection().head(), 3)
  let second = field_test_event(
      double,
      @primitives.PointerButtonMultiClick(
        position=word_test_point(double, 6),
        button=@primitives.Primary,
        modifiers=@primitives.Modifiers::none(),
        click_count=2,
      ),
    ).0
  assert_eq(second.selection().anchor(), 4)
  assert_eq(second.selection().head(), 7)
}

///|
test "drag beyond the field clamps to the nearest end" {
  let field = word_test_field("abcdef")
  let press = field_test_event(
      field,
      @primitives.PointerButtonPressed(
        position=word_test_point(field, 2),
        button=@primitives.Primary,
        modifiers=@primitives.Modifiers::none(),
      ),
    ).0
  let far_right = @primitives.Point::new(field.bounds().right() + 40.0, 12.0).unwrap()
  let dragged = field_test_event(
      press,
      @primitives.PointerMoved(position=far_right),
    ).0
  assert_eq(dragged.selection().anchor(), 2)
  assert_eq(dragged.selection().head(), 6)
}
