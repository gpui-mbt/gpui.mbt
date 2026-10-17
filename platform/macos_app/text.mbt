///|
/// Errors from scene-label painting through CoreText measurement.
pub(all) enum MacosTextPaintError {
  Text(@macos_text.MacosTextError)
  Scene(@scene.SceneBuilderError)
  UnsupportedText
  InvalidMetrics
} derive(Eq)

///|
pub extend MacosTextPaintError with Eq::{not_equal, equal}

///|
/// Copied logical metrics for one single-line system-sans run.
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
/// Bounded CoreText measurement cache for scene labels. A full cache clears
/// before inserting the next entry; measurement itself is never skipped.
pub struct MacosTextPainter {
  priv max_entries : Int32
  priv mut entries : Map[String, TextMetrics]
  priv mut entries_count : Int32
  priv mut hits : Int32
  priv mut misses : Int32
}

///|
pub fn MacosTextPainter::new(
  max_entries : Int32,
) -> Result[MacosTextPainter, MacosTextPaintError] {
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
  measurement : @text_layout.TextMeasurement,
  font_size : Double,
) -> TextMetrics {
  let logical = measurement.logical_rect()
  let ink = measurement.ink_rect()
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
  { width, line_height: height, }
}

///|
/// Measure a single-line system-sans run, reusing copied logical metrics for
/// repeated labels. Invalid font sizes and unsupported text return typed
/// CoreText errors.
pub fn MacosTextPainter::measure(
  self : MacosTextPainter,
  text : String,
  font_size : Double,
) -> Result[TextMetrics, MacosTextPaintError] {
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
      let measurement = match @macos_text.measure(document, "sans", font_size) {
        Err(error) => return Err(Text(error))
        Ok(value) => value
      }
      let metrics = painter_metrics(measurement, font_size)
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
pub fn MacosTextPainter::cache_hits(self : MacosTextPainter) -> Int32 {
  self.hits
}

///|
pub fn MacosTextPainter::cache_misses(self : MacosTextPainter) -> Int32 {
  self.misses
}

///|
pub fn MacosTextPainter::cache_entries(self : MacosTextPainter) -> Int32 {
  self.entries_count
}

///|
/// Append one measured, aligned text item to a SceneBuilder.
pub fn MacosTextPainter::label(
  self : MacosTextPainter,
  builder : @scene.SceneBuilder,
  bounds : @primitives.Rect,
  text : String,
  font_size : Double,
  color : @primitives.Color,
  align : @scene.TextAlign,
  vertical : @scene.TextVerticalAlign,
  clip_chain_id : Int32?,
) -> Result[Unit, MacosTextPaintError] {
  let metrics = match self.measure(text, font_size) {
    Err(error) => return Err(error)
    Ok(value) => value
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
/// CoreText measure/admit/hit callbacks for `controls/text_field` and
/// `controls/command_palette` on macOS. Font size is logical points.
pub struct MacosTextFieldAdapter {
  priv font_size : Double
}

///|
pub fn MacosTextFieldAdapter::new(
  font_size : Double,
) -> Result[MacosTextFieldAdapter, @text_field.TextFieldError] {
  if font_size.is_nan() ||
    font_size.is_inf() ||
    font_size <= 0.0 ||
    font_size > 32.0 {
    return Err(@text_field.InvalidFontSize)
  }
  Ok({ font_size, })
}

///|
pub fn MacosTextFieldAdapter::font_size(self : MacosTextFieldAdapter) -> Double {
  self.font_size
}

///|
pub fn MacosTextFieldAdapter::measure(
  self : MacosTextFieldAdapter,
  document : @text.TextDocument,
) -> Result[@text_layout.TextMeasurement, @text_field.TextFieldError] {
  match @macos_text.measure(document, "sans", self.font_size) {
    Err(_) => Err(@text_field.MeasurementFailed)
    Ok(value) => Ok(value)
  }
}

///|
pub fn MacosTextFieldAdapter::admit(
  self : MacosTextFieldAdapter,
  document : @text.TextDocument,
  measurement : @text_layout.TextMeasurement,
) -> Result[Unit, @text_field.TextFieldError] {
  ignore(self)
  if measurement.document() != document {
    return Err(@text_field.AdmissionFailed)
  }
  match @text_field.scene_text_run_geometry(measurement) {
    Err(_) => Err(@text_field.UnsupportedLayout)
    Ok(_) => Ok(())
  }
}

///|
/// Return the nearest validated caret stop for a field-local logical point.
pub fn MacosTextFieldAdapter::hit(
  self : MacosTextFieldAdapter,
  document : @text.TextDocument,
  point : @primitives.Point,
) -> Result[@text_layout.TextHit, @text_field.TextFieldError] {
  let measurement = match self.measure(document) {
    Err(error) => return Err(error)
    Ok(value) => value
  }
  let carets = measurement.carets()
  if carets.length() == 0 {
    return Err(@text_field.HitTestFailed)
  }
  let mut nearest_offset = carets[0].utf16_offset()
  let mut nearest_distance = if carets[0].strong().left() >= point.x() {
    carets[0].strong().left() - point.x()
  } else {
    point.x() - carets[0].strong().left()
  }
  for caret in carets {
    if caret.is_cursor_position() {
      let x = caret.strong().left()
      let distance = if x >= point.x() { x - point.x() } else { point.x() - x }
      if distance < nearest_distance {
        nearest_offset = caret.utf16_offset()
        nearest_distance = distance
      }
    }
  }
  ignore(nearest_distance)
  match
    @text_layout.TextHit::new(
      document, nearest_offset, 0, nearest_offset, true, true,
    ) {
    Ok(value) => Ok(value)
    Err(_) => Err(@text_field.HitTestFailed)
  }
}
