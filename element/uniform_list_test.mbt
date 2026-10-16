// Observed cases were independently read from the actual source5a supplemental
// headless trace, CI 38968060005 / artifact 12075667392, raw SHA256
// 23c70cdb9f668f31200fcf89babe52a795d83cecc5a123de10880334d2d2b4e7.
// These are regression assertions against that font-free fixture, not a
// cross-runtime comparison or unchanged-example/browser/native parity claim.
// Tests labeled defensive extend the bounded API beyond that corpus.

///|
fn ul_size(w : Double, h : Double) -> @primitives.Size {
  @primitives.Size::new(w, h).unwrap()
}

///|
fn ul_point(x : Double, y : Double) -> @primitives.Point {
  @primitives.Point::new(x, y).unwrap()
}

///|
fn ul_rect(x : Double, y : Double, w : Double, h : Double) -> @primitives.Rect {
  @primitives.Rect::new(x, y, w, h).unwrap()
}

///|
fn ul_column() -> @layout.FlexTreeStyle {
  @layout.FlexTreeStyle::new(@layout.FlowDirection::column())
}

///|
fn ul_item(id : UInt64, h : Double, w : Double) -> @layout.FlexItem {
  @layout.FlexItem::new(
    id,
    @layout.Dimension::points(h).unwrap(),
    @layout.Dimension::points(w).unwrap(),
    ul_size(w, h),
  )
  .with_flex(0, 0)
  .unwrap()
}

///|
fn ul_auto(id : UInt64, w : Double, h : Double) -> @layout.FlexItem {
  @layout.FlexItem::new(
    id,
    @layout.Dimension::auto(),
    @layout.Dimension::auto(),
    ul_size(w, h),
  )
  .with_flex(0, 0)
  .unwrap()
}

///|
fn ul_id(index : Int32) -> UInt64 {
  100 + index.to_uint64() * 4
}

///|
fn ul_rows(
  range : @element.UniformListRange,
  inner_height : Double,
  padded~ : Bool = false,
) -> Result[Array[@element.Element], @element.UniformListError] {
  // Fail boundedly even if a regression asks the factory to build all N rows.
  if range.end() - range.start() > 64 {
    return Err(@element.FactoryFailure("test factory exceeded visible budget"))
  }
  let style = if padded {
    ul_column().with_insets(
      @layout.Insets::new(3, 8, 5, 8).unwrap(),
      @layout.Insets::zero(),
    )
  } else {
    ul_column()
  }
  let rows = []
  for index = range.start(); index < range.end(); index = index + 1 {
    rows.push(
      @element.Element::new(ul_auto(range.id(index, 0).unwrap(), 0, 0))
      .with_children_style(style)
      .with_child(
        @element.Element::new(
          ul_auto(
            range.id(index, 1).unwrap(),
            if padded {
              42
            } else {
              220
            },
            inner_height,
          ),
        ),
      ),
    )
  }
  Ok(rows)
}

///|
fn ul_list(
  count : Int32,
  inner_height : Double,
  viewport_height : Double,
  offset : Double,
  calls : Array[(Int32, Int32)],
  padded~ : Bool = false,
) -> @element.UniformList {
  @element.UniformList::new(
    ul_item(2, viewport_height, 220),
    count,
    @element.UniformListIdSpace::new(100, 4).unwrap(),
    range => {
      calls.push((range.start(), range.end()))
      ul_rows(range, inner_height, padded~)
    },
  )
  .unwrap()
  .with_scroll_offset(offset)
  .unwrap()
}

///|
fn ul_root(list : @element.Element) -> @element.Element {
  @element.Element::root(
    1,
    ul_column().with_insets(
      @layout.Insets::new(50, 0, 0, 40).unwrap(),
      @layout.Insets::zero(),
    ),
  ).with_child(list)
}

///|
fn ul_frame(
  count : Int32,
  inner_height : Double,
  viewport_height : Double,
  offset : Double,
  calls : Array[(Int32, Int32)],
) -> @element.Prepainted {
  ul_root(
    ul_list(count, inner_height, viewport_height, offset, calls).into_element(),
  )
  .request_layout(ul_size(420, 420))
  .unwrap()
  .prepaint()
  .unwrap()
}

///|
fn ul_down(
  x : Double,
  y : Double,
  button~ : @primitives.MouseButton = @primitives.Primary,
) -> @primitives.InputEvent {
  @primitives.PointerButtonPressed(
    position=ul_point(x, y),
    button~,
    modifiers=@primitives.Modifiers::none(),
  )
}

///|
fn ul_up(
  x : Double,
  y : Double,
  button~ : @primitives.MouseButton = @primitives.Primary,
) -> @primitives.InputEvent {
  @primitives.PointerButtonReleased(
    position=ul_point(x, y),
    button~,
    modifiers=@primitives.Modifiers::none(),
  )
}

///|
test "uniform observed lifecycle measures two prototypes and publishes only live rows" {
  let calls = []
  let root = ul_root(ul_list(50, 26, 300, 0, calls).into_element())
  let requested = root.request_layout(ul_size(420, 420)).unwrap()
  assert_true(calls == [(0, 1)])
  let frame = requested.prepaint().unwrap()
  assert_true(calls == [(0, 1), (0, 1), (0, 12)])
  let tree = frame.tree()
  let list = tree.uniform_list(2).unwrap()
  assert_true(list.id() == 2 && list.item_count() == 50)
  assert_true(list.measured_item_size() == Some(ul_size(220, 26)))
  assert_true(list.bounds() == ul_rect(40, 50, 220, 300))
  assert_true(list.content_size() == ul_size(220, 1300))
  assert_true(list.offset() == 0 && list.max_offset() == 1000)
  assert_eq(tree.nodes().length(), 26)
  for index = 0; index < 12; index = index + 1 {
    assert_true(
      tree.node(ul_id(index)).unwrap().bounds() ==
      ul_rect(40, 50 + index.to_double() * 26, 220, 26),
    )
    assert_true(
      tree.node(ul_id(index) + 1).unwrap().bounds() ==
      tree.node(ul_id(index)).unwrap().bounds(),
    )
    assert_true(tree.node(ul_id(index)).unwrap().parent() == Some(2))
  }
  assert_true(tree.node(ul_id(12)) is None)
  assert_true(tree.uniform_list(1) is None)
  assert_true(tree.uniform_list(999) is None)
  let viewport = tree.scroll_viewport(2).unwrap()
  assert_true(viewport.bounds() == list.bounds())
  assert_true(viewport.offset() == ul_point(0, 0))
  assert_true(viewport.max_offset() == ul_point(0, 1000))
}

