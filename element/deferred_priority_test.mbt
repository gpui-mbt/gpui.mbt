///|
// These tests run genuine request_layout/prepaint/scene emission. Expected
// attachment-box paint sequences are projected from actual Rust observer
// callbacks in run39024859010/artifact12098386453 (CI7dcd/treee9cc).
// They are not Rust scene captures or lifecycle-callback equality. The helper
// nodes below express the authored offsets through ordinary flex layout.
// Input callback/occlusion parity is explicitly outside this projection.
fn priority_item(
  id : UInt64,
  main : Double,
  cross : Double,
) -> @layout.FlexItem {
  @layout.FlexItem::new(
    id,
    @layout.Dimension::points(main).unwrap(),
    @layout.Dimension::points(cross).unwrap(),
    @primitives.Size::new(0, 0).unwrap(),
  )
  .with_flex(0, 0)
  .unwrap()
}

///|
fn priority_box(
  id : UInt64,
  width : Double,
  height : Double,
  interactive : Bool,
) -> @element.Element {
  @element.Element::new(priority_item(id, width, height))
  .with_background(Some(@primitives.Color::rgba(120, 154, 188, 255).unwrap()))
  .with_pointer_events(interactive)
  .with_focusable(true)
  .with_tab_stop(true)
}

///|
fn priority_attachment(
  id : UInt64,
  priority : Int32,
  interactive : Bool,
  explicit : Bool,
) -> @element.Element {
  let row = @layout.FlexTreeStyle::new(@layout.FlowDirection::row())
  let first = @element.Element::new(priority_item(id + 3, 24, 96))
    .with_pointer_events(false)
    .with_children_style(row)
    .with_child(priority_box(id + 1, 80, 64, interactive))
  let second = @element.Element::new(priority_item(id + 4, 80, 96))
    .with_pointer_events(false)
    .with_children_style(
      row.with_insets(
        @layout.Insets::new(16, 0, 0, 0).unwrap(),
        @layout.Insets::zero(),
      ),
    )
    .with_child(priority_box(id + 2, 80, 64, interactive))
  let popup = priority_box(id, 128, 96, interactive)
    .with_children_style(row)
    .with_child(first)
    .with_child(second)
  let attachment = @element.Element::anchored_after(
    id + 5,
    2,
    popup,
    @element.TopLeft,
    @element.Window,
    @primitives.Point::new(48, 48).unwrap(),
  ).unwrap()
  if explicit {
    attachment.deferred(priority~).unwrap()
  } else {
    attachment.deferred().unwrap()
  }
}

///|
fn priority_frame(
  layers : Array[(UInt64, Int32)],
  scale : Double,
  transparent? : UInt64,
  explicit~ : Bool = true,
) -> @element.Prepainted {
  let column = @layout.FlexTreeStyle::new(@layout.FlowDirection::column())
  let mut parent = @element.Element::new(priority_item(5, 0, 240))
    .with_pointer_events(false)
    .with_children_style(column)
    .with_child(
      @element.Element::new(priority_item(2, 0, 0)).with_pointer_events(false),
    )
  for (id, priority) in layers {
    parent = parent.with_child(
      priority_attachment(id, priority, transparent != Some(id), explicit),
    )
  }
  @element.Element::root(
    1,
    @layout.FlexTreeStyle::new(@layout.FlowDirection::row()),
  )
  .with_pointer_events(false)
  .with_child(parent)
  .with_child(priority_box(4, 320, 240, true))
  .request_layout_with_device_scale(
    @primitives.Size::new(320, 240).unwrap(),
    scale,
  )
  .unwrap()
  .prepaint()
  .unwrap()
}

///|
fn priority_quad_ids(scene : @scene.Scene) -> Array[UInt64] {
  let ids : Array[UInt64] = []
  for command in scene.commands() {
    if command.kind() == @scene.Quad {
      ids.push(command.id())
    }
  }
  ids
}

///|
fn priority_assert_observation(
  layers : Array[(UInt64, Int32)],
  scale : Double,
  expected : Array[UInt64],
) -> Unit raise {
  let frame = priority_frame(layers, scale)
  let commands = frame.paint().commands()
  assert_eq(priority_quad_ids(frame.paint()), expected)
  // Bounds are read from real prepaint and actual emitted commands, never
  // supplied as a layout result. Each literal is present in the actual raw run.
  for (id, _) in layers {
    for
      (offset, x, y, width, height) in [
        (0, 48.0, 48.0, 128.0, 96.0),
        (1, 48.0, 48.0, 80.0, 64.0),
        (2, 72.0, 64.0, 80.0, 64.0),
      ] {
      let box_id = id + offset.to_uint64()
      let bounds = @primitives.Rect::new(x, y, width, height).unwrap()
      assert_true(frame.tree().node(box_id).unwrap().bounds() == bounds)
      let matching = commands.filter(command => {
        command.id() == box_id && command.kind() == @scene.Quad
      })
      assert_eq(matching.length(), 1)
      assert_true(matching[0].bounds() == Some(bounds))
    }
  }
  let viewport = @primitives.Rect::new(0, 0, 320, 240).unwrap()
  let stack : Array[UInt64] = []
  for command in commands {
    match command {
      @scene.ClipPushCommand(id~, bounds~) => {
        assert_true(bounds == viewport)
        stack.push(id)
      }
      @scene.ClipPopCommand(id~) => assert_true(stack.pop() == Some(id))
      @scene.QuadCommand(id~, ..) if id != 4 => assert_true(stack.length() > 0)
      _ => ()
    }
  }
  assert_eq(stack.length(), 0)
  assert_true(frame.paint_snapshot(scale) is Ok(_))
}

///|
test "deferred priorities observed ascending-scale1 all 14 frames" {
  // initial
  priority_assert_observation([(10, 0), (20, 1), (30, 2)], 2.0, [
    4, 10, 11, 12, 20, 21, 22, 30, 31, 32,
  ])
  // base
  priority_assert_observation([(10, 0), (20, 1), (30, 2)], 1.0, [
    4, 10, 11, 12, 20, 21, 22, 30, 31, 32,
  ])
  // base
  priority_assert_observation([(10, 0), (20, 1), (30, 2)], 1.0, [
    4, 10, 11, 12, 20, 21, 22, 30, 31, 32,
  ])
  // base.input
  priority_assert_observation([(10, 0), (20, 1), (30, 2)], 1.0, [
    4, 10, 11, 12, 20, 21, 22, 30, 31, 32,
  ])
  // base.input
  priority_assert_observation([(10, 0), (20, 1), (30, 2)], 1.0, [
    4, 10, 11, 12, 20, 21, 22, 30, 31, 32,
  ])
  // updated
  priority_assert_observation([(10, 2), (20, 1), (30, 2)], 1.0, [
    4, 20, 21, 22, 10, 11, 12, 30, 31, 32,
  ])
  // updated.input
  priority_assert_observation([(10, 2), (20, 1), (30, 2)], 1.0, [
    4, 20, 21, 22, 10, 11, 12, 30, 31, 32,
  ])
  // updated.input
  priority_assert_observation([(10, 2), (20, 1), (30, 2)], 1.0, [
    4, 20, 21, 22, 10, 11, 12, 30, 31, 32,
  ])
  // removed
  priority_assert_observation([(20, 1), (30, 2)], 1.0, [
    4, 20, 21, 22, 30, 31, 32,
  ])
  // removed.input
  priority_assert_observation([(20, 1), (30, 2)], 1.0, [
    4, 20, 21, 22, 30, 31, 32,
  ])
  // removed.input
  priority_assert_observation([(20, 1), (30, 2)], 1.0, [
    4, 20, 21, 22, 30, 31, 32,
  ])
  // restored
  priority_assert_observation([(10, 0), (20, 1), (30, 2)], 1.0, [
    4, 10, 11, 12, 20, 21, 22, 30, 31, 32,
  ])
  // restored.input
  priority_assert_observation([(10, 0), (20, 1), (30, 2)], 1.0, [
    4, 10, 11, 12, 20, 21, 22, 30, 31, 32,
  ])
  // restored.input
  priority_assert_observation([(10, 0), (20, 1), (30, 2)], 1.0, [
    4, 10, 11, 12, 20, 21, 22, 30, 31, 32,
  ])
}

