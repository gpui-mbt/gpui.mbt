///|
// Assertions copied from actual GPUI run 39019813091, artifact 12096028446,
// raw.json SHA-256 1d19d7bb63f3415ef13e1aca483af83c40815f7c3669791a9d406cd82af5ae35.
// All 88 authored cases and all 264 observed frames are retained, including
// bootstrap scale 2 and both configured frames. These observations are never
// inputs to layout. The 0.000016 allowance covers f32/Double representation
// only; it is far smaller than any exercised logical/device snap difference.
fn margin_observed_close(actual : Double, observed : Double) -> Unit raise {
  assert_true((actual - observed).abs() < 0.000016)
}

///|
fn margin_root(
  anchor : @element.Anchor,
  mode : @element.AnchoredPositionMode,
  position : @primitives.Point,
  width : Double,
  height : Double,
  margin : Double?,
  interactive~ : Bool = false,
) -> @element.Element {
  let popup = anchor_popup(10, width, height, interactive)
    .with_focusable(interactive)
    .with_tab_stop(interactive)
  let attachment = match margin {
    Some(margin) =>
      @element.Element::anchored_after(
        20,
        3,
        popup,
        anchor,
        mode,
        position,
        margin~,
      ).unwrap()
    None =>
      @element.Element::anchored_after(20, 3, popup, anchor, mode, position).unwrap()
  }
  let parent = @element.Element::new(anchor_item(2, 120, 96))
    .with_children_style(
      @layout.FlexTreeStyle::new(@layout.FlowDirection::column()),
    )
    .with_child(
      @element.Element::new(anchor_item(3, 65, 120))
      .with_focusable(true)
      .with_tab_stop(true),
    )
    .with_child(attachment.deferred().unwrap())
  anchor_root(parent, 16, 16)
}

///|
fn margin_check_observed(
  anchor : @element.Anchor,
  mode : @element.AnchoredPositionMode,
  px : Double,
  py : Double,
  width : Double,
  height : Double,
  margin : Double,
  frames : Array[(Double, Double, Double, Double, Double)],
) -> Unit raise {
  let root = margin_root(
    anchor,
    mode,
    anchor_point(px, py),
    width,
    height,
    Some(margin),
  )
  assert_eq(frames.length(), 3)
  for (scale, sx, sy, x, y) in frames {
    let request = root
      .request_layout_with_device_scale(anchor_size(160, 120), scale)
      .unwrap()
    // The popup never consumes ordinary flex allocation.
    assert_eq(request.layout.items().length(), 2)
    let frame = request.prepaint().unwrap()
    let tree = frame.tree()
    let attachment = tree.node(20).unwrap().bounds()
    let popup = tree.node(10).unwrap().bounds()
    margin_observed_close(attachment.left(), sx)
    margin_observed_close(attachment.top(), sy)
    margin_observed_close(popup.left(), x)
    margin_observed_close(popup.top(), y)
    margin_observed_close(popup.size().width(), width)
    margin_observed_close(popup.size().height(), height)
    assert_eq(tree.nodes().map(node => node.id()), [1, 2, 3, 20, 10])
    assert_eq(tree.path_to_root(10).unwrap(), [1, 2, 20, 10])
    let scene = frame.paint()
    assert_true(scene.validate() is Ok(_))
    let quads = scene
      .commands()
      .filter(command => command.kind() == @scene.Quad)
    assert_eq(quads.length(), 1)
    assert_true(quads[0].bounds() == Some(popup))
    let clips = scene
      .commands()
      .filter(command => command.kind() == @scene.ClipPush)
    assert_eq(clips.length(), 2)
    for clip in clips {
      assert_true(
        clip.bounds() == Some(@primitives.Rect::new(0, 0, 160, 120).unwrap()),
      )
    }
    // Explicit zero has exactly the old omitted-option tree/scene geometry.
    if margin == 0.0 {
      let old = margin_root(
          anchor,
          mode,
          anchor_point(px, py),
          width,
          height,
          None,
        )
        .request_layout_with_device_scale(anchor_size(160, 120), scale)
        .unwrap()
        .prepaint()
        .unwrap()
      assert_true(old.paint().commands() == scene.commands())
      for node in tree.nodes() {
        assert_true(
          old.tree().node(node.id()).unwrap().bounds() == node.bounds(),
        )
      }
    }
  }
}

///|
test "margin observed cross-left-margin0-scale1" {
  margin_check_observed(
    @element.TopLeft,
    @element.Window,
    -0.25,
    48,
    40,
    24,
    0,
    [
      (2.0, 16.0, 81.0, 0.0, 48.0),
      (1.0, 16.0, 81.0, 0.0, 48.0),
      (1.0, 16.0, 81.0, 0.0, 48.0),
    ],
  )
}

///|
test "margin observed cross-left-margin0-scale1.25" {
  margin_check_observed(
    @element.TopLeft,
    @element.Window,
    -0.25,
    48,
    40,
    24,
    0,
    [
      (2.0, 16.0, 81.0, 0.0, 48.0),
      (1.25, 16.0, 80.80000305175781, 0.0, 48.000003814697266),
      (1.25, 16.0, 80.80000305175781, 0.0, 48.000003814697266),
    ],
  )
}

///|
test "margin observed cross-left-margin8-scale1" {
  margin_check_observed(
    @element.TopLeft,
    @element.Window,
    -0.25,
    48,
    40,
    24,
    8,
    [
      (2.0, 16.0, 81.0, 8.0, 48.0),
      (1.0, 16.0, 81.0, 8.0, 48.0),
      (1.0, 16.0, 81.0, 8.0, 48.0),
    ],
  )
}

///|
test "margin observed cross-left-margin8-scale1.25" {
  margin_check_observed(
    @element.TopLeft,
    @element.Window,
    -0.25,
    48,
    40,
    24,
    8,
    [
      (2.0, 16.0, 81.0, 8.0, 48.0),
      (1.25, 16.0, 80.80000305175781, 8.0, 48.000003814697266),
      (1.25, 16.0, 80.80000305175781, 8.0, 48.000003814697266),
    ],
  )
}

