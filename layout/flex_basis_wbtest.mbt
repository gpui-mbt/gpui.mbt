///|
test "raw invalid flex basis is rejected by resolver" {
  let size = @primitives.Size::new(10.0, 10.0).unwrap()
  for value in [-1.0, 0.0 / 0.0, 1.0 / 0.0] {
    let item = FlexItem::new(1, Dimension::Auto, Dimension::Auto, size).with_flex_basis(
      FlexBasis::Points(value),
    )
    assert_true(item.resolved_flex_basis(10.0, 100.0) is Err(_))
  }
}

///|
test "raw invalid percentage basis and containing extents are rejected" {
  let size = @primitives.Size::new(10.0, 10.0).unwrap()
  for value in [-1.0, 0.0 / 0.0, 1.0 / 0.0] {
    let item = FlexItem::new(1, Dimension::Auto, Dimension::Auto, size).with_flex_basis(
      FlexBasis::Percent(value),
    )
    assert_true(item.resolved_flex_basis(10.0, 100.0) is Err(_))
    let item = item.with_flex_basis(FlexBasis::Percent(0.5))
    assert_true(item.resolved_flex_basis(10.0, value) is Err(_))
  }
}