///|
test "deferred priorities observed ascending-scale1.25 all 14 frames" {
  // initial
  priority_assert_observation([(10, 0), (20, 1), (30, 2)], 2.0, [
    4, 10, 11, 12, 20, 21, 22, 30, 31, 32,
  ])
  // base
  priority_assert_observation([(10, 0), (20, 1), (30, 2)], 1.25, [
    4, 10, 11, 12, 20, 21, 22, 30, 31, 32,
  ])
  // base
  priority_assert_observation([(10, 0), (20, 1), (30, 2)], 1.25, [
    4, 10, 11, 12, 20, 21, 22, 30, 31, 32,
  ])
  // base.input
  priority_assert_observation([(10, 0), (20, 1), (30, 2)], 1.25, [
    4, 10, 11, 12, 20, 21, 22, 30, 31, 32,
  ])
  // base.input
  priority_assert_observation([(10, 0), (20, 1), (30, 2)], 1.25, [
    4, 10, 11, 12, 20, 21, 22, 30, 31, 32,
  ])
  // updated
  priority_assert_observation([(10, 2), (20, 1), (30, 2)], 1.25, [
    4, 20, 21, 22, 10, 11, 12, 30, 31, 32,
  ])
  // updated.input
  priority_assert_observation([(10, 2), (20, 1), (30, 2)], 1.25, [
    4, 20, 21, 22, 10, 11, 12, 30, 31, 32,
  ])
  // updated.input
  priority_assert_observation([(10, 2), (20, 1), (30, 2)], 1.25, [
    4, 20, 21, 22, 10, 11, 12, 30, 31, 32,
  ])
  // removed
  priority_assert_observation([(20, 1), (30, 2)], 1.25, [
    4, 20, 21, 22, 30, 31, 32,
  ])
  // removed.input
  priority_assert_observation([(20, 1), (30, 2)], 1.25, [
    4, 20, 21, 22, 30, 31, 32,
  ])
  // removed.input
  priority_assert_observation([(20, 1), (30, 2)], 1.25, [
    4, 20, 21, 22, 30, 31, 32,
  ])
  // restored
  priority_assert_observation([(10, 0), (20, 1), (30, 2)], 1.25, [
    4, 10, 11, 12, 20, 21, 22, 30, 31, 32,
  ])
  // restored.input
  priority_assert_observation([(10, 0), (20, 1), (30, 2)], 1.25, [
    4, 10, 11, 12, 20, 21, 22, 30, 31, 32,
  ])
  // restored.input
  priority_assert_observation([(10, 0), (20, 1), (30, 2)], 1.25, [
    4, 10, 11, 12, 20, 21, 22, 30, 31, 32,
  ])
}

///|
test "deferred priorities observed descending-scale1 all 14 frames" {
  // initial
  priority_assert_observation([(10, 2), (20, 1), (30, 0)], 2.0, [
    4, 30, 31, 32, 20, 21, 22, 10, 11, 12,
  ])
  // base
  priority_assert_observation([(10, 2), (20, 1), (30, 0)], 1.0, [
    4, 30, 31, 32, 20, 21, 22, 10, 11, 12,
  ])
  // base
  priority_assert_observation([(10, 2), (20, 1), (30, 0)], 1.0, [
    4, 30, 31, 32, 20, 21, 22, 10, 11, 12,
  ])
  // base.input
  priority_assert_observation([(10, 2), (20, 1), (30, 0)], 1.0, [
    4, 30, 31, 32, 20, 21, 22, 10, 11, 12,
  ])
  // base.input
  priority_assert_observation([(10, 2), (20, 1), (30, 0)], 1.0, [
    4, 30, 31, 32, 20, 21, 22, 10, 11, 12,
  ])
  // updated
  priority_assert_observation([(10, 0), (20, 1), (30, 0)], 1.0, [
    4, 10, 11, 12, 30, 31, 32, 20, 21, 22,
  ])
  // updated.input
  priority_assert_observation([(10, 0), (20, 1), (30, 0)], 1.0, [
    4, 10, 11, 12, 30, 31, 32, 20, 21, 22,
  ])
  // updated.input
  priority_assert_observation([(10, 0), (20, 1), (30, 0)], 1.0, [
    4, 10, 11, 12, 30, 31, 32, 20, 21, 22,
  ])
  // removed
  priority_assert_observation([(20, 1), (30, 0)], 1.0, [
    4, 30, 31, 32, 20, 21, 22,
  ])
  // removed.input
  priority_assert_observation([(20, 1), (30, 0)], 1.0, [
    4, 30, 31, 32, 20, 21, 22,
  ])
  // removed.input
  priority_assert_observation([(20, 1), (30, 0)], 1.0, [
    4, 30, 31, 32, 20, 21, 22,
  ])
  // restored
  priority_assert_observation([(10, 2), (20, 1), (30, 0)], 1.0, [
    4, 30, 31, 32, 20, 21, 22, 10, 11, 12,
  ])
  // restored.input
  priority_assert_observation([(10, 2), (20, 1), (30, 0)], 1.0, [
    4, 30, 31, 32, 20, 21, 22, 10, 11, 12,
  ])
  // restored.input
  priority_assert_observation([(10, 2), (20, 1), (30, 0)], 1.0, [
    4, 30, 31, 32, 20, 21, 22, 10, 11, 12,
  ])
}