///|
test "uniform defensive recursive measurement includes authored row insets" {
  // The supplemental Rust fixture has zero insets; h34 is a genuine MoonBit
  // layout contract, independently probed on the unchanged MoonBit baseline.
  let calls = []
  let frame = ul_root(
      ul_list(50, 26, 300, 0, calls, padded=true).into_element(),
    )
    .request_layout(ul_size(420, 420))
    .unwrap()
    .prepaint()
    .unwrap()
  let tree = frame.tree()
  let list = tree.uniform_list(2).unwrap()
  assert_true(list.measured_item_size() == Some(ul_size(58, 34)))
  assert_true(list.content_size() == ul_size(220, 1700))
  assert_true(list.max_offset() == 1400)
  assert_true(calls == [(0, 1), (0, 1), (0, 9)])
  assert_true(tree.node(100).unwrap().bounds() == ul_rect(40, 50, 220, 34))
  assert_true(tree.node(101).unwrap().bounds() == ul_rect(48, 53, 42, 26))
}

///|
test "uniform observed partial and exact boundaries retain full extent and stable IDs" {
  for
    (offset, first, limit) in [
      (0.0, 0, 12),
      (25.0, 0, 13),
      (26.0, 1, 13),
      (27.0, 1, 13),
      (1000.0, 38, 50),
    ] {
    let calls = []
    let tree = ul_frame(50, 26, 300, offset, calls).tree()
    let list = tree.uniform_list(2).unwrap()
    assert_true(calls == [(0, 1), (0, 1), (first, limit)])
    assert_true(
      list.visible_range().start() == first &&
      list.visible_range().end() == limit,
    )
    assert_true(list.content_size() == ul_size(220, 1300))
    assert_true(list.max_offset() == 1000 && list.offset() == offset)
    assert_eq(tree.nodes().length(), 2 + 2 * (limit - first))
    for index = first; index < limit; index = index + 1 {
      assert_true(list.visible_range().id(index, 0) == Ok(ul_id(index)))
      assert_true(
        tree.node(ul_id(index)).unwrap().bounds() ==
        ul_rect(40, 50 + index.to_double() * 26 - offset, 220, 26),
      )
    }
    if first > 0 {
      assert_true(tree.node(ul_id(0)) is None)
    }
    if limit < 50 {
      assert_true(tree.node(ul_id(limit)) is None)
    }
  }
  for
    (viewport, offset, first, limit) in [
      (13.0, 0.0, 0, 1),
      (13.0, 25.0, 0, 2),
      (13.0, 1287.0, 49, 50),
      (52.0, 0.0, 0, 2),
      (52.0, 26.0, 1, 3),
      (52.0, 27.0, 1, 4),
    ] {
    let calls = []
    let list = ul_frame(50, 26, viewport, offset, calls)
      .tree()
      .uniform_list(2)
      .unwrap()
    assert_true(calls == [(0, 1), (0, 1), (first, limit)])
    assert_true(list.max_offset() == 1300 - viewport)
  }
}

///|
test "uniform observed million row range allocates only visible subtrees" {
  for
    (offset, first, limit, first_y) in [
      (0.0, 0, 12, 50.0),
      (25999500.0, 999980, 999993, 30.0),
      (100000000.0, 999988, 1000000, 38.0),
      (25999674.0, 999987, 999999, 38.0),
    ] {
    let calls = []
    let tree = ul_frame(1000000, 26, 300, offset, calls).tree()
    let list = tree.uniform_list(2).unwrap()
    assert_true(calls == [(0, 1), (0, 1), (first, limit)])
    assert_true(list.content_size() == ul_size(220, 26000000))
    assert_true(list.max_offset() == 25999700)
    assert_eq(tree.nodes().length(), 2 + 2 * (limit - first))
    assert_true(
      tree.node(ul_id(first)).unwrap().bounds() == ul_rect(40, first_y, 220, 26),
    )
    assert_true(list.visible_range().id(limit - 1, 0) == Ok(ul_id(limit - 1)))
    if first > 0 {
      assert_true(tree.node(100) is None)
    }
  }
}

///|
test "uniform observed viewport count and metric changes reclamp retained state immutably" {
  let old = ul_frame(50, 26, 300, 1000, []).tree()
  let resized = ul_frame(50, 26, 350, 1000, []).tree()
  assert_true(resized.uniform_list(2).unwrap().offset() == 950)
  assert_true(resized.uniform_list(2).unwrap().visible_range().start() == 36)
  let shrunk = ul_frame(7, 26, 350, 950, []).tree()
  assert_true(shrunk.uniform_list(2).unwrap().offset() == 0)
  assert_true(
    shrunk.uniform_list(2).unwrap().content_size() == ul_size(220, 182),
  )
  let taller = ul_frame(50, 31, 350, 0, []).tree()
  assert_true(
    taller.uniform_list(2).unwrap().measured_item_size() ==
    Some(ul_size(220, 31)),
  )
  assert_true(
    taller.uniform_list(2).unwrap().content_size() == ul_size(220, 1550),
  )
  assert_true(taller.uniform_list(2).unwrap().max_offset() == 1200)
  let endpoint = ul_frame(50, 31, 350, 99999, []).tree()
  assert_true(endpoint.uniform_list(2).unwrap().offset() == 1200)
  assert_true(
    endpoint.node(ul_id(38)).unwrap().bounds() == ul_rect(40, 28, 220, 31),
  )
  assert_true(old.uniform_list(2).unwrap().offset() == 1000)
  assert_true(old.node(ul_id(38)).unwrap().bounds() == ul_rect(40, 38, 220, 26))
  assert_true(
    ul_frame(50, 26, 300, -1000, []).tree().uniform_list(2).unwrap().offset() ==
    0,
  )
}

