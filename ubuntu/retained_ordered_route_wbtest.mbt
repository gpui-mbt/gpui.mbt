///|
fn retained_test_route() -> RetainedOrderedRoute {
  let host : Host = { token: -1, stopped: true, }
  {
    host,
    window: Some(@platform.WindowId::new(51L)),
    root: 9UL,
    portable_epoch: 3UL,
    native_epoch: 7,
    direct_binding: false,
    direct_cutoff_complete: false,
    native_seat: 11L,
    native_proxy: 4,
    ordinal: 0L,
    closed: false,
    pending_geometry: None,
    geometry_generation: 0UL,
    geometry_handoff: None,
    geometry_handoff_call: false,
    shortcuts: ShortcutKeyTracker::new(),
  }
}

///|
fn retained_test_record(
  route : RetainedOrderedRoute,
  sequence : Int32,
  native_epoch : Int32,
  event : TextSessionEvent,
  stale : Bool,
) -> RetainedEditorRecord {
  let window = @platform.WindowId::new(51L)
  let target : TextSessionTarget = {
    window,
    sequence: sequence.to_int64(),
    epoch: native_epoch,
    seat: 11L,
    proxy_generation: 4,
    serial: 1,
  }
  let fields = FixedArray::make(217, 0.0)
  fields[3] = 2.0
  {
    host: route.host,
    window,
    sequence,
    event: Some(TextSession(target, event)),
    raw_fields: fields,
    stale,
    direct_epoch: 0,
    composition_epoch: 0,
    revoked: false,
    direct_origin: false,
  }
}

///|
test "retained ordered candidates hold native sequence and commit ordinal only after ack" {
  let route = retained_test_route()
  let record = retained_test_record(
    route,
    80,
    7,
    Commit(text="日本", deletion=None, position=None),
    false,
  )
  let first = route.prepare(record).unwrap()
  let second = route.prepare(record).unwrap()
  assert_eq(first.native_sequence(), 80)
  assert_eq(first.epoch(), 3UL)
  assert_eq(first.root(), 9UL)
  match first.event() {
    Text(event) => {
      assert_eq(event.sequence(), 1L)
      assert_eq(event.epoch(), 3UL)
    }
    _ => fail("expected retained text")
  }
  match second.event() {
    Text(event) => assert_eq(event.sequence(), 1L)
    _ => fail("expected same candidate")
  }
  assert_eq(route.ordinal, 0L)
  let failed = first.finish_ack(fn() {
    Err(@diagnostics.FrameworkError::new(@diagnostics.Busy, "native_ack"))
  })
  assert_true(failed is Err(_))
  assert_eq(route.ordinal, 0L)
  first.finish_ack(fn() { Ok(()) }).unwrap()
  assert_eq(route.ordinal, 1L)
  let mut called = false
  assert_true(
    second.finish_ack(fn() {
      called = true
      Ok(())
    })
    is Err(_),
  )
  assert_false(called)
  let next = route
    .prepare(
      retained_test_record(
        route,
        84,
        7,
        Preedit(text="に", fallback="", cursor_utf16=Some(1), styles=[]),
        false,
      ),
    )
    .unwrap()
  match next.event() {
    Text(event) => assert_eq(event.sequence(), 2L)
    _ => fail("expected next text ordinal")
  }
  assert_eq(next.native_sequence(), 84)
}

