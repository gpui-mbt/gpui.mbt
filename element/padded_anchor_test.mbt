///|
fn padded_leaf(
  id : UInt64,
  width : Double,
  height : Double,
) -> @element.Element {
  @element.Element::new(
    @layout.FlexItem::new(
      id,
      @layout.Dimension::auto(),
      @layout.Dimension::auto(),
      anchor_size(width, height),
    )
    .with_flex(0, 0)
    .unwrap(),
  )
}

///|
fn padded_owner(
  id : UInt64,
  leaf_id : UInt64,
  width : Double,
  height : Double,
) -> @element.Element {
  padded_leaf(id, 0, 0)
  .with_children_style(
    @layout.FlexTreeStyle::new(@layout.FlowDirection::column()).with_insets(
      @layout.Insets::new(3.25, 8.5, 6.75, 11.25).unwrap(),
      @layout.Insets::new(1.25, 2.5, 3.25, 0.75).unwrap(),
    ),
  )
  .with_child(padded_leaf(leaf_id, width, height))
}

///|
fn padded_attachment(
  id : UInt64,
  leaf_id : UInt64,
  popup : @element.Element,
) -> @element.Element {
  @element.Element::anchored_after_measured_leaf(
    id,
    leaf_id,
    popup,
    @element.TopLeft,
    @element.Local,
    anchor_point(0, 0),
    margin=8,
  )
  .unwrap()
  .deferred()
  .unwrap()
}

///|
// These are independent synthetic metric inputs, not Rust oracle rectangles.
// The assertions compare public lifecycle outputs to their live reference.
test "measured leaf anchor follows actual decorated auto owner layout" {
  for scale in [1.0, 1.25, 1.5, 2.0] {
    for (width, height) in [(51.25, 17.5), (91.75, 29.25)] {
      let parent = padded_owner(2, 3, width, height)
      let root = anchor_root(parent, 32, 24)
      let ordinary = root
        .request_layout_with_device_scale(anchor_size(640, 480), scale)
        .unwrap()
        .prepaint()
        .unwrap()
        .tree()
      let frame = anchor_root(
          parent.with_child(
            padded_attachment(20, 3, padded_owner(10, 11, 80, 32)),
          ),
          32,
          24,
        )
        .request_layout_with_device_scale(anchor_size(640, 480), scale)
        .unwrap()
        .prepaint()
        .unwrap()
      let tree = frame.tree()
      let owner = tree.node(2).unwrap().bounds()
      let leaf = tree.node(3).unwrap().bounds()
      let attachment = tree.node(20).unwrap().bounds()
      let popup = tree.node(10).unwrap().bounds()
      anchor_assert_rect(owner, ordinary.node(2).unwrap().bounds())
      anchor_assert_rect(leaf, ordinary.node(3).unwrap().bounds())
      anchor_assert_point(
        attachment.origin(),
        // Reconstruct the snapped device edge before division, rather than
        // adding two logical quotients and introducing a subpixel residue.
        anchor_point(
          leaf.left(),
          (leaf.top() * scale + leaf.size().height() * scale) / scale,
        ),
      )
      anchor_assert_point(popup.origin(), attachment.origin())
      assert_true(attachment.left() > owner.left())
      assert_true(attachment.top() < owner.bottom())
      assert_true(
        popup.size().width() > tree.node(11).unwrap().bounds().size().width(),
      )
      assert_true(
        popup.size().height() > tree.node(11).unwrap().bounds().size().height(),
      )
      assert_true(frame.paint().validate() is Ok(_))
      assert_true(!tree.node(20).unwrap().accepts_pointer_events())
    }
  }
}

///|
test "measured metrics change auto owner and popup sizes without host boxes" {
  let render = fn(width : Double, height : Double) {
    anchor_root(
      padded_owner(2, 3, width, height).with_child(
        padded_attachment(20, 3, padded_owner(10, 11, width + 20, height + 10)),
      ),
      32,
      24,
    )
    .request_layout(anchor_size(640, 480))
    .unwrap()
    .prepaint()
    .unwrap()
    .tree()
  }
  let small = render(40, 15)
  let large = render(90, 30)
  for id in [2UL, 3UL, 10UL, 11UL] {
    assert_true(
      large.node(id).unwrap().bounds().size().width() >
      small.node(id).unwrap().bounds().size().width(),
    )
    assert_true(
      large.node(id).unwrap().bounds().size().height() >
      small.node(id).unwrap().bounds().size().height(),
    )
  }
  assert_true(
    large.node(20).unwrap().bounds().top() >
    small.node(20).unwrap().bounds().top(),
  )
}

