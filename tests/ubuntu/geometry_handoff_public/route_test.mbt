///|
extern "C" fn review207_setup() -> Int32 = "gpui_review207_setup"
///|
extern "C" fn review207_enter() -> Unit = "gpui_review207_enter"
///|
extern "C" fn review207_make_inactive() -> Unit = "gpui_review207_make_inactive"
///|
extern "C" fn review207_make_active() -> Unit = "gpui_review207_make_active"
///|
extern "C" fn review207_commit() -> Unit = "gpui_review207_commit"
///|
extern "C" fn review207_commit_next() -> Unit = "gpui_review207_commit_next"
///|
extern "C" fn review207_nontext() -> Unit = "gpui_review207_nontext"
///|
extern "C" fn review207_fail_next_ack() -> Unit = "gpui_review207_fail_next_ack"
///|
extern "C" fn review207_wrong_seat() -> Unit = "gpui_review207_wrong_seat"
///|
extern "C" fn review207_wrong_epoch() -> Unit = "gpui_review207_wrong_epoch"
///|
extern "C" fn review207_finish() -> Unit = "gpui_review207_finish"
///|
#borrow(fields, output)
extern "C" fn review207_state(fields : FixedArray[Int32], capacity : Int32, output : Bytes, length : Int32) -> Int32 = "gpui_review207_state"

///|
fn review207_begin() -> (RetainedOrderedRoute, UInt64) {
  let token = review207_setup()
  if token != 741 { abort("fixture start failed") }
  let host : Host = { token, stopped: false }
  let route = RetainedOrderedRoute::new(host).unwrap()
  let initial = retained_geometry_test_state("old", 1.0)
  let epoch = route.begin(@platform.WindowId::new(51L), 9UL, initial).unwrap()
  review207_enter()
  let entered = route.peek().unwrap().unwrap()
  if !(entered.event() is Lifecycle(_, _)) { abort("native enter missing") }
  entered.ack().unwrap()
  (route, epoch)
}

///|
fn review207_count() -> Int32 {
  let fields = FixedArray::make(8, 0)
  let output = Bytes::make(128, (0).to_byte())
  if review207_state(fields, fields.length(), output, output.length()) != 0 { abort("state unavailable") }
  fields[4]
}

///|
fn review207_uncertain(route : RetainedOrderedRoute, epoch : UInt64) -> Unit {
  review207_make_inactive()
  let candidate = retained_geometry_test_state("new", 5.0)
  if !(route.update_with_receipt(epoch, candidate) is Err(_)) { abort("expected injected activation error") }
  let fields = FixedArray::make(8, 0)
  let output = Bytes::make(128, (0).to_byte())
  if review207_state(fields, fields.length(), output, output.length()) != 0 { abort("state unavailable") }
  if fields[0] != 3 || fields[6] != 5 || output[0].to_int() != 110 { abort("native partial mutation missing") }
  review207_make_active()
}

///|
test "public retained route hands off one real native FIFO commit after geometry error" {
  let (route, epoch) = review207_begin()
  review207_uncertain(route, epoch)
  review207_commit()
  assert_eq(review207_count(), 1)
  let head = route.peek().unwrap().unwrap()
  assert_true(head.event() is Text(_))
  let source_seq = head.native_sequence()
  review207_fail_next_ack()
  assert_true(route.handoff_geometry_head(head) is Err(_))
  assert_eq(review207_count(), 1)
  assert_true(route.reserved_geometry_text() is Some(_))
  assert_true(route.owned_geometry_text() is None)
  assert_true(route.retry_geometry(epoch) is Err(_))
  route.handoff_geometry_head(head).unwrap()
  assert_eq(review207_count(), 0)
  assert_true(route.reserved_geometry_text() is None)
  let held = route.owned_geometry_text().unwrap()
  assert_eq(held.native_sequence(), source_seq)
  assert_eq(held.native_target().seat, 117L)
  assert_eq(held.native_target().proxy_generation, 4)
  assert_true(held.event().kind() is @text_host.Commit(text="日本"))
  assert_true(route.take_owned_geometry_text(epoch) is Err(_))
  ignore(route.retry_geometry(epoch).unwrap())
  let moved = route.take_owned_geometry_text(epoch).unwrap()
  assert_eq(moved.native_sequence(), source_seq)
  assert_true(moved.native_text() is Commit(text="日本", deletion=None, position=None))
  assert_true(route.take_owned_geometry_text(epoch) is Err(_))
  assert_true(route.peek().unwrap() is None)
  review207_finish()
}

