///|
test "terminal seal rejects an active or cutoff binding before native call" {
  let route = retained_test_route()
  let mut calls = 0
  let seal = fn(_ : Int32, _ : Int32) {
    calls += 1
    Ok(())
  }
  let window = @platform.WindowId::new(51L)
  assert_true(route.seal_destroyed_from(window, 21, seal) is Err(_))
  route.direct_binding = true
  route.end_from(3UL, fn() { Ok(()) }, fn(_, _) { Ok(()) }).unwrap()
  assert_true(route.seal_destroyed_from(window, 21, seal) is Err(_))
  assert_eq(calls, 0)
  assert_eq(route.binding_epoch(), Some(3UL))
}

///|
test "terminal seal preserves released route on native refusal" {
  let route = retained_test_route()
  route.end_from(3UL, fn() { Ok(()) }, fn(_, _) { Ok(()) }).unwrap()
  route.release_from(3UL, fn() { Ok(()) }, fn() { Ok(()) }).unwrap()
  let window = @platform.WindowId::new(51L)
  let mut calls = 0
  let mut observed_window = 0
  let mut observed_sequence = 0
  assert_true(
    route.seal_destroyed_from(window, 21, fn(token, sequence) {
      observed_window = token
      observed_sequence = sequence
      calls += 1
      Err(@diagnostics.FrameworkError::new(@diagnostics.Busy, "native_seal"))
    })
    is Err(_),
  )
  assert_eq(calls, 1)
  assert_eq(observed_window, 51)
  assert_eq(observed_sequence, 21)
  assert_true(route.binding_epoch() is None)
  assert_false(route.closed)
  assert_eq(route.ordinal, 0L)
}

///|
test "terminal receipt carries only the exact native sealed identity" {
  let route = retained_test_route()
  route.end_from(3UL, fn() { Ok(()) }, fn(_, _) { Ok(()) }).unwrap()
  route.release_from(3UL, fn() { Ok(()) }, fn() { Ok(()) }).unwrap()
  let window = @platform.WindowId::new(51L)
  let receipt = route
    .seal_destroyed_from(window, 21, fn(_, _) { Ok(()) })
    .unwrap()
  assert_eq(receipt.window().value(), window.value())
  assert_eq(receipt.native_sequence(), 21)
  let mut called = false
  assert_true(
    route.seal_destroyed_from(window, 0, fn(_, _) {
      called = true
      Ok(())
    })
    is Err(_),
  )
  assert_true(
    route.seal_destroyed_from(@platform.WindowId::new(0L), 21, fn(_, _) {
      called = true
      Ok(())
    })
    is Err(_),
  )
  assert_false(called)
}
