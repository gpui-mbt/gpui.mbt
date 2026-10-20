///|
test "windows portable translation keeps preedit, insert, cancel and skips lifecycle" {
  let empty = @text.TextRange::new(0, 0).unwrap()
  match
    translate_editor_event(
      Marked(
        text="にほん",
        cursor_utf16=Some(3),
        attributes=[0],
        replacement_range=empty,
      ),
    ) {
    Emit(@text_host.Preedit(text~, cursor~)) => {
      assert_eq(text, "にほん")
      assert_eq(cursor, 3)
    }
    _ => fail("expected a preedit translation")
  }
  match
    translate_editor_event(
      Marked(
        text="に",
        cursor_utf16=None,
        attributes=[],
        replacement_range=empty,
      ),
    ) {
    Emit(@text_host.Preedit(cursor~, ..)) => assert_eq(cursor, -1)
    _ => fail("expected a hidden-cursor preedit")
  }
  match
    translate_editor_event(Inserted(text="日本語", replacement_range=empty)) {
    Emit(@text_host.Commit(text~)) => assert_eq(text, "日本語")
    _ => fail("expected an insertion commit")
  }
  let replaced = @text.TextRange::new(1, 2).unwrap()
  match
    translate_editor_event(Inserted(text="日本", replacement_range=replaced)) {
    Unsupported => ()
    _ => fail("replacement insert must not flatten to an insertion")
  }
  match translate_editor_event(Cancelled) {
    Emit(@text_host.Cancel) => ()
    _ => fail("expected a cancel translation")
  }
  match translate_editor_event(CompositionStarted(replacement_range=empty)) {
    Skip => ()
    _ => fail("composition start is not an observation")
  }
  match translate_editor_event(CompositionEnded) {
    Skip => ()
    _ => fail("composition end is not an observation")
  }
}
