///|
fn query_size(width : Double, height : Double) -> @primitives.Size {
  @primitives.Size::new(width, height).unwrap()
}

///|
fn query_rect(
  x : Double,
  y : Double,
  width : Double,
  height : Double,
) -> @primitives.Rect {
  @primitives.Rect::new(x, y, width, height).unwrap()
}

///|
fn query_style() -> @layout.FlexTreeStyle {
  @layout.FlexTreeStyle::new(@layout.FlowDirection::row())
}

///|
fn query_flex(id : UInt64, width : Double, height : Double) -> Element {
  Element::new(
    @layout.FlexItem::new(
      id,
      @layout.Dimension::points(width).unwrap(),
      @layout.Dimension::points(height).unwrap(),
      query_size(0.0, 0.0),
    ),
  )
}

///|
fn query_grid(id : UInt64) -> Element {
  Element::grid_item(
    @layout.GridItem::new(
      id,
      @layout.Dimension::auto(),
      @layout.Dimension::auto(),
    ),
  )
}

///|
test "query remains a leaf until prepaint consumes its one-shot request lease" {
  let calls = Ref(0)
  let observed : Ref[@primitives.Size?] = Ref(None)
  let root = Element::container_query_root(1, fn(size) {
    calls.val += 1
    observed.val = Some(size)
    Ok(
      Element::grid_root(2, @layout.GridTreeStyle::new(2, 1).unwrap())
      .with_child(query_grid(3))
      .with_child(query_grid(4)),
    )
  })
  let request = root.request_layout(query_size(100.0, 30.0)).unwrap()
  assert_eq(calls.val, 0)
  assert_eq(request.layout.items().length(), 0)
  let first = request.prepaint().unwrap()
  assert_eq(calls.val, 1)
  assert_true(observed.val == Some(query_size(100.0, 30.0)))
  assert_eq(first.tree().nodes().length(), 4)
  assert_true(
    first.tree().node(4).unwrap().bounds() == query_rect(50.0, 0.0, 50.0, 30.0),
  )
  assert_true(request.prepaint() is Err(AlreadyPrepainted))
  assert_eq(calls.val, 1)
  root.request_layout(query_size(80.0, 20.0)).unwrap().prepaint().unwrap()
  |> ignore
  assert_eq(calls.val, 2)
  assert_true(
    first.tree().node(4).unwrap().bounds() == query_rect(50.0, 0.0, 50.0, 30.0),
  )
}

///|
test "query callback uses allocated size and nonzero origin rather than viewport" {
  let observed : Ref[@primitives.Size?] = Ref(None)
  let query = query_flex(3, 40.0, 25.0).with_container_query(fn(size) {
    observed.val = Some(size)
    Ok(
      Element::grid_root(4, @layout.GridTreeStyle::new(2, 1).unwrap())
      .with_child(query_grid(5))
      .with_child(query_grid(6)),
    )
  })
  let style = query_style().with_insets(
    @layout.Insets::new(7.0, 0.0, 0.0, 11.0).unwrap(),
    @layout.Insets::zero(),
  )
  let request = Element::root(1, style)
    .with_child(query_flex(2, 20.0, 25.0))
    .with_child(query)
    .request_layout(query_size(200.0, 100.0))
    .unwrap()
  assert_true(observed.val is None)
  let prepainted = request.prepaint().unwrap()
  assert_true(observed.val == Some(query_size(40.0, 25.0)))
  assert_true(
    prepainted.tree().node(3).unwrap().bounds() ==
    query_rect(31.0, 7.0, 40.0, 25.0),
  )
  assert_true(
    prepainted.tree().node(4).unwrap().bounds() ==
    query_rect(31.0, 7.0, 40.0, 25.0),
  )
  assert_true(
    prepainted.tree().node(6).unwrap().bounds() ==
    query_rect(51.0, 7.0, 20.0, 25.0),
  )
}

