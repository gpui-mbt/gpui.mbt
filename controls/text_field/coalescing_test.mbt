///|
test "adjacent typing coalesces until selection movement and a no-op cursor move" {
  let start = field_test_focused(
    field_test_selection(
      field_test_create("", field_test_rect(0.0, 0.0, 100.0, 28.0)),
      0,
      0,
    ),
  )
  let a = field_test_text(start, "a").0
  let ab = field_test_text(a, "b").0
  assert_eq(ab.document().text(), "ab")

  let left = field_test_key(
      ab,
      @primitives.ArrowLeft,
      @primitives.Modifiers::none(),
    ).0
  let right = field_test_key(
      left,
      @primitives.ArrowRight,
      @primitives.Modifiers::none(),
    ).0
  assert_eq(right.selection().head(), 2)
  let abc = field_test_text(right, "c").0
  assert_eq(field_test_undo(abc).document().text(), "ab")
  assert_eq(field_test_undo(field_test_undo(abc)).document().text(), "")

  let one = field_test_text(start, "a").0
  let at_end = field_test_key(
      one,
      @primitives.ArrowRight,
      @primitives.Modifiers::none(),
    ).0
  assert_true(at_end.document() == one.document())
  assert_eq(at_end.revision(), one.revision() + 1)
  let two = field_test_text(at_end, "b").0
  assert_eq(field_test_undo(two).document().text(), "a")
  assert_eq(field_test_undo(field_test_undo(two)).document().text(), "")
}

///|
test "pointer placement at the current caret closes the open run" {
  let start = field_test_focused(
    field_test_selection(
      field_test_create("", field_test_rect(0.0, 0.0, 120.0, 28.0)),
      0,
      0,
    ),
  )
  let a = field_test_text(start, "a").0
  let point = @primitives.Point::new(40.0, 14.0).unwrap()
  let (clicked, action) = a
    .handle_input(
      @primitives.PointerButtonPressed(
        position=point,
        button=@primitives.Primary,
        modifiers=@primitives.Modifiers::none(),
      ),
      field_test_measure,
      field_test_admit,
      fn(document, _point) {
        let head = document.selection().head()
        match @text_layout.TextHit::new(document, head, 0, head, true, true) {
          Ok(value) => Ok(value)
          Err(_) => Err(@text_field.HitTestFailed)
        }
      },
    )
    .unwrap()
  assert_true(action is None)
  assert_true(clicked.document() == a.document())
  assert_eq(clicked.revision(), a.revision() + 1)
  let ab = field_test_text(clicked, "b").0
  assert_eq(field_test_undo(ab).document().text(), "a")
  assert_eq(field_test_undo(field_test_undo(ab)).document().text(), "")
}

///|
test "a snapped Unicode insertion stays a standalone history group" {
  let start = field_test_focused(
    field_test_selection(
      field_test_create("a", field_test_rect(0.0, 0.0, 120.0, 28.0)),
      0,
      0,
    ),
  )
  let snapped = field_test_text(start, "\u{301}").0
  assert_eq(snapped.document().text(), "\u{301}a")
  assert_eq(snapped.selection().head(), 2)
  let appended = field_test_text(snapped, "b").0
  assert_eq(appended.document().text(), "\u{301}ab")
  assert_eq(field_test_undo(appended).document().text(), "\u{301}a")
  assert_eq(field_test_undo(field_test_undo(appended)).document().text(), "a")
}

///|
test "backspace and forward delete coalesce separately at collapsed carets" {
  let backspace_start = field_test_focused(
    field_test_selection(
      field_test_create("abcd", field_test_rect(0.0, 0.0, 120.0, 28.0)),
      4,
      4,
    ),
  )
  let after_backspace_one = field_test_key(
      backspace_start,
      @primitives.Backspace,
      @primitives.Modifiers::none(),
    ).0
  let after_backspace_two = field_test_key(
      after_backspace_one,
      @primitives.Backspace,
      @primitives.Modifiers::none(),
    ).0
  assert_eq(after_backspace_two.document().text(), "ab")
  assert_eq(field_test_undo(after_backspace_two).document().text(), "abcd")

  let forward_start = field_test_focused(
    field_test_selection(
      field_test_create("abcd", field_test_rect(0.0, 0.0, 120.0, 28.0)),
      1,
      1,
    ),
  )
  let after_forward_one = field_test_key(
      forward_start,
      @primitives.Delete,
      @primitives.Modifiers::none(),
    ).0
  let after_forward_two = field_test_key(
      after_forward_one,
      @primitives.Delete,
      @primitives.Modifiers::none(),
    ).0
  assert_eq(after_forward_two.document().text(), "ad")
  assert_eq(field_test_undo(after_forward_two).document().text(), "abcd")

  // Changing direction at the same caret starts a separate group.
  let switch_start = field_test_focused(
    field_test_selection(
      field_test_create("abcd", field_test_rect(0.0, 0.0, 120.0, 28.0)),
      2,
      2,
    ),
  )
  let after_backward = field_test_key(
      switch_start,
      @primitives.Backspace,
      @primitives.Modifiers::none(),
    ).0
  let switched = field_test_key(
      after_backward,
      @primitives.Delete,
      @primitives.Modifiers::none(),
    ).0
  assert_eq(switched.document().text(), "ad")
  assert_eq(field_test_undo(switched).document().text(), "acd")
  assert_eq(field_test_undo(field_test_undo(switched)).document().text(), "abcd")
}

