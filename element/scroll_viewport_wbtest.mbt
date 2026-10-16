///|
fn scroll_probe_rect(x : Double, width : Double) -> @primitives.Rect {
  match @primitives.Rect::new(x, 0, width, 10) {
    Ok(value) => value
    Err(_) => abort("invalid probe rectangle")
  }
}

///|
fn scroll_probe_element(id : UInt64, scroll : Bool) -> Element {
  let size = match @primitives.Size::new(10, 10) {
    Ok(value) => value
    Err(_) => abort("invalid probe size")
  }
  let element = Element::new(
    @layout.FlexItem::new(
      id,
      @layout.Dimension::auto(),
      @layout.Dimension::auto(),
      size,
    ),
  )
  if scroll {
    element.with_scroll_offset(scroll_point(1.7e308, 0))
  } else {
    element
  }
}

///|
test "scroll prepaint reports geometry failure for unrepresentable translated bounds" {
  let root = scroll_probe_element(1, true).with_child(
    scroll_probe_element(2, false),
  )
  let placements = [
    ElementPlacement::{ element: root, parent: None, depth: 0, },
    ElementPlacement::{
      element: scroll_probe_element(2, false),
      parent: Some(1),
      depth: 1,
    },
    ElementPlacement::{
      element: scroll_probe_element(3, false),
      parent: Some(1),
      depth: 1,
    },
  ]
  let nodes = [
    ElementNode::new(1, None, scroll_probe_rect(0, 1)),
    ElementNode::new(2, Some(1), scroll_probe_rect(0, 1)),
    ElementNode::new(3, Some(1), scroll_probe_rect(0, 1.7e308)),
  ]
  assert_true(
    resolve_scroll_nodes(nodes, placements, None) is Err(GeometryFailure),
  )
}

///|
test "scroll prepaint reports geometry failure when ancestor offsets overflow" {
  let inner = scroll_probe_element(2, true).with_child(
    scroll_probe_element(3, false),
  )
  let root = scroll_probe_element(1, true)
    .with_child(inner)
    .with_child(scroll_probe_element(4, false))
  let placements = [
    ElementPlacement::{ element: root, parent: None, depth: 0, },
    ElementPlacement::{ element: inner, parent: Some(1), depth: 1, },
    ElementPlacement::{
      element: scroll_probe_element(3, false),
      parent: Some(2),
      depth: 2,
    },
    ElementPlacement::{
      element: scroll_probe_element(4, false),
      parent: Some(1),
      depth: 1,
    },
  ]
  let nodes = [
    ElementNode::new(1, None, scroll_probe_rect(0, 1.0e307)),
    ElementNode::new(2, Some(1), scroll_probe_rect(0, 1.0e307)),
    ElementNode::new(3, Some(2), scroll_probe_rect(0, 1.7e308)),
    ElementNode::new(4, Some(1), scroll_probe_rect(0, 1.7e308)),
  ]
  assert_true(
    resolve_scroll_nodes(nodes, placements, None) is Err(GeometryFailure),
  )
}

///|
test "scroll direct-child union rejects unrepresentable spans" {
  let root = scroll_probe_element(1, true)
  let placements = [
    ElementPlacement::{ element: root, parent: None, depth: 0, },
    ElementPlacement::{
      element: scroll_probe_element(2, false),
      parent: Some(1),
      depth: 1,
    },
    ElementPlacement::{
      element: scroll_probe_element(3, false),
      parent: Some(1),
      depth: 1,
    },
  ]
  let nodes = [
    ElementNode::new(1, None, scroll_probe_rect(0, 10)),
    ElementNode::new(2, Some(1), scroll_probe_rect(-1.0e308, 1.0e307)),
    ElementNode::new(3, Some(1), scroll_probe_rect(1.0e308, 1.0e307)),
  ]
  assert_true(
    scroll_maximum(nodes, placements, 0, None) is Err(GeometryFailure),
  )
}

///|
test "scroll device translation rejects overflow and preserves midpoint semantics" {
  assert_true(
    scroll_translation(scroll_point(1.0e308, 0), Some(2.0))
    is Err(GeometryFailure),
  )
  assert_true(
    scroll_translation(scroll_point(0, -1.0e308), Some(2.0))
    is Err(GeometryFailure),
  )
  assert_true(
    scroll_translation(scroll_point(0, 0), Some(0.0)) is Err(GeometryFailure),
  )
  let tie = match scroll_translation(scroll_point(0.25, -0.75), Some(2.0)) {
    Ok(value) => value
    Err(_) => fail("finite translation rejected")
  }
  assert_true(tie == scroll_point(0, -0.5))
}