///|
test "margin observed cross-right-margin0-scale1" {
  margin_check_observed(
    @element.TopLeft,
    @element.Window,
    120.25,
    48,
    40,
    24,
    0,
    [
      (2.0, 16.0, 81.0, 120.0, 48.0),
      (1.0, 16.0, 81.0, 120.0, 48.0),
      (1.0, 16.0, 81.0, 120.0, 48.0),
    ],
  )
}

///|
test "margin observed cross-right-margin0-scale1.25" {
  margin_check_observed(
    @element.TopLeft,
    @element.Window,
    120.25,
    48,
    40,
    24,
    0,
    [
      (2.0, 16.0, 81.0, 120.0, 48.0),
      (1.25, 16.0, 80.80000305175781, 120.0, 48.000003814697266),
      (1.25, 16.0, 80.80000305175781, 120.0, 48.000003814697266),
    ],
  )
}

///|
test "margin observed cross-right-margin8-scale1" {
  margin_check_observed(
    @element.TopLeft,
    @element.Window,
    120.25,
    48,
    40,
    24,
    8,
    [
      (2.0, 16.0, 81.0, 112.0, 48.0),
      (1.0, 16.0, 81.0, 112.0, 48.0),
      (1.0, 16.0, 81.0, 112.0, 48.0),
    ],
  )
}

///|
test "margin observed cross-right-margin8-scale1.25" {
  margin_check_observed(
    @element.TopLeft,
    @element.Window,
    120.25,
    48,
    40,
    24,
    8,
    [
      (2.0, 16.0, 81.0, 112.0, 48.0),
      (1.25, 16.0, 80.80000305175781, 112.0, 48.000003814697266),
      (1.25, 16.0, 80.80000305175781, 112.0, 48.000003814697266),
    ],
  )
}

///|
test "margin observed cross-top-margin0-scale1" {
  margin_check_observed(
    @element.TopLeft,
    @element.Window,
    64,
    -0.25,
    40,
    24,
    0,
    [
      (2.0, 16.0, 81.0, 64.0, 0.0),
      (1.0, 16.0, 81.0, 64.0, 0.0),
      (1.0, 16.0, 81.0, 64.0, 0.0),
    ],
  )
}

///|
test "margin observed cross-top-margin0-scale1.25" {
  margin_check_observed(
    @element.TopLeft,
    @element.Window,
    64,
    -0.25,
    40,
    24,
    0,
    [
      (2.0, 16.0, 81.0, 64.0, 0.0),
      (1.25, 16.0, 80.80000305175781, 64.0, 0.0),
      (1.25, 16.0, 80.80000305175781, 64.0, 0.0),
    ],
  )
}

///|
test "margin observed cross-top-margin8-scale1" {
  margin_check_observed(
    @element.TopLeft,
    @element.Window,
    64,
    -0.25,
    40,
    24,
    8,
    [
      (2.0, 16.0, 81.0, 64.0, 8.0),
      (1.0, 16.0, 81.0, 64.0, 8.0),
      (1.0, 16.0, 81.0, 64.0, 8.0),
    ],
  )
}

///|
test "margin observed cross-top-margin8-scale1.25" {
  margin_check_observed(
    @element.TopLeft,
    @element.Window,
    64,
    -0.25,
    40,
    24,
    8,
    [
      (2.0, 16.0, 81.0, 64.0, 8.0),
      (1.25, 16.0, 80.80000305175781, 64.0, 8.0),
      (1.25, 16.0, 80.80000305175781, 64.0, 8.0),
    ],
  )
}

///|
test "margin observed cross-bottom-margin0-scale1" {
  margin_check_observed(
    @element.TopLeft,
    @element.Window,
    64,
    96.25,
    40,
    24,
    0,
    [
      (2.0, 16.0, 81.0, 64.0, 96.0),
      (1.0, 16.0, 81.0, 64.0, 96.0),
      (1.0, 16.0, 81.0, 64.0, 96.0),
    ],
  )
}

///|
test "margin observed cross-bottom-margin0-scale1.25" {
  margin_check_observed(
    @element.TopLeft,
    @element.Window,
    64,
    96.25,
    40,
    24,
    0,
    [
      (2.0, 16.0, 81.0, 64.0, 96.0),
      (1.25, 16.0, 80.80000305175781, 64.0, 96.0),
      (1.25, 16.0, 80.80000305175781, 64.0, 96.0),
    ],
  )
}

///|
test "margin observed cross-bottom-margin8-scale1" {
  margin_check_observed(
    @element.TopLeft,
    @element.Window,
    64,
    96.25,
    40,
    24,
    8,
    [
      (2.0, 16.0, 81.0, 64.0, 88.0),
      (1.0, 16.0, 81.0, 64.0, 88.0),
      (1.0, 16.0, 81.0, 64.0, 88.0),
    ],
  )
}

///|
test "margin observed cross-bottom-margin8-scale1.25" {
  margin_check_observed(
    @element.TopLeft,
    @element.Window,
    64,
    96.25,
    40,
    24,
    8,
    [
      (2.0, 16.0, 81.0, 64.0, 88.0),
      (1.25, 16.0, 80.80000305175781, 64.0, 88.0),
      (1.25, 16.0, 80.80000305175781, 64.0, 88.0),
    ],
  )
}

///|
test "margin observed inside-left-margin0-scale1" {
  margin_check_observed(@element.TopLeft, @element.Window, 0.5, 48, 40, 24, 0, [
    (2.0, 16.0, 81.0, 0.0, 48.0),
    (1.0, 16.0, 81.0, 0.0, 48.0),
    (1.0, 16.0, 81.0, 0.0, 48.0),
  ])
}

///|
test "margin observed inside-left-margin0-scale1.25" {
  margin_check_observed(@element.TopLeft, @element.Window, 0.5, 48, 40, 24, 0, [
    (2.0, 16.0, 81.0, 0.0, 48.0),
    (1.25, 16.0, 80.80000305175781, 0.0, 48.000003814697266),
    (1.25, 16.0, 80.80000305175781, 0.0, 48.000003814697266),
  ])
}

