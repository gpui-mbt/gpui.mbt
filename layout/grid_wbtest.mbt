///|
fn grid_size(width : Double, height : Double) -> @primitives.Size {
  @primitives.Size::new(width, height).unwrap()
}

///|
fn grid_auto(id : UInt64) -> GridItem {
  GridItem::new(id, Auto, Auto)
}

///|
test "grid generic counts divide remaining space into equal zero-min tracks" {
  for columns = 1; columns <= 7; columns = columns + 1 {
    for rows = 1; rows <= 5; rows = rows + 1 {
      let style = GridTreeStyle::new(columns, rows)
        .unwrap()
        .with_gap_x(3.0)
        .unwrap()
        .with_gap_y(7.0)
        .unwrap()
      let items : Array[GridItem] = []
      for index = 0; index < columns * rows; index = index + 1 {
        items.push(grid_auto(index.to_uint64()))
      }
      let result = layout_grid(
        GridContainer::new(grid_size(311.0, 193.0), style),
        items,
      ).unwrap()
      assert_true(!result.overflow())
      let width = (311.0 - (columns - 1).to_double() * 3.0) /
        columns.to_double()
      let height = (193.0 - (rows - 1).to_double() * 7.0) / rows.to_double()
      for index = 0; index < items.length(); index = index + 1 {
        let bounds = result.items()[index].bounds()
        assert_true((bounds.size().width() - width).abs() < 0.00000001)
        assert_true((bounds.size().height() - height).abs() < 0.00000001)
        assert_true(
          (bounds.left() - (index % columns).to_double() * (width + 3.0)).abs() <
          0.00000001,
        )
        assert_true(
          (bounds.top() - (index / columns).to_double() * (height + 7.0)).abs() <
          0.00000001,
        )
      }
    }
  }
}

///|
test "grid physical asymmetric insets and percentage area resolution" {
  let style = GridTreeStyle::new(2, 3)
    .unwrap()
    .with_gap_x(10.0)
    .unwrap()
    .with_gap_y(6.0)
    .unwrap()
    .with_insets(
      Insets::new(2.0, 3.0, 4.0, 5.0).unwrap(),
      Insets::new(7.0, 8.0, 9.0, 10.0).unwrap(),
    )
  let result = layout_grid(GridContainer::new(grid_size(126.0, 94.0), style), [
    GridItem::new(1, Percent(0.5), Percent(0.25)),
    grid_auto(2),
  ]).unwrap()
  assert_true(
    result.content_bounds() ==
    @primitives.Rect::new(15.0, 9.0, 100.0, 72.0).unwrap(),
  )
  assert_true(
    result.items()[0].bounds() ==
    @primitives.Rect::new(15.0, 9.0, 22.5, 5.0).unwrap(),
  )
  assert_true(
    result.items()[1].bounds() ==
    @primitives.Rect::new(70.0, 9.0, 45.0, 20.0).unwrap(),
  )
}

///|
test "grid sparse placement leaves holes and checks the whole multirow span" {
  let style = GridTreeStyle::new(4, 3).unwrap()
  let result = layout_grid(GridContainer::new(grid_size(400.0, 300.0), style), [
    grid_auto(1).with_span(2, 2).unwrap(),
    grid_auto(2).with_span(3, 1).unwrap(),
    grid_auto(3),
  ]).unwrap()
  assert_true(
    result.items()[0].bounds() ==
    @primitives.Rect::new(0.0, 0.0, 200.0, 200.0).unwrap(),
  )
  assert_true(
    result.items()[1].bounds() ==
    @primitives.Rect::new(0.0, 200.0, 300.0, 100.0).unwrap(),
  )
  assert_true(
    result.items()[2].bounds() ==
    @primitives.Rect::new(300.0, 200.0, 100.0, 100.0).unwrap(),
  )
  // Dense placement would backfill (200, 0) for the last item.
  assert_true(result.items()[2].bounds().top() != 0.0)
}

///|
test "grid full columns starts at definite first line after a partial row" {
  let style = GridTreeStyle::new(3, 3).unwrap().with_gap(5.0).unwrap()
  let result = layout_grid(GridContainer::new(grid_size(100.0, 100.0), style), [
    grid_auto(1),
    grid_auto(2).full_columns(),
    grid_auto(3),
  ]).unwrap()
  assert_true(
    result.items()[1].bounds() ==
    @primitives.Rect::new(0.0, 35.0, 100.0, 30.0).unwrap(),
  )
  assert_true(
    result.items()[2].bounds() ==
    @primitives.Rect::new(0.0, 70.0, 30.0, 30.0).unwrap(),
  )
}

///|
test "grid fixed-size overflow cannot grow explicit tracks" {
  let result = layout_grid(
    GridContainer::new(
      grid_size(150.0, 40.0),
      GridTreeStyle::new(3, 1).unwrap(),
    ),
    [GridItem::new(1, Points(90.0), Points(224.0)), grid_auto(2), grid_auto(3)],
  ).unwrap()
  assert_true(result.overflow())
  assert_true(result.items()[0].overflow())
  assert_true(result.items()[0].bounds().size() == grid_size(90.0, 224.0))
  assert_true(
    result.items()[1].bounds() ==
    @primitives.Rect::new(50.0, 0.0, 50.0, 40.0).unwrap(),
  )
  assert_eq(result.items()[2].bounds().left(), 100.0)
}

