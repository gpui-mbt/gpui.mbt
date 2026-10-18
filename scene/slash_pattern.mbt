///|
/// Bounded model of GPUI's packed slash background. Authored dimensions are
/// retained; both must quantize to positive values and be at most 256 pixels.
/// This excludes undefined/overflowing upstream inputs, not valid legacy paint.
pub struct SlashPattern {
  color : @primitives.FloatColor
  width : Double
  interval : Double
} derive(Eq)

///|
pub extend SlashPattern with Eq::{equal, not_equal}

///|
pub fn SlashPattern::new(
  color : @primitives.FloatColor,
  width : Double,
  interval : Double,
) -> Result[SlashPattern, PaintError] {
  let pattern = SlashPattern::{ color, width, interval }
  match pattern.validate() {
    Ok(_) => Ok(pattern)
    Err(e) => Err(e)
  }
}

///|
fn slash_scaled(value : Double) -> Double {
  // Rust accepts f32 inputs and multiplies in f32 before truncating to u32.
  (value.to_float() * 255.0).to_double().to_int().to_double()
}

///|
pub fn SlashPattern::validate(self : SlashPattern) -> Result[Unit, PaintError] {
  if self.color.validate() is Err(_) {
    return Err(InvalidColor)
  }
  if !snapshot_finite(self.width) ||
    !snapshot_finite(self.interval) ||
    self.width <= 0.0 || self.width > 256.0 ||
    self.interval <= 0.0 || self.interval > 256.0 {
    return Err(InvalidPattern)
  }
  if slash_scaled(self.width) < 1.0 || slash_scaled(self.interval) < 1.0 {
    return Err(InvalidPattern)
  }
  Ok(())
}

///|
pub fn SlashPattern::color(self : SlashPattern) -> @primitives.FloatColor {
  self.color
}

///|
pub fn SlashPattern::width(self : SlashPattern) -> Double {
  self.width
}

///|
pub fn SlashPattern::interval(self : SlashPattern) -> Double {
  self.interval
}

///|
/// Exact integer packing followed by the upstream f32 transport rounding.
/// Double holds the bounded integer sum exactly, avoiding signed i32 overflow.
pub fn SlashPattern::packed(self : SlashPattern) -> Double {
  (slash_scaled(self.width) * 65535.0 + slash_scaled(self.interval))
  .to_float()
  .to_double()
}

///|
/// Sample unpremultiplied shader-linear RGB with stripe coverage in alpha.
/// Matches the pinned WGSL's non-floored width decode and signed remainder.
/// Packed transport is f32-exact; geometry uses Double as in LinearGradient,
/// so this is a numerical model, not a promise of bit-exact GPU edge pixels.
/// Bounds are the original quad, never its clipped visible rectangle.
pub fn SlashPattern::sample_shader_linear(
  self : SlashPattern,
  point : @primitives.Point,
  bounds : @primitives.Rect,
) -> Result[@primitives.FloatColor, PaintError] {
  match self.validate() {
    Err(e) => return Err(e)
    Ok(_) => ()
  }
  if bounds.size().width() <= 0.0 || bounds.size().height() <= 0.0 ||
    !paint_coordinate(bounds.left()) || !paint_coordinate(bounds.top()) ||
    !paint_coordinate(bounds.right()) || !paint_coordinate(bounds.bottom()) ||
    !paint_coordinate(point.x()) || !paint_coordinate(point.y()) {
    return Err(InvalidGeometry)
  }
  let packed = self.packed().to_float()
  let width = ((packed / 65535.0) / 255.0).to_double()
  let interval = ((packed % 65535.0) / 255.0).to_double()
  let height = width + interval
  let angle = 3.1415926 / 4.0
  let period = height * @math.sin(angle)
  let relative_x = point.x() - bounds.left()
  let relative_y = point.y() - bounds.top()
  // WGSL matrices are column-major: rotated.x = cos*x + sin*y.
  let phase = (@math.cos(angle) * relative_x + @math.sin(angle) * relative_y) % period
  let distance = (if phase < period - phase { phase } else { period - phase }) -
    period * (width / height) / 2.0
  let coverage = gradient_clamp(0.5 - distance)
  match @primitives.FloatColor::rgba(
    self.color.red(), self.color.green(), self.color.blue(),
    self.color.alpha() * coverage,
  ) {
    Ok(c) => Ok(c)
    Err(_) => Err(InvalidColor)
  }
}

///|
pub fn SlashPattern::sample(
  self : SlashPattern,
  point : @primitives.Point,
  bounds : @primitives.Rect,
) -> Result[@primitives.FloatColor, PaintError] {
  self.sample_shader_linear(point, bounds)
}

///|
pub fn SlashPattern::canonical_json(self : SlashPattern) -> String {
  "{\"color\":\{paint_float_json(self.color)},\"width\":\{snapshot_double(self.width)},\"interval\":\{snapshot_double(self.interval)},\"packed\":\{snapshot_double(self.packed())}}"
}
