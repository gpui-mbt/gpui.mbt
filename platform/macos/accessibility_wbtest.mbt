///|
test "dialog AX payload carries the title, role and logical frame" {
  let bounds = match @primitives.Rect::new(20.0, 30.0, 320.0, 120.0) {
    Ok(value) => value
    Err(_) => fail("test bounds must be valid")
  }
  let payload = macos_ax_dialog_payload(
    DialogAccessibilitySnapshot::new("Save changes?", bounds, true),
  )
  let text = @utf8.decode(payload)
  assert_true(text.contains("\"role\":\"dialog\""))
  assert_true(text.contains("\"title\":\"Save changes?\""))
  assert_true(text.contains("\"left\":20"))
  assert_true(text.contains("\"top\":30"))
  assert_true(text.contains("\"width\":320"))
  assert_true(text.contains("\"height\":120"))
  assert_true(text.contains("\"focused\":true"))
  assert_true(text.contains("\"version\":1"))
}