///|
test "grid gaps exceeding extent produce zero tracks with explicit overflow" {
  let result = layout_grid(
    GridContainer::new(
      grid_size(5.0, 4.0),
      GridTreeStyle::new(3, 2).unwrap().with_gap(10.0).unwrap(),
    ),
    [grid_auto(1), grid_auto(2)],
  ).unwrap()
  assert_true(result.overflow())
  assert_true(result.items()[0].bounds().size() == grid_size(0.0, 0.0))
  assert_eq(result.items()[1].bounds().left(), 10.0)
}

///|
test "grid rejects invalid counts spans exhausted placement duplicate IDs and arithmetic overflow" {
  assert_true(GridTreeStyle::new(0, 2) is Err(InvalidTrackCount))
  assert_true(GridTreeStyle::new(-1, 2) is Err(InvalidTrackCount))
  assert_true(
    GridTreeStyle::new(2147483647, 2147483647) is Err(CellLimitExceeded),
  )
  assert_true(GridTreeStyle::new(65, 64) is Err(CellLimitExceeded))
  assert_true(GridTreeStyle::new(64, 64) is Ok(_))
  assert_true(grid_auto(1).with_span(0, 2) is Err(InvalidSpan))
  let container = GridContainer::new(
    grid_size(20.0, 20.0),
    GridTreeStyle::new(2, 2).unwrap(),
  )
  assert_true(
    layout_grid(container, [grid_auto(1).with_span(3, 1).unwrap()])
    is Err(InvalidSpan),
  )
  assert_true(
    layout_grid(container, [grid_auto(1), grid_auto(1)]) is Err(DuplicateId),
  )
  assert_true(
    layout_grid(container, [grid_auto(1).with_span(2, 2).unwrap(), grid_auto(2)])
    is Err(PlacementExhausted),
  )
  let huge = GridTreeStyle::new(3, 1).unwrap().with_gap_x(1.0e308).unwrap()
  assert_true(
    layout_grid(GridContainer::new(grid_size(20.0, 20.0), huge), [])
    is Err(Numeric(NonFiniteValue)),
  )
  let nonfinite = 0.0 / 0.0
  assert_true(
    GridTreeStyle::new(1, 1).unwrap().with_gap(nonfinite)
    is Err(Numeric(NonFiniteValue)),
  )
  assert_true(
    layout_grid(container, [GridItem::new(1, Percent(1.0e308), Auto)])
    is Err(Numeric(NonFiniteValue)),
  )
}

///|
test "mixed tree rounds final absolute edges rather than local grid rectangles" {
  let root = @primitives.Rect::new(0.0, 0.0, 100.0, 10.0).unwrap()
  let style = MixedTreeStyle::FlexStyle(FlexTreeStyle::new(Row))
  let nodes = [
    MixedTreeNode::new(
      FlexChild(
        FlexItem::new(2, Percent(1.0 / 3.0), Points(10.0), grid_size(0.0, 0.0)),
      ),
      1,
      None,
    ),
    MixedTreeNode::new(
      FlexChild(
        FlexItem::new(3, Percent(2.0 / 3.0), Points(10.0), grid_size(0.0, 0.0)),
      ),
      1,
      Some(GridStyle(GridTreeStyle::new(3, 1).unwrap())),
    ),
    MixedTreeNode::new(GridChild(grid_auto(4)), 3, None),
    MixedTreeNode::new(GridChild(grid_auto(5)), 3, None),
    MixedTreeNode::new(GridChild(grid_auto(6)), 3, None),
  ]
  let raw = layout_mixed_tree_at(1, root, style, nodes, None).unwrap()
  assert_true(
    (raw.items()[2].bounds().right() - 55.55555555555556).abs() < 0.000001,
  )
  let snapped = layout_mixed_tree_at(1, root, style, nodes, Some(1.0)).unwrap()
  assert_eq(snapped.items()[2].bounds().left(), 33.0)
  assert_eq(snapped.items()[2].bounds().right(), 56.0)
  assert_eq(snapped.items()[2].bounds().size().width(), 23.0)
  for scale in [1.25, 2.0] {
    let snapped = layout_mixed_tree_at(1, root, style, nodes, Some(scale)).unwrap()
    for item in snapped.items() {
      assert_true(
        (item.bounds().left() * scale - (item.bounds().left() * scale).round()).abs() <
        0.000001,
      )
      assert_true(
        (item.bounds().right() * scale - (item.bounds().right() * scale).round()).abs() <
        0.000001,
      )
    }
  }
}

