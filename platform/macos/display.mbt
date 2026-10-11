///|
/// Copied metadata for one current macOS display. AppKit frame and visible
/// frame coordinates are global screen points; mode dimensions are pixels.
/// Array order is temporary and no display identifier is exposed. Refresh is
/// `None` when CoreGraphics reports that the current rate is unavailable.
pub(all) struct DisplayInfo {
  frame_x_points : Double
  frame_y_points : Double
  frame_width_points : Double
  frame_height_points : Double
  visible_x_points : Double
  visible_y_points : Double
  visible_width_points : Double
  visible_height_points : Double
  backing_scale_factor : Double
  mode_width_px : Int
  mode_height_px : Int
  refresh_rate_hz : Double?
  is_primary : Bool
  is_window_monitor : Bool
} derive(Eq)

///|
pub extend DisplayInfo with Eq::{not_equal, equal}

///|
const DISPLAY_SNAPSHOT_CAPACITY : Int = 16

///|
const DISPLAY_INFO_FIELDS : Int = 14

///|
fn exact_display_int(value : Double) -> Bool {
  !value.is_nan() &&
  !value.is_inf() &&
  value >= 0.0 &&
  value <= 2147483647.0 &&
  value.to_int().to_double() == value
}

///|
fn valid_display_number(value : Double) -> Bool {
  !value.is_nan() && !value.is_inf()
}

///|
fn display_decode_error(message : String) -> @diagnostics.FrameworkError {
  @diagnostics.FrameworkError::new(
    @diagnostics.ConversionFailed,
    "display_snapshot",
    backend="macos-metal",
    subsystem="display",
    message~,
  )
}

///|
/// Decode a bounded copy of current-screen metadata. Malformed records fail
/// closed instead of returning a partial display list.
fn decode_display_snapshot(
  records : FixedArray[Double],
  count : Int,
) -> Result[Array[DisplayInfo], @diagnostics.FrameworkError] {
  if count < 0 ||
    count > DISPLAY_SNAPSHOT_CAPACITY ||
    records.length() != DISPLAY_SNAPSHOT_CAPACITY * DISPLAY_INFO_FIELDS {
    return Err(display_decode_error("invalid display snapshot length"))
  }
  let displays : Array[DisplayInfo] = []
  let mut primary_count = 0
  let mut window_monitor_count = 0
  for index = 0; index < count; index = index + 1 {
    let base = index * DISPLAY_INFO_FIELDS
    let frame_x = records[base]
    let frame_y = records[base + 1]
    let frame_width = records[base + 2]
    let frame_height = records[base + 3]
    let visible_x = records[base + 4]
    let visible_y = records[base + 5]
    let visible_width = records[base + 6]
    let visible_height = records[base + 7]
    let scale = records[base + 8]
    let mode_width = records[base + 9]
    let mode_height = records[base + 10]
    let refresh = records[base + 11]
    let primary = records[base + 12]
    let window_monitor = records[base + 13]
    if !valid_display_number(frame_x) ||
      !valid_display_number(frame_y) ||
      !valid_display_number(visible_x) ||
      !valid_display_number(visible_y) ||
      !valid_display_number(frame_width) ||
      !valid_display_number(frame_height) ||
      !valid_display_number(visible_width) ||
      !valid_display_number(visible_height) ||
      frame_width <= 0.0 ||
      frame_height <= 0.0 ||
      visible_width <= 0.0 ||
      visible_height <= 0.0 ||
      !valid_display_number(scale) ||
      scale <= 0.0 ||
      scale > 8.0 ||
      !exact_display_int(mode_width) ||
      !exact_display_int(mode_height) ||
      mode_width <= 0.0 ||
      mode_height <= 0.0 ||
      !valid_display_number(refresh) ||
      refresh < 0.0 ||
      refresh > 1000.0 ||
      (primary != 0.0 && primary != 1.0) ||
      (window_monitor != 0.0 && window_monitor != 1.0) {
      return Err(display_decode_error("invalid display metadata"))
    }
    if primary == 1.0 {
      primary_count += 1
    }
    if window_monitor == 1.0 {
      window_monitor_count += 1
    }
    displays.push(DisplayInfo::{
      frame_x_points: frame_x,
      frame_y_points: frame_y,
      frame_width_points: frame_width,
      frame_height_points: frame_height,
      visible_x_points: visible_x,
      visible_y_points: visible_y,
      visible_width_points: visible_width,
      visible_height_points: visible_height,
      backing_scale_factor: scale,
      mode_width_px: mode_width.to_int(),
      mode_height_px: mode_height.to_int(),
      refresh_rate_hz: if refresh == 0.0 {
        None
      } else {
        Some(refresh)
      },
      is_primary: primary == 1.0,
      is_window_monitor: window_monitor == 1.0,
    })
  }
  if (count == 0 && primary_count != 0) ||
    (count > 0 && primary_count != 1) ||
    window_monitor_count > 1 {
    return Err(display_decode_error("inconsistent display flags"))
  }
  Ok(displays)
}

///|
/// Return copied metadata for the displays currently known to AppKit. Screen
/// frames use global points, mode sizes use CoreGraphics pixels, and refresh
/// is absent when the current mode does not report it. The bounded list has
/// temporary ordering and no persistent display identifier. When a GPUI key
/// window exists, its screen is marked; enumeration fails with `Busy` if the
/// display set changes while it is sampled.
pub fn Host::display_snapshot(
  self : Host,
) -> Result[Array[DisplayInfo], @diagnostics.FrameworkError] {
  match self.check() {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  let records = FixedArray::make(
    DISPLAY_SNAPSHOT_CAPACITY * DISPLAY_INFO_FIELDS,
    0.0,
  )
  let count = native_display_snapshot(self.marker, records, records.length())
  if count < 0 {
    match status(-count, "display_snapshot") {
      Err(error) =>
        Err(
          @diagnostics.FrameworkError::new(
            error.code(),
            "display_snapshot",
            backend="macos-metal",
            subsystem="display",
            message="CoreGraphics display enumeration failed or changed during sampling",
          ),
        )
      Ok(_) => Err(display_decode_error("invalid native display status"))
    }
  } else {
    decode_display_snapshot(records, count)
  }
}
