///|
// These tests only use public APIs: painting is interleaved with real input,
// while an independently constructed control follows the same unpainted trace.
fn palette_trace_color(index : Int32) -> @primitives.Color {
  @primitives.Color::rgba(index, 30 + index, 90 + index, 120 + index).unwrap()
}

///|
fn palette_trace_palette() -> @button.ButtonPaintPalette {
  @button.ButtonPaintPalette::new(
    normal_border=palette_trace_color(1),
    focused_border=palette_trace_color(2),
    disabled_border=palette_trace_color(3),
    normal_fill=palette_trace_color(4),
    hovered_fill=palette_trace_color(5),
    pressed_fill=palette_trace_color(6),
    loading_fill=palette_trace_color(7),
    disabled_fill=palette_trace_color(8),
    enabled_foreground=palette_trace_color(9),
    disabled_foreground=palette_trace_color(10),
  )
}

///|
fn palette_trace_json(items : Array[@scene.SceneItem]) -> String {
  @scene.SceneSnapshot::new(
    button_test_rect(0.0, 0.0, 400.0, 300.0),
    1.0,
    [],
    [],
    items,
  )
  .unwrap()
  .canonical_json()
}

///|
fn palette_trace_tree(button : @button.Button) -> @element.ElementTree {
  let tree = @element.ElementTree::new([
    @element.ElementNode::new(
      1UL,
      None,
      button_test_rect(0.0, 0.0, 400.0, 300.0),
    ),
    button.element_node(Some(1UL)),
  ]).unwrap()
  if button.is_focused() {
    tree.with_focus(button.id()).unwrap()
  } else {
    tree
  }
}

///|
fn palette_trace_assert_state(
  actual : @button.Button,
  control : @button.Button,
) -> Unit raise {
  assert_eq(actual.id(), control.id())
  assert_eq(actual.label(), control.label())
  assert_true(actual.bounds() == control.bounds())
  assert_eq(actual.is_enabled(), control.is_enabled())
  assert_eq(actual.is_loading(), control.is_loading())
  assert_eq(actual.is_focused(), control.is_focused())
  assert_eq(actual.is_hovered(), control.is_hovered())
  assert_eq(actual.is_pressed(), control.is_pressed())
  assert_eq(actual.can_activate(), control.can_activate())
  for parent in [None, Some(1UL)] {
    let left = actual.element_node(parent)
    let right = control.element_node(parent)
    assert_eq(left.id(), right.id())
    assert_eq(left.parent(), right.parent())
    assert_true(left.bounds() == right.bounds())
    assert_eq(left.is_focusable(), right.is_focusable())
    assert_eq(left.accepts_pointer_events(), right.accepts_pointer_events())
    assert_eq(left.is_tab_stop(), right.is_tab_stop())
    assert_eq(left.tab_index(), right.tab_index())
    assert_eq(left.tab_group_index(), right.tab_group_index())
    assert_true(left.background() == right.background())
  }
  let actual_tree = palette_trace_tree(actual)
  let control_tree = palette_trace_tree(control)
  assert_eq(actual_tree.focused(), control_tree.focused())
  for
    point in [
      button_test_point(40.0, 50.0),
      button_test_point(270.0, 150.0),
      button_test_point(390.0, 290.0),
    ] {
    assert_eq(actual_tree.hit_test(point), control_tree.hit_test(point))
    let left = actual_tree.dispatch_pointer(point)
    let right = control_tree.dispatch_pointer(point)
    assert_eq(left.target(), right.target())
    assert_eq(left.capture(), right.capture())
    assert_eq(left.bubble(), right.bubble())
  }
  let event = button_test_key_down(@primitives.Space, false)
  let left = actual_tree.dispatch_input(event)
  let right = control_tree.dispatch_input(event)
  assert_eq(left.target(), right.target())
  assert_eq(left.capture(), right.capture())
  assert_eq(left.bubble(), right.bubble())
}

