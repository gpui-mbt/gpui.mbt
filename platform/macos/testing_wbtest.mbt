///|
test "synthetic key hook maps printable ASCII to ANSI positions and rejects non-ASCII" {
  match test_key_code(@primitives.Character("K")) {
    Ok((code, text)) => {
      assert_eq(code, 40)
      assert_eq(text, "K")
    }
    Err(_) => fail("ASCII K was rejected")
  }
  match test_key_code(@primitives.Character("s")) {
    Ok((code, text)) => {
      assert_eq(code, 1)
      assert_eq(text, "s")
    }
    Err(_) => fail("ASCII s was rejected")
  }
  match test_key_code(@primitives.Character("あ")) {
    Ok(_) => fail("non-ASCII key was admitted to the test hook")
    Err(error) =>
      assert_eq(error.code().label(), @diagnostics.InvalidInput.label())
  }
  match test_key_code(@primitives.Character("!")) {
    Ok((code, text)) => {
      assert_eq(code, 18)
      assert_eq(text, "!")
    }
    Err(_) => fail("printable ASCII punctuation was rejected")
  }
}
