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
test "ordered ingress returns a commit before a later focus event" {
  let host : Host = { token: -1, stopped: true, }
  let route = TextHostRoute::new_ordered(host)
  let queue = route.queue
  route.started = true
  route.native_epoch = 1
  let window = @platform.WindowId::new(1L)
  let epoch = queue.begin(window).unwrap()
  let target : TextSessionTarget = {
    window,
    sequence: 1L,
    epoch: 1,
    seat: 1L,
    proxy_generation: 1,
    serial: 1,
  }
  let pending : Ref[Array[EditorEvent]] = Ref([
    TextSession(target, Commit(text="日本語", deletion=None, position=None)),
    Platform(
      @platform.Event::new(window, 2L, 1.0, @platform.FocusChanged(false)),
    ),
  ])
  let read = fn(_) {
    if pending.val.length() == 0 {
      Ok(None)
    } else {
      Ok(Some(pending.val.remove(0)))
    }
  }
  let absorb = fn(target, event) { route.absorb(target, event) }
  match next_ordered_event_from(queue, 0, read, absorb).unwrap() {
    Some(Text(event)) => {
      assert_eq(event.epoch(), epoch)
      match event.kind() {
        @text_host.Commit(text~) => assert_eq(text, "日本語")
        _ => fail("expected commit")
      }
    }
    _ => fail("commit must precede focus loss")
  }
  match next_ordered_event_from(queue, 0, read, absorb).unwrap() {
    Some(Platform(event)) =>
      assert_true(event.kind() is @platform.FocusChanged(false))
    _ => fail("expected focus loss after commit")
  }
  assert_true(next_ordered_event_from(queue, 0, read, absorb).unwrap() is None)
}

///|
test "ordered ingress does not read text past a platform boundary" {
  let host : Host = { token: -1, stopped: true, }
  let route = TextHostRoute::new_ordered(host)
  let queue = route.queue
  route.started = true
  route.native_epoch = 1
  let window = @platform.WindowId::new(1L)
  ignore(queue.begin(window).unwrap())
  let target : TextSessionTarget = {
    window,
    sequence: 2L,
    epoch: 1,
    seat: 1L,
    proxy_generation: 1,
    serial: 1,
  }
  let pending : Ref[Array[EditorEvent]] = Ref([
    Platform(
      @platform.Event::new(window, 1L, 1.0, @platform.FocusChanged(false)),
    ),
    TextSession(target, Commit(text="late", deletion=None, position=None)),
  ])
  let read = fn(_) {
    if pending.val.length() == 0 {
      Ok(None)
    } else {
      Ok(Some(pending.val.remove(0)))
    }
  }
  let absorb = fn(target, event) { route.absorb(target, event) }
  match next_ordered_event_from(queue, 0, read, absorb).unwrap() {
    Some(Platform(event)) =>
      assert_true(event.kind() is @platform.FocusChanged(false))
    _ => fail("focus event must precede the later text")
  }
  assert_eq(pending.val.length(), 1)
}

///|
test "ordered and legacy polling cannot be mixed" {
  // Invalid native token: every call below must reject before invoking native
  // code, so no display or live host is required.
  let host : Host = { token: -1, stopped: true, }
  let ordered = TextHostRoute::new_ordered(host)
  assert_true(ordered.next_platform_event(timeout_ms=0) is Err(_))
  assert_true(ordered.next_text_input(timeout_ms=0) is Err(_))
}

///|
test "drained end validates portable ownership and pending observations first" {
  // The invalid token ensures any unexpected native invocation fails; the
  // portable busy/stale paths must preserve the route and its queued record.
  let host : Host = { token: -1, stopped: true, }
  let ordered = OrderedTextHostRoute::new(host)
  let route = ordered.route
  let epoch = route.queue.begin(@platform.WindowId::new(1L)).unwrap()
  route.started = true
  route.native_epoch = 1
  route.window = Some(@platform.WindowId::new(1L))
  route.queue.emit(@text_host.Commit(text="日本")).unwrap()
  match ordered.try_end_when_drained(epoch + 1UL) {
    Err(error) => assert_true(error.code() is @diagnostics.StaleHandle)
    _ => fail("foreign epoch must be rejected")
  }
  match ordered.try_end_when_drained(epoch) {
    Err(error) => assert_true(error.code() is @diagnostics.Busy)
    _ => fail("pending portable text must block cutoff")
  }
  assert_true(route.started && route.queue.is_active())
  assert_true(route.queue.take_text() is Some(_))
  route.queue.fail(@diagnostics.UnsupportedCapability)
  match ordered.try_end_when_drained(epoch) {
    Err(error) =>
      assert_true(error.code() is @diagnostics.UnsupportedCapability)
    _ => fail("a previously rejected observation must not be hidden")
  }
  assert_true(route.started && route.queue.is_active())
}

///|
test "ordered ingress rejects unsupported edits and skips a stale epoch" {
  let host : Host = { token: -1, stopped: true, }
  let route = TextHostRoute::new_ordered(host)
  let queue = route.queue
  let window = @platform.WindowId::new(1L)
  ignore(queue.begin(window).unwrap())
  route.started = true
  route.native_epoch = 2
  let stale : TextSessionTarget = {
    window,
    sequence: 1L,
    epoch: 1,
    seat: 1L,
    proxy_generation: 1,
    serial: 1,
  }
  let current = { ..stale, epoch: 2, sequence: 2L, }
  let pending : Ref[Array[EditorEvent]] = Ref([
    TextSession(stale, Commit(text="stale", deletion=None, position=None)),
    TextSession(
      current,
      Commit(
        text="replace",
        deletion=Some({ index_bytes: -1, length_bytes: 1, }),
        position=None,
      ),
    ),
  ])
  let read = fn(_) {
    if pending.val.length() == 0 {
      Ok(None)
    } else {
      Ok(Some(pending.val.remove(0)))
    }
  }
  let absorb = fn(target, event) { route.absorb(target, event) }
  assert_true(next_ordered_event_from(queue, 0, read, absorb) is Err(_))
  assert_eq(pending.val.length(), 0)
  assert_true(queue.take_text() is None)
  assert_true(queue.failure() is Some(@diagnostics.UnsupportedCapability))
}

