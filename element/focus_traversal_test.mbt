///|
// Independently authored source-derived contracts, not Rust/browser observations.
fn tab_node(id : UInt64, index : Int32, stop : Bool) -> @element.ElementNode {
  @element.ElementNode::new(id, None, element_rect(0, 0, 20, 20))
  .with_focusable(true)
  .with_tab_index(index)
  .with_tab_stop(stop)
}

///|
fn tab_step(
  tree : @element.ElementTree,
  backward : Bool,
) -> @element.ElementTree {
  match (if backward { tree.focus_prev() } else { tree.focus_next() }) {
    Ok(value) => value
    Err(_) => abort("valid traversal rejected")
  }
}

///|
fn tab_walk(
  tree : @element.ElementTree,
  count : Int32,
  backward : Bool,
) -> Array[UInt64] {
  let mut current = tree
  let visited = []
  for _index = 0; _index < count; _index = _index + 1 {
    current = tab_step(current, backward)
    match current.focused() {
      Some(id) => visited.push(id)
      None => abort("traversal destination missing")
    }
  }
  visited
}

///|
test "tab metadata defaults and setters are independent and immutable" {
  let original = @element.ElementNode::new(1, None, element_rect(1, 2, 30, 40))
  assert_eq(original.tab_index(), 0)
  assert_false(original.is_tab_stop())
  let indexed = original.with_tab_index(-4)
  let stop = indexed.with_tab_stop(true)
  assert_false(stop.is_focusable())
  assert_true(unwrap_tree([stop]).focus_next() is Ok(_))
  assert_true(tab_step(unwrap_tree([stop]), false).focused() is None)
  assert_true(unwrap_tree([stop]).with_focus(1) is Err(NotFocusable))
  let styled = stop
    .with_focusable(true)
    .with_background(Some(element_color(1, 2, 3)))
    .with_pointer_events(false)
  assert_eq(styled.tab_index(), -4)
  assert_true(styled.is_tab_stop())
  assert_true(styled.bounds() == original.bounds())
  assert_true(styled.background() == Some(element_color(1, 2, 3)))
  assert_false(styled.accepts_pointer_events())
  assert_true(tab_step(unwrap_tree([styled]), false).focused() == Some(1))
  let disabled = styled.with_tab_stop(false).with_tab_index(9)
  assert_eq(disabled.tab_index(), 9)
  assert_false(disabled.is_tab_stop())
  assert_true(styled.is_tab_stop())
  assert_eq(original.tab_index(), 0)
  assert_false(original.is_tab_stop())
  assert_false(indexed.is_tab_stop())
}

///|
test "tab traversal orders signed extremes and equal indices by stable preorder" {
  let tree = unwrap_tree([
    tab_node(40, 7, true),
    tab_node(90, -3, true),
    tab_node(10, 7, true),
    tab_node(60, -2147483648, true),
    tab_node(20, 2147483647, true),
    tab_node(70, -3, true),
    tab_node(30, 0, true),
  ])
  assert_true(tab_walk(tree, 9, false) == [60, 90, 70, 30, 40, 10, 20, 60, 90])
  assert_true(tab_walk(tree, 9, true) == [20, 10, 40, 30, 70, 90, 60, 20, 10])
  assert_true(tree.focused() is None)
  assert_true(
    tree.nodes().map(node => node.id()) == [40, 90, 10, 60, 20, 70, 30],
  )
}

///|
test "tab equal-index preorder includes descendants before the next sibling" {
  let bounds = element_rect(0, 0, 20, 20)
  let tree = unwrap_tree([
    @element.ElementNode::new(80, None, bounds)
    .with_focusable(true)
    .with_tab_stop(true),
    @element.ElementNode::new(50, Some(80), bounds)
    .with_focusable(true)
    .with_tab_stop(true),
    @element.ElementNode::new(90, Some(50), bounds)
    .with_focusable(true)
    .with_tab_stop(true),
    @element.ElementNode::new(10, Some(80), bounds)
    .with_focusable(true)
    .with_tab_stop(true),
  ])
  assert_true(tab_walk(tree, 5, false) == [80, 50, 90, 10, 80])
  assert_true(tab_walk(tree, 5, true) == [10, 90, 50, 80, 10])
}

