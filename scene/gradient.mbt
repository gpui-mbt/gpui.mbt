///|
/// Color space used for unpremultiplied interpolation. Both modes accept and
/// return FloatColor values in the pinned shader's linear RGB domain.
pub(all) enum GradientColorSpace {
  Srgb
  Oklab
} derive(Eq)

///|
pub extend GradientColorSpace with Eq::{not_equal, equal}

///|
/// Exactly two authored stops. Positions are finite, but need not be sorted,
/// distinct, or inside [0, 1]. The finite angle is retained without normalization.
pub struct LinearGradient {
  angle : Double
  start : @primitives.FloatColor
  start_position : Double
  end : @primitives.FloatColor
  end_position : Double
  space : GradientColorSpace
} derive(Eq)

///|
pub extend LinearGradient with Eq::{not_equal, equal}

///|
pub fn LinearGradient::new(
  angle : Double,
  start : @primitives.FloatColor,
  start_position : Double,
  end : @primitives.FloatColor,
  end_position : Double,
  space : GradientColorSpace,
) -> Result[LinearGradient, PaintError] {
  let gradient = LinearGradient::{
    angle,
    start,
    start_position,
    end,
    end_position,
    space,
  }
  match gradient.validate() {
    Err(error) => Err(error)
    Ok(_) => Ok(gradient)
  }
}

///|
pub fn LinearGradient::validate(
  self : LinearGradient,
) -> Result[Unit, PaintError] {
  if !gradient_finite(self.angle) ||
    !gradient_finite(self.start_position) ||
    !gradient_finite(self.end_position) {
    Err(InvalidGradient)
  } else if self.start.validate() is Err(_) || self.end.validate() is Err(_) {
    Err(InvalidColor)
  } else {
    Ok(())
  }
}

///|
pub fn LinearGradient::angle(self : LinearGradient) -> Double {
  self.angle
}

///|
pub fn LinearGradient::start(self : LinearGradient) -> @primitives.FloatColor {
  self.start
}

///|
pub fn LinearGradient::start_position(self : LinearGradient) -> Double {
  self.start_position
}

///|
pub fn LinearGradient::end(self : LinearGradient) -> @primitives.FloatColor {
  self.end
}

///|
pub fn LinearGradient::end_position(self : LinearGradient) -> Double {
  self.end_position
}

///|
pub fn LinearGradient::space(self : LinearGradient) -> GradientColorSpace {
  self.space
}

