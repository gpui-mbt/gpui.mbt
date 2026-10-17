///|
/// Refresh only hit-test bounds from a genuine lifecycle prepaint result.
/// This is a bounded same-topology, non-scroll operation, not reconciliation:
/// positional preorder IDs/parents, input metadata (including exact deferred
/// priorities), and root viewport bounds
/// must match exactly. A scroll viewport in either tree is unsupported.
///
/// Validation finishes before any bounds are copied. Success retains this
/// tree's exact focus acquisition and lineage, all non-bounds node fields
/// (including paint-only backgrounds), and every earlier immutable snapshot.
/// The fresh prepaint's focus state and identity are never adopted. Paint the
/// fresh Prepainted separately; the returned tree is the retained input tree.
pub fn ElementTree::with_layout_bounds(
  self : ElementTree,
  prepainted : Prepainted,
) -> Result[ElementTree, ElementError] {
  let fresh = prepainted.tree.nodes
  if self.nodes.length() != fresh.length() || fresh.length() == 0 {
    return Err(LayoutBoundsMismatch)
  }
  if self.nodes[0].bounds != prepainted.viewport_bounds {
    return Err(LayoutBoundsMismatch)
  }
  for index = 0; index < self.nodes.length(); index = index + 1 {
    let retained = self.nodes[index]
    let next = fresh[index]
    if retained.scroll_viewport is Some(_) || next.scroll_viewport is Some(_) {
      return Err(ScrollLayoutBoundsUnsupported)
    }
    if retained.id != next.id ||
      retained.parent != next.parent ||
      retained.focusable != next.focusable ||
      retained.tab_index != next.tab_index ||
      retained.tab_group_index != next.tab_group_index ||
      retained.tab_stop != next.tab_stop ||
      retained.deferred != next.deferred ||
      retained.anchored_after != next.anchored_after ||
      retained.window_clip != next.window_clip ||
      retained.pointer_events != next.pointer_events {
      return Err(LayoutBoundsMismatch)
    }
  }
  let nodes : Array[ElementNode] = []
  for index = 0; index < self.nodes.length(); index = index + 1 {
    nodes.push({ ..self.nodes[index], bounds: fresh[index].bounds, })
  }
  Ok({ ..self, nodes, })
}
