///|
test "root box snapshot retains exact physical window metrics" {
  for scale in [1.0, 2.0, 1.5] {
    let metrics = WindowMetrics::new(10.2, 9.1, scale).unwrap()
    let size = @primitives.Size::new(10.2, 9.1).unwrap()
    let insets = @layout.Insets::new(3.0, 5.0, 7.0, 9.0).unwrap()
    let style = @layout.FlexTreeStyle::new(@layout.FlowDirection::row()).with_insets(
      insets,
      @layout.Insets::zero(),
    )
    let frame = @element.Element::root(1, style)
      .request_layout_root_box_with_device_scale(size, scale)
      .unwrap()
      .prepaint()
      .unwrap()
    assert_true(
      frame.tree().nodes()[0].bounds().size().width() > metrics.width(),
    )
    let snapshot = frame.paint_snapshot(scale).unwrap()
    assert_true(app_validate_scene(snapshot, metrics) is Ok(_))
    assert_true(
      app_validate_scene(
        snapshot,
        WindowMetrics::new(14.0, 10.0, scale).unwrap(),
      )
      is Err(_),
    )
  }
}
