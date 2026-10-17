///|
fn anchor_size(width : Double, height : Double) -> @primitives.Size {
  @primitives.Size::new(width, height).unwrap()
}

///|
fn anchor_point(x : Double, y : Double) -> @primitives.Point {
  @primitives.Point::new(x, y).unwrap()
}

///|
fn anchor_item(id : UInt64, main : Double, cross : Double) -> @layout.FlexItem {
  @layout.FlexItem::new(
    id,
    @layout.Dimension::points(main).unwrap(),
    @layout.Dimension::points(cross).unwrap(),
    anchor_size(0, 0),
  )
  .with_flex(0, 0)
  .unwrap()
}

///|
fn anchor_popup(
  id : UInt64,
  width : Double,
  height : Double,
  interactive : Bool,
) -> @element.Element {
  @element.Element::new(anchor_item(id, width, height))
  .with_pointer_events(interactive)
  .with_background(Some(@primitives.Color::rgba(0, 0, 0, 255).unwrap()))
}

///|
fn anchor_parent() -> @element.Element {
  @element.Element::new(anchor_item(2, 160, 120))
  .with_children_style(
    @layout.FlexTreeStyle::new(@layout.FlowDirection::column()),
  )
  .with_child(
    @element.Element::new(anchor_item(3, 65, 120))
    .with_focusable(true)
    .with_tab_stop(true),
  )
}

///|
fn anchor_root(
  parent : @element.Element,
  x : Double,
  y : Double,
) -> @element.Element {
  @element.Element::root(
    1,
    @layout.FlexTreeStyle::new(@layout.FlowDirection::row()).with_insets(
      @layout.Insets::new(y, 0, 0, x).unwrap(),
      @layout.Insets::zero(),
    ),
  ).with_child(parent)
}

///|
fn anchor_attachment(
  anchor : @element.Anchor,
  mode : @element.AnchoredPositionMode,
  position : @primitives.Point,
  width : Double,
  height : Double,
) -> @element.Element {
  @element.Element::anchored_after(
    20,
    3,
    anchor_popup(10, width, height, false),
    anchor,
    mode,
    position,
  )
  .unwrap()
  .deferred()
  .unwrap()
}

///|
// Expected bounds are observations from the configured frames of the genuine
// GPUI diagnostic at upstream 5a5fbe79917971a4d52a96b6ddb04da198a5012e.
// They are assertions only; inputs are authored ordinary dimensions and a
// real popup subtree. In particular no popup rectangle is passed to layout.
test "anchored lifecycle matches eight observed source anchors and Block static origin" {
  for
    (anchor, px, py, x, y) in [
      (@element.TopLeft, 0.0, 0.0, 80.0, 145.0),
      (@element.TopCenter, 60.0, 0.0, 90.0, 145.0),
      (@element.TopRight, 120.0, 0.0, 100.0, 145.0),
      (@element.LeftCenter, 120.0, -32.5, 200.0, 100.0),
      (@element.RightCenter, 0.0, -32.5, 0.0, 100.0),
      (@element.BottomLeft, 0.0, -65.0, 80.0, 56.0),
      (@element.BottomCenter, 60.0, -65.0, 90.0, 56.0),
      (@element.BottomRight, 120.0, -65.0, 100.0, 56.0),
    ] {
    let tree = anchor_root(
        anchor_parent().with_child(
          anchor_attachment(
            anchor,
            @element.Local,
            anchor_point(px, py),
            100,
            24,
          ),
        ),
        80,
        80,
      )
      .request_layout_with_device_scale(anchor_size(640, 480), 1)
      .unwrap()
      .prepaint()
      .unwrap()
      .tree()
    anchor_assert_rect(
      tree.node(20).unwrap().bounds(),
      @primitives.Rect::new(80, 145, 100, 24).unwrap(),
    )
    anchor_assert_rect(
      tree.node(10).unwrap().bounds(),
      @primitives.Rect::new(x, y, 100, 24).unwrap(),
    )
    anchor_assert_rect(
      tree.node(2).unwrap().bounds(),
      @primitives.Rect::new(80, 80, 160, 120).unwrap(),
    )
    anchor_assert_rect(
      tree.node(3).unwrap().bounds(),
      @primitives.Rect::new(80, 80, 120, 65).unwrap(),
    )
    assert_eq(tree.path_to_root(10).unwrap(), [1, 2, 20, 10])
  }
}

