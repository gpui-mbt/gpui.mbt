///|
fn painter_test_rect(
  x : Double,
  y : Double,
  w : Double,
  h : Double,
) -> @primitives.Rect {
  @primitives.Rect::new(x, y, w, h).unwrap()
}

///|
test "Windows label inputs obey native font and UTF8 byte bounds" {
  assert_true(painter_label_input("Hello", 32.0) is Ok(_))
  assert_true(painter_label_input("Hello", 32.01) is Err(InvalidMetrics))
  assert_true(painter_label_input("Hello", 0.0) is Err(InvalidMetrics))
  assert_true(painter_label_input("Hello", 0.0 / 0.0) is Err(InvalidMetrics))
  assert_true(painter_label_input("Hello", 1.0 / 0.0) is Err(InvalidMetrics))
  let ascii = "a".repeat(4096)
  assert_true(painter_label_input(ascii, 16.0) is Ok(_))
  assert_true(painter_label_input(ascii + "a", 16.0) is Err(UnsupportedText))
  assert_true(painter_label_input("é".repeat(2048), 16.0) is Ok(_))
  assert_true(
    painter_label_input("é".repeat(2049), 16.0) is Err(UnsupportedText),
  )
}

///|
test "Windows label metrics reject unknown glyphs and negative ink bearings" {
  let logical = painter_test_rect(0.0, 0.0, 20.0, 18.0)
  let ink = painter_test_rect(0.0, 0.0, 20.0, 18.0)
  assert_true(painter_metrics(logical, ink, 0, 16.0) is Ok(_))
  assert_true(painter_metrics(logical, ink, 1, 16.0) is Err(UnsupportedText))
  assert_true(
    painter_metrics(logical, painter_test_rect(-0.25, 0.0, 20.0, 18.0), 0, 16.0)
    is Err(UnsupportedText),
  )
  assert_true(
    painter_metrics(logical, painter_test_rect(0.0, -0.25, 20.0, 18.0), 0, 16.0)
    is Err(UnsupportedText),
  )
}

///|
test "Windows label bounds use padded width and final aligned origin" {
  let bounds = painter_test_rect(0.0, 0.0, 10.0, 10.0)
  assert_true(
    painter_label_bounds_valid(
      bounds,
      { width: 2046.0, line_height: 128.0, },
      Left,
      Top,
    ),
  )
  assert_false(
    painter_label_bounds_valid(
      bounds,
      { width: 2046.01, line_height: 128.0, },
      Left,
      Top,
    ),
  )
  assert_false(
    painter_label_bounds_valid(
      bounds,
      { width: 2046.0, line_height: 128.01, },
      Left,
      Top,
    ),
  )
}

///|
test "Windows scene painter measures and caches on DirectWrite hosts" {
  let painter = match WindowsTextPainter::new(8) {
    Ok(value) => value
    Err(_) => fail("painter")
  }
  match painter.measure("Hello", 16.0) {
    Err(Text(@windows_text.UnsupportedPlatform)) => ()
    Err(_) => fail("DirectWrite measurement")
    Ok(first) => {
      assert_true(first.width() > 0.0)
      assert_true(first.line_height() > 0.0)
      assert_eq(painter.cache_misses(), 1)
      match painter.measure("Hello", 16.0) {
        Ok(second) => {
          assert_eq(second.width(), first.width())
          assert_eq(painter.cache_hits(), 1)
          assert_eq(painter.cache_entries(), 1)
        }
        Err(_) => fail("cached measurement")
      }
    }
  }
}

///|
test "Windows field adapter rejects invalid styles before DirectWrite" {
  assert_true(
    WindowsTextFieldAdapter::new(0.0) is Err(@text_field.InvalidFontSize),
  )
  assert_true(
    WindowsTextFieldAdapter::new(33.0) is Err(@text_field.InvalidFontSize),
  )
  let adapter = match WindowsTextFieldAdapter::new(16.0) {
    Ok(value) => value
    Err(_) => fail("adapter")
  }
  assert_eq(adapter.font_size(), 16.0)
}

///|
test "Windows window configuration validates bounded dimensions" {
  assert_true(WindowsWindowConfig::new("demo", 640.0, 400.0) is Ok(_))
  assert_true(WindowsWindowConfig::new("", 640.0, 400.0) is Err(_))
  assert_true(WindowsWindowConfig::new("demo", 0.0, 400.0) is Err(_))
  assert_true(WindowsWindowConfig::new("demo", 640.0, 8193.0) is Err(_))
  assert_true(
    WindowsWindowConfig::new("demo", 640.0, 400.0, require_text=false) is Ok(_),
  )
}
