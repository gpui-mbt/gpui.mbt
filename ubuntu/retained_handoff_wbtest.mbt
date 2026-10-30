///|
test "left before entered captures only matching native target on exact ACK" {
  let route = retained_test_route()
  route.native_seat = 0L
  route.native_proxy = 0
  let foreign = retained_test_record(route, 10, 6, Left, false)
  assert_true(route.prepare(foreign).unwrap().event() is Unhandled(_))
  let left = route
    .prepare(retained_test_record(route, 11, 7, Left, false))
    .unwrap()
  assert_true(left.event() is Lifecycle(_, _))
  let err = fn() {
    Err(@diagnostics.FrameworkError::new(@diagnostics.Busy, "ack"))
  }
  assert_true(left.finish_ack(err) is Err(_))
  assert_false(route.left_acked)
  left.finish_ack(fn() { Ok(()) }).unwrap()
  assert_true(route.left_acked)
  assert_eq(route.native_seat, 11L)
  assert_eq(route.native_proxy, 4)
  assert_true(left.finish_ack(fn() { Ok(()) }) is Err(_))
  let late = route
    .prepare(
      retained_test_record(
        route,
        12,
        7,
        Commit(text="日本", deletion=None, position=None),
        false,
      ),
    )
    .unwrap()
  assert_true(late.event() is Unhandled(_))
  let empty = fn() { Ok(()) }
  let busy = fn() {
    Err(@diagnostics.FrameworkError::new(@diagnostics.Busy, "fifo"))
  }
  let mut calls = 0
  let mut seen_window = 0L
  let mut seen_epoch = 0
  let mut seen_seat = 0L
  let mut seen_proxy = 0
  let check = fn(
    window : @platform.WindowId,
    epoch : Int32,
    seat : Int64,
    proxy : Int32,
  ) {
    calls += 1
    seen_window = window.value()
    seen_epoch = epoch
    seen_seat = seat
    seen_proxy = proxy
    Ok(())
  }
  assert_true(route.end_after_left_from(4UL, empty, check) is Err(_))
  assert_true(route.end_after_left_from(3UL, busy, check) is Err(_))
  assert_eq(calls, 0)
  route.end_after_left_from(3UL, empty, check).unwrap()
  assert_true(route.left_cutoff)
  assert_eq(calls, 1)
  assert_eq(seen_window, 51L)
  assert_eq(seen_epoch, 7)
  assert_eq(seen_seat, 11L)
  assert_eq(seen_proxy, 4)
  assert_true(route.end_after_left_from(3UL, empty, check) is Err(_))
}
