///|
test "intent survives FIFO Busy, transfers one original commit and retries same candidate" {
  let route = retained_test_route()
  route.host.stopped = false
  let state = retained_geometry_test_state("", 5.0)
  let intent = route
    .reserve_geometry_intent_from(3UL, state, fn(_, _) { true })
    .unwrap()
  assert_true(
    route.geometry_intent_stage(intent) is Some(GeometryIntentNotSubmitted),
  )
  let calls = Ref(0)
  assert_true(
    route.submit_geometry_intent_from(
      intent,
      fn() { true },
      fn() { Err(@diagnostics.FrameworkError::new(@diagnostics.Busy, "fifo")) },
      fn(_, _, _) {
        calls.val += 1
        Ok(7)
      },
    )
    is Err(_),
  )
  assert_eq(calls.val, 0)
  assert_true(
    route.geometry_intent_stage(intent) is Some(GeometryIntentNotSubmitted),
  )
  assert_true(route.retry_geometry(3UL) is Err(_))
  let record = retained_test_record(
    route,
    21,
    7,
    Commit(text="日本", deletion=None, position=None),
    false,
  )
  let receipt = route.prepare(record).unwrap()
  route
  .handoff_geometry_from(receipt, fn() { Ok(Some(record)) }, fn(_) { Ok(()) })
  .unwrap()
  let owned = route.owned_geometry_text().unwrap()
  assert_eq(owned.native_sequence(), 21)
  assert_eq(owned.event().sequence(), 1L)
  assert_true(
    owned.native_text() is Commit(text="日本", deletion=None, position=None),
  )
  assert_true(
    route.submit_geometry_intent_from(intent, fn() { true }, fn() { Ok(()) }, fn(
      _,
      _,
      candidate,
    ) {
      calls.val += 1
      if candidate.document().text() != "" {
        return Err(
          @diagnostics.FrameworkError::new(
            @diagnostics.InvalidInput,
            "candidate_changed",
          ),
        )
      }
      Err(
        @diagnostics.FrameworkError::new(
          @diagnostics.NativeFailure,
          "after_native",
        ),
      )
    })
    is Err(_),
  )
  assert_eq(calls.val, 1)
  assert_true(
    route.geometry_intent_stage(intent) is Some(GeometryIntentOutcomeUncertain),
  )
  assert_true(route.owned_geometry_text() is Some(_))
  let accepted = route
    .submit_geometry_intent_from(intent, fn() { true }, fn() { Ok(()) }, fn(
      _,
      _,
      _,
    ) {
      calls.val += 1
      Ok(7)
    })
    .unwrap()
  assert_eq(calls.val, 2)
  assert_eq(accepted.pending().generation(), intent.pending().generation())
  assert_true(route.geometry_intent_stage(intent) is None)
  assert_true(route.owned_geometry_text() is Some(_))
  assert_true(
    route.submit_geometry_intent_from(intent, fn() { true }, fn() { Ok(()) }, fn(
      _,
      _,
      _,
    ) {
      calls.val += 1
      Ok(7)
    })
    is Err(_),
  )
  assert_eq(calls.val, 2)
  let transferred = route.take_owned_geometry_text(3UL).unwrap()
  assert_eq(transferred.native_sequence(), 21)
}

///|
test "intent refuses foreign route, owner changes and reentry" {
  let route = retained_test_route()
  route.host.stopped = false
  let state = retained_geometry_test_state("x", 2.0)
  let reentry_blocked = Ref(false)
  let intent = route
    .reserve_geometry_intent_from(3UL, state, fn(_, _) {
      reentry_blocked.val = route.reserve_geometry_intent_from(3UL, state, fn(
          _,
          _,
        ) {
          true
        })
        is Err(_)
      true
    })
    .unwrap()
  assert_true(reentry_blocked.val)
  let foreign = retained_test_route()
  foreign.host.stopped = false
  let calls = Ref(0)
  assert_true(
    foreign.submit_geometry_intent_from(
      intent,
      fn() { true },
      fn() { Ok(()) },
      fn(_, _, _) {
        calls.val += 1
        Ok(7)
      },
    )
    is Err(_),
  )
  assert_true(
    route.submit_geometry_intent_from(
      intent,
      fn() {
        route.root = 10UL
        true
      },
      fn() { Ok(()) },
      fn(_, _, _) {
        calls.val += 1
        Ok(7)
      },
    )
    is Err(_),
  )
  assert_eq(calls.val, 0)
  assert_true(route.pending_geometry() is Some(_))
  assert_true(route.geometry_intent_stage(intent) is None)
}

///|
test "intent submission hides in-progress stage and blocks reentrant handoff" {
  let route = retained_test_route()
  route.host.stopped = false
  let state = retained_geometry_test_state("x", 2.0)
  let intent = route
    .reserve_geometry_intent_from(3UL, state, fn(_, _) { true })
    .unwrap()
  let record = retained_test_record(
    route,
    21,
    7,
    Commit(text="日本", deletion=None, position=None),
    false,
  )
  let receipt = route.prepare(record).unwrap()
  let reentry_blocked = Ref(false)
  let hidden = Ref(false)
  assert_true(
    route.submit_geometry_intent_from(intent, fn() { true }, fn() { Ok(()) }, fn(
      _,
      _,
      _,
    ) {
      hidden.val = route.geometry_intent_stage(intent) is None
      reentry_blocked.val = route.handoff_geometry_from(
          receipt,
          fn() { Ok(Some(record)) },
          fn(_) { Ok(()) },
        )
        is Err(_)
      Err(
        @diagnostics.FrameworkError::new(@diagnostics.NativeFailure, "fixture"),
      )
    })
    is Err(_),
  )
  assert_true(hidden.val && reentry_blocked.val)
  assert_true(
    route.geometry_intent_stage(intent) is Some(GeometryIntentOutcomeUncertain),
  )
  assert_true(route.owned_geometry_text() is None)
}

///|
test "intent reservation errors install nothing and a current owner may retry" {
  let route = retained_test_route()
  route.host.stopped = false
  let state = retained_geometry_test_state("x", 2.0)
  let initial_generation = route.geometry_generation
  assert_true(
    route.reserve_geometry_intent_from(4UL, state, fn(_, _) { true }) is Err(_),
  )
  assert_true(route.pending_geometry() is None)
  assert_eq(route.geometry_generation, initial_generation)
  assert_true(
    route.reserve_geometry_intent_from(3UL, state, fn(_, _) { false }) is Err(_),
  )
  assert_true(route.pending_geometry() is None)
  assert_eq(route.geometry_generation, initial_generation)
  let intent = route
    .reserve_geometry_intent_from(3UL, state, fn(_, _) { true })
    .unwrap()
  assert_true(
    route.geometry_intent_stage(intent) is Some(GeometryIntentNotSubmitted),
  )
  assert_eq(intent.pending().generation(), initial_generation + 1UL)
}