///|
/// Sample the pinned GPUI WGSL projection and color-conversion formulas using
/// Double arithmetic. This is a numerical model, not bit-exact f32 GPU output.
/// Bounds must be finite with strictly positive extents. Points outside bounds
/// are allowed. Unrepresentable intermediate geometry is rejected.
///
/// The result is unpremultiplied linear shader-domain RGBA, before paint opacity
/// or compositing. Srgb converts linear endpoints to sRGB, mixes, then converts
/// back; Oklab mixes converted linear endpoints and returns linear RGB. Final RGB
/// is clamped to [0, 1] to fit FloatColor, including Oklab out-of-gamut results.
/// No output display encoding or byte rounding is performed.
///
/// Equal stop positions select the first endpoint when projected t <= the stop,
/// otherwise the second. This deterministic policy matches the observed pinned
/// SwiftShader WebGL2 equal-stop diagnostic; it is not a universal GPU NaN rule.
pub fn LinearGradient::sample_shader_linear(
  self : LinearGradient,
  point : @primitives.Point,
  bounds : @primitives.Rect,
) -> Result[@primitives.FloatColor, PaintError] {
  match self.validate() {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  let width = bounds.size().width()
  let height = bounds.size().height()
  if width <= 0.0 ||
    height <= 0.0 ||
    @primitives.Point::new(point.x(), point.y()) is Err(_) ||
    @primitives.Rect::new(bounds.left(), bounds.top(), width, height) is Err(_) {
    return Err(InvalidGeometry)
  }
  // Preserve the shader's literal M_PI_F rather than substituting Math.PI.
  let radians = (self.angle % 360.0 - 90.0) * 3.1415926 / 180.0
  let mut direction_x = @math.cos(radians)
  let mut direction_y = @math.sin(radians)
  if width > height {
    direction_y *= height / width
  } else {
    direction_x *= width / height
  }
  let direction_length = (direction_x * direction_x + direction_y * direction_y).sqrt()
  if !gradient_finite(direction_length) || direction_length <= 0.0 {
    return Err(InvalidGeometry)
  }
  let half_width = width / 2.0
  let half_height = height / 2.0
  let relative_x = point.x() - (bounds.left() + half_width)
  let relative_y = point.y() - (bounds.top() + half_height)
  let projected = (relative_x * direction_x + relative_y * direction_y) /
    direction_length
  let t = if direction_x.abs() > direction_y.abs() {
    (projected + half_width) / width
  } else {
    (projected + half_height) / height
  }
  if !gradient_finite(relative_x) ||
    !gradient_finite(relative_y) ||
    !gradient_finite(projected) ||
    !gradient_finite(t) {
    return Err(InvalidGeometry)
  }
  let fraction = gradient_stop_fraction(
    t,
    self.start_position,
    self.end_position,
  )
  let (red, green, blue) = match self.space {
    Srgb =>
      (
        gradient_srgb_to_linear(
          gradient_mix(
            gradient_linear_to_srgb(self.start.red()),
            gradient_linear_to_srgb(self.end.red()),
            fraction,
          ),
        ),
        gradient_srgb_to_linear(
          gradient_mix(
            gradient_linear_to_srgb(self.start.green()),
            gradient_linear_to_srgb(self.end.green()),
            fraction,
          ),
        ),
        gradient_srgb_to_linear(
          gradient_mix(
            gradient_linear_to_srgb(self.start.blue()),
            gradient_linear_to_srgb(self.end.blue()),
            fraction,
          ),
        ),
      )
    Oklab => {
      let (start_l, start_a, start_b) = gradient_linear_to_oklab(self.start)
      let (end_l, end_a, end_b) = gradient_linear_to_oklab(self.end)
      gradient_oklab_to_linear(
        gradient_mix(start_l, end_l, fraction),
        gradient_mix(start_a, end_a, fraction),
        gradient_mix(start_b, end_b, fraction),
      )
    }
  }
  let alpha = gradient_mix(self.start.alpha(), self.end.alpha(), fraction)
  match
    @primitives.FloatColor::rgba(
      gradient_clamp(red),
      gradient_clamp(green),
      gradient_clamp(blue),
      gradient_clamp(alpha),
    ) {
    Ok(color) => Ok(color)
    Err(_) => Err(InvalidColor)
  }
}

///|
/// Alias for sample_shader_linear. Returns unpremultiplied linear shader-domain
/// channels, with no display encoding, opacity composition, or byte conversion.
pub fn LinearGradient::sample(
  self : LinearGradient,
  point : @primitives.Point,
  bounds : @primitives.Rect,
) -> Result[@primitives.FloatColor, PaintError] {
  self.sample_shader_linear(point, bounds)
}

///|
fn gradient_finite(value : Double) -> Bool {
  !value.is_nan() && !value.is_inf()
}

///|
fn gradient_clamp(value : Double) -> Double {
  if value < 0.0 {
    0.0
  } else if value > 1.0 {
    1.0
  } else {
    value
  }
}

///|
fn gradient_stop_fraction(t : Double, start : Double, end : Double) -> Double {
  if start == end {
    if t <= start {
      0.0
    } else {
      1.0
    }
  } else if (start < end && t <= start) || (start > end && t >= start) {
    0.0
  } else if (start < end && t >= end) || (start > end && t <= end) {
    1.0
  } else {
    let span = end - start
    // Both stops may be finite although their subtraction overflows. Scaling
    // both differences equally retains their authored order and interpolation.
    let fraction = if gradient_finite(span) {
      (t - start) / span
    } else {
      (t / 2.0 - start / 2.0) / (end / 2.0 - start / 2.0)
    }
    gradient_clamp(fraction)
  }
}

///|
fn gradient_mix(start : Double, end : Double, t : Double) -> Double {
  start * (1.0 - t) + end * t
}

///|
fn gradient_linear_to_srgb(value : Double) -> Double {
  if value < 0.0031308 {
    value * 12.92
  } else {
    1.055 * @math.pow(value, 1.0 / 2.4) - 0.055
  }
}

///|
fn gradient_srgb_to_linear(value : Double) -> Double {
  if value < 0.04045 {
    value / 12.92
  } else {
    @math.pow((value + 0.055) / 1.055, 2.4)
  }
}

///|
fn gradient_linear_to_oklab(
  color : @primitives.FloatColor,
) -> (Double, Double, Double) {
  let l = 0.4122214708 * color.red() +
    0.5363325363 * color.green() +
    0.0514459929 * color.blue()
  let m = 0.2119034982 * color.red() +
    0.6806995451 * color.green() +
    0.1073969566 * color.blue()
  let s = 0.0883024619 * color.red() +
    0.2817188376 * color.green() +
    0.6299787005 * color.blue()
  let l_root = @math.pow(l, 1.0 / 3.0)
  let m_root = @math.pow(m, 1.0 / 3.0)
  let s_root = @math.pow(s, 1.0 / 3.0)
  (
    0.2104542553 * l_root + 0.7936177850 * m_root - 0.0040720468 * s_root,
    1.9779984951 * l_root - 2.4285922050 * m_root + 0.4505937099 * s_root,
    0.0259040371 * l_root + 0.7827717662 * m_root - 0.8086757660 * s_root,
  )
}

///|
fn gradient_oklab_to_linear(
  lab_l : Double,
  lab_a : Double,
  lab_b : Double,
) -> (Double, Double, Double) {
  let l_root = lab_l + 0.3963377774 * lab_a + 0.2158037573 * lab_b
  let m_root = lab_l - 0.1055613458 * lab_a - 0.0638541728 * lab_b
  let s_root = lab_l - 0.0894841775 * lab_a - 1.2914855480 * lab_b
  let l = l_root * l_root * l_root
  let m = m_root * m_root * m_root
  let s = s_root * s_root * s_root
  (
    4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s,
    -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
    -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s,
  )
}

///|
/// Stable authored-data serialization. Angles and stop positions are not sorted
/// or clamped; negative zero is represented as zero, as in existing snapshots.
pub fn LinearGradient::canonical_json(self : LinearGradient) -> String {
  let space = match self.space {
    Srgb => "srgb"
    Oklab => "oklab"
  }
  "{\"angle\":\{canonical_double(self.angle)},\"start\":{\"color\":\{gradient_float_color_json(self.start)},\"position\":\{canonical_double(self.start_position)}},\"end\":{\"color\":\{gradient_float_color_json(self.end)},\"position\":\{canonical_double(self.end_position)}},\"space\":\"\{space}\"}"
}

///|
fn gradient_float_color_json(color : @primitives.FloatColor) -> String {
  "{\"r\":\{canonical_double(color.red())},\"g\":\{canonical_double(color.green())},\"b\":\{canonical_double(color.blue())},\"a\":\{canonical_double(color.alpha())}}"
}