///|
test "margin observed inside-left-margin8-scale1" {
  margin_check_observed(@element.TopLeft, @element.Window, 0.5, 48, 40, 24, 8, [
    (2.0, 16.0, 81.0, 0.0, 48.0),
    (1.0, 16.0, 81.0, 0.0, 48.0),
    (1.0, 16.0, 81.0, 0.0, 48.0),
  ])
}

///|
test "margin observed inside-left-margin8-scale1.25" {
  margin_check_observed(@element.TopLeft, @element.Window, 0.5, 48, 40, 24, 8, [
    (2.0, 16.0, 81.0, 0.0, 48.0),
    (1.25, 16.0, 80.80000305175781, 0.0, 48.000003814697266),
    (1.25, 16.0, 80.80000305175781, 0.0, 48.000003814697266),
  ])
}

///|
test "margin observed inside-right-margin0-scale1" {
  margin_check_observed(
    @element.TopLeft,
    @element.Window,
    119.5,
    48,
    40,
    24,
    0,
    [
      (2.0, 16.0, 81.0, 120.0, 48.0),
      (1.0, 16.0, 81.0, 120.0, 48.0),
      (1.0, 16.0, 81.0, 120.0, 48.0),
    ],
  )
}

///|
test "margin observed inside-right-margin0-scale1.25" {
  margin_check_observed(
    @element.TopLeft,
    @element.Window,
    119.5,
    48,
    40,
    24,
    0,
    [
      (2.0, 16.0, 81.0, 120.0, 48.0),
      (1.25, 16.0, 80.80000305175781, 120.0, 48.000003814697266),
      (1.25, 16.0, 80.80000305175781, 120.0, 48.000003814697266),
    ],
  )
}

///|
test "margin observed inside-right-margin8-scale1" {
  margin_check_observed(
    @element.TopLeft,
    @element.Window,
    119.5,
    48,
    40,
    24,
    8,
    [
      (2.0, 16.0, 81.0, 120.0, 48.0),
      (1.0, 16.0, 81.0, 120.0, 48.0),
      (1.0, 16.0, 81.0, 120.0, 48.0),
    ],
  )
}

///|
test "margin observed inside-right-margin8-scale1.25" {
  margin_check_observed(
    @element.TopLeft,
    @element.Window,
    119.5,
    48,
    40,
    24,
    8,
    [
      (2.0, 16.0, 81.0, 120.0, 48.0),
      (1.25, 16.0, 80.80000305175781, 120.0, 48.000003814697266),
      (1.25, 16.0, 80.80000305175781, 120.0, 48.000003814697266),
    ],
  )
}

///|
test "margin observed inside-top-margin0-scale1" {
  margin_check_observed(@element.TopLeft, @element.Window, 64, 0.5, 40, 24, 0, [
    (2.0, 16.0, 81.0, 64.0, 0.0),
    (1.0, 16.0, 81.0, 64.0, 0.0),
    (1.0, 16.0, 81.0, 64.0, 0.0),
  ])
}

///|
test "margin observed inside-top-margin0-scale1.25" {
  margin_check_observed(@element.TopLeft, @element.Window, 64, 0.5, 40, 24, 0, [
    (2.0, 16.0, 81.0, 64.0, 0.0),
    (1.25, 16.0, 80.80000305175781, 64.0, 0.8000030517578125),
    (1.25, 16.0, 80.80000305175781, 64.0, 0.8000030517578125),
  ])
}

///|
test "margin observed inside-top-margin8-scale1" {
  margin_check_observed(@element.TopLeft, @element.Window, 64, 0.5, 40, 24, 8, [
    (2.0, 16.0, 81.0, 64.0, 0.0),
    (1.0, 16.0, 81.0, 64.0, 0.0),
    (1.0, 16.0, 81.0, 64.0, 0.0),
  ])
}

///|
test "margin observed inside-top-margin8-scale1.25" {
  margin_check_observed(@element.TopLeft, @element.Window, 64, 0.5, 40, 24, 8, [
    (2.0, 16.0, 81.0, 64.0, 0.0),
    (1.25, 16.0, 80.80000305175781, 64.0, 0.8000030517578125),
    (1.25, 16.0, 80.80000305175781, 64.0, 0.8000030517578125),
  ])
}

///|
test "margin observed inside-bottom-margin0-scale1" {
  margin_check_observed(
    @element.TopLeft,
    @element.Window,
    64,
    95.5,
    40,
    24,
    0,
    [
      (2.0, 16.0, 81.0, 64.0, 96.0),
      (1.0, 16.0, 81.0, 64.0, 96.0),
      (1.0, 16.0, 81.0, 64.0, 96.0),
    ],
  )
}

///|
test "margin observed inside-bottom-margin0-scale1.25" {
  margin_check_observed(
    @element.TopLeft,
    @element.Window,
    64,
    95.5,
    40,
    24,
    0,
    [
      (2.0, 16.0, 81.0, 64.0, 96.0),
      (1.25, 16.0, 80.80000305175781, 64.0, 96.0),
      (1.25, 16.0, 80.80000305175781, 64.0, 96.0),
    ],
  )
}

///|
test "margin observed inside-bottom-margin8-scale1" {
  margin_check_observed(
    @element.TopLeft,
    @element.Window,
    64,
    95.5,
    40,
    24,
    8,
    [
      (2.0, 16.0, 81.0, 64.0, 96.0),
      (1.0, 16.0, 81.0, 64.0, 96.0),
      (1.0, 16.0, 81.0, 64.0, 96.0),
    ],
  )
}

///|
test "margin observed inside-bottom-margin8-scale1.25" {
  margin_check_observed(
    @element.TopLeft,
    @element.Window,
    64,
    95.5,
    40,
    24,
    8,
    [
      (2.0, 16.0, 81.0, 64.0, 96.0),
      (1.25, 16.0, 80.80000305175781, 64.0, 96.0),
      (1.25, 16.0, 80.80000305175781, 64.0, 96.0),
    ],
  )
}

///|
test "margin observed exact-left-margin0-scale1" {
  margin_check_observed(@element.TopLeft, @element.Window, 0, 48, 40, 24, 0, [
    (2.0, 16.0, 81.0, 0.0, 48.0),
    (1.0, 16.0, 81.0, 0.0, 48.0),
    (1.0, 16.0, 81.0, 0.0, 48.0),
  ])
}