///|
test "retained ordered route preserves stale and unsupported records" {
  let route = retained_test_route()
  let old = route
    .prepare(
      retained_test_record(
        route,
        41,
        6,
        Commit(text="old", deletion=None, position=None),
        false,
      ),
    )
    .unwrap()
  assert_true(old.event() is Unhandled(_))
  let stale = route
    .prepare(
      retained_test_record(
        route,
        42,
        7,
        Commit(text="old", deletion=None, position=None),
        true,
      ),
    )
    .unwrap()
  assert_true(stale.event() is Unhandled(_))
  let deletion = route
    .prepare(
      retained_test_record(
        route,
        43,
        7,
        Commit(
          text="x",
          deletion=Some({ index_bytes: -1, length_bytes: 1, }),
          position=None,
        ),
        false,
      ),
    )
    .unwrap()
  assert_true(deletion.event() is Unhandled(_))
  let position = route
    .prepare(
      retained_test_record(
        route,
        44,
        7,
        Commit(
          text="x",
          deletion=None,
          position=Some({ cursor_index_bytes: 0, anchor_index_bytes: 0, }),
        ),
        false,
      ),
    )
    .unwrap()
  assert_true(position.event() is Unhandled(_))
  assert_eq(route.ordinal, 0L)
  let left = route
    .prepare(retained_test_record(route, 45, 7, Left, false))
    .unwrap()
  assert_true(left.event() is Lifecycle(_, _))
  route.portable_epoch = 4UL
  assert_true(left.finish_ack(fn() { Ok(()) }) is Err(_))
  assert_eq(route.ordinal, 0L)
}

///|
test "retained ordered route leaves shortcut state unchanged on failed ack" {
  let route = retained_test_route()
  let modifiers = @primitives.Modifiers::new(
    control=true,
    alt=false,
    shift=false,
    meta=false,
  )
  let press = retained_test_record(
    route,
    19,
    7,
    ForwardedPressed(
      keysym=0x61,
      key=Some(@primitives.Character("a")),
      modifiers~,
    ),
    false,
  )
  let first = route.prepare(press).unwrap()
  let again = route.prepare(press).unwrap()
  assert_true(first.event() is Platform(_))
  assert_eq(route.shortcuts.held, 0)
  assert_true(
    first.finish_ack(fn() {
      Err(@diagnostics.FrameworkError::new(@diagnostics.Busy, "ack"))
    })
    is Err(_),
  )
  assert_eq(route.shortcuts.held, 0)
  again.finish_ack(fn() { Ok(()) }).unwrap()
  assert_true(route.shortcuts.held != 0)
  assert_true(first.finish_ack(fn() { Ok(()) }) is Err(_))
}

///|
test "retained binding accepts seat and proxy only after entered ACK" {
  let route = retained_test_route()
  route.native_seat = 0L
  route.native_proxy = 0
  let commit = retained_test_record(
    route,
    30,
    7,
    Commit(text="日本", deletion=None, position=None),
    false,
  )
  assert_true(route.prepare(commit).unwrap().event() is Unhandled(_))
  let enter = route
    .prepare(retained_test_record(route, 29, 7, Entered, false))
    .unwrap()
  assert_true(enter.event() is Lifecycle(_, _))
  assert_true(
    enter.finish_ack(fn() {
      Err(@diagnostics.FrameworkError::new(@diagnostics.Busy, "ack"))
    })
    is Err(_),
  )
  assert_eq(route.native_seat, 0L)
  enter.finish_ack(fn() { Ok(()) }).unwrap()
  assert_eq(route.native_seat, 11L)
  assert_eq(route.native_proxy, 4)
  assert_true(route.prepare(commit).unwrap().event() is Text(_))
  let other_target : TextSessionTarget = {
    window: @platform.WindowId::new(51L),
    sequence: 31L,
    epoch: 7,
    seat: 11L,
    proxy_generation: 5,
    serial: 1,
  }
  let fields = FixedArray::make(217, 0.0)
  let wrong : RetainedEditorRecord = {
    host: route.host,
    window: other_target.window,
    sequence: 31,
    event: Some(
      TextSession(
        other_target,
        Commit(text="old", deletion=None, position=None),
      ),
    ),
    raw_fields: fields,
    stale: false,
    direct_epoch: 0,
    composition_epoch: 0,
    revoked: false,
    direct_origin: false,
  }
  assert_true(route.prepare(wrong).unwrap().event() is Unhandled(_))
}

