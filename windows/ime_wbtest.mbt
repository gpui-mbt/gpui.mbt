///|
fn ime_test_rect(
  x : Double,
  y : Double,
  width : Double,
  height : Double,
) -> @primitives.Rect {
  match @primitives.Rect::new(x, y, width, height) {
    Ok(value) => value
    Err(_) => abort("fixture rectangle was rejected")
  }
}

///|
fn ime_test_repeat(character : Char, count : Int32) -> String {
  let builder = StringBuilder()
  for _ in 0..<count {
    builder.write_char(character)
  }
  builder.to_string()
}

///|
test "Windows composition caret validation rejects invalid geometry" {
  let valid = ime_test_rect(12.0, 8.0, 2.0, 18.0)
  assert_true(composition_rect_valid(valid, "test") is Ok(_))
  let zero_width = ime_test_rect(12.0, 8.0, 0.0, 18.0)
  assert_true(composition_rect_valid(zero_width, "test") is Err(_))
  let zero_height = ime_test_rect(12.0, 8.0, 2.0, 0.0)
  assert_true(composition_rect_valid(zero_height, "test") is Err(_))
  let fractional = ime_test_rect(12.0, 8.0, 1.5, 18.0)
  assert_true(composition_rect_valid(fractional, "test") is Err(_))
  let oversized = ime_test_rect(12.0, 8.0, 8193.0, 18.0)
  assert_true(composition_rect_valid(oversized, "test") is Err(_))
}

///|
test "Windows composition window tokens require positive Int32 values" {
  assert_true(
    session_window_token(@platform.WindowId::new(1L), "test") is Ok(1),
  )
  assert_true(
    session_window_token(@platform.WindowId::new(0L), "test") is Err(_),
  )
  assert_true(
    session_window_token(@platform.WindowId::new(-1L), "test") is Err(_),
  )
  assert_true(
    session_window_token(@platform.WindowId::new(2147483648L), "test") is Err(_),
  )
}

///|
test "Windows composition decoder maps the four portable states" {
  assert_true(
    decode_composition_event(0, 0.0, 0.0, "", "test")
    is Ok(@platform.Composition(@primitives.Start)),
  )
  assert_true(
    decode_composition_event(1, 4.0, 4.0, "にほんご", "test")
    is Ok(
      @platform.Composition(
        @primitives.Update(text="にほんご", cursor_utf16=4)
      )
    ),
  )
  assert_true(
    decode_composition_event(2, 3.0, 0.0, "日本語", "test")
    is Ok(@platform.Composition(@primitives.Commit(text="日本語"))),
  )
  assert_true(
    decode_composition_event(3, 0.0, 0.0, "", "test")
    is Ok(@platform.Composition(@primitives.Cancel)),
  )
}

///|
test "Windows composition decoder preserves UTF-16 cursor boundaries" {
  assert_true(
    decode_composition_event(1, 2.0, 2.0, "😀", "test")
    is Ok(
      @platform.Composition(@primitives.Update(text="😀", cursor_utf16=2))
    ),
  )
  assert_true(decode_composition_event(1, 2.0, 1.0, "😀", "test") is Err(_))
  assert_true(decode_composition_event(1, 2.0, 3.0, "😀", "test") is Err(_))
  assert_true(decode_composition_event(1, 2.0, 0.0, "あ", "test") is Err(_))
}

///|
test "Windows composition decoder treats empty preedit as cancel" {
  assert_true(
    decode_composition_event(1, 0.0, 0.0, "", "test")
    is Ok(@platform.Composition(@primitives.Cancel)),
  )
  assert_true(decode_composition_event(1, 0.0, 1.0, "", "test") is Err(_))
}

///|
test "Windows composition decoder enforces preedit and commit limits" {
  let preedit = ime_test_repeat('a', 16_385)
  assert_true(
    decode_composition_event(1, 16_385.0, 16_385.0, preedit, "test") is Err(_),
  )
  let commit = ime_test_repeat('a', 65_537)
  assert_true(
    decode_composition_event(2, 65_537.0, 0.0, commit, "test") is Err(_),
  )
  let max_preedit = ime_test_repeat('a', 16_384)
  assert_true(
    decode_composition_event(1, 16_384.0, 16_384.0, max_preedit, "test")
    is Ok(_),
  )
  let max_commit = ime_test_repeat('a', 65_536)
  assert_true(
    decode_composition_event(2, 65_536.0, 0.0, max_commit, "test") is Ok(_),
  )
}

///|
test "Windows composition decoder rejects malformed frames" {
  assert_true(decode_composition_event(4, 0.0, 0.0, "", "test") is Err(_))
  assert_true(decode_composition_event(0, 1.0, 0.0, "a", "test") is Err(_))
  assert_true(decode_composition_event(2, 1.0, 1.0, "a", "test") is Err(_))
  assert_true(decode_composition_event(3, 0.0, 0.0, "a", "test") is Err(_))
  assert_true(decode_composition_event(1, 1.5, 0.0, "a", "test") is Err(_))
}