///|
test "tiny and huge returned query roots cannot change outer measurement" {
  for generated_size in [query_size(8.0, 7.0), query_size(900.0, 700.0)] {
    let root = Element::root(1, query_style())
      .with_child(
        query_flex(2, 115.0, 120.0).with_container_query(fn(_) {
          Ok(
            Element::root(3, query_style()).with_query_root_size(generated_size),
          )
        }),
      )
      .with_child(query_flex(4, 20.0, 10.0))
    let requested = root.request_layout(query_size(200.0, 150.0)).unwrap()
    assert_true(
      requested.layout.items()[0].bounds().size() == query_size(115.0, 120.0),
    )
    let painted = requested.prepaint().unwrap()
    assert_true(
      painted.tree().node(2).unwrap().bounds().size() ==
      query_size(115.0, 120.0),
    )
    assert_true(
      painted.tree().node(3).unwrap().bounds().size() == generated_size,
    )
    assert_eq(painted.tree().node(4).unwrap().bounds().left(), 115.0)
    assert_eq(painted.overflow(), generated_size.width() > 115.0)
  }
}

///|
test "nested query callbacks run once each with cumulative origin and depth" {
  let outer = Ref(0)
  let inner = Ref(0)
  let root = Element::root(1, query_style())
    .with_child(query_flex(2, 12.0, 20.0))
    .with_child(
      query_flex(3, 60.0, 20.0).with_container_query(fn(_) {
        outer.val += 1
        Ok(
          Element::grid_root(4, @layout.GridTreeStyle::new(2, 1).unwrap())
          .with_child(query_grid(5))
          .with_child(
            query_grid(6).with_container_query(fn(size) {
              inner.val += 1
              Ok(
                Element::root(7, query_style())
                .with_query_root_size(size)
                .with_child(query_flex(8, 5.0, 6.0)),
              )
            }),
          ),
        )
      }),
    )
  let request = root.request_layout(query_size(100.0, 40.0)).unwrap()
  assert_eq(outer.val, 0)
  assert_eq(inner.val, 0)
  let tree = request.prepaint().unwrap().tree()
  assert_eq(outer.val, 1)
  assert_eq(inner.val, 1)
  assert_true(tree.node(8).unwrap().bounds() == query_rect(42.0, 0.0, 5.0, 6.0))
  let ids = tree.nodes().map(fn(node) { node.id() })
  assert_true(ids == [1, 2, 3, 4, 5, 6, 7, 8])
  assert_true(tree.node(7).unwrap().parent() == Some(6))
}

///|
test "query lease is consumed before reentrant callbacks and after callback failure" {
  let saved : Ref[RequestedLayout?] = Ref(None)
  let reentrant = Ref(false)
  let root = Element::container_query_root(1, fn(_) {
    reentrant.val = saved.val.unwrap().prepaint() is Err(AlreadyPrepainted)
    Ok(Element::root(2, query_style()))
  })
  let request = root.request_layout(query_size(10.0, 10.0)).unwrap()
  saved.val = Some(request)
  request.prepaint().unwrap() |> ignore
  assert_true(reentrant.val)
  let calls = Ref(0)
  let failing = Element::container_query_root(1, fn(_) {
      calls.val += 1
      Err(GeometryFailure)
    })
    .request_layout(query_size(10.0, 10.0))
    .unwrap()
  assert_true(failing.prepaint() is Err(GeometryFailure))
  assert_true(failing.prepaint() is Err(AlreadyPrepainted))
  assert_eq(calls.val, 1)
}

///|
test "generated identities are reserved globally including later static siblings" {
  let root = Element::root(1, query_style())
    .with_child(
      query_flex(2, 10.0, 10.0).with_container_query(fn(_) {
        Ok(Element::root(3, query_style()))
      }),
    )
    .with_child(query_flex(3, 10.0, 10.0))
  let request = root.request_layout(query_size(30.0, 10.0)).unwrap()
  assert_true(request.prepaint() is Err(DuplicateId))
  assert_true(request.prepaint() is Err(AlreadyPrepainted))
  let duplicate = Element::container_query_root(1, fn(_) {
    Ok(
      Element::root(2, query_style())
      .with_child(query_flex(3, 1.0, 1.0))
      .with_child(query_flex(3, 1.0, 1.0)),
    )
  })
  assert_true(
    duplicate.request_layout(query_size(10.0, 10.0)).unwrap().prepaint()
    is Err(DuplicateId),
  )
  let invalid = Element::container_query_root(1, fn(_) {
    Ok(query_flex(2, 1.0, 1.0))
  })
  assert_true(
    invalid.request_layout(query_size(10.0, 10.0)).unwrap().prepaint()
    is Err(RootRequired),
  )
  let child_root = Element::container_query_root(1, fn(_) {
    Ok(
      Element::root(2, query_style()).with_child(
        Element::root(3, query_style()),
      ),
    )
  })
  assert_true(
    child_root.request_layout(query_size(10.0, 10.0)).unwrap().prepaint()
    is Err(InvalidChildRoot),
  )
}