///|
test "deferred priorities observed descending-scale1.25 all 14 frames" {
  // initial
  priority_assert_observation([(10, 2), (20, 1), (30, 0)], 2.0, [
    4, 30, 31, 32, 20, 21, 22, 10, 11, 12,
  ])
  // base
  priority_assert_observation([(10, 2), (20, 1), (30, 0)], 1.25, [
    4, 30, 31, 32, 20, 21, 22, 10, 11, 12,
  ])
  // base
  priority_assert_observation([(10, 2), (20, 1), (30, 0)], 1.25, [
    4, 30, 31, 32, 20, 21, 22, 10, 11, 12,
  ])
  // base.input
  priority_assert_observation([(10, 2), (20, 1), (30, 0)], 1.25, [
    4, 30, 31, 32, 20, 21, 22, 10, 11, 12,
  ])
  // base.input
  priority_assert_observation([(10, 2), (20, 1), (30, 0)], 1.25, [
    4, 30, 31, 32, 20, 21, 22, 10, 11, 12,
  ])
  // updated
  priority_assert_observation([(10, 0), (20, 1), (30, 0)], 1.25, [
    4, 10, 11, 12, 30, 31, 32, 20, 21, 22,
  ])
  // updated.input
  priority_assert_observation([(10, 0), (20, 1), (30, 0)], 1.25, [
    4, 10, 11, 12, 30, 31, 32, 20, 21, 22,
  ])
  // updated.input
  priority_assert_observation([(10, 0), (20, 1), (30, 0)], 1.25, [
    4, 10, 11, 12, 30, 31, 32, 20, 21, 22,
  ])
  // removed
  priority_assert_observation([(20, 1), (30, 0)], 1.25, [
    4, 30, 31, 32, 20, 21, 22,
  ])
  // removed.input
  priority_assert_observation([(20, 1), (30, 0)], 1.25, [
    4, 30, 31, 32, 20, 21, 22,
  ])
  // removed.input
  priority_assert_observation([(20, 1), (30, 0)], 1.25, [
    4, 30, 31, 32, 20, 21, 22,
  ])
  // restored
  priority_assert_observation([(10, 2), (20, 1), (30, 0)], 1.25, [
    4, 30, 31, 32, 20, 21, 22, 10, 11, 12,
  ])
  // restored.input
  priority_assert_observation([(10, 2), (20, 1), (30, 0)], 1.25, [
    4, 30, 31, 32, 20, 21, 22, 10, 11, 12,
  ])
  // restored.input
  priority_assert_observation([(10, 2), (20, 1), (30, 0)], 1.25, [
    4, 30, 31, 32, 20, 21, 22, 10, 11, 12,
  ])
}

///|
test "deferred priorities observed equal-one-scale1 all 14 frames" {
  // initial
  priority_assert_observation([(10, 1), (20, 1), (30, 1)], 2.0, [
    4, 10, 11, 12, 20, 21, 22, 30, 31, 32,
  ])
  // base
  priority_assert_observation([(10, 1), (20, 1), (30, 1)], 1.0, [
    4, 10, 11, 12, 20, 21, 22, 30, 31, 32,
  ])
  // base
  priority_assert_observation([(10, 1), (20, 1), (30, 1)], 1.0, [
    4, 10, 11, 12, 20, 21, 22, 30, 31, 32,
  ])
  // base.input
  priority_assert_observation([(10, 1), (20, 1), (30, 1)], 1.0, [
    4, 10, 11, 12, 20, 21, 22, 30, 31, 32,
  ])
  // base.input
  priority_assert_observation([(10, 1), (20, 1), (30, 1)], 1.0, [
    4, 10, 11, 12, 20, 21, 22, 30, 31, 32,
  ])
  // updated
  priority_assert_observation([(10, 2), (20, 1), (30, 1)], 1.0, [
    4, 20, 21, 22, 30, 31, 32, 10, 11, 12,
  ])
  // updated.input
  priority_assert_observation([(10, 2), (20, 1), (30, 1)], 1.0, [
    4, 20, 21, 22, 30, 31, 32, 10, 11, 12,
  ])
  // updated.input
  priority_assert_observation([(10, 2), (20, 1), (30, 1)], 1.0, [
    4, 20, 21, 22, 30, 31, 32, 10, 11, 12,
  ])
  // removed
  priority_assert_observation([(20, 1), (30, 1)], 1.0, [
    4, 20, 21, 22, 30, 31, 32,
  ])
  // removed.input
  priority_assert_observation([(20, 1), (30, 1)], 1.0, [
    4, 20, 21, 22, 30, 31, 32,
  ])
  // removed.input
  priority_assert_observation([(20, 1), (30, 1)], 1.0, [
    4, 20, 21, 22, 30, 31, 32,
  ])
  // restored
  priority_assert_observation([(10, 1), (20, 1), (30, 1)], 1.0, [
    4, 10, 11, 12, 20, 21, 22, 30, 31, 32,
  ])
  // restored.input
  priority_assert_observation([(10, 1), (20, 1), (30, 1)], 1.0, [
    4, 10, 11, 12, 20, 21, 22, 30, 31, 32,
  ])
  // restored.input
  priority_assert_observation([(10, 1), (20, 1), (30, 1)], 1.0, [
    4, 10, 11, 12, 20, 21, 22, 30, 31, 32,
  ])
}

///|
test "deferred priorities observed equal-one-scale1.25 all 14 frames" {
  // initial
  priority_assert_observation([(10, 1), (20, 1), (30, 1)], 2.0, [
    4, 10, 11, 12, 20, 21, 22, 30, 31, 32,
  ])
  // base
  priority_assert_observation([(10, 1), (20, 1), (30, 1)], 1.25, [
    4, 10, 11, 12, 20, 21, 22, 30, 31, 32,
  ])
  // base
  priority_assert_observation([(10, 1), (20, 1), (30, 1)], 1.25, [
    4, 10, 11, 12, 20, 21, 22, 30, 31, 32,
  ])
  // base.input
  priority_assert_observation([(10, 1), (20, 1), (30, 1)], 1.25, [
    4, 10, 11, 12, 20, 21, 22, 30, 31, 32,
  ])
  // base.input
  priority_assert_observation([(10, 1), (20, 1), (30, 1)], 1.25, [
    4, 10, 11, 12, 20, 21, 22, 30, 31, 32,
  ])
  // updated
  priority_assert_observation([(10, 2), (20, 1), (30, 1)], 1.25, [
    4, 20, 21, 22, 30, 31, 32, 10, 11, 12,
  ])
  // updated.input
  priority_assert_observation([(10, 2), (20, 1), (30, 1)], 1.25, [
    4, 20, 21, 22, 30, 31, 32, 10, 11, 12,
  ])
  // updated.input
  priority_assert_observation([(10, 2), (20, 1), (30, 1)], 1.25, [
    4, 20, 21, 22, 30, 31, 32, 10, 11, 12,
  ])
  // removed
  priority_assert_observation([(20, 1), (30, 1)], 1.25, [
    4, 20, 21, 22, 30, 31, 32,
  ])
  // removed.input
  priority_assert_observation([(20, 1), (30, 1)], 1.25, [
    4, 20, 21, 22, 30, 31, 32,
  ])
  // removed.input
  priority_assert_observation([(20, 1), (30, 1)], 1.25, [
    4, 20, 21, 22, 30, 31, 32,
  ])
  // restored
  priority_assert_observation([(10, 1), (20, 1), (30, 1)], 1.25, [
    4, 10, 11, 12, 20, 21, 22, 30, 31, 32,
  ])
  // restored.input
  priority_assert_observation([(10, 1), (20, 1), (30, 1)], 1.25, [
    4, 10, 11, 12, 20, 21, 22, 30, 31, 32,
  ])
  // restored.input
  priority_assert_observation([(10, 1), (20, 1), (30, 1)], 1.25, [
    4, 10, 11, 12, 20, 21, 22, 30, 31, 32,
  ])
}

