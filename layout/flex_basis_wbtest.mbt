///|
test "raw invalid flex basis is rejected by resolver" {
  let size = @primitives.Size::new(10.0, 10.0).unwrap()
  for value in [-1.0, 0.0 / 0.0, 1.0 / 0.0] {
    let item = FlexItem::new(1, Dimension::Auto, Dimension::Auto, size).with_flex_basis(
      FlexBasis::Points(value),
    )
    assert_true(item.resolved_flex_basis(10.0) is Err(_))
  }
}
