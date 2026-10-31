///|
test "unresolved compose result rejects zero and insufficient copy buffers" {
  let route = retained_test_route()
  route.direct_binding = true
  let result : RetainedDirectResult = {
    route,
    window: @platform.WindowId::new(51L),
    root: 9UL,
    epoch: 3UL,
    native_epoch: 7,
    length: 200,
    watermark: 21,
    key: 30,
    modifiers: 0,
  }
  for capacity in [0, 199, 200] {
    let output = Bytes::make(capacity, (0).to_byte())
    match result.copy_into(output) {
      Err(error) => assert_true(error.code() is @diagnostics.ResourceExhausted)
      Ok(_) => fail("undersized buffer was accepted")
    }
  }
}
