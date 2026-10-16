///|
fn ul_size(w : Double, h : Double) -> @primitives.Size {
  @primitives.Size::new(w, h).unwrap()
}

///|
fn ul_auto(id : UInt64, w : Double, h : Double) -> Element {
  Element::new(
    @layout.FlexItem::new(
      id,
      @layout.Dimension::auto(),
      @layout.Dimension::auto(),
      ul_size(w, h),
    ),
  )
}

///|
fn ul_fixed(id : UInt64, w : Double, h : Double) -> @layout.FlexItem {
  @layout.FlexItem::new(
    id,
    @layout.Dimension::points(h).unwrap(),
    @layout.Dimension::points(w).unwrap(),
    ul_size(w, h),
  )
  .with_flex(0.0, 0.0)
  .unwrap()
}

///|
fn ul_column() -> @layout.FlexTreeStyle {
  @layout.FlexTreeStyle::new(@layout.FlowDirection::column())
}

///|
test "uniform list combined ordinary and row depth is bounded before publication" {
  let list = UniformList::new(
      ul_fixed(2, 220, 300),
      1,
      UniformListIdSpace::new(1000, 100).unwrap(),
      range => {
        let mut row = ul_auto(range.id(0, 63).unwrap(), 42, 26)
        for slot = 62; slot >= 0; slot = slot - 1 {
          row = ul_auto(range.id(0, slot.to_uint64()).unwrap(), 0, 0)
            .with_children_style(ul_column())
            .with_child(row)
        }
        Ok([row])
      },
    )
    .unwrap()
    .into_element()
  let root = Element::root(1, ul_column()).with_child(list)
  assert_true(
    root.request_layout(ul_size(220, 300)).unwrap().prepaint()
    is Err(TreeTooDeep),
  )
}

///|
test "uniform list validates static namespace before calling any factory" {
  let calls = Ref(0)
  let list = UniformList::new(
      ul_fixed(2, 220, 300),
      1000000,
      UniformListIdSpace::new(100, 2).unwrap(),
      _ => {
        calls.val += 1
        Err(FactoryFailure("must not run"))
      },
    )
    .unwrap()
    .into_element()
  let root = Element::root(1, ul_column())
    .with_child(list)
    .with_child(Element::new(ul_fixed(1900000, 1, 1)))
  assert_true(
    root.request_layout(ul_size(220, 300))
    is Err(UniformListFailure(ReservedIdCollision(1900000))),
  )
  assert_true(calls.val == 0)
}

///|
test "uniform list zero viewport and tiny heights stay bounded without fabricated prototype" {
  let calls : Array[(Int32, Int32)] = []
  let list = UniformList::new(
      ul_fixed(2, 220, 0),
      50,
      UniformListIdSpace::new(100, 1).unwrap(),
      range => {
        calls.push((range.start(), range.end()))
        let rows : Array[Element] = []
        for index = range.start(); index < range.end(); index = index + 1 {
          rows.push(ul_auto(range.id(index, 0).unwrap(), 42, 0.001))
        }
        Ok(rows)
      },
    )
    .unwrap()
    .with_scroll_offset(100)
    .unwrap()
    .into_element()
  let frame = Element::root(1, ul_column())
    .with_child(list)
    .request_layout(ul_size(220, 300))
    .unwrap()
    .prepaint()
    .unwrap()
  let live = frame.tree.uniform_list(2).unwrap()
  assert_true(live.visible_range().start() == 50)
  assert_true(live.visible_range().end() == 50)
  assert_true(live.offset() == 0.05)
  assert_true(calls == [(0, 1), (0, 1), (50, 50)])
  assert_true(frame.tree.nodes().length() == 2)
}

///|
test "uniform list clipped ancestor keeps own virtual extent independent of ordinary siblings" {
  let list = UniformList::new(
      ul_fixed(2, 220, 300),
      50,
      UniformListIdSpace::new(100, 1).unwrap(),
      range => {
        let rows : Array[Element] = []
        for index = range.start(); index < range.end(); index = index + 1 {
          rows.push(ul_auto(range.id(index, 0).unwrap(), 42, 26))
        }
        Ok(rows)
      },
    )
    .unwrap()
    .with_scroll_offset(25)
    .unwrap()
    .into_element()
  let root = Element::root(1, ul_column())
    .with_scroll_offset(scroll_point(0, 20))
    .with_child(list)
    .with_child(Element::new(ul_fixed(3, 220, 100)))
  let frame = root
    .request_layout(ul_size(220, 350))
    .unwrap()
    .prepaint()
    .unwrap()
  assert_true(frame.tree.scroll_viewport(1).unwrap().max_offset().y() == 50)
  assert_true(frame.tree.uniform_list(2).unwrap().bounds().top() == -20)
  assert_true(frame.tree.node(100).unwrap().bounds().top() == -45)
  assert_true(frame.tree.node(3).unwrap().bounds().top() == 280)
  assert_true(frame.tree.hit_test(scroll_point(20, 0)) == Some(101))
  assert_true(frame.tree.hit_test(scroll_point(20, 349.99)) == Some(3))
}

///|
test "uniform list reserved IDs safely include UInt64 maximum" {
  let max : UInt64 = 0xffff_ffff_ffff_ffff
  let list = UniformList::new(
      ul_fixed(2, 220, 300),
      1,
      UniformListIdSpace::new(max, 1).unwrap(),
      range => Ok([ul_auto(range.id(0, 0).unwrap(), 42, 26)]),
    )
    .unwrap()
    .into_element()
  let frame = Element::root(1, ul_column())
    .with_child(list)
    .request_layout(ul_size(220, 300))
    .unwrap()
    .prepaint()
    .unwrap()
  assert_true(frame.tree.node(max) is Some(_))
  assert_true(
    UniformList::new(
      ul_fixed(2, 220, 300),
      2,
      UniformListIdSpace::new(max, 1).unwrap(),
      _ => Ok([]),
    )
    is Err(InvalidIdSpace),
  )
}

///|
test "uniform list invalid device scale rejects before factory side effects" {
  let calls = Ref(0)
  let list = UniformList::new(
      ul_fixed(2, 220, 300),
      1,
      UniformListIdSpace::new(100, 1).unwrap(),
      range => {
        calls.val += 1
        Ok([ul_auto(range.id(0, 0).unwrap(), 42, 26)])
      },
    )
    .unwrap()
    .into_element()
  let root = Element::root(1, ul_column()).with_child(list)
  assert_true(
    root.request_layout_with_device_scale(ul_size(220, 300), 0)
    is Err(LayoutFailure(_)),
  )
  assert_true(
    root.request_layout_with_device_scale(ul_size(220, 300), 1.0 / 0.0)
    is Err(LayoutFailure(_)),
  )
  assert_true(calls.val == 0)
}

///|
test "uniform factory rejects out of namespace ranges before user callbacks" {
  let calls = Ref(0)
  let ids = UniformListIdSpace::new(100, 4).unwrap()
  let list = UniformList::new(ul_fixed(2, 220, 300), 3, ids, _ => {
    calls.val += 1
    Ok([])
  }).unwrap()
  for (first, limit) in [(-1, 0), (4, 4), (2, 1), (2, 4)] {
    assert_true(
      uniform_factory(list, { first, limit, ids, })
      is Err(UniformListFailure(InvalidRangeIndex(_))),
    )
  }
  assert_true(calls.val == 0)
}