///|
test "margin observed exact-left-margin0-scale1.25" {
  margin_check_observed(@element.TopLeft, @element.Window, 0, 48, 40, 24, 0, [
    (2.0, 16.0, 81.0, 0.0, 48.0),
    (1.25, 16.0, 80.80000305175781, 0.0, 48.000003814697266),
    (1.25, 16.0, 80.80000305175781, 0.0, 48.000003814697266),
  ])
}

///|
test "margin observed exact-left-margin8-scale1" {
  margin_check_observed(@element.TopLeft, @element.Window, 0, 48, 40, 24, 8, [
    (2.0, 16.0, 81.0, 0.0, 48.0),
    (1.0, 16.0, 81.0, 0.0, 48.0),
    (1.0, 16.0, 81.0, 0.0, 48.0),
  ])
}

///|
test "margin observed exact-left-margin8-scale1.25" {
  margin_check_observed(@element.TopLeft, @element.Window, 0, 48, 40, 24, 8, [
    (2.0, 16.0, 81.0, 0.0, 48.0),
    (1.25, 16.0, 80.80000305175781, 0.0, 48.000003814697266),
    (1.25, 16.0, 80.80000305175781, 0.0, 48.000003814697266),
  ])
}

///|
test "margin observed exact-right-margin0-scale1" {
  margin_check_observed(@element.TopLeft, @element.Window, 120, 48, 40, 24, 0, [
    (2.0, 16.0, 81.0, 120.0, 48.0),
    (1.0, 16.0, 81.0, 120.0, 48.0),
    (1.0, 16.0, 81.0, 120.0, 48.0),
  ])
}

///|
test "margin observed exact-right-margin0-scale1.25" {
  margin_check_observed(@element.TopLeft, @element.Window, 120, 48, 40, 24, 0, [
    (2.0, 16.0, 81.0, 120.0, 48.0),
    (1.25, 16.0, 80.80000305175781, 120.0, 48.000003814697266),
    (1.25, 16.0, 80.80000305175781, 120.0, 48.000003814697266),
  ])
}

///|
test "margin observed exact-right-margin8-scale1" {
  margin_check_observed(@element.TopLeft, @element.Window, 120, 48, 40, 24, 8, [
    (2.0, 16.0, 81.0, 120.0, 48.0),
    (1.0, 16.0, 81.0, 120.0, 48.0),
    (1.0, 16.0, 81.0, 120.0, 48.0),
  ])
}

///|
test "margin observed exact-right-margin8-scale1.25" {
  margin_check_observed(@element.TopLeft, @element.Window, 120, 48, 40, 24, 8, [
    (2.0, 16.0, 81.0, 120.0, 48.0),
    (1.25, 16.0, 80.80000305175781, 120.0, 48.000003814697266),
    (1.25, 16.0, 80.80000305175781, 120.0, 48.000003814697266),
  ])
}

///|
test "margin observed exact-top-margin0-scale1" {
  margin_check_observed(@element.TopLeft, @element.Window, 64, 0, 40, 24, 0, [
    (2.0, 16.0, 81.0, 64.0, 0.0),
    (1.0, 16.0, 81.0, 64.0, 0.0),
    (1.0, 16.0, 81.0, 64.0, 0.0),
  ])
}

///|
test "margin observed exact-top-margin0-scale1.25" {
  margin_check_observed(@element.TopLeft, @element.Window, 64, 0, 40, 24, 0, [
    (2.0, 16.0, 81.0, 64.0, 0.0),
    (1.25, 16.0, 80.80000305175781, 64.0, 0.0),
    (1.25, 16.0, 80.80000305175781, 64.0, 0.0),
  ])
}

///|
test "margin observed exact-top-margin8-scale1" {
  margin_check_observed(@element.TopLeft, @element.Window, 64, 0, 40, 24, 8, [
    (2.0, 16.0, 81.0, 64.0, 0.0),
    (1.0, 16.0, 81.0, 64.0, 0.0),
    (1.0, 16.0, 81.0, 64.0, 0.0),
  ])
}

///|
test "margin observed exact-top-margin8-scale1.25" {
  margin_check_observed(@element.TopLeft, @element.Window, 64, 0, 40, 24, 8, [
    (2.0, 16.0, 81.0, 64.0, 0.0),
    (1.25, 16.0, 80.80000305175781, 64.0, 0.0),
    (1.25, 16.0, 80.80000305175781, 64.0, 0.0),
  ])
}

///|
test "margin observed exact-bottom-margin0-scale1" {
  margin_check_observed(@element.TopLeft, @element.Window, 64, 96, 40, 24, 0, [
    (2.0, 16.0, 81.0, 64.0, 96.0),
    (1.0, 16.0, 81.0, 64.0, 96.0),
    (1.0, 16.0, 81.0, 64.0, 96.0),
  ])
}

///|
test "margin observed exact-bottom-margin0-scale1.25" {
  margin_check_observed(@element.TopLeft, @element.Window, 64, 96, 40, 24, 0, [
    (2.0, 16.0, 81.0, 64.0, 96.0),
    (1.25, 16.0, 80.80000305175781, 64.0, 96.0),
    (1.25, 16.0, 80.80000305175781, 64.0, 96.0),
  ])
}

///|
test "margin observed exact-bottom-margin8-scale1" {
  margin_check_observed(@element.TopLeft, @element.Window, 64, 96, 40, 24, 8, [
    (2.0, 16.0, 81.0, 64.0, 96.0),
    (1.0, 16.0, 81.0, 64.0, 96.0),
    (1.0, 16.0, 81.0, 64.0, 96.0),
  ])
}

///|
test "margin observed exact-bottom-margin8-scale1.25" {
  margin_check_observed(@element.TopLeft, @element.Window, 64, 96, 40, 24, 8, [
    (2.0, 16.0, 81.0, 64.0, 96.0),
    (1.25, 16.0, 80.80000305175781, 64.0, 96.0),
    (1.25, 16.0, 80.80000305175781, 64.0, 96.0),
  ])
}

