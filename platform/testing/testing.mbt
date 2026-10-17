///|
/// A copied RGBA8 image of the most recently completed native presentation.
/// Pixels and coordinates use a top-left origin and logical content is scaled
/// into the physical dimensions reported here.
pub struct FrameCapture {
  priv width : Int32
  priv height : Int32
  priv scale : Double
  priv rgba8_top_left : Bytes
}

///|
/// Native hosts implement this seam only for opt-in E2E image evidence.
pub(open) trait FrameReadback {
  fn frame_metrics(Self, @platform.WindowId) -> Result[
    (Int32, Int32, Double),
    @diagnostics.FrameworkError,
  ]
  fn copy_frame(Self, @platform.WindowId, FixedArray[Byte]) -> Result[
    Unit,
    @diagnostics.FrameworkError,
  ]
}

///|
fn error(
  code : @diagnostics.ErrorCode,
  operation : String,
) -> @diagnostics.FrameworkError {
  @diagnostics.FrameworkError::new(
    code,
    operation,
    subsystem="native-testing",
    backend="platform-readback",
  )
}

///|
fn checked_byte_length(
  width : Int32,
  height : Int32,
  scale : Double,
) -> Result[Int32, @diagnostics.FrameworkError] {
  if width <= 0 ||
    height <= 0 ||
    width > 16384 ||
    height > 16384 ||
    scale.is_nan() ||
    scale.is_inf() ||
    scale <= 0.0 ||
    scale > 8.0 {
    return Err(error(@diagnostics.ConversionFailed, "frame_metrics"))
  }
  let pixel_count = width * height
  if pixel_count > 16 * 1024 * 1024 {
    return Err(error(@diagnostics.ResourceExhausted, "frame_metrics"))
  }
  Ok(pixel_count * 4)
}

///|
/// Read a native frame only when the process opted in with
/// `GPUI_NATIVE_E2E=1`. Host implementations copy the last completed GPU
/// buffer; this function validates all dimensions before allocating pixels.
pub fn[H : FrameReadback] capture_frame(
  host : H,
  window : @platform.WindowId,
) -> Result[FrameCapture, @diagnostics.FrameworkError] {
  if @env.get_env_var("GPUI_NATIVE_E2E") != Some("1") {
    return Err(error(@diagnostics.UnsupportedCapability, "capture_frame"))
  }
  let (width, height, scale) = match host.frame_metrics(window) {
    Ok(metrics) => metrics
    Err(failure) => return Err(failure)
  }
  let length = match checked_byte_length(width, height, scale) {
    Ok(value) => value
    Err(failure) => return Err(failure)
  }
  let output = FixedArray::make(length, b'\x00')
  match host.copy_frame(window, output) {
    Err(failure) => Err(failure)
    Ok(_) =>
      Ok({ width, height, scale, rgba8_top_left: Bytes::from_array(output), })
  }
}

///|
pub fn FrameCapture::width(self : FrameCapture) -> Int32 {
  self.width
}

///|
pub fn FrameCapture::height(self : FrameCapture) -> Int32 {
  self.height
}

///|
pub fn FrameCapture::scale(self : FrameCapture) -> Double {
  self.scale
}

///|
pub fn FrameCapture::rgba8_top_left(self : FrameCapture) -> Bytes {
  self.rgba8_top_left
}

///|
pub fn FrameCapture::pixel_rgba8(
  self : FrameCapture,
  x : Int32,
  y : Int32,
) -> Result[(Int32, Int32, Int32, Int32), @diagnostics.FrameworkError] {
  if x < 0 || x >= self.width || y < 0 || y >= self.height {
    return Err(error(@diagnostics.InvalidInput, "pixel_rgba8"))
  }
  let offset = (y * self.width + x) * 4
  Ok(
    (
      self.rgba8_top_left.unsafe_get(offset).to_int(),
      self.rgba8_top_left.unsafe_get(offset + 1).to_int(),
      self.rgba8_top_left.unsafe_get(offset + 2).to_int(),
      self.rgba8_top_left.unsafe_get(offset + 3).to_int(),
    ),
  )
}

///|
fn logical_finite(value : Double) -> Bool {
  !value.is_nan() && !value.is_inf()
}

///|
fn clamp_capture_coord(value : Int32, high : Int32) -> Int32 {
  if value < 0 {
    0
  } else if value > high {
    high
  } else {
    value
  }
}

///|
/// Read a physical pixel using logical content coordinates. The bottom-right
/// edge is exclusive, matching element hit testing and frame layout.
pub fn FrameCapture::pixel_rgba8_logical(
  self : FrameCapture,
  x : Double,
  y : Double,
) -> Result[(Int32, Int32, Int32, Int32), @diagnostics.FrameworkError] {
  if !logical_finite(x) || !logical_finite(y) {
    return Err(error(@diagnostics.InvalidInput, "pixel_rgba8_logical"))
  }
  let px = (x * self.scale).floor().to_int()
  let py = (y * self.scale).floor().to_int()
  self.pixel_rgba8(px, py)
}