///|
fn query_chain(id : UInt64, remaining : Int32, calls : Ref[Int32]) -> Element {
  Element::container_query_root(id, fn(_) {
    calls.val += 1
    Ok(
      if remaining == 0 {
        Element::root(id + 1, query_style())
      } else {
        query_chain(id + 1, remaining - 1, calls)
      },
    )
  })
}

///|
test "nested query boundaries cannot reset the global depth budget" {
  let calls = Ref(0)
  let request = query_chain(1, 80, calls)
    .request_layout(query_size(20.0, 20.0))
    .unwrap()
  assert_true(request.prepaint() is Err(TreeTooDeep))
  assert_eq(calls.val, MAX_ELEMENT_DEPTH)
  assert_true(request.prepaint() is Err(AlreadyPrepainted))
  let valid = query_chain(1000, MAX_ELEMENT_DEPTH - 1, Ref(0))
    .request_layout(query_size(20.0, 20.0))
    .unwrap()
    .prepaint()
    .unwrap()
  assert_eq(valid.tree().nodes().length(), MAX_ELEMENT_DEPTH + 1)
}

///|
test "queries reject scroll ancestry descendant scroll and uniform-list composition" {
  let offset = @primitives.Point::new(0.0, 0.0).unwrap()
  let query = query_flex(2, 10.0, 10.0).with_container_query(fn(_) {
    Ok(Element::root(3, query_style()))
  })
  let scroll_root = Element::root(1, query_style())
    .with_scroll_offset(offset)
    .with_child(query)
  assert_true(
    scroll_root.request_layout(query_size(20.0, 20.0))
    is Err(UnsupportedQueryComposition),
  )
  let generated_scroll = Element::container_query_root(1, fn(_) {
    Ok(Element::root(2, query_style()).with_scroll_offset(offset))
  })
  assert_true(
    generated_scroll.request_layout(query_size(20.0, 20.0)).unwrap().prepaint()
    is Err(UnsupportedQueryComposition),
  )
  let list = UniformList::new(
      @layout.FlexItem::new(
        4,
        @layout.Dimension::points(10.0).unwrap(),
        @layout.Dimension::points(10.0).unwrap(),
        query_size(0.0, 0.0),
      ),
      0,
      UniformListIdSpace::new(100, 10).unwrap(),
      fn(_) { Ok([]) },
    )
    .unwrap()
    .into_element()
  assert_true(
    Element::root(1, query_style())
    .with_child(query)
    .with_child(list)
    .request_layout(query_size(20.0, 20.0))
    is Err(UnsupportedQueryComposition),
  )
  assert_true(
    Element::grid_root(1, @layout.GridTreeStyle::new(1, 1).unwrap())
    .with_scroll_offset(offset)
    .request_layout(query_size(20.0, 20.0))
    is Err(UnsupportedGridScroll),
  )
}

