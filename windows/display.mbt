///|
/// Copied metadata for one Windows monitor. Desktop and work-area geometry
/// use virtual-screen pixel coordinates in the host's per-monitor-v2 context.
/// Monitor order is ephemeral and is not an ID.
/// DPI is the effective DPI of this host's window monitor when available.
/// Other monitors have no DPI value in this snapshot. Mode refresh is the
/// integer Hertz value reported by Win32; zero means unavailable or default.
/// Physical panel dimensions are omitted because Win32 does not provide a
/// reliable value for every monitor.
pub(all) struct DisplayInfo {
  bounds_left_px : Int32
  bounds_top_px : Int32
  bounds_width_px : Int32
  bounds_height_px : Int32
  work_area_left_px : Int32
  work_area_top_px : Int32
  work_area_width_px : Int32
  work_area_height_px : Int32
  is_primary : Bool
  is_window_monitor : Bool
  has_effective_dpi : Bool
  effective_dpi_x : Int32
  effective_dpi_y : Int32
  has_current_mode : Bool
  mode_width_px : Int32
  mode_height_px : Int32
  refresh_rate_hz : Int32
  orientation_degrees : Int32
} derive(Eq)

///|
pub extend DisplayInfo with Eq::{not_equal, equal}

///|
#borrow(records)
extern "C" fn native_display_snapshot(
  host : Int32,
  records : FixedArray[Double],
  capacity : Int32,
) -> Int32 = "gpui_windows_display_snapshot"

///|
const DISPLAY_SNAPSHOT_CAPACITY : Int32 = 16

///|
const DISPLAY_INFO_FIELDS : Int32 = 18

///|
fn exact_display_int(value : Double) -> Bool {
  !value.is_nan() &&
  !value.is_inf() &&
  value >= -2147483648.0 &&
  value <= 2147483647.0 &&
  value.to_int().to_double() == value
}

///|
fn display_decode_error() -> @diagnostics.FrameworkError {
  @diagnostics.FrameworkError::new(
    @diagnostics.ConversionFailed,
    "display_snapshot",
    backend="windows-d3d11",
    subsystem="display",
  )
}

///|
/// Decode a copied, bounded native monitor list. Invalid or inconsistent
/// records fail closed rather than returning a partial snapshot.
fn decode_display_snapshot(
  records : FixedArray[Double],
  count : Int32,
) -> Result[Array[DisplayInfo], @diagnostics.FrameworkError] {
  if count < 0 ||
    count > DISPLAY_SNAPSHOT_CAPACITY ||
    records.length() != DISPLAY_SNAPSHOT_CAPACITY * DISPLAY_INFO_FIELDS {
    return Err(display_decode_error())
  }
  let displays : Array[DisplayInfo] = []
  let mut primary_count = 0
  let mut window_monitor_count = 0
  for index = 0; index < count; index = index + 1 {
    let base = index * DISPLAY_INFO_FIELDS
    for field = 0; field < DISPLAY_INFO_FIELDS; field = field + 1 {
      if !exact_display_int(records[base + field]) {
        return Err(display_decode_error())
      }
    }
    let bounds_width = records[base + 2].to_int()
    let bounds_height = records[base + 3].to_int()
    let work_width = records[base + 6].to_int()
    let work_height = records[base + 7].to_int()
    let is_primary = records[base + 8] == 1.0
    let is_window_monitor = records[base + 9] == 1.0
    let has_dpi = records[base + 10] == 1.0
    let dpi_x = records[base + 11].to_int()
    let dpi_y = records[base + 12].to_int()
    let has_mode = records[base + 13] == 1.0
    let mode_width = records[base + 14].to_int()
    let mode_height = records[base + 15].to_int()
    let refresh = records[base + 16].to_int()
    let orientation = records[base + 17].to_int()
    if records[base + 8] < 0.0 ||
      records[base + 8] > 1.0 ||
      records[base + 9] < 0.0 ||
      records[base + 9] > 1.0 ||
      records[base + 10] < 0.0 ||
      records[base + 10] > 1.0 ||
      records[base + 13] < 0.0 ||
      records[base + 13] > 1.0 ||
      bounds_width <= 0 ||
      bounds_height <= 0 ||
      work_width <= 0 ||
      work_height <= 0 ||
      dpi_x < 0 ||
      dpi_y < 0 ||
      (has_dpi && (dpi_x == 0 || dpi_y == 0)) ||
      (!has_dpi && (dpi_x != 0 || dpi_y != 0)) ||
      mode_width < 0 ||
      mode_height < 0 ||
      refresh < 0 ||
      (has_mode && (mode_width == 0 || mode_height == 0)) ||
      (!has_mode && (mode_width != 0 || mode_height != 0 || refresh != 0)) ||
      (
        orientation != -1 &&
        orientation != 0 &&
        orientation != 90 &&
        orientation != 180 &&
        orientation != 270
      ) {
      return Err(display_decode_error())
    }
    if is_primary {
      primary_count += 1
    }
    if is_window_monitor {
      window_monitor_count += 1
    }
    displays.push(DisplayInfo::{
      bounds_left_px: records[base].to_int(),
      bounds_top_px: records[base + 1].to_int(),
      bounds_width_px: bounds_width,
      bounds_height_px: bounds_height,
      work_area_left_px: records[base + 4].to_int(),
      work_area_top_px: records[base + 5].to_int(),
      work_area_width_px: work_width,
      work_area_height_px: work_height,
      is_primary,
      is_window_monitor,
      has_effective_dpi: has_dpi,
      effective_dpi_x: dpi_x,
      effective_dpi_y: dpi_y,
      has_current_mode: has_mode,
      mode_width_px: mode_width,
      mode_height_px: mode_height,
      refresh_rate_hz: refresh,
      orientation_degrees: orientation,
    })
  }
  if primary_count > 1 || window_monitor_count > 1 {
    return Err(display_decode_error())
  }
  Ok(displays)
}

///|
/// Return copied monitor geometry, the host window monitor's effective DPI
/// when a window exists, current modes, and primary / window-monitor flags.
/// Enumeration order can change between calls; the API does not expose durable
/// device IDs or infer physical panel dimensions.
pub fn Host::display_snapshot(
  self : Host,
) -> Result[Array[DisplayInfo], @diagnostics.FrameworkError] {
  let records = FixedArray::make(
    DISPLAY_SNAPSHOT_CAPACITY * DISPLAY_INFO_FIELDS,
    0.0,
  )
  let count = native_display_snapshot(self.token, records, records.length())
  if count < 0 {
    return Err(backend_error(-count, "display_snapshot"))
  }
  decode_display_snapshot(records, count)
}