///|
test "uniform observed empty and one row lists do not fabricate prototype nodes" {
  let calls = []
  let tree = ul_frame(0, 26, 300, 1000, calls).tree()
  let list = tree.uniform_list(2).unwrap()
  assert_true(calls == [])
  assert_eq(tree.nodes().length(), 2)
  assert_true(list.measured_item_size() is None)
  assert_true(list.content_size() == ul_size(220, 0))
  assert_true(list.offset() == 0 && list.max_offset() == 0)
  assert_true(
    list.visible_range().start() == 0 && list.visible_range().end() == 0,
  )
  assert_true(
    tree.scroll_wheel(ul_point(100, 100), 0, 100).unwrap()[0].offset() ==
    ul_point(0, 0),
  )
  let session = @element.UniformListClickSession::new(2)
  assert_true(session.dispatch(tree, ul_down(100, 60)) is @element.Unchanged)
  assert_true(session.dispatch(tree, ul_up(100, 60)) is @element.Unchanged)
  let calls = []
  let one = ul_frame(1, 26, 300, 1000, calls).tree()
  assert_true(calls == [(0, 1), (0, 1), (0, 1)])
  assert_eq(one.nodes().length(), 4)
  assert_true(one.uniform_list(2).unwrap().max_offset() == 0)
  assert_true(
    session.dispatch(one, ul_down(100, 60)) is @element.Pressed(index=0, id=100),
  )
  assert_true(
    session.dispatch(one, ul_up(100, 60)) is @element.Clicked(index=0, id=100),
  )
  assert_true(session.dispatch(one, ul_down(100, 100)) is @element.Unchanged)
  assert_true(session.dispatch(one, ul_up(100, 100)) is @element.Unchanged)
}

///|
test "uniform observed wheel policy with defensive finite endpoint saturation" {
  let mut offset = 100.0
  for
    (dx, dy, expected) in [
      (0.0, 25.0, 125.0),
      (26.0, 0.0, 151.0),
      (40.0, 7.0, 158.0),
      (-80.0, 9.0, 167.0),
      (0.0, -31.0, 136.0),
    ] {
    let tree = ul_frame(50, 26, 300, offset, []).tree()
    let updates = tree.scroll_wheel(ul_point(100, 100), dx, dy).unwrap()
    assert_eq(updates.length(), 1)
    assert_true(
      updates[0].id() == 2 && updates[0].offset() == ul_point(0, expected),
    )
    assert_true(tree.uniform_list(2).unwrap().offset() == offset)
    offset = updates[0].offset().y()
  }
  let tree = ul_frame(50, 26, 300, offset, []).tree()
  for
    point in [
      ul_point(39.5, 100),
      ul_point(100, 49.5),
      ul_point(260, 100),
      ul_point(100, 350),
    ] {
    assert_true(tree.scroll_wheel(point, 40, 30) is Ok([]))
  }
  assert_true(
    tree.scroll_wheel(ul_point(100, 100), 0, 0).unwrap()[0].offset() ==
    ul_point(0, 136),
  )
  assert_true(
    tree.scroll_wheel(ul_point(100, 100), 0, 1.7976931348623157e308).unwrap()[0].offset() ==
    ul_point(0, 1000),
  )
  assert_true(
    tree.scroll_wheel(ul_point(100, 100), -1.7976931348623157e308, 0).unwrap()[0].offset() ==
    ul_point(0, 0),
  )
}

///|
test "uniform observed partial rows use real scene clips and half open hit routes" {
  let frame = ul_frame(50, 26, 300, 25, [])
  let tree = frame.tree()
  assert_true(tree.node(100).unwrap().bounds() == ul_rect(40, 25, 220, 26))
  assert_true(
    tree.node(ul_id(12)).unwrap().bounds() == ul_rect(40, 337, 220, 26),
  )
  assert_true(tree.hit_test(ul_point(100, 50)) == Some(101))
  assert_true(
    tree.dispatch_pointer(ul_point(100, 50)).bubble() == [101, 100, 2, 1],
  )
  for
    (x, y, index) in [
      (100.0, 50.0, 0),
      (259.5, 100.0, 2),
      (100.0, 349.5, 12),
      (40.0, 100.0, 2),
    ] {
    let session = @element.UniformListClickSession::new(2)
    assert_true(
      session.dispatch(tree, ul_down(x, y))
      is @element.Pressed(index=actual_index, id~) &&
      actual_index == index &&
      id == ul_id(index),
    )
    assert_true(
      session.dispatch(tree, ul_up(x, y))
      is @element.Clicked(index=actual_index, id~) &&
      actual_index == index &&
      id == ul_id(index),
    )
  }
  for
    point in [
      ul_point(100, 49.5),
      ul_point(39.5, 100),
      ul_point(260, 100),
      ul_point(100, 350),
      ul_point(100, 360),
    ] {
    assert_true(tree.hit_test(point) == Some(1))
    let session = @element.UniformListClickSession::new(2)
    assert_true(
      session.dispatch(tree, ul_down(point.x(), point.y()))
      is @element.Unchanged,
    )
    assert_true(
      session.dispatch(tree, ul_up(point.x(), point.y())) is @element.Unchanged,
    )
  }
  let commands = frame.paint().commands()
  assert_eq(commands.length(), 2)
  assert_true(commands[0].kind() == @scene.ClipPush && commands[0].id() == 2)
  assert_true(commands[0].bounds() == Some(ul_rect(40, 50, 220, 300)))
  assert_true(commands[1].kind() == @scene.ClipPop && commands[1].id() == 2)
}