///|
test "grid and query row factories fail before uniform intrinsic measurement" {
  for kind in [0, 1] {
    let calls = Ref(0)
    let list = UniformList::new(
      @layout.FlexItem::new(
        2,
        @layout.Dimension::points(10.0).unwrap(),
        @layout.Dimension::points(10.0).unwrap(),
        query_size(0.0, 0.0),
      ),
      1,
      UniformListIdSpace::new(100, 10).unwrap(),
      fn(_) {
        let row = Element::new(
          @layout.FlexItem::new(
            100,
            @layout.Dimension::auto(),
            @layout.Dimension::auto(),
            query_size(5.0, 5.0),
          ),
        )
        Ok([
          if kind == 0 {
            row.with_grid_children_style(
              @layout.GridTreeStyle::new(1, 1).unwrap(),
            )
          } else {
            row.with_container_query(fn(_) {
              calls.val += 1
              Ok(Element::root(101, query_style()))
            })
          },
        ])
      },
    ).unwrap()
    assert_true(
      Element::root(1, query_style())
      .with_child(list.into_element())
      .request_layout(query_size(20.0, 20.0))
      is Err(UniformListFailure(UnsupportedRowShape(0))),
    )
    assert_eq(calls.val, 0)
  }
}

///|
test "query and grid metadata survive every ordinary builder chain" {
  let calls = Ref(0)
  let color = @primitives.Color::rgba(10, 20, 30, 255).unwrap()
  let root = Element::grid_root(1, @layout.GridTreeStyle::new(2, 1).unwrap())
    .with_background(Some(color))
    .with_focusable(true)
    .with_pointer_events(true)
    .with_tab_index(2)
    .with_tab_group_index(Some(3))
    .with_tab_stop(true)
    .with_child(
      query_grid(2)
      .with_background(Some(color))
      .with_focusable(true)
      .with_pointer_events(true)
      .with_tab_index(7)
      .with_tab_group_index(Some(4))
      .with_tab_stop(true)
      .with_container_query(fn(_) {
        calls.val += 1
        Ok(
          Element::root(3, query_style())
          .with_query_root_size(query_size(8.0, 7.0))
          .with_background(Some(color))
          .with_focusable(true)
          .with_tab_index(8)
          .with_tab_group_index(Some(5))
          .with_tab_stop(true)
          .with_pointer_events(true)
          .with_children_style(query_style()),
        )
      }),
    )
    .with_child(
      query_grid(4)
      .with_children_style(query_style())
      .with_child(query_flex(5, 4.0, 5.0)),
    )
  let prepainted = root
    .request_layout(query_size(100.0, 30.0))
    .unwrap()
    .prepaint()
    .unwrap()
  assert_eq(calls.val, 1)
  assert_true(
    prepainted.tree().node(3).unwrap().bounds().size() == query_size(8.0, 7.0),
  )
  assert_true(
    prepainted.tree().node(4).unwrap().bounds() ==
    query_rect(50.0, 0.0, 50.0, 30.0),
  )
  assert_true(
    prepainted.tree().node(5).unwrap().bounds() ==
    query_rect(50.0, 0.0, 4.0, 5.0),
  )
  assert_eq(prepainted.tree().node(2).unwrap().tab_index(), 7)
  assert_eq(prepainted.paint().command_count(), 3)
  assert_true(
    Element::root(9, query_style())
    .with_query_root_size(query_size(4.0, 5.0))
    .request_layout(query_size(10.0, 10.0))
    is Err(InvalidQueryShape),
  )
}

///|
test "mixed flex inside grid and definite grid inside flex retain sizing" {
  let nested = query_flex(2, 80.0, 30.0)
    .with_grid_children_style(@layout.GridTreeStyle::new(2, 1).unwrap())
    .with_child(
      query_grid(3)
      .with_children_style(query_style())
      .with_child(query_flex(4, 10.0, 7.0)),
    )
    .with_child(query_grid(5))
  let painted = Element::root(1, query_style())
    .with_child(nested)
    .request_layout(query_size(100.0, 40.0))
    .unwrap()
    .prepaint()
    .unwrap()
  assert_true(
    painted.tree().node(4).unwrap().bounds() == query_rect(0.0, 0.0, 10.0, 7.0),
  )
  assert_true(
    painted.tree().node(5).unwrap().bounds() ==
    query_rect(40.0, 0.0, 40.0, 30.0),
  )
  let auto = Element::new(
    @layout.FlexItem::new(
      2,
      @layout.Dimension::auto(),
      @layout.Dimension::points(30.0).unwrap(),
      query_size(0.0, 0.0),
    ),
  ).with_grid_children_style(@layout.GridTreeStyle::new(1, 1).unwrap())
  assert_true(
    Element::root(1, query_style())
    .with_child(auto)
    .request_layout(query_size(100.0, 40.0))
    is Err(LayoutFailure(@layout.UnsupportedIntrinsicGrid)),
  )
}