///|
test "deferred priorities observed equal-one-reverse-scale1 all 14 frames" {
  // initial
  priority_assert_observation([(30, 1), (20, 1), (10, 1)], 2.0, [
    4, 30, 31, 32, 20, 21, 22, 10, 11, 12,
  ])
  // base
  priority_assert_observation([(30, 1), (20, 1), (10, 1)], 1.0, [
    4, 30, 31, 32, 20, 21, 22, 10, 11, 12,
  ])
  // base
  priority_assert_observation([(30, 1), (20, 1), (10, 1)], 1.0, [
    4, 30, 31, 32, 20, 21, 22, 10, 11, 12,
  ])
  // base.input
  priority_assert_observation([(30, 1), (20, 1), (10, 1)], 1.0, [
    4, 30, 31, 32, 20, 21, 22, 10, 11, 12,
  ])
  // base.input
  priority_assert_observation([(30, 1), (20, 1), (10, 1)], 1.0, [
    4, 30, 31, 32, 20, 21, 22, 10, 11, 12,
  ])
  // updated
  priority_assert_observation([(30, 2), (20, 1), (10, 1)], 1.0, [
    4, 20, 21, 22, 10, 11, 12, 30, 31, 32,
  ])
  // updated.input
  priority_assert_observation([(30, 2), (20, 1), (10, 1)], 1.0, [
    4, 20, 21, 22, 10, 11, 12, 30, 31, 32,
  ])
  // updated.input
  priority_assert_observation([(30, 2), (20, 1), (10, 1)], 1.0, [
    4, 20, 21, 22, 10, 11, 12, 30, 31, 32,
  ])
  // removed
  priority_assert_observation([(20, 1), (10, 1)], 1.0, [
    4, 20, 21, 22, 10, 11, 12,
  ])
  // removed.input
  priority_assert_observation([(20, 1), (10, 1)], 1.0, [
    4, 20, 21, 22, 10, 11, 12,
  ])
  // removed.input
  priority_assert_observation([(20, 1), (10, 1)], 1.0, [
    4, 20, 21, 22, 10, 11, 12,
  ])
  // restored
  priority_assert_observation([(30, 1), (20, 1), (10, 1)], 1.0, [
    4, 30, 31, 32, 20, 21, 22, 10, 11, 12,
  ])
  // restored.input
  priority_assert_observation([(30, 1), (20, 1), (10, 1)], 1.0, [
    4, 30, 31, 32, 20, 21, 22, 10, 11, 12,
  ])
  // restored.input
  priority_assert_observation([(30, 1), (20, 1), (10, 1)], 1.0, [
    4, 30, 31, 32, 20, 21, 22, 10, 11, 12,
  ])
}

///|
test "deferred priorities observed equal-one-reverse-scale1.25 all 14 frames" {
  // initial
  priority_assert_observation([(30, 1), (20, 1), (10, 1)], 2.0, [
    4, 30, 31, 32, 20, 21, 22, 10, 11, 12,
  ])
  // base
  priority_assert_observation([(30, 1), (20, 1), (10, 1)], 1.25, [
    4, 30, 31, 32, 20, 21, 22, 10, 11, 12,
  ])
  // base
  priority_assert_observation([(30, 1), (20, 1), (10, 1)], 1.25, [
    4, 30, 31, 32, 20, 21, 22, 10, 11, 12,
  ])
  // base.input
  priority_assert_observation([(30, 1), (20, 1), (10, 1)], 1.25, [
    4, 30, 31, 32, 20, 21, 22, 10, 11, 12,
  ])
  // base.input
  priority_assert_observation([(30, 1), (20, 1), (10, 1)], 1.25, [
    4, 30, 31, 32, 20, 21, 22, 10, 11, 12,
  ])
  // updated
  priority_assert_observation([(30, 2), (20, 1), (10, 1)], 1.25, [
    4, 20, 21, 22, 10, 11, 12, 30, 31, 32,
  ])
  // updated.input
  priority_assert_observation([(30, 2), (20, 1), (10, 1)], 1.25, [
    4, 20, 21, 22, 10, 11, 12, 30, 31, 32,
  ])
  // updated.input
  priority_assert_observation([(30, 2), (20, 1), (10, 1)], 1.25, [
    4, 20, 21, 22, 10, 11, 12, 30, 31, 32,
  ])
  // removed
  priority_assert_observation([(20, 1), (10, 1)], 1.25, [
    4, 20, 21, 22, 10, 11, 12,
  ])
  // removed.input
  priority_assert_observation([(20, 1), (10, 1)], 1.25, [
    4, 20, 21, 22, 10, 11, 12,
  ])
  // removed.input
  priority_assert_observation([(20, 1), (10, 1)], 1.25, [
    4, 20, 21, 22, 10, 11, 12,
  ])
  // restored
  priority_assert_observation([(30, 1), (20, 1), (10, 1)], 1.25, [
    4, 30, 31, 32, 20, 21, 22, 10, 11, 12,
  ])
  // restored.input
  priority_assert_observation([(30, 1), (20, 1), (10, 1)], 1.25, [
    4, 30, 31, 32, 20, 21, 22, 10, 11, 12,
  ])
  // restored.input
  priority_assert_observation([(30, 1), (20, 1), (10, 1)], 1.25, [
    4, 30, 31, 32, 20, 21, 22, 10, 11, 12,
  ])
}

///|
test "deferred priorities observed equal-zero-scale1 all 14 frames" {
  // initial
  priority_assert_observation([(10, 0), (20, 0), (30, 0)], 2.0, [
    4, 10, 11, 12, 20, 21, 22, 30, 31, 32,
  ])
  // base
  priority_assert_observation([(10, 0), (20, 0), (30, 0)], 1.0, [
    4, 10, 11, 12, 20, 21, 22, 30, 31, 32,
  ])
  // base
  priority_assert_observation([(10, 0), (20, 0), (30, 0)], 1.0, [
    4, 10, 11, 12, 20, 21, 22, 30, 31, 32,
  ])
  // base.input
  priority_assert_observation([(10, 0), (20, 0), (30, 0)], 1.0, [
    4, 10, 11, 12, 20, 21, 22, 30, 31, 32,
  ])
  // base.input
  priority_assert_observation([(10, 0), (20, 0), (30, 0)], 1.0, [
    4, 10, 11, 12, 20, 21, 22, 30, 31, 32,
  ])
  // updated
  priority_assert_observation([(10, 2), (20, 0), (30, 0)], 1.0, [
    4, 20, 21, 22, 30, 31, 32, 10, 11, 12,
  ])
  // updated.input
  priority_assert_observation([(10, 2), (20, 0), (30, 0)], 1.0, [
    4, 20, 21, 22, 30, 31, 32, 10, 11, 12,
  ])
  // updated.input
  priority_assert_observation([(10, 2), (20, 0), (30, 0)], 1.0, [
    4, 20, 21, 22, 30, 31, 32, 10, 11, 12,
  ])
  // removed
  priority_assert_observation([(20, 0), (30, 0)], 1.0, [
    4, 20, 21, 22, 30, 31, 32,
  ])
  // removed.input
  priority_assert_observation([(20, 0), (30, 0)], 1.0, [
    4, 20, 21, 22, 30, 31, 32,
  ])
  // removed.input
  priority_assert_observation([(20, 0), (30, 0)], 1.0, [
    4, 20, 21, 22, 30, 31, 32,
  ])
  // restored
  priority_assert_observation([(10, 0), (20, 0), (30, 0)], 1.0, [
    4, 10, 11, 12, 20, 21, 22, 30, 31, 32,
  ])
  // restored.input
  priority_assert_observation([(10, 0), (20, 0), (30, 0)], 1.0, [
    4, 10, 11, 12, 20, 21, 22, 30, 31, 32,
  ])
  // restored.input
  priority_assert_observation([(10, 0), (20, 0), (30, 0)], 1.0, [
    4, 10, 11, 12, 20, 21, 22, 30, 31, 32,
  ])
}