///|
test "public retained route keeps nontext native and blocks retry" {
  let (route, epoch) = review207_begin()
  review207_uncertain(route, epoch)
  review207_nontext()
  let head = route.peek().unwrap().unwrap()
  assert_true(route.handoff_geometry_head(head) is Err(_))
  assert_true(route.retry_geometry(epoch) is Err(_))
  assert_eq(review207_count(), 1)
  assert_true(route.reserved_geometry_text() is None)
  assert_true(route.host.stop() is Err(_))
  review207_finish()
}

///|
test "public retained route preserves second arrival when one slot is owned" {
  let (route, epoch) = review207_begin()
  review207_uncertain(route, epoch)
  review207_commit()
  review207_commit_next()
  assert_eq(review207_count(), 2)
  let first = route.peek().unwrap().unwrap()
  route.handoff_geometry_head(first).unwrap()
  assert_eq(review207_count(), 1)
  let second = route.peek().unwrap().unwrap()
  assert_true(route.handoff_geometry_head(second) is Err(_))
  assert_true(route.retry_geometry(epoch) is Err(_))
  assert_true(route.try_end_when_drained(epoch) is Err(_))
  assert_true(route.host.stop() is Err(_))
  assert_eq(review207_count(), 1)
  assert_true(route.owned_geometry_text().unwrap().event().kind() is @text_host.Commit(text="日本"))
  review207_finish()
}

///|
test "public retained route rejects faulted native seat and epoch without ACK" {
  for scenario in [0, 1] {
    let (route, epoch) = review207_begin()
    review207_uncertain(route, epoch)
    review207_commit()
    let head = route.peek().unwrap().unwrap()
    if scenario == 0 { review207_wrong_seat() } else { review207_wrong_epoch() }
    assert_true(route.handoff_geometry_head(head) is Err(_))
    assert_eq(review207_count(), 1)
    assert_true(route.reserved_geometry_text() is None)
    review207_finish()
  }
}

///|
test "public retained route rejects a forged root receipt without ACK" {
  let (route, epoch) = review207_begin()
  review207_uncertain(route, epoch)
  review207_commit()
  let head = route.peek().unwrap().unwrap()
  let forged = { ..head, root: 10UL }
  assert_true(route.handoff_geometry_head(forged) is Err(_))
  assert_eq(review207_count(), 1)
  assert_true(route.reserved_geometry_text() is None)
  review207_finish()
}

///|
test "public intent preserves FIFO text before native submission and exact retry" {
  let (route, epoch) = review207_begin()
  review207_commit()
  assert_eq(review207_count(), 1)
  let candidate = retained_geometry_test_state("new", 5.0)
  let intent = route.reserve_geometry_intent(epoch, candidate).unwrap()
  assert_true(route.geometry_intent_stage(intent) is Some(GeometryIntentNotSubmitted))
  assert_true(route.submit_geometry_intent(intent) is Err(_))
  assert_true(route.geometry_intent_stage(intent) is Some(GeometryIntentNotSubmitted))
  let head = route.peek().unwrap().unwrap()
  let sequence = head.native_sequence()
  route.handoff_geometry_head(head).unwrap()
  assert_eq(review207_count(), 0)
  assert_true(route.owned_geometry_text() is Some(_))
  review207_make_inactive()
  assert_true(route.submit_geometry_intent(intent) is Err(_))
  assert_true(route.geometry_intent_stage(intent) is Some(GeometryIntentOutcomeUncertain))
  let fields = FixedArray::make(8, 0)
  let bytes = Bytes::make(128, (0).to_byte())
  ignore(review207_state(fields, fields.length(), bytes, bytes.length()))
  assert_eq(fields[0], 3)
  assert_eq(fields[6], 5)
  assert_eq(bytes[0].to_int(), 110)
  assert_true(route.owned_geometry_text() is Some(_))
  review207_make_active()
  let receipt = route.submit_geometry_intent(intent).unwrap()
  assert_true(route.geometry_intent_stage(intent) is None)
  assert_true(route.geometry_receipt_is_current(receipt))
  assert_true(route.submit_geometry_intent(intent) is Err(_))
  let transferred = route.take_owned_geometry_text(epoch).unwrap()
  assert_eq(transferred.native_sequence(), sequence)
  assert_true(transferred.event().kind() is @text_host.Commit(text="日本"))
  review207_finish()
}