///|
test "grid gaps hit container and fixed overflow stays hittable without clipping" {
  let root = Element::grid_root(
      1,
      @layout.GridTreeStyle::new(2, 1).unwrap().with_gap_x(10.0).unwrap(),
    )
    .with_child(
      Element::grid_item(
        @layout.GridItem::new(
          2,
          @layout.Dimension::auto(),
          @layout.Dimension::points(224.0).unwrap(),
        ),
      ),
    )
    .with_child(query_grid(3))
  let request = root.request_layout(query_size(110.0, 30.0)).unwrap()
  let tree = request.prepaint().unwrap().tree()
  assert_true(
    tree.hit_test(@primitives.Point::new(55.0, 10.0).unwrap()) == Some(1),
  )
  assert_true(
    tree.hit_test(@primitives.Point::new(20.0, 200.0).unwrap()) == Some(2),
  )
  assert_true(request.prepaint() is Ok(_))
}

///|
test "query input follows device assigned bounds and generated edges use actual origin" {
  for scale in [1.0, 1.25, 2.0] {
    let observed : Ref[@primitives.Size?] = Ref(None)
    let first = Element::new(
      @layout.FlexItem::new(
        2,
        @layout.Dimension::percent(1.0 / 3.0).unwrap(),
        @layout.Dimension::points(10.0).unwrap(),
        query_size(0.0, 0.0),
      ),
    )
    let second = Element::new(
      @layout.FlexItem::new(
        3,
        @layout.Dimension::percent(2.0 / 3.0).unwrap(),
        @layout.Dimension::points(10.0).unwrap(),
        query_size(0.0, 0.0),
      ),
    ).with_container_query(fn(size) {
      observed.val = Some(size)
      Ok(
        Element::grid_root(4, @layout.GridTreeStyle::new(3, 1).unwrap())
        .with_child(query_grid(5))
        .with_child(query_grid(6))
        .with_child(query_grid(7)),
      )
    })
    let request = Element::root(1, query_style())
      .with_child(first)
      .with_child(second)
      .request_layout_with_device_scale(query_size(100.0, 10.0), scale)
      .unwrap()
    let assigned = request.layout.items()[1].bounds()
    let tree = request.prepaint().unwrap().tree()
    assert_true(observed.val == Some(assigned.size()))
    assert_eq(tree.node(4).unwrap().bounds().left(), assigned.left())
    assert_eq(tree.node(5).unwrap().bounds().left(), assigned.left())
    assert_eq(tree.node(7).unwrap().bounds().right(), assigned.right())
  }
}

///|
test "query bounds refresh retains focus lineage only with same topology and viewport" {
  let make = fn(width) {
    Element::container_query_root(1, fn(_) {
      Ok(
        Element::root(2, query_style()).with_child(
          query_flex(3, width, 10.0).with_focusable(true),
        ),
      )
    })
  }
  let first = make(20.0)
    .request_layout(query_size(100.0, 30.0))
    .unwrap()
    .prepaint()
    .unwrap()
  let retained = first.tree().with_focus(3).unwrap()
  let owner = retained.focus_owner().unwrap()
  let fresh = make(40.0)
    .request_layout(query_size(100.0, 30.0))
    .unwrap()
    .prepaint()
    .unwrap()
  let refreshed = retained.with_layout_bounds(fresh).unwrap()
  assert_true(refreshed.focus_owner() == Some(owner))
  assert_eq(refreshed.node(3).unwrap().bounds().size().width(), 40.0)
  assert_eq(retained.node(3).unwrap().bounds().size().width(), 20.0)
  assert_true(fresh.tree().with_focus_owner(owner) is Err(UnknownElement))
  let resized = make(40.0)
    .request_layout(query_size(120.0, 30.0))
    .unwrap()
    .prepaint()
    .unwrap()
  assert_true(retained.with_layout_bounds(resized) is Err(LayoutBoundsMismatch))
}

