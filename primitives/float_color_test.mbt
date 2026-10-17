///|
test "float color preserves authored channels without byte conversion" {
  match @primitives.FloatColor::rgba(0.123456789012345, 0.5, 0.0, 0.25) {
    Err(_) => fail("valid floating color rejected")
    Ok(color) => {
      assert_true(color.red() == 0.123456789012345)
      assert_true(color.green() == 0.5)
      assert_true(color.blue() == 0.0)
      assert_true(color.alpha() == 0.25)
      assert_true(color.validate() is Ok(_))
      assert_false(color.is_opaque())
      assert_true(color.green() != 127.0 / 255.0)
      assert_true(color.green() != 128.0 / 255.0)
    }
  }
  assert_true(
    @primitives.FloatColor::rgba(0.0, 1.0, -0.0, 1.0) is Ok(color) &&
    color.is_opaque(),
  )
}

///|
test "float color validates every channel including nonfinite values" {
  let invalid = [
    -0.000001, 1.000001, @double.not_a_number, @double.infinity, @double.neg_infinity,
  ]
  for value in invalid {
    assert_true(
      @primitives.FloatColor::rgba(value, 0.5, 0.5, 0.5) is Err(InvalidChannel),
    )
    assert_true(
      @primitives.FloatColor::rgba(0.5, value, 0.5, 0.5) is Err(InvalidChannel),
    )
    assert_true(
      @primitives.FloatColor::rgba(0.5, 0.5, value, 0.5) is Err(InvalidChannel),
    )
    assert_true(
      @primitives.FloatColor::rgba(0.5, 0.5, 0.5, value) is Err(InvalidChannel),
    )
  }
}

///|
test "float colors compare exact authored values" {
  let first = @primitives.FloatColor::rgba(0.0, 0.5, 0.0, 1.0)
  let equal = @primitives.FloatColor::rgba(0.0, 0.5, 0.0, 1.0)
  let different = @primitives.FloatColor::rgba(0.0, 128.0 / 255.0, 0.0, 1.0)
  match (first, equal, different) {
    (Ok(first), Ok(equal), Ok(different)) => {
      assert_true(first == equal)
      assert_true(first != different)
    }
    _ => fail("valid floating color rejected")
  }
}
