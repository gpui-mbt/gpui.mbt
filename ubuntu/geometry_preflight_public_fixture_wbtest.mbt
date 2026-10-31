///|
/// The C wrapper mocks protocol requests but uses the real native FIFO,
/// geometry mutation and public route APIs. This is not a live compositor.
extern "C" fn preflight_fixture_setup() -> Int32 = "gpui_review206_setup"
///|
extern "C" fn preflight_fixture_focus() -> Unit = "gpui_review206_focus"
///|
extern "C" fn preflight_fixture_enqueue() -> Unit = "gpui_review206_enqueue"
///|
extern "C" fn preflight_fixture_finish() -> Unit = "gpui_review206_finish"
///|
#borrow(fields, output)
extern "C" fn preflight_fixture_state(fields : FixedArray[Int32], capacity : Int32, output : Bytes, length : Int32) -> Int32 = "gpui_review206_state"

///|
test "public route distinguishes FIFO preflight from native side effects" {
  let token = preflight_fixture_setup()
  assert_eq(token, 741)
  let base = retained_test_route()
  let route = { ..base, host: { token, stopped: false } }
  let state = retained_geometry_test_state("日本", 5.0)
  preflight_fixture_enqueue()
  let proof = match route.attempt_geometry(3UL, state) {
    GeometryPreflightRejected(_, value) => value
    _ => fail("nonempty FIFO must reject before native entry")
  }
  let fields = FixedArray::make(13, 0)
  let bytes = Bytes::make(128, (0).to_byte())
  ignore(preflight_fixture_state(fields, fields.length(), bytes, bytes.length()))
  assert_eq(fields[0], 3)
  assert_eq(fields[7], 1)
  assert_eq(fields[4], 1)
  assert_true(route.pending_geometry() is None)
  let head = route.peek().unwrap().unwrap()
  head.ack().unwrap()
  assert_true(route.preflight_geometry_is_current(proof))
  assert_true(route.retry_preflight_geometry(proof) is GeometryOutcomeUncertain(_))
  ignore(preflight_fixture_state(fields, fields.length(), bytes, bytes.length()))
  assert_eq(fields[0], 6)
  assert_eq(fields[7], 5)
  assert_eq(bytes[0].to_int(), 230)
  assert_true(route.pending_geometry() is Some(_))
  assert_false(route.preflight_geometry_is_current(proof))
  assert_true(route.retry_preflight_geometry(proof) is GeometryOutcomeUncertain(_))
  preflight_fixture_focus()
  let receipt = route.retry_geometry(3UL).unwrap()
  assert_true(route.geometry_receipt_is_current(receipt))
  assert_true(route.pending_geometry() is None)
  preflight_fixture_finish()
}
