///|
fn released_direct_test_route() -> RetainedOrderedRoute {
  let route = retained_test_route()
  route.direct_binding = true
  route.end_from(3UL, fn() { Ok(()) }, fn(_, _) { Ok(()) }).unwrap()
  route.release_from(3UL, fn() { Ok(()) }, fn() { Ok(()) }).unwrap()
  route
}

///|
test "resolved direct rearm preserves the released owner on Busy" {
  let route = released_direct_test_route()
  let window = @platform.WindowId::new(51L)
  let mut observed = (0, 0, 0)
  assert_true(
    route.begin_after_resolved_cutoff_from(window, 10UL, 3UL, 27, fn(
      token,
      epoch,
      sequence,
    ) {
      observed = (token, epoch, sequence)
      Err(@diagnostics.FrameworkError::new(@diagnostics.Busy, "native_rebegin"))
    })
    is Err(_),
  )
  assert_eq(observed, (51, 7, 27))
  assert_true(route.binding_epoch() is None)
  assert_eq(route.portable_epoch, 3UL)
  assert_eq(route.root, 0UL)
  assert_eq(route.native_epoch, 0)
  assert_true(route.released_direct is Some((_, 3UL, 7)))
  assert_false(route.closed)
}

///|
test "resolved direct rearm creates one fresh owner and rejects predecessor reuse" {
  let route = released_direct_test_route()
  let window = @platform.WindowId::new(51L)
  let next = route
    .begin_after_resolved_cutoff_from(window, 10UL, 3UL, 27, fn(_, _, _) {
      Ok(9)
    })
    .unwrap()
  assert_eq(next, 4UL)
  assert_eq(route.binding_epoch(), Some(4UL))
  assert_eq(route.root, 10UL)
  assert_eq(route.native_epoch(), Some(9))
  assert_true(route.direct_binding)
  assert_false(route.direct_cutoff_complete)
  assert_true(route.released_direct is None)
  let mut called = false
  assert_true(
    route.begin_after_resolved_cutoff_from(window, 11UL, 3UL, 27, fn(_, _, _) {
      called = true
      Ok(10)
    })
    is Err(_),
  )
  assert_false(called)
  assert_eq(route.binding_epoch(), Some(4UL))
}

///|
test "resolved direct rearm rejects foreign identities and a non-direct release" {
  let route = released_direct_test_route()
  let window = @platform.WindowId::new(51L)
  let mut called = false
  let begin = fn(_ : Int32, _ : Int32, _ : Int32) {
    called = true
    Ok(9)
  }
  assert_true(
    route.begin_after_resolved_cutoff_from(
      @platform.WindowId::new(52L),
      10UL,
      3UL,
      27,
      begin,
    )
    is Err(_),
  )
  assert_true(
    route.begin_after_resolved_cutoff_from(window, 10UL, 2UL, 27, begin)
    is Err(_),
  )
  assert_true(
    route.begin_after_resolved_cutoff_from(window, 0UL, 3UL, 27, begin)
    is Err(_),
  )
  assert_true(
    route.begin_after_resolved_cutoff_from(window, 10UL, 3UL, 0, begin)
    is Err(_),
  )
  route.released_direct = None
  assert_true(
    route.begin_after_resolved_cutoff_from(window, 10UL, 3UL, 27, begin)
    is Err(_),
  )
  assert_false(called)
  assert_eq(route.portable_epoch, 3UL)
}
