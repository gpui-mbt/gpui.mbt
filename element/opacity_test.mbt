///|
fn opacity_command(scene : @scene.Scene, id : UInt64) -> @scene.PaintCommand {
  for command in scene.commands() {
    if command.id() == id &&
      command.kind() != @scene.ClipPush &&
      command.kind() != @scene.ClipPop {
      return command
    }
  }
  abort("opacity paint command missing")
}

///|
test "element opacity is finite bounded and immutable" {
  let root = @element.Element::root(
    1,
    @layout.FlexTreeStyle::new(@layout.FlowDirection::row()),
  )
  let rect = @primitives.Rect::new(0, 0, 10, 10).unwrap()
  let node = @element.ElementNode::new(1, None, rect)
  for invalid in [-0.1, 1.1, 0.0 / 0.0, 1.0 / 0.0, -1.0 / 0.0] {
    assert_true(root.with_opacity(invalid) is Err(InvalidOpacity))
    assert_true(node.with_opacity(invalid) is Err(InvalidOpacity))
  }
  assert_eq(root.opacity(), 1.0)
  assert_eq(node.opacity(), 1.0)
  assert_eq(root.with_opacity(0.0).unwrap().opacity(), 0.0)
  assert_eq(node.with_opacity(1.0).unwrap().opacity(), 1.0)
}

///|
test "actual lifecycle multiplies ancestors once and restores sibling scope" {
  let style = @layout.FlexTreeStyle::new(@layout.FlowDirection::row())
  let color = @primitives.Color::rgba(20, 40, 60, 127).unwrap()
  let parent = @element.Element::new(lifecycle_item(2, 40, 20))
    .with_opacity(0.5)
    .unwrap()
    .with_children_style(style)
    .with_background(Some(color))
    .with_child(
      @element.Element::new(lifecycle_item(3, 20, 20))
      .with_opacity(0.5)
      .unwrap()
      .with_background(Some(color)),
    )
    .with_child(
      @element.Element::new(lifecycle_item(4, 20, 20)).with_background(
        Some(color),
      ),
    )
  let root = @element.Element::root(1, style)
    .with_opacity(0.5)
    .unwrap()
    .with_child(parent)
    .with_child(
      @element.Element::new(lifecycle_item(5, 20, 20)).with_background(
        Some(color),
      ),
    )
  let frame = root
    .request_layout(lifecycle_size(80, 20))
    .unwrap()
    .prepaint()
    .unwrap()
  let scene = frame.paint()
  assert_eq(opacity_command(scene, 2).opacity(), 0.25)
  assert_eq(opacity_command(scene, 3).opacity(), 0.125)
  assert_eq(opacity_command(scene, 4).opacity(), 0.25)
  assert_eq(opacity_command(scene, 5).opacity(), 0.5)
  assert_true(opacity_command(scene, 3).color() == Some(color))
  assert_eq(frame.tree().node(3).unwrap().opacity(), 0.5)
  // Repainting the same immutable frame never compounds opacity.
  assert_true(frame.paint().commands() == scene.commands())
  let snapshot = frame.paint_snapshot(1).unwrap()
  for item in snapshot.items() {
    match item {
      @scene.QuadItem(id~, color=actual, opacity~, ..) => {
        assert_true(actual == color)
        assert_eq(opacity, opacity_command(scene, id).opacity())
      }
      _ => abort("background must remain a QuadItem")
    }
  }
}

