///|
/// FIXTURE ONLY. This synthetic route uses an invalid native host token and
/// must never be used as a product dependency or native acceptance evidence.
pub fn fixture_handoff_receipt(
  state : @text_host.TextInputState,
) -> (RetainedOrderedRoute, RetainedOrderedReceipt) {
  let host : Host = { token: -1, stopped: true }
  let window = @platform.WindowId::new(51L)
  let route : RetainedOrderedRoute = {
    host, window: Some(window), root: 9UL, portable_epoch: 3UL,
    native_epoch: 7, direct_binding: false, direct_cutoff_complete: false,
    native_seat: 11L, native_proxy: 4, ordinal: 0L, closed: false,
    pending_geometry: None, geometry_generation: 0UL, geometry_handoff: None,
    geometry_handoff_call: false, shortcuts: ShortcutKeyTracker::new(),
  }
  ignore(route.update_from(3UL, state, fn() { Ok(()) }, fn(_, _, _) {
    Err(@diagnostics.FrameworkError::new(@diagnostics.NativeFailure, "fixture"))
  }))
  let target : TextSessionTarget = {
    window, sequence: 21L, epoch: 7, seat: 11L, proxy_generation: 4, serial: 12,
  }
  let fields = FixedArray::make(217, 0.0)
  fields[3] = 1.0
  let record : RetainedEditorRecord = {
    host, window, sequence: 21,
    event: Some(TextSession(target, Commit(text="日本", deletion=None, position=None))),
    raw_fields: fields, stale: false, direct_epoch: 0, composition_epoch: 0,
    revoked: false, direct_origin: false,
  }
  (route, route.prepare(record).unwrap())
}

///|
/// FIXTURE ONLY. Exercises the real route handoff state machine with fake
/// exact-head ACK, not a native queue or a compositor.
pub fn fixture_handoff_transfer(
  route : RetainedOrderedRoute, receipt : RetainedOrderedReceipt,
) -> Result[Unit, @diagnostics.FrameworkError] {
  route.handoff_geometry_from(receipt, fn() { Ok(Some(receipt.record)) }, fn(_) { Ok(()) })
}