///|
test "retained cutoff and release preserve binding on busy and reject old receipts" {
  let route = retained_test_route()
  let receipt = route
    .prepare(retained_test_record(route, 20, 7, Left, false))
    .unwrap()
  let mut cutoff_calls = 0
  let busy = fn() {
    Err(@diagnostics.FrameworkError::new(@diagnostics.Busy, "fifo"))
  }
  let empty = fn() { Ok(()) }
  let mut observed_window = 0L
  let mut observed_epoch = 0
  let cutoff = fn(window : @platform.WindowId, epoch : Int32) {
    observed_window = window.value()
    observed_epoch = epoch
    cutoff_calls += 1
    Ok(())
  }
  assert_true(route.end_from(3UL, busy, cutoff) is Err(_))
  assert_eq(cutoff_calls, 0)
  assert_false(route.closed)
  route.end_from(3UL, empty, cutoff).unwrap()
  assert_true(route.closed)
  assert_eq(cutoff_calls, 1)
  assert_eq(observed_window, 51L)
  assert_eq(observed_epoch, 7)
  assert_true(route.release_from(3UL, busy, empty) is Err(_))
  assert_true(route.release_from(3UL, empty, busy) is Err(_))
  assert_true(route.window is Some(_))
  assert_eq(route.native_epoch, 7)
  route.release_from(3UL, empty, empty).unwrap()
  assert_true(route.window is None)
  assert_eq(route.root, 0UL)
  assert_true(route.release_from(3UL, empty, empty) is Err(_))
  assert_true(receipt.finish_ack(fn() { Ok(()) }) is Err(_))
}

///|
test "foreign window platform records remain unhandled" {
  let route = retained_test_route()
  let window = @platform.WindowId::new(52L)
  let event = @platform.Event::new(
    window,
    12L,
    1.0,
    @platform.FocusChanged(false),
  )
  let fields = FixedArray::make(217, 0.0)
  let record : RetainedEditorRecord = {
    host: route.host,
    window,
    sequence: 12,
    event: Some(Platform(event)),
    raw_fields: fields,
    stale: false,
    direct_epoch: 0,
    composition_epoch: 0,
    revoked: false,
    direct_origin: false,
  }
  assert_true(route.prepare(record).unwrap().event() is Unhandled(_))
  assert_eq(route.ordinal, 0L)
}

///|
test "printable release candidate preserves exact owner and requires ACK" {
  let route = retained_test_route()
  let release = retained_test_record(
    route,
    11,
    7,
    ForwardedReleased(
      keysym=0x6e,
      key=None,
      modifiers=@primitives.Modifiers::none(),
    ),
    false,
  )
  let receipt = route.prepare(release).unwrap()
  assert_true(receipt.event() is Unhandled(_))
  let candidate = receipt.printable_release_candidate().unwrap()
  assert_eq(candidate.keysym, 0x6e)
  assert_eq(candidate.target.sequence, 11L)
  assert_eq(candidate.target.epoch, 7)
  assert_eq(candidate.target.seat, 11L)
  assert_eq(candidate.target.proxy_generation, 4)
  assert_eq(receipt.native_sequence(), 11)
  assert_eq(receipt.epoch(), 3UL)
  assert_eq(receipt.root(), 9UL)
  assert_eq(route.ordinal, 0L)
  assert_true(
    receipt.finish_ack(fn() {
      Err(@diagnostics.FrameworkError::new(@diagnostics.Busy, "ack"))
    })
    is Err(_),
  )
  assert_eq(route.ordinal, 0L)
  assert_eq(
    route
    .prepare(release)
    .unwrap()
    .printable_release_candidate()
    .unwrap()
    .keysym(),
    0x6e,
  )
  let mut acked = false
  let ack = fn() {
    if acked {
      Err(@diagnostics.FrameworkError::new(@diagnostics.StaleHandle, "ack"))
    } else {
      acked = true
      Ok(())
    }
  }
  receipt.finish_ack(ack).unwrap()
  assert_true(receipt.finish_ack(ack) is Err(_))
  assert_eq(route.ordinal, 0L)
  route.root = 10UL
  assert_true(receipt.finish_ack(fn() { Ok(()) }) is Err(_))
}

