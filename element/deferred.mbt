///|
/// Defer one anchored attachment with a nonnegative Int32 priority. Deferred
/// attachments paint after ordinary nodes, from lower to higher priority;
/// ties retain structural attachment order. Omitted priority is zero.
/// Negative priorities return InvalidDeferredPriority. Ordinary deferred
/// content, repeated wrapping and nested attachments remain unsupported.
pub fn Element::deferred(
  self : Element,
  priority~ : Int32 = 0,
) -> Result[Element, ElementError] {
  if priority < 0 {
    Err(InvalidDeferredPriority)
  } else if self.anchored is None || self.deferred is Some(_) {
    Err(UnsupportedAnchoredComposition)
  } else {
    Ok({
      ..self,
      children: copy_elements(self.children),
      deferred: Some(priority),
    })
  }
}

///|
// Keep structural preorder intact. Queue complete contiguous subtrees, then
// stable-sort the queue by root priority. Descendant metadata is validated by
// ElementTree::new; no descendant can escape its subtree's scheduled span.
fn deferred_paint_indices(nodes : Array[ElementNode]) -> Array[Int32] {
  let order : Array[Int32] = []
  let deferred : Array[(Int32, Int32, Int32)] = []
  let mut index = 0
  while index < nodes.length() {
    match nodes[index].deferred {
      None => {
        order.push(index)
        index += 1
      }
      Some(priority) => {
        let start = index
        index += 1
        // A valid preorder subtree continues exactly while each next node's
        // parent belongs to this span. Siblings of the root start a new span,
        // including equal-priority siblings that must retain structural order.
        while index < nodes.length() {
          let mut descendant = false
          for ancestor = start; ancestor < index; ancestor = ancestor + 1 {
            if nodes[index].parent == Some(nodes[ancestor].id) {
              descendant = true
              break
            }
          }
          if !descendant {
            break
          }
          index += 1
        }
        deferred.push((priority, start, index))
        let mut position = deferred.length() - 1
        // Compare directly, never subtract: adjacent priorities at Int32::max
        // retain order without overflow. Strict > preserves equal-priority ties.
        while position > 0 && deferred[position - 1].0 > priority {
          deferred[position] = deferred[position - 1]
          position -= 1
        }
        deferred[position] = (priority, start, index)
      }
    }
  }
  for (_, start, end) in deferred {
    for index = start; index < end; index = index + 1 {
      order.push(index)
    }
  }
  order
}