///|
test "measured nested attachments fit through existing lifecycle and restore" {
  let child = padded_attachment(30, 11, padded_owner(40, 41, 190, 45))
  let parent = padded_attachment(
    20,
    3,
    padded_owner(10, 11, 150, 55).with_child(child),
  )
  let root = anchor_root(padded_owner(2, 3, 70, 25).with_child(parent), 60, 50)
  for scale in [1.0, 1.25, 1.5, 2.0] {
    let render = fn(width : Double, height : Double) {
      root
      .request_layout_with_device_scale(anchor_size(width, height), scale)
      .unwrap()
      .prepaint()
      .unwrap()
      .tree()
    }
    let wide = render(640, 480)
    let narrow = render(160, 120)
    let restored = render(640, 480)
    for id in [1UL, 2UL, 3UL, 20UL, 10UL, 11UL, 30UL, 40UL, 41UL] {
      anchor_assert_rect(
        wide.node(id).unwrap().bounds(),
        restored.node(id).unwrap().bounds(),
      )
    }
    for (wrapper, reference) in [(20UL, 3UL), (30UL, 11UL)] {
      let bounds = narrow.node(reference).unwrap().bounds()
      anchor_assert_point(
        narrow.node(wrapper).unwrap().bounds().origin(),
        anchor_point(bounds.left(), bounds.bottom()),
      )
    }
    for id in [10UL, 40UL] {
      let popup = narrow.node(id).unwrap().bounds()
      assert_true(popup.left() >= 0)
      assert_true(popup.top() >= 0)
      assert_true(popup.size() == wide.node(id).unwrap().bounds().size())
    }
    assert_true(narrow.node(40).unwrap().bounds().size().width() > 160)
    assert_true(narrow.to_scene().validate() is Ok(_))
  }
}

///|
test "measured construction validates margin and metric input constructors" {
  for invalid in [-1.0, 0.0 / 0.0, 1.0 / 0.0, -1.0 / 0.0] {
    assert_true(@primitives.Size::new(invalid, 20) is Err(_))
    assert_true(@primitives.Size::new(20, invalid) is Err(_))
    assert_true(@layout.Insets::new(invalid, 0, 0, 0) is Err(_))
    assert_true(@layout.Insets::new(0, invalid, 0, 0) is Err(_))
    assert_true(@layout.Insets::new(0, 0, invalid, 0) is Err(_))
    assert_true(@layout.Insets::new(0, 0, 0, invalid) is Err(_))
    assert_true(
      @element.Element::anchored_after_measured_leaf(
        20,
        3,
        padded_owner(10, 11, 50, 20),
        @element.TopLeft,
        @element.Local,
        anchor_point(0, 0),
        margin=invalid,
      )
      is Err(@element.GeometryFailure),
    )
  }
  let zero = anchor_root(
    padded_owner(2, 3, 0, 0).with_child(
      padded_attachment(20, 3, padded_owner(10, 11, 0, 0)),
    ),
    0,
    0,
  )
  assert_true(
    zero.request_layout(anchor_size(640, 480)).unwrap().prepaint() is Ok(_),
  )
}

///|
test "measured popup descendants preserve cumulative centered layout phase" {
  for scale in [1.0, 1.25, 1.5, 2.0] {
    for
      (leaf_width, popup_child_width) in [
        (116.0, 141.0),
        (72.0, 95.0),
        (117.0, 140.0),
      ] {
      let owner = padded_leaf(2, 0, 0)
        .with_children_style(
          @layout.FlexTreeStyle::new(@layout.FlowDirection::column()).with_insets(
            @layout.Insets::new(4 / scale, 17 / scale, 3 / scale, 11 / scale).unwrap(),
            @layout.Insets::new(1 / scale, 2 / scale, 1 / scale, 1 / scale).unwrap(),
          ),
        )
        .with_child(padded_leaf(3, leaf_width / scale, 26 / scale))
      let popup = anchor_popup(10, 384 / scale, 80 / scale, false)
        .with_children_style(
          @layout.FlexTreeStyle::new(@layout.FlowDirection::row()).with_justify(
            @layout.JustifyContent::center(),
          ),
        )
        .with_child(
          anchor_popup(11, popup_child_width / scale, 20 / scale, true),
        )
      let root = @element.Element::root(
        1,
        @layout.FlexTreeStyle::new(@layout.FlowDirection::row())
        .with_justify(@layout.JustifyContent::center())
        .with_align(@layout.AlignItems::center()),
      ).with_child(owner.with_child(padded_attachment(20, 3, popup)))
      let request = root
        .request_layout_with_device_scale(
          anchor_size(900 / scale, 700 / scale),
          scale,
        )
        .unwrap()
      let reference = request.layout.bounds_before_edge_snap(3).unwrap()
      let frame = request.prepaint().unwrap()
      let tree = frame.tree()
      // Positive physical half ties round toward zero. Derive expected position
      // from live raw reference and authored child size, not an oracle box.
      let physical = reference.left() * scale + (384 - popup_child_width) / 2
      let expected = (physical - 0.5).ceil()
      let actual = tree.node(11).unwrap().bounds().left() * scale
      assert_true(
        actual - expected < 0.000000001 && actual - expected > -0.000000001,
      )
      anchor_assert_point(
        tree.node(20).unwrap().bounds().origin(),
        tree.node(10).unwrap().bounds().origin(),
      )
      assert_true(frame.paint().validate() is Ok(_))
    }
  }
}
