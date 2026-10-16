///|
// Source-derived contract tests for the bounded two-axis viewport slice.
// These assertions are not a substitute for an executed Rust/browser oracle.
fn viewport_item(
  id : UInt64,
  main : Double,
  cross : Double,
) -> @layout.FlexItem {
  match lifecycle_item(id, main, cross).with_flex(0.0, 0.0) {
    Ok(item) => item
    Err(_) => abort("valid flex factors rejected")
  }
}

///|
fn viewport_prepaint(
  root : @element.Element,
  width : Double,
  height : Double,
) -> @element.Prepainted {
  let requested = match root.request_layout(lifecycle_size(width, height)) {
    Ok(value) => value
    Err(_) => abort("valid viewport layout rejected")
  }
  match requested.prepaint() {
    Ok(value) => value
    Err(_) => abort("valid viewport prepaint rejected")
  }
}

///|
fn viewport_of(
  tree : @element.ElementTree,
  id : UInt64,
) -> @element.ScrollViewport {
  match tree.scroll_viewport(id) {
    Some(value) => value
    None => abort("scroll viewport missing")
  }
}

///|
fn viewport_node(
  tree : @element.ElementTree,
  id : UInt64,
) -> @element.ElementNode {
  match tree.node(id) {
    Some(value) => value
    None => abort("viewport node missing")
  }
}

///|
fn viewport_nested(
  outer_y : Double,
  inner_x : Double,
  inner_y : Double,
) -> @element.Element {
  let column = @layout.FlexTreeStyle::new(@layout.FlowDirection::column())
  let row = @layout.FlexTreeStyle::new(@layout.FlowDirection::row())
  let color = lifecycle_color(12, 34, 56)
  @element.Element::root(1, column)
  .with_scroll_offset(element_point(0.0, outer_y))
  .with_background(Some(color))
  .with_child(
    @element.Element::new(viewport_item(2, 180.0, 100.0))
    .with_children_style(column)
    .with_child(
      @element.Element::new(viewport_item(3, 40.0, 100.0)).with_background(
        Some(color),
      ),
    )
    .with_child(
      @element.Element::new(viewport_item(4, 50.0, 80.0))
      .with_scroll_offset(element_point(inner_x, inner_y))
      .with_children_style(row)
      .with_background(Some(color))
      .with_child(
        @element.Element::new(viewport_item(5, 200.0, 90.0))
        .with_background(Some(color))
        .with_focusable(true),
      ),
    )
    .with_child(
      @element.Element::new(viewport_item(6, 40.0, 100.0)).with_background(
        Some(color),
      ),
    ),
  )
}

///|
test "scroll viewports compose ancestor offsets and unwind before siblings" {
  let prepainted = viewport_prepaint(
    viewport_nested(20.0, 30.0, 10.0),
    100.0,
    100.0,
  )
  let tree = prepainted.tree()
  assert_true(viewport_node(tree, 1).bounds() == element_rect(0, 0, 100, 100))
  assert_true(viewport_node(tree, 2).bounds() == element_rect(0, -20, 100, 180))
  assert_true(viewport_node(tree, 4).bounds() == element_rect(0, 20, 80, 50))
  assert_true(viewport_node(tree, 5).bounds() == element_rect(-30, 10, 200, 90))
  assert_true(viewport_node(tree, 6).bounds() == element_rect(0, 70, 100, 40))
  assert_true(viewport_of(tree, 1).max_offset() == element_point(0, 80))
  assert_true(viewport_of(tree, 4).max_offset() == element_point(120, 40))
  assert_true(viewport_of(tree, 4).bounds() == viewport_node(tree, 4).bounds())
  assert_true(tree.scroll_viewport(2) is None)
  assert_true(tree.scroll_viewport(999) is None)
}

///|
test "scroll hit testing intersects every ancestor clip with half-open edges" {
  let tree = viewport_prepaint(viewport_nested(20, 30, 10), 100, 100).tree()
  assert_true(tree.hit_test(element_point(0, 20)) == Some(5))
  assert_true(tree.hit_test(element_point(79.999, 69.999)) == Some(5))
  assert_true(tree.hit_test(element_point(10, 19.999)) == Some(3))
  assert_true(tree.hit_test(element_point(80, 30)) == Some(2))
  assert_true(tree.hit_test(element_point(10, 70)) == Some(6))
  assert_true(tree.hit_test(element_point(-0.001, 30)) is None)
  assert_true(tree.hit_test(element_point(10, 100)) is None)
  assert_true(
    tree.dispatch_pointer(element_point(10, 30)).bubble() == [5, 4, 2, 1],
  )
}

