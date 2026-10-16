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
/// Signed flat tab order, independent of whether this node is a tab stop.
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
/// Move to the next live focusable tab stop, ordered by signed tab_index and
/// stable tree preorder. Non-stops remain ordering anchors when focused.
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
// Compare keys directly, avoiding signed subtraction overflow at Int extremes.
fn tab_precedes(
  nodes : Array[ElementNode],
  left : Int32,
  right : Int32,
) -> Bool {
  nodes[left].tab_index < nodes[right].tab_index ||
  (nodes[left].tab_index == nodes[right].tab_index && left < right)
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
  for index = 0; index < self.nodes.length(); index = index + 1 {
    let node = self.nodes[index]
    if node.focusable && self.focused == Some(node.id) {
      anchor = Some(index)
    }
  }
  let mut adjacent : Int32? = None
  let mut wrap : Int32? = None
  for index = 0; index < self.nodes.length(); index = index + 1 {
    let node = self.nodes[index]
    if node.focusable && node.tab_stop {
      let preferred = fn(candidate : Int32, existing : Int32) {
        if backward {
          tab_precedes(self.nodes, existing, candidate)
        } else {
          tab_precedes(self.nodes, candidate, existing)
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
            tab_precedes(self.nodes, index, current)
          } else {
            tab_precedes(self.nodes, current, index)
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