///|
test "margin observed corner-top-left-margin0-scale1" {
  margin_check_observed(
    @element.TopLeft,
    @element.Window,
    -0.25,
    -0.25,
    40,
    24,
    0,
    [
      (2.0, 16.0, 81.0, 0.0, 0.0),
      (1.0, 16.0, 81.0, 0.0, 0.0),
      (1.0, 16.0, 81.0, 0.0, 0.0),
    ],
  )
}

///|
test "margin observed corner-top-left-margin0-scale1.25" {
  margin_check_observed(
    @element.TopLeft,
    @element.Window,
    -0.25,
    -0.25,
    40,
    24,
    0,
    [
      (2.0, 16.0, 81.0, 0.0, 0.0),
      (1.25, 16.0, 80.80000305175781, 0.0, 0.0),
      (1.25, 16.0, 80.80000305175781, 0.0, 0.0),
    ],
  )
}

///|
test "margin observed corner-top-left-margin8-scale1" {
  margin_check_observed(
    @element.TopLeft,
    @element.Window,
    -0.25,
    -0.25,
    40,
    24,
    8,
    [
      (2.0, 16.0, 81.0, 8.0, 8.0),
      (1.0, 16.0, 81.0, 8.0, 8.0),
      (1.0, 16.0, 81.0, 8.0, 8.0),
    ],
  )
}

///|
test "margin observed corner-top-left-margin8-scale1.25" {
  margin_check_observed(
    @element.TopLeft,
    @element.Window,
    -0.25,
    -0.25,
    40,
    24,
    8,
    [
      (2.0, 16.0, 81.0, 8.0, 8.0),
      (1.25, 16.0, 80.80000305175781, 8.0, 8.0),
      (1.25, 16.0, 80.80000305175781, 8.0, 8.0),
    ],
  )
}

///|
test "margin observed corner-top-right-margin0-scale1" {
  margin_check_observed(
    @element.TopLeft,
    @element.Window,
    120.25,
    -0.25,
    40,
    24,
    0,
    [
      (2.0, 16.0, 81.0, 120.0, 0.0),
      (1.0, 16.0, 81.0, 120.0, 0.0),
      (1.0, 16.0, 81.0, 120.0, 0.0),
    ],
  )
}

///|
test "margin observed corner-top-right-margin0-scale1.25" {
  margin_check_observed(
    @element.TopLeft,
    @element.Window,
    120.25,
    -0.25,
    40,
    24,
    0,
    [
      (2.0, 16.0, 81.0, 120.0, 0.0),
      (1.25, 16.0, 80.80000305175781, 120.0, 0.0),
      (1.25, 16.0, 80.80000305175781, 120.0, 0.0),
    ],
  )
}

///|
test "margin observed corner-top-right-margin8-scale1" {
  margin_check_observed(
    @element.TopLeft,
    @element.Window,
    120.25,
    -0.25,
    40,
    24,
    8,
    [
      (2.0, 16.0, 81.0, 112.0, 8.0),
      (1.0, 16.0, 81.0, 112.0, 8.0),
      (1.0, 16.0, 81.0, 112.0, 8.0),
    ],
  )
}

///|
test "margin observed corner-top-right-margin8-scale1.25" {
  margin_check_observed(
    @element.TopLeft,
    @element.Window,
    120.25,
    -0.25,
    40,
    24,
    8,
    [
      (2.0, 16.0, 81.0, 112.0, 8.0),
      (1.25, 16.0, 80.80000305175781, 112.0, 8.0),
      (1.25, 16.0, 80.80000305175781, 112.0, 8.0),
    ],
  )
}

///|
test "margin observed corner-bottom-left-margin0-scale1" {
  margin_check_observed(
    @element.TopLeft,
    @element.Window,
    -0.25,
    96.25,
    40,
    24,
    0,
    [
      (2.0, 16.0, 81.0, 0.0, 96.0),
      (1.0, 16.0, 81.0, 0.0, 96.0),
      (1.0, 16.0, 81.0, 0.0, 96.0),
    ],
  )
}

///|
test "margin observed corner-bottom-left-margin0-scale1.25" {
  margin_check_observed(
    @element.TopLeft,
    @element.Window,
    -0.25,
    96.25,
    40,
    24,
    0,
    [
      (2.0, 16.0, 81.0, 0.0, 96.0),
      (1.25, 16.0, 80.80000305175781, 0.0, 96.0),
      (1.25, 16.0, 80.80000305175781, 0.0, 96.0),
    ],
  )
}

///|
test "margin observed corner-bottom-left-margin8-scale1" {
  margin_check_observed(
    @element.TopLeft,
    @element.Window,
    -0.25,
    96.25,
    40,
    24,
    8,
    [
      (2.0, 16.0, 81.0, 8.0, 88.0),
      (1.0, 16.0, 81.0, 8.0, 88.0),
      (1.0, 16.0, 81.0, 8.0, 88.0),
    ],
  )
}

///|
test "margin observed corner-bottom-left-margin8-scale1.25" {
  margin_check_observed(
    @element.TopLeft,
    @element.Window,
    -0.25,
    96.25,
    40,
    24,
    8,
    [
      (2.0, 16.0, 81.0, 8.0, 88.0),
      (1.25, 16.0, 80.80000305175781, 8.0, 88.0),
      (1.25, 16.0, 80.80000305175781, 8.0, 88.0),
    ],
  )
}

///|
test "margin observed corner-bottom-right-margin0-scale1" {
  margin_check_observed(
    @element.TopLeft,
    @element.Window,
    120.25,
    96.25,
    40,
    24,
    0,
    [
      (2.0, 16.0, 81.0, 120.0, 96.0),
      (1.0, 16.0, 81.0, 120.0, 96.0),
      (1.0, 16.0, 81.0, 120.0, 96.0),
    ],
  )
}

///|
test "margin observed corner-bottom-right-margin0-scale1.25" {
  margin_check_observed(
    @element.TopLeft,
    @element.Window,
    120.25,
    96.25,
    40,
    24,
    0,
    [
      (2.0, 16.0, 81.0, 120.0, 96.0),
      (1.25, 16.0, 80.80000305175781, 120.0, 96.0),
      (1.25, 16.0, 80.80000305175781, 120.0, 96.0),
    ],
  )
}