///|
test "scroll paint orders backgrounds and balances nested clips before siblings" {
  let prepainted = viewport_prepaint(viewport_nested(20, 30, 10), 100, 100)
  let commands = prepainted.paint().commands()
  let kinds = commands.map(command => command.kind())
  let ids = commands.map(command => command.id())
  assert_true(
    kinds ==
    [
      @scene.Quad,
      @scene.ClipPush,
      @scene.Quad,
      @scene.Quad,
      @scene.ClipPush,
      @scene.Quad,
      @scene.ClipPop,
      @scene.Quad,
      @scene.ClipPop,
    ],
  )
  assert_true(ids == [1, 1, 3, 4, 4, 5, 4, 6, 1])
  assert_true(commands[1].bounds() == Some(element_rect(0, 0, 100, 100)))
  assert_true(commands[4].bounds() == Some(element_rect(0, 20, 80, 50)))
  assert_true(prepainted.paint_snapshot(1.0) is Ok(_))
}

///|
test "scroll wheel gives the same dominant delta to each ancestor and clamps independently" {
  let tree = viewport_prepaint(viewport_nested(20, 30, 10), 100, 100).tree()
  let updates = match tree.scroll_wheel(element_point(10, 30), 5.0, 50.0) {
    Ok(value) => value
    Err(_) => fail("finite wheel update rejected")
  }
  assert_true(updates.length() == 2)
  assert_true(updates[0].id() == 4 && updates[1].id() == 1)
  assert_true(updates[0].offset() == element_point(30, 40))
  assert_true(updates[1].offset() == element_point(0, 70))
  assert_true(viewport_of(tree, 4).offset() == element_point(30, 10))
  assert_true(viewport_of(tree, 1).offset() == element_point(0, 20))
  let tie = match tree.scroll_wheel(element_point(10, 30), -10.0, -10.0) {
    Ok(value) => value
    Err(_) => fail("finite wheel tie rejected")
  }
  assert_true(tie[0].offset() == element_point(30, 0))
  assert_true(tie[1].offset() == element_point(0, 10))
  let horizontal = match tree.scroll_wheel(element_point(10, 30), 15.0, 10.0) {
    Ok(value) => value
    Err(_) => fail("finite horizontal wheel rejected")
  }
  assert_true(horizontal[0].offset() == element_point(45, 10))
  assert_true(horizontal[1].offset() == element_point(0, 20))
  let outside_inner = match
    tree.scroll_wheel(element_point(85, 30), 0.0, 10.0) {
    Ok(value) => value
    Err(_) => fail("finite wheel outside inner rejected")
  }
  assert_true(outside_inner.length() == 1)
  assert_true(outside_inner[0].id() == 1)
  assert_true(tree.scroll_wheel(element_point(100, 30), 0.0, 10.0) is Ok([]))
}

///|
test "scroll maxima use direct child union plus padding and round to two decimals" {
  let padding = match @layout.Insets::new(11, 7, 13, 5) {
    Ok(value) => value
    Err(_) => fail("valid padding rejected")
  }
  let style = @layout.FlexTreeStyle::new(@layout.FlowDirection::row()).with_insets(
    padding,
    @layout.Insets::zero(),
  )
  let root = @element.Element::root(1, style)
    .with_scroll_offset(element_point(999, 999))
    .with_child(@element.Element::new(viewport_item(2, 100, 150)))
  let viewport = viewport_of(viewport_prepaint(root, 100, 100).tree(), 1)
  assert_true(viewport.max_offset() == element_point(12, 74))
  assert_true(viewport.offset() == element_point(12, 74))
  let rounded = @element.Element::root(
      1,
      @layout.FlexTreeStyle::new(@layout.FlowDirection::row()),
    )
    .with_scroll_offset(element_point(99, 99))
    .with_child(@element.Element::new(viewport_item(2, 100.004, 100.006)))
  let viewport = viewport_of(viewport_prepaint(rounded, 100, 100).tree(), 1)
  assert_true(viewport.max_offset() == element_point(0, 0.01))
  assert_true(viewport.offset() == element_point(0, 0.01))
}

