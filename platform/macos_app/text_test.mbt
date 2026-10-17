///|
fn macos_app_coretext_available() -> Bool {
  match @macos_text.require_grayscale_raster() {
    Ok(_) => true
    Err(_) => false
  }
}

///|
fn macos_app_rect(
  x : Double,
  y : Double,
  width : Double,
  height : Double,
) -> @primitives.Rect {
  @primitives.Rect::new(x, y, width, height).unwrap()
}

///|
fn macos_app_color() -> @primitives.Color {
  @primitives.Color::rgba(240, 242, 248, 255).unwrap()
}

///|
test "macOS text field adapter measures, admits and hits CoreText geometry" {
  if !macos_app_coretext_available() {
    return
  }
  let adapter = @macos_app.MacosTextFieldAdapter::new(16.0).unwrap()
  let document = @text.TextDocument::new("Hello").unwrap()
  let measurement = adapter.measure(document).unwrap()
  assert_true(measurement.logical_rect().size().width() > 0.0)
  assert_true(adapter.admit(document, measurement) is Ok(_))
  let point = @primitives.Point::new(0.0, 0.0).unwrap()
  let hit = adapter.hit(document, point).unwrap()
  assert_eq(hit.resolved_utf16_offset(), 0)
  assert_true(
    @macos_app.MacosTextFieldAdapter::new(0.0)
    is Err(@text_field.InvalidFontSize),
  )
  assert_true(
    @macos_app.MacosTextFieldAdapter::new(64.0)
    is Err(@text_field.InvalidFontSize),
  )
}

///|
test "macOS text painter caches bounded CoreText measurements" {
  if !macos_app_coretext_available() {
    return
  }
  let painter = @macos_app.MacosTextPainter::new(2).unwrap()
  let first = painter.measure("Hello", 16.0).unwrap()
  assert_true(first.width() > 0.0)
  assert_true(first.line_height() > 0.0)
  ignore(painter.measure("Hello", 16.0).unwrap())
  assert_eq(painter.cache_hits(), 1)
  assert_eq(painter.cache_misses(), 1)
  ignore(painter.measure("World", 16.0).unwrap())
  assert_eq(painter.cache_entries(), 2)
  ignore(painter.measure("Third", 16.0).unwrap())
  assert_eq(painter.cache_entries(), 1)
  assert_eq(painter.cache_misses(), 3)
  assert_true(painter.measure("Hello", 0.0) is Err(_))
  assert_true(@macos_app.MacosTextPainter::new(0) is Err(_))
}

///|
test "macOS text painter aligns CoreText labels in a scene builder" {
  if !macos_app_coretext_available() {
    return
  }
  let painter = @macos_app.MacosTextPainter::new(16).unwrap()
  let builder = @scene.SceneBuilder::new(
    macos_app_rect(0.0, 0.0, 100.0, 40.0),
    1.0,
  ).unwrap()
  let metrics = painter.measure("Centered", 16.0).unwrap()
  painter
  .label(
    builder,
    macos_app_rect(0.0, 0.0, 100.0, 40.0),
    "Centered",
    16.0,
    macos_app_color(),
    @scene.TextAlign::Center,
    @scene.TextVerticalAlign::Center,
    None,
  )
  .unwrap()
  let snapshot = match builder.snapshot() {
    Ok(value) => value
    Err(_) => abort("valid painter scene should snapshot")
  }
  match snapshot.items()[0] {
    @scene.TextItem(bounds~, text="Centered", ..) => {
      assert_eq(bounds.size().width(), metrics.width() + 2.0)
      assert_eq(bounds.left(), (100.0 - (metrics.width() + 2.0)) / 2.0)
      assert_eq(bounds.top(), (40.0 - metrics.line_height()) / 2.0)
    }
    _ => fail("painter should emit a text item")
  }
}