///|
test "ordered ingress preserves forwarded-key position between commits" {
  let queue = @text_host.TextHostQueue::new()
  let window = @platform.WindowId::new(1L)
  ignore(queue.begin(window).unwrap())
  let target : TextSessionTarget = {
    window,
    sequence: 1L,
    epoch: 1,
    seat: 1L,
    proxy_generation: 1,
    serial: 1,
  }
  let pending : Ref[Array[EditorEvent]] = Ref([
    TextSession(target, Commit(text="a", deletion=None, position=None)),
    TextSession(
      target,
      ForwardedPressed(
        keysym=0xff51,
        key=Some(@primitives.ArrowLeft),
        modifiers=@primitives.Modifiers::none(),
      ),
    ),
    TextSession(target, Commit(text="b", deletion=None, position=None)),
  ])
  let read = fn(_) {
    if pending.val.length() == 0 {
      Ok(None)
    } else {
      Ok(Some(pending.val.remove(0)))
    }
  }
  let absorb = fn(_, event) {
    match translate_editor_event(event) {
      Emit(kind) => queue.emit(kind)
      Forward(key, pressed, modifiers) => {
        let kind = if pressed {
          @platform.Input(
            @primitives.KeyPressed(key~, repeat=false, modifiers~),
          )
        } else {
          @platform.Input(@primitives.KeyReleased(key~, modifiers~))
        }
        if !queue.park(@platform.Event::new(window, 2L, 1.0, kind)) {
          abort("unexpected full test queue")
        }
        Ok(())
      }
      _ => abort("unexpected test event")
    }
  }
  match next_ordered_event_from(queue, 0, read, absorb).unwrap() {
    Some(Text(event)) =>
      assert_true(event.kind() is @text_host.Commit(text="a"))
    _ => fail("expected first commit")
  }
  match next_ordered_event_from(queue, 0, read, absorb).unwrap() {
    Some(Platform(event)) =>
      assert_true(
        event.kind()
        is @platform.Input(
          @primitives.KeyPressed(key=@primitives.ArrowLeft, ..)
        ),
      )
    _ => fail("expected forwarded key")
  }
  match next_ordered_event_from(queue, 0, read, absorb).unwrap() {
    Some(Text(event)) =>
      assert_true(event.kind() is @text_host.Commit(text="b"))
    _ => fail("expected second commit")
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

///|
test "ordered ingress preserves modified shortcut between text observations" {
  let host : Host = { token: -1, stopped: true, }
  let route = TextHostRoute::new_ordered(host)
  let queue = route.queue
  let window = @platform.WindowId::new(1L)
  ignore(queue.begin(window).unwrap())
  let target : TextSessionTarget = {
    window,
    sequence: 1L,
    epoch: 1,
    seat: 1L,
    proxy_generation: 1,
    serial: 1,
  }
  let control = @primitives.Modifiers::new(
    shift=false,
    control=true,
    alt=false,
    meta=false,
  )
  let pending : Ref[Array[EditorEvent]] = Ref([
    TextSession(target, Commit(text="日本", deletion=None, position=None)),
    TextSession(
      target,
      ForwardedPressed(keysym=0x7a, key=None, modifiers=control),
    ),
    TextSession(
      target,
      ForwardedReleased(
        keysym=0x7a,
        key=None,
        modifiers=@primitives.Modifiers::none(),
      ),
    ),
  ])
  let read = fn(_) {
    if pending.val.length() == 0 {
      Ok(None)
    } else {
      Ok(Some(pending.val.remove(0)))
    }
  }
  let absorb = fn(_, event) {
    match route.shortcuts.translate(event) {
      Emit(kind) => queue.emit(kind)
      Forward(key, pressed, modifiers) => {
        let kind = if pressed {
          @platform.Input(
            @primitives.KeyPressed(key~, repeat=false, modifiers~),
          )
        } else {
          @platform.Input(@primitives.KeyReleased(key~, modifiers~))
        }
        if !queue.park(@platform.Event::new(window, 2L, 1.0, kind)) {
          abort("unexpected full test queue")
        }
        Ok(())
      }
      _ => abort("unexpected test event")
    }
  }
  match next_ordered_event_from(queue, 0, read, absorb).unwrap() {
    Some(Text(event)) =>
      assert_true(event.kind() is @text_host.Commit(text="日本"))
    _ => fail("expected commit before shortcut")
  }
  match next_ordered_event_from(queue, 0, read, absorb).unwrap() {
    Some(Platform(event)) =>
      assert_true(
        event.kind()
        is @platform.Input(
          @primitives.KeyPressed(key=@primitives.Character("z"), ..)
        ),
      )
    _ => fail("expected shortcut press")
  }
  match next_ordered_event_from(queue, 0, read, absorb).unwrap() {
    Some(Platform(event)) =>
      assert_true(
        event.kind()
        is @platform.Input(
          @primitives.KeyReleased(key=@primitives.Character("z"), ..)
        ),
      )
    _ => fail("expected matching shortcut release")
  }
}
