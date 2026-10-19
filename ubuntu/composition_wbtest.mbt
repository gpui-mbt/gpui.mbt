///|
fn composition_test_record(tag : Int32, source : String) -> FixedArray[Double] {
  let data = ime_test_record(tag, source)
  data[13] = 0.0
  data
}

///|
fn composition_test_event(
  data : FixedArray[Double],
  source : String,
) -> @platform.Event raise {
  match ime_test_decode(data, @utf8.encode(source)) {
    Ok(Some(Platform(event))) => event
    _ => fail("expected a platform composition event")
  }
}

///|
test "composition native records preserve window and sequence" {
  let start = composition_test_event(composition_test_record(26, ""), "")
  assert_eq(start.window().value(), 7L)
  assert_eq(start.sequence(), 19L)
  assert_true(start.kind() is @platform.Composition(@primitives.Start))
  let cancel = composition_test_event(composition_test_record(29, ""), "")
  assert_true(cancel.kind() is @platform.Composition(@primitives.Cancel))
  let commit = composition_test_event(
    composition_test_record(28, "日本語"),
    "日本語",
  )
  assert_true(
    commit.kind() is @platform.Composition(@primitives.Commit(text="日本語")),
  )
}

///|
test "composition converts UTF8 byte cursor to UTF16 without clamping" {
  let source = "A😀éあ"
  let data = composition_test_record(27, source)
  data[16] = 1.0
  data[17] = 5.0
  let event = composition_test_event(data, source)
  assert_true(
    event.kind()
    is @platform.Composition(
      @primitives.Update(text="A😀éあ", cursor_utf16=3)
    ),
  )
  data[17] = 2.0
  assert_true(ime_test_decode(data, @utf8.encode(source)) is Err(_))
  data[17] = 11.0
  assert_true(ime_test_decode(data, @utf8.encode(source)) is Err(_))
  data[17] = 1.5
  assert_true(ime_test_decode(data, @utf8.encode(source)) is Err(_))
  data[17] = -1.0
  assert_true(
    composition_test_event(data, source).kind()
    is @platform.Composition(@primitives.Update(cursor_utf16=5, ..)),
  )
  data[16] = 0.0
  data[17] = 0.0
  assert_true(
    composition_test_event(data, source).kind()
    is @platform.Composition(@primitives.Update(cursor_utf16=5, ..)),
  )
}

///|
test "composition rejects foreign editor semantics and malformed identity" {
  for field in [4, 5, 6, 7, 8, 9, 15, 18, 19, 20, 21, 22, 23, 24, 25] {
    let data = composition_test_record(27, "x")
    data[field] = 1.0
    assert_true(ime_test_decode(data, @utf8.encode("x")) is Err(_))
  }
  for field in [1, 2, 3, 10, 11, 12] {
    let data = composition_test_record(27, "x")
    data[field] = 0.0
    assert_true(ime_test_decode(data, @utf8.encode("x")) is Err(_))
  }
  let data = composition_test_record(27, "x")
  data[13] = -1.0
  assert_true(ime_test_decode(data, @utf8.encode("x")) is Err(_))
}

///|
test "composition lifecycle and commit cannot smuggle preedit metadata" {
  for tag in [26, 29] {
    assert_true(
      ime_test_decode(composition_test_record(tag, "x"), @utf8.encode("x"))
      is Err(_),
    )
  }
  let commit = composition_test_record(28, "x")
  commit[16] = 1.0
  assert_true(ime_test_decode(commit, @utf8.encode("x")) is Err(_))
  let update = composition_test_record(27, "x")
  update[14] = 4097.0
  assert_true(ime_test_decode(update, @utf8.encode("x")) is Err(_))
  update[14] = 2.0
  assert_true(ime_test_decode(update, @utf8.encode("x")) is Err(_))
}

///|
test "composition caret validation is nonmutating before native entry" {
  let host : Host = { token: -1, stopped: false, }
  let window = @platform.WindowId::new(1L)
  for
    rect in [
      @primitives.Rect::new(0.5, 0.0, 1.0, 1.0),
      @primitives.Rect::new(0.0, 0.0, 0.0, 1.0),
      @primitives.Rect::new(2147483648.0, 0.0, 1.0, 1.0),
    ] {
    let rect = rect.unwrap()
    match host.set_text_composition_caret(window, rect) {
      Err(error) => assert_true(error.code() is @diagnostics.InvalidInput)
      _ => fail("invalid caret reached native code")
    }
  }
}

///|
test "composition forwarded keypad Enter maps to the normal command" {
  assert_true(key(0xff8d, 0) is Some(@primitives.Enter))
}
