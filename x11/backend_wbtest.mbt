///|
test "missing X11 display is typed and retryable" {
  let previous = @env.get_env_var("DISPLAY")
  @env.unset_env_var("DISPLAY")
  for _i = 0; _i < 2; _i = _i + 1 {
    match Host::start() {
      Ok(host) => {
        ignore(host.stop())
        fail("missing DISPLAY must be unsupported")
      }
      Err(error) => assert_eq(error.code().label(), "unsupported_capability")
    }
  }
  match previous {
    Some(value) => @env.set_env_var("DISPLAY", value)
    None => @env.unset_env_var("DISPLAY")
  }
}

///|
test "X11 explicitly excludes IME and accepts portable logical dimensions" {
  let host : Host = { token: 0, stopped: true, }
  match host.require_capability(@platform.TextInput) {
    Err(error) => assert_eq(error.code().label(), "unsupported_capability")
    Ok(_) => fail("X11 must not advertise IME text sessions")
  }
  assert_eq(logical_dimension(1280.0, "test").unwrap(), 1280)
  assert_true(logical_dimension(0.0, "test") is Err(_))
  assert_true(logical_dimension(4.5, "test") is Err(_))
  assert_true(logical_dimension(16385.0, "test") is Err(_))
  assert_true(host.state() == Stopped)
  assert_true(host.stop() is Ok(_))
}

///|
test "X11 wire preserves physical key repeat and copied direct UTF8" {
  let data = FixedArray::make(10, 0.0)
  data[0] = 11.0
  data[1] = 1.0
  data[2] = 1.0
  data[3] = 1.0
  data[6] = 97.0
  data[7] = 1.0
  data[8] = 97.0
  data[9] = 2.0
  let text = @utf8.encode("é")
  match decode_v2_event(data, text, "test") {
    Ok(Some(@platform.Input(@primitives.KeyPressed(key~, modifiers~, repeat~)))) => {
      assert_true(key == @primitives.Character("a"))
      assert_true(modifiers.control())
      assert_true(repeat)
    }
    _ => fail("expected repeated shortcut key")
  }
  data[0] = 13.0
  data[6] = 0.0
  data[7] = 0.0
  data[8] = 2.0
  data[9] = 0.0
  match decode_v2_event(data, text, "test") {
    Ok(Some(@platform.Input(@primitives.TextInput(text~)))) =>
      assert_eq(text, "é")
    _ => fail("expected copied UTF8 text")
  }
  data[8] = 129.0
  assert_true(decode_v2_event(data, text, "test") is Err(_))
}

///|
test "X11 maps renderer completion and terminal window records" {
  let data = FixedArray::make(10, 0.0)
  data[0] = 5.0
  assert_true(decode_event(data) is Some(@platform.FrameCompleted))
  data[0] = 4.0
  assert_true(decode_event(data) is Some(@platform.Destroyed))
  data[0] = 6.0
  data[8] = 1.0
  assert_true(decode_event(data) is Some(@platform.FocusChanged(true)))
}