///|
test "non-stop current nodes retain signed and equal-index ordering anchors" {
  let tree = unwrap_tree([
    tab_node(1, 0, true),
    tab_node(2, 0, false),
    tab_node(3, 0, true),
    tab_node(4, 2, false),
    tab_node(5, 3, true),
    tab_node(6, -5, false),
    tab_node(7, 7, false),
  ])
  let equal = owner_test_focus(tree, 2)
  assert_true(tab_step(equal, false).focused() == Some(3))
  assert_true(tab_step(equal, true).focused() == Some(1))
  let between = owner_test_focus(tree, 4)
  assert_true(tab_step(between, false).focused() == Some(5))
  assert_true(tab_step(between, true).focused() == Some(3))
  let before = owner_test_focus(tree, 6)
  assert_true(tab_step(before, false).focused() == Some(1))
  assert_true(tab_step(before, true).focused() == Some(5))
  let after = owner_test_focus(tree, 7)
  assert_true(tab_step(after, false).focused() == Some(1))
  assert_true(tab_step(after, true).focused() == Some(5))
  assert_true(tab_walk(tree, 4, false) == [1, 3, 5, 1])
  assert_true(tab_walk(tree, 4, true) == [5, 3, 1, 5])
}

///|
test "focusable defaults and tab indices alone are not traversal destinations" {
  let tree = unwrap_tree([
    @element.ElementNode::new(1, None, element_rect(0, 0, 20, 20)).with_focusable(
      true,
    ),
    tab_node(2, -8, false),
    tab_node(3, 2, true).with_focusable(false),
  ])
  assert_true(tab_step(tree, false).focused() is None)
  assert_true(tab_step(tree, true).focused() is None)
  let focused = owner_test_focus(tree, 1)
  assert_true(tab_step(focused, false).focus_owner() == focused.focus_owner())
  assert_true(tab_step(focused, true).focus_owner() == focused.focus_owner())
  assert_true(tab_step(unwrap_tree([]), false).focused() is None)
  assert_true(tab_step(unwrap_tree([]), true).focused() is None)
}

///|
test "singleton traversal preserves acquisition while explicit focus reacquires" {
  let tree = unwrap_tree([tab_node(1, 3, true), tab_node(2, 0, false)])
  let first = tab_step(tree, false)
  let owner = first.focus_owner()
  assert_true(owner is Some(_))
  assert_true(tab_step(first, false).focus_owner() == owner)
  assert_true(tab_step(first, true).focus_owner() == owner)
  assert_true(owner_test_focus(first, 1).focus_owner() != owner)
  let previous = owner_test_focus(tree, 2)
  let different = tab_step(previous, false)
  assert_true(different.focus_owner() != previous.focus_owner())
  assert_true(different.focused() == Some(1))
  match different.with_focus_owner(owner_test_capture(previous)) {
    Ok(restored) =>
      assert_true(restored.focus_owner() == previous.focus_owner())
    Err(_) => fail("traversal must retain lineage")
  }
}

///|
test "removed stops and focus never survive by stale numeric identity" {
  let tree = unwrap_tree([
    tab_node(1, 1, true),
    tab_node(2, 2, true),
    tab_node(3, 3, true),
  ])
  let focused = owner_test_focus(tree, 2)
  let owner = owner_test_capture(focused)
  let removed = owner_test_remove(focused, 2)
  assert_true(removed.focused() is None)
  assert_true(removed.with_focus_owner(owner) is Err(UnknownElement))
  assert_true(tab_walk(removed, 3, false) == [1, 3, 1])
  assert_true(tab_walk(removed, 3, true) == [3, 1, 3])
  let remaining = owner_test_remove(focused, 1)
  assert_true(remaining.focus_owner() == Some(owner))
  assert_true(tab_step(remaining, true).focused() == Some(3))
  let rebuilt = unwrap_tree(focused.nodes())
  assert_true(
    tab_step(rebuilt, false).with_focus_owner(owner) is Err(UnknownElement),
  )
  assert_true(focused.focus_owner() == Some(owner))
}

///|
test "traversal snapshots own input and returned arrays without changing node order" {
  let nodes = [
    tab_node(1, 2, true),
    tab_node(2, 1, true),
    tab_node(3, 3, false),
  ]
  let tree = unwrap_tree(nodes)
  nodes[1] = tab_node(99, -9, true)
  nodes.push(tab_node(4, -8, true))
  let exposed = tree.nodes()
  exposed[0] = tab_node(98, -8, true)
  let _ = exposed.pop()
  let focused = tab_step(tree, false)
  assert_true(focused.focused() == Some(2))
  assert_true(tree.focused() is None)
  assert_true(tree.nodes().map(node => node.id()) == [1, 2, 3])
  assert_true(focused.nodes().map(node => node.id()) == [1, 2, 3])
  let reverse = tab_step(focused, true)
  assert_true(reverse.focused() == Some(1))
  assert_true(focused.focused() == Some(2))
}