///|
/// Compare one logical pixel with an expected RGB triplet using a per-channel
/// tolerance. Alpha is intentionally ignored; native fixtures are opaque.
pub fn FrameCapture::pixel_matches_logical(
  self : FrameCapture,
  x : Double,
  y : Double,
  red : Int32,
  green : Int32,
  blue : Int32,
  tolerance : Int32,
) -> Result[Bool, @diagnostics.FrameworkError] {
  if tolerance < 0 || tolerance > 255 {
    return Err(error(@diagnostics.InvalidInput, "pixel_matches_logical"))
  }
  let pixel = self.pixel_rgba8_logical(x, y)
  match pixel {
    Err(failure) => Err(failure)
    Ok((actual_red, actual_green, actual_blue, _alpha)) => {
      let dr = if actual_red >= red {
        actual_red - red
      } else {
        red - actual_red
      }
      let dg = if actual_green >= green {
        actual_green - green
      } else {
        green - actual_green
      }
      let db = if actual_blue >= blue {
        actual_blue - blue
      } else {
        blue - actual_blue
      }
      Ok(dr <= tolerance && dg <= tolerance && db <= tolerance)
    }
  }
}

///|
/// True when any pixel inside the logical rectangle differs between two
/// captures. Both captures must have identical physical dimensions and scale.
pub fn FrameCapture::region_differs(
  self : FrameCapture,
  other : FrameCapture,
  rect : @primitives.Rect,
) -> Result[Bool, @diagnostics.FrameworkError] {
  if self.width != other.width ||
    self.height != other.height ||
    self.scale != other.scale {
    return Err(error(@diagnostics.ConversionFailed, "region_differs"))
  }
  if !logical_finite(rect.left()) ||
    !logical_finite(rect.top()) ||
    !logical_finite(rect.right()) ||
    !logical_finite(rect.bottom()) {
    return Err(error(@diagnostics.InvalidInput, "region_differs"))
  }
  let x0 = clamp_capture_coord(
    (rect.left() * self.scale).floor().to_int(),
    self.width,
  )
  let y0 = clamp_capture_coord(
    (rect.top() * self.scale).floor().to_int(),
    self.height,
  )
  let x1 = clamp_capture_coord(
    (rect.right() * self.scale).ceil().to_int(),
    self.width,
  )
  let y1 = clamp_capture_coord(
    (rect.bottom() * self.scale).ceil().to_int(),
    self.height,
  )
  if x1 <= x0 || y1 <= y0 {
    return Ok(false)
  }
  let old_pixels = self.rgba8_top_left
  let new_pixels = other.rgba8_top_left
  let mut changed = false
  let mut y = y0
  while y < y1 && !changed {
    let mut x = x0
    while x < x1 && !changed {
      let offset = (y * self.width + x) * 4
      if old_pixels.unsafe_get(offset) != new_pixels.unsafe_get(offset) ||
        old_pixels.unsafe_get(offset + 1) != new_pixels.unsafe_get(offset + 1) ||
        old_pixels.unsafe_get(offset + 2) != new_pixels.unsafe_get(offset + 2) ||
        old_pixels.unsafe_get(offset + 3) != new_pixels.unsafe_get(offset + 3) {
        changed = true
      }
      x += 1
    }
    y += 1
  }
  Ok(changed)
}

///|
/// Count opaque pixels inside a logical rectangle whose average RGB channel is
/// at least `min_luminance`. Useful for checking that text or an icon produced
/// visible ink without pinning every antialiased pixel.
pub fn FrameCapture::ink_count(
  self : FrameCapture,
  rect : @primitives.Rect,
  min_luminance : Int32,
) -> Result[Int32, @diagnostics.FrameworkError] {
  if min_luminance < 0 || min_luminance > 255 {
    return Err(error(@diagnostics.InvalidInput, "ink_count"))
  }
  if !logical_finite(rect.left()) ||
    !logical_finite(rect.top()) ||
    !logical_finite(rect.right()) ||
    !logical_finite(rect.bottom()) {
    return Err(error(@diagnostics.InvalidInput, "ink_count"))
  }
  let x0 = clamp_capture_coord(
    (rect.left() * self.scale).floor().to_int(),
    self.width,
  )
  let y0 = clamp_capture_coord(
    (rect.top() * self.scale).floor().to_int(),
    self.height,
  )
  let x1 = clamp_capture_coord(
    (rect.right() * self.scale).ceil().to_int(),
    self.width,
  )
  let y1 = clamp_capture_coord(
    (rect.bottom() * self.scale).ceil().to_int(),
    self.height,
  )
  let mut count : Int32 = 0
  if x1 <= x0 || y1 <= y0 {
    return Ok(count)
  }
  let pixels = self.rgba8_top_left
  let mut y = y0
  while y < y1 {
    let mut x = x0
    while x < x1 {
      let offset = (y * self.width + x) * 4
      let red = pixels.unsafe_get(offset).to_int()
      let green = pixels.unsafe_get(offset + 1).to_int()
      let blue = pixels.unsafe_get(offset + 2).to_int()
      let alpha = pixels.unsafe_get(offset + 3).to_int()
      if alpha >= 240 && (red + green + blue) / 3 >= min_luminance {
        count += 1
      }
      x += 1
    }
    y += 1
  }
  Ok(count)
}