///|
test "deferred priorities observed equal-zero-scale1.25 all 14 frames" {
  // initial
  priority_assert_observation([(10, 0), (20, 0), (30, 0)], 2.0, [
    4, 10, 11, 12, 20, 21, 22, 30, 31, 32,
  ])
  // base
  priority_assert_observation([(10, 0), (20, 0), (30, 0)], 1.25, [
    4, 10, 11, 12, 20, 21, 22, 30, 31, 32,
  ])
  // base
  priority_assert_observation([(10, 0), (20, 0), (30, 0)], 1.25, [
    4, 10, 11, 12, 20, 21, 22, 30, 31, 32,
  ])
  // base.input
  priority_assert_observation([(10, 0), (20, 0), (30, 0)], 1.25, [
    4, 10, 11, 12, 20, 21, 22, 30, 31, 32,
  ])
  // base.input
  priority_assert_observation([(10, 0), (20, 0), (30, 0)], 1.25, [
    4, 10, 11, 12, 20, 21, 22, 30, 31, 32,
  ])
  // updated
  priority_assert_observation([(10, 2), (20, 0), (30, 0)], 1.25, [
    4, 20, 21, 22, 30, 31, 32, 10, 11, 12,
  ])
  // updated.input
  priority_assert_observation([(10, 2), (20, 0), (30, 0)], 1.25, [
    4, 20, 21, 22, 30, 31, 32, 10, 11, 12,
  ])
  // updated.input
  priority_assert_observation([(10, 2), (20, 0), (30, 0)], 1.25, [
    4, 20, 21, 22, 30, 31, 32, 10, 11, 12,
  ])
  // removed
  priority_assert_observation([(20, 0), (30, 0)], 1.25, [
    4, 20, 21, 22, 30, 31, 32,
  ])
  // removed.input
  priority_assert_observation([(20, 0), (30, 0)], 1.25, [
    4, 20, 21, 22, 30, 31, 32,
  ])
  // removed.input
  priority_assert_observation([(20, 0), (30, 0)], 1.25, [
    4, 20, 21, 22, 30, 31, 32,
  ])
  // restored
  priority_assert_observation([(10, 0), (20, 0), (30, 0)], 1.25, [
    4, 10, 11, 12, 20, 21, 22, 30, 31, 32,
  ])
  // restored.input
  priority_assert_observation([(10, 0), (20, 0), (30, 0)], 1.25, [
    4, 10, 11, 12, 20, 21, 22, 30, 31, 32,
  ])
  // restored.input
  priority_assert_observation([(10, 0), (20, 0), (30, 0)], 1.25, [
    4, 10, 11, 12, 20, 21, 22, 30, 31, 32,
  ])
}

///|
test "deferred priorities observed transparent-top-scale1 all 14 frames" {
  // initial
  priority_assert_observation([(10, 0), (20, 1), (30, 2)], 2.0, [
    4, 10, 11, 12, 20, 21, 22, 30, 31, 32,
  ])
  // base
  priority_assert_observation([(10, 0), (20, 1), (30, 2)], 1.0, [
    4, 10, 11, 12, 20, 21, 22, 30, 31, 32,
  ])
  // base
  priority_assert_observation([(10, 0), (20, 1), (30, 2)], 1.0, [
    4, 10, 11, 12, 20, 21, 22, 30, 31, 32,
  ])
  // base.input
  priority_assert_observation([(10, 0), (20, 1), (30, 2)], 1.0, [
    4, 10, 11, 12, 20, 21, 22, 30, 31, 32,
  ])
  // base.input
  priority_assert_observation([(10, 0), (20, 1), (30, 2)], 1.0, [
    4, 10, 11, 12, 20, 21, 22, 30, 31, 32,
  ])
  // updated
  priority_assert_observation([(10, 2), (20, 1), (30, 2)], 1.0, [
    4, 20, 21, 22, 10, 11, 12, 30, 31, 32,
  ])
  // updated.input
  priority_assert_observation([(10, 2), (20, 1), (30, 2)], 1.0, [
    4, 20, 21, 22, 10, 11, 12, 30, 31, 32,
  ])
  // updated.input
  priority_assert_observation([(10, 2), (20, 1), (30, 2)], 1.0, [
    4, 20, 21, 22, 10, 11, 12, 30, 31, 32,
  ])
  // removed
  priority_assert_observation([(20, 1), (30, 2)], 1.0, [
    4, 20, 21, 22, 30, 31, 32,
  ])
  // removed.input
  priority_assert_observation([(20, 1), (30, 2)], 1.0, [
    4, 20, 21, 22, 30, 31, 32,
  ])
  // removed.input
  priority_assert_observation([(20, 1), (30, 2)], 1.0, [
    4, 20, 21, 22, 30, 31, 32,
  ])
  // restored
  priority_assert_observation([(10, 0), (20, 1), (30, 2)], 1.0, [
    4, 10, 11, 12, 20, 21, 22, 30, 31, 32,
  ])
  // restored.input
  priority_assert_observation([(10, 0), (20, 1), (30, 2)], 1.0, [
    4, 10, 11, 12, 20, 21, 22, 30, 31, 32,
  ])
  // restored.input
  priority_assert_observation([(10, 0), (20, 1), (30, 2)], 1.0, [
    4, 10, 11, 12, 20, 21, 22, 30, 31, 32,
  ])
}

///|
test "deferred priorities observed transparent-top-scale1.25 all 14 frames" {
  // initial
  priority_assert_observation([(10, 0), (20, 1), (30, 2)], 2.0, [
    4, 10, 11, 12, 20, 21, 22, 30, 31, 32,
  ])
  // base
  priority_assert_observation([(10, 0), (20, 1), (30, 2)], 1.25, [
    4, 10, 11, 12, 20, 21, 22, 30, 31, 32,
  ])
  // base
  priority_assert_observation([(10, 0), (20, 1), (30, 2)], 1.25, [
    4, 10, 11, 12, 20, 21, 22, 30, 31, 32,
  ])
  // base.input
  priority_assert_observation([(10, 0), (20, 1), (30, 2)], 1.25, [
    4, 10, 11, 12, 20, 21, 22, 30, 31, 32,
  ])
  // base.input
  priority_assert_observation([(10, 0), (20, 1), (30, 2)], 1.25, [
    4, 10, 11, 12, 20, 21, 22, 30, 31, 32,
  ])
  // updated
  priority_assert_observation([(10, 2), (20, 1), (30, 2)], 1.25, [
    4, 20, 21, 22, 10, 11, 12, 30, 31, 32,
  ])
  // updated.input
  priority_assert_observation([(10, 2), (20, 1), (30, 2)], 1.25, [
    4, 20, 21, 22, 10, 11, 12, 30, 31, 32,
  ])
  // updated.input
  priority_assert_observation([(10, 2), (20, 1), (30, 2)], 1.25, [
    4, 20, 21, 22, 10, 11, 12, 30, 31, 32,
  ])
  // removed
  priority_assert_observation([(20, 1), (30, 2)], 1.25, [
    4, 20, 21, 22, 30, 31, 32,
  ])
  // removed.input
  priority_assert_observation([(20, 1), (30, 2)], 1.25, [
    4, 20, 21, 22, 30, 31, 32,
  ])
  // removed.input
  priority_assert_observation([(20, 1), (30, 2)], 1.25, [
    4, 20, 21, 22, 30, 31, 32,
  ])
  // restored
  priority_assert_observation([(10, 0), (20, 1), (30, 2)], 1.25, [
    4, 10, 11, 12, 20, 21, 22, 30, 31, 32,
  ])
  // restored.input
  priority_assert_observation([(10, 0), (20, 1), (30, 2)], 1.25, [
    4, 10, 11, 12, 20, 21, 22, 30, 31, 32,
  ])
  // restored.input
  priority_assert_observation([(10, 0), (20, 1), (30, 2)], 1.25, [
    4, 10, 11, 12, 20, 21, 22, 30, 31, 32,
  ])
}

