///|
/// FIXTURE ONLY: the native FIFO is real but protocol requests are mocked.
extern "C" fn fixture_intent_setup() -> Int32 = "gpui_review207_setup"
///|
extern "C" fn fixture_intent_enter() -> Unit = "gpui_review207_enter"
///|
extern "C" fn fixture_intent_set_window(window : Int32) -> Unit = "gpui_fixture_intent_set_window"

///|
pub extern "C" fn fixture_intent_commit() -> Unit = "gpui_review207_commit"
///|
pub extern "C" fn fixture_intent_finish() -> Unit = "gpui_review207_finish"

///|
/// FIXTURE ONLY. Do not ship this helper or treat it as live IME acceptance.
pub fn fixture_intent_route(
  state : @text_host.TextInputState, window : @platform.WindowId, root : UInt64,
) -> RetainedOrderedRoute {
  let token = fixture_intent_setup()
  if token != 741 { abort("fixture start failed") }
  fixture_intent_set_window(window.value().to_int())
  let host : Host = { token, stopped: false }
  let route = RetainedOrderedRoute::new(host).unwrap()
  ignore(route.begin(window, root, state).unwrap())
  fixture_intent_enter()
  let entered = route.peek().unwrap().unwrap()
  ignore(entered.ack().unwrap())
  route
}

///|
/// FIXTURE ONLY: change the fake native requested flag.
pub extern "C" fn fixture_intent_set_requested(value : Int32) -> Unit = "gpui_fixture_intent_set_requested"

///| Fixture-only simulated native preedit callback.
pub extern "C" fn fixture_intent_preedit() -> Unit = "gpui_fixture_intent_preedit"

///| Fixture-only later native commit callback.
pub extern "C" fn fixture_intent_commit_next() -> Unit = "gpui_review207_commit_next"

///| FIXTURE ONLY: enqueue an ordinary non-text platform record.
pub extern "C" fn fixture_intent_nontext() -> Unit = "gpui_review207_nontext"

///| FIXTURE ONLY: corrupt the queued text epoch to make the native head stale.
pub extern "C" fn fixture_intent_stale_epoch() -> Unit = "gpui_review207_wrong_epoch"

///| FIXTURE ONLY: return Busy after the real native update has taken effect.
pub extern "C" fn fixture_intent_fail_after_update() -> Unit = "gpui_fixture_fail_after_update"

///| FIXTURE ONLY: count mocked Wayland requests to detect duplicate updates.
pub extern "C" fn fixture_intent_wayland_calls() -> Int32 = "gpui_fixture_wayland_calls"

///| FIXTURE ONLY: prepare the first physical focus after the route claim.
extern "C" fn fixture_physical_windowless() -> Unit = "gpui_fixture_physical_windowless"

///|
extern "C" fn fixture_physical_focus(window : Int32) -> Unit = "gpui_fixture_physical_focus"

///|
pub extern "C" fn fixture_physical_release() -> Unit = "gpui_fixture_physical_release"

///| FIXTURE ONLY: build first-window/focus provenance using native callbacks.
pub fn fixture_physical_route(
  state : @text_host.TextInputState, window : @platform.WindowId, root : UInt64,
) -> RetainedOrderedRoute {
  let token = fixture_intent_setup()
  if token != 741 { abort("fixture start failed") }
  fixture_physical_windowless()
  let host : Host = { token, stopped: false }
  let route = RetainedOrderedRoute::new(host).unwrap()
  fixture_physical_focus(window.value().to_int())
  let focus = route.peek().unwrap().unwrap()
  ignore(focus.ack().unwrap())
  ignore(route.begin(window, root, state).unwrap())
  fixture_intent_enter()
  let entered = route.peek().unwrap().unwrap()
  ignore(entered.ack().unwrap())
  route
}