///|
test "uniform observed stable row click survives changed position only while live" {
  let initial = ul_frame(50, 26, 300, 0, []).tree()
  let one_row = ul_frame(50, 26, 300, 26, []).tree()
  let moved = ul_frame(50, 26, 300, 36, []).tree()
  let session = @element.UniformListClickSession::new(2)
  let shared = session
  assert_true(
    session.dispatch(initial, ul_down(100, 140))
    is @element.Pressed(index=3, id=112),
  )
  assert_true(
    session.dispatch(initial, ul_up(100, 140))
    is @element.Clicked(index=3, id=112),
  )
  assert_true(shared.dispatch(initial, ul_up(100, 140)) is @element.Unchanged)
  assert_true(
    session.dispatch(one_row, ul_down(100, 114))
    is @element.Pressed(index=3, id=112),
  )
  assert_true(
    session.dispatch(one_row, ul_up(100, 114))
    is @element.Clicked(index=3, id=112),
  )
  assert_true(
    session.dispatch(one_row, ul_down(100, 114))
    is @element.Pressed(index=3, id=112),
  )
  assert_true(!session.reconcile(moved))
  assert_true(
    shared.dispatch(moved, ul_up(100, 104)) is @element.Clicked(index=3, id=112),
  )
  assert_true(session.dispatch(moved, ul_up(100, 104)) is @element.Unchanged)
  assert_true(
    session.dispatch(initial, ul_down(100, 140))
    is @element.Pressed(index=3, id=112),
  )
  let omitted = ul_frame(50, 26, 300, 500, []).tree()
  assert_true(omitted.node(112) is None)
  assert_true(session.reconcile(omitted))
  assert_true(!session.reconcile(initial))
  assert_true(session.dispatch(initial, ul_up(100, 140)) is @element.Unchanged)
  assert_true(
    session.dispatch(initial, ul_down(100, 140))
    is @element.Pressed(index=3, id=112),
  )
  assert_true(session.reconcile(ul_frame(2, 26, 300, 0, []).tree()))
  assert_true(!session.reconcile(initial))
  assert_true(session.dispatch(initial, ul_up(100, 140)) is @element.Unchanged)
}

///|
test "uniform observed no down other row and outside releases cannot click" {
  let tree = ul_frame(50, 26, 300, 0, []).tree()
  let session = @element.UniformListClickSession::new(2)
  assert_true(session.dispatch(tree, ul_up(100, 140)) is @element.Unchanged)
  assert_true(
    session.dispatch(tree, ul_down(100, 140))
    is @element.Pressed(index=3, id=112),
  )
  assert_true(session.dispatch(tree, ul_up(100, 160)) is @element.Cancelled)
  assert_true(
    session.dispatch(tree, ul_down(100, 140))
    is @element.Pressed(index=3, id=112),
  )
  assert_true(session.dispatch(tree, ul_up(100, 400)) is @element.Cancelled)
  assert_true(session.dispatch(tree, ul_up(100, 140)) is @element.Unchanged)
}

///|
test "uniform defensive nonprimary input and moved away returned pointer" {
  let tree = ul_frame(50, 26, 300, 0, []).tree()
  let session = @element.UniformListClickSession::new(2)
  assert_true(
    session.dispatch(tree, ul_down(100, 140, button=@primitives.Secondary))
    is @element.Unchanged,
  )
  assert_true(
    session.dispatch(tree, ul_up(100, 140, button=@primitives.Secondary))
    is @element.Unchanged,
  )
  assert_true(
    session.dispatch(tree, ul_down(100, 140))
    is @element.Pressed(index=3, id=112),
  )
  assert_true(
    session.dispatch(
      tree,
      @primitives.PointerMoved(position=ul_point(400, 400)),
    )
    is @element.Unchanged,
  )
  assert_true(
    session.dispatch(
      tree,
      @primitives.PointerMoved(position=ul_point(100, 140)),
    )
    is @element.Unchanged,
  )
  assert_true(
    session.dispatch(tree, ul_up(100, 140)) is @element.Clicked(index=3, id=112),
  )
}

///|
test "uniform defensive model replacement cancellation consumes shared session state" {
  let tree = ul_frame(50, 26, 300, 0, []).tree()
  let session = @element.UniformListClickSession::new(2)
  let shared = session
  assert_true(!session.cancel())
  assert_true(
    session.dispatch(tree, ul_down(100, 140))
    is @element.Pressed(index=3, id=112),
  )
  assert_true(shared.cancel())
  assert_true(!session.cancel())
  assert_true(session.dispatch(tree, ul_up(100, 140)) is @element.Unchanged)
  assert_true(
    session.dispatch(tree, ul_down(100, 140))
    is @element.Pressed(index=3, id=112),
  )
  let ordinary = @element.Element::root(1, ul_column())
    .request_layout(ul_size(420, 420))
    .unwrap()
    .prepaint()
    .unwrap()
    .tree()
  assert_true(session.dispatch(ordinary, ul_up(100, 140)) is @element.Cancelled)
}

///|
fn ul_custom(
  factory : (@element.UniformListRange) -> Result[
    Array[@element.Element],
    @element.UniformListError,
  ],
) -> @element.Element {
  ul_root(
    @element.UniformList::new(
      ul_item(2, 300, 220),
      50,
      @element.UniformListIdSpace::new(100, 4).unwrap(),
      factory,
    )
    .unwrap()
    .into_element(),
  )
}