///|
test "deferred priorities observed occluding-top-scale1 all 14 frames" {
  // initial
  priority_assert_observation([(10, 0), (20, 1), (30, 2)], 2.0, [
    4, 10, 11, 12, 20, 21, 22, 30, 31, 32,
  ])
  // base
  priority_assert_observation([(10, 0), (20, 1), (30, 2)], 1.0, [
    4, 10, 11, 12, 20, 21, 22, 30, 31, 32,
  ])
  // base
  priority_assert_observation([(10, 0), (20, 1), (30, 2)], 1.0, [
    4, 10, 11, 12, 20, 21, 22, 30, 31, 32,
  ])
  // base.input
  priority_assert_observation([(10, 0), (20, 1), (30, 2)], 1.0, [
    4, 10, 11, 12, 20, 21, 22, 30, 31, 32,
  ])
  // base.input
  priority_assert_observation([(10, 0), (20, 1), (30, 2)], 1.0, [
    4, 10, 11, 12, 20, 21, 22, 30, 31, 32,
  ])
  // updated
  priority_assert_observation([(10, 2), (20, 1), (30, 2)], 1.0, [
    4, 20, 21, 22, 10, 11, 12, 30, 31, 32,
  ])
  // updated.input
  priority_assert_observation([(10, 2), (20, 1), (30, 2)], 1.0, [
    4, 20, 21, 22, 10, 11, 12, 30, 31, 32,
  ])
  // updated.input
  priority_assert_observation([(10, 2), (20, 1), (30, 2)], 1.0, [
    4, 20, 21, 22, 10, 11, 12, 30, 31, 32,
  ])
  // removed
  priority_assert_observation([(20, 1), (30, 2)], 1.0, [
    4, 20, 21, 22, 30, 31, 32,
  ])
  // removed.input
  priority_assert_observation([(20, 1), (30, 2)], 1.0, [
    4, 20, 21, 22, 30, 31, 32,
  ])
  // removed.input
  priority_assert_observation([(20, 1), (30, 2)], 1.0, [
    4, 20, 21, 22, 30, 31, 32,
  ])
  // restored
  priority_assert_observation([(10, 0), (20, 1), (30, 2)], 1.0, [
    4, 10, 11, 12, 20, 21, 22, 30, 31, 32,
  ])
  // restored.input
  priority_assert_observation([(10, 0), (20, 1), (30, 2)], 1.0, [
    4, 10, 11, 12, 20, 21, 22, 30, 31, 32,
  ])
  // restored.input
  priority_assert_observation([(10, 0), (20, 1), (30, 2)], 1.0, [
    4, 10, 11, 12, 20, 21, 22, 30, 31, 32,
  ])
}

///|
test "deferred priorities observed occluding-top-scale1.25 all 14 frames" {
  // initial
  priority_assert_observation([(10, 0), (20, 1), (30, 2)], 2.0, [
    4, 10, 11, 12, 20, 21, 22, 30, 31, 32,
  ])
  // base
  priority_assert_observation([(10, 0), (20, 1), (30, 2)], 1.25, [
    4, 10, 11, 12, 20, 21, 22, 30, 31, 32,
  ])
  // base
  priority_assert_observation([(10, 0), (20, 1), (30, 2)], 1.25, [
    4, 10, 11, 12, 20, 21, 22, 30, 31, 32,
  ])
  // base.input
  priority_assert_observation([(10, 0), (20, 1), (30, 2)], 1.25, [
    4, 10, 11, 12, 20, 21, 22, 30, 31, 32,
  ])
  // base.input
  priority_assert_observation([(10, 0), (20, 1), (30, 2)], 1.25, [
    4, 10, 11, 12, 20, 21, 22, 30, 31, 32,
  ])
  // updated
  priority_assert_observation([(10, 2), (20, 1), (30, 2)], 1.25, [
    4, 20, 21, 22, 10, 11, 12, 30, 31, 32,
  ])
  // updated.input
  priority_assert_observation([(10, 2), (20, 1), (30, 2)], 1.25, [
    4, 20, 21, 22, 10, 11, 12, 30, 31, 32,
  ])
  // updated.input
  priority_assert_observation([(10, 2), (20, 1), (30, 2)], 1.25, [
    4, 20, 21, 22, 10, 11, 12, 30, 31, 32,
  ])
  // removed
  priority_assert_observation([(20, 1), (30, 2)], 1.25, [
    4, 20, 21, 22, 30, 31, 32,
  ])
  // removed.input
  priority_assert_observation([(20, 1), (30, 2)], 1.25, [
    4, 20, 21, 22, 30, 31, 32,
  ])
  // removed.input
  priority_assert_observation([(20, 1), (30, 2)], 1.25, [
    4, 20, 21, 22, 30, 31, 32,
  ])
  // restored
  priority_assert_observation([(10, 0), (20, 1), (30, 2)], 1.25, [
    4, 10, 11, 12, 20, 21, 22, 30, 31, 32,
  ])
  // restored.input
  priority_assert_observation([(10, 0), (20, 1), (30, 2)], 1.25, [
    4, 10, 11, 12, 20, 21, 22, 30, 31, 32,
  ])
  // restored.input
  priority_assert_observation([(10, 0), (20, 1), (30, 2)], 1.25, [
    4, 10, 11, 12, 20, 21, 22, 30, 31, 32,
  ])
}

///|
test "deferred priorities observed stopping-top-scale1 all 14 frames" {
  // initial
  priority_assert_observation([(10, 0), (20, 1), (30, 2)], 2.0, [
    4, 10, 11, 12, 20, 21, 22, 30, 31, 32,
  ])
  // base
  priority_assert_observation([(10, 0), (20, 1), (30, 2)], 1.0, [
    4, 10, 11, 12, 20, 21, 22, 30, 31, 32,
  ])
  // base
  priority_assert_observation([(10, 0), (20, 1), (30, 2)], 1.0, [
    4, 10, 11, 12, 20, 21, 22, 30, 31, 32,
  ])
  // base.input
  priority_assert_observation([(10, 0), (20, 1), (30, 2)], 1.0, [
    4, 10, 11, 12, 20, 21, 22, 30, 31, 32,
  ])
  // base.input
  priority_assert_observation([(10, 0), (20, 1), (30, 2)], 1.0, [
    4, 10, 11, 12, 20, 21, 22, 30, 31, 32,
  ])
  // updated
  priority_assert_observation([(10, 2), (20, 1), (30, 2)], 1.0, [
    4, 20, 21, 22, 10, 11, 12, 30, 31, 32,
  ])
  // updated.input
  priority_assert_observation([(10, 2), (20, 1), (30, 2)], 1.0, [
    4, 20, 21, 22, 10, 11, 12, 30, 31, 32,
  ])
  // updated.input
  priority_assert_observation([(10, 2), (20, 1), (30, 2)], 1.0, [
    4, 20, 21, 22, 10, 11, 12, 30, 31, 32,
  ])
  // removed
  priority_assert_observation([(20, 1), (30, 2)], 1.0, [
    4, 20, 21, 22, 30, 31, 32,
  ])
  // removed.input
  priority_assert_observation([(20, 1), (30, 2)], 1.0, [
    4, 20, 21, 22, 30, 31, 32,
  ])
  // removed.input
  priority_assert_observation([(20, 1), (30, 2)], 1.0, [
    4, 20, 21, 22, 30, 31, 32,
  ])
  // restored
  priority_assert_observation([(10, 0), (20, 1), (30, 2)], 1.0, [
    4, 10, 11, 12, 20, 21, 22, 30, 31, 32,
  ])
  // restored.input
  priority_assert_observation([(10, 0), (20, 1), (30, 2)], 1.0, [
    4, 10, 11, 12, 20, 21, 22, 30, 31, 32,
  ])
  // restored.input
  priority_assert_observation([(10, 0), (20, 1), (30, 2)], 1.0, [
    4, 10, 11, 12, 20, 21, 22, 30, 31, 32,
  ])
}