///|
test "margin observed corner-bottom-right-margin8-scale1" {
  margin_check_observed(
    @element.TopLeft,
    @element.Window,
    120.25,
    96.25,
    40,
    24,
    8,
    [
      (2.0, 16.0, 81.0, 112.0, 88.0),
      (1.0, 16.0, 81.0, 112.0, 88.0),
      (1.0, 16.0, 81.0, 112.0, 88.0),
    ],
  )
}

///|
test "margin observed corner-bottom-right-margin8-scale1.25" {
  margin_check_observed(
    @element.TopLeft,
    @element.Window,
    120.25,
    96.25,
    40,
    24,
    8,
    [
      (2.0, 16.0, 81.0, 112.0, 88.0),
      (1.25, 16.0, 80.80000305175781, 112.0, 88.0),
      (1.25, 16.0, 80.80000305175781, 112.0, 88.0),
    ],
  )
}

///|
test "margin observed oversized-horizontal-margin0-scale1" {
  margin_check_observed(@element.TopLeft, @element.Window, 40, 48, 200, 24, 0, [
    (2.0, 16.0, 81.0, 0.0, 48.0),
    (1.0, 16.0, 81.0, 0.0, 48.0),
    (1.0, 16.0, 81.0, 0.0, 48.0),
  ])
}

///|
test "margin observed oversized-horizontal-margin0-scale1.25" {
  margin_check_observed(@element.TopLeft, @element.Window, 40, 48, 200, 24, 0, [
    (2.0, 16.0, 81.0, 0.0, 48.0),
    (1.25, 16.0, 80.80000305175781, 0.0, 48.000003814697266),
    (1.25, 16.0, 80.80000305175781, 0.0, 48.000003814697266),
  ])
}

///|
test "margin observed oversized-horizontal-margin8-scale1" {
  margin_check_observed(@element.TopLeft, @element.Window, 40, 48, 200, 24, 8, [
    (2.0, 16.0, 81.0, 8.0, 48.0),
    (1.0, 16.0, 81.0, 8.0, 48.0),
    (1.0, 16.0, 81.0, 8.0, 48.0),
  ])
}

///|
test "margin observed oversized-horizontal-margin8-scale1.25" {
  margin_check_observed(@element.TopLeft, @element.Window, 40, 48, 200, 24, 8, [
    (2.0, 16.0, 81.0, 8.0, 48.0),
    (1.25, 16.0, 80.80000305175781, 8.0, 48.000003814697266),
    (1.25, 16.0, 80.80000305175781, 8.0, 48.000003814697266),
  ])
}

///|
test "margin observed oversized-vertical-margin0-scale1" {
  margin_check_observed(@element.TopLeft, @element.Window, 64, 40, 40, 160, 0, [
    (2.0, 16.0, 81.0, 64.0, 0.0),
    (1.0, 16.0, 81.0, 64.0, 0.0),
    (1.0, 16.0, 81.0, 64.0, 0.0),
  ])
}

///|
test "margin observed oversized-vertical-margin0-scale1.25" {
  margin_check_observed(@element.TopLeft, @element.Window, 64, 40, 40, 160, 0, [
    (2.0, 16.0, 81.0, 64.0, 0.0),
    (1.25, 16.0, 80.80000305175781, 64.0, 0.0),
    (1.25, 16.0, 80.80000305175781, 64.0, 0.0),
  ])
}

///|
test "margin observed oversized-vertical-margin8-scale1" {
  margin_check_observed(@element.TopLeft, @element.Window, 64, 40, 40, 160, 8, [
    (2.0, 16.0, 81.0, 64.0, 8.0),
    (1.0, 16.0, 81.0, 64.0, 8.0),
    (1.0, 16.0, 81.0, 64.0, 8.0),
  ])
}

///|
test "margin observed oversized-vertical-margin8-scale1.25" {
  margin_check_observed(@element.TopLeft, @element.Window, 64, 40, 40, 160, 8, [
    (2.0, 16.0, 81.0, 64.0, 8.0),
    (1.25, 16.0, 80.80000305175781, 64.0, 8.0),
    (1.25, 16.0, 80.80000305175781, 64.0, 8.0),
  ])
}

///|
test "margin observed oversized-both-margin0-scale1" {
  margin_check_observed(
    @element.TopLeft,
    @element.Window,
    40,
    40,
    200,
    160,
    0,
    [
      (2.0, 16.0, 81.0, 0.0, 0.0),
      (1.0, 16.0, 81.0, 0.0, 0.0),
      (1.0, 16.0, 81.0, 0.0, 0.0),
    ],
  )
}

///|
test "margin observed oversized-both-margin0-scale1.25" {
  margin_check_observed(
    @element.TopLeft,
    @element.Window,
    40,
    40,
    200,
    160,
    0,
    [
      (2.0, 16.0, 81.0, 0.0, 0.0),
      (1.25, 16.0, 80.80000305175781, 0.0, 0.0),
      (1.25, 16.0, 80.80000305175781, 0.0, 0.0),
    ],
  )
}

///|
test "margin observed oversized-both-margin8-scale1" {
  margin_check_observed(
    @element.TopLeft,
    @element.Window,
    40,
    40,
    200,
    160,
    8,
    [
      (2.0, 16.0, 81.0, 8.0, 8.0),
      (1.0, 16.0, 81.0, 8.0, 8.0),
      (1.0, 16.0, 81.0, 8.0, 8.0),
    ],
  )
}

///|
test "margin observed oversized-both-margin8-scale1.25" {
  margin_check_observed(
    @element.TopLeft,
    @element.Window,
    40,
    40,
    200,
    160,
    8,
    [
      (2.0, 16.0, 81.0, 8.0, 8.0),
      (1.25, 16.0, 80.80000305175781, 8.0, 8.0),
      (1.25, 16.0, 80.80000305175781, 8.0, 8.0),
    ],
  )
}

///|
test "margin observed margin-induced-opposite-crossing-margin0-scale1" {
  margin_check_observed(
    @element.TopLeft,
    @element.Window,
    10,
    10,
    156,
    116,
    0,
    [
      (2.0, 16.0, 81.0, 4.0, 4.0),
      (1.0, 16.0, 81.0, 4.0, 4.0),
      (1.0, 16.0, 81.0, 4.0, 4.0),
    ],
  )
}