///|
test "mixed tree rejects incompatible items invalid preorder duplicate IDs and missing containers" {
  let bounds = @primitives.Rect::new(0.0, 0.0, 20.0, 20.0).unwrap()
  let flex = FlexChild(
    FlexItem::new(2, Points(10.0), Points(10.0), grid_size(0.0, 0.0)),
  )
  let style = GridStyle(GridTreeStyle::new(1, 1).unwrap())
  assert_true(
    layout_mixed_tree_at(
      1,
      bounds,
      style,
      [MixedTreeNode::new(flex, 1, None)],
      None,
    )
    is Err(MismatchedItem),
  )
  assert_true(
    layout_mixed_tree_at(
      1,
      bounds,
      FlexStyle(FlexTreeStyle::new(Row)),
      [MixedTreeNode::new(GridChild(grid_auto(2)), 1, None)],
      None,
    )
    is Err(MismatchedItem),
  )
  assert_true(
    layout_mixed_tree_at(
      1,
      bounds,
      style,
      [MixedTreeNode::new(GridChild(grid_auto(2)), 99, None)],
      None,
    )
    is Err(MissingParent),
  )
  assert_true(
    layout_mixed_tree_at(
      1,
      bounds,
      style,
      [
        MixedTreeNode::new(GridChild(grid_auto(2)), 1, None),
        MixedTreeNode::new(GridChild(grid_auto(2)), 1, None),
      ],
      None,
    )
    is Err(DuplicateId),
  )
  assert_true(
    layout_mixed_tree_at(
      1,
      bounds,
      style,
      [
        MixedTreeNode::new(GridChild(grid_auto(2)), 1, None),
        MixedTreeNode::new(GridChild(grid_auto(3)), 2, None),
      ],
      None,
    )
    is Err(MissingContainer),
  )
  let preorder = [
    MixedTreeNode::new(GridChild(grid_auto(2)), 1, Some(style)),
    MixedTreeNode::new(GridChild(grid_auto(3)), 1, None),
    MixedTreeNode::new(GridChild(grid_auto(4)), 2, None),
  ]
  assert_true(
    layout_mixed_tree_at(1, bounds, style, preorder, None)
    is Err(InvalidPreorder),
  )
  assert_true(
    layout_mixed_tree_at(1, bounds, style, [], Some(0.0))
    is Err(Flex(NegativeValue)),
  )
  assert_true(
    layout_mixed_tree_at(1, bounds, style, [], Some(0.0 / 0.0))
    is Err(Flex(NonFiniteValue)),
  )
}

///|
test "single grid tracks do not overflow from an unused gap stride" {
  let style = GridTreeStyle::new(1, 1).unwrap().with_gap(1.0e308).unwrap()
  let result = layout_grid(
    GridContainer::new(grid_size(1.0e308, 1.0e308), style),
    [grid_auto(1)],
  ).unwrap()
  assert_true(!result.overflow())
  assert_eq(result.items()[0].bounds().left(), 0.0)
  assert_eq(result.items()[0].bounds().size().width(), 1.0e308)
}

///|
test "grid exact fit tolerates fractional far-edge residue but keeps real overflow" {
  for horizontal in [true, false] {
    let style = if horizontal {
      GridTreeStyle::new(3, 1).unwrap().with_gap_x(1.0).unwrap()
    } else {
      GridTreeStyle::new(1, 3).unwrap().with_gap_y(1.0).unwrap()
    }
    let size = if horizontal {
      grid_size(7.0, 1.0)
    } else {
      grid_size(1.0, 7.0)
    }
    let result = layout_grid(GridContainer::new(size, style), [
      grid_auto(1),
      grid_auto(2),
      grid_auto(3),
    ]).unwrap()
    let last = result.items()[2].bounds()
    // This exact-fit reconstruction is one binary64 step beyond seven.
    assert_true(
      if horizontal {
        last.right() > 7.0
      } else {
        last.bottom() > 7.0
      },
    )
    assert_true(!result.overflow())
    for item in result.items() {
      assert_true(!item.overflow())
    }
    let oversized = if horizontal {
      GridItem::new(3, Points(2.0), Auto)
    } else {
      GridItem::new(3, Auto, Points(2.0))
    }
    let overflow = layout_grid(GridContainer::new(size, style), [
      grid_auto(1),
      grid_auto(2),
      oversized,
    ]).unwrap()
    assert_true(overflow.overflow())
    assert_true(!overflow.items()[0].overflow())
    assert_true(overflow.items()[2].overflow())
  }
}

///|
test "ordinary mixed trees still snap absolute edges at negative origins" {
  let layout = layout_mixed_tree_at(
    1,
    @primitives.Rect::new(0.0, 0.0, 100.0, 10.0).unwrap(),
    FlexStyle(FlexTreeStyle::new(Row).with_align(End)),
    [
      MixedTreeNode::new(
        FlexChild(
          FlexItem::new(2, Points(10.0), Points(12.0), grid_size(0.0, 0.0)),
        ),
        1,
        Some(GridStyle(GridTreeStyle::new(1, 8).unwrap())),
      ),
      MixedTreeNode::new(GridChild(grid_auto(3)), 2, None),
    ],
    Some(1.0),
  ).unwrap()
  // Without an independent query-root boundary, [-2, -0.5] rounds to [-2, 0].
  assert_true(
    layout.items()[1].bounds() ==
    @primitives.Rect::new(0.0, -2.0, 10.0, 2.0).unwrap(),
  )
}
