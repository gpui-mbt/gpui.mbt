///|
/// Explicit window/input-state value for the supported Mouse/Keyboard subset.
/// Initialize to Mouse, then apply after_input before dispatching each event.
/// This value is independent of focus ownership and pure event routing.
/// Touch and pointer-capture hover exceptions are not modeled here.
pub(all) enum InputModality {
  Mouse
  Keyboard
} derive(Eq)

///|
pub extend InputModality with Eq::{not_equal, equal}

///|
/// Key presses (including repeats and modified keys) select Keyboard; pointer
/// movement or presses select Mouse. Releases, committed text and scroll retain
/// the previous modality. This never moves focus or interprets key bindings.
pub fn InputModality::after_input(
  self : InputModality,
  event : @primitives.InputEvent,
) -> InputModality {
  match event {
    @primitives.KeyPressed(..) => Keyboard
    @primitives.PointerMoved(..) | @primitives.PointerButtonPressed(..) => Mouse
    @primitives.KeyReleased(..)
    | @primitives.PointerButtonReleased(..)
    | @primitives.TextInput(..)
    | @primitives.Scroll(..) => self
  }
}

///|
/// Uncaptured hover policy only. Combine with the caller's hit-test result.
/// GPUI's captured-hitbox exception and Touch modality are outside this subset.
pub fn InputModality::allows_hover(self : InputModality) -> Bool {
  self == Mouse
}

///|
/// Signed handle index, independent of group prefixes and tab-stop eligibility.
pub fn ElementNode::tab_index(self : ElementNode) -> Int32 {
  self.tab_index
}

///|
pub fn ElementNode::is_tab_stop(self : ElementNode) -> Bool {
  self.tab_stop
}

///|
/// Set ordering metadata without making the node focusable or a tab stop.
pub fn ElementNode::with_tab_index(
  self : ElementNode,
  index : Int32,
) -> ElementNode {
  {
    id: self.id,
    parent: self.parent,
    bounds: self.bounds,
    focusable: self.focusable,
    tab_index: index,
    tab_group_index: self.tab_group_index,
    tab_stop: self.tab_stop,
    pointer_events: self.pointer_events,
    background: self.background,
    scroll_viewport: self.scroll_viewport,
  }
}

///|
/// An optional signed group prefix, independent of this node's handle index.
pub fn ElementNode::tab_group_index(self : ElementNode) -> Int32? {
  self.tab_group_index
}

///|
/// Set or clear the group prefix for this node and its descendants. A group's
/// own handle is inside the prefix. This never makes a node focusable/a stop.
pub fn ElementNode::with_tab_group_index(
  self : ElementNode,
  index : Int32?,
) -> ElementNode {
  {
    id: self.id,
    parent: self.parent,
    bounds: self.bounds,
    focusable: self.focusable,
    tab_index: self.tab_index,
    tab_group_index: index,
    tab_stop: self.tab_stop,
    pointer_events: self.pointer_events,
    background: self.background,
    scroll_viewport: self.scroll_viewport,
  }
}

///|
/// Opt into traversal destinations; non-focusable nodes remain ineligible.
pub fn ElementNode::with_tab_stop(
  self : ElementNode,
  enabled : Bool,
) -> ElementNode {
  {
    id: self.id,
    parent: self.parent,
    bounds: self.bounds,
    focusable: self.focusable,
    tab_index: self.tab_index,
    tab_group_index: self.tab_group_index,
    tab_stop: enabled,
    pointer_events: self.pointer_events,
    background: self.background,
    scroll_viewport: self.scroll_viewport,
  }
}

///|
pub fn Element::tab_index(self : Element) -> Int32 {
  self.tab_index
}

///|
pub fn Element::is_tab_stop(self : Element) -> Bool {
  self.tab_stop
}

