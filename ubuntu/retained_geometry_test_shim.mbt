///|
/// FIXTURE ONLY: constructs a synthetic host/route; never ship this API.
fn fixture_geometry_route() -> RetainedOrderedRoute {
  let host : Host = { token: -1, stopped: true }
  { host, window: Some(@platform.WindowId::new(51L)), root: 9UL,
    portable_epoch: 3UL, native_epoch: 7, direct_binding: false,
    direct_cutoff_complete: false, native_seat: 11L, native_proxy: 4,
    ordinal: 0L, closed: false, pending_geometry: None,
    geometry_generation: 0UL, shortcuts: ShortcutKeyTracker::new() }
}

///|
/// FIXTURE ONLY: an actual opaque route receipt from a synthetic callback;
/// token -1 ensures it is never current in a native host.
pub fn fixture_geometry_receipt(
  state : @text_host.TextInputState,
) -> (RetainedOrderedRoute, RetainedGeometryReceipt) {
  let route = fixture_geometry_route()
  let receipt = route.update_from(3UL, state, fn() { Ok(()) }, fn(_, _, _) { Ok(7) }).unwrap()
  (route, receipt)
}

///|
/// FIXTURE ONLY: installs a pending candidate after synthetic native error.
pub fn fixture_geometry_pending(
  state : @text_host.TextInputState,
) -> RetainedOrderedRoute {
  let route = fixture_geometry_route()
  ignore(route.update_from(3UL, state, fn() { Ok(()) }, fn(_, _, _) {
    Err(@diagnostics.FrameworkError::new(@diagnostics.NativeFailure, "synthetic_fixture"))
  }))
  route
}