///|
test "binding opacity and intrinsic float alpha are applied exactly once" {
  let frame = @element.Element::root(
      1,
      @layout.FlexTreeStyle::new(@layout.FlowDirection::row()),
    )
    .with_opacity(0.5)
    .unwrap()
    .with_child(
      @element.Element::new(lifecycle_item(2, 20, 20))
      .with_opacity(0.3)
      .unwrap(),
    )
    .request_layout(lifecycle_size(20, 20))
    .unwrap()
    .prepaint()
    .unwrap()
  let binding = @element.ElementPaintBinding::new(2, bounds => {
    Ok(
      (
        @scene.PaintShape::rounded_quad(bounds, 0).unwrap(),
        @scene.FloatSolid(
          @primitives.FloatColor::rgba(0.2, 0.4, 0.6, 0.37).unwrap(),
        ),
        0.7,
      ),
    )
  })
  let scene = frame.paint_with_paints([binding]).unwrap()
  assert_eq(opacity_command(scene, 2).opacity(), 0.5 * 0.3 * 0.7)
  let sample = scene
    .snapshot_v1(@primitives.Rect::new(0, 0, 20, 20).unwrap(), 1)
    .unwrap()
    .sample_paint(2, @primitives.Point::new(5, 5).unwrap())
    .unwrap()
    .unwrap()
  assert_eq(sample.alpha(), 0.37 * (0.5 * 0.3 * 0.7))
  assert_eq(sample.red(), 0.2)
  assert_true(
    frame.paint_with_paints([binding]).unwrap().commands() == scene.commands(),
  )
  let invalid = @element.ElementPaintBinding::new(2, bounds => {
    Ok(
      (
        @scene.PaintShape::rounded_quad(bounds, 0).unwrap(),
        @scene.FloatSolid(@primitives.FloatColor::rgba(1, 0, 0, 1).unwrap()),
        2.0,
      ),
    )
  })
  // An inherited zero must not hide an invalid binding-local scalar.
  let zero = @element.Element::root(
      2,
      @layout.FlexTreeStyle::new(@layout.FlowDirection::row()),
    )
    .with_opacity(0)
    .unwrap()
    .request_layout(lifecycle_size(20, 20))
    .unwrap()
    .prepaint()
    .unwrap()
  assert_true(
    zero.paint_with_paints([invalid]) is Err(PaintFailure(InvalidOpacity)),
  )
}

///|
test "zero opacity preserves actual geometry hit routing and focus" {
  let make = fn(opacity) {
    @element.Element::root(
      1,
      @layout.FlexTreeStyle::new(@layout.FlowDirection::row()),
    )
    .with_child(
      @element.Element::new(lifecycle_item(2, 20, 20))
      .with_opacity(opacity)
      .unwrap()
      .with_focusable(true)
      .with_tab_stop(true)
      .with_tab_index(3)
      .with_background(Some(lifecycle_color(255, 0, 0))),
    )
    .request_layout(lifecycle_size(40, 20))
    .unwrap()
    .prepaint()
    .unwrap()
  }
  let visible = make(1.0)
  let hidden = make(0.0)
  assert_true(
    visible.tree().node(2).unwrap().bounds() ==
    hidden.tree().node(2).unwrap().bounds(),
  )
  let point = @primitives.Point::new(5, 5).unwrap()
  assert_true(hidden.tree().hit_test(point) == Some(2))
  assert_true(hidden.tree().dispatch_pointer(point).target() == Some(2))
  assert_true(hidden.tree().with_focus(2).unwrap().focused() == Some(2))
  assert_eq(hidden.paint().command_count(), visible.paint().command_count())
  assert_eq(opacity_command(hidden.paint(), 2).opacity(), 0.0)
  assert_true(opacity_command(visible.paint(), 2) is @scene.QuadCommand(..))
}

///|
test "scroll clipping keeps inherited opacity and balanced commands" {
  let frame = @element.Element::root(
      1,
      @layout.FlexTreeStyle::new(@layout.FlowDirection::row()),
    )
    .with_opacity(0.5)
    .unwrap()
    .with_scroll_offset(@primitives.Point::new(0, 0).unwrap())
    .with_child(
      @element.Element::new(lifecycle_item(2, 20, 20))
      .with_opacity(0.5)
      .unwrap()
      .with_background(Some(lifecycle_color(255, 0, 0))),
    )
    .request_layout(lifecycle_size(20, 20))
    .unwrap()
    .prepaint()
    .unwrap()
  assert_eq(opacity_command(frame.paint(), 2).opacity(), 0.25)
  assert_true(frame.paint().validate() is Ok(_))
  assert_eq(frame.paint_snapshot(1).unwrap().clip_chains().length(), 1)
}