///|
test "explicit query-root dimensions snap before descendant track resolution" {
  let root = Element::container_query_root(1, fn(_) {
    Ok(
      Element::grid_root(2, @layout.GridTreeStyle::new(3, 1).unwrap())
      .with_query_root_size(query_size(8.49, 10.0))
      .with_child(query_grid(3))
      .with_child(query_grid(4))
      .with_child(query_grid(5)),
    )
  })
  let tree = root
    .request_layout_with_device_scale(query_size(20.0, 20.0), 1.0)
    .unwrap()
    .prepaint()
    .unwrap()
    .tree()
  assert_eq(tree.node(2).unwrap().bounds().size().width(), 8.0)
  assert_eq(tree.node(4).unwrap().bounds().right(), 5.0)
  assert_eq(tree.node(5).unwrap().bounds().left(), 5.0)
}

///|
test "scroll builders retain grid metadata and unrelated ordinary scroll remains supported" {
  let zero = @primitives.Point::new(0.0, 0.0).unwrap()
  let grid = query_flex(2, 40.0, 20.0)
    .with_grid_children_style(@layout.GridTreeStyle::new(2, 1).unwrap())
    .with_child(query_grid(3))
    .with_child(query_grid(4))
  let scroll = query_flex(5, 60.0, 20.0)
    .with_children_style(query_style())
    .with_child(grid)
    .with_scroll_offset(zero)
  let root = Element::root(1, query_style()).with_child(scroll)
  let tree = root
    .request_layout(query_size(100.0, 40.0))
    .unwrap()
    .prepaint()
    .unwrap()
    .tree()
  assert_true(tree.scroll_viewport(5) is Some(_))
  assert_eq(tree.node(4).unwrap().bounds().left(), 20.0)
  let query = query_flex(6, 20.0, 20.0).with_container_query(fn(_) {
    Ok(Element::root(7, query_style()))
  })
  let sibling = query_flex(8, 30.0, 20.0)
    .with_children_style(query_style())
    .with_scroll_offset(zero)
  let tree = Element::root(1, query_style())
    .with_child(query)
    .with_child(sibling)
    .request_layout(query_size(100.0, 40.0))
    .unwrap()
    .prepaint()
    .unwrap()
    .tree()
  assert_true(tree.scroll_viewport(8) is Some(_))
  let rejected = query_grid(9)
    .with_grid_children_style(@layout.GridTreeStyle::new(1, 1).unwrap())
    .with_scroll_offset(zero)
  assert_true(rejected.grid_item is Some(_))
  assert_true(rejected.grid_style is Some(_))
}

///|
test "invalid query shapes and device scales cannot invoke callbacks" {
  let calls = Ref(0)
  let query = Element::container_query_root(1, fn(_) {
    calls.val += 1
    Ok(Element::root(2, query_style()))
  })
  assert_true(
    query
    .with_child(query_flex(3, 1.0, 1.0))
    .request_layout(query_size(20.0, 20.0))
    is Err(InvalidQueryShape),
  )
  assert_true(
    query.request_layout_with_device_scale(query_size(20.0, 20.0), 0.0)
    is Err(LayoutFailure(@layout.Flex(@layout.NegativeValue))),
  )
  assert_true(
    query.request_layout_with_device_scale(query_size(20.0, 20.0), 0.0 / 0.0)
    is Err(LayoutFailure(@layout.Flex(@layout.NonFiniteValue))),
  )
  assert_eq(calls.val, 0)
}