///|
test "focus and focus-visible queries are exact and hover policy is uncaptured" {
  let bounds = element_rect(0, 0, 20, 20)
  let tree = owner_test_focus(
    unwrap_tree([
      @element.ElementNode::new(1, None, bounds).with_focusable(true),
      @element.ElementNode::new(2, Some(1), bounds).with_focusable(true),
    ]),
    2,
  )
  for modality in [@element.Mouse, @element.Keyboard] {
    assert_true(tree.is_focused(2))
    assert_false(tree.is_focused(1))
    assert_false(tree.is_focused(999))
    assert_false(tree.is_focus_visible(1, modality))
    assert_false(tree.is_focus_visible(999, modality))
    assert_false(tree.clear_focus().is_focus_visible(2, modality))
  }
  assert_true(tree.is_focus_visible(2, @element.Keyboard))
  assert_false(tree.is_focus_visible(2, @element.Mouse))
  assert_true(@element.Mouse.allows_hover())
  assert_false(@element.Keyboard.allows_hover())
  assert_true(@element.Mouse.equal(@element.Mouse))
  assert_true(@element.Mouse.not_equal(@element.Keyboard))
}

///|
test "every key press changes modality despite key modifiers repeats or missing focus" {
  let keys = [
    @primitives.Character("a"),
    @primitives.Enter,
    @primitives.Escape,
    @primitives.Backspace,
    @primitives.Delete,
    @primitives.Tab,
    @primitives.Space,
    @primitives.ArrowLeft,
    @primitives.ArrowRight,
    @primitives.ArrowUp,
    @primitives.ArrowDown,
    @primitives.Home,
    @primitives.End,
    @primitives.PageUp,
    @primitives.PageDown,
  ]
  for shift in [false, true] {
    for control in [false, true] {
      for alt in [false, true] {
        for meta in [false, true] {
          let modifiers = @primitives.Modifiers::new(
            shift~,
            control~,
            alt~,
            meta~,
          )
          for key in keys {
            for repeat in [false, true] {
              let event = @primitives.KeyPressed(key~, modifiers~, repeat~)
              assert_true(
                @element.Mouse.after_input(event) == @element.Keyboard,
              )
              assert_true(
                @element.Keyboard.after_input(event) == @element.Keyboard,
              )
              assert_true(
                unwrap_tree([]).dispatch_input(event).target() is None,
              )
            }
            let released = @primitives.KeyReleased(key~, modifiers~)
            assert_true(@element.Mouse.after_input(released) == @element.Mouse)
            assert_true(
              @element.Keyboard.after_input(released) == @element.Keyboard,
            )
          }
        }
      }
    }
  }
}

///|
test "pointer moves and presses select Mouse while releases text and scroll retain modality" {
  let point = element_point(1000, -1000)
  let moved = @primitives.PointerMoved(position=point)
  assert_true(@element.Keyboard.after_input(moved) == @element.Mouse)
  assert_true(@element.Mouse.after_input(moved) == @element.Mouse)
  let combinations = []
  for shift in [false, true] {
    for control in [false, true] {
      for alt in [false, true] {
        for meta in [false, true] {
          combinations.push(
            @primitives.Modifiers::new(shift~, control~, alt~, meta~),
          )
        }
      }
    }
  }
  for modifiers in combinations {
    for
      button in [
        @primitives.Primary,
        @primitives.Secondary,
        @primitives.Middle,
        @primitives.Back,
        @primitives.Forward,
      ] {
      let press = @primitives.PointerButtonPressed(
        position=point,
        button~,
        modifiers~,
      )
      let release = @primitives.PointerButtonReleased(
        position=point,
        button~,
        modifiers~,
      )
      for before in [@element.Mouse, @element.Keyboard] {
        assert_true(before.after_input(press) == @element.Mouse)
        assert_true(before.after_input(release) == before)
      }
    }
    let scroll = @primitives.Scroll(
      position=point,
      delta=element_point(1, -2),
      modifiers~,
    )
    for before in [@element.Mouse, @element.Keyboard] {
      assert_true(before.after_input(scroll) == before)
      assert_true(
        before.after_input(@primitives.TextInput(text="あ🙂")) == before,
      )
      assert_true(before.after_input(@primitives.TextInput(text="")) == before)
    }
  }
}

