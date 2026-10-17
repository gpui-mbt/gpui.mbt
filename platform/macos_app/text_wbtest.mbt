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
test "label inputs obey native font and UTF8 byte bounds without CoreText" {
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
test "label metrics reject unknown glyphs and negative ink bearings" {
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
test "label bounds use padded width and final aligned origin" {
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
  let edge = painter_test_rect(1000000000.0, 1000000000.0, 10.0, 10.0)
  let small = { width: 1.0, line_height: 1.0, }
  assert_true(painter_label_bounds_valid(edge, small, Left, Top))
  assert_false(painter_label_bounds_valid(edge, small, Center, Top))
  assert_false(painter_label_bounds_valid(edge, small, Right, Top))
  assert_false(painter_label_bounds_valid(edge, small, Left, Center))
  assert_false(painter_label_bounds_valid(edge, small, Left, Bottom))
  let negative = painter_test_rect(-1000000000.0, -1000000000.0, 1.0, 1.0)
  assert_true(painter_label_bounds_valid(negative, small, Left, Top))
  assert_false(painter_label_bounds_valid(negative, small, Center, Top))
  assert_false(
    painter_label_bounds_valid(
      negative,
      { width: 0.0, line_height: 2.0, },
      Left,
      Bottom,
    ),
  )
}
