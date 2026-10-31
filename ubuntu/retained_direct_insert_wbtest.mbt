///|
fn direct_insert_record(
  route : RetainedOrderedRoute,
  sequence : Int32,
  text : String,
) -> RetainedEditorRecord {
  let window = @platform.WindowId::new(51L)
  let fields = FixedArray::make(217, 0.0)
  let event = @platform.Event::new(
    window,
    sequence.to_int64(),
    1.0,
    @platform.Input(@primitives.TextInput(text~)),
  )
  {
    host: route.host,
    window,
    sequence,
    event: Some(Platform(event)),
    raw_fields: fields,
    stale: false,
    direct_epoch: 7,
    composition_epoch: 0,
    revoked: false,
    direct_origin: true,
  }
}

///|
test "direct insert retains identity and advances ordinal only on exact ack" {
  let route = retained_test_route()
  route.direct_binding = true
  let record = direct_insert_record(route, 21, "日")
  let first = route.prepare(record).unwrap()
  let repeated = route.prepare(record).unwrap()
  // A direct text record cannot also be dispatched as platform TextInput.
  assert_true(first.event() is Unhandled(_))
  let insert = first.direct_insert().unwrap()
  let again = repeated.direct_insert().unwrap()
  assert_eq(insert.native_sequence(), 21)
  assert_eq(insert.window().value(), 51L)
  assert_eq(insert.root(), 9UL)
  assert_eq(insert.epoch(), 3UL)
  assert_eq(insert.native_epoch(), 7)
  assert_eq(insert.ordinal(), 1L)
  assert_eq(insert.text(), "日")
  assert_eq(again.ordinal(), 1L)
  assert_eq(route.ordinal, 0L)
  assert_true(
    first.finish_ack(fn() {
      Err(@diagnostics.FrameworkError::new(@diagnostics.Busy, "native_ack"))
    })
    is Err(_),
  )
  assert_eq(route.ordinal, 0L)
  assert_true(route.window is Some(_))
  first.finish_ack(fn() { Ok(()) }).unwrap()
  assert_eq(route.ordinal, 1L)
  let mut called = false
  assert_true(
    repeated.finish_ack(fn() {
      called = true
      Ok(())
    })
    is Err(_),
  )
  assert_false(called)
  let next = route.prepare(direct_insert_record(route, 24, "本")).unwrap()
  assert_eq(next.direct_insert().unwrap().ordinal(), 2L)
}

///|
test "direct insert rejects mismatched and stale owner without ordinal promotion" {
  let route = retained_test_route()
  route.direct_binding = true
  let record = direct_insert_record(route, 21, "日")
  assert_true(
    route.prepare({ ..record, stale: true, }).unwrap().direct_insert() is None,
  )
  assert_true(
    route.prepare({ ..record, revoked: true, }).unwrap().direct_insert() is None,
  )
  assert_true(
    route.prepare({ ..record, revoked: true, }).unwrap().event() is Unhandled(_),
  )
  assert_true(
    route.prepare({ ..record, direct_epoch: 8, }).unwrap().direct_insert()
    is None,
  )
  assert_true(
    route.prepare({ ..record, direct_origin: false, }).unwrap().direct_insert()
    is None,
  )
  assert_true(
    route.prepare({ ..record, composition_epoch: 7, }).unwrap().direct_insert()
    is None,
  )
  assert_true(
    route.prepare({ ..record, composition_epoch: 7, }).unwrap().event()
    is Unhandled(_),
  )
  let foreign = @platform.WindowId::new(52L)
  let foreign_event = @platform.Event::new(
    foreign,
    21L,
    1.0,
    @platform.Input(@primitives.TextInput(text="日")),
  )
  assert_true(
    route
    .prepare({
      ..record,
      window: foreign,
      event: Some(Platform(foreign_event)),
    })
    .unwrap()
    .direct_insert()
    is None,
  )
  let wrong_sequence = @platform.Event::new(
    record.window,
    22L,
    1.0,
    @platform.Input(@primitives.TextInput(text="日")),
  )
  assert_true(
    route
    .prepare({ ..record, event: Some(Platform(wrong_sequence)), })
    .unwrap()
    .direct_insert()
    is None,
  )
  assert_true(
    route
    .prepare({ ..record, event: Some(Platform(wrong_sequence)), })
    .unwrap()
    .event()
    is Unhandled(_),
  )
  route.root = 0UL
  assert_true(route.prepare(record).unwrap().direct_insert() is None)
  route.root = 9UL
  route.closed = true
  assert_true(route.prepare(record).unwrap().direct_insert() is None)
  assert_eq(route.ordinal, 0L)
}

///|
test "direct insert refuses acknowledgement after native owner changes" {
  let route = retained_test_route()
  route.direct_binding = true
  let receipt = route.prepare(direct_insert_record(route, 21, "日")).unwrap()
  route.native_epoch = 8
  let mut called = false
  assert_true(
    receipt.finish_ack(fn() {
      called = true
      Ok(())
    })
    is Err(_),
  )
  assert_false(called)
  assert_eq(route.ordinal, 0L)
}

///|
test "non-direct platform text keeps existing delivery and is not an insert" {
  let route = retained_test_route()
  let legacy = direct_insert_record(route, 21, "日")
  let ordinary = route
    .prepare({ ..legacy, direct_origin: false, direct_epoch: 0, })
    .unwrap()
  assert_true(ordinary.event() is Platform(_))
  assert_true(ordinary.direct_insert() is None)
  assert_eq(route.ordinal, 0L)
}
