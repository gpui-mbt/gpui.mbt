///|
#borrow(bytes)
extern "C" fn call(
  op : Int32,
  token : Int64,
  x : Double,
  y : Double,
  bytes : Bytes,
  length : Int32,
) -> Int32 = "gpui_call"

///|
#borrow(records)
extern "C" fn native_display_snapshot(
  host : Int64,
  records : FixedArray[Double],
  capacity : Int32,
) -> Int32 = "gpui_macos_display_snapshot"

///|
extern "C" fn integer(field : Int32) -> Int64 = "gpui_integer"

///|
extern "C" fn number(field : Int32) -> Double = "gpui_number"

///|
#borrow(payload, output)
extern "C" fn accessibility_publish(
  window : Int64,
  binding : Int64,
  payload : Bytes,
  length : Int32,
  output : FixedArray[Int64],
) -> Int32 = "gpui_macos_ax_publish"

///|
extern "C" fn accessibility_revoke(window : Int64, binding : Int64) -> Int32 = "gpui_macos_ax_revoke"

///|
#borrow(output)
extern "C" fn accessibility_take_request(
  window : Int64,
  output : FixedArray[Int64],
) -> Int32 = "gpui_macos_ax_take_request"

///|
#borrow(metrics)
extern "C" fn frame_metrics(
  window : Int64,
  metrics : FixedArray[Double],
) -> Int32 = "gpui_macos_frame_metrics"

///|
#borrow(output)
extern "C" fn frame_copy(
  window : Int64,
  output : FixedArray[Byte],
  capacity : Int32,
) -> Int32 = "gpui_macos_frame_copy"

///|
extern "C" fn test_post_click(window : Int64, x : Double, y : Double) -> Int32 = "gpui_macos_test_post_click"

///|
extern "C" fn test_post_escape(window : Int64) -> Int32 = "gpui_macos_test_post_escape"

///|
#borrow(text)
extern "C" fn test_post_key(
  window : Int64,
  key_code : Int32,
  modifiers : Int32,
  text : Bytes,
  text_length : Int32,
) -> Int32 = "gpui_macos_test_post_key"

///|
#borrow(text)
extern "C" fn test_post_composition(
  window : Int64,
  kind : Int32,
  cursor : Int32,
  text : Bytes,
  text_length : Int32,
) -> Int32 = "gpui_macos_test_post_composition"

///|
#borrow(fields, bytes)
extern "C" fn text_session(
  op : Int32,
  window : Int64,
  epoch : Int64,
  fields : FixedArray[Double],
  bytes : Bytes,
  length : Int32,
) -> Int32 = "gpui_macos_text_session"

///|
#borrow(fields, payload)
extern "C" fn text_next(
  window : Int64,
  epoch : Int64,
  timeout_ms : Int32,
  fields : FixedArray[Double],
  payload : FixedArray[Byte],
  capacity : Int32,
) -> Int32 = "gpui_macos_text_next"

///|
extern "C" fn text_available() -> Int32 = "gpui_macos_text_available"
