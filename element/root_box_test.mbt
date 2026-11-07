///|
fn root_box_style() -> @layout.FlexTreeStyle {
  @layout.FlexTreeStyle::new(@layout.FlowDirection::row()).with_insets(
    @layout.Insets::new(5, 6, 5, 6).unwrap(),
    @layout.Insets::zero(),
  )
}

///|
fn root_box_root() -> @element.Element {
  @element.Element::root(1, root_box_style()).with_background(
    Some(@primitives.Color::rgba(255, 0, 0, 255).unwrap()),
  )
}

///|
fn root_box_size(width : Double, height : Double) -> @primitives.Size {
  @primitives.Size::new(width, height).unwrap()
}

///|
fn root_box_rect(width : Double, height : Double) -> @primitives.Rect {
  @primitives.Rect::new(0, 0, width, height).unwrap()
}

///|
fn root_box_point(x : Double, y : Double) -> @primitives.Point {
  @primitives.Point::new(x, y).unwrap()
}

///|
fn root_box_item(
  id : UInt64,
  width : Double,
  height : Double,
) -> @layout.FlexItem {
  @layout.FlexItem::new(
    id,
    @layout.Dimension::points(width).unwrap(),
    @layout.Dimension::points(height).unwrap(),
    root_box_size(width, height),
  )
  .with_flex(0, 0)
  .unwrap()
}

///|
test "authored root lifecycle preserves physical viewport and unmodified paint geometry" {
  let viewport = root_box_size(10, 8)
  let request = root_box_root().request_layout_root_box(viewport).unwrap()
  assert_true(request.viewport == viewport)
  assert_true(request.layout.root_bounds() == root_box_rect(12, 10))
  let prepainted = request.prepaint().unwrap()
  assert_true(prepainted.viewport() == viewport)
  assert_true(prepainted.viewport_bounds() == root_box_rect(10, 8))
  assert_true(prepainted.overflow())
  assert_eq(prepainted.tree().nodes().length(), 1)
  assert_true(
    prepainted.tree().node(1).unwrap().bounds() == root_box_rect(12, 10),
  )
  let commands = prepainted.paint().commands()
  assert_eq(commands.length(), 1)
  assert_true(commands[0].id() == 1)
  assert_true(commands[0].bounds() == Some(root_box_rect(12, 10)))
  let snapshot = prepainted.paint_snapshot(1).unwrap()
  assert_true(snapshot.viewport() == root_box_rect(10, 8))
  assert_eq(snapshot.items().length(), 1)
}

///|
// Headless renderer-boundary checks, not a native-window or desktop claim.
test "authored root snapshot raster clips expanded background to physical viewport" {
  let snapshot = root_box_root()
    .request_layout_root_box(root_box_size(10, 8))
    .unwrap()
    .prepaint()
    .unwrap()
    .paint_snapshot(1)
    .unwrap()
  let pixels = snapshot
    .rasterize_webgl2_linear(
      root_box_rect(14, 12),
      14,
      12,
      @primitives.FloatColor::rgba(0, 0, 0, 0).unwrap(),
    )
    .unwrap()
  for y = 0; y < 12; y = y + 1 {
    for x = 0; x < 14; x = x + 1 {
      let index = (y * 14 + x) * 4
      if x < 10 && y < 8 {
        assert_eq(pixels[index], 255)
        assert_eq(pixels[index + 3], 255)
      } else {
        assert_eq(pixels[index + 3], 0)
      }
    }
  }
  let tile = snapshot.rasterize_item_tile_webgl2_linear(0).unwrap().unwrap()
  assert_eq([tile.x(), tile.y(), tile.width(), tile.height()], [0, 0, 10, 8])
}

///|
test "authored root hit eligibility is the half-open physical viewport" {
  let tree = root_box_root()
    .request_layout_root_box(root_box_size(10, 8))
    .unwrap()
    .prepaint()
    .unwrap()
    .tree()
  assert_true(tree.hit_test(root_box_point(0, 0)) == Some(1))
  assert_true(tree.hit_test(root_box_point(9.999, 7.999)) == Some(1))
  for
    point in [
      root_box_point(-0.001, 4),
      root_box_point(4, -0.001),
      root_box_point(10, 4),
      root_box_point(4, 8),
      root_box_point(11, 9),
    ] {
    assert_true(tree.hit_test(point) is None)
    assert_true(tree.dispatch_pointer(point).target() is None)
  }
}

