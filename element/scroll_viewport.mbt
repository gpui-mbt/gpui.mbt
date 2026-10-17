///|
/// A resolved, immutable two-axis scroll viewport. Positive offsets move
/// content left/up. Bounds stay fixed relative to this viewport's parent;
/// only descendants receive its translation. Limits come from direct layout
/// children, not their overflowing descendants.
pub struct ScrollViewport {
  priv element_id : UInt64
  priv viewport_bounds : @primitives.Rect
  priv position : @primitives.Point
  priv maximum : @primitives.Point
}

///|
pub fn ScrollViewport::id(self : ScrollViewport) -> UInt64 {
  self.element_id
}

///|
pub fn ScrollViewport::bounds(self : ScrollViewport) -> @primitives.Rect {
  self.viewport_bounds
}

///|
pub fn ScrollViewport::offset(self : ScrollViewport) -> @primitives.Point {
  self.position
}

///|
pub fn ScrollViewport::max_offset(self : ScrollViewport) -> @primitives.Point {
  self.maximum
}

///|
/// Opt into the bounded two-axis scroll surface. Retain offsets in caller
/// state and pass them back on the next render. Prepaint clamps the finite
/// point against current layout. This clips children at the viewport bounds;
/// border-aware masks, one-axis scrolling, and scrollbar painting are outside
/// this API's contract.
pub fn Element::with_scroll_offset(
  self : Element,
  offset : @primitives.Point,
) -> Element {
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
    tab_stop: self.tab_stop,
    pointer_events: self.pointer_events,
    scroll_offset: Some(offset),
    uniform_list: self.uniform_list,
    grid_item: self.grid_item,
    grid_style: self.grid_style,
    container_query: self.container_query,
    query_root_size: self.query_root_size,
    anchored: self.anchored,
    deferred: self.deferred,
  }
}

///|
pub fn ElementTree::scroll_viewport(
  self : ElementTree,
  id : UInt64,
) -> ScrollViewport? {
  match self.node(id) {
    None => None
    Some(node) => node.scroll_viewport
  }
}

///|
/// Resolve a logical-pixel wheel delta without changing this live tree. Every
/// pointer-enabled scroll viewport on the target-to-root route receives the
/// same delta and clamps independently; unused delta is not redistributed.
/// Ordinary viewports use the dominant axis, with ties choosing Y. Uniform
/// lists always use nonzero Y, otherwise X as a vertical fallback.
/// Positive deltas increase content offsets (the browser/InputEvent convention).
/// The returned fresh array contains all eligible ancestors, even at a limit.
/// Save these offsets in caller state and render again to update geometry.
/// Overlapping unrelated hitboxes and GPUI occlusion policies are out of scope.
pub fn ElementTree::scroll_wheel(
  self : ElementTree,
  position : @primitives.Point,
  delta_x : Double,
  delta_y : Double,
) -> Result[Array[ScrollViewport], ScrollError] {
  self.scroll_wheel_on_route(
    position,
    delta_x,
    delta_y,
    self.dispatch_pointer(position).bubble(),
  )
}

///|
// Scope controllers provide a truncated route; ordinary tree behavior remains
// the complete bubble route above.
fn ElementTree::scroll_wheel_on_route(
  self : ElementTree,
  position : @primitives.Point,
  delta_x : Double,
  delta_y : Double,
  route : Array[UInt64],
) -> Result[Array[ScrollViewport], ScrollError] {
  if !scroll_finite(delta_x) || !scroll_finite(delta_y) {
    Err(NonFiniteValue)
  } else {
    let (dx, dy) = if delta_x.abs() > delta_y.abs() {
      (delta_x, 0.0)
    } else {
      (0.0, delta_y)
    }
    let updates : Array[ScrollViewport] = []
    for id in route {
      match self.node(id) {
        Some(node) if node.pointer_events &&
          pointer_in_bounds(node.bounds, position) =>
          match node.scroll_viewport {
            None => ()
            Some(viewport) => {
              let (dx, dy) = if node.uniform_list is Some(_) {
                (0.0, if delta_y != 0.0 { delta_y } else { delta_x })
              } else {
                (dx, dy)
              }
              updates.push({
                element_id: id,
                viewport_bounds: viewport.viewport_bounds,
                maximum: viewport.maximum,
                position: scroll_point(
                  scroll_advance(
                    viewport.position.x(),
                    dx,
                    viewport.maximum.x(),
                  ),
                  scroll_advance(
                    viewport.position.y(),
                    dy,
                    viewport.maximum.y(),
                  ),
                ),
              })
            }
          }
        _ => ()
      }
    }
    Ok(updates)
  }
}

