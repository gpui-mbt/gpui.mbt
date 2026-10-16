///|
// Source/core contracts, not execution of the unchanged Rust/browser example.
// Measurements that motivate the 2px ordinary-button and 1px card probes are
// recorded separately in docs/evidence/tab-stop-geometry-20261016/README.md.
fn bounds_frame(first_width : Double) -> @element.Prepainted {
  let row = @layout.FlexTreeStyle::new(@layout.FlowDirection::row())
    .with_gap(12.0)
    .unwrap()
  // The first gap plus this 4px spacer gives the observed x=16px origin.
  let row = @element.Element::root(1, row)
    .with_child(
      @element.Element::new(viewport_item(90, 4, 40)).with_pointer_events(false),
    )
    .with_child(
      @element.Element::new(viewport_item(2, first_width, 40))
      .with_focusable(true)
      .with_tab_stop(true)
      .with_tab_index(1),
    )
    .with_child(
      @element.Element::new(viewport_item(3, 756.0 - first_width, 40))
      .with_focusable(true)
      .with_tab_stop(true)
      .with_tab_index(2),
    )
  viewport_prepaint(row, 800, 40)
}

///|
test "unchanged core gap frozen geometry misses moved ordinary button edges" {
  let initial = bounds_frame(378)
  let first_focused = bounds_frame(380)
  let second_focused = bounds_frame(376)
  let retained = owner_test_focus(initial.tree(), 2)
  let owner = owner_test_capture(retained)
  assert_true(
    viewport_node(retained, 2).bounds() == element_rect(16, 0, 378, 40),
  )
  assert_true(
    viewport_node(first_focused.tree(), 3).bounds() ==
    element_rect(408, 0, 376, 40),
  )
  assert_true(
    viewport_node(second_focused.tree(), 3).bounds() ==
    element_rect(404, 0, 380, 40),
  )
  assert_true(retained.hit_test(element_point(395, 20)) == Some(1))
  assert_true(first_focused.tree().hit_test(element_point(395, 20)) == Some(2))
  assert_true(retained.hit_test(element_point(405, 20)) == Some(1))
  assert_true(second_focused.tree().hit_test(element_point(405, 20)) == Some(3))
  // Replacing the tree fixes bounds but correctly rejects retained ownership.
  assert_true(
    first_focused.tree().with_focus_owner(owner) is Err(UnknownElement),
  )
  assert_true(retained.focus_owner() == Some(owner))
}

///|
test "layout bounds refresh moves both ordinary button edges without replacing focus" {
  let initial = bounds_frame(378)
  let retained = owner_test_focus(initial.tree(), 2)
  let owner = owner_test_capture(retained)
  let fresh = bounds_frame(380)
  let refreshed = retained.with_layout_bounds(fresh).unwrap()
  assert_true(refreshed.hit_test(element_point(395, 20)) == Some(2))
  assert_true(refreshed.hit_test(element_point(407, 20)) == Some(1))
  assert_true(retained.hit_test(element_point(395, 20)) == Some(1))
  assert_true(retained.hit_test(element_point(407, 20)) == Some(3))
  assert_true(refreshed.focused() == Some(2))
  assert_true(refreshed.focus_owner() == Some(owner))
  assert_true(
    refreshed.clear_focus().with_focus_owner(owner).unwrap().focus_owner() ==
    Some(owner),
  )
  assert_true(fresh.tree().focused() is None)
  assert_true(fresh.tree().with_focus_owner(owner) is Err(UnknownElement))
  let next = refreshed.with_layout_bounds(bounds_frame(376)).unwrap()
  assert_true(next.hit_test(element_point(393, 20)) == Some(1))
  assert_true(next.hit_test(element_point(405, 20)) == Some(3))
  assert_true(refreshed.hit_test(element_point(393, 20)) == Some(2))
  assert_true(refreshed.hit_test(element_point(405, 20)) == Some(1))
  assert_true(next.focus_owner() == Some(owner))
  assert_true(retained.focus_owner() == Some(owner))
  assert_true(initial.tree().focused() is None)
}

///|
fn bounds_cards(heights : Array[Double]) -> @element.Prepainted {
  let column = @layout.FlexTreeStyle::new(@layout.FlowDirection::column())
    .with_align(@layout.AlignItems::start())
    .with_gap(12.0)
    .unwrap()
    .with_insets(
      @layout.Insets::new(54, 16, 0, 16).unwrap(),
      @layout.Insets::zero(),
    )
  let mut root = @element.Element::root(1, column)
  for index = 0; index < heights.length(); index = index + 1 {
    let id = (index + 10).to_uint64()
    root = root.with_child(
      @element.Element::new(viewport_item(id, heights[index], 100))
      .with_focusable(true)
      .with_tab_stop(true),
    )
  }
  viewport_prepaint(root, 800, 400)
}