///|
test "deferred priorities observed stopping-top-scale1.25 all 14 frames" {
  // initial
  priority_assert_observation([(10, 0), (20, 1), (30, 2)], 2.0, [
    4, 10, 11, 12, 20, 21, 22, 30, 31, 32,
  ])
  // base
  priority_assert_observation([(10, 0), (20, 1), (30, 2)], 1.25, [
    4, 10, 11, 12, 20, 21, 22, 30, 31, 32,
  ])
  // base
  priority_assert_observation([(10, 0), (20, 1), (30, 2)], 1.25, [
    4, 10, 11, 12, 20, 21, 22, 30, 31, 32,
  ])
  // base.input
  priority_assert_observation([(10, 0), (20, 1), (30, 2)], 1.25, [
    4, 10, 11, 12, 20, 21, 22, 30, 31, 32,
  ])
  // base.input
  priority_assert_observation([(10, 0), (20, 1), (30, 2)], 1.25, [
    4, 10, 11, 12, 20, 21, 22, 30, 31, 32,
  ])
  // updated
  priority_assert_observation([(10, 2), (20, 1), (30, 2)], 1.25, [
    4, 20, 21, 22, 10, 11, 12, 30, 31, 32,
  ])
  // updated.input
  priority_assert_observation([(10, 2), (20, 1), (30, 2)], 1.25, [
    4, 20, 21, 22, 10, 11, 12, 30, 31, 32,
  ])
  // updated.input
  priority_assert_observation([(10, 2), (20, 1), (30, 2)], 1.25, [
    4, 20, 21, 22, 10, 11, 12, 30, 31, 32,
  ])
  // removed
  priority_assert_observation([(20, 1), (30, 2)], 1.25, [
    4, 20, 21, 22, 30, 31, 32,
  ])
  // removed.input
  priority_assert_observation([(20, 1), (30, 2)], 1.25, [
    4, 20, 21, 22, 30, 31, 32,
  ])
  // removed.input
  priority_assert_observation([(20, 1), (30, 2)], 1.25, [
    4, 20, 21, 22, 30, 31, 32,
  ])
  // restored
  priority_assert_observation([(10, 0), (20, 1), (30, 2)], 1.25, [
    4, 10, 11, 12, 20, 21, 22, 30, 31, 32,
  ])
  // restored.input
  priority_assert_observation([(10, 0), (20, 1), (30, 2)], 1.25, [
    4, 10, 11, 12, 20, 21, 22, 30, 31, 32,
  ])
  // restored.input
  priority_assert_observation([(10, 0), (20, 1), (30, 2)], 1.25, [
    4, 10, 11, 12, 20, 21, 22, 30, 31, 32,
  ])
}

///|
test "deferred priority bounds preserve negative errors and maximum ordering" {
  let popup = priority_box(10, 128, 96, true)
  let attachment = @element.Element::anchored_after(
    15,
    2,
    popup,
    @element.TopLeft,
    @element.Window,
    @primitives.Point::new(48, 48).unwrap(),
  ).unwrap()
  assert_true(
    attachment.deferred(priority=-1) is Err(@element.InvalidDeferredPriority),
  )
  assert_true(
    attachment.deferred(priority=-2147483648)
    is Err(@element.InvalidDeferredPriority),
  )
  assert_true(attachment.deferred(priority=2147483647) is Ok(_))
  priority_assert_observation(
    [(10, 2147483647), (20, 0), (30, 2147483646)],
    1,
    [4, 20, 21, 22, 30, 31, 32, 10, 11, 12],
  )
  priority_assert_observation(
    [(30, 2147483647), (10, 2147483647), (20, 0)],
    1.25,
    [4, 20, 21, 22, 30, 31, 32, 10, 11, 12],
  )
}

///|
test "deferred priority zero is exactly compatible across genuine layout and scenes" {
  for scale in [1.0, 1.25, 2.0] {
    let implicit = priority_frame(
      [(30, 0), (10, 0), (20, 0)],
      scale,
      explicit=false,
    )
    let explicit = priority_frame([(30, 0), (10, 0), (20, 0)], scale)
    assert_true(implicit.paint().commands() == explicit.paint().commands())
    let before = implicit.tree().nodes()
    let after = explicit.tree().nodes()
    assert_eq(before.length(), after.length())
    for i = 0; i < before.length(); i = i + 1 {
      assert_true(before[i].id() == after[i].id())
      assert_true(before[i].parent() == after[i].parent())
      assert_true(before[i].bounds() == after[i].bounds())
    }
    assert_eq(priority_quad_ids(implicit.paint()), [
      4, 30, 31, 32, 10, 11, 12, 20, 21, 22,
    ])
  }
}

///|
test "deferred priority update rejects bounds-only refresh even when paint order ties" {
  let first = priority_frame([(10, 0), (20, 1), (30, 2)], 1)
  let retained = first.tree().with_focus(21).unwrap()
  let owner = retained.focus_owner()
  let changed = priority_frame([(10, 3), (20, 1), (30, 2)], 1)
  assert_true(
    retained.with_layout_bounds(changed) is Err(@element.LayoutBoundsMismatch),
  )
  let same_order = priority_frame([(10, 0), (20, 1), (30, 3)], 1)
  assert_true(
    retained.with_layout_bounds(same_order)
    is Err(@element.LayoutBoundsMismatch),
  )
  assert_true(retained.focus_owner() == owner)
  assert_eq(priority_quad_ids(retained.to_scene()), [
    4, 10, 11, 12, 20, 21, 22, 30, 31, 32,
  ])
  assert_eq(priority_quad_ids(changed.paint()), [
    4, 20, 21, 22, 30, 31, 32, 10, 11, 12,
  ])
  assert_true(
    retained.with_layout_bounds(first).unwrap().focus_owner() == owner,
  )
}

