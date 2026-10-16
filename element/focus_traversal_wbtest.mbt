///|
test "tab no-op traversal never allocates focus identity while a changed target does" {
  let bounds = match @primitives.Rect::new(0, 0, 10, 10) {
    Ok(value) => value
    Err(_) => abort("invalid bounds")
  }
  let tree = match
    ElementTree::new([
      ElementNode::new(1, None, bounds).with_focusable(true).with_tab_stop(true),
      ElementNode::new(2, None, bounds).with_focusable(true),
    ]) {
    Ok(value) => value
    Err(_) => abort("invalid tree")
  }
  let focused = match tree.with_focus(1) {
    Ok(value) => value
    Err(_) => abort("invalid focus")
  }
  let other = match tree.with_focus(2) {
    Ok(value) => value
    Err(_) => abort("invalid focus")
  }
  let saved = focus_identity_sequence.val
  focus_identity_sequence.val = 0xffff_ffff_ffff_ffff
  let next = focused.focus_next()
  let prev = focused.focus_prev()
  let changed = other.focus_next()
  let explicit = focused.with_focus(1)
  let no_stops = match focused.without_subtree(1) {
    Ok(value) => value
    Err(_) => abort("invalid removal")
  }
  let no_stops_next = no_stops.focus_next()
  let exhausted = focus_identity_sequence.val
  focus_identity_sequence.val = saved
  for result in [next, prev] {
    match result {
      Ok(value) => assert_true(value.focus_owner() == focused.focus_owner())
      Err(_) => fail("unchanged destination allocated identity")
    }
  }
  assert_true(changed is Err(FocusIdentityExhausted))
  assert_true(explicit is Err(FocusIdentityExhausted))
  assert_true(no_stops_next is Ok(_))
  assert_true(exhausted == 0xffff_ffff_ffff_ffff)
}

///|
test "declarative tab builders defensively copy child arrays" {
  let style = @layout.FlexTreeStyle::new(@layout.FlowDirection::row())
  let root = Element::root(1, style).with_child(Element::root(2, style))
  let indexed = root.with_tab_index(-3)
  let stopped = root.with_tab_stop(true)
  root.children[0] = Element::root(9, style)
  assert_true(indexed.children[0].id == 2)
  assert_true(stopped.children[0].id == 2)
  indexed.children.push(Element::root(8, style))
  assert_eq(stopped.children.length(), 1)
  assert_eq(root.children.length(), 1)
}