///|
test "authored root keeps ordinary nested flex and visible child overflow" {
  let row = @layout.FlexTreeStyle::new(@layout.FlowDirection::row())
  let root = root_box_root().with_child(
    @element.Element::new(root_box_item(2, 1, 1))
    .with_children_style(row)
    .with_child(@element.Element::new(root_box_item(3, 10, 10))),
  )
  let prepainted = root
    .request_layout_root_box(root_box_size(10, 8))
    .unwrap()
    .prepaint()
    .unwrap()
  let tree = prepainted.tree()
  assert_true(prepainted.overflow())
  assert_true(
    tree.node(2).unwrap().bounds() == @primitives.Rect::new(6, 5, 1, 1).unwrap(),
  )
  assert_true(
    tree.node(3).unwrap().bounds() ==
    @primitives.Rect::new(6, 5, 10, 10).unwrap(),
  )
  // The child may overflow its parent inside V, but never target outside V.
  assert_true(tree.hit_test(root_box_point(9, 7)) == Some(3))
  assert_true(tree.hit_test(root_box_point(10, 7)) is None)
  assert_true(tree.hit_test(root_box_point(9, 8)) is None)
}

///|
test "authored scaled root keeps fractional physical viewport while legacy stays snapped" {
  let viewport = root_box_size(10.25, 8.25)
  let root = root_box_root()
  let authored = root
    .request_layout_root_box_with_device_scale(viewport, 2)
    .unwrap()
    .prepaint()
    .unwrap()
  assert_true(
    authored.tree().node(1).unwrap().bounds() == root_box_rect(12, 10),
  )
  assert_true(authored.viewport_bounds() == root_box_rect(10.25, 8.25))
  assert_true(
    authored.paint_snapshot(2).unwrap().viewport() == root_box_rect(10.25, 8.25),
  )
  let legacy = root
    .request_layout_with_device_scale(viewport, 2)
    .unwrap()
    .prepaint()
    .unwrap()
  assert_true(legacy.tree().node(1).unwrap().bounds() == root_box_rect(10, 8))
  assert_true(legacy.viewport_bounds() == root_box_rect(10, 8))
  assert_true(
    legacy.paint_snapshot(2).unwrap().viewport() == root_box_rect(10, 8),
  )
  // The existing absolute-edge helper rounds midpoint ties toward zero.
  // Only the new path retains the unsnapped physical edge at x = 10.25.
  assert_true(legacy.tree().hit_test(root_box_point(10.1, 4)) is None)
  assert_true(authored.tree().hit_test(root_box_point(10.1, 4)) == Some(1))
  assert_true(authored.tree().hit_test(root_box_point(10.3, 4)) is None)
}

///|
test "authored lifecycle preserves legacy fixed roots at narrow equal and wide sizes" {
  for (width, height) in [(10.0, 8.0), (12.0, 10.0), (14.0, 12.0)] {
    let viewport = root_box_size(width, height)
    let legacy = root_box_root()
      .request_layout(viewport)
      .unwrap()
      .prepaint()
      .unwrap()
    assert_true(
      legacy.tree().node(1).unwrap().bounds() == root_box_rect(width, height),
    )
    assert_true(legacy.viewport_bounds() == root_box_rect(width, height))
    let authored = root_box_root()
      .request_layout_root_box(viewport)
      .unwrap()
      .prepaint()
      .unwrap()
    assert_true(authored.viewport_bounds() == root_box_rect(width, height))
    assert_true(authored.overflow() == (width < 12 || height < 10))
  }
}