///|
test "layout bounds refresh covers one pixel card edges and immutable snapshots" {
  let initial = bounds_cards([33, 33, 34, 33, 33])
  let retained = owner_test_focus(initial.tree(), 10)
  let owner = owner_test_capture(retained)
  let first = retained
    .with_layout_bounds(bounds_cards([34, 33, 33, 33, 33]))
    .unwrap()
  let card = viewport_node(retained, 10).bounds()
  assert_eq(card.left(), 16)
  assert_eq(card.top(), 54)
  assert_eq(card.size().width(), 100)
  assert_eq(card.size().height(), 33)
  assert_true(
    viewport_node(first, 10).bounds() == element_rect(16, 54, 100, 34),
  )
  assert_true(retained.hit_test(element_point(20, 87)) == Some(1))
  assert_true(first.hit_test(element_point(20, 87)) == Some(10))
  assert_true(retained.hit_test(element_point(20, 99)) == Some(11))
  assert_true(first.hit_test(element_point(20, 99)) == Some(1))
  let last = first
    .with_layout_bounds(bounds_cards([33, 33, 33, 33, 34]))
    .unwrap()
  assert_true(retained.hit_test(element_point(20, 234)) == Some(1))
  assert_true(last.hit_test(element_point(20, 234)) == Some(14))
  assert_true(last.focus_owner() == Some(owner))
  assert_true(first.focus_owner() == Some(owner))
}

///|
fn bounds_leaf(id : UInt64) -> @element.Element {
  @element.Element::new(viewport_item(id, 10, 10))
  .with_focusable(true)
  .with_tab_index(5)
  .with_tab_stop(true)
}

///|
fn bounds_left(width : Double) -> @element.Element {
  @element.Element::new(viewport_item(2, width, 40))
  .with_focusable(true)
  .with_tab_index(1)
  .with_tab_stop(true)
}

///|
fn bounds_right(last : @element.Element) -> @element.Element {
  @element.Element::new(viewport_item(3, 40, 40))
  .with_children_style(
    @layout.FlexTreeStyle::new(@layout.FlowDirection::column()),
  )
  .with_tab_group_index(Some(3))
  .with_child(bounds_leaf(4))
  .with_child(last)
}

///|
fn bounds_pair(
  left : @element.Element,
  right : @element.Element,
) -> @element.Element {
  @element.Element::root(
    1,
    @layout.FlexTreeStyle::new(@layout.FlowDirection::row()),
  )
  .with_child(left)
  .with_child(right)
}

///|
fn bounds_reject_unchanged(
  retained : @element.ElementTree,
  fresh : @element.Prepainted,
  scroll : Bool,
) -> Unit raise {
  let before = retained.nodes()
  let next_before = fresh.tree().nodes()
  let owner = retained.focus_owner()
  let focused = retained.focused()
  if scroll {
    assert_true(
      retained.with_layout_bounds(fresh) is Err(ScrollLayoutBoundsUnsupported),
    )
  } else {
    assert_true(retained.with_layout_bounds(fresh) is Err(LayoutBoundsMismatch))
  }
  assert_true(retained.focus_owner() == owner)
  assert_true(retained.focused() == focused)
  for index = 0; index < before.length(); index = index + 1 {
    assert_true(retained.nodes()[index].bounds() == before[index].bounds())
  }
  for index = 0; index < next_before.length(); index = index + 1 {
    assert_true(
      fresh.tree().nodes()[index].bounds() == next_before[index].bounds(),
    )
  }
}

///|
test "layout bounds refresh atomically rejects every input metadata mismatch" {
  let leaf = bounds_leaf(5)
  let retained = owner_test_focus(
    viewport_prepaint(
      bounds_pair(bounds_left(20), bounds_right(leaf)),
      200,
      100,
    ).tree(),
    5,
  )
  let mismatches = [
    leaf.with_focusable(false),
    leaf.with_tab_index(-7),
    leaf.with_tab_group_index(Some(8)),
    leaf.with_tab_stop(false),
    leaf.with_pointer_events(false),
  ]
  for last in mismatches {
    // Earlier node 2 has already moved when the final node mismatches. No
    // partially updated tree may escape, even on a late validation failure.
    bounds_reject_unchanged(
      retained,
      viewport_prepaint(
        bounds_pair(bounds_left(22), bounds_right(last)),
        200,
        100,
      ),
      false,
    )
  }
}

