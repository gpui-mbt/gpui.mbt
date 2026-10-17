///|
fn gradient_test_color(
  red : Double,
  green : Double,
  blue : Double,
  alpha : Double,
) -> @primitives.FloatColor {
  match @primitives.FloatColor::rgba(red, green, blue, alpha) {
    Ok(color) => color
    Err(_) => abort("valid floating color rejected")
  }
}

///|
fn gradient_test_gradient(
  angle : Double,
  start : @primitives.FloatColor,
  start_position : Double,
  end : @primitives.FloatColor,
  end_position : Double,
  space : @scene.GradientColorSpace,
) -> @scene.LinearGradient {
  match
    @scene.LinearGradient::new(
      angle, start, start_position, end, end_position, space,
    ) {
    Ok(gradient) => gradient
    Err(_) => abort("valid linear gradient rejected")
  }
}

///|
fn gradient_test_point(x : Double, y : Double) -> @primitives.Point {
  match @primitives.Point::new(x, y) {
    Ok(point) => point
    Err(_) => abort("valid point rejected")
  }
}

///|
fn gradient_test_sample(
  gradient : @scene.LinearGradient,
  x : Double,
  y : Double,
  bounds : @primitives.Rect,
) -> @primitives.FloatColor {
  match gradient.sample_shader_linear(gradient_test_point(x, y), bounds) {
    Ok(color) => color
    Err(_) => abort("valid gradient sample rejected")
  }
}

///|
fn gradient_test_near(actual : Double, expected : Double) -> Bool {
  (actual - expected).abs() < 1.0e-10
}

///|
test "linear gradient preserves raw angle outside reversed and equal positions" {
  let first = gradient_test_color(0.0, 0.5, 0.0, 0.25)
  let last = gradient_test_color(0.0, 0.0, 1.0, 0.75)
  let gradient = gradient_test_gradient(-450.0, first, 1.25, last, -0.25, Srgb)
  assert_true(gradient.angle() == -450.0)
  assert_true(gradient.start() == first)
  assert_true(gradient.end() == last)
  assert_true(gradient.start_position() == 1.25)
  assert_true(gradient.end_position() == -0.25)
  assert_true(gradient.space() == @scene.GradientColorSpace::Srgb)
  assert_true(gradient.validate() is Ok(_))
  assert_true(
    @scene.LinearGradient::new(1.0e308, first, -1.0e308, last, 1.0e308, Oklab)
    is Ok(_),
  )
  assert_true(
    @scene.LinearGradient::new(0.0, first, 0.5, last, 0.5, Srgb) is Ok(_),
  )
  for invalid in [@double.not_a_number, @double.infinity, @double.neg_infinity] {
    assert_true(
      @scene.LinearGradient::new(invalid, first, 0.0, last, 1.0, Srgb)
      is Err(InvalidGradient),
    )
    assert_true(
      @scene.LinearGradient::new(0.0, first, invalid, last, 1.0, Srgb)
      is Err(InvalidGradient),
    )
    assert_true(
      @scene.LinearGradient::new(0.0, first, 0.0, last, invalid, Srgb)
      is Err(InvalidGradient),
    )
  }
}

///|
test "linear gradient canonical data stays deterministic and float precise" {
  let first = gradient_test_color(-0.0, 0.5, 0.0, 0.25)
  let last = gradient_test_color(0.123456789012345, 0.0, 1.0, 0.75)
  let gradient = gradient_test_gradient(-0.0, first, 1.25, last, -0.25, Oklab)
  assert_eq(
    gradient.canonical_json(),
    "{\"angle\":0,\"start\":{\"color\":{\"r\":0,\"g\":0.5,\"b\":0,\"a\":0.25},\"position\":1.25},\"end\":{\"color\":{\"r\":0.123456789012345,\"g\":0,\"b\":1,\"a\":0.75},\"position\":-0.25},\"space\":\"oklab\"}",
  )
}