///|
test "printable candidate rejects stale foreign modified or unsupported input" {
  let route = retained_test_route()
  let plain = @primitives.Modifiers::none()
  let control = @primitives.Modifiers::new(
    control=true,
    alt=false,
    shift=false,
    meta=false,
  )
  let cases = [
    retained_test_record(
      route,
      12,
      7,
      ForwardedReleased(keysym=0x6e, key=None, modifiers=plain),
      true,
    ),
    retained_test_record(
      route,
      13,
      6,
      ForwardedReleased(keysym=0x6e, key=None, modifiers=plain),
      false,
    ),
    retained_test_record(
      route,
      14,
      7,
      ForwardedReleased(keysym=0x6e, key=None, modifiers=control),
      false,
    ),
    retained_test_record(
      route,
      15,
      7,
      ForwardedPressed(keysym=0x6e, key=None, modifiers=plain),
      false,
    ),
    retained_test_record(
      route,
      16,
      7,
      ForwardedReleased(keysym=0xffe1, key=None, modifiers=plain),
      false,
    ),
    retained_test_record(
      route,
      17,
      7,
      Commit(
        text="x",
        deletion=Some({ index_bytes: -1, length_bytes: 1, }),
        position=None,
      ),
      false,
    ),
  ]
  for record in cases {
    let result = route.prepare(record).unwrap()
    assert_true(result.event() is Unhandled(_))
    assert_true(result.printable_release_candidate() is None)
  }
  let original = retained_test_record(
    route,
    18,
    7,
    ForwardedReleased(keysym=0x6e, key=None, modifiers=plain),
    false,
  )
  let target = match original.event {
    Some(TextSession(value, _)) => value
    _ => fail("expected native text-session record")
  }
  let wrong_seat = { ..target, seat: 12L, }
  let wrong_proxy = { ..target, proxy_generation: 5, }
  for target in [wrong_seat, wrong_proxy] {
    let wrong = {
      ..original,
      event: Some(
        TextSession(
          target,
          ForwardedReleased(keysym=0x6e, key=None, modifiers=plain),
        ),
      ),
    }
    assert_true(
      route.prepare(wrong).unwrap().printable_release_candidate() is None,
    )
  }
}

///|
test "observed native sequence eleven remains an explicit release candidate" {
  let route = retained_test_route()
  route.portable_epoch = 1UL
  route.native_epoch = 1
  route.native_seat = 14L
  route.native_proxy = 1
  let plain = @primitives.Modifiers::none()
  let release = ForwardedReleased(keysym=110, key=None, modifiers=plain)
  let original = retained_test_record(route, 11, 1, release, false)
  let target = match original.event {
    Some(TextSession(value, _)) => { ..value, seat: 14L, proxy_generation: 1, }
    _ => fail("expected native text-session record")
  }
  let record = { ..original, event: Some(TextSession(target, release)), }
  let receipt = route.prepare(record).unwrap()
  let candidate = receipt.printable_release_candidate().unwrap()
  assert_eq(candidate.target().sequence, 11L)
  assert_eq(candidate.target().epoch, 1)
  assert_eq(candidate.target().seat, 14L)
  assert_eq(candidate.target().proxy_generation, 1)
  assert_eq(candidate.keysym(), 110)
  assert_true(receipt.event() is Unhandled(_))
  assert_eq(route.ordinal, 0L)
}

///|
test "candidate ACK rechecks stale native evidence before consuming head" {
  let route = retained_test_route()
  let receipt = route
    .prepare(
      retained_test_record(
        route,
        11,
        7,
        ForwardedReleased(
          keysym=0x6e,
          key=None,
          modifiers=@primitives.Modifiers::none(),
        ),
        false,
      ),
    )
    .unwrap()
  assert_true(receipt.printable_release_candidate() is Some(_))
  let mut consumed = false
  let native_ack = fn() {
    consumed = true
    Ok(())
  }
  let stale = fn() {
    Err(@diagnostics.FrameworkError::new(@diagnostics.StaleHandle, "focus"))
  }
  assert_true(receipt.ack_from(stale, native_ack) is Err(_))
  assert_false(consumed)
  assert_eq(route.ordinal, 0L)
  assert_eq(route.root, 9UL)
  receipt.ack_from(fn() { Ok(()) }, native_ack).unwrap()
  assert_true(consumed)
}