///|
fn pointer_in_bounds(
  bounds : @primitives.Rect,
  position : @primitives.Point,
) -> Bool {
  position.x() >= bounds.left() &&
  position.x() < bounds.right() &&
  position.y() >= bounds.top() &&
  position.y() < bounds.bottom()
}

///|
fn ElementTree::within_scroll_clips(
  self : ElementTree,
  node : ElementNode,
  position : @primitives.Point,
) -> Bool {
  match node.window_clip {
    Some(bounds) if !pointer_in_bounds(bounds, position) => return false
    _ => ()
  }
  let mut parent = node.parent
  while parent is Some(_) {
    match parent {
      None => ()
      Some(id) =>
        match self.node(id) {
          None => return false
          Some(ancestor) => {
            if ancestor.scroll_viewport is Some(_) &&
              !pointer_in_bounds(ancestor.bounds, position) {
              return false
            }
            match ancestor.window_clip {
              Some(bounds) if !pointer_in_bounds(bounds, position) =>
                return false
              _ => ()
            }
            parent = ancestor.parent
          }
        }
    }
  }
  true
}

///|
// Resolve against original layout boxes first. Ancestor translation must not
// leak into content measurement or make limits depend on the current offset.
fn resolve_scroll_nodes(
  layout_nodes : Array[ElementNode],
  placements : Array[ElementPlacement],
  scale_factor : Double?,
) -> Result[Array[ElementNode], ElementError] {
  let resolved : Array[ElementNode] = []
  let offsets = [scroll_point(0.0, 0.0)]
  for index = 0; index < layout_nodes.length(); index = index + 1 {
    let placement = placements[index]
    let original = layout_nodes[index]
    while offsets.length() > placement.depth + 1 {
      let _ = offsets.pop()
    }
    if placement.depth < 0 || placement.depth >= offsets.length() {
      return Err(GeometryFailure)
    }
    let inherited = offsets[placement.depth]
    // Layout bounds are already device-snapped. Apply one snapped copy of
    // the raw accumulated offset, as GPUI Window::layout_bounds does; do not
    // feed this rounded copy back into descendant accumulation.
    let applied = match scroll_translation(inherited, scale_factor) {
      Ok(offset) => offset
      Err(error) => return Err(error)
    }
    let bounds = match original.bounds.translated(applied) {
      Ok(bounds) => bounds
      Err(_) => return Err(GeometryFailure)
    }
    let uniform = match placement.element.uniform_list {
      None => None
      Some(list) =>
        match resolve_uniform_list(list, bounds, scale_factor) {
          Ok(value) => Some(value)
          Err(error) => return Err(error)
        }
    }
    let viewport = if uniform is Some(list) {
      Some({
        element_id: original.id,
        viewport_bounds: bounds,
        position: scroll_point(0.0, list.position),
        maximum: scroll_point(0.0, list.maximum),
      })
    } else {
      match placement.element.scroll_offset {
        None => None
        Some(requested) => {
          let maximum = match
            scroll_maximum(layout_nodes, placements, index, scale_factor) {
            Ok(maximum) => maximum
            Err(error) => return Err(error)
          }
          Some({
            element_id: original.id,
            viewport_bounds: bounds,
            position: scroll_point(
              scroll_clamp(requested.x(), maximum.x()),
              scroll_clamp(requested.y(), maximum.y()),
            ),
            maximum,
          })
        }
      }
    }
    resolved.push({
      id: original.id,
      parent: original.parent,
      bounds,
      focusable: original.focusable,
      tab_index: original.tab_index,
      tab_group_index: original.tab_group_index,
      tab_stop: original.tab_stop,
      pointer_events: original.pointer_events,
      background: original.background,
      scroll_viewport: viewport,
      uniform_list: uniform,
      deferred: original.deferred,
      anchored_after: original.anchored_after,
      window_clip: original.window_clip,
    })
    // A leaf has no descendants to translate. Avoid failing on an unused sum.
    let descendant_offset = match viewport {
      Some(viewport) if placement.element.children.length() > 0 =>
        match
          @primitives.Point::new(
            inherited.x() - viewport.position.x(),
            inherited.y() - viewport.position.y(),
          ) {
          Ok(offset) => offset
          Err(_) => return Err(GeometryFailure)
        }
      _ => inherited
    }
    offsets.push(descendant_offset)
  }
  Ok(resolved)
}

