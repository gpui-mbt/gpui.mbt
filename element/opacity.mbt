///|
fn valid_element_opacity(opacity : Double) -> Bool {
  !opacity.is_nan() && !opacity.is_inf() && opacity >= 0.0 && opacity <= 1.0
}

///|
/// Set this element's local paint opacity. It multiplies ordinary ancestors
/// and descendants, without changing layout, pointer events or focusability.
/// Deferred attachments begin a fresh opacity scope, matching pinned GPUI.
pub fn Element::with_opacity(
  self : Element,
  opacity : Double,
) -> Result[Element, ElementError] {
  if !valid_element_opacity(opacity) {
    Err(InvalidOpacity)
  } else {
    Ok({ ..self, opacity, children: copy_elements(self.children), })
  }
}

///|
pub fn Element::opacity(self : Element) -> Double {
  self.opacity
}

///|
pub fn ElementNode::with_opacity(
  self : ElementNode,
  opacity : Double,
) -> Result[ElementNode, ElementError] {
  if !valid_element_opacity(opacity) {
    Err(InvalidOpacity)
  } else {
    Ok(self.with_local_opacity(opacity))
  }
}

///|
pub fn ElementNode::opacity(self : ElementNode) -> Double {
  self.opacity
}

///|
// Lifecycle-only transfer of the already validated local scalar.
fn ElementNode::with_local_opacity(
  self : ElementNode,
  opacity : Double,
) -> ElementNode {
  { ..self, opacity, }
}

///|
// Structural preorder gives each parent a resolved scalar before its children.
// Keep this independent of priority-sorted paint order: deferred groups may
// paint before their structural parents. Pinned GPUI's DeferredDraw captures
// no element_opacity, so every group root starts at one, even when nested.
fn effective_element_opacities(nodes : Array[ElementNode]) -> Array[Double] {
  let result : Array[Double] = []
  let ancestors : Array[(UInt64, Double)] = []
  for node in nodes {
    // Each node is pushed and popped at most once, including default-opacity
    // frames. Do not rescan the whole prefix for every parent.
    while ancestors.length() > 0 &&
          Some(ancestors[ancestors.length() - 1].0) != node.parent {
      ignore(ancestors.pop())
    }
    let inherited = if node.deferred_group == Some(node.id) ||
      ancestors.length() == 0 {
      1.0
    } else {
      ancestors[ancestors.length() - 1].1
    }
    let opacity = inherited * node.opacity
    result.push(opacity)
    ancestors.push((node.id, opacity))
  }
  result
}