///|
fn palette_trace_paint(button : @button.Button) -> Unit raise {
  let palette = palette_trace_palette()
  let first = button.paint_items_with_palette(700UL, palette).unwrap()
  let again = button.paint_items_with_palette(700UL, palette).unwrap()
  assert_eq(palette_trace_json(first), palette_trace_json(again))
  assert_eq(
    palette_trace_json(button.paint_items(700UL).unwrap()),
    palette_trace_json(
      button
      .paint_items_with_palette(700UL, @button.ButtonPaintPalette::standard())
      .unwrap(),
    ),
  )
  assert_eq(first.length(), 3)
  let border = if !button.is_enabled() {
    3
  } else if button.is_focused() {
    2
  } else {
    1
  }
  let fill = if !button.is_enabled() {
    8
  } else if button.is_loading() {
    7
  } else if button.is_pressed() {
    6
  } else if button.is_hovered() {
    5
  } else {
    4
  }
  let foreground = if button.is_enabled() { 9 } else { 10 }
  let inset = if button.is_focused() { 2.0 } else { 1.0 }
  let bounds = button.bounds()
  match first[0] {
    @scene.QuadItem(id=700, bounds=painted_bounds, color~, ..) => {
      assert_true(painted_bounds == bounds)
      assert_true(color == palette_trace_color(border))
    }
    _ => fail("palette trace must retain the border item")
  }
  match first[1] {
    @scene.QuadItem(id=701, bounds=painted_bounds, color~, ..) => {
      assert_true(
        painted_bounds ==
        button_test_rect(
          bounds.left() + inset,
          bounds.top() + inset,
          bounds.size().width() - 2.0 * inset,
          bounds.size().height() - 2.0 * inset,
        ),
      )
      assert_true(color == palette_trace_color(fill))
    }
    _ => fail("palette trace must retain the fill item")
  }
  match first[2] {
    @scene.TextItem(id=702, text~, color~, font_size=16.0, ..) => {
      assert_eq(text, button.label())
      assert_true(color == palette_trace_color(foreground))
    }
    _ => fail("palette trace must retain real label text")
  }
}

///|
enum PaletteTraceStep {
  Input(@primitives.InputEvent, Bool, Bool, Bool)
  Focus(Bool)
  Enabled(Bool)
  Loading(Bool)
  Cancel
  Bounds(@primitives.Rect)
}

///|
fn palette_trace_run(steps : Array[PaletteTraceStep]) -> Unit raise {
  let mut painted = button_test_button()
  let mut control = button_test_button()
  for step in steps {
    palette_trace_assert_state(painted, control)
    palette_trace_paint(painted)
    palette_trace_assert_state(painted, control)
    match step {
      Input(event, consumed, activated, pressed) => {
        let (next_painted, actual) = painted.handle_input(event)
        let (next_control, expected) = control.handle_input(event)
        assert_eq(actual.consumed(), expected.consumed())
        assert_true(actual.effect() == expected.effect())
        assert_eq(actual.consumed(), consumed)
        assert_eq(actual.effect() is @button.Activated, activated)
        assert_eq(next_painted.is_pressed(), pressed)
        painted = next_painted
        control = next_control
      }
      Focus(value) => {
        painted = painted.with_focus(value)
        control = control.with_focus(value)
      }
      Enabled(value) => {
        painted = painted.with_enabled(value)
        control = control.with_enabled(value)
      }
      Loading(value) => {
        painted = painted.with_loading(value)
        control = control.with_loading(value)
      }
      Cancel => {
        painted = painted.cancel_press()
        control = control.cancel_press()
      }
      Bounds(value) => {
        painted = painted.with_bounds(value).unwrap()
        control = control.with_bounds(value).unwrap()
      }
    }
    palette_trace_paint(painted)
    palette_trace_assert_state(painted, control)
  }
}

///|
test "palette painting preserves pointer traces cancellation and bounds routing" {
  let down = button_test_pointer(true, 40.0, 50.0, true)
  let up = button_test_pointer(false, 40.0, 50.0, true)
  palette_trace_run([
    Input(
      @primitives.PointerMoved(position=button_test_point(40.0, 50.0)),
      false,
      false,
      false,
    ),
    Input(down, true, false, true),
    Input(down, true, false, true),
    Input(
      @primitives.PointerMoved(position=button_test_point(390.0, 290.0)),
      false,
      false,
      true,
    ),
    Input(button_test_pointer(false, 390.0, 290.0, true), true, false, false),
    Input(up, false, false, false),
    Input(button_test_pointer(true, 390.0, 290.0, true), false, false, false),
    Input(up, false, false, false),
    Input(button_test_pointer(true, 40.0, 50.0, false), false, false, false),
    Input(button_test_pointer(false, 40.0, 50.0, false), false, false, false),
    Input(down, true, false, true),
    Input(up, true, true, false),
    Input(up, false, false, false),
    Input(down, true, false, true),
    Cancel,
    Input(up, false, false, false),
    Focus(true),
    Input(down, true, false, true),
    Focus(false),
    Input(up, false, false, false),
    Input(down, true, false, true),
    Bounds(button_test_rect(250.0, 130.0, 100.0, 50.0)),
    Input(up, false, false, false),
    Input(down, false, false, false),
    Input(button_test_pointer(true, 270.0, 150.0, true), true, false, true),
    Input(button_test_pointer(false, 270.0, 150.0, true), true, true, false),
  ])
}