///|
test "Srgb sampling returns source linear shader output rather than encoded mix" {
  let red = gradient_test_color(1.0, 0.0, 0.0, 1.0)
  let blue = gradient_test_color(0.0, 0.0, 1.0, 1.0)
  let gradient = gradient_test_gradient(90.0, red, 0.0, blue, 1.0, Srgb)
  let bounds = scene_rect(0.0, 0.0, 100.0, 100.0)
  let center = gradient_test_sample(gradient, 50.0, 50.0, bounds)
  assert_true(gradient_test_near(center.red(), 0.21404114048223244))
  assert_true(center.green() == 0.0)
  assert_true(gradient_test_near(center.blue(), 0.21404114048223244))
  assert_true(center.alpha() == 1.0)
  assert_true(
    gradient.sample(gradient_test_point(50.0, 50.0), bounds) is Ok(alias_color) &&
    alias_color == center,
  )
  let left = gradient_test_sample(gradient, -100.0, 50.0, bounds)
  let right = gradient_test_sample(gradient, 200.0, 50.0, bounds)
  assert_true(gradient_test_near(left.red(), 1.0) && left.blue() == 0.0)
  assert_true(right.red() == 0.0 && gradient_test_near(right.blue(), 1.0))
}

///|
test "Oklab conversion follows pinned matrices and clamps output gamut" {
  let bounds = scene_rect(10.0, 20.0, 100.0, 100.0)
  let red = gradient_test_color(1.0, 0.0, 0.0, 1.0)
  let blue = gradient_test_color(0.0, 0.0, 1.0, 1.0)
  let gradient = gradient_test_gradient(90.0, red, 0.0, blue, 1.0, Oklab)
  let center = gradient_test_sample(gradient, 60.0, 70.0, bounds)
  assert_true(gradient_test_near(center.red(), 0.2637342897946341))
  assert_true(gradient_test_near(center.green(), 0.08657167566646633))
  assert_true(gradient_test_near(center.blue(), 0.3628242653977132))
  let half_green = gradient_test_color(0.0, 0.5, 0.0, 0.25)
  let end_blue = gradient_test_color(0.0, 0.0, 1.0, 0.75)
  let gradient = gradient_test_gradient(
    90.0,
    half_green,
    0.0,
    end_blue,
    1.0,
    Oklab,
  )
  let center = gradient_test_sample(gradient, 60.0, 70.0, bounds)
  assert_true(center.red() == 0.0)
  assert_true(gradient_test_near(center.green(), 0.24900731758504493))
  assert_true(gradient_test_near(center.blue(), 0.41534530895140337))
  assert_true(center.alpha() == 0.5)
}

///|
test "transparent color channels interpolate without alpha premultiplication" {
  let red = gradient_test_color(1.0, 0.0, 0.0, 0.0)
  let blue = gradient_test_color(0.0, 0.0, 1.0, 0.75)
  let bounds = scene_rect(0.0, 0.0, 100.0, 100.0)
  let gradient = gradient_test_gradient(90.0, red, 0.0, blue, 1.0, Srgb)
  let center = gradient_test_sample(gradient, 50.0, 50.0, bounds)
  assert_true(gradient_test_near(center.red(), 0.21404114048223244))
  assert_true(gradient_test_near(center.blue(), 0.21404114048223244))
  assert_true(center.alpha() == 0.375)
  let gradient = gradient_test_gradient(90.0, red, 0.0, blue, 1.0, Oklab)
  let center = gradient_test_sample(gradient, 50.0, 50.0, bounds)
  assert_true(gradient_test_near(center.red(), 0.2637342897946341))
  assert_true(gradient_test_near(center.blue(), 0.3628242653977132))
  assert_true(center.alpha() == 0.375)
}

///|
test "projection preserves CSS angle aspect adjustment and dominant axis" {
  let black = gradient_test_color(0.0, 0.0, 0.0, 1.0)
  let white = gradient_test_color(1.0, 1.0, 1.0, 1.0)
  let gradient = gradient_test_gradient(45.0, black, 0.0, white, 1.0, Srgb)
  let wide = scene_rect(10.0, 20.0, 200.0, 100.0)
  let tall = scene_rect(10.0, 20.0, 100.0, 200.0)
  let wide_sample = gradient_test_sample(gradient, 170.0, 50.0, wide)
  let tall_sample = gradient_test_sample(gradient, 40.0, 180.0, tall)
  assert_true(gradient_test_near(wide_sample.red(), 0.6261824575405526))
  assert_true(gradient_test_near(tall_sample.red(), 0.029183520685649663))
  let negative = gradient_test_gradient(-45.0, black, 0.0, white, 1.0, Srgb)
  let sample = gradient_test_sample(negative, 170.0, 50.0, wide)
  assert_true(gradient_test_near(sample.red(), 0.06208958385172462))
  let zero = gradient_test_gradient(0.0, black, 0.0, white, 1.0, Srgb)
  let full = gradient_test_gradient(360.0, black, 0.0, white, 1.0, Srgb)
  assert_true(
    gradient_test_sample(zero, 170.0, 50.0, wide) ==
    gradient_test_sample(full, 170.0, 50.0, wide),
  )
}