///|
test "authored root rejects grid roots grid children and mixed nested containers" {
  let viewport = root_box_size(10, 8)
  let grid = @layout.GridTreeStyle::new(1, 1).unwrap()
  let grid_child = @element.Element::grid_item(
    @layout.GridItem::new(
      2,
      @layout.Dimension::auto(),
      @layout.Dimension::auto(),
    ),
  )
  for
    root in [
      @element.Element::grid_root(1, grid),
      root_box_root().with_child(grid_child),
      root_box_root().with_child(
        @element.Element::new(root_box_item(2, 4, 4)).with_grid_children_style(
          grid,
        ),
      ),
    ] {
    assert_true(
      root.request_layout_root_box(viewport)
      is Err(UnsupportedRootBoxComposition),
    )
    assert_true(
      root.request_layout_root_box_with_device_scale(viewport, 2)
      is Err(UnsupportedRootBoxComposition),
    )
  }
}

///|
test "authored root rejects root and nested queries without invoking callbacks" {
  let calls = Ref(0)
  let query : (@primitives.Size) -> Result[
    @element.Element,
    @element.ElementError,
  ] = fn(_) {
    calls.val += 1
    Ok(root_box_root())
  }
  let roots = [
    @element.Element::container_query_root(1, query),
    root_box_root().with_child(
      @element.Element::new(root_box_item(2, 4, 4))
      .with_children_style(
        @layout.FlexTreeStyle::new(@layout.FlowDirection::row()),
      )
      .with_child(
        @element.Element::new(root_box_item(3, 2, 2)).with_container_query(
          query,
        ),
      ),
    ),
  ]
  for root in roots {
    assert_true(
      root.request_layout_root_box(root_box_size(10, 8))
      is Err(UnsupportedRootBoxComposition),
    )
    assert_true(
      root.request_layout_root_box_with_device_scale(root_box_size(10, 8), 2)
      is Err(UnsupportedRootBoxComposition),
    )
  }
  assert_eq(calls.val, 0)
}

///|
test "authored root rejects anchored and deferred attachments before layout dispatch" {
  let attachment = @element.Element::anchored_after(
    3,
    2,
    @element.Element::new(root_box_item(4, 2, 2)),
    @element.TopLeft,
    @element.Window,
    root_box_point(0, 0),
  ).unwrap()
  for popup in [attachment, attachment.deferred().unwrap()] {
    let root = @element.Element::root(
        1,
        @layout.FlexTreeStyle::new(@layout.FlowDirection::column()),
      )
      .with_child(@element.Element::new(root_box_item(2, 4, 4)))
      .with_child(popup)
    assert_true(
      root.request_layout_root_box(root_box_size(10, 8))
      is Err(UnsupportedRootBoxComposition),
    )
    assert_true(
      root.request_layout_root_box_with_device_scale(root_box_size(10, 8), 2)
      is Err(UnsupportedRootBoxComposition),
    )
  }
}

///|
test "authored root rejects uniform lists before prototype factories run" {
  let calls = Ref(0)
  let list = @element.UniformList::new(
    root_box_item(2, 4, 4),
    1,
    @element.UniformListIdSpace::new(100, 4).unwrap(),
    fn(_) {
      calls.val += 1
      Ok([])
    },
  ).unwrap()
  let root = root_box_root().with_child(list.into_element())
  assert_true(
    root.request_layout_root_box(root_box_size(10, 8))
    is Err(UnsupportedRootBoxComposition),
  )
  assert_true(
    root.request_layout_root_box_with_device_scale(root_box_size(10, 8), 2)
    is Err(UnsupportedRootBoxComposition),
  )
  assert_eq(calls.val, 0)
}

///|
test "authored root lifecycle keeps root-required and invalid-scale errors" {
  assert_true(
    @element.Element::new(root_box_item(2, 1, 1)).request_layout_root_box(
      root_box_size(10, 8),
    )
    is Err(RootRequired),
  )
  for scale in [0.0, -1.0] {
    assert_true(
      root_box_root().request_layout_root_box_with_device_scale(
        root_box_size(10, 8),
        scale,
      )
      is Err(LayoutFailure(@layout.Flex(@layout.NegativeValue))),
    )
  }
}

///|
test "authored root lifecycle rejects nonfinite device scales" {
  for scale in [@double.infinity, @double.neg_infinity, @double.not_a_number] {
    assert_true(
      root_box_root().request_layout_root_box_with_device_scale(
        root_box_size(10, 8),
        scale,
      )
      is Err(LayoutFailure(@layout.Flex(@layout.NonFiniteValue))),
    )
  }
}