///|
test "input dispatch remains route-only and explicit modality transition precedes callbacks" {
  let tree = owner_test_focus(
    unwrap_tree([tab_node(1, 0, true), tab_node(2, 1, true)]),
    1,
  )
  let owner = tree.focus_owner()
  let event = @primitives.KeyPressed(
    key=@primitives.Tab,
    modifiers=@primitives.Modifiers::none(),
    repeat=false,
  )
  let before = @element.Mouse
  assert_true(tree.dispatch_input(event).target() == Some(1))
  assert_true(tree.focus_owner() == owner)
  assert_true(before == @element.Mouse)
  assert_false(tree.is_focus_visible(1, before))
  let after = before.after_input(event)
  let visited = Ref(0)
  let observed = Ref(true)
  let result = tree.dispatch_input_with(event, (context, delivered) => {
    visited.val += 1
    observed.val = observed.val &&
      tree.is_focus_visible(1, after) &&
      context.target() == 1 &&
      delivered == event
    Ok(())
  })
  assert_true(result is Ok(_))
  assert_eq(visited.val, 2)
  assert_true(observed.val)
  assert_true(tree.focus_owner() == owner)
  let pointer = @primitives.PointerButtonPressed(
    position=element_point(1, 1),
    button=@primitives.Primary,
    modifiers=@primitives.Modifiers::none(),
  )
  assert_true(tree.dispatch_input(pointer).target() == Some(2))
  assert_true(tree.focused() == Some(1))
  assert_true(after.after_input(pointer) == @element.Mouse)
}

///|
test "declarative tab metadata survives every builder layout scroll and device scaling" {
  let column = @layout.FlexTreeStyle::new(@layout.FlowDirection::column())
  let base = @element.Element::root(1, column)
  assert_eq(base.tab_index(), 0)
  assert_false(base.is_tab_stop())
  let child_base = @element.Element::new(viewport_item(2, 100, 40))
  assert_eq(child_base.tab_index(), 0)
  assert_false(child_base.is_tab_stop())
  let child = child_base
    .with_tab_index(-4)
    .with_tab_stop(true)
    .with_focusable(true)
    .with_pointer_events(false)
    .with_background(Some(element_color(1, 2, 3)))
    .with_scroll_offset(element_point(0, 0))
    .with_children_style(column)
    .with_child(
      @element.Element::new(viewport_item(3, 130, 40))
      .with_focusable(true)
      .with_tab_stop(true)
      .with_tab_index(2),
    )
  let root = base
    .with_tab_index(9)
    .with_tab_stop(true)
    .with_focusable(true)
    .with_background(Some(element_color(4, 5, 6)))
    .with_pointer_events(true)
    .with_children_style(column)
    .with_scroll_offset(element_point(0, 15))
    .with_child(child)
  for scale in [None, Some(1.5)] {
    let requested = match scale {
      None => root.request_layout(lifecycle_size(40, 40))
      Some(value) =>
        root.request_layout_with_device_scale(lifecycle_size(40, 40), value)
    }
    let requested = match requested {
      Ok(value) => value
      Err(_) => abort("layout rejected")
    }
    let first = match requested.prepaint() {
      Ok(value) => value
      Err(_) => abort("prepaint rejected")
    }
    let tree = first.tree()
    assert_true(tab_walk(tree, 4, false) == [2, 3, 1, 2])
    assert_eq(viewport_node(tree, 1).tab_index(), 9)
    assert_eq(viewport_node(tree, 2).tab_index(), -4)
    assert_eq(viewport_node(tree, 3).tab_index(), 2)
    assert_true(viewport_node(tree, 2).is_tab_stop())
    assert_false(viewport_node(tree, 2).accepts_pointer_events())
    assert_true(viewport_node(tree, 2).bounds().top() < 0)
    assert_true(tree.scroll_viewport(1) is Some(_))
    assert_true(tree.scroll_viewport(2) is Some(_))
    let copied = viewport_node(tree, 2)
      .with_tab_index(7)
      .with_tab_stop(false)
      .with_focusable(true)
      .with_pointer_events(true)
      .with_background(None)
    let copy_tree = unwrap_tree([
      viewport_node(tree, 1),
      copied,
      viewport_node(tree, 3),
    ])
    assert_true(
      viewport_of(copy_tree, 2).offset() == viewport_of(tree, 2).offset(),
    )
    assert_true(
      viewport_of(copy_tree, 2).bounds() == viewport_of(tree, 2).bounds(),
    )
    assert_true(
      viewport_of(copy_tree, 2).max_offset() ==
      viewport_of(tree, 2).max_offset(),
    )
    let focused = tab_step(tree, false)
    let owner = owner_test_capture(focused)
    let second = match requested.prepaint() {
      Ok(value) => value
      Err(_) => abort("prepaint rejected")
    }
    assert_true(second.tree().with_focus_owner(owner) is Err(UnknownElement))
    assert_true(second.tree().focused() is None)
    assert_true(first.tree().focused() is None)
    assert_true(first.paint_snapshot(1.0) is Ok(_))
  }
  assert_eq(base.tab_index(), 0)
  assert_false(base.is_tab_stop())
  assert_eq(child_base.tab_index(), 0)
  assert_false(child_base.is_tab_stop())
  assert_eq(child.tab_index(), -4)
  assert_true(child.is_tab_stop())
  assert_false(child.with_tab_stop(false).is_tab_stop())
}