///|
fn scroll_translation(
  offset : @primitives.Point,
  scale_factor : Double?,
) -> Result[@primitives.Point, ElementError] {
  match scale_factor {
    None => Ok(offset)
    Some(scale) => {
      if !scroll_finite(scale) || scale <= 0.0 {
        return Err(GeometryFailure)
      }
      let device_offset = match offset.scaled(scale) {
        Ok(value) => value
        Err(_) => return Err(GeometryFailure)
      }
      let snap = fn(value : Double) {
        let rounded = (value.abs() - 0.5).ceil() / scale
        if value < 0.0 {
          -rounded
        } else {
          rounded
        }
      }
      match
        @primitives.Point::new(snap(device_offset.x()), snap(device_offset.y())) {
        Ok(value) => Ok(value)
        Err(_) => Err(GeometryFailure)
      }
    }
  }
}

///|
fn scroll_maximum(
  nodes : Array[ElementNode],
  placements : Array[ElementPlacement],
  index : Int32,
  scale_factor : Double?,
) -> Result[@primitives.Point, ElementError] {
  let placement = placements[index]
  let bounds = nodes[index].bounds
  let mut union : @primitives.Rect? = None
  let mut child = index + 1
  while child < placements.length() && placements[child].depth > placement.depth {
    if placements[child].parent == Some(nodes[index].id) {
      union = match union {
        None => Some(nodes[child].bounds)
        Some(previous) =>
          match previous.union(nodes[child].bounds) {
            Ok(combined) => Some(combined)
            Err(_) => return Err(GeometryFailure)
          }
      }
    }
    child += 1
  }
  let content = match union {
    Some(bounds) => bounds.size()
    // Matches GPUI's empty-child fallback before padding is added.
    None => bounds.size()
  }
  let padding = match placement.element.children_style {
    None => @layout.Insets::zero()
    Some(style) => style.padding
  }
  let horizontal = scroll_padding(padding.left(), scale_factor) +
    scroll_padding(padding.right(), scale_factor)
  let vertical = scroll_padding(padding.top(), scale_factor) +
    scroll_padding(padding.bottom(), scale_factor)
  let width = content.width() + horizontal
  let height = content.height() + vertical
  if !scroll_finite(width) || !scroll_finite(height) {
    return Err(GeometryFailure)
  }
  match
    @primitives.Point::new(
      rounded_scroll_limit(width - bounds.size().width()),
      rounded_scroll_limit(height - bounds.size().height()),
    ) {
    Ok(maximum) => Ok(maximum)
    Err(_) => Err(GeometryFailure)
  }
}

///|
// Authored nonnegative padding uses the same half-toward-zero device snapping
// as request_layout_with_device_scale; raw logical layout keeps raw padding.
fn scroll_padding(value : Double, scale_factor : Double?) -> Double {
  match scale_factor {
    None => value
    Some(scale) => (value * scale - 0.5).ceil() / scale
  }
}

///|
fn rounded_scroll_limit(value : Double) -> Double {
  if value <= 0.0 {
    0.0
  } else if value >= 1.0e14 {
    // At this magnitude a Double cannot represent hundredth-pixel detail;
    // avoid overflowing a finite limit during the rounding multiplication.
    value
  } else {
    (value * 100.0 + 0.5).floor() / 100.0
  }
}
