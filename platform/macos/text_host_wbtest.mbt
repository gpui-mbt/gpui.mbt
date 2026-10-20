///|
test "text input epochs reject non-positive and non-finite host values" {
  assert_true(text_input_epoch(0.0) is Err(_))
  assert_true(text_input_epoch(-1.0) is Err(_))
  assert_true(text_input_epoch(1.0 / 0.0) is Err(_))
  assert_true(text_input_epoch(0.0 / 0.0) is Err(_))
  assert_true(text_input_epoch(2_147_483_648.0) is Err(_))
  assert_eq(text_input_epoch(7.0).unwrap(), 7UL)
}

///|
test "text input decoding preserves UTF-8 and rejects invalid payloads" {
  let source = @utf8.encode("日本語 🙂")
  let payload = FixedArray::make(source.length(), b'\x00')
  for index = 0; index < source.length(); index = index + 1 {
    payload[index] = source[index]
  }
  assert_eq(
    decode_text_input(payload, source.length()).unwrap(),
    "日本語 🙂",
  )
  assert_true(decode_text_input(payload, -1) is Err(_))
  assert_true(decode_text_input(payload, 65_537) is Err(_))
  let invalid = FixedArray::make(2, (0xFF).to_byte())
  assert_true(decode_text_input(invalid, 2) is Err(_))
}
