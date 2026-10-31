///|
test "uncertain geometry retains one exact commit until retry and transfer" {
  let route = retained_test_route()
  let candidate = retained_geometry_test_state("old", 2.0)
  assert_true(
    route.update_from(3UL, candidate, fn() { Ok(()) }, fn(_, _, _) {
      Err(
        @diagnostics.FrameworkError::new(@diagnostics.NativeFailure, "fixture"),
      )
    })
    is Err(_),
  )
  let record = retained_test_record(
    route,
    21,
    7,
    Commit(text="日本", deletion=None, position=None),
    false,
  )
  let receipt = route.prepare(record).unwrap()
  let mut ack_calls = 0
  let mut reentrant_rejected = false
  let mut inflight_unknown = false
  assert_true(
    route.handoff_geometry_from(receipt, fn() { Ok(Some(record)) }, fn(_) {
      ack_calls += 1
      inflight_unknown = route.geometry_handoff_in_progress() &&
        route.reserved_geometry_text() is None &&
        route.owned_geometry_text() is None
      reentrant_rejected = route.handoff_geometry_from(
          receipt,
          fn() { Ok(Some(record)) },
          fn(_) { Ok(()) },
        )
        is Err(_)
      Err(@diagnostics.FrameworkError::new(@diagnostics.Busy, "fixture"))
    })
    is Err(_),
  )
  assert_true(reentrant_rejected)
  assert_true(inflight_unknown)
  assert_eq(ack_calls, 1)
  assert_eq(route.ordinal, 0L)
  assert_true(route.reserved_geometry_text() is Some(_))
  assert_true(route.owned_geometry_text() is None)
  assert_true(
    route.retry_geometry_from(3UL, fn() { Ok(()) }, fn(_, _, _) { Ok(7) })
    is Err(_),
  )
  assert_true(route.take_owned_geometry_text(3UL) is Err(_))
  assert_true(
    route.handoff_geometry_from(receipt, fn() { Ok(Some(record)) }, fn(_) {
      ack_calls += 1
      Ok(())
    })
    is Ok(_),
  )
  assert_eq(ack_calls, 2)
  assert_eq(route.ordinal, 1L)
  assert_true(route.reserved_geometry_text() is None)
  let owned = route.owned_geometry_text().unwrap()
  assert_eq(owned.native_sequence(), 21)
  assert_eq(owned.window().value(), 51L)
  assert_eq(owned.root(), 9UL)
  assert_eq(owned.epoch(), 3UL)
  assert_eq(owned.native_epoch(), 7)
  assert_eq(owned.geometry_generation(), 1UL)
  assert_true(
    owned.native_text() is Commit(text="日本", deletion=None, position=None),
  )
  assert_true(owned.event().kind() is @text_host.Commit(text="日本"))
  route.closed = true
  assert_true(
    route.retry_geometry_from(3UL, fn() { Ok(()) }, fn(_, _, _) { Ok(7) })
    is Err(_),
  )
  assert_true(route.take_owned_geometry_text(3UL) is Err(_))
  assert_true(route.owned_geometry_text() is Some(_))
  route.closed = false
  let second = retained_test_record(
    route,
    22,
    7,
    Commit(text="次", deletion=None, position=None),
    false,
  )
  let second_receipt = route.prepare(second).unwrap()
  assert_true(
    route.handoff_geometry_from(second_receipt, fn() { Ok(Some(second)) }, fn(
      _,
    ) {
      ack_calls += 1
      Ok(())
    })
    is Err(_),
  )
  assert_eq(ack_calls, 2)
  assert_true(route.take_owned_geometry_text(3UL) is Err(_))
  assert_true(
    route.retry_geometry_from(
      3UL,
      fn() {
        Err(
          @diagnostics.FrameworkError::new(@diagnostics.Busy, "fifo not empty"),
        )
      },
      fn(_, _, _) { Ok(7) },
    )
    is Err(_),
  )
  assert_true(
    route.retry_geometry_from(3UL, fn() { Ok(()) }, fn(_, _, state) {
      if state.document().text() == "old" {
        Ok(7)
      } else {
        Err(
          @diagnostics.FrameworkError::new(
            @diagnostics.InvalidInput,
            "wrong candidate",
          ),
        )
      }
    })
    is Ok(_),
  )
  let moved = route.take_owned_geometry_text(3UL).unwrap()
  assert_true(moved.event().kind() is @text_host.Commit(text="日本"))
  assert_true(route.take_owned_geometry_text(3UL) is Err(_))
  assert_eq(route.ordinal, 1L)
}