///|
test "uniform defensive checked count and complete UInt64 namespace reject overflow" {
  assert_true(
    @element.UniformListIdSpace::new(100, 0) is Err(@element.InvalidIdSpace),
  )
  let ids = @element.UniformListIdSpace::new(100, 4).unwrap()
  assert_true(
    @element.UniformList::new(ul_item(2, 300, 220), -1, ids, _ => Ok([]))
    is Err(@element.InvalidCount),
  )
  assert_true(
    @element.UniformList::new(
      ul_item(2, 300, 220),
      50,
      @element.UniformListIdSpace::new(0, 4).unwrap(),
      _ => Ok([]),
    )
    is Err(@element.ReservedIdCollision(2)),
  )
  let max_id : UInt64 = 0xffff_ffff_ffff_ffff
  assert_true(
    @element.UniformList::new(
      ul_item(2, 300, 220),
      2,
      @element.UniformListIdSpace::new(100, max_id).unwrap(),
      _ => Ok([]),
    )
    is Err(@element.InvalidIdSpace),
  )
  assert_true(
    @element.UniformList::new(
      ul_item(2, 300, 220),
      2,
      @element.UniformListIdSpace::new(max_id - 2, 2).unwrap(),
      _ => Ok([]),
    )
    is Err(@element.InvalidIdSpace),
  )
  // This accepts a valid namespace near the full UInt64 boundary without
  // converting identities to Double or constructing all rows.
  let root = ul_root(
    @element.UniformList::new(
      ul_item(2, 300, 220),
      2,
      @element.UniformListIdSpace::new(max_id - 3, 2).unwrap(),
      range => ul_rows(range, 26),
    )
    .unwrap()
    .into_element(),
  )
  let tree = root
    .request_layout(ul_size(420, 420))
    .unwrap()
    .prepaint()
    .unwrap()
    .tree()
  assert_true(tree.node(max_id - 3) is Some(_))
  assert_true(tree.node(max_id - 1) is Some(_))
  assert_true(tree.node(max_id) is Some(_))
  assert_eq(tree.nodes().length(), 6)
}

///|
test "uniform defensive Int maximum count remains bounded and range IDs stay checked" {
  let calls = []
  let tree = ul_frame(2147483647, 26, 300, 1.0e20, calls).tree()
  let list = tree.uniform_list(2).unwrap()
  assert_true(list.item_count() == 2147483647)
  assert_true(list.content_size() == ul_size(220, 55834574822.0))
  assert_true(list.max_offset() == 55834574522.0)
  assert_true(calls == [(0, 1), (0, 1), (2147483635, 2147483647)])
  assert_eq(tree.nodes().length(), 26)
  let range = list.visible_range()
  assert_true(range.id(2147483646, 3) == Ok(8589934687))
  assert_true(
    range.id(range.start() - 1, 0)
    is Err(@element.InvalidRangeIndex(2147483634)),
  )
  assert_true(
    range.id(range.end(), 0) is Err(@element.InvalidRangeIndex(2147483647)),
  )
  assert_true(range.id(range.start(), 4) is Err(@element.InvalidLocalSlot(4)))
  assert_true(
    range.id(range.start(), 0xffff_ffff_ffff_ffff)
    is Err(@element.InvalidLocalSlot(0xffff_ffff_ffff_ffff)),
  )
}

///|
test "uniform defensive static and pairwise reserved span collisions include offscreen IDs" {
  let calls = []
  let colliding_sibling = ul_root(ul_list(50, 26, 300, 0, calls).into_element()).with_child(
    @element.Element::new(ul_item(ul_id(49) + 3, 1, 1)),
  )
  assert_true(
    colliding_sibling.request_layout(ul_size(420, 420))
    is Err(@element.UniformListFailure(@element.ReservedIdCollision(299))),
  )
  assert_true(calls == [])
  let first = ul_list(50, 26, 300, 0, calls).into_element()
  let second = @element.UniformList::new(
      ul_item(3, 30, 220),
      50,
      @element.UniformListIdSpace::new(299, 4).unwrap(),
      range => ul_rows(range, 26),
    )
    .unwrap()
    .into_element()
  assert_true(
    ul_root(first).with_child(second).request_layout(ul_size(420, 420))
    is Err(@element.UniformListFailure(@element.ReservedIdCollision(299))),
  )
  assert_true(calls == [])
  let adjacent = @element.UniformList::new(
      ul_item(3, 30, 220),
      50,
      @element.UniformListIdSpace::new(300, 4).unwrap(),
      range => ul_rows(range, 26),
    )
    .unwrap()
    .into_element()
  let tree = ul_root(ul_list(50, 26, 300, 0, []).into_element())
    .with_child(adjacent)
    .request_layout(ul_size(420, 420))
    .unwrap()
    .prepaint()
    .unwrap()
    .tree()
  assert_true(
    tree.uniform_list(2) is Some(_) && tree.uniform_list(3) is Some(_),
  )
  assert_true(tree.node(100) is Some(_) && tree.node(300) is Some(_))
}

