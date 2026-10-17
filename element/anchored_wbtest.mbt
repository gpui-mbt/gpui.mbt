///|
fn anchored_test_popup(text_width : Double) -> Element {
  let zero = @primitives.Size::new(0, 0).unwrap()
  let auto = @layout.Dimension::auto()
  let item = @layout.FlexItem::new(10, auto, auto, zero)
    .with_main_limits(100, None)
    .unwrap()
  let padding = @layout.Insets::new(2, 8, 2, 8).unwrap()
  let style = @layout.FlexTreeStyle::new(@layout.FlowDirection::row()).with_insets(
    padding,
    @layout.Insets::zero(),
  )
  Element::new(item)
  .with_children_style(style)
  .with_child(
    Element::new(
      @layout.FlexItem::new(
        11,
        auto,
        auto,
        @primitives.Size::new(text_width, 20).unwrap(),
      ),
    ),
  )
}

///|
test "anchored measurement derives popup width from text padding and minimum" {
  let small = measure_anchored_popup(9, anchored_test_popup(60), None).unwrap()
  let wide = measure_anchored_popup(9, anchored_test_popup(120), None).unwrap()
  assert_eq(small.layout.items().length(), 2)
  assert_eq(small.layout.items()[0].bounds().size().width(), 100)
  assert_eq(small.layout.items()[0].bounds().size().height(), 24)
  assert_eq(wide.layout.items()[0].bounds().size().width(), 136)
  assert_eq(wide.layout.items()[0].bounds().size().height(), 24)
  assert_eq(wide.layout.items()[1].bounds().left(), 8)
  assert_eq(wide.layout.items()[1].bounds().top(), 2)
  assert_true(wide.placements[1].parent == Some(9))
  assert_true(wide.placements[2].parent == Some(10))
}

///|
test "anchored measurement runs device scale through the core subtree" {
  let popup = anchored_test_popup(120)
  let raw = measure_anchored_popup(9, popup, None).unwrap()
  let snapped = measure_anchored_popup(9, popup, Some(1.25)).unwrap()
  assert_eq(raw.layout.items()[0].bounds().size().height(), 24)
  assert_eq(snapped.layout.items()[0].bounds().size().width(), 136)
  assert_eq(snapped.layout.items()[0].bounds().size().height(), 23.2)
  assert_eq(snapped.layout.items()[1].bounds().top(), 1.6)
  assert_true(
    measure_anchored_popup(9, popup, Some(0.0)) is Err(LayoutFailure(_)),
  )
}

///|
test "anchored measurement rejects contextual shapes before invoking queries" {
  let popup = anchored_test_popup(60)
  let queried = popup.with_container_query(_ => abort("query must not run"))
  assert_true(
    measure_anchored_popup(9, queried, None)
    is Err(UnsupportedAnchoredComposition),
  )
  let scrolled = popup.with_scroll_offset(@primitives.Point::new(0, 0).unwrap())
  assert_true(
    measure_anchored_popup(9, scrolled, None)
    is Err(UnsupportedAnchoredComposition),
  )
  let percentage = {
    ..popup,
    item: Some(
      @layout.FlexItem::new(
        10,
        @layout.Dimension::percent(0.5).unwrap(),
        @layout.Dimension::auto(),
        @primitives.Size::new(0, 0).unwrap(),
      ),
    ),
  }
  assert_true(
    measure_anchored_popup(9, percentage, None) is Err(InvalidAnchoredShape),
  )
  assert_true(measure_anchored_popup(10, popup, None) is Err(DuplicateId))
  assert_true(
    measure_anchored_popup(9, popup.with_child(popup), None) is Err(DuplicateId),
  )
}

///|
test "anchored measurement checks leaf element and layout item identity" {
  let leaf = anchored_test_popup(60).children[0]
  let baseline = measure_anchored_popup(9, leaf, None).unwrap()
  assert_true(baseline.placements[1].element.id == 11)
  assert_true(baseline.layout.items()[0].id() == 11)
  assert_true(baseline.prepaint().unwrap().tree().node(11) is Some(_))
  let mismatched = { ..leaf, id: 12, }
  assert_true(
    measure_anchored_popup(9, mismatched, None) is Err(InvalidAnchoredShape),
  )
}

///|
test "anchored measurement checks descendant element and layout item identity" {
  let popup = anchored_test_popup(60)
  let baseline = measure_anchored_popup(9, popup, None).unwrap()
  assert_true(baseline.placements[2].element.id == 11)
  assert_true(baseline.layout.items()[1].id() == 11)
  assert_true(baseline.prepaint().unwrap().tree().node(11) is Some(_))
  let mismatched = { ..popup, children: [{ ..popup.children[0], id: 12, }], }
  assert_true(
    measure_anchored_popup(9, mismatched, None) is Err(InvalidAnchoredShape),
  )
}

///|
test "anchored node validation preserves attachment reference and rejects nesting" {
  let reference = Element::new(
    @layout.FlexItem::new(
      2,
      @layout.Dimension::points(65).unwrap(),
      @layout.Dimension::points(120).unwrap(),
      @primitives.Size::new(0, 0).unwrap(),
    )
    .with_flex(0, 0)
    .unwrap(),
  )
  let attachment = Element::anchored_after(
      20,
      2,
      anchored_test_popup(60),
      TopLeft,
      Local,
      @primitives.Point::new(0, 0).unwrap(),
    )
    .unwrap()
    .deferred()
    .unwrap()
  let tree = Element::root(
      1,
      @layout.FlexTreeStyle::new(@layout.FlowDirection::column()),
    )
    .with_child(reference)
    .with_child(attachment)
    .request_layout(@primitives.Size::new(640, 480).unwrap())
    .unwrap()
    .prepaint()
    .unwrap()
    .tree()
  let nodes = tree.nodes()
  let nested = { ..nodes[2], id: 21, parent: Some(20), }
  assert_true(
    ElementTree::new([nodes[0], nodes[1], nodes[2], nested, nodes[3], nodes[4]])
    is Err(UnsupportedAnchoredComposition),
  )
  let wrong_parent = { ..nodes[2], parent: None, }
  assert_true(
    ElementTree::new([nodes[0], nodes[1], wrong_parent])
    is Err(InvalidAnchoredShape),
  )
}