///|
test "anchored lifecycle distinguishes Window and Local and snaps all overflow edges" {
  for
    (mode, px, py, x, y) in [
      (@element.Local, 160.0, 120.0, 240.0, 265.0),
      (@element.Window, 160.0, 120.0, 160.0, 120.0),
      (@element.Window, -20.0, 120.0, 0.0, 120.0),
      (@element.Window, 630.0, 120.0, 560.0, 120.0),
      (@element.Window, 160.0, -8.0, 160.0, 0.0),
      (@element.Window, 160.0, 470.0, 160.0, 456.0),
    ] {
    let frame = anchor_root(
        anchor_parent().with_child(
          anchor_attachment(
            @element.TopLeft,
            mode,
            anchor_point(px, py),
            80,
            24,
          ),
        ),
        80,
        80,
      )
      .request_layout_with_device_scale(anchor_size(640, 480), 1)
      .unwrap()
      .prepaint()
      .unwrap()
    anchor_assert_rect(
      frame.tree().node(10).unwrap().bounds(),
      @primitives.Rect::new(x, y, 80, 24).unwrap(),
    )
  }
  let oversized = anchor_root(
      anchor_parent().with_child(
        anchor_attachment(
          @element.TopLeft,
          @element.Window,
          anchor_point(80, 60),
          240,
          160,
        ),
      ),
      8,
      8,
    )
    .request_layout_with_device_scale(anchor_size(160, 120), 1)
    .unwrap()
    .prepaint()
    .unwrap()
  anchor_assert_point(
    oversized.tree().node(20).unwrap().bounds().origin(),
    anchor_point(8, 73),
  )
  anchor_assert_rect(
    oversized.tree().node(10).unwrap().bounds(),
    @primitives.Rect::new(0, 0, 240, 160).unwrap(),
  )
  assert_true(oversized.overflow())
}

///|
test "anchored logical ties away precede independent device offset snapping" {
  for
    (scale, delta, static_y) in [
      (1.0, 1.0, 145.0),
      (1.25, 0.8, 144.8),
      (2.0, 1.0, 145.0),
    ] {
    for
      (anchor, position, sign) in [
        (@element.TopLeft, anchor_point(0.5, 0.5), 1.0),
        (@element.BottomRight, anchor_point(23.5, 11.5), -1.0),
      ] {
      let frame = anchor_root(
          anchor_parent().with_child(
            anchor_attachment(anchor, @element.Local, position, 24, 12),
          ),
          40,
          80,
        )
        .request_layout_with_device_scale(anchor_size(640, 480), scale)
        .unwrap()
        .prepaint()
        .unwrap()
      let tree = frame.tree()
      assert_true(
        (tree.node(20).unwrap().bounds().top() - static_y).abs() < 0.000001,
      )
      let popup = tree.node(10).unwrap().bounds()
      assert_true((popup.left() - (40 + sign * delta)).abs() < 0.000001)
      assert_true((popup.top() - (static_y + sign * delta)).abs() < 0.000001)
      // A single physical rounding would produce +/-0.4 at1.25x and
      // +/-0.5 at2x, instead of the source's two-stage movement.
      assert_true((popup.left() - 40).abs() > 0.79)
    }
  }
}

