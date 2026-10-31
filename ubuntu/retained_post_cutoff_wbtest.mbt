///|
test "post cutoff ordinary key remains deliverable until binding release" {
  let route = retained_test_route()
  route.direct_binding = true
  route.closed = true
  route.direct_cutoff_complete = true
  let window = @platform.WindowId::new(51L)
  let event = @platform.Event::new(
    window,
    21L,
    1.0,
    @platform.Input(
      @primitives.KeyPressed(
        key=@primitives.Enter,
        modifiers=@primitives.Modifiers::none(),
        repeat=false,
      ),
    ),
  )
  let record = direct_insert_record(route, 21, "x")
  let receipt = route
    .prepare({
      ..record,
      event: Some(Platform(event)),
      direct_origin: false,
      direct_epoch: 0,
    })
    .unwrap()
  assert_true(receipt.event() is Platform(_))
  assert_true(receipt.direct_insert() is None)
  assert_eq(route.ordinal, 0L)
}

///|
test "post cutoff keys still reject unresolved and foreign ownership" {
  let route = retained_test_route()
  route.direct_binding = true
  let window = @platform.WindowId::new(51L)
  let event = @platform.Event::new(
    window,
    21L,
    1.0,
    @platform.Input(
      @primitives.KeyPressed(
        key=@primitives.Enter,
        modifiers=@primitives.Modifiers::none(),
        repeat=false,
      ),
    ),
  )
  let base = direct_insert_record(route, 21, "x")
  let key = { ..base, event: Some(Platform(event)), direct_origin: false, }
  // A partial begin failure can close a route without performing cutoff.
  route.closed = true
  assert_true(route.prepare(key).unwrap().event() is Unhandled(_))
  route.closed = false
  route.end_from(3UL, fn() { Ok(()) }, fn(_, _) { Ok(()) }).unwrap()
  assert_true(route.direct_cutoff_complete)
  assert_true(route.prepare(key).unwrap().event() is Platform(_))
  assert_true(
    route.prepare({ ..key, stale: true, }).unwrap().event() is Unhandled(_),
  )
  assert_true(
    route.prepare({ ..key, revoked: true, }).unwrap().event() is Unhandled(_),
  )
  assert_true(
    route
    .prepare({ ..key, direct_origin: true, direct_epoch: 8, })
    .unwrap()
    .event()
    is Unhandled(_),
  )
  assert_true(
    route
    .prepare({ ..key, direct_origin: true, direct_epoch: 7, })
    .unwrap()
    .event()
    is Unhandled(_),
  )
  assert_true(
    route.prepare({ ..key, composition_epoch: 7, }).unwrap().event()
    is Unhandled(_),
  )
  assert_true(
    route.prepare({ ..key, sequence: 22, }).unwrap().event() is Unhandled(_),
  )
  let other = @platform.WindowId::new(52L)
  assert_true(
    route.prepare({ ..key, window: other, }).unwrap().event() is Unhandled(_),
  )
  assert_eq(route.ordinal, 0L)
}