///|
test "query generated roots snap independently before negative origin translation" {
  for scale in [1.0, 1.25, 2.0] {
    for horizontal in [false, true] {
      for cross_extent in [10.0, 14.0] {
        let observed : Ref[@primitives.Size?] = Ref(None)
        let calls = Ref(0)
        let style = @layout.FlexTreeStyle::new(
          if horizontal {
            @layout.FlowDirection::column()
          } else {
            @layout.FlowDirection::row()
          },
        ).with_align(@layout.AlignItems::end())
        let root = Element::root(1, style).with_child(
          query_flex(2, 10.0 / scale, 12.0 / scale).with_container_query(fn(
            size,
          ) {
            calls.val += 1
            observed.val = Some(size)
            Ok(
              Element::grid_root(
                3,
                @layout.GridTreeStyle::new(
                  if horizontal {
                    8
                  } else {
                    1
                  },
                  if horizontal {
                    1
                  } else {
                    8
                  },
                ).unwrap(),
              ).with_child(query_grid(4)),
            )
          }),
        )
        let viewport = if horizontal {
          query_size(cross_extent / scale, 100.0 / scale)
        } else {
          query_size(100.0 / scale, cross_extent / scale)
        }
        let request = root
          .request_layout_with_device_scale(viewport, scale)
          .unwrap()
        let assigned = request.layout.items()[0].bounds()
        let tree = request.prepaint().unwrap().tree()
        assert_eq(calls.val, 1)
        assert_true(observed.val == Some(assigned.size()))
        assert_true(tree.node(2).unwrap().bounds() == assigned)
        assert_true(tree.node(3).unwrap().bounds() == assigned)
        let leaf = tree.node(4).unwrap().bounds()
        let origin = (cross_extent - 12.0) / scale
        if horizontal {
          assert_eq(leaf.left(), origin)
          assert_eq(leaf.size().width(), 1.0 / scale)
        } else {
          assert_eq(leaf.top(), origin)
          assert_eq(leaf.size().height(), 1.0 / scale)
        }
        assert_true(tree.node(3).unwrap().parent() == Some(2))
        assert_true(tree.node(4).unwrap().parent() == Some(3))
        assert_true(request.prepaint() is Err(AlreadyPrepainted))
        assert_eq(calls.val, 1)
      }
    }
  }
}

///|
test "nested query origins translate independently rounded returned roots" {
  for scale in [None, Some(1.0), Some(1.25), Some(2.0)] {
    let unit = match scale {
      None => 1.0
      Some(value) => 1.0 / value
    }
    let calls = Ref(0)
    let observed : Array[@primitives.Size] = []
    let style = query_style().with_align(@layout.AlignItems::end())
    let root = Element::root(1, style).with_child(
      query_flex(2, 10.0 * unit, 12.0 * unit).with_container_query(fn(size) {
        calls.val += 1
        observed.push(size)
        Ok(
          Element::root(3, style)
          .with_query_root_size(query_size(10.0 * unit, 10.0 * unit))
          .with_child(
            query_flex(4, 10.0 * unit, 12.0 * unit).with_container_query(fn(
              size,
            ) {
              calls.val += 1
              observed.push(size)
              Ok(
                Element::grid_root(5, @layout.GridTreeStyle::new(1, 8).unwrap()).with_child(
                  query_grid(6),
                ),
              )
            }),
          ),
        )
      }),
    )
    let viewport = query_size(100.0 * unit, 10.0 * unit)
    let request = match scale {
      None => root.request_layout(viewport).unwrap()
      Some(scale) =>
        root.request_layout_with_device_scale(viewport, scale).unwrap()
    }
    let tree = request.prepaint().unwrap().tree()
    assert_eq(calls.val, 2)
    assert_eq(observed.length(), 2)
    assert_true(observed[0] == tree.node(2).unwrap().bounds().size())
    assert_true(observed[1] == tree.node(4).unwrap().bounds().size())
    assert_true(tree.nodes().map(fn(node) { node.id() }) == [1, 2, 3, 4, 5, 6])
    assert_true(tree.node(3).unwrap().parent() == Some(2))
    assert_true(tree.node(5).unwrap().parent() == Some(4))
    assert_eq(tree.node(2).unwrap().bounds().top(), -2.0 * unit)
    assert_eq(tree.node(4).unwrap().bounds().top(), -4.0 * unit)
    assert_eq(tree.node(6).unwrap().bounds().top(), -4.0 * unit)
    assert_eq(
      tree.node(6).unwrap().bounds().size().height(),
      if scale is None {
        1.5
      } else {
        unit
      },
    )
    assert_true(request.prepaint() is Err(AlreadyPrepainted))
    assert_eq(calls.val, 2)
  }
}

