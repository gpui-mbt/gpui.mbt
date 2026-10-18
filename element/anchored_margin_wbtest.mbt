///|
fn margin_translation(
  position : @primitives.Point,
  origin : @primitives.Point,
  size : @primitives.Size,
  viewport : @primitives.Size,
  margin : Double,
  mode~ : AnchoredPositionMode = Window,
  scale~ : Double? = None,
) -> Result[@primitives.Point, ElementError] {
  anchored_translation(
    { after: 3, measured_leaf: false, anchor: TopLeft, mode, position, margin, },
    origin,
    size,
    viewport,
    scale,
  )
}

///|
test "margin translation rejects invalid specs and preserves unused finite margins" {
  let point = @primitives.Point::new(0, 0).unwrap()
  let size = @primitives.Size::new(40, 24).unwrap()
  let viewport = @primitives.Size::new(160, 120).unwrap()
  for margin in [-1.0, 0.0 / 0.0, 1.0 / 0.0, -1.0 / 0.0] {
    assert_true(
      margin_translation(point, point, size, viewport, margin)
      is Err(GeometryFailure),
    )
  }
  assert_true(
    margin_translation(point, point, size, viewport, 1.7976931348623157e308) ==
    Ok(point),
  )
}

///|
test "margin translation rejects correction overflow before an opposite edge can hide it" {
  let zero = @primitives.Point::new(0, 0).unwrap()
  let viewport = @primitives.Size::new(0, 0).unwrap()
  for
    (px, py, width, height, margin) in [
      // Raw far-edge overflow.
      (1.0e308, 0.0, 1.0e308, 0.0, 8.0),
      (0.0, 1.0e308, 0.0, 1.0e308, 8.0),
      // Overflow-plus-margin becomes infinite, even with zero-sized children.
      (1.0e308, 0.0, 0.0, 0.0, 1.0e308),
      (0.0, 1.0e308, 0.0, 0.0, 1.0e308),
      // Correction stays finite but subtracting it overflows before left/top.
      (-1.2e308, 0.0, 1.7e308, 0.0, 1.0e308),
      (0.0, -1.2e308, 0.0, 1.7e308, 1.0e308),
    ] {
    assert_true(
      margin_translation(
        @primitives.Point::new(px, py).unwrap(),
        zero,
        @primitives.Size::new(width, height).unwrap(),
        viewport,
        margin,
      )
      is Err(GeometryFailure),
    )
  }
}

///|
test "margin translation rejects corrected extents local sums offsets and device overflow" {
  let zero = @primitives.Point::new(0, 0).unwrap()
  let empty = @primitives.Size::new(0, 0).unwrap()
  let large_viewport = @primitives.Size::new(1.7e308, 1.7e308).unwrap()
  for
    (px, py, width, height) in [
      (-1.0, 0.0, 1.0e308, 0.0),
      (0.0, -1.0, 0.0, 1.0e308),
    ] {
    assert_true(
      margin_translation(
        @primitives.Point::new(px, py).unwrap(),
        zero,
        @primitives.Size::new(width, height).unwrap(),
        large_viewport,
        1.0e308,
      )
      is Err(GeometryFailure),
    )
  }
  assert_true(
    margin_translation(
      @primitives.Point::new(1.0e308, 0).unwrap(),
      @primitives.Point::new(1.0e308, 0).unwrap(),
      empty,
      large_viewport,
      8,
      mode=Local,
    )
    is Err(GeometryFailure),
  )
  assert_true(
    margin_translation(
      @primitives.Point::new(1.0e308, 0).unwrap(),
      @primitives.Point::new(-1.0e308, 0).unwrap(),
      empty,
      large_viewport,
      8,
    )
    is Err(GeometryFailure),
  )
  assert_true(
    margin_translation(
      @primitives.Point::new(1.0e308, 0).unwrap(),
      zero,
      empty,
      large_viewport,
      8,
      scale=Some(2.0),
    )
    is Err(GeometryFailure),
  )
}

///|
test "fractional margin correction precedes logical rounding and device snapping" {
  let origin = @primitives.Point::new(0, 0).unwrap()
  let position = @primitives.Point::new(-0.25, -0.25).unwrap()
  let size = @primitives.Size::new(40, 24).unwrap()
  let viewport = @primitives.Size::new(160, 120).unwrap()
  assert_true(
    margin_translation(position, origin, size, viewport, 0.5) ==
    Ok(@primitives.Point::new(1, 1).unwrap()),
  )
  assert_true(
    margin_translation(position, origin, size, viewport, 0.5, scale=Some(1.25)) ==
    Ok(@primitives.Point::new(0.8, 0.8).unwrap()),
  )
}