///|
/// Set signed ordering metadata, preserved through layout and prepaint.
/// This does not opt into focusability or tab-stop destinations.
pub fn Element::with_tab_index(self : Element, index : Int32) -> Element {
  {
    id: self.id,
    item: self.item,
    is_root: self.is_root,
    children_style: self.children_style,
    children: copy_elements(self.children),
    background: self.background,
    focusable: self.focusable,
    tab_index: index,
    tab_group_index: self.tab_group_index,
    tab_stop: self.tab_stop,
    pointer_events: self.pointer_events,
    scroll_offset: self.scroll_offset,
  }
}

///|
pub fn Element::tab_group_index(self : Element) -> Int32? {
  self.tab_group_index
}

///|
/// Preserve a separately configured group prefix through layout and prepaint.
/// None removes only this prefix, leaving tab_index and eligibility unchanged.
pub fn Element::with_tab_group_index(self : Element, index : Int32?) -> Element {
  {
    id: self.id,
    item: self.item,
    is_root: self.is_root,
    children_style: self.children_style,
    children: copy_elements(self.children),
    background: self.background,
    focusable: self.focusable,
    tab_index: self.tab_index,
    tab_group_index: index,
    tab_stop: self.tab_stop,
    pointer_events: self.pointer_events,
    scroll_offset: self.scroll_offset,
  }
}

///|
pub fn Element::with_tab_stop(self : Element, enabled : Bool) -> Element {
  {
    id: self.id,
    item: self.item,
    is_root: self.is_root,
    children_style: self.children_style,
    children: copy_elements(self.children),
    background: self.background,
    focusable: self.focusable,
    tab_index: self.tab_index,
    tab_group_index: self.tab_group_index,
    tab_stop: enabled,
    pointer_events: self.pointer_events,
    scroll_offset: self.scroll_offset,
  }
}

///|
/// Query exact focus, not whether an ancestor or descendant is focused.
pub fn ElementTree::is_focused(self : ElementTree, id : UInt64) -> Bool {
  self.focused == Some(id)
}

///|
/// Keyboard focus styling. Apply ordinary focus styling first, then any
/// focus-visible overrides. These queries do not choose or paint styles.
pub fn ElementTree::is_focus_visible(
  self : ElementTree,
  id : UInt64,
  modality : InputModality,
) -> Bool {
  self.is_focused(id) && modality == Keyboard
}

///|
/// Move to the next live focusable tab stop, ordered lexicographically by
/// signed group prefixes then handle index, with stable tree preorder ties.
/// Groups do not trap focus. Focused non-stops remain ordering anchors.
/// Wrap at the end; with no focus choose the first stop. With no stops or an
/// already-focused destination, return the existing acquisition unchanged.
/// Unlike explicit with_focus, this only acquires a different destination.
pub fn ElementTree::focus_next(
  self : ElementTree,
) -> Result[ElementTree, ElementError] {
  self.traverse_focus(false)
}

///|
/// Reverse focus_next. With no focus choose the last stop; wrap at the start.
pub fn ElementTree::focus_prev(
  self : ElementTree,
) -> Result[ElementTree, ElementError] {
  self.traverse_focus(true)
}

///|
priv struct TabPrefix {
  parent : Int32?
  index : Int32
}

///|
priv struct TabKey {
  prefix : Int32?
  index : Int32
}

///|
priv struct TabOrder {
  keys : Array[TabKey]
  prefixes : Array[TabPrefix]
  left_path : Array[Int32]
  right_path : Array[Int32]
}

///|
// Shared immutable prefix links avoid copying an entire path per node. Direct
// ElementTree inputs need not obey the declarative lifecycle's depth limit.
fn tab_order(nodes : Array[ElementNode]) -> TabOrder {
  let ancestors : Array[(UInt64, Int32?)] = []
  let prefixes : Array[TabPrefix] = []
  let keys : Array[TabKey] = []
  for node in nodes {
    while ancestors.length() > 0 &&
          Some(ancestors[ancestors.length() - 1].0) != node.parent {
      let _ = ancestors.pop()
    }
    let inherited = if ancestors.length() > 0 {
      ancestors[ancestors.length() - 1].1
    } else {
      None
    }
    let prefix = match node.tab_group_index {
      None => inherited
      Some(index) => {
        let slot = prefixes.length()
        prefixes.push({ parent: inherited, index, })
        Some(slot)
      }
    }
    keys.push({ prefix, index: node.tab_index, })
    ancestors.push((node.id, prefix))
  }
  { keys, prefixes, left_path: [], right_path: [], }
}

