///|
fn retained_test_route() -> RetainedOrderedRoute {
  let host : Host = { token: -1, stopped: true, }
  {
    host,
    window: Some(@platform.WindowId::new(51L)),
    root: 9UL,
    portable_epoch: 3UL,
    native_epoch: 7,
    native_seat: 11L,
    native_proxy: 4,
    ordinal: 0L,
    closed: false,
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
  assert_true(route.release_from(3UL, busy) is Err(_))
  assert_true(route.window is Some(_))
  assert_eq(route.native_epoch, 7)
  route.release_from(3UL, empty).unwrap()
  assert_true(route.window is None)
  assert_eq(route.root, 0UL)
  assert_true(route.release_from(3UL, empty) is Err(_))
  assert_true(receipt.finish_ack(fn() { Ok(()) }) is Err(_))
}