///|
test "outside and reversed stops keep authored range and direction" {
  let black = gradient_test_color(0.0, 0.0, 0.0, 1.0)
  let white = gradient_test_color(1.0, 1.0, 1.0, 1.0)
  let bounds = scene_rect(0.0, 0.0, 100.0, 100.0)
  let outside = gradient_test_gradient(90.0, black, -0.25, white, 1.25, Srgb)
  let reversed = gradient_test_gradient(90.0, black, 1.0, white, 0.0, Srgb)
  let ordinary = gradient_test_gradient(90.0, black, 0.0, white, 1.0, Srgb)
  let outside_left = gradient_test_sample(outside, 0.0, 50.0, bounds)
  let outside_right = gradient_test_sample(outside, 100.0, 50.0, bounds)
  assert_true(outside_left.red() > 0.0)
  assert_true(outside_right.red() < 1.0)
  assert_true(outside_left.red() < outside_right.red())
  assert_true(
    gradient_test_sample(reversed, 25.0, 50.0, bounds) ==
    gradient_test_sample(ordinary, 75.0, 50.0, bounds),
  )
  let extreme = gradient_test_gradient(
    90.0,
    black,
    -1.0e308,
    white,
    1.0e308,
    Srgb,
  )
  assert_true(
    gradient_test_near(
      gradient_test_sample(extreme, 50.0, 50.0, bounds).red(),
      0.21404114048223244,
    ),
  )
}

///|
test "equal stops use explicit first endpoint at boundary in both spaces" {
  let red = gradient_test_color(1.0, 0.0, 0.0, 0.25)
  let blue = gradient_test_color(0.0, 0.0, 1.0, 0.75)
  let bounds = scene_rect(0.0, 0.0, 161.0, 100.0)
  for space in [@scene.GradientColorSpace::Srgb, Oklab] {
    let gradient = gradient_test_gradient(90.0, red, 0.5, blue, 0.5, space)
    let before = gradient_test_sample(gradient, 79.5, 50.0, bounds)
    let exact = gradient_test_sample(gradient, 80.5, 50.0, bounds)
    let after = gradient_test_sample(gradient, 81.5, 50.0, bounds)
    assert_true(before.red() > 0.999999 && before.blue() < 0.000001)
    assert_true(exact.red() > 0.999999 && exact.blue() < 0.000001)
    assert_true(after.red() < 0.000001 && after.blue() > 0.999999)
    assert_true(before.alpha() == 0.25 && exact.alpha() == 0.25)
    assert_true(after.alpha() == 0.75)
  }
}

///|
test "sampling rejects degenerate and overflowing geometry" {
  let black = gradient_test_color(0.0, 0.0, 0.0, 1.0)
  let white = gradient_test_color(1.0, 1.0, 1.0, 1.0)
  let gradient = gradient_test_gradient(90.0, black, 0.0, white, 1.0, Srgb)
  let point = gradient_test_point(0.0, 0.0)
  assert_true(
    gradient.sample_shader_linear(point, scene_rect(0.0, 0.0, 0.0, 1.0))
    is Err(InvalidGeometry),
  )
  assert_true(
    gradient.sample_shader_linear(point, scene_rect(0.0, 0.0, 1.0, 0.0))
    is Err(InvalidGeometry),
  )
  assert_true(
    gradient.sample_shader_linear(
      gradient_test_point(-1.0e308, 0.0),
      scene_rect(1.0e308, 0.0, 1.0e307, 1.0),
    )
    is Err(InvalidGeometry),
  )
}
