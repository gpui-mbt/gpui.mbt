///|
test "preflight Busy yields same-route one-shot retry receipt without native call" {
  let route = retained_test_route()
  route.host.stopped = false
  let state = retained_geometry_test_state("日本", 5.0)
  let calls = Ref(0)
  let outcome = route.attempt_geometry_from(
    3UL,
    state,
    fn() { Err(@diagnostics.FrameworkError::new(@diagnostics.Busy, "fixture")) },
    fn(_, _, _) {
      calls.val += 1
      Ok(7)
    },
  )
  let proof = match outcome {
    GeometryPreflightRejected(_, value) => value
    _ => fail("preflight Busy must be distinguished")
  }
  assert_eq(calls.val, 0)
  assert_true(route.pending_geometry() is None)
  let exact = Ref(false)
  let retried = route.retry_preflight_geometry_from(
    proof,
    fn() { true },
    fn() { Ok(()) },
    fn(window, epoch, candidate) {
      calls.val += 1
      exact.val = window.value() == 51L &&
        epoch == 7 &&
        candidate.document() == state.document() &&
        candidate.caret() == state.caret()
      Ok(7)
    },
  )
  assert_true(retried is GeometryAccepted(_))
  assert_true(exact.val)
  assert_eq(calls.val, 1)
  assert_true(
    route.retry_preflight_geometry_from(proof, fn() { true }, fn() { Ok(()) }, fn(
      _,
      _,
      _,
    ) {
      calls.val += 1
      Ok(7)
    })
    is GeometryOutcomeUncertain(_),
  )
  assert_eq(calls.val, 1)
}

///|
test "preflight proof rejects foreign route, native epoch change and later attempt" {
  let route = retained_test_route()
  route.host.stopped = false
  let state = retained_geometry_test_state("x", 2.0)
  let proof = match
    route.attempt_geometry_from(
      3UL,
      state,
      fn() {
        Err(@diagnostics.FrameworkError::new(@diagnostics.Busy, "fixture"))
      },
      fn(_, _, _) { Ok(7) },
    ) {
    GeometryPreflightRejected(_, value) => value
    _ => fail("preflight proof missing")
  }
  let foreign = retained_test_route()
  foreign.host.stopped = false
  let calls = Ref(0)
  assert_true(
    foreign.retry_preflight_geometry_from(
      proof,
      fn() { true },
      fn() { Ok(()) },
      fn(_, _, _) {
        calls.val += 1
        Ok(7)
      },
    )
    is GeometryOutcomeUncertain(_),
  )
  assert_true(
    route.retry_preflight_geometry_from(
      proof,
      fn() { false },
      fn() { Ok(()) },
      fn(_, _, _) {
        calls.val += 1
        Ok(7)
      },
    )
    is GeometryOutcomeUncertain(_),
  )
  assert_eq(calls.val, 0)
  ignore(
    route.update_from(
      3UL,
      state,
      fn() { Err(@diagnostics.FrameworkError::new(@diagnostics.Busy, "again")) },
      fn(_, _, _) {
        calls.val += 1
        Ok(7)
      },
    ),
  )
  assert_true(
    route.retry_preflight_geometry_from(proof, fn() { true }, fn() { Ok(()) }, fn(
      _,
      _,
      _,
    ) {
      calls.val += 1
      Ok(7)
    })
    is GeometryOutcomeUncertain(_),
  )
  assert_eq(calls.val, 0)
}

///|
test "native error after candidate admission never produces a preflight receipt" {
  let route = retained_test_route()
  route.host.stopped = false
  let state = retained_geometry_test_state("x", 2.0)
  let calls = Ref(0)
  let result = route.attempt_geometry_from(3UL, state, fn() { Ok(()) }, fn(
    _,
    _,
    _,
  ) {
    calls.val += 1
    Err(
      @diagnostics.FrameworkError::new(
        @diagnostics.NativeFailure,
        "after_native",
      ),
    )
  })
  assert_true(result is GeometryOutcomeUncertain(_))
  assert_eq(calls.val, 1)
  assert_true(route.pending_geometry() is Some(_))
}

///|
test "repeated preflight produces a new receipt and old receipt cannot replay" {
  let route = retained_test_route()
  route.host.stopped = false
  let state = retained_geometry_test_state("日本", 2.0)
  let busy = fn() {
    Err(@diagnostics.FrameworkError::new(@diagnostics.Busy, "fixture"))
  }
  let first = match
    route.attempt_geometry_from(3UL, state, busy, fn(_, _, _) { Ok(7) }) {
    GeometryPreflightRejected(_, value) => value
    _ => fail("first proof missing")
  }
  let second = match
    route.retry_preflight_geometry_from(first, fn() { true }, busy, fn(
      _,
      _,
      _,
    ) {
      Ok(7)
    }) {
    GeometryPreflightRejected(_, value) => value
    _ => fail("second proof missing")
  }
  let calls = Ref(0)
  assert_true(
    route.retry_preflight_geometry_from(first, fn() { true }, fn() { Ok(()) }, fn(
      _,
      _,
      _,
    ) {
      calls.val += 1
      Ok(7)
    })
    is GeometryOutcomeUncertain(_),
  )
  assert_eq(calls.val, 0)
  assert_true(
    route.retry_preflight_geometry_from(
      second,
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
    is GeometryOutcomeUncertain(_),
  )
  assert_eq(calls.val, 0)
}