///|
test "physical evidence decodes host-local window history without inventing owners" {
  let route = retained_test_route()
  let record = retained_test_record(
    route,
    11,
    7,
    ForwardedReleased(
      keysym=0x6e,
      key=None,
      modifiers=@primitives.Modifiers::none(),
    ),
    false,
  )
  let candidate = route
    .prepare(record)
    .unwrap()
    .printable_release_candidate()
    .unwrap()
  let fields = FixedArray::make(8, 0)
  fields[0] = 1
  fields[1] = 49
  fields[2] = 1
  fields[3] = 1
  fields[6] = 1
  fields[7] = 1
  let value = decode_physical_release(candidate, fields, "fixture").unwrap()
  assert_eq(value.physical_key(), 49)
  assert_eq(value.focus_generation(), 1)
  assert_true(value.prior() is NoPressObservedSinceFocus)
  assert_eq(value.host_window_generation(), Some(1))
  assert_true(value.claim_before_any_window())
  fields[6] = 0
  let unknown_window = decode_physical_release(candidate, fields, "fixture").unwrap()
  assert_true(unknown_window.host_window_generation() is None)
  fields[7] = 2
  assert_true(decode_physical_release(candidate, fields, "fixture") is Err(_))
  fields[7] = 1
  fields[3] = 2
  fields[4] = 11
  fields[5] = 51
  assert_true(decode_physical_release(candidate, fields, "fixture") is Err(_))
  fields[4] = 5
  fields[5] = 52
  assert_true(decode_physical_release(candidate, fields, "fixture") is Err(_))
  fields[5] = 51
  let prior = decode_physical_release(candidate, fields, "fixture").unwrap()
  assert_true(prior.prior() is PressAdmitted(5, _))
}

///|
test "direct retained candidates keep original epoch and reject foreign origin" {
  let route = retained_test_route()
  route.direct_binding = true
  let window = @platform.WindowId::new(51L)
  let event = @platform.Event::new(
    window,
    21L,
    1.0,
    @platform.Input(@primitives.TextInput(text="a")),
  )
  let fields = FixedArray::make(217, 0.0)
  let record : RetainedEditorRecord = {
    host: route.host,
    window,
    sequence: 21,
    event: Some(Platform(event)),
    raw_fields: fields,
    stale: false,
    direct_epoch: 7,
    composition_epoch: 0,
    revoked: false,
    direct_origin: true,
  }
  let accepted = route.prepare(record).unwrap()
  assert_true(accepted.event() is Unhandled(_))
  assert_eq(accepted.direct_insert().unwrap().text(), "a")
  assert_eq(accepted.root(), 9UL)
  assert_eq(accepted.epoch(), 3UL)
  assert_eq(accepted.native_sequence(), 21)
  assert_true(
    route.prepare({ ..record, direct_epoch: 8, }).unwrap().event()
    is Unhandled(_),
  )
  assert_true(
    route.prepare({ ..record, direct_origin: false, }).unwrap().event()
    is Unhandled(_),
  )
  assert_true(
    route.prepare({ ..record, stale: true, }).unwrap().event() is Unhandled(_),
  )
  let other = @platform.WindowId::new(52L)
  let other_event = @platform.Event::new(
    other,
    21L,
    1.0,
    @platform.Input(@primitives.TextInput(text="a")),
  )
  assert_true(
    route
    .prepare({ ..record, window: other, event: Some(Platform(other_event)), })
    .unwrap()
    .event()
    is Unhandled(_),
  )
  let failed = accepted.finish_ack(fn() {
    Err(@diagnostics.FrameworkError::new(@diagnostics.Busy, "native_ack"))
  })
  assert_true(failed is Err(_))
  assert_true(route.window is Some(_))
  assert_true(accepted.finish_ack(fn() { Ok(()) }) is Ok(_))
}
