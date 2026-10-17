///|
/// Tracks the last cursor installed on a macOS host so repeated frames only
/// cross the native boundary when the desired cursor changes.
pub struct CursorState {
  priv mut current : @platform.Cursor?
}

///|
pub fn CursorState::new() -> CursorState {
  { current: None, }
}

///|
/// Apply a cursor, returning true only when the host was called.
pub fn CursorState::apply(
  self : CursorState,
  host : @macos.Host,
  cursor : @platform.Cursor,
) -> Result[Bool, @diagnostics.FrameworkError] {
  let unchanged = match self.current {
    Some(previous) =>
      match (previous, cursor) {
        (Arrow, Arrow) | (PointingHand, PointingHand) | (Text, Text) => true
        _ => false
      }
    None => false
  }
  if unchanged {
    return Ok(false)
  }
  match host.set_cursor(cursor) {
    Err(error) => Err(error)
    Ok(_) => {
      self.current = Some(cursor)
      Ok(true)
    }
  }
}

///|
pub fn CursorState::current(self : CursorState) -> @platform.Cursor? {
  self.current
}
