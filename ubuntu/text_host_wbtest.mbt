///|
test "ubuntu portable translation keeps preedit, insert, cancel and keys" {
  match
    translate_editor_event(
      Preedit(text="にほん", fallback="", cursor_utf16=Some(3), styles=[]),
    ) {
    Emit(@text_host.Preedit(text~, cursor~)) => {
      assert_eq(text, "にほん")
      assert_eq(cursor, 3)
    }
    _ => fail("expected a preedit translation")
  }
  match
    translate_editor_event(
      Preedit(text="に", fallback="", cursor_utf16=None, styles=[]),
    ) {
    Emit(@text_host.Preedit(cursor~, ..)) => assert_eq(cursor, -1)
    _ => fail("expected a hidden-cursor preedit")
  }
  match
    translate_editor_event(
      Commit(text="日本語", deletion=None, position=None),
    ) {
    Emit(@text_host.Commit(text~)) => assert_eq(text, "日本語")
    _ => fail("expected an insertion commit")
  }
  match
    translate_editor_event(
      Commit(
        text="日本",
        deletion=Some({ index_bytes: 0, length_bytes: 0, }),
        position=None,
      ),
    ) {
    Emit(@text_host.Commit(_)) => ()
    _ => fail("an empty deletion is still an insertion")
  }
  match
    translate_editor_event(
      Commit(
        text="日本",
        deletion=Some({ index_bytes: -3, length_bytes: 3, }),
        position=None,
      ),
    ) {
    Unsupported => ()
    _ => fail("deleting surrounding text must not flatten to an insertion")
  }
  match translate_editor_event(Entered) {
    Skip => ()
    _ => fail("Entered is protocol focus, not an observation")
  }
  match translate_editor_event(Left) {
    Skip => ()
    _ => fail("Left is a protocol fence, not an observation")
  }
  match
    translate_editor_event(
      ForwardedPressed(
        keysym=0xff51,
        key=Some(@primitives.ArrowLeft),
        modifiers=@primitives.Modifiers::none(),
      ),
    ) {
    Forward(@primitives.ArrowLeft, true, _) => ()
    _ => fail("expected a forwarded ArrowLeft press")
  }
  match
    translate_editor_event(
      ForwardedReleased(
        keysym=0xffff,
        key=None,
        modifiers=@primitives.Modifiers::none(),
      ),
    ) {
    Skip => ()
    _ => fail("an unmapped forwarded key has no portable event")
  }
}