///|
test "margin observed margin-induced-opposite-crossing-margin0-scale1.25" {
  margin_check_observed(
    @element.TopLeft,
    @element.Window,
    10,
    10,
    156,
    116,
    0,
    [
      (2.0, 16.0, 81.0, 4.0, 4.0),
      (1.25, 16.0, 80.80000305175781, 4.0, 4.0),
      (1.25, 16.0, 80.80000305175781, 4.0, 4.0),
    ],
  )
}

///|
test "margin observed margin-induced-opposite-crossing-margin8-scale1" {
  margin_check_observed(
    @element.TopLeft,
    @element.Window,
    10,
    10,
    156,
    116,
    8,
    [
      (2.0, 16.0, 81.0, 8.0, 8.0),
      (1.0, 16.0, 81.0, 8.0, 8.0),
      (1.0, 16.0, 81.0, 8.0, 8.0),
    ],
  )
}

///|
test "margin observed margin-induced-opposite-crossing-margin8-scale1.25" {
  margin_check_observed(
    @element.TopLeft,
    @element.Window,
    10,
    10,
    156,
    116,
    8,
    [
      (2.0, 16.0, 81.0, 8.0, 8.0),
      (1.25, 16.0, 80.80000305175781, 8.0, 8.0),
      (1.25, 16.0, 80.80000305175781, 8.0, 8.0),
    ],
  )
}

///|
test "margin observed half-local-positive-margin0-scale1" {
  margin_check_observed(@element.TopLeft, @element.Local, 0.5, 0.5, 40, 24, 0, [
    (2.0, 16.0, 81.0, 17.0, 82.0),
    (1.0, 16.0, 81.0, 17.0, 82.0),
    (1.0, 16.0, 81.0, 17.0, 82.0),
  ])
}

///|
test "margin observed half-local-positive-margin0-scale1.25" {
  margin_check_observed(@element.TopLeft, @element.Local, 0.5, 0.5, 40, 24, 0, [
    (2.0, 16.0, 81.0, 17.0, 82.0),
    (1.25, 16.0, 80.80000305175781, 16.799999237060547, 81.60000610351562),
    (1.25, 16.0, 80.80000305175781, 16.799999237060547, 81.60000610351562),
  ])
}

///|
test "margin observed half-local-positive-margin8-scale1" {
  margin_check_observed(@element.TopLeft, @element.Local, 0.5, 0.5, 40, 24, 8, [
    (2.0, 16.0, 81.0, 17.0, 82.0),
    (1.0, 16.0, 81.0, 17.0, 82.0),
    (1.0, 16.0, 81.0, 17.0, 82.0),
  ])
}

///|
test "margin observed half-local-positive-margin8-scale1.25" {
  margin_check_observed(@element.TopLeft, @element.Local, 0.5, 0.5, 40, 24, 8, [
    (2.0, 16.0, 81.0, 17.0, 82.0),
    (1.25, 16.0, 80.80000305175781, 16.799999237060547, 81.60000610351562),
    (1.25, 16.0, 80.80000305175781, 16.799999237060547, 81.60000610351562),
  ])
}

///|
test "margin observed half-local-negative-margin0-scale1" {
  margin_check_observed(
    @element.BottomRight,
    @element.Local,
    39.5,
    23.5,
    40,
    24,
    0,
    [
      (2.0, 16.0, 81.0, 15.0, 80.0),
      (1.0, 16.0, 81.0, 15.0, 80.0),
      (1.0, 16.0, 81.0, 15.0, 80.0),
    ],
  )
}

///|
test "margin observed half-local-negative-margin0-scale1.25" {
  margin_check_observed(
    @element.BottomRight,
    @element.Local,
    39.5,
    23.5,
    40,
    24,
    0,
    [
      (2.0, 16.0, 81.0, 15.0, 80.0),
      (1.25, 16.0, 80.80000305175781, 15.199999809265137, 80.0),
      (1.25, 16.0, 80.80000305175781, 15.199999809265137, 80.0),
    ],
  )
}

///|
test "margin observed half-local-negative-margin8-scale1" {
  margin_check_observed(
    @element.BottomRight,
    @element.Local,
    39.5,
    23.5,
    40,
    24,
    8,
    [
      (2.0, 16.0, 81.0, 15.0, 80.0),
      (1.0, 16.0, 81.0, 15.0, 80.0),
      (1.0, 16.0, 81.0, 15.0, 80.0),
    ],
  )
}

///|
test "margin observed half-local-negative-margin8-scale1.25" {
  margin_check_observed(
    @element.BottomRight,
    @element.Local,
    39.5,
    23.5,
    40,
    24,
    8,
    [
      (2.0, 16.0, 81.0, 15.0, 80.0),
      (1.25, 16.0, 80.80000305175781, 15.199999809265137, 80.0),
      (1.25, 16.0, 80.80000305175781, 15.199999809265137, 80.0),
    ],
  )
}

///|
test "margin rejects negative and nonfinite input before layout" {
  for
    invalid in [
      -0.25, @double.not_a_number, @double.infinity, @double.neg_infinity,
    ] {
    assert_true(
      @element.Element::anchored_after(
        20,
        3,
        anchor_popup(10, 40, 24, false),
        @element.TopLeft,
        @element.Window,
        anchor_point(40, 40),
        margin=invalid,
      )
      is Err(@element.GeometryFailure),
    )
  }
  // Zero, signed zero, fractions and finite margins larger than the viewport
  // are valid scalar options. An unused large margin must not inset a popup.
  for margin in [0.0, -0.0, 0.5, 200.0, @double.max_value] {
    let frame = margin_root(
        @element.TopLeft,
        @element.Window,
        anchor_point(40, 40),
        40,
        24,
        Some(margin),
      )
      .request_layout(anchor_size(160, 120))
      .unwrap()
      .prepaint()
      .unwrap()
    anchor_assert_point(
      frame.tree().node(10).unwrap().bounds().origin(),
      anchor_point(40, 40),
    )
  }
}

