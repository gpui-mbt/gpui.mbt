///|
fn retained_geometry_test_state(
  text : String,
  x : Double,
) -> @text_host.TextInputState {
  @text_host.TextInputState::new(
    @text.TextDocument::new(text).unwrap(),
    @primitives.Rect::new(x, 1.0, 1.0, 20.0).unwrap(),
  )
}

///|
test "uncertain native geometry retains the original candidate for exact retry" {
  let route = retained_test_route()
  let wanted = retained_geometry_test_state("日本", 5.0).with_preedit(
    Some(
      @text_host.TextPreedit::new(
        "に",
        @text.TextSelection::new(1, 1).unwrap(),
      ),
    ),
  )
  let replacement = retained_geometry_test_state("other", 11.0)
  let mut calls = 0
  let mut native_shadow = "old"
  let mut captured_identity = false
  let mut reentrant_update_blocked = false
  let mut reentrant_end_blocked = false
  let queued = route
    .prepare(retained_test_record(route, 21, 7, Entered, false))
    .unwrap()
  let attempted = route.update_from(3UL, wanted, fn() { Ok(()) }, fn(
    window,
    epoch,
    state,
  ) {
    calls += 1
    captured_identity = window.value() == 51L && epoch == 7
    reentrant_update_blocked = route.update_from(
        3UL,
        replacement,
        fn() { Ok(()) },
        fn(_, _, _) { Ok(7) },
      )
      is Err(_)
    reentrant_end_blocked = route.end_from(3UL, fn() { Ok(()) }, fn(_, _) {
        Ok(())
      })
      is Err(_)
    native_shadow = state.document().text()
    Err(@diagnostics.FrameworkError::new(@diagnostics.NativeFailure, "fixture"))
  })
  assert_true(attempted is Err(_))
  assert_true(captured_identity)
  assert_true(reentrant_update_blocked && reentrant_end_blocked)
  assert_eq(native_shadow, "日本")
  let pending = route.pending_geometry().unwrap()
  assert_eq(pending.window().value(), 51L)
  assert_eq(pending.root(), 9UL)
  assert_eq(pending.epoch(), 3UL)
  assert_eq(pending.native_epoch(), 7)
  assert_eq(pending.generation(), 1UL)
  assert_eq(pending.state().document().text(), "日本")
  assert_eq(pending.state().preedit().unwrap().text(), "に")
  assert_true(
    pending.state().preedit().unwrap().selection() ==
    @text.TextSelection::new(1, 1).unwrap(),
  )
  assert_true(pending.state().caret() == wanted.caret())
  let mut ack_called = false
  assert_true(
    queued.finish_ack(fn() {
      ack_called = true
      Ok(())
    })
    is Err(_),
  )
  assert_false(ack_called)
  assert_true(
    route.update_from(3UL, replacement, fn() { Ok(()) }, fn(_, _, _) {
      calls += 1
      Ok(7)
    })
    is Err(_),
  )
  let mut cutoff_called = false
  assert_true(
    route.end_from(3UL, fn() { Ok(()) }, fn(_, _) {
      cutoff_called = true
      Ok(())
    })
    is Err(_),
  )
  assert_false(cutoff_called)
  assert_true(
    route.retry_geometry_from(
      3UL,
      fn() {
        Err(@diagnostics.FrameworkError::new(@diagnostics.Busy, "fixture"))
      },
      fn(_, _, _) {
        calls += 1
        Ok(7)
      },
    )
    is Err(_),
  )
  assert_true(
    route.retry_geometry_from(4UL, fn() { Ok(()) }, fn(_, _, _) {
      calls += 1
      Ok(7)
    })
    is Err(_),
  )
  route.root = 10UL
  assert_true(
    route.retry_geometry_from(3UL, fn() { Ok(()) }, fn(_, _, _) {
      calls += 1
      Ok(7)
    })
    is Err(_),
  )
  route.root = 9UL
  assert_eq(calls, 1)
  assert_true(
    route.retry_geometry_from(3UL, fn() { Ok(()) }, fn(_, _, _) { Ok(8) })
    is Err(_),
  )
  assert_true(route.pending_geometry() is Some(_))
  let mut exact_retry = false
  let receipt = route
    .retry_geometry_from(3UL, fn() { Ok(()) }, fn(window, epoch, state) {
      exact_retry = window.value() == 51L &&
        epoch == 7 &&
        state.document().text() == "日本" &&
        state.caret() == wanted.caret()
      Ok(7)
    })
    .unwrap()
  assert_true(exact_retry)
  assert_eq(receipt.pending().generation(), 1UL)
  assert_true(route.pending_geometry() is None)
  assert_true(
    route.retry_geometry_from(3UL, fn() { Ok(()) }, fn(_, _, _) { Ok(7) })
    is Err(_),
  )
  assert_true(
    route.update_from(3UL, replacement, fn() { Ok(()) }, fn(_, _, _) {
      Err(
        @diagnostics.FrameworkError::new(@diagnostics.NativeFailure, "fixture"),
      )
    })
    is Err(_),
  )
  assert_eq(route.pending_geometry().unwrap().generation(), 2UL)
  assert_eq(receipt.pending().generation(), 1UL)
  assert_false(route.geometry_receipt_is_current(receipt))
}

///|
test "preflight failure and direct geometry do not claim native application" {
  let route = retained_test_route()
  let state = retained_geometry_test_state("x", 1.0)
  let mut calls = 0
  assert_true(
    route.update_from(
      3UL,
      state,
      fn() {
        Err(@diagnostics.FrameworkError::new(@diagnostics.Busy, "fixture"))
      },
      fn(_, _, _) {
        calls += 1
        Ok(7)
      },
    )
    is Err(_),
  )
  assert_true(route.pending_geometry() is None)
  assert_eq(route.geometry_generation, 0UL)
  route.direct_binding = true
  match
    route.update_from(3UL, state, fn() { Ok(()) }, fn(_, _, _) {
      calls += 1
      Ok(7)
    }) {
    Err(error) =>
      assert_true(error.code() is @diagnostics.UnsupportedCapability)
    Ok(_) => fail("direct binding has no native text geometry")
  }
  assert_eq(calls, 0)
  assert_true(route.pending_geometry() is None)
}