///|
// Paths are built backwards into two reusable scratch buffers, so comparisons
// need only O(group depth) scratch storage instead of O(nodes * depth) keys.
fn tab_path(order : TabOrder, index : Int32, scratch : Array[Int32]) -> Unit {
  scratch.clear()
  let key = order.keys[index]
  scratch.push(key.index)
  let mut current = key.prefix
  while current is Some(_) {
    match current {
      None => ()
      Some(slot) => {
        let prefix = order.prefixes[slot]
        scratch.push(prefix.index)
        current = prefix.parent
      }
    }
  }
}

///|
// Compare components directly; subtraction would overflow at signed extremes.
fn tab_precedes(order : TabOrder, left : Int32, right : Int32) -> Bool {
  tab_path(order, left, order.left_path)
  tab_path(order, right, order.right_path)
  let mut left_index = order.left_path.length() - 1
  let mut right_index = order.right_path.length() - 1
  while left_index >= 0 &&
        right_index >= 0 &&
        order.left_path[left_index] == order.right_path[right_index] {
    left_index -= 1
    right_index -= 1
  }
  if left_index >= 0 && right_index >= 0 {
    order.left_path[left_index] < order.right_path[right_index]
  } else if left_index != right_index {
    left_index < right_index
  } else {
    left < right
  }
}

///|
// One scan selects the nearest directional stop and the wrap destination.
// The current node is found separately so non-stops retain their order key.
// This does not reorder or expose the tree's owned node array.
fn ElementTree::traverse_focus(
  self : ElementTree,
  backward : Bool,
) -> Result[ElementTree, ElementError] {
  let mut anchor : Int32? = None
  let mut stops = 0
  let mut only_stop : Int32? = None
  for index = 0; index < self.nodes.length(); index = index + 1 {
    let node = self.nodes[index]
    if node.focusable && self.focused == Some(node.id) {
      anchor = Some(index)
    }
    if node.focusable && node.tab_stop {
      stops += 1
      only_stop = Some(index)
    }
  }
  if stops == 0 || (stops == 1 && only_stop == anchor) {
    return Ok(self)
  }
  let order = tab_order(self.nodes)
  let mut adjacent : Int32? = None
  let mut wrap : Int32? = None
  for index = 0; index < self.nodes.length(); index = index + 1 {
    let node = self.nodes[index]
    if node.focusable && node.tab_stop {
      let preferred = fn(candidate : Int32, existing : Int32) {
        if backward {
          tab_precedes(order, existing, candidate)
        } else {
          tab_precedes(order, candidate, existing)
        }
      }
      match wrap {
        None => wrap = Some(index)
        Some(existing) => if preferred(index, existing) { wrap = Some(index) }
      }
      let on_requested_side = match anchor {
        None => true
        Some(current) =>
          if backward {
            tab_precedes(order, index, current)
          } else {
            tab_precedes(order, current, index)
          }
      }
      if on_requested_side {
        match adjacent {
          None => adjacent = Some(index)
          Some(existing) =>
            if preferred(index, existing) {
              adjacent = Some(index)
            }
        }
      }
    }
  }
  let target = match adjacent {
    Some(index) => Some(index)
    None => wrap
  }
  match target {
    None => Ok(self)
    Some(index) => {
      let id = self.nodes[index].id
      if self.focused == Some(id) {
        Ok(self)
      } else {
        self.with_focus(id)
      }
    }
  }
}