///|
test "scroll layout retains caller offsets and reclamps after content shrinks" {
  let big = viewport_prepaint(viewport_nested(999, 999, -999), 100, 100).tree()
  assert_true(viewport_of(big, 1).offset() == element_point(0, 80))
  assert_true(viewport_of(big, 4).offset() == element_point(120, 0))
  let rebuilt = viewport_prepaint(viewport_nested(80, 120, 0), 100, 160).tree()
  assert_true(viewport_of(rebuilt, 1).offset() == element_point(0, 20))
  assert_true(viewport_of(rebuilt, 4).offset() == element_point(120, 0))
  assert_true(viewport_of(big, 1).offset() == element_point(0, 80))
}

///|
test "scroll rejects non-finite wheel deltas atomically and saturates finite overflow" {
  let tree = viewport_prepaint(viewport_nested(20, 30, 10), 100, 100).tree()
  assert_true(
    tree.scroll_wheel(element_point(10, 30), @double.not_a_number, 1.0)
    is Err(@element.NonFiniteValue),
  )
  assert_true(
    tree.scroll_wheel(element_point(10, 30), 1.0, @double.infinity)
    is Err(@element.NonFiniteValue),
  )
  assert_true(
    tree.scroll_wheel(element_point(999, 999), @double.infinity, 0.0)
    is Err(@element.NonFiniteValue),
  )
  let maximum = match
    tree.scroll_wheel(element_point(10, 30), 0.0, 1.7976931348623157e308) {
    Ok(value) => value
    Err(_) => fail("finite saturating update rejected")
  }
  assert_true(maximum[0].offset() == element_point(30, 40))
  assert_true(maximum[1].offset() == element_point(0, 80))
}

///|
test "scroll queries preserve focus ownership and defensive tree copies" {
  let tree = viewport_prepaint(viewport_nested(20, 30, 10), 100, 100).tree()
  let focused = match tree.with_focus(5) {
    Ok(value) => value
    Err(_) => fail("focusable scroll descendant rejected")
  }
  let owner = focused.focus_owner()
  let nodes = focused.nodes()
  nodes.clear()
  let _ = focused.scroll_wheel(element_point(10, 30), 0.0, 10.0)
  assert_true(focused.nodes().length() == 6)
  assert_true(focused.focus_owner() == owner)
  let removed = match focused.without_subtree(4) {
    Ok(value) => value
    Err(_) => fail("scroll subtree removal rejected")
  }
  assert_true(removed.scroll_viewport(4) is None)
  assert_true(removed.focus_owner() is None)
  assert_true(
    removed.to_scene().snapshot_v1(element_rect(0, 0, 100, 100), 1.0) is Ok(_),
  )
}

///|
test "scroll clips and translations unwind before unrelated siblings and roots" {
  let style = @layout.FlexTreeStyle::new(@layout.FlowDirection::row())
  let color = lifecycle_color(10, 20, 30)
  let root = @element.Element::root(1, style)
    .with_child(
      @element.Element::new(viewport_item(2, 100, 100))
      .with_scroll_offset(element_point(30, 40))
      .with_children_style(style)
      .with_child(
        @element.Element::new(viewport_item(3, 200, 200)).with_background(
          Some(color),
        ),
      ),
    )
    .with_child(
      @element.Element::new(viewport_item(4, 100, 100)).with_background(
        Some(color),
      ),
    )
  let prepainted = viewport_prepaint(root, 200, 100)
  let tree = prepainted.tree()
  assert_true(
    viewport_node(tree, 3).bounds() == element_rect(-30, -40, 200, 200),
  )
  assert_true(viewport_node(tree, 4).bounds() == element_rect(100, 0, 100, 100))
  assert_true(tree.hit_test(element_point(100, 50)) == Some(4))
  assert_true(tree.hit_test(element_point(50, 100)) is None)
  assert_true(
    prepainted.paint().commands().map(command => command.kind()) ==
    [@scene.ClipPush, @scene.Quad, @scene.ClipPop, @scene.Quad],
  )
  let nodes = tree.nodes()
  nodes.push(
    @element.ElementNode::new(9, None, element_rect(200, 0, 30, 30)).with_background(
      Some(color),
    ),
  )
  let forest = unwrap_tree(nodes)
  assert_true(forest.hit_test(element_point(210, 10)) == Some(9))
  assert_true(forest.to_scene().validate() is Ok(_))
}

