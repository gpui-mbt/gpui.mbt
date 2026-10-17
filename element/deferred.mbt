///|
/// Defer one anchored attachment with a nonnegative Int32 priority. Deferred
/// attachments paint after ordinary nodes, from lower to higher priority;
/// ties retain discovery order (structural order for flat attachments).
/// Omitted priority is zero. Exactly two anchored deferred levels are supported.
/// Negative priorities return InvalidDeferredPriority. Ordinary deferred
/// content, repeated wrapping and a third attachment level are unsupported.
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
// Stable insertion avoids subtraction/overflow at Int32::max. Input order is
// discovery order, not structural order once a second round has been found.
fn sort_deferred_groups(
  nodes : Array[ElementNode],
  groups : Array[Int32],
) -> Unit {
  for index = 1; index < groups.length(); index = index + 1 {
    let current = groups[index]
    let priority = nodes[current].deferred.unwrap()
    let mut position = index
    while position > 0 &&
          nodes[groups[position - 1]].deferred.unwrap() > priority {
      groups[position] = groups[position - 1]
      position -= 1
    }
    groups[position] = current
  }
}

///|
// Discover first-level groups structurally. Each stable priority-sorted
// prepaint round discovers only the direct child groups of its members, in
// that round's order. The second round is independent of the final global
// paint sort: a child may paint before its parent, and equal child priorities
// inherit discovery order from the sorted parent round.
fn deferred_group_rounds(nodes : Array[ElementNode]) -> Array[Array[Int32]] {
  let first : Array[Int32] = []
  for index = 0; index < nodes.length(); index = index + 1 {
    let node = nodes[index]
    if node.deferred_group == Some(node.id) {
      let mut parent_group : UInt64? = None
      for parent in nodes {
        if Some(parent.id) == node.parent {
          parent_group = parent.deferred_group
          break
        }
      }
      if parent_group is None {
        first.push(index)
      }
    }
  }
  let rounds : Array[Array[Int32]] = []
  let mut round = first
  while round.length() > 0 {
    rounds.push(round.copy())
    sort_deferred_groups(nodes, round)
    let next : Array[Int32] = []
    for group_index in round {
      let group = nodes[group_index].id
      for index = 0; index < nodes.length(); index = index + 1 {
        let node = nodes[index]
        if node.deferred_group == Some(node.id) {
          for parent in nodes {
            if Some(parent.id) == node.parent &&
              parent.deferred_group == Some(group) {
              next.push(index)
              break
            }
          }
        }
      }
    }
    round = next
  }
  rounds
}

///|
fn deferred_indices(nodes : Array[ElementNode], paint : Bool) -> Array[Int32] {
  let order : Array[Int32] = []
  for index = 0; index < nodes.length(); index = index + 1 {
    if nodes[index].deferred_group is None {
      order.push(index)
    }
  }
  let groups : Array[Int32] = []
  for round in deferred_group_rounds(nodes) {
    if !paint {
      sort_deferred_groups(nodes, round)
    }
    for group in round {
      groups.push(group)
    }
  }
  if paint {
    sort_deferred_groups(nodes, groups)
  }
  for root in groups {
    let group = Some(nodes[root].id)
    for index = 0; index < nodes.length(); index = index + 1 {
      if nodes[index].deferred_group == group {
        order.push(index)
      }
    }
  }
  order
}

///|
fn deferred_paint_indices(nodes : Array[ElementNode]) -> Array[Int32] {
  deferred_indices(nodes, true)
}
