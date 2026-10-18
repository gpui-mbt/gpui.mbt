///|
/// Multiply a command's existing opacity without quantizing its color alpha.
/// Unit opacity preserves the legacy command exactly. Clips are unchanged.
/// Nonunit legacy quads retain byte colors and unrestricted legacy geometry
/// in the additive OpacityQuadCommand variant; snapshots remain QuadItem.
pub fn PaintCommand::with_opacity(
  self : PaintCommand,
  opacity : Double,
) -> Result[PaintCommand, PaintError] {
  if !snapshot_finite(opacity) || opacity < 0.0 || opacity > 1.0 {
    return Err(InvalidOpacity)
  }
  let existing = self.opacity()
  if !snapshot_finite(existing) || existing < 0.0 || existing > 1.0 {
    return Err(InvalidOpacity)
  }
  if opacity == 1.0 {
    return Ok(self)
  }
  Ok(match self {
    QuadCommand(id~, bounds~, color~) =>
      OpacityQuadCommand(id~, bounds~, color~, opacity~)
    OpacityQuadCommand(id~, bounds~, color~, opacity=local) =>
      OpacityQuadCommand(id~, bounds~, color~, opacity=local * opacity)
    PaintCommand(id~, shape~, fill~, opacity=local) =>
      PaintCommand(id~, shape~, fill~, opacity=local * opacity)
    ClipPushCommand(..) | ClipPopCommand(..) => self
  })
}

///|
/// The scalar multiplier, separate from intrinsic color/fill alpha.
pub fn PaintCommand::opacity(self : PaintCommand) -> Double {
  match self {
    PaintCommand(opacity~, ..) | OpacityQuadCommand(opacity~, ..) => opacity
    QuadCommand(..) | ClipPushCommand(..) | ClipPopCommand(..) => 1.0
  }
}
