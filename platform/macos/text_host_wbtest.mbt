///|
test "parked composition records keep their order for the text route" {
  // The ordinary event pump parks records that an armed session produced, so a
  // live loop observes a preedit before its commit instead of only the commit.
  let queue = @text_host.TextHostQueue::new()
  let window = @platform.WindowId::new(4)
  let epoch = queue.begin(window).unwrap()
  queue.emit(@text_host.Preedit(text="にほん", cursor=3)).unwrap()
  queue.emit(@text_host.Commit(text="日本")).unwrap()
  match queue.take_text() {
    Some(event) =>
      match event.kind() {
        @text_host.Preedit(text~, cursor~) => {
          assert_eq(text, "にほん")
          assert_eq(cursor, 3)
        }
        _ => fail("the first parked record was not the preedit")
      }
    None => fail("the preedit was not parked")
  }
  match queue.take_text() {
    Some(event) =>
      match event.kind() {
        @text_host.Commit(text~) => assert_eq(text, "日本")
        _ => fail("the second parked record was not the commit")
      }
    None => fail("the commit was not parked")
  }
  assert_true(queue.take_text() is None)
  assert_eq(epoch, 1UL)
}

///|
test "cancelling a parked session drops records from the replaced epoch" {
  let queue = @text_host.TextHostQueue::new()
  let window = @platform.WindowId::new(5)
  let epoch = queue.begin(window).unwrap()
  queue.emit(@text_host.Preedit(text="あ", cursor=1)).unwrap()
  let replacement = queue.cancel(epoch).unwrap()
  assert_true(replacement != epoch)
  assert_true(queue.take_text() is None)
}

///|
test "emit_at keeps the host sequence so a mirrored copy is recognisable" {
  let queue = @text_host.TextHostQueue::new()
  let window = @platform.WindowId::new(6)
  let epoch = queue.begin(window).unwrap()
  queue.emit_at(3L, @text_host.Preedit(text="に", cursor=1)).unwrap()
  queue.emit_at(4L, @text_host.Commit(text="日")).unwrap()
  match queue.take_text() {
    Some(event) => {
      assert_eq(event.sequence(), 3L)
      assert_eq(event.epoch(), epoch)
    }
    None => fail("the parked record was not queued")
  }
  match queue.take_text() {
    Some(event) => assert_eq(event.sequence(), 4L)
    None => fail("the second parked record was not queued")
  }
  assert_true(queue.emit_at(0L, @text_host.Cancel) is Err(_))
}

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
