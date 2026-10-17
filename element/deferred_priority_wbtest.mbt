///|
test "deferred priority malformed internal metadata is rejected before publication" {
  let bounds = @primitives.Rect::new(0, 0, 10, 10).unwrap()
  let negative = { ..ElementNode::new(1, None, bounds), deferred: Some(-1), }
  assert_true(ElementTree::new([negative]) is Err(InvalidDeferredPriority))
  let root = { ..ElementNode::new(1, None, bounds), deferred: Some(9), }
  let wrong = { ..ElementNode::new(2, Some(1), bounds), deferred: Some(1), }
  let absent = ElementNode::new(2, Some(1), bounds)
  assert_true(
    ElementTree::new([root, wrong]) is Err(UnsupportedAnchoredComposition),
  )
  assert_true(
    ElementTree::new([root, absent]) is Err(UnsupportedAnchoredComposition),
  )
}
