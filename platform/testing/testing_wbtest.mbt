///|
/// Deterministic in-memory contract fixture. Its bytes are test data and do
/// not represent a native host, compositor, or rendered Button scene.
struct DeterministicFrameReadback {
  width : Int32
  height : Int32
  scale : Double
  pixels : Array[Byte]
  metrics_calls : Ref[Int32]
  copy_calls : Ref[Int32]
}

///|
impl FrameReadback for DeterministicFrameReadback with fn frame_metrics(
  self,
  _window : @platform.WindowId,
) -> Result[(Int32, Int32, Double), @diagnostics.FrameworkError] {
  self.metrics_calls.val = self.metrics_calls.val + 1
  Ok((self.width, self.height, self.scale))
}

///|
impl FrameReadback for DeterministicFrameReadback with fn copy_frame(
  self,
  _window : @platform.WindowId,
  output : FixedArray[Byte],
) -> Result[Unit, @diagnostics.FrameworkError] {
  self.copy_calls.val = self.copy_calls.val + 1
  if output.length() != self.pixels.length() {
    return Err(error(@diagnostics.ConversionFailed, "mock_copy_frame"))
  }
  for i = 0; i < output.length(); i = i + 1 {
    output[i] = self.pixels[i]
  }
  Ok(())
}

///|
test "capture_frame gates readback and preserves bounded top-left RGBA8 layout" {
  let original_gate = @env.get_env_var("GPUI_NATIVE_E2E")
  @env.unset_env_var("GPUI_NATIVE_E2E")

  let deterministic = {
    width: 2,
    height: 2,
    scale: 2.0,
    pixels: [
      b'\x10', b'\x11', b'\x12', b'\xff', b'\x20', b'\x21', b'\x22', b'\xff', b'\x30',
      b'\x31', b'\x32', b'\xff', b'\x40', b'\x41', b'\x42', b'\xff',
    ],
    metrics_calls: Ref(0),
    copy_calls: Ref(0),
  }
  let window = @platform.WindowId::new(7)
  assert_true(capture_frame(deterministic, window) is Err(_))
  assert_eq(deterministic.metrics_calls.val, 0)
  assert_eq(deterministic.copy_calls.val, 0)

  @env.set_env_var("GPUI_NATIVE_E2E", "1")
  let capture = capture_frame(deterministic, window).unwrap()
  assert_eq(capture.width(), 2)
  assert_eq(capture.height(), 2)
  assert_eq(capture.scale(), 2.0)
  assert_eq(capture.pixel_rgba8(0, 0).unwrap(), (16, 17, 18, 255))
  assert_eq(capture.pixel_rgba8(1, 0).unwrap(), (32, 33, 34, 255))
  assert_eq(capture.pixel_rgba8(0, 1).unwrap(), (48, 49, 50, 255))
  assert_eq(capture.pixel_rgba8(1, 1).unwrap(), (64, 65, 66, 255))
  assert_true(capture.pixel_rgba8(-1, 0) is Err(_))
  assert_true(capture.pixel_rgba8(2, 0) is Err(_))
  assert_eq(deterministic.metrics_calls.val, 1)
  assert_eq(deterministic.copy_calls.val, 1)

  let oversized = {
    width: 4097,
    height: 4096,
    scale: 1.0,
    pixels: [],
    metrics_calls: Ref(0),
    copy_calls: Ref(0),
  }
  assert_true(capture_frame(oversized, window) is Err(_))
  assert_eq(oversized.metrics_calls.val, 1)
  assert_eq(oversized.copy_calls.val, 0)

  let invalid_scale = {
    width: 1,
    height: 1,
    scale: 0.0,
    pixels: [],
    metrics_calls: Ref(0),
    copy_calls: Ref(0),
  }
  assert_true(capture_frame(invalid_scale, window) is Err(_))
  assert_eq(invalid_scale.metrics_calls.val, 1)
  assert_eq(invalid_scale.copy_calls.val, 0)

  match original_gate {
    Some(value) => @env.set_env_var("GPUI_NATIVE_E2E", value)
    None => @env.unset_env_var("GPUI_NATIVE_E2E")
  }
}

///|
fn frame_test_rect(
  left : Double,
  top : Double,
  right : Double,
  bottom : Double,
) -> @primitives.Rect {
  @primitives.Rect::new(left, top, right - left, bottom - top).unwrap()
}

///|
test "frame helpers read logical pixels, compare regions and count ink" {
  let original_gate = @env.get_env_var("GPUI_NATIVE_E2E")
  @env.set_env_var("GPUI_NATIVE_E2E", "1")
  let window = @platform.WindowId::new(9L)
  let pixels : Array[Byte] = [
    b'\x10', b'\x11', b'\x12', b'\xff', b'\x20', b'\x21', b'\x22', b'\xff', b'\x30',
    b'\x31', b'\x32', b'\xff', b'\x40', b'\x41', b'\x42', b'\xff',
  ]
  let fixture = {
    width: 2,
    height: 2,
    scale: 2.0,
    pixels,
    metrics_calls: Ref(0),
    copy_calls: Ref(0),
  }
  let first = capture_frame(fixture, window).unwrap()
  assert_eq(first.pixel_rgba8_logical(0.25, 0.25).unwrap(), (16, 17, 18, 255))
  assert_eq(first.pixel_rgba8_logical(0.75, 0.75).unwrap(), (64, 65, 66, 255))
  assert_true(first.pixel_matches_logical(0.25, 0.25, 16, 17, 18, 0).unwrap())
  assert_false(first.pixel_matches_logical(0.25, 0.25, 16, 17, 19, 0).unwrap())
  assert_true(first.pixel_matches_logical(0.25, 0.25, 16, 17, 19, 1).unwrap())
  assert_eq(
    first.ink_count(frame_test_rect(0.0, 0.0, 1.0, 1.0), 50).unwrap(),
    1,
  )
  assert_eq(
    first.ink_count(frame_test_rect(0.0, 0.0, 0.0, 1.0), 50).unwrap(),
    0,
  )
  assert_false(
    first.region_differs(first, frame_test_rect(0.0, 0.0, 1.0, 1.0)).unwrap(),
  )

  let changed_pixels : Array[Byte] = [
    b'\x10', b'\x11', b'\x12', b'\xff', b'\x20', b'\x21', b'\x22', b'\xff', b'\x30',
    b'\x31', b'\x32', b'\xff', b'\x40', b'\x41', b'\x43', b'\xff',
  ]
  let changed = {
    width: 2,
    height: 2,
    scale: 2.0,
    pixels: changed_pixels,
    metrics_calls: Ref(0),
    copy_calls: Ref(0),
  }
  let second = capture_frame(changed, window).unwrap()
  assert_true(
    first.region_differs(second, frame_test_rect(0.0, 0.0, 1.0, 1.0)).unwrap(),
  )
  assert_false(
    first.region_differs(second, frame_test_rect(0.0, 0.0, 0.0, 0.5)).unwrap(),
  )
  match original_gate {
    Some(value) => @env.set_env_var("GPUI_NATIVE_E2E", value)
    None => @env.unset_env_var("GPUI_NATIVE_E2E")
  }
}