///|
test "palette painting preserves keyboard repeat matching release and focus latches" {
  let enter = button_test_key_down(@primitives.Enter, false)
  let enter_repeat = button_test_key_down(@primitives.Enter, true)
  let enter_up = button_test_key_up(@primitives.Enter)
  let space = button_test_key_down(@primitives.Space, false)
  let space_repeat = button_test_key_down(@primitives.Space, true)
  let space_up = button_test_key_up(@primitives.Space)
  palette_trace_run([
    Input(enter, false, false, false),
    Input(space, false, false, false),
    Focus(true),
    Input(enter, true, true, true),
    Input(enter_repeat, true, false, true),
    Input(enter, true, false, true),
    Input(space_up, true, false, true),
    Input(enter_up, true, false, false),
    Input(enter_repeat, true, false, false),
    Input(space, true, false, true),
    Input(space_repeat, true, false, true),
    Input(enter_up, true, false, true),
    Input(space_up, true, true, false),
    Input(space_up, true, false, false),
    Input(space, true, false, true),
    Focus(false),
    Focus(true),
    Input(space_repeat, true, false, false),
    Input(space_up, true, false, false),
    Input(enter, true, true, true),
    Cancel,
    Input(enter_repeat, true, false, false),
    Input(enter_up, true, false, false),
    Input(space, true, false, true),
    Input(space_up, true, true, false),
  ])
}

///|
test "palette painting preserves loading disabling and stale gesture rejection" {
  let down = button_test_pointer(true, 40.0, 50.0, true)
  let up = button_test_pointer(false, 40.0, 50.0, true)
  let space = button_test_key_down(@primitives.Space, false)
  let space_up = button_test_key_up(@primitives.Space)
  palette_trace_run([
    Focus(true),
    Input(down, true, false, true),
    Enabled(false),
    Focus(true),
    Input(up, false, false, false),
    Input(space, false, false, false),
    Input(down, true, false, false),
    Enabled(true),
    Input(up, false, false, false),
    Focus(true),
    Input(space, true, false, true),
    Loading(true),
    Input(space_up, true, false, false),
    Input(space, true, false, false),
    Input(down, true, false, false),
    Input(
      @primitives.PointerMoved(position=button_test_point(40.0, 50.0)),
      false,
      false,
      false,
    ),
    Enabled(false),
    Enabled(true),
    Focus(true),
    Input(space, true, false, false),
    Loading(false),
    Input(space_up, true, false, false),
    Input(down, true, false, true),
    Loading(true),
    Loading(false),
    Input(up, false, false, false),
    Input(space, true, false, true),
    Input(space_up, true, true, false),
  ])
}

///|
test "both paint entry points preserve label and item ID boundaries" {
  let palette = palette_trace_palette()
  let maximum = 18446744073709551612UL
  for label in ["", String::from_array(Array::make(65536, 'x'))] {
    let button = @button.Button::new(
      17UL,
      button_test_rect(20.0, 30.0, 160.0, 40.0),
      label,
    ).unwrap()
    for
      items in [
        button.paint_items(maximum).unwrap(),
        button.paint_items_with_palette(maximum, palette).unwrap(),
      ] {
      assert_eq(items.length(), 3)
      assert_eq(items[0].id(), maximum)
      assert_eq(items[1].id(), maximum + 1UL)
      assert_eq(items[2].id(), maximum + 2UL)
      match items[2] {
        @scene.TextItem(text~, ..) => assert_eq(text, label)
        _ => fail("label boundary must remain a text item")
      }
    }
    for invalid in [0UL, maximum + 1UL, maximum + 2UL, maximum + 3UL] {
      assert_true(button.paint_items(invalid) is Err(@button.InvalidItemId))
      assert_true(
        button.paint_items_with_palette(invalid, palette)
        is Err(@button.InvalidItemId),
      )
    }
  }
  let too_long = @button.Button::new(
    17UL,
    button_test_rect(20.0, 30.0, 160.0, 40.0),
    String::from_array(Array::make(65537, 'x')),
  ).unwrap()
  assert_true(
    too_long.paint_items(1UL) is Err(@button.SceneFailure(@scene.TextTooLong)),
  )
  assert_true(
    too_long.paint_items_with_palette(1UL, palette)
    is Err(@button.SceneFailure(@scene.TextTooLong)),
  )
  // ID validation still wins over text validation in both public entry points.
  assert_true(too_long.paint_items(0UL) is Err(@button.InvalidItemId))
  assert_true(
    too_long.paint_items_with_palette(0UL, palette)
    is Err(@button.InvalidItemId),
  )
}