///|
test "deferred priority structural focus dispatch and drag identities remain stable" {
  let frame = priority_frame([(10, 9), (20, 1), (30, 5)], 1)
  let tree = frame.tree()
  assert_eq(tree.nodes().map(node => node.id()), [
    1, 5, 2, 15, 10, 13, 11, 14, 12, 25, 20, 23, 21, 24, 22, 35, 30, 33, 31, 34,
    32, 4,
  ])
  let point = @primitives.Point::new(88, 80).unwrap()
  assert_true(tree.hit_test(point) == Some(12))
  assert_eq(tree.dispatch_pointer(point).capture(), [1, 5, 15, 10, 14, 12])
  assert_eq(tree.dispatch_pointer(point).bubble(), [12, 14, 10, 15, 5, 1])
  assert_true(
    tree.with_focus(12).unwrap().focus_next().unwrap().focused() == Some(20),
  )
  assert_true(
    tree.with_focus(20).unwrap().focus_prev().unwrap().focused() == Some(12),
  )
  let drag = @element.DragGesture::new(0).unwrap().begin(12, point)
  let refreshed = tree
    .with_focus(12)
    .unwrap()
    .with_layout_bounds(frame)
    .unwrap()
  assert_true(drag.source() == Some(12))
  assert_true(refreshed.node(drag.source().unwrap()) is Some(_))
  let transparent = priority_frame(
    [(10, 9), (20, 1), (30, 5)],
    1,
    transparent=10,
  )
  assert_true(transparent.tree().hit_test(point) == Some(32))
  // Current core selects one topmost target and its ancestor route. It does
  // not promise the Rust baseline's multi-listener or occlusion semantics.
}

///|
test "deferred priority immutable removal restoration and node copies retain ordering" {
  let frame = priority_frame([(10, 9), (20, 1), (30, 5)], 1.25)
  let tree = frame.tree().with_focus(21).unwrap()
  let owner = tree.focus_owner()
  let removed = tree.without_subtree(15).unwrap()
  assert_true(removed.focus_owner() == owner)
  assert_eq(priority_quad_ids(removed.to_scene()), [4, 20, 21, 22, 30, 31, 32])
  assert_eq(priority_quad_ids(tree.to_scene()), [
    4, 20, 21, 22, 30, 31, 32, 10, 11, 12,
  ])
  let copied = @element.ElementTree::new(
    tree
    .nodes()
    .map(node => {
      node
      .with_background(node.background())
      .with_focusable(node.is_focusable())
      .with_pointer_events(node.accepts_pointer_events())
      .with_tab_index(node.tab_index)
      .with_tab_group_index(node.tab_group_index)
      .with_tab_stop(node.tab_stop)
    }),
  ).unwrap()
  assert_true(copied.to_scene().commands() == tree.to_scene().commands())
  let restored = priority_frame([(10, 9), (20, 1), (30, 5)], 1.25)
  assert_true(restored.paint().commands() == frame.paint().commands())
  assert_true(tree.without_subtree(2) is Err(@element.InvalidAnchoredShape))
  assert_eq(priority_quad_ids(tree.without_subtree(5).unwrap().to_scene()), [4])
}

///|
test "deferred priority composition rejection remains explicit" {
  let plain = priority_box(10, 128, 96, true)
  assert_true(
    plain.deferred(priority=1) is Err(@element.UnsupportedAnchoredComposition),
  )
  let once = priority_attachment(10, 1, true, true)
  assert_true(
    once.deferred(priority=2) is Err(@element.UnsupportedAnchoredComposition),
  )
  assert_true(
    @element.Element::anchored_after(
      100,
      2,
      once,
      @element.TopLeft,
      @element.Window,
      @primitives.Point::new(0, 0).unwrap(),
    )
    is Err(@element.UnsupportedAnchoredComposition),
  )
  let nested = plain
    .with_children_style(
      @layout.FlexTreeStyle::new(@layout.FlowDirection::row()),
    )
    .with_child(priority_attachment(30, 1, false, true))
  assert_true(
    @element.Element::anchored_after(
      100,
      2,
      nested,
      @element.TopLeft,
      @element.Window,
      @primitives.Point::new(0, 0).unwrap(),
    )
    is Err(@element.UnsupportedAnchoredComposition),
  )
}

///|
test "deferred priority alpha zero paint remains emitted and does not change hits" {
  let tree = priority_frame([(10, 9), (20, 1), (30, 5)], 1).tree()
  let transparent = @primitives.Color::rgba(120, 154, 188, 0).unwrap()
  let copied = @element.ElementTree::new(
    tree
    .nodes()
    .map(node => {
      if node.id() == 10 || node.id() == 11 || node.id() == 12 {
        node.with_background(Some(transparent))
      } else {
        node
      }
    }),
  ).unwrap()
  assert_eq(priority_quad_ids(copied.to_scene()), [
    4, 20, 21, 22, 30, 31, 32, 10, 11, 12,
  ])
  assert_true(
    copied.hit_test(@primitives.Point::new(88, 80).unwrap()) == Some(12),
  )
  for command in copied.to_scene().commands() {
    if command.id() == 10 || command.id() == 11 || command.id() == 12 {
      assert_true(command.color() == Some(transparent))
    }
  }
}

///|
test "deferred priority element fluent copies preserve scheduling and geometry" {
  let attachment = priority_attachment(10, 2147483647, true, true)
    .with_background(None)
    .with_focusable(false)
    .with_pointer_events(false)
    .with_tab_index(0)
    .with_tab_group_index(None)
    .with_tab_stop(false)
  let frame = @element.Element::root(
      1,
      @layout.FlexTreeStyle::new(@layout.FlowDirection::column()),
    )
    .with_child(@element.Element::new(priority_item(2, 0, 0)))
    .with_child(attachment)
    .with_child(priority_attachment(20, 1, true, true))
    .request_layout(@primitives.Size::new(320, 240).unwrap())
    .unwrap()
    .prepaint()
    .unwrap()
  assert_eq(priority_quad_ids(frame.paint()), [20, 21, 22, 10, 11, 12])
  assert_true(
    frame.tree().node(12).unwrap().bounds() ==
    @primitives.Rect::new(72, 64, 80, 64).unwrap(),
  )
}

///|
test "deferred priority scheduling is global across distinct flat attachment owners" {
  let column = @layout.FlexTreeStyle::new(@layout.FlowDirection::column())
  let first = @element.Element::new(priority_item(5, 0, 240))
    .with_children_style(column)
    .with_child(@element.Element::new(priority_item(2, 0, 0)))
    .with_child(priority_attachment(10, 9, true, true))
  let popup = priority_box(20, 128, 96, true)
  let second_attachment = @element.Element::anchored_after(
      25,
      6,
      popup,
      @element.TopLeft,
      @element.Window,
      @primitives.Point::new(48, 48).unwrap(),
    )
    .unwrap()
    .deferred(priority=1)
    .unwrap()
  let second = @element.Element::new(priority_item(7, 0, 240))
    .with_children_style(column)
    .with_child(@element.Element::new(priority_item(6, 0, 0)))
    .with_child(second_attachment)
  let frame = @element.Element::root(
      1,
      @layout.FlexTreeStyle::new(@layout.FlowDirection::row()),
    )
    .with_child(first)
    .with_child(second)
    .with_child(priority_box(4, 320, 240, true))
    .request_layout_with_device_scale(
      @primitives.Size::new(320, 240).unwrap(),
      1.25,
    )
    .unwrap()
    .prepaint()
    .unwrap()
  assert_eq(priority_quad_ids(frame.paint()), [4, 20, 10, 11, 12])
  assert_true(frame.paint_snapshot(1.25) is Ok(_))
}