///|
test "margin all anchors correct crossed edges without changing coordinate modes" {
  for
    (anchor, x, y) in [
      (@element.TopLeft, -1.0, -1.0),
      (@element.TopCenter, 19.0, -1.0),
      (@element.TopRight, 39.0, -1.0),
      (@element.LeftCenter, -1.0, 11.0),
      (@element.RightCenter, 39.0, 11.0),
      (@element.BottomLeft, -1.0, 23.0),
      (@element.BottomCenter, 19.0, 23.0),
      (@element.BottomRight, 39.0, 23.0),
    ] {
    for
      (mode, dx, dy) in [
        (@element.Window, 0.0, 0.0),
        (@element.Local, -16.0, -81.0),
      ] {
      let frame = margin_root(
          anchor,
          mode,
          anchor_point(x + dx, y + dy),
          40,
          24,
          Some(8),
        )
        .request_layout(anchor_size(160, 120))
        .unwrap()
        .prepaint()
        .unwrap()
      anchor_assert_point(
        frame.tree().node(10).unwrap().bounds().origin(),
        anchor_point(8, 8),
      )
    }
  }
}

///|
test "margin has no iteration when a finite margin exceeds the viewport" {
  // A right correction crosses left; the later left correction wins even
  // though its result crosses right again. Same contract for bottom/top.
  let frame = margin_root(
      @element.TopLeft,
      @element.Window,
      anchor_point(121, 97),
      40,
      24,
      Some(200),
    )
    .request_layout(anchor_size(160, 120))
    .unwrap()
    .prepaint()
    .unwrap()
  anchor_assert_point(
    frame.tree().node(10).unwrap().bounds().origin(),
    anchor_point(200, 200),
  )
  assert_true(frame.overflow())
  assert_true(frame.paint().validate() is Ok(_))
  assert_true(frame.tree().hit_test(anchor_point(210, 210)) is None)
}

///|
test "margin preserves clipped hits focus refresh and immutable removal" {
  for scale in [1.0, 1.25] {
    let root = margin_root(
      @element.TopLeft,
      @element.Window,
      anchor_point(80, 60),
      240,
      160,
      Some(8),
      interactive=true,
    )
    let frame = root
      .request_layout_with_device_scale(anchor_size(160, 120), scale)
      .unwrap()
      .prepaint()
      .unwrap()
    let tree = frame.tree().with_focus(10).unwrap()
    let popup = tree.node(10).unwrap().bounds()
    anchor_assert_point(popup.origin(), anchor_point(8, 8))
    assert_true(tree.hit_test(anchor_point(8, 8)) == Some(10))
    assert_true(tree.hit_test(anchor_point(7.9, 8)) != Some(10))
    assert_true(tree.hit_test(anchor_point(159.9, 119.9)) == Some(10))
    for
      point in [
        anchor_point(160, 119),
        anchor_point(159, 120),
        anchor_point(-0.1, 0),
      ] {
      assert_true(tree.hit_test(point) is None)
    }
    assert_eq(tree.dispatch_pointer(anchor_point(8, 8)).capture(), [
      1, 2, 20, 10,
    ])
    let snapshot = frame.paint_snapshot(scale).unwrap()
    assert_eq(snapshot.items().length(), 1)
    assert_true(snapshot.items()[0].clip_chain_id() is Some(_))
    for chain in snapshot.clip_chains() {
      for rect in chain.rects() {
        assert_true(rect == @primitives.Rect::new(0, 0, 160, 120).unwrap())
      }
    }
    // Margin changes geometry only. Compatible refresh retains focus identity.
    let moved = margin_root(
        @element.TopLeft,
        @element.Window,
        anchor_point(80, 60),
        240,
        160,
        Some(16),
        interactive=true,
      )
      .request_layout_with_device_scale(anchor_size(160, 120), scale)
      .unwrap()
      .prepaint()
      .unwrap()
    let refreshed = tree.with_layout_bounds(moved).unwrap()
    assert_true(refreshed.focus_owner() == tree.focus_owner())
    assert_true(refreshed.hit_test(anchor_point(8, 8)) != Some(10))
    assert_true(refreshed.hit_test(anchor_point(16, 16)) == Some(10))
    assert_true(tree.node(10).unwrap().bounds() == popup)
    let focused_reference = refreshed.with_focus(3).unwrap()
    assert_true(
      focused_reference.without_subtree(3) is Err(@element.InvalidAnchoredShape),
    )
    let removed = focused_reference.without_subtree(20).unwrap()
    assert_true(removed.node(10) is None)
    assert_true(removed.node(3) is Some(_))
    assert_true(removed.focus_owner() == focused_reference.focus_owner())
  }
}

///|
test "margin does not admit unsupported nesting dynamic content or wrapper input" {
  let popup = anchor_popup(10, 40, 24, false)
  let nested = @element.Element::anchored_after(
    20,
    3,
    popup,
    @element.TopLeft,
    @element.Window,
    anchor_point(0, 0),
    margin=8,
  ).unwrap()
  assert_true(
    @element.Element::anchored_after(
      21,
      3,
      nested,
      @element.TopLeft,
      @element.Window,
      anchor_point(0, 0),
      margin=8,
    )
    is Err(@element.UnsupportedAnchoredComposition),
  )
  let queried = popup.with_container_query(_ => {
    abort("margin must not invoke an unsupported query")
  })
  assert_true(
    @element.Element::anchored_after(
      20,
      3,
      queried,
      @element.TopLeft,
      @element.Window,
      anchor_point(0, 0),
      margin=8,
    )
    is Err(@element.UnsupportedAnchoredComposition),
  )
  let scrolling = popup.with_scroll_offset(anchor_point(0, 0))
  assert_true(
    @element.Element::anchored_after(
      20,
      3,
      scrolling,
      @element.TopLeft,
      @element.Window,
      anchor_point(0, 0),
      margin=8,
    )
    is Err(@element.UnsupportedAnchoredComposition),
  )
  assert_true(
    anchor_root(
      anchor_parent().with_child(nested.with_pointer_events(true)),
      0,
      0,
    ).request_layout(anchor_size(160, 120))
    is Err(@element.InvalidAnchoredShape),
  )
  assert_true(
    nested.deferred().unwrap().deferred()
    is Err(@element.UnsupportedAnchoredComposition),
  )
}