///|
test "scroll limits exclude descendant overflow and include direct child gaps" {
  let style = match
    @layout.FlexTreeStyle::new(@layout.FlowDirection::row()).with_gap(7) {
    Ok(value) => value
    Err(_) => fail("valid gap rejected")
  }
  let root = @element.Element::root(1, style)
    .with_scroll_offset(element_point(999, 999))
    .with_child(
      @element.Element::new(viewport_item(2, 60, 50))
      .with_children_style(style)
      .with_child(@element.Element::new(viewport_item(3, 500, 500))),
    )
    .with_child(@element.Element::new(viewport_item(4, 60, 50)))
  let tree = viewport_prepaint(root, 100, 100).tree()
  assert_true(viewport_of(tree, 1).max_offset() == element_point(27, 0))
  assert_true(viewport_of(tree, 1).offset() == element_point(27, 0))
}

///|
test "scroll empty zero-sized and fully clipped viewports remain safe" {
  let style = @layout.FlexTreeStyle::new(@layout.FlowDirection::row())
  let empty = viewport_prepaint(
    @element.Element::root(1, style).with_scroll_offset(element_point(1, 1)),
    0,
    0,
  )
  assert_true(viewport_of(empty.tree(), 1).max_offset() == element_point(0, 0))
  assert_true(empty.tree().hit_test(element_point(0, 0)) is None)
  assert_true(empty.paint().validate() is Ok(_))
  let invisible = viewport_prepaint(viewport_nested(80, 30, 10), 100, 100)
  // Inner bounds now span y=-40..10; only their last ten pixels are visible.
  assert_true(invisible.tree().hit_test(element_point(10, 0)) == Some(5))
  assert_true(invisible.tree().hit_test(element_point(10, -0.01)) is None)
  let root = @element.Element::root(1, style)
    .with_scroll_offset(element_point(0, 0))
    .with_child(
      @element.Element::new(viewport_item(2, 0, 0))
      .with_scroll_offset(element_point(9, 9))
      .with_children_style(style)
      .with_child(@element.Element::new(viewport_item(3, 50, 50))),
    )
  let zero_inner = viewport_prepaint(root, 100, 100)
  assert_true(zero_inner.tree().hit_test(element_point(0, 0)) == Some(1))
  assert_true(zero_inner.paint().validate() is Ok(_))
}

///|
test "scroll device-scale limits use snapped padding and layout sizes" {
  let padding = match @layout.Insets::all(0.25) {
    Ok(value) => value
    Err(_) => fail("valid fractional padding rejected")
  }
  let style = @layout.FlexTreeStyle::new(@layout.FlowDirection::row()).with_insets(
    padding,
    @layout.Insets::zero(),
  )
  let root = @element.Element::root(1, style)
    .with_scroll_offset(element_point(9, 9))
    .with_child(@element.Element::new(viewport_item(2, 100, 100)))
  let raw = viewport_prepaint(root, 100, 100)
  assert_true(
    viewport_of(raw.tree(), 1).max_offset() == element_point(0.5, 0.5),
  )
  let requested = match
    root.request_layout_with_device_scale(lifecycle_size(100, 100), 2.0) {
    Ok(value) => value
    Err(_) => fail("device scale layout rejected")
  }
  let snapped = match requested.prepaint() {
    Ok(value) => value
    Err(_) => fail("device scale prepaint rejected")
  }
  assert_true(
    viewport_of(snapped.tree(), 1).max_offset() == element_point(0, 0),
  )
}

///|
test "scroll pointer-disabled ancestors still clip but receive no wheel update" {
  let tree = viewport_prepaint(
    viewport_nested(20, 30, 10).with_pointer_events(false),
    100,
    100,
  ).tree()
  let updates = match tree.scroll_wheel(element_point(10, 30), 0, 10) {
    Ok(value) => value
    Err(_) => fail("finite wheel rejected")
  }
  assert_true(updates.length() == 1 && updates[0].id() == 4)
  assert_true(tree.hit_test(element_point(10, 100)) is None)
}