///|
test "uniform defensive factories reject cardinality identity duplication and unsupported rows" {
  let empty = ul_custom(_ => Ok([]))
  assert_true(
    empty.request_layout(ul_size(420, 420))
    is Err(@element.UniformListFailure(@element.InvalidFactoryLength(1, 0))),
  )
  let wrong_root = ul_custom(_ => {
    Ok([@element.Element::new(ul_auto(999, 220, 26))])
  })
  assert_true(
    wrong_root.request_layout(ul_size(420, 420))
    is Err(@element.UniformListFailure(@element.InvalidRowRoot(0, 999))),
  )
  let outside = ul_custom(_ => {
    Ok([
      @element.Element::new(ul_auto(100, 0, 0))
      .with_children_style(ul_column())
      .with_child(@element.Element::new(ul_auto(104, 220, 26))),
    ])
  })
  assert_true(
    outside.request_layout(ul_size(420, 420))
    is Err(@element.UniformListFailure(@element.RowIdOutsideNamespace(0, 104))),
  )
  let duplicate = ul_custom(_ => {
    Ok([
      @element.Element::new(ul_auto(100, 0, 0))
      .with_children_style(ul_column())
      .with_child(@element.Element::new(ul_auto(101, 220, 26)))
      .with_child(@element.Element::new(ul_auto(101, 220, 26))),
    ])
  })
  assert_true(
    duplicate.request_layout(ul_size(420, 420)) is Err(@element.DuplicateId),
  )
  let rooted = ul_custom(_ => Ok([@element.Element::root(100, ul_column())]))
  assert_true(
    rooted.request_layout(ul_size(420, 420))
    is Err(@element.UniformListFailure(@element.UnsupportedRowShape(0))),
  )
  let sized = ul_custom(_ => Ok([@element.Element::new(ul_item(100, 26, 220))]))
  assert_true(
    sized.request_layout(ul_size(420, 420))
    is Err(@element.UniformListFailure(@element.UnsupportedRowShape(0))),
  )
  let scrolling = ul_custom(_ => {
    Ok([
      @element.Element::new(ul_auto(100, 220, 26)).with_scroll_offset(
        ul_point(0, 0),
      ),
    ])
  })
  assert_true(
    scrolling.request_layout(ul_size(420, 420))
    is Err(@element.UniformListFailure(@element.UnsupportedRowShape(0))),
  )
  let nested = ul_custom(_ => {
    Ok([
      @element.Element::new(ul_auto(100, 0, 0))
      .with_children_style(ul_column())
      .with_child(
        @element.UniformList::new(
          ul_item(101, 26, 220),
          0,
          @element.UniformListIdSpace::new(1000, 4).unwrap(),
          _ => Ok([]),
        )
        .unwrap()
        .into_element(),
      ),
    ])
  })
  assert_true(
    nested.request_layout(ul_size(420, 420))
    is Err(@element.UniformListFailure(@element.UnsupportedRowShape(0))),
  )
}

///|
test "uniform defensive converted list shape is validated rather than silently ignored" {
  let list = ul_list(50, 26, 300, 0, []).into_element()
  for
    invalid in [
      list.with_children_style(ul_column()),
      list.with_child(@element.Element::new(ul_item(999, 1, 1))),
      list.with_scroll_offset(ul_point(0, 0)),
    ] {
    assert_true(
      ul_root(invalid).request_layout(ul_size(420, 420))
      is Err(@element.UniformListFailure(@element.UnsupportedListShape)),
    )
  }
  assert_true(
    @element.UniformList::new(
      ul_auto(2, 220, 300),
      50,
      @element.UniformListIdSpace::new(100, 4).unwrap(),
      range => ul_rows(range, 26),
    )
    is Err(@element.UnsupportedListShape),
  )
}

///|
test "uniform defensive invalid heights nonfinite inputs and geometry overflow are explicit" {
  let zero = ul_custom(range => ul_rows(range, 0))
  assert_true(
    zero.request_layout(ul_size(420, 420))
    is Err(@element.UniformListFailure(@element.InvalidMeasuredHeight)),
  )
  let list = ul_list(50, 26, 300, 125, [])
  let tree = ul_frame(50, 26, 300, 125, []).tree()
  for invalid in [@double.not_a_number, @double.infinity, @double.neg_infinity] {
    assert_true(
      list.with_scroll_offset(invalid) is Err(@element.NonFiniteOffset),
    )
    assert_true(
      tree.scroll_wheel(ul_point(100, 100), invalid, 0)
      is Err(@element.NonFiniteValue),
    )
    assert_true(
      tree.scroll_wheel(ul_point(100, 100), 0, invalid)
      is Err(@element.NonFiniteValue),
    )
  }
  assert_true(tree.uniform_list(2).unwrap().offset() == 125)
  let huge = ul_custom(range => ul_rows(range, 1.0e307))
  let requested = huge.request_layout(ul_size(420, 420)).unwrap()
  assert_true(
    requested.prepaint()
    is Err(@element.UniformListFailure(@element.GeometryOverflow)),
  )
}

///|
test "uniform defensive late factory errors preserve old tree focus and click ownership" {
  let before_frame = ul_root(
      ul_list(50, 26, 300, 26, []).into_element().with_focusable(true),
    )
    .request_layout(ul_size(420, 420))
    .unwrap()
    .prepaint()
    .unwrap()
  let before = before_frame.tree().with_focus(2).unwrap()
  let owner = before.focus_owner().unwrap()
  let session = @element.UniformListClickSession::new(2)
  assert_true(
    session.dispatch(before, ul_down(100, 114))
    is @element.Pressed(index=3, id=112),
  )
  for failing_call in [1, 2, 3] {
    let calls = Ref(0)
    let root = ul_custom(range => {
      calls.val = calls.val + 1
      if calls.val == failing_call {
        Err(@element.FactoryFailure("deliberate failure"))
      } else {
        ul_rows(range, 26)
      }
    })
    let result = match root.request_layout(ul_size(420, 420)) {
      Err(error) => Err(error)
      Ok(requested) => requested.prepaint()
    }
    assert_true(
      result
      is Err(
        @element.UniformListFailure(
          @element.FactoryFailure("deliberate failure")
        )
      ),
    )
    // Callback trace side effects remain observable; atomicity covers only
    // published trees and owner/session state, not arbitrary callback effects.
    assert_eq(calls.val, failing_call)
    assert_true(before.uniform_list(2).unwrap().offset() == 26)
    assert_true(before.focus_owner() == Some(owner))
    assert_true(before.node(112).unwrap().bounds() == ul_rect(40, 102, 220, 26))
    assert_true(!session.reconcile(before))
  }
  assert_true(
    session.dispatch(before, ul_up(100, 114))
    is @element.Clicked(index=3, id=112),
  )
  assert_true(
    before.with_layout_bounds(before_frame)
    is Err(@element.ScrollLayoutBoundsUnsupported),
  )
}

