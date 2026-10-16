///|
test "layout bounds refresh allocates no focus identity even at exhaustion" {
  let viewport = @primitives.Size::new(100, 40).unwrap()
  let row = @layout.FlexTreeStyle::new(@layout.FlowDirection::row())
  let child = Element::new(
    @layout.FlexItem::new(
      2,
      @layout.Dimension::points(20).unwrap(),
      @layout.Dimension::points(40).unwrap(),
      viewport,
    ),
  ).with_focusable(true)
  let frame = Element::root(1, row)
    .with_child(child)
    .request_layout(viewport)
    .unwrap()
    .prepaint()
    .unwrap()
  let retained = frame.tree().with_focus(2).unwrap()
  let previous = focus_identity_sequence.val
  focus_identity_sequence.val = 0xffff_ffff_ffff_ffff
  let result = retained.with_layout_bounds(frame)
  let after = focus_identity_sequence.val
  focus_identity_sequence.val = previous
  assert_true(after == 0xffff_ffff_ffff_ffff)
  let refreshed = result.unwrap()
  assert_true(refreshed.lineage == retained.lineage)
  assert_true(refreshed.owner == retained.owner)
  assert_true(refreshed.focused == retained.focused)
}
