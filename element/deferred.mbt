///|
/// Defer one anchored attachment at priority zero. Deferred attachments paint
/// after all ordinary nodes, in structural attachment order. Other priorities,
/// ordinary deferred content, repeated wrapping and nested attachments are
/// outside this bounded surface.
pub fn Element::deferred(self : Element) -> Result[Element, ElementError] {
  if self.anchored is None || self.deferred {
    Err(UnsupportedAnchoredComposition)
  } else {
    Ok({ ..self, children: copy_elements(self.children), deferred: true, })
  }
}

///|
// Keep structural preorder intact. The bounded priority-zero surface assigns
// every node in each flat deferred subtree to the second paint pass. This
// derived traversal needs no mutable indices and survives subtree removal.
fn deferred_paint_indices(nodes : Array[ElementNode]) -> Array[Int32] {
  let order : Array[Int32] = []
  for index = 0; index < nodes.length(); index = index + 1 {
    if !nodes[index].deferred {
      order.push(index)
    }
  }
  for index = 0; index < nodes.length(); index = index + 1 {
    if nodes[index].deferred {
      order.push(index)
    }
  }
  order
}