///|
fn query_fractional_boundary(
  horizontal : Bool,
  oversized : Bool,
) -> RequestedLayout {
  let root = Element::grid_root(
      1,
      @layout.GridTreeStyle::new(
        if horizontal {
          5
        } else {
          1
        },
        if horizontal {
          1
        } else {
          5
        },
      ).unwrap(),
    )
    .with_child(query_grid(2))
    .with_child(
      Element::grid_item(
        @layout.GridItem::new(
          3,
          @layout.Dimension::auto(),
          @layout.Dimension::auto(),
        )
        .with_span(
          if horizontal {
            2
          } else {
            1
          },
          if horizontal {
            1
          } else {
            2
          },
        )
        .unwrap(),
      ).with_container_query(fn(_) {
        let generated = Element::grid_root(
          4,
          @layout.GridTreeStyle::new(1, 1).unwrap(),
        )
        Ok(
          if oversized {
            generated.with_query_root_size(
              if horizontal {
                query_size(2.4, 0.8)
              } else {
                query_size(0.8, 2.4)
              },
            )
          } else {
            generated
          },
        )
      }),
    )
  root
  .request_layout_with_device_scale(
    if horizontal {
      query_size(4.0, 0.8)
    } else {
      query_size(0.8, 4.0)
    },
    1.25,
  )
  .unwrap()
}

///|
test "query translated horizontal exact-fit residue does not overflow" {
  let request = query_fractional_boundary(true, false)
  let assigned = request.layout.items()[1].bounds()
  assert_true(!request.layout.overflow())
  assert_eq(assigned.left(), 0.8)
  assert_eq(assigned.right(), 2.4000000000000004)
  assert_eq(assigned.size().width(), 1.6)
  let painted = request.prepaint().unwrap()
  let generated = painted.tree().node(4).unwrap().bounds()
  assert_eq(generated.size().width(), 1.6)
  assert_eq(generated.right(), 2.4000000000000004)
  assert_true(!painted.overflow())
}

///|
test "query translated vertical exact-fit residue does not overflow" {
  let request = query_fractional_boundary(false, false)
  let assigned = request.layout.items()[1].bounds()
  assert_true(!request.layout.overflow())
  assert_eq(assigned.top(), 0.8)
  assert_eq(assigned.bottom(), 2.4000000000000004)
  assert_eq(assigned.size().height(), 1.6)
  let painted = request.prepaint().unwrap()
  let generated = painted.tree().node(4).unwrap().bounds()
  assert_eq(generated.size().height(), 1.6)
  assert_eq(generated.bottom(), 2.4000000000000004)
  assert_true(!painted.overflow())
}

///|
test "query translated boundary keeps genuinely oversized generated roots" {
  for horizontal in [true, false] {
    let request = query_fractional_boundary(horizontal, true)
    assert_true(!request.layout.overflow())
    let painted = request.prepaint().unwrap()
    let assigned = painted.tree().node(3).unwrap().bounds()
    let generated = painted.tree().node(4).unwrap().bounds()
    assert_true(painted.overflow())
    if horizontal {
      assert_eq(generated.size().width(), 2.4)
      assert_true(generated.right() - assigned.right() > 0.79)
    } else {
      assert_eq(generated.size().height(), 2.4)
      assert_true(generated.bottom() - assigned.bottom() > 0.79)
    }
  }
}

///|
test "query boundary tolerance remains bounded below meaningful subpixel excess" {
  assert_true(!query_exceeds_with_tolerance(2.4000000000000004, 2.4))
  assert_true(!query_exceeds_with_tolerance(-2.4, -2.4000000000000004))
  assert_true(query_exceeds_with_tolerance(2.4 + 0.0000000001, 2.4))
  assert_true(query_exceeds_with_tolerance(-2.4 + 0.0000000001, -2.4))
  assert_true(!query_exceeds_with_tolerance(2.3, 2.4))
}