///|
test "anchored flat deferred ties paint after ordinary siblings and retain input identity" {
  let mut parent = anchor_parent()
  for index = 0; index < 3; index = index + 1 {
    let popup = anchor_popup(10 + index.to_uint64(), 80, 24, true)
      .with_focusable(true)
      .with_tab_stop(true)
    parent = parent.with_child(
      @element.Element::anchored_after(
        20 + index.to_uint64(),
        3,
        popup,
        @element.TopLeft,
        @element.Window,
        anchor_point(220, 180),
      )
      .unwrap()
      .deferred()
      .unwrap(),
    )
  }
  let sibling = anchor_popup(30, 120, 200, true)
    .with_focusable(true)
    .with_tab_stop(true)
  let frame = anchor_root(parent, 80, 80)
    .with_child(sibling)
    .request_layout_with_device_scale(anchor_size(640, 480), 1)
    .unwrap()
    .prepaint()
    .unwrap()
  let tree = frame.tree()
  assert_eq(tree.nodes().map(node => node.id()), [
    1, 2, 3, 20, 10, 21, 11, 22, 12, 30,
  ])
  assert_eq(
    frame
    .paint()
    .commands()
    .filter(command => command.kind() == @scene.Quad)
    .map(command => command.id()),
    [30, 10, 11, 12],
  )
  for id in [20UL, 21UL, 22UL] {
    anchor_assert_point(
      tree.node(id).unwrap().bounds().origin(),
      anchor_point(80, 145),
    )
  }
  let point = anchor_point(250, 190)
  assert_true(tree.hit_test(point) == Some(12))
  assert_eq(tree.dispatch_pointer(point).capture(), [1, 2, 22, 12])
  assert_true(
    tree.with_focus(11).unwrap().focus_next().unwrap().focused() == Some(12),
  )
  assert_true(
    tree.with_focus(12).unwrap().focus_next().unwrap().focused() == Some(30),
  )
  let focused = tree.with_focus(30).unwrap()
  let removed = focused.without_subtree(2).unwrap()
  assert_true(removed.focus_owner() == focused.focus_owner())
  assert_true(removed.hit_test(point) == Some(30))
  assert_true(tree.hit_test(anchor_point(300, 190)) == Some(30))
  let drag : @element.DragSession[String] = @element.DragSession::new()
  let sources = [@element.DragSource::new(12, "popup payload")]
  assert_true(
    drag
    .dispatch(
      tree,
      @primitives.PointerButtonPressed(
        position=point,
        button=@primitives.Primary,
        modifiers=@primitives.Modifiers::none(),
      ),
      sources,
      [],
    )
    .unwrap()
    is @element.Admitted,
  )
  assert_true(drag.snapshot() is @element.Pending(source=12, ..))
  assert_true(
    drag
    .dispatch(
      tree,
      @primitives.PointerMoved(position=anchor_point(255, 190)),
      sources,
      [],
    )
    .unwrap()
    is @element.Activated,
  )
  assert_true(
    drag.snapshot() is @element.Active(source=12, payload="popup payload", ..),
  )
}

///|
test "anchored transparent popup preserves ordinary hits and refresh rejects incompatible metadata atomically" {
  let attachment = anchor_attachment(
    @element.TopLeft,
    @element.Window,
    anchor_point(220, 180),
    80,
    24,
  )
  let root = anchor_root(anchor_parent().with_child(attachment), 80, 80).with_child(
    anchor_popup(30, 120, 200, true),
  )
  let frame = root
    .request_layout(anchor_size(640, 480))
    .unwrap()
    .prepaint()
    .unwrap()
  assert_true(frame.tree().hit_test(anchor_point(250, 190)) == Some(30))
  let retained = frame.tree().with_focus(3).unwrap()
  let refreshed = retained.with_layout_bounds(frame).unwrap()
  assert_true(refreshed.focus_owner() == retained.focus_owner())
  let inline = @element.Element::anchored_after(
    20,
    3,
    anchor_popup(10, 80, 24, false),
    @element.TopLeft,
    @element.Window,
    anchor_point(220, 180),
  ).unwrap()
  let incompatible = anchor_root(anchor_parent().with_child(inline), 80, 80)
    .with_child(anchor_popup(30, 120, 200, true))
    .request_layout(anchor_size(640, 480))
    .unwrap()
    .prepaint()
    .unwrap()
  assert_true(
    retained.with_layout_bounds(incompatible)
    is Err(@element.LayoutBoundsMismatch),
  )
  assert_true(retained.focus_owner() == refreshed.focus_owner())
  assert_eq(
    retained.nodes().map(node => node.id()),
    refreshed.nodes().map(node => node.id()),
  )
}

