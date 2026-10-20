///|
fn self_item(id : UInt64, cross : @layout.Dimension) -> @layout.FlexItem {
  @layout.FlexItem::new(id, tree_points(10.0), cross, tree_size(10.0, 12.0))
}

///|
test "align self overrides inherited cross placement in either axis" {
  for column in [false, true] {
    let container = @layout.FlexContainer::new(
      if column {
        @layout.FlowDirection::column()
      } else {
        @layout.FlowDirection::row()
      },
      if column {
        unwrap_size(80.0, 100.0)
      } else {
        unwrap_size(100.0, 80.0)
      },
    ).with_align(@layout.AlignItems::center())
    let modes = [
      @layout.AlignSelf::start(),
      @layout.AlignSelf::center(),
      @layout.AlignSelf::end(),
      @layout.AlignSelf::auto(),
    ]
    let items = modes.mapi((i, mode) => {
      self_item((i + 1).to_uint64(), tree_points(12.0)).with_align_self(mode)
    })
    let result = unwrap_layout(@layout.layout_flex(container, items)).items()
    let expected = [0.0, 34.0, 68.0, 34.0]
    for i, item in result {
      assert_eq(
        if column {
          item.bounds().left()
        } else {
          item.bounds().top()
        },
        expected[i],
      )
    }
  }
}

///|
test "align self stretch resizes only auto cross dimensions and respects caps" {
  let container = @layout.FlexContainer::new(
    @layout.FlowDirection::row(),
    unwrap_size(100.0, 80.0),
  ).with_align(@layout.AlignItems::end())
  let automatic = self_cross_limits(
    self_item(1, @layout.Dimension::auto()).with_align_self(
      @layout.AlignSelf::stretch(),
    ),
    10.0,
    Some(42.0),
  )
  let fixed = self_item(2, unwrap_points(12.0)).with_align_self(
    @layout.AlignSelf::stretch(),
  )
  let inherited = self_item(3, @layout.Dimension::auto())
  let result = unwrap_layout(
    @layout.layout_flex(container, [automatic, fixed, inherited]),
  ).items()
  assert_eq(result[0].bounds().size().height(), 42.0)
  assert_eq(result[1].bounds().size().height(), 12.0)
  assert_eq(result[2].bounds().size().height(), 12.0)
  assert_eq(result[2].bounds().top(), 68.0)
}

///|
test "align self physical and flex edges differ under wrap reverse" {
  let container = @layout.FlexContainer::new(
    @layout.FlowDirection::row(),
    unwrap_size(100.0, 80.0),
  ).with_wrap(@layout.FlexWrap::wrap_reverse())
  let modes = [
    @layout.AlignSelf::start(),
    @layout.AlignSelf::end(),
    @layout.AlignSelf::flex_start(),
    @layout.AlignSelf::flex_end(),
  ]
  let items = modes.mapi((i, mode) => {
    self_item((i + 1).to_uint64(), tree_points(12.0)).with_align_self(mode)
  })
  let result = unwrap_layout(@layout.layout_flex(container, items)).items()
  let expected = [0.0, 68.0, 68.0, 0.0]
  for i, item in result {
    assert_eq(item.bounds().top(), expected[i])
  }
}

///|
test "item rebuilders preserve align self and auto restores inheritance" {
  let container = @layout.FlexContainer::new(
    @layout.FlowDirection::row(),
    unwrap_size(100.0, 80.0),
  ).with_align(@layout.AlignItems::center())
  let item = self_item(1, unwrap_points(12.0)).with_align_self(
    @layout.AlignSelf::end(),
  )
  let item = unwrap_item_flex(item, 0.0, 1.0)
  let item = unwrap_main_limits(item, 0.0, None)
  let item = self_cross_limits(item, 0.0, None).with_intrinsic(
    unwrap_size(10.0, 12.0),
  )
  let result = unwrap_layout(@layout.layout_flex(container, [item])).items()
  assert_eq(result[0].bounds().top(), 68.0)
  let result = unwrap_layout(
    @layout.layout_flex(container, [
      item.with_align_self(@layout.AlignSelf::auto()),
    ]),
  ).items()
  assert_eq(result[0].bounds().top(), 34.0)
}

///|
test "device scale preparation preserves align self in a recursive tree" {
  let style = @layout.FlexTreeStyle::new(@layout.FlowDirection::row()).with_align(
    @layout.AlignItems::start(),
  )
  let node = @layout.FlexTreeNode::new(
    self_item(2, unwrap_points(12.0)).with_align_self(@layout.AlignSelf::end()),
    1,
  )
  match
    @layout.layout_flex_tree_with_device_scale(
      1,
      unwrap_size(100.0, 80.0),
      style,
      [node],
      2.0,
    ) {
    Err(_) => fail("valid align self tree rejected")
    Ok(result) => assert_eq(result.items()[0].bounds().top(), 68.0)
  }
}

///|
test "align self center and end retain signed cross overflow" {
  let container = @layout.FlexContainer::new(
    @layout.FlowDirection::row(),
    unwrap_size(100.0, 80.0),
  )
  let items = [
    self_item(1, unwrap_points(120.0)).with_align_self(
      @layout.AlignSelf::center(),
    ),
    self_item(2, unwrap_points(120.0)).with_align_self(@layout.AlignSelf::end()),
  ]
  let result = unwrap_layout(@layout.layout_flex(container, items))
  assert_eq(result.items()[0].bounds().top(), -20.0)
  assert_eq(result.items()[1].bounds().top(), -40.0)
  assert_true(result.overflow())
}

///|
fn self_cross_limits(
  item : @layout.FlexItem,
  min : Double,
  max : Double?,
) -> @layout.FlexItem raise {
  match item.with_cross_limits(min, max) {
    Ok(value) => value
    Err(_) => fail("valid cross limits rejected")
  }
}
