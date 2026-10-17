///|
/// A floating-point channel that is not finite or lies outside [0, 1].
pub enum FloatColorError {
  InvalidChannel
} derive(Eq)

///|
pub extend FloatColorError with Eq::{not_equal, equal}

///|
/// Unpremultiplied floating-point RGBA in the pinned GPUI shader's linear RGB
/// domain. This is distinct from the legacy byte-based sRGB `Color` type.
/// Channels retain their authored Double values; construction never quantizes
/// through bytes or applies a display transfer function.
pub struct FloatColor {
  red : Double
  green : Double
  blue : Double
  alpha : Double
} derive(Eq)

///|
pub extend FloatColor with Eq::{not_equal, equal}

///|
/// Construct an unpremultiplied color from finite channels in [0, 1].
pub fn FloatColor::rgba(
  red : Double,
  green : Double,
  blue : Double,
  alpha : Double,
) -> Result[FloatColor, FloatColorError] {
  let color = FloatColor::{ red, green, blue, alpha, }
  match color.validate() {
    Err(error) => Err(error)
    Ok(_) => Ok(color)
  }
}

///|
/// Recheck channel invariants at a serialization or paint boundary.
pub fn FloatColor::validate(self : FloatColor) -> Result[Unit, FloatColorError] {
  if !float_color_channel_valid(self.red) ||
    !float_color_channel_valid(self.green) ||
    !float_color_channel_valid(self.blue) ||
    !float_color_channel_valid(self.alpha) {
    Err(InvalidChannel)
  } else {
    Ok(())
  }
}

///|
fn float_color_channel_valid(value : Double) -> Bool {
  !value.is_nan() && !value.is_inf() && value >= 0.0 && value <= 1.0
}

///|
pub fn FloatColor::red(self : FloatColor) -> Double {
  self.red
}

///|
pub fn FloatColor::green(self : FloatColor) -> Double {
  self.green
}

///|
pub fn FloatColor::blue(self : FloatColor) -> Double {
  self.blue
}

///|
pub fn FloatColor::alpha(self : FloatColor) -> Double {
  self.alpha
}

///|
pub fn FloatColor::is_opaque(self : FloatColor) -> Bool {
  self.alpha == 1.0
}