///|
test "replacement paste and equal-content replacement are history boundaries" {
  let start = field_test_focused(
    field_test_selection(
      field_test_create("", field_test_rect(0.0, 0.0, 120.0, 28.0)),
      0,
      0,
    ),
  )
  let a = field_test_text(start, "a").0
  let replaced = a
    .replace_selection("x", field_test_measure, field_test_admit)
    .unwrap()
  let typed_after_paste = field_test_text(replaced, "b").0
  assert_eq(typed_after_paste.document().text(), "axb")
  assert_eq(field_test_undo(typed_after_paste).document().text(), "ax")
  assert_eq(field_test_undo(field_test_undo(typed_after_paste)).document().text(), "a")
  assert_eq(
    field_test_undo(
      field_test_undo(field_test_undo(typed_after_paste)),
    ).document().text(),
    "",
  )

  // An accepted empty replacement is equal-content, but explicitly closes
  // the current run while preserving its retained entry.
  let empty_replacement = a
    .replace_selection("", field_test_measure, field_test_admit)
    .unwrap()
  assert_true(empty_replacement.document() == a.document())
  assert_eq(empty_replacement.revision(), a.revision() + 1)
  let after_empty_replacement = field_test_text(empty_replacement, "b").0
  assert_eq(field_test_undo(after_empty_replacement).document().text(), "a")
  assert_eq(
    field_test_undo(field_test_undo(after_empty_replacement)).document().text(),
    "",
  )

  let same = field_test_key(
      a,
      @primitives.ArrowLeft,
      @primitives.Modifiers::new(
        shift=true,
        control=false,
        alt=false,
        meta=false,
      ),
    ).0
  let unchanged = same
    .replace_selection("a", field_test_measure, field_test_admit)
    .unwrap()
  assert_eq(unchanged.document().text(), "a")
  assert_true(unchanged.can_undo())
  let appended = field_test_text(unchanged, "b").0
  assert_eq(field_test_undo(appended).document().text(), "a")
  assert_eq(field_test_undo(field_test_undo(appended)).document().text(), "")
}

///|
test "focus composition commit and cancel close prior typing runs" {
  let start = field_test_focused(
    field_test_selection(
      field_test_create("", field_test_rect(0.0, 0.0, 120.0, 28.0)),
      0,
      0,
    ),
  )
  let a = field_test_text(start, "a").0
  let blurred = a.with_focus(false).unwrap()
  let refocused = blurred.with_focus(true).unwrap()
  let ab = field_test_text(refocused, "b").0
  assert_eq(field_test_undo(ab).document().text(), "a")
  assert_eq(field_test_undo(field_test_undo(ab)).document().text(), "")

  let composition_start = field_test_text(start, "a").0
  let preview = field_test_preedit(composition_start, "x", 1, 1)
  let committed = preview
    .commit_composition("y", field_test_measure, field_test_admit)
    .unwrap()
  let after_commit = field_test_text(committed, "z").0
  assert_eq(after_commit.document().text(), "ayz")
  assert_eq(field_test_undo(after_commit).document().text(), "ay")
  assert_eq(field_test_undo(field_test_undo(after_commit)).document().text(), "a")
  assert_eq(field_test_undo(field_test_undo(field_test_undo(after_commit))).document().text(), "")

  let cancelled = field_test_preedit(composition_start, "x", 1, 1)
    .cancel_composition(field_test_measure, field_test_admit)
    .unwrap()
  let after_cancel = field_test_text(cancelled, "b").0
  assert_eq(field_test_undo(after_cancel).document().text(), "a")
  assert_eq(field_test_undo(field_test_undo(after_cancel)).document().text(), "")
}

///|
test "undo redo and new branches never reopen a previous coalescing run" {
  let start = field_test_focused(
    field_test_selection(
      field_test_create("", field_test_rect(0.0, 0.0, 120.0, 28.0)),
      0,
      0,
    ),
  )
  let a = field_test_text(start, "a").0
  let ab = field_test_text(a, "b").0
  let undone = field_test_undo(ab)
  assert_eq(undone.document().text(), "")
  let branch = field_test_text(undone, "x").0
  assert_false(branch.can_redo())
  let branch_xy = field_test_text(branch, "y").0
  assert_eq(field_test_undo(branch_xy).document().text(), "")

  let redone = field_test_redo(undone)
  assert_eq(redone.document().text(), "ab")
  let after_redo = field_test_text(redone, "c").0
  assert_eq(field_test_undo(after_redo).document().text(), "ab")
  assert_eq(field_test_undo(field_test_undo(after_redo)).document().text(), "")
}

///|
test "empty redo preserves the run while successful undo closes it" {
  let start = field_test_focused(
    field_test_selection(
      field_test_create("", field_test_rect(0.0, 0.0, 120.0, 28.0)),
      0,
      0,
    ),
  )
  let a = field_test_text(start, "a").0
  let empty_redo = field_test_redo(a)
  let ab = field_test_text(empty_redo, "b").0
  assert_eq(field_test_undo(ab).document().text(), "")

  let successful_undo = field_test_undo(a)
  assert_eq(successful_undo.document().text(), "")
  let branched = field_test_text(successful_undo, "c").0
  let c = field_test_text(branched, "d").0
  assert_eq(field_test_undo(c).document().text(), "")
  assert_false(c.can_redo())
}

///|
test "failed typing edit leaves the prior run available for a later commit" {
  let start = field_test_focused(
    field_test_selection(
      field_test_create("", field_test_rect(0.0, 0.0, 120.0, 28.0)),
      0,
      0,
    ),
  )
  let a = field_test_text(start, "a").0
  let failed = a.handle_input(
    @primitives.TextInput(text="b"),
    _ => Err(@text_field.MeasurementFailed),
    field_test_admit,
    field_test_hit,
  )
  assert_true(failed is Err(@text_field.MeasurementFailed))
  let ac = field_test_text(a, "c").0
  assert_eq(ac.document().text(), "ac")
  assert_eq(field_test_undo(ac).document().text(), "")
}
