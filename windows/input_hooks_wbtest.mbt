///|
fn[T] input_hook_required(result : Result[T, @diagnostics.FrameworkError]) -> T {
  match result {
    Ok(value) => value
    Err(error) => abort("\{error.operation()}: \{error.code().label()}")
  }
}

///|
#borrow(event_data)
extern "C" fn native_test_shortcut_wndproc(
  host : Int32,
  window : Int32,
  virtual_key : Int32,
  repeat : Int32,
  state : Int32,
  event_data : FixedArray[Double],
) -> Int32 = "gpui_windows_test_shortcut_wndproc"

///|
#borrow(output)
extern "C" fn native_test_shortcut_layout(
  host : Int32,
  virtual_key : Int32,
  output : FixedArray[Double],
) -> Int32 = "gpui_windows_test_shortcut_layout"

///|
test "Windows test key encoding accepts one printable scalar" {
  assert_true(test_key_encoding(@primitives.Character("k")) is Ok((1, 107)))
  assert_true(
    test_key_encoding(@primitives.Character("日")) is Ok((1, 0x65e5)),
  )
  assert_true(test_key_encoding(@primitives.Character("ab")) is Err(_))
  assert_true(test_key_encoding(@primitives.Character("\u{7f}")) is Err(_))
  assert_true(test_key_encoding(@primitives.Character("\u{1f}")) is Err(_))
  assert_true(test_key_encoding(@primitives.Enter) is Ok((0, 0xff0d)))
  assert_true(test_key_encoding(@primitives.Escape) is Ok((0, 0xff1b)))
  assert_true(test_key_encoding(@primitives.ArrowDown) is Ok((0, 0xff54)))
}

///|
test "Windows test modifier bits match the event decoder" {
  let none = @primitives.Modifiers::new(
    shift=false,
    control=false,
    alt=false,
    meta=false,
  )
  assert_eq(test_modifier_bits(none), 0)
  let all = @primitives.Modifiers::new(
    shift=true,
    control=true,
    alt=true,
    meta=true,
  )
  assert_eq(test_modifier_bits(all), 15)
  let control = @primitives.Modifiers::new(
    shift=false,
    control=true,
    alt=false,
    meta=false,
  )
  assert_eq(test_modifier_bits(control), 2)
}

///|
test "Windows test input hooks enqueue decoded shortcuts" {
  if @env.get_env_var("GPUI_WINDOWS_E2E") != Some("1") {
    return
  }
  let original = @env.get_env_var("GPUI_NATIVE_E2E")
  @env.set_env_var("GPUI_NATIVE_E2E", "1")
  let host = input_hook_required(Host::start())
  let window = input_hook_required(host.create_window(96, 64, "input hooks"))
  input_hook_required(
    host.post_test_key(
      window,
      @primitives.Character("k"),
      @primitives.Modifiers::new(
        shift=false,
        control=true,
        alt=false,
        meta=false,
      ),
    ),
  )
  let key_events = input_hook_required(host.dispatch(16))
  let mut saw_shortcut = false
  for event in key_events {
    if event.kind()
      is @platform.Input(
        @primitives.KeyPressed(
          key=@primitives.Character(value),
          modifiers~,
          repeat=_
        )
      ) {
      if value == "k" && modifiers.control() {
        saw_shortcut = true
      }
    }
  }
  assert_true(saw_shortcut)
  input_hook_required(
    host.post_test_click(window, @primitives.Point::new(12.0, 10.0).unwrap()),
  )
  let click_events = input_hook_required(host.dispatch(16))
  let mut moved = false
  let mut pressed = false
  let mut released = false
  for event in click_events {
    match event.kind() {
      @platform.Input(@primitives.PointerMoved(..)) => moved = true
      @platform.Input(@primitives.PointerButtonPressed(..)) => pressed = true
      @platform.Input(@primitives.PointerButtonReleased(..)) => released = true
      _ => ()
    }
  }
  assert_true(moved && pressed && released)
  input_hook_required(host.destroy_window(window))
  input_hook_required(host.stop())
  match original {
    Some(value) => @env.set_env_var("GPUI_NATIVE_E2E", value)
    None => @env.unset_env_var("GPUI_NATIVE_E2E")
  }
}

///|
test "Windows shortcut WndProc emits exactly one event" {
  if @env.get_env_var("GPUI_WINDOWS_E2E") != Some("1") {
    return
  }
  let original = @env.get_env_var("GPUI_NATIVE_E2E")
  @env.set_env_var("GPUI_NATIVE_E2E", "1")
  let host = input_hook_required(Host::start())
  let window = input_hook_required(
    host.create_window(96, 64, "shortcut WndProc"),
  )
  for virtual_key in [0x56, 0x5a, 0x4b] {
    let expected = if virtual_key == 0x56 {
      "v"
    } else if virtual_key == 0x5a {
      "z"
    } else {
      "k"
    }
    for state in 0..<3 {
      for repeat in 0..<2 {
        let data = FixedArray::make(10, 0.0)
        let status = native_test_shortcut_wndproc(
          host.token,
          window.value().to_int(),
          virtual_key,
          repeat,
          state,
          data,
        )
        assert_eq(status, 0)
        match decode_event(data) {
          Some(
            @platform.Input(
              @primitives.KeyPressed(
                key=@primitives.Character(value),
                modifiers~,
                repeat=repeat_value
              )
            )
          ) => {
            assert_eq(value, expected)
            assert_true(modifiers.control())
            assert_eq(repeat_value, repeat == 1)
          }
          _ => fail("shortcut did not decode to one Character key-down")
        }
      }
    }
  }
  input_hook_required(host.destroy_window(window))
  input_hook_required(host.stop())
  match original {
    Some(value) => @env.set_env_var("GPUI_NATIVE_E2E", value)
    None => @env.unset_env_var("GPUI_NATIVE_E2E")
  }
}

///|
test "Windows shortcut punctuation follows the keyboard layout" {
  if @env.get_env_var("GPUI_WINDOWS_E2E") != Some("1") {
    return
  }
  let original = @env.get_env_var("GPUI_NATIVE_E2E")
  @env.set_env_var("GPUI_NATIVE_E2E", "1")
  let host = input_hook_required(Host::start())
  let output = FixedArray::make(2, 0.0)
  let status = native_test_shortcut_layout(host.token, 0xba, output)
  input_hook_required(host.stop())
  if status == 1 {
    // A runner without the French layout can skip the differential check.
    match original {
      Some(value) => @env.set_env_var("GPUI_NATIVE_E2E", value)
      None => @env.unset_env_var("GPUI_NATIVE_E2E")
    }
    return
  }
  assert_eq(status, 0)
  assert_eq(output[0].to_int(), 0x3b)
  assert_true(output[1] > 0.0)
  assert_true(output[1] != output[0])
  match original {
    Some(value) => @env.set_env_var("GPUI_NATIVE_E2E", value)
    None => @env.unset_env_var("GPUI_NATIVE_E2E")
  }
}
