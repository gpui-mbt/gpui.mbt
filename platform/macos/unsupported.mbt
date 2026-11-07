///|
fn call(
  _op : Int32,
  _token : Int64,
  _x : Double,
  _y : Double,
  _bytes : Bytes,
  _length : Int32,
) -> Int32 {
  9
}

///|
fn integer(_field : Int32) -> Int64 {
  0
}

///|
fn number(_field : Int32) -> Double {
  0.0
}

///|
fn native_display_snapshot(
  _host : Int64,
  _records : FixedArray[Double],
  _capacity : Int32,
) -> Int32 {
  9
}

///|
fn accessibility_publish(
  _window : Int64,
  _binding : Int64,
  _payload : Bytes,
  _length : Int32,
  _output : FixedArray[Int64],
) -> Int32 {
  9
}

///|
fn accessibility_publish_field(
  _window : Int64,
  _binding : Int64,
  _payload : Bytes,
  _length : Int32,
  _output : FixedArray[Int64],
) -> Int32 {
  9
}

///|
fn accessibility_publish_dialog(
  _window : Int64,
  _binding : Int64,
  _payload : Bytes,
  _length : Int32,
  _output : FixedArray[Int64],
) -> Int32 {
  9
}

///|
fn accessibility_revoke(_window : Int64, _binding : Int64) -> Int32 {
  9
}

///|
fn accessibility_revoke_dialog(_window : Int64, _binding : Int64) -> Int32 {
  9
}

///|
fn accessibility_revoke_field(_window : Int64, _binding : Int64) -> Int32 {
  9
}

///|
fn accessibility_take_request(
  _window : Int64,
  _output : FixedArray[Int64],
) -> Int32 {
  9
}

///|
fn text_session(
  _op : Int32,
  _window : Int64,
  _epoch : Int64,
  _fields : FixedArray[Double],
  _bytes : Bytes,
  _length : Int32,
) -> Int32 {
  9
}

///|
fn text_next(
  _window : Int64,
  _epoch : Int64,
  _timeout_ms : Int32,
  _fields : FixedArray[Double],
  _payload : FixedArray[Byte],
  _capacity : Int32,
) -> Int32 {
  9
}

///|
fn text_available() -> Int32 {
  0
}
