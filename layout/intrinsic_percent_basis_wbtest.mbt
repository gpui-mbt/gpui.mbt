///|
test "intrinsic percent precision follows physical measured axis and preserves siblings" {
  let zero = @primitives.Size::new(0, 0).unwrap()
  let row = FlexTreeStyle::new(Row)
  let column = FlexTreeStyle::new(Column)
  let auto_main = FlexItem::new(2, Auto, Points(100), zero)
  let leaf = FlexItem::new(3, Points(40), Points(10), zero).with_flex_basis(
    Percent(0.5),
  )
  let nodes = [
    FlexTreeNode::new(auto_main, 1).with_children(row),
    FlexTreeNode::new(leaf, 2),
    FlexTreeNode::new(FlexItem::new(4, Points(20), Points(10), zero), 1),
    FlexTreeNode::new(FlexItem::new(5, Auto, Points(100), zero), 1).with_children(
      column,
    ),
    FlexTreeNode::new(
      FlexItem::new(6, Points(20), Points(10), zero).with_flex_basis(
        Percent(0.5),
      ),
      5,
    ),
    FlexTreeNode::new(FlexItem::new(7, Points(100), Auto, zero), 1).with_children(
      column,
    ),
    FlexTreeNode::new(
      FlexItem::new(8, Points(20), Points(10), zero).with_flex_basis(
        Percent(0.5),
      ),
      7,
    ),
  ]
  assert_eq(intrinsic_percent_precision_ids(1, Some(Row), nodes), [
    2UL, 3UL, 7UL, 8UL,
  ])
}

///|
test "intrinsic percent logical representation never changes ineligible rectangles" {
  let bounds = @primitives.Rect::new(
    -292.6666666666667, 371.3333333333333, 49.3333333333333, 10,
  ).unwrap()
  assert_true(
    intrinsic_percent_logical_bounds(bounds, false).unwrap() == bounds,
  )
  let qualified = intrinsic_percent_logical_bounds(bounds, true).unwrap()
  assert_eq(qualified.left(), -292.6666564941406)
  assert_eq(qualified.top(), 371.3333435058594)
  assert_eq(qualified.size().width(), 49.33333206176758)
}