///|
test "scroll public prepaint rejects unrepresentable translated geometry" {
  let style = @layout.FlexTreeStyle::new(@layout.FlowDirection::row())
  let root = @element.Element::root(1, style)
    .with_scroll_offset(element_point(1.0e308, 0))
    .with_child(@element.Element::new(viewport_item(2, 1, 10)))
    .with_child(@element.Element::new(viewport_item(3, 1.0e308, 10)))
  let requested = match root.request_layout(lifecycle_size(10, 10)) {
    Ok(value) => value
    Err(_) => fail("finite large source layout should succeed")
  }
  assert_true(requested.prepaint() is Err(@element.GeometryFailure))
}

///|
fn viewport_scaled(root : @element.Element) -> @element.Prepainted {
  let requested = match
    root.request_layout_with_device_scale(lifecycle_size(100, 100), 2.0) {
    Ok(value) => value
    Err(_) => abort("valid device-scale layout rejected")
  }
  match requested.prepaint() {
    Ok(value) => value
    Err(_) => abort("valid device-scale prepaint rejected")
  }
}

///|
test "scroll device-scale translation snaps the raw cumulative nested offset once" {
  let root = viewport_nested(0.2, 0.2, 0.2)
  let snapped = viewport_scaled(root)
  let tree = snapped.tree()
  // Each 0.2 offset alone snaps to zero at 2x. Their raw sum 0.4 snaps
  // to 0.5, so snapping each viewport before accumulation would be wrong.
  assert_true(viewport_node(tree, 2).bounds().top() == 0)
  assert_true(viewport_node(tree, 4).bounds() == element_rect(0, 40, 80, 50))
  assert_true(viewport_node(tree, 5).bounds() == element_rect(0, 39.5, 200, 90))
  assert_true(viewport_node(tree, 6).bounds().top() == 90)
  assert_true(viewport_of(tree, 1).offset() == element_point(0, 0.2))
  assert_true(viewport_of(tree, 4).offset() == element_point(0.2, 0.2))
  assert_true(tree.hit_test(element_point(10, 39.75)) == Some(3))
  assert_true(tree.hit_test(element_point(10, 40)) == Some(5))
  assert_true(tree.hit_test(element_point(10, 90)) == Some(6))
  let commands = snapped.paint().commands()
  assert_true(commands[4].bounds() == Some(element_rect(0, 40, 80, 50)))
  assert_true(commands[5].bounds() == Some(element_rect(0, 39.5, 200, 90)))
  assert_true(snapped.paint_snapshot(2.0) is Ok(_))
  // The raw logical path deliberately keeps fractional coordinates.
  let raw = viewport_prepaint(root, 100, 100).tree()
  assert_true(viewport_node(raw, 4).bounds().top() == 39.8)
  assert_true(
    viewport_node(raw, 5).bounds() == element_rect(-0.2, 39.6, 200, 90),
  )
}

///|
test "scroll device-scale traversal retains unsnapped ancestors and rounds ties toward zero" {
  let tree = viewport_scaled(viewport_nested(0.3, 0.3, 0.3)).tree()
  assert_true(viewport_node(tree, 4).bounds().top() == 39.5)
  // Reusing the snapped -0.5 ancestor here would sum to -0.8 and snap to
  // -1.0. The correct raw sum is -0.6, which snaps to -0.5.
  assert_true(
    viewport_node(tree, 5).bounds() == element_rect(-0.5, 39.5, 200, 90),
  )
  assert_true(viewport_node(tree, 6).bounds().top() == 89.5)
  let tie = viewport_scaled(viewport_nested(0.25, 0.75, 0.5)).tree()
  assert_true(viewport_node(tie, 4).bounds().top() == 40)
  assert_true(
    viewport_node(tie, 5).bounds() == element_rect(-0.5, 39.5, 200, 90),
  )
  assert_true(viewport_of(tie, 1).offset() == element_point(0, 0.25))
  assert_true(viewport_of(tie, 4).offset() == element_point(0.75, 0.5))
}

///|
fn viewport_axis_gaps(
  direction : @layout.FlowDirection,
) -> @layout.FlexTreeStyle {
  let horizontal = match
    @layout.FlexTreeStyle::new(direction).with_gap_x(3.25) {
    Ok(value) => value
    Err(_) => abort("valid horizontal gap rejected")
  }
  match horizontal.with_gap_y(7.75) {
    Ok(value) => value
    Err(_) => abort("valid vertical gap rejected")
  }
}

