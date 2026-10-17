///|
/// Errors from scene-label painting through DirectWrite measurement.
pub(all) enum WindowsTextPaintError {
  Text(@windows_text.WindowsTextError)
  Scene(@scene.SceneBuilderError)
  UnsupportedText
  InvalidMetrics
} derive(Eq)

///|
pub extend WindowsTextPaintError with Eq::{not_equal, equal}

///|
/// Copied logical metrics for one single-line Segoe UI run.
pub(all) struct TextMetrics {
  width : Double
  line_height : Double
}

///|
pub fn TextMetrics::width(self : TextMetrics) -> Double {
  self.width
}

///|
pub fn TextMetrics::line_height(self : TextMetrics) -> Double {
  self.line_height
}

///|
/// Bounded DirectWrite measurement cache for scene labels. A full cache clears
/// before inserting the next entry; measurement itself is never skipped.
pub struct WindowsTextPainter {
  priv max_entries : Int32
  priv mut entries : Map[String, TextMetrics]
  priv mut entries_count : Int32
  priv mut hits : Int32
  priv mut misses : Int32
}

///|
pub fn WindowsTextPainter::new(
  max_entries : Int32,
) -> Result[WindowsTextPainter, WindowsTextPaintError] {
  if max_entries <= 0 || max_entries > 4096 {
    return Err(InvalidMetrics)
  }
  Ok({ max_entries, entries: Map([]), entries_count: 0, hits: 0, misses: 0, })
}

///|
fn painter_key(text : String, font_size : Double) -> String {
  "\{font_size}:\{text}"
}

///|
fn painter_metrics(
  logical : @primitives.Rect,
  ink : @primitives.Rect,
  unknown_glyph_count : Int32,
  font_size : Double,
) -> Result[TextMetrics, WindowsTextPaintError] {
  if unknown_glyph_count > 0 {
    return Err(UnsupportedText)
  }
  // Legacy scene labels cannot represent an origin separate from their clip
  // bounds. Reject overhanging ink rather than silently cropping it.
  if ink.left() < 0.0 || ink.top() < 0.0 {
    return Err(UnsupportedText)
  }
  let mut width = logical.right()
  if ink.right() > width {
    width = ink.right()
  }
  let mut height = logical.bottom()
  if ink.bottom() > height {
    height = ink.bottom()
  }
  if width < 0.0 {
    width = 0.0
  }
  if height <= 0.0 {
    height = font_size
  }
  Ok({ width, line_height: height, })
}

///|
/// Measure a single-line Segoe UI run, reusing copied logical metrics for
/// repeated labels. Invalid font sizes and unsupported text return typed
/// DirectWrite errors.
pub fn WindowsTextPainter::measure(
  self : WindowsTextPainter,
  text : String,
  font_size : Double,
) -> Result[TextMetrics, WindowsTextPaintError] {
  if font_size.is_nan() ||
    font_size.is_inf() ||
    font_size <= 0.0 ||
    font_size > @windows_text.max_scene_font_size_px {
    return Err(InvalidMetrics)
  }
  let key = painter_key(text, font_size)
  match self.entries.get(key) {
    Some(value) => {
      self.hits += 1
      Ok(value)
    }
    None => {
      let document = match @text.TextDocument::new(text) {
        Ok(value) => value
        Err(_) => return Err(UnsupportedText)
      }
      let measurement = match
        @windows_text.measure(document, "Segoe UI", font_size) {
        Err(error) => return Err(Text(error))
        Ok(value) => value
      }
      let metrics = match
        painter_metrics(
          measurement.logical_rect(),
          measurement.ink_rect(),
          measurement.unknown_glyph_count(),
          font_size,
        ) {
        Err(error) => return Err(error)
        Ok(value) => value
      }
      if self.entries_count >= self.max_entries {
        self.entries = Map([])
        self.entries_count = 0
      }
      self.entries[key] = metrics
      self.entries_count += 1
      self.misses += 1
      Ok(metrics)
    }
  }
}

///|
pub fn WindowsTextPainter::cache_hits(self : WindowsTextPainter) -> Int32 {
  self.hits
}

///|
pub fn WindowsTextPainter::cache_misses(self : WindowsTextPainter) -> Int32 {
  self.misses
}

///|
pub fn WindowsTextPainter::cache_entries(self : WindowsTextPainter) -> Int32 {
  self.entries_count
}

///|
fn painter_label_input(
  text : String,
  font_size : Double,
) -> Result[Unit, WindowsTextPaintError] {
  if font_size.is_nan() ||
    font_size.is_inf() ||
    font_size <= 0.0 ||
    font_size > @windows_text.max_scene_font_size_px {
    return Err(InvalidMetrics)
  }
  let document = match @text.TextDocument::new(text) {
    Err(_) => return Err(UnsupportedText)
    Ok(value) => value
  }
  match document.utf8_length() {
    Ok(length) if length <= @windows_text.max_scene_text_bytes => Ok(())
    _ => Err(UnsupportedText)
  }
}