///|
test "anchored rejects unsupported shape and dynamic compositions before callbacks" {
  let attachment = anchor_attachment(
    @element.TopLeft,
    @element.Local,
    anchor_point(0, 0),
    100,
    24,
  )
  assert_true(
    attachment.deferred() is Err(@element.UnsupportedAnchoredComposition),
  )
  assert_true(
    anchor_popup(10, 80, 24, false).deferred()
    is Err(@element.UnsupportedAnchoredComposition),
  )
  assert_true(
    @element.Element::anchored_after(
      21,
      3,
      attachment,
      @element.TopLeft,
      @element.Local,
      anchor_point(0, 0),
    )
    is Err(@element.UnsupportedAnchoredComposition),
  )
  let wrong_reference = @element.Element::anchored_after(
    20,
    99,
    anchor_popup(10, 100, 24, false),
    @element.TopLeft,
    @element.Local,
    anchor_point(0, 0),
  ).unwrap()
  assert_true(
    anchor_root(anchor_parent().with_child(wrong_reference), 80, 80).request_layout(
      anchor_size(640, 480),
    )
    is Err(@element.InvalidAnchoredShape),
  )
  let gap_parent = anchor_parent()
    .with_children_style(
      @layout.FlexTreeStyle::new(@layout.FlowDirection::column())
      .with_gap(1)
      .unwrap(),
    )
    .with_child(attachment)
  assert_true(
    anchor_root(gap_parent, 80, 80).request_layout(anchor_size(640, 480))
    is Err(@element.InvalidAnchoredShape),
  )
  let normal = anchor_root(anchor_parent().with_child(attachment), 80, 80)
  assert_true(
    normal
    .with_scroll_offset(anchor_point(0, 0))
    .request_layout(anchor_size(640, 480))
    is Err(@element.UnsupportedAnchoredComposition),
  )
  let query = @element.Element::new(anchor_item(40, 10, 10)).with_container_query(_ => {
      abort("rejected query callback must not run")
    },
  )
  assert_true(
    normal.with_child(query).request_layout(anchor_size(640, 480))
    is Err(@element.UnsupportedAnchoredComposition),
  )
  let list = @element.UniformList::new(
      anchor_item(50, 10, 10),
      0,
      @element.UniformListIdSpace::new(100, 2).unwrap(),
      _ => abort("rejected list factory must not run"),
    )
    .unwrap()
    .into_element()
  assert_true(
    normal.with_child(list).request_layout(anchor_size(640, 480))
    is Err(@element.UnsupportedAnchoredComposition),
  )
  let generated = @element.Element::container_query_root(60, _ => Ok(normal))
  assert_true(
    generated.request_layout(anchor_size(640, 480)).unwrap().prepaint()
    is Err(@element.UnsupportedAnchoredComposition),
  )
}

///|
fn anchor_assert_rect(
  actual : @primitives.Rect,
  expected : @primitives.Rect,
) -> Unit raise {
  assert_eq(actual.left(), expected.left())
  assert_eq(actual.top(), expected.top())
  assert_eq(actual.size().width(), expected.size().width())
  assert_eq(actual.size().height(), expected.size().height())
}

///|
fn anchor_assert_point(
  actual : @primitives.Point,
  expected : @primitives.Point,
) -> Unit raise {
  assert_eq(actual.x(), expected.x())
  assert_eq(actual.y(), expected.y())
}

///|
test "anchored oversized paint retains viewport clips and half open hit boundaries" {
  let popup = anchor_popup(10, 240, 160, true)
  let attachment = @element.Element::anchored_after(
      20,
      3,
      popup,
      @element.TopLeft,
      @element.Window,
      anchor_point(80, 60),
    )
    .unwrap()
    .deferred()
    .unwrap()
  let frame = anchor_root(anchor_parent().with_child(attachment), 8, 8)
    .request_layout_with_device_scale(anchor_size(160, 120), 1)
    .unwrap()
    .prepaint()
    .unwrap()
  let tree = frame.tree()
  assert_true(tree.hit_test(anchor_point(159.5, 119.5)) == Some(10))
  assert_true(tree.hit_test(anchor_point(160, 119)) is None)
  assert_true(tree.hit_test(anchor_point(159, 120)) is None)
  assert_true(tree.hit_test(anchor_point(-0.1, 0)) is None)
  assert_true(tree.hit_test(anchor_point(0, 0)) == Some(10))
  let scene = frame.paint()
  assert_true(scene.validate() is Ok(_))
  let clips = scene
    .commands()
    .filter(command => command.kind() == @scene.ClipPush)
  assert_eq(clips.length(), 2)
  for clip in clips {
    anchor_assert_rect(
      clip.bounds().unwrap(),
      @primitives.Rect::new(0, 0, 160, 120).unwrap(),
    )
  }
  let snapshot = frame.paint_snapshot(1).unwrap()
  assert_eq(snapshot.items().length(), 1)
  assert_true(snapshot.items()[0].clip_chain_id() is Some(_))
  anchor_assert_rect(
    snapshot.clip_chains()[0].rects()[0],
    @primitives.Rect::new(0, 0, 160, 120).unwrap(),
  )
}