///|
test "layout bounds refresh rejects IDs preorder parents counts and viewport changes" {
  let leaf = bounds_leaf(5)
  let retained = owner_test_focus(
    viewport_prepaint(
      bounds_pair(bounds_left(20), bounds_right(leaf)),
      200,
      100,
    ).tree(),
    5,
  )
  let row = @layout.FlexTreeStyle::new(@layout.FlowDirection::row())
  let changed_id = bounds_pair(bounds_left(22), bounds_right(bounds_leaf(50)))
  let reordered = @element.Element::root(1, row)
    .with_child(bounds_right(leaf))
    .with_child(bounds_left(22))
  let reparented = bounds_pair(
    bounds_left(22),
    @element.Element::new(viewport_item(3, 40, 40))
    .with_tab_group_index(Some(3))
    .with_children_style(row)
    .with_child(bounds_leaf(4)),
  ).with_child(leaf)
  let removed = bounds_pair(
    bounds_left(22),
    @element.Element::new(viewport_item(3, 40, 40))
    .with_tab_group_index(Some(3))
    .with_children_style(row)
    .with_child(bounds_leaf(4)),
  )
  let added = bounds_pair(bounds_left(22), bounds_right(leaf)).with_child(
    bounds_leaf(6),
  )
  let wrong_root = @element.Element::root(999, row)
    .with_child(bounds_left(22))
    .with_child(bounds_right(leaf))
  for root in [changed_id, reordered, reparented, removed, added, wrong_root] {
    bounds_reject_unchanged(retained, viewport_prepaint(root, 200, 100), false)
  }
  bounds_reject_unchanged(
    retained,
    viewport_prepaint(
      bounds_pair(bounds_left(22), bounds_right(leaf)),
      201,
      100,
    ),
    false,
  )
  let empty = @element.ElementTree::new([]).unwrap()
  bounds_reject_unchanged(
    empty,
    viewport_prepaint(
      bounds_pair(bounds_left(22), bounds_right(leaf)),
      200,
      100,
    ),
    false,
  )
}

///|
test "layout bounds refresh rejects scroll viewports in retained fresh or both trees" {
  let plain = bounds_pair(bounds_left(20), bounds_right(bounds_leaf(5)))
  let scrolling = plain.with_scroll_offset(element_point(0, 0))
  let plain_frame = viewport_prepaint(plain, 200, 100)
  let scroll_frame = viewport_prepaint(scrolling, 200, 100)
  bounds_reject_unchanged(plain_frame.tree(), scroll_frame, true)
  bounds_reject_unchanged(scroll_frame.tree(), plain_frame, true)
  bounds_reject_unchanged(scroll_frame.tree(), scroll_frame, true)
  let nested = bounds_pair(
    bounds_left(22),
    bounds_right(bounds_leaf(5).with_scroll_offset(element_point(0, 0))),
  )
  bounds_reject_unchanged(
    plain_frame.tree(),
    viewport_prepaint(nested, 200, 100),
    true,
  )
}

///|
test "layout bounds refresh accepts paint differences without copying backgrounds" {
  let old_color = lifecycle_color(1, 2, 3)
  let hover_color = lifecycle_color(9, 8, 7)
  let initial = bounds_pair(
    bounds_left(20).with_background(Some(old_color)),
    bounds_right(bounds_leaf(5)),
  )
  let fresh = viewport_prepaint(
    bounds_pair(
      bounds_left(22).with_background(Some(hover_color)),
      bounds_right(bounds_leaf(5)),
    ),
    200,
    100,
  )
  let retained = owner_test_focus(
    viewport_prepaint(initial, 200, 100).tree(),
    2,
  )
  let owner = owner_test_capture(retained)
  let refreshed = retained.with_layout_bounds(fresh).unwrap()
  assert_true(viewport_node(refreshed, 2).background() == Some(old_color))
  assert_true(viewport_node(fresh.tree(), 2).background() == Some(hover_color))
  assert_true(viewport_node(refreshed, 2).bounds().size().width() == 22)
  assert_true(viewport_node(retained, 2).bounds().size().width() == 20)
  assert_true(refreshed.focus_owner() == Some(owner))
  assert_true(fresh.paint().command_at(0).unwrap().color() == Some(hover_color))
  assert_true(
    refreshed.to_scene().command_at(0).unwrap().color() == Some(old_color),
  )
}