///|
test "query generated subtree inherits local opacity through actual prepaint" {
  let root = @element.Element::container_query_root(1, _size => {
      Ok(
        @element.Element::root(
          2,
          @layout.FlexTreeStyle::new(@layout.FlowDirection::row()),
        )
        .with_opacity(0.5)
        .unwrap()
        .with_child(
          @element.Element::new(lifecycle_item(3, 20, 20))
          .with_opacity(0.5)
          .unwrap()
          .with_background(Some(lifecycle_color(0, 255, 0))),
        ),
      )
    })
    .with_opacity(0.5)
    .unwrap()
  let frame = root
    .request_layout(lifecycle_size(20, 20))
    .unwrap()
    .prepaint()
    .unwrap()
  assert_eq(opacity_command(frame.paint(), 3).opacity(), 0.125)
}

///|
test "deferred attachment resets ancestor opacity but inherits its local scope" {
  let popup = anchor_popup(10, 20, 20, true).with_opacity(0.5).unwrap()
  let attachment = @element.Element::anchored_after(
      20,
      3,
      popup,
      @element.TopLeft,
      @element.Local,
      anchor_point(0, 0),
    )
    .unwrap()
    .deferred()
    .unwrap()
  let parent = anchor_parent().with_opacity(0.5).unwrap().with_child(attachment)
  let frame = anchor_root(parent, 0, 0)
    .with_opacity(0.5)
    .unwrap()
    .request_layout(anchor_size(320, 240))
    .unwrap()
    .prepaint()
    .unwrap()
  assert_eq(opacity_command(frame.paint(), 10).opacity(), 0.5)
  assert_true(frame.paint().validate() is Ok(_))
}

///|
test "overlapping descendants use per primitive alpha rather than group compositing" {
  let red = Some(lifecycle_color(255, 0, 0))
  let frame = @element.Element::root(
      1,
      @layout.FlexTreeStyle::new(@layout.FlowDirection::row()),
    )
    .with_opacity(0.5)
    .unwrap()
    .with_background(red)
    .with_child(
      @element.Element::new(lifecycle_item(2, 20, 20)).with_background(red),
    )
    .request_layout(lifecycle_size(20, 20))
    .unwrap()
    .prepaint()
    .unwrap()
  let bytes = frame
    .paint_snapshot(1)
    .unwrap()
    .rasterize_webgl2_linear(
      @primitives.Rect::new(0, 0, 20, 20).unwrap(),
      1,
      1,
      @primitives.FloatColor::rgba(0, 0, 0, 1).unwrap(),
    )
    .unwrap()
  assert_eq(bytes, [191, 0, 0, 255])
}

///|
test "uniform list visible row lowering preserves each local opacity" {
  let list = @element.UniformList::new(
      ul_item(2, 40, 220),
      4,
      @element.UniformListIdSpace::new(100, 4).unwrap(),
      range => {
        match ul_rows(range, 20) {
          Err(error) => Err(error)
          Ok(rows) =>
            Ok(
              rows.map(row => {
                row
                .with_opacity(0.5)
                .unwrap()
                .with_background(Some(lifecycle_color(0, 255, 0)))
              }),
            )
        }
      },
    )
    .unwrap()
    .into_element()
    .with_opacity(0.5)
    .unwrap()
  let frame = ul_root(list)
    .with_opacity(0.5)
    .unwrap()
    .request_layout(ul_size(420, 420))
    .unwrap()
    .prepaint()
    .unwrap()
  let commands = frame
    .paint()
    .commands()
    .filter(command => command.kind() == @scene.Quad)
  assert_true(commands.length() > 0)
  for command in commands {
    assert_eq(command.opacity(), 0.125)
  }
}