///|
test "anchored snapshot reassembly rejects scroll composition" {
  let root = anchor_root(
    anchor_parent().with_child(
      anchor_attachment(
        @element.TopLeft,
        @element.Window,
        anchor_point(220, 180),
        80,
        24,
      ),
    ),
    80,
    80,
  )
  let tree = root
    .request_layout(anchor_size(640, 480))
    .unwrap()
    .prepaint()
    .unwrap()
    .tree()
  let scrolled = @element.Element::root(
      50,
      @layout.FlexTreeStyle::new(@layout.FlowDirection::column()),
    )
    .with_scroll_offset(anchor_point(0, 0))
    .with_child(@element.Element::new(anchor_item(51, 100, 40)))
    .request_layout(anchor_size(40, 40))
    .unwrap()
    .prepaint()
    .unwrap()
    .tree()
  let combined = tree.nodes()
  for node in scrolled.nodes() {
    combined.push(node)
  }
  assert_true(
    @element.ElementTree::new(combined)
    is Err(@element.UnsupportedAnchoredComposition),
  )
  assert_true(tree.hit_test(anchor_point(250, 190)) is Some(_))
}

///|
test "anchored reference removal and wrapper input mutation reject atomically" {
  let frame = anchor_root(
      anchor_parent().with_child(
        anchor_attachment(
          @element.TopLeft,
          @element.Local,
          anchor_point(0, 0),
          100,
          24,
        ),
      ),
      80,
      80,
    )
    .request_layout(anchor_size(640, 480))
    .unwrap()
    .prepaint()
    .unwrap()
  let tree = frame.tree().with_focus(3).unwrap()
  let owner = tree.focus_owner()
  assert_true(tree.without_subtree(3) is Err(@element.InvalidAnchoredShape))
  assert_true(tree.focus_owner() == owner)
  assert_true(tree.node(3) is Some(_))
  let without_attachment = tree.without_subtree(20).unwrap()
  assert_true(without_attachment.node(20) is None)
  assert_true(without_attachment.node(10) is None)
  assert_true(without_attachment.node(3) is Some(_))
  assert_true(without_attachment.focus_owner() == owner)
  assert_true(without_attachment.to_scene().validate() is Ok(_))
  assert_true(tree.without_subtree(2).unwrap().node(10) is None)
  let altered = tree.nodes()
  altered[3] = altered[3].with_pointer_events(true)
  assert_true(
    @element.ElementTree::new(altered) is Err(@element.InvalidAnchoredShape),
  )
}

///|
test "anchored deferred hit routes retain integrated focus scope truncation" {
  let popup = anchor_popup(10, 80, 24, true)
    .with_focusable(true)
    .with_tab_stop(true)
  let attachment = @element.Element::anchored_after(
      20,
      3,
      popup,
      @element.TopLeft,
      @element.Window,
      anchor_point(220, 180),
    )
    .unwrap()
    .deferred()
    .unwrap()
  let frame = anchor_root(
      anchor_parent().with_focusable(true).with_child(attachment),
      80,
      80,
    )
    .with_child(
      anchor_popup(30, 120, 200, true).with_focusable(true).with_tab_stop(true),
    )
    .request_layout(anchor_size(640, 480))
    .unwrap()
    .prepaint()
    .unwrap()
  let tree = frame.tree()
  let session = @element.FocusScopeSession::new(tree).unwrap()
  let _ = session.open_scope(session.target(), 2, _ => Ok(())).unwrap()
  let outcome = session
    .dispatch_input_with(
      session.target(),
      @primitives.PointerMoved(position=anchor_point(250, 190)),
      (_, _) => Ok(()),
    )
    .unwrap()
  assert_true(outcome.target() == Some(10))
  assert_eq(outcome.capture_visited(), [2, 20, 10])
  assert_eq(outcome.bubble_visited(), [10, 20, 2])
  let unrelated = @element.FocusScopeSession::new(tree).unwrap()
  let _ = unrelated.open_scope(unrelated.target(), 30, _ => Ok(())).unwrap()
  let blocked = unrelated
    .dispatch_input_with(
      unrelated.target(),
      @primitives.PointerMoved(position=anchor_point(250, 190)),
      (_, _) => Ok(()),
    )
    .unwrap()
  assert_true(blocked.target() is None)
  assert_eq(blocked.capture_visited(), [])
  assert_eq(blocked.bubble_visited(), [])
}