///|
test "layout bounds refresh preserves traversal and ownership guard ABA reset semantics" {
  let initial = bounds_pair(bounds_left(20), bounds_right(bounds_leaf(5)))
  let fresh = viewport_prepaint(
    bounds_pair(bounds_left(22), bounds_right(bounds_leaf(5))),
    200,
    100,
  )
  let retained = owner_test_focus(
    viewport_prepaint(initial, 200, 100).tree(),
    2,
  )
  let pending_owner = owner_test_capture(retained)
  let refreshed = retained.with_layout_bounds(fresh).unwrap()
  // These are caller-side owner guards. This API does not implement a click
  // recognizer; it must leave an already armed acquisition usable unchanged.
  assert_true(refreshed.focus_owner() == Some(pending_owner))
  assert_true(
    refreshed.dispatch_pointer(element_point(21, 20)).target() == Some(2),
  )
  assert_true(
    refreshed
    .dispatch_input(
      @primitives.KeyPressed(
        key=@primitives.Space,
        modifiers=@primitives.Modifiers::none(),
        repeat=false,
      ),
    )
    .target() ==
    Some(2),
  )
  assert_true(tab_walk(refreshed, 5, false) == [4, 5, 2, 4, 5])
  assert_true(tab_walk(refreshed, 5, true) == [5, 4, 2, 5, 4])
  let same_id = owner_test_focus(refreshed, 2)
  assert_true(same_id.focus_owner() != Some(pending_owner))
  let aba = owner_test_focus(owner_test_focus(refreshed, 5), 2)
    .with_layout_bounds(fresh)
    .unwrap()
  assert_true(aba.focus_owner() != Some(pending_owner))
  let reset = refreshed.clear_focus().with_layout_bounds(fresh).unwrap()
  assert_true(reset.focused() is None)
  assert_true(reset.focus_owner() is None)
  let replaced = @element.ElementTree::new(refreshed.nodes()).unwrap()
  assert_true(replaced.with_focus_owner(pending_owner) is Err(UnknownElement))
  // A modal restore after bounds refresh still uses the exact acquisition.
  let modal = owner_test_focus(refreshed, 5)
  let modal_owner = owner_test_capture(modal)
  let modal_refreshed = modal.with_layout_bounds(fresh).unwrap()
  let restored = modal_refreshed.restore_focus(Some(pending_owner), modal_owner)
  assert_true(restored.focus_owner() == Some(pending_owner))
  let deliberate = owner_test_focus(modal_refreshed, 5)
  assert_true(
    deliberate.restore_focus(Some(pending_owner), modal_owner).focus_owner() ==
    deliberate.focus_owner(),
  )
}

///|
fn bounds_pending_matches(
  tree : @element.ElementTree,
  owner : @element.FocusOwner,
  position : @primitives.Point,
) -> Bool {
  tree.focus_owner() == Some(owner) &&
  tree.hit_test(position) == Some(owner.id())
}

///|
test "layout bounds refresh retains pending same-target guards and rejects stale acquisitions" {
  let retained = owner_test_focus(bounds_frame(378).tree(), 2)
  let pending = owner_test_capture(retained)
  let refreshed = retained.with_layout_bounds(bounds_frame(380)).unwrap()
  assert_true(
    bounds_pending_matches(refreshed, pending, element_point(395, 20)),
  )
  assert_false(
    bounds_pending_matches(retained, pending, element_point(395, 20)),
  )
  assert_false(
    bounds_pending_matches(refreshed, pending, element_point(409, 20)),
  )
  let same_id_new_owner = owner_test_focus(refreshed, 2)
  assert_false(
    bounds_pending_matches(same_id_new_owner, pending, element_point(395, 20)),
  )
  let aba = owner_test_focus(owner_test_focus(refreshed, 3), 2)
  assert_false(bounds_pending_matches(aba, pending, element_point(395, 20)))
  assert_false(
    bounds_pending_matches(
      refreshed.clear_focus(),
      pending,
      element_point(395, 20),
    ),
  )
  let new_tree = owner_test_focus(bounds_frame(380).tree(), 2)
  assert_false(
    bounds_pending_matches(new_tree, pending, element_point(395, 20)),
  )
}

///|
test "layout bounds refresh rejects a retained root origin change" {
  let fresh = bounds_frame(380)
  let nodes = bounds_frame(378).tree().nodes()
  nodes[0] = @element.ElementNode::new(1, None, element_rect(1, 0, 800, 40))
  let retained = owner_test_focus(@element.ElementTree::new(nodes).unwrap(), 2)
  bounds_reject_unchanged(retained, fresh, false)
}