///|
test "geometry text handoff leaves unknown, stale, and foreign records native" {
  let route = retained_test_route()
  let candidate = retained_geometry_test_state("old", 2.0)
  assert_true(
    route.update_from(3UL, candidate, fn() { Ok(()) }, fn(_, _, _) {
      Err(
        @diagnostics.FrameworkError::new(@diagnostics.NativeFailure, "fixture"),
      )
    })
    is Err(_),
  )
  let lifecycle = retained_test_record(route, 21, 7, Entered, false)
  let life_receipt = route.prepare(lifecycle).unwrap()
  let mut ack_calls = 0
  assert_true(
    route.handoff_geometry_from(life_receipt, fn() { Ok(Some(lifecycle)) }, fn(
      _,
    ) {
      ack_calls += 1
      Ok(())
    })
    is Err(_),
  )
  let unknown = { ..lifecycle, event: None, }
  let unknown_receipt = route.prepare(unknown).unwrap()
  assert_true(
    route.handoff_geometry_from(unknown_receipt, fn() { Ok(Some(unknown)) }, fn(
      _,
    ) {
      ack_calls += 1
      Ok(())
    })
    is Err(_),
  )
  let valid = retained_test_record(
    route,
    22,
    7,
    Commit(text="日本", deletion=None, position=None),
    false,
  )
  let valid_receipt = route.prepare(valid).unwrap()
  assert_true(
    route.handoff_geometry_from(
      valid_receipt,
      fn() { Ok(Some({ ..valid, stale: true, })) },
      fn(_) {
        ack_calls += 1
        Ok(())
      },
    )
    is Err(_),
  )
  let foreign = retained_test_record(
    route,
    22,
    8,
    Commit(text="日本", deletion=None, position=None),
    false,
  )
  assert_true(
    route.handoff_geometry_from(valid_receipt, fn() { Ok(Some(foreign)) }, fn(
      _,
    ) {
      ack_calls += 1
      Ok(())
    })
    is Err(_),
  )
  route.closed = true
  assert_true(
    route.handoff_geometry_from(valid_receipt, fn() { Ok(Some(valid)) }, fn(_) {
      ack_calls += 1
      Ok(())
    })
    is Err(_),
  )
  route.closed = false
  assert_eq(ack_calls, 0)
  assert_true(route.reserved_geometry_text() is None)
  assert_true(route.owned_geometry_text() is None)
}

///|
test "geometry preedit source payload is isolated from caller mutation" {
  let route = retained_test_route()
  let candidate = retained_geometry_test_state("old", 2.0)
  assert_true(
    route.update_from(3UL, candidate, fn() { Ok(()) }, fn(_, _, _) {
      Err(
        @diagnostics.FrameworkError::new(@diagnostics.NativeFailure, "fixture"),
      )
    })
    is Err(_),
  )
  let record = retained_test_record(
    route,
    21,
    7,
    Preedit(text="に", fallback="ni", cursor_utf16=Some(1), styles=[]),
    false,
  )
  let receipt = route.prepare(record).unwrap()
  route
  .handoff_geometry_from(receipt, fn() { Ok(Some(record)) }, fn(_) { Ok(()) })
  .unwrap()
  let owned = route.owned_geometry_text().unwrap()
  match owned.native_text() {
    Preedit(fallback~, styles~, ..) => {
      assert_eq(fallback, "ni")
      styles.push({ range: @text.TextRange::new(0, 1).unwrap(), style: 1, })
    }
    _ => fail("source preedit was not retained")
  }
  match owned.native_text() {
    Preedit(styles~, ..) => assert_eq(styles.length(), 0)
    _ => fail("source preedit was not retained")
  }
  assert_true(owned.event().kind() is @text_host.Preedit(text="に", cursor=1))
}