///|
test "uniform defensive visible factory cardinality and uniform height errors are atomic" {
  for mode in [0, 1] {
    let calls = Ref(0)
    let root = ul_custom(range => {
      calls.val = calls.val + 1
      if calls.val < 3 {
        ul_rows(range, 26)
      } else if mode == 0 {
        Ok([])
      } else {
        ul_rows(range, 31)
      }
    })
    let requested = root.request_layout(ul_size(420, 420)).unwrap()
    let result = requested.prepaint()
    if mode == 0 {
      assert_true(
        result
        is Err(
          @element.UniformListFailure(@element.InvalidFactoryLength(12, 0))
        ),
      )
    } else {
      assert_true(
        result
        is Err(@element.UniformListFailure(@element.NonUniformVisibleRow(0))),
      )
    }
    assert_eq(calls.val, 3)
  }
}

///|
test "uniform defensive ordinary eager scroll and dominant axis contracts stay unchanged" {
  let mut ordinary = @element.Element::root(1, ul_column()).with_scroll_offset(
    ul_point(0, 0),
  )
  for index = 0; index < 50; index = index + 1 {
    ordinary = ordinary.with_child(
      @element.Element::new(ul_item(ul_id(index), 26, 220)),
    )
  }
  let frame = ordinary
    .request_layout(ul_size(220, 300))
    .unwrap()
    .prepaint()
    .unwrap()
  let tree = frame.tree()
  assert_eq(tree.nodes().length(), 51)
  assert_true(tree.node(ul_id(49)) is Some(_))
  assert_true(tree.uniform_list(1) is None)
  assert_true(
    tree.scroll_viewport(1).unwrap().max_offset() == ul_point(0, 1000),
  )
  assert_true(
    tree.scroll_wheel(ul_point(100, 100), 25, 0).unwrap()[0].offset() ==
    ul_point(0, 0),
  )
  assert_true(
    tree.scroll_wheel(ul_point(100, 100), 40, 3).unwrap()[0].offset() ==
    ul_point(0, 0),
  )
  assert_true(
    tree.scroll_wheel(ul_point(100, 100), 2, 4).unwrap()[0].offset() ==
    ul_point(0, 4),
  )
  assert_true(
    tree.with_layout_bounds(frame)
    is Err(@element.ScrollLayoutBoundsUnsupported),
  )
}

///|
test "uniform defensive full size viewport uses ordinary parent allocation" {
  let item = @layout.FlexItem::new(
      2,
      @layout.Dimension::percent(1).unwrap(),
      @layout.Dimension::percent(1).unwrap(),
      ul_size(0, 0),
    )
    .with_flex(0, 0)
    .unwrap()
  let calls = []
  let list = @element.UniformList::new(
      item,
      50,
      @element.UniformListIdSpace::new(100, 4).unwrap(),
      range => {
        calls.push((range.start(), range.end()))
        ul_rows(range, 26)
      },
    )
    .unwrap()
    .with_scroll_offset(25)
    .unwrap()
    .into_element()
  let root = @element.Element::root(1, ul_column()).with_child(list)
  let frame = root
    .request_layout(ul_size(220, 300))
    .unwrap()
    .prepaint()
    .unwrap()
  assert_true(
    frame.tree().uniform_list(2).unwrap().bounds() == ul_rect(0, 0, 220, 300),
  )
  assert_true(calls == [(0, 1), (0, 1), (0, 13)])
  assert_true(
    frame.tree().node(100).unwrap().bounds() == ul_rect(0, -25, 220, 26),
  )
  let resized = root
    .request_layout(ul_size(260, 350))
    .unwrap()
    .prepaint()
    .unwrap()
  assert_true(
    resized.tree().uniform_list(2).unwrap().bounds() == ul_rect(0, 0, 260, 350),
  )
  assert_true(resized.tree().uniform_list(2).unwrap().max_offset() == 950)
  assert_true(
    resized.tree().node(100).unwrap().bounds() == ul_rect(0, -25, 260, 26),
  )
}

///|
test "uniform defensive fractional row heights preserve exact half open ranges" {
  // Neither fractional height nor zero viewport occurs in the actual Rust
  // corpus. This asserts only the safe raw logical-pixel MoonBit contract.
  for
    (offset, first, limit) in [
      (0.0, 0, 2),
      (26.25, 1, 3),
      (26.5, 1, 4),
      (1260.0, 48, 50),
    ] {
    let calls = []
    let tree = ul_frame(50, 26.25, 52.5, offset, calls).tree()
    let list = tree.uniform_list(2).unwrap()
    assert_true(list.measured_item_size() == Some(ul_size(220, 26.25)))
    assert_true(list.content_size() == ul_size(220, 1312.5))
    assert_true(list.max_offset() == 1260)
    assert_true(calls == [(0, 1), (0, 1), (first, limit)])
    assert_true(
      tree.node(ul_id(first)).unwrap().bounds() ==
      ul_rect(40, 50 + first.to_double() * 26.25 - offset, 220, 26.25),
    )
  }
}

