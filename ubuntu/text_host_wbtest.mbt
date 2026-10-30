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

///|
test "Ubuntu text route admits only modified shortcut keysyms and pairs releases" {
  let held = ShortcutKeyTracker::new()
  let plain = @primitives.Modifiers::none()
  let control = @primitives.Modifiers::new(
    shift=false,
    control=true,
    alt=false,
    meta=false,
  )
  for symbol in [0x7a, 0x5a] {
    match
      held.translate(ForwardedPressed(keysym=symbol, key=None, modifiers=plain)) {
      Skip => ()
      _ => fail("plain z must not synthesize text or a key")
    }
  }
  match
    held.translate(ForwardedPressed(keysym=0x62, key=None, modifiers=control)) {
    Skip => ()
    _ => fail("non-allowlisted modified characters must remain unmapped")
  }
  match
    held.translate(ForwardedPressed(keysym=0x7a, key=None, modifiers=control)) {
    Forward(@primitives.Character("z"), true, modifiers) =>
      assert_true(modifiers.control())
    _ => fail("Ctrl+Z must reach the portable command path")
  }
  match
    held.translate(ForwardedReleased(keysym=0x7a, key=None, modifiers=plain)) {
    Forward(@primitives.Character("z"), false, _) => ()
    _ => fail("modifier release must not orphan the acquired key")
  }
  match
    held.translate(ForwardedReleased(keysym=0x7a, key=None, modifiers=plain)) {
    Skip => ()
    _ => fail("an orphan release must not revive a shortcut")
  }
  match held.translate(Commit(text="日本", deletion=None, position=None)) {
    Emit(@text_host.Commit(text~)) => assert_eq(text, "日本")
    _ => fail("an IME commit must remain one text observation")
  }
  for
    (symbol, value) in [
      (0x41, "a"),
      (0x63, "c"),
      (0x58, "x"),
      (0x76, "v"),
      (0x5a, "z"),
      (0x79, "y"),
    ] {
    match
      held.translate(
        ForwardedPressed(keysym=symbol, key=None, modifiers=control),
      ) {
      Forward(@primitives.Character(key), true, _) => assert_eq(key, value)
      _ => fail("allowlisted command was not forwarded")
    }
    // Session cancellation/replacement revokes all pending acquisitions.
    held.held = 0
    match
      held.translate(
        ForwardedReleased(keysym=symbol, key=None, modifiers=plain),
      ) {
      Skip => ()
      _ => fail("revoked shortcut release must not be delivered")
    }
  }
}