///|
test "scroll limits use the physical item gap and its device-scale value" {
  for
    direction in [@layout.FlowDirection::row(), @layout.FlowDirection::column()] {
    let root = @element.Element::root(1, viewport_axis_gaps(direction))
      .with_scroll_offset(element_point(999, 999))
      .with_child(@element.Element::new(viewport_item(2, 60, 50)))
      .with_child(@element.Element::new(viewport_item(3, 60, 50)))
    let raw = viewport_prepaint(root, 100, 100).tree()
    let snapped = viewport_scaled(root).tree()
    let row = direction is @layout.Row
    let raw_limit = if row {
      element_point(23.25, 0)
    } else {
      element_point(0, 27.75)
    }
    let snapped_limit = if row {
      element_point(23, 0)
    } else {
      element_point(0, 27.5)
    }
    assert_true(viewport_of(raw, 1).max_offset() == raw_limit)
    assert_true(viewport_of(raw, 1).offset() == raw_limit)
    assert_true(viewport_of(snapped, 1).max_offset() == snapped_limit)
    assert_true(viewport_of(snapped, 1).offset() == snapped_limit)
    let final_child = if row {
      element_rect(40, 0, 60, 50)
    } else {
      element_rect(0, 40, 50, 60)
    }
    assert_true(viewport_node(raw, 3).bounds() == final_child)
    assert_true(viewport_node(snapped, 3).bounds() == final_child)
    assert_true(raw.hit_test(element_point(45, 45)) == Some(3))
    assert_true(snapped.hit_test(element_point(45, 45)) == Some(3))
    assert_true(raw.hit_test(element_point(-0.01, -0.01)) is None)
    assert_true(snapped.hit_test(element_point(-0.01, -0.01)) is None)
  }
}

///|
test "wrapped scroll limits preserve independent item and line gaps at device scale" {
  for
    direction in [@layout.FlowDirection::row(), @layout.FlowDirection::column()] {
    let style = viewport_axis_gaps(direction)
      .with_wrap(@layout.FlexWrap::wrap())
      .with_align_content(@layout.AlignContent::start())
    let root = @element.Element::root(1, style)
      .with_scroll_offset(element_point(999, 999))
      .with_child(@element.Element::new(viewport_item(2, 40, 60)))
      .with_child(@element.Element::new(viewport_item(3, 40, 60)))
      .with_child(@element.Element::new(viewport_item(4, 40, 60)))
    let raw = viewport_prepaint(root, 100, 100).tree()
    let snapped = viewport_scaled(root).tree()
    let row = direction is @layout.Row
    let raw_limit = if row {
      element_point(0, 27.75)
    } else {
      element_point(23.25, 0)
    }
    let snapped_limit = if row {
      element_point(0, 27.5)
    } else {
      element_point(23, 0)
    }
    assert_true(viewport_of(raw, 1).max_offset() == raw_limit)
    assert_true(viewport_of(raw, 1).offset() == raw_limit)
    assert_true(viewport_of(snapped, 1).max_offset() == snapped_limit)
    assert_true(viewport_of(snapped, 1).offset() == snapped_limit)
    let raw_second = if row {
      element_rect(43.25, -27.75, 40, 60)
    } else {
      element_rect(-23.25, 47.75, 60, 40)
    }
    let snapped_second = if row {
      element_rect(43, -27.5, 40, 60)
    } else {
      element_rect(-23, 47.5, 60, 40)
    }
    assert_true(viewport_node(raw, 3).bounds() == raw_second)
    assert_true(viewport_node(snapped, 3).bounds() == snapped_second)
    let final_child = if row {
      element_rect(0, 40, 40, 60)
    } else {
      element_rect(40, 0, 60, 40)
    }
    assert_true(viewport_node(raw, 4).bounds() == final_child)
    assert_true(viewport_node(snapped, 4).bounds() == final_child)
    let inside_last = if row {
      element_point(20, 99.99)
    } else {
      element_point(99.99, 20)
    }
    let outside_last = if row {
      element_point(20, 100)
    } else {
      element_point(100, 20)
    }
    assert_true(raw.hit_test(inside_last) == Some(4))
    assert_true(snapped.hit_test(inside_last) == Some(4))
    assert_true(raw.hit_test(outside_last) is None)
    assert_true(snapped.hit_test(outside_last) is None)
    assert_true(raw.to_scene().validate() is Ok(_))
    assert_true(snapped.to_scene().validate() is Ok(_))
  }
}