///|
test "uniform defensive list background and disabled pointer state remain real elements" {
  let color = @primitives.Color::rgba(12, 34, 56, 255).unwrap()
  let list = ul_list(50, 26, 300, 25, [])
    .into_element()
    .with_background(Some(color))
    .with_pointer_events(false)
  let frame = ul_root(list)
    .request_layout(ul_size(420, 420))
    .unwrap()
    .prepaint()
    .unwrap()
  let tree = frame.tree()
  let commands = frame.paint().commands()
  assert_eq(commands.length(), 3)
  assert_true(commands[0].kind() == @scene.Quad && commands[0].id() == 2)
  assert_true(commands[0].bounds() == Some(ul_rect(40, 50, 220, 300)))
  assert_true(commands[0].color() == Some(color))
  assert_true(
    commands[1].kind() == @scene.ClipPush &&
    commands[2].kind() == @scene.ClipPop,
  )
  assert_true(tree.scroll_wheel(ul_point(100, 100), 0, 25) is Ok([]))
  let session = @element.UniformListClickSession::new(2)
  assert_true(session.dispatch(tree, ul_down(100, 100)) is @element.Unchanged)
  assert_true(session.dispatch(tree, ul_up(100, 100)) is @element.Unchanged)
}

///|
test "uniform observed integer fixture keeps geometry at explicit one and two device scales" {
  for scale in [1.0, 2.0] {
    let calls = []
    let frame = ul_root(ul_list(50, 26, 300, 25, calls).into_element())
      .request_layout_with_device_scale(ul_size(420, 420), scale)
      .unwrap()
      .prepaint()
      .unwrap()
    let tree = frame.tree()
    assert_true(calls == [(0, 1), (0, 1), (0, 13)])
    assert_true(
      tree.uniform_list(2).unwrap().measured_item_size() ==
      Some(ul_size(220, 26)),
    )
    assert_true(tree.node(100).unwrap().bounds() == ul_rect(40, 25, 220, 26))
    assert_true(
      tree.node(ul_id(12)).unwrap().bounds() == ul_rect(40, 337, 220, 26),
    )
    assert_true(frame.paint_snapshot(scale) is Ok(_))
  }
}

///|
test "uniform defensive percent descendants and constrained row roots reject explicitly" {
  let percentage_child = @layout.FlexItem::new(
    101,
    @layout.Dimension::percent(0.5).unwrap(),
    @layout.Dimension::auto(),
    ul_size(220, 26),
  )
  let root = ul_custom(_ => {
    Ok([
      @element.Element::new(ul_auto(100, 0, 0))
      .with_children_style(ul_column())
      .with_child(@element.Element::new(percentage_child)),
    ])
  })
  assert_true(
    root.request_layout(ul_size(420, 420))
    is Err(@element.UniformListFailure(@element.UnsupportedRowShape(0))),
  )
  for
    item in [
      ul_auto(100, 220, 26).with_flex(1, 0).unwrap(),
      ul_auto(100, 220, 26).with_main_limits(1, None).unwrap(),
      ul_auto(100, 220, 26).with_main_limits(0, Some(100)).unwrap(),
      ul_auto(100, 220, 26).with_cross_limits(1, None).unwrap(),
      ul_auto(100, 220, 26).with_cross_limits(0, Some(100)).unwrap(),
    ] {
    let root = ul_custom(_ => Ok([@element.Element::new(item)]))
    assert_true(
      root.request_layout(ul_size(420, 420))
      is Err(@element.UniformListFailure(@element.UnsupportedRowShape(0))),
    )
  }
}

///|
test "uniform defensive reordered visible roots cannot rebind stable row identity" {
  let calls = Ref(0)
  let root = ul_custom(range => {
    calls.val += 1
    let rows = ul_rows(range, 26).unwrap()
    if calls.val == 3 {
      let first = rows[0]
      rows[0] = rows[1]
      rows[1] = first
    }
    Ok(rows)
  })
  let requested = root.request_layout(ul_size(420, 420)).unwrap()
  assert_true(
    requested.prepaint()
    is Err(@element.UniformListFailure(@element.InvalidRowRoot(0, 104))),
  )
  assert_eq(calls.val, 3)
}

// Defensive Double boundary regressions from independent review. These exact
// tiny fractional viewports are outside the retained upstream input corpus.

///|
test "uniform fractional endpoint stays inside the reserved row namespace" {
  let h = 27.142077840697404
  let viewport = 1.4068746168049984e-14
  let position = 81.4262335220922
  let calls : Array[(Int32, Int32)] = []
  let list = @element.UniformList::new(
      ul_item(2, viewport, 220),
      3,
      @element.UniformListIdSpace::new(100, 4).unwrap(),
      range => {
        calls.push((range.start(), range.end()))
        ul_rows(range, h)
      },
    )
    .unwrap()
    .with_scroll_offset(position)
    .unwrap()
    .into_element()
  let frame = @element.Element::root(1, ul_column())
    .with_child(list)
    .request_layout(ul_size(220, 300))
    .unwrap()
    .prepaint()
    .unwrap()
  let observed = frame.tree().uniform_list(2).unwrap()
  debug_inspect(calls, content="[(0, 1), (0, 1), (2, 3)]")
  assert_true(observed.visible_range().end() <= observed.item_count())
  assert_true(observed.visible_range().id(3, 0) is Err(_))
  assert_true(frame.tree().node(112) is None)
}

///|
test "uniform Int maximum endpoint is clamped before integer conversion" {
  let calls : Array[(Int32, Int32)] = []
  let list = @element.UniformList::new(
      ul_item(2, 7.5531005859375e-06, 220),
      2147483647,
      @element.UniformListIdSpace::new(100, 4).unwrap(),
      range => {
        calls.push((range.start(), range.end()))
        if range.end() < range.start() || range.start() < 0 {
          Err(@element.FactoryFailure("range conversion escaped bounds"))
        } else {
          ul_rows(range, 23.04131646983303)
        }
      },
    )
    .unwrap()
    .with_scroll_offset(49480850324.3182)
    .unwrap()
    .into_element()
  let result = @element.Element::root(1, ul_column())
    .with_child(list)
    .request_layout(ul_size(220, 300))
    .unwrap()
    .prepaint()
  debug_inspect(calls, content="[(0, 1), (0, 1), (2147483646, 2147483647)]")
  assert_true(result is Ok(_))
}