///|
fn painter_label_bounds_valid(
  bounds : @primitives.Rect,
  metrics : TextMetrics,
  align : @scene.TextAlign,
  vertical : @scene.TextVerticalAlign,
) -> Bool {
  let width = if metrics.width <= 0.0 { 1.0 } else { metrics.width + 2.0 }
  let height = metrics.line_height
  let x = match align {
    Left => bounds.left()
    Center => bounds.left() + (bounds.size().width() - width) / 2.0
    Right => bounds.right() - width
  }
  let y = match vertical {
    Top => bounds.top()
    Center => bounds.top() + (bounds.size().height() - height) / 2.0
    Bottom => bounds.bottom() - height
  }
  !width.is_nan() &&
  !width.is_inf() &&
  width <= 2048.0 &&
  !height.is_nan() &&
  !height.is_inf() &&
  height > 0.0 &&
  height <= 128.0 &&
  !x.is_nan() &&
  !x.is_inf() &&
  x >= -1000000000.0 &&
  x <= 1000000000.0 &&
  !y.is_nan() &&
  !y.is_inf() &&
  y >= -1000000000.0 &&
  y <= 1000000000.0
}

///|
/// Append one measured, aligned text item to a SceneBuilder.
/// Reject inputs outside the native label renderer's bounded text subset.
pub fn WindowsTextPainter::label(
  self : WindowsTextPainter,
  builder : @scene.SceneBuilder,
  bounds : @primitives.Rect,
  text : String,
  font_size : Double,
  color : @primitives.Color,
  align : @scene.TextAlign,
  vertical : @scene.TextVerticalAlign,
  clip_chain_id : Int32?,
) -> Result[Unit, WindowsTextPaintError] {
  match painter_label_input(text, font_size) {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  let metrics = match self.measure(text, font_size) {
    Err(error) => return Err(error)
    Ok(value) => value
  }
  if !painter_label_bounds_valid(bounds, metrics, align, vertical) {
    return Err(InvalidMetrics)
  }
  match
    builder.text(
      bounds,
      text,
      font_size,
      color,
      align,
      vertical,
      metrics.width,
      metrics.line_height,
      clip_chain_id,
    ) {
    Err(error) => Err(Scene(error))
    Ok(_) => Ok(())
  }
}

///|
/// DirectWrite measure/admit/hit callbacks for `controls/text_field` and
/// `controls/command_palette` on Windows. Font size is logical pixels.
pub struct WindowsTextFieldAdapter {
  priv font_size : Double
}

///|
pub fn WindowsTextFieldAdapter::new(
  font_size : Double,
) -> Result[WindowsTextFieldAdapter, @text_field.TextFieldError] {
  if font_size.is_nan() ||
    font_size.is_inf() ||
    font_size <= 0.0 ||
    font_size > @windows_text.max_scene_font_size_px {
    return Err(@text_field.InvalidFontSize)
  }
  Ok({ font_size, })
}

///|
pub fn WindowsTextFieldAdapter::font_size(
  self : WindowsTextFieldAdapter,
) -> Double {
  self.font_size
}

///|
pub fn WindowsTextFieldAdapter::measure(
  self : WindowsTextFieldAdapter,
  document : @text.TextDocument,
) -> Result[@text_layout.TextMeasurement, @text_field.TextFieldError] {
  match @windows_text.measure(document, "Segoe UI", self.font_size) {
    Err(_) => Err(@text_field.MeasurementFailed)
    Ok(value) => Ok(value)
  }
}

///|
pub fn WindowsTextFieldAdapter::admit(
  self : WindowsTextFieldAdapter,
  document : @text.TextDocument,
  measurement : @text_layout.TextMeasurement,
) -> Result[Unit, @text_field.TextFieldError] {
  if measurement.document() != document {
    return Err(@text_field.AdmissionFailed)
  }
  let (origin, clip_rect) = match
    @text_field.scene_text_run_geometry(measurement) {
    Err(_) => return Err(@text_field.UnsupportedLayout)
    Ok(value) => value
  }
  match
    @windows_text.admit_scene_text_run_at(
      document,
      self.font_size,
      origin,
      clip_rect,
    ) {
    Ok(_) => Ok(())
    Err(_) => Err(@text_field.AdmissionFailed)
  }
}

///|
/// Return the DirectWrite cluster hit for a field-local logical point.
pub fn WindowsTextFieldAdapter::hit(
  self : WindowsTextFieldAdapter,
  document : @text.TextDocument,
  point : @primitives.Point,
) -> Result[@text_layout.TextHit, @text_field.TextFieldError] {
  match @windows_text.hit_test(document, "Segoe UI", self.font_size, point) {
    Err(_) => Err(@text_field.HitTestFailed)
    Ok(value) => Ok(value)
  }
}
