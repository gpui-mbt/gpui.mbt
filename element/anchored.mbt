///|
/// The eight perimeter anchors supported by GPUI's anchored element.
/// Center is deliberately absent: it is not an Anchor in the Rust surface.
pub(all) enum Anchor {
  TopLeft
  TopCenter
  TopRight
  LeftCenter
  RightCenter
  BottomLeft
  BottomCenter
  BottomRight
} derive(Eq)

///|
pub extend Anchor with Eq::{not_equal, equal}

///|
/// Coordinate mode for an explicitly supplied anchor position. Local is
/// relative to the anchored element's actual layout origin.
pub(all) enum AnchoredPositionMode {
  Local
  Window
} derive(Eq)

///|
pub extend AnchoredPositionMode with Eq::{not_equal, equal}

///|
// A single zero-margin popup subtree is measured through ordinary recursive
// core layout. Neither its measured size nor descendant rectangles are host
// fixture inputs. Text leaves may carry measured intrinsic metrics, as in the
// ordinary element lifecycle. The temporary root is never a live identity.
fn measure_anchored_popup(
  wrapper_id : UInt64,
  popup : Element,
  scale_factor : Double?,
  origin? : @primitives.Point,
) -> Result[RequestedLayout, ElementError] {
  match validate_anchored_popup(wrapper_id, popup) {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  let item = match popup.item.unwrap().with_flex(0.0, 0.0) {
    Ok(item) => item
    Err(_) => return Err(GeometryFailure)
  }
  let measured = { ..popup, item: Some(item), }
  let style = @layout.FlexTreeStyle::new(@layout.FlowDirection::row()).with_align(
    @layout.AlignItems::start(),
  )
  let origin = origin.unwrap_or(@primitives.Point::new(0, 0).unwrap())
  let bounds = match @primitives.Rect::new(origin.x(), origin.y(), 0, 0) {
    Ok(value) => value
    Err(_) => return Err(GeometryFailure)
  }
  mixed_layout_at(
    Element::root(wrapper_id, style).with_child(measured),
    bounds,
    scale_factor,
  )
}

///|
// This first measured surface excludes context-dependent sizing, queries,
// lists, grid and scrolling. Rejection is explicit rather than allowing a
// hidden alternate layout or a second dynamic-content callback execution.
fn validate_anchored_popup(
  wrapper_id : UInt64,
  popup : Element,
) -> Result[Unit, ElementError] {
  let pending = [(popup, 1)]
  let ids : Array[UInt64] = [wrapper_id]
  while pending.length() > 0 {
    let (element, depth) = pending.pop().unwrap()
    if depth > MAX_ELEMENT_DEPTH {
      return Err(TreeTooDeep)
    }
    if element.is_root {
      return Err(InvalidAnchoredShape)
    }
    for id in ids {
      if id == element.id {
        return Err(DuplicateId)
      }
    }
    ids.push(element.id)
    if element.anchored is Some(_) || element.deferred {
      return Err(UnsupportedAnchoredComposition)
    }
    if element.grid_item is Some(_) ||
      element.grid_style is Some(_) ||
      element.container_query is Some(_) ||
      element.query_root_size is Some(_) ||
      element.uniform_list is Some(_) ||
      element.scroll_offset is Some(_) {
      return Err(UnsupportedAnchoredComposition)
    }
    let item = match element.item {
      None => return Err(MissingLayoutItem)
      Some(item) => item
    }
    // A copied Element can change its public ID independently from its item.
    // Reject that mismatch before layout produces boxes under another ID.
    if item.id() != element.id {
      return Err(InvalidAnchoredShape)
    }
    if item.main is @layout.Percent(_) || item.cross is @layout.Percent(_) {
      return Err(InvalidAnchoredShape)
    }
    match element.children_style {
      Some(style) if style.wrap != @layout.FlexWrap::no_wrap() =>
        return Err(InvalidAnchoredShape)
      _ => ()
    }
    for child in element.children {
      pending.push((child, depth + 1))
    }
  }
  Ok(())
}

///|
priv struct AnchoredSpec {
  after : UInt64
  anchor : Anchor
  mode : AnchoredPositionMode
  position : @primitives.Point
}

///|
priv struct AnchoredLayout {
  placements : Array[ElementPlacement]
  measured : Array[(UInt64, RequestedLayout)]
}

///|
/// Attach one measured popup after a parent's single fixed ordinary child.
/// Fitting is always SnapToWindow, with zero margin and no extra offset.
/// All position choices are explicit. Append the returned element after the
/// reference child, then optionally call deferred() before appending it.
///
/// The parent must be a zero-inset, zero-gap, start-aligned column containing
/// that one nonflexing fixed-size child followed only by anchored attachments.
/// This models the observed default-Block single-child source shape, not
/// arbitrary CSS absolute/static positioning. The core derives the static
/// origin from live parent-left and reference-child-bottom geometry.
/// The attachment itself never paints or receives pointer/focus input.
pub fn Element::anchored_after(
  id : UInt64,
  after_child : UInt64,
  popup : Element,
  anchor : Anchor,
  mode : AnchoredPositionMode,
  position : @primitives.Point,
) -> Result[Element, ElementError] {
  match validate_anchored_popup(id, popup) {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  let zero = @primitives.Size::new(0, 0).unwrap()
  Ok({
    ..Element::new(
      @layout.FlexItem::new(
        id,
        @layout.Dimension::auto(),
        @layout.Dimension::auto(),
        zero,
      ),
    ),
    item: None,
    children: [popup],
    pointer_events: false,
    anchored: Some({ after: after_child, anchor, mode, position, }),
  })
}

///|
fn has_anchored_elements(root : Element) -> Bool {
  let pending = [(root, 0)]
  while pending.length() > 0 {
    let (element, depth) = pending.pop().unwrap()
    if element.anchored is Some(_) || element.deferred {
      return true
    }
    if depth > MAX_ELEMENT_DEPTH {
      continue
    }
    for child in element.children {
      pending.push((child, depth + 1))
    }
  }
  false
}

///|
fn validate_anchored_parent(parent : Element) -> Result[Unit, ElementError] {
  let style = match parent.children_style {
    Some(style) => style
    None => return Err(InvalidAnchoredShape)
  }
  if parent.grid_style is Some(_) ||
    style.direction != @layout.FlowDirection::column() ||
    style.wrap != @layout.FlexWrap::no_wrap() ||
    style.align != @layout.AlignItems::start() ||
    style.justify != @layout.JustifyContent::start() ||
    style.padding != @layout.Insets::zero() ||
    style.border != @layout.Insets::zero() ||
    style.gap_x != 0.0 ||
    style.gap_y != 0.0 ||
    parent.children.length() < 2 {
    return Err(InvalidAnchoredShape)
  }
  let reference = parent.children[0]
  if reference.anchored is Some(_) || reference.deferred {
    return Err(InvalidAnchoredShape)
  }
  let item = match reference.item {
    Some(item) => item
    None => return Err(InvalidAnchoredShape)
  }
  if !(item.main is @layout.Points(_)) ||
    !(item.cross is @layout.Points(_)) ||
    item.grow != 0.0 ||
    item.shrink != 0.0 {
    return Err(InvalidAnchoredShape)
  }
  for index = 1; index < parent.children.length(); index = index + 1 {
    match parent.children[index].anchored {
      Some(spec) if spec.after == reference.id => ()
      _ => return Err(InvalidAnchoredShape)
    }
  }
  Ok(())
}

///|
fn anchored_placements(
  root : Element,
) -> Result[Array[ElementPlacement], ElementError] {
  if !root.is_root || root.anchored is Some(_) || root.deferred {
    return Err(RootRequired)
  }
  let placements : Array[ElementPlacement] = []
  let pending : Array[ElementPlacement] = [
    { element: root, parent: None, depth: 0, },
  ]
  let mut attachment_depth = -1
  while pending.length() > 0 {
    let placement = pending.pop().unwrap()
    let element = placement.element
    if placement.depth > MAX_ELEMENT_DEPTH {
      return Err(TreeTooDeep)
    }
    if placement.depth > 0 && element.is_root {
      return Err(InvalidChildRoot)
    }
    for previous in placements {
      if previous.element.id == element.id {
        return Err(DuplicateId)
      }
    }
    if placement.depth <= attachment_depth {
      attachment_depth = -1
    }
    if element.container_query is Some(_) ||
      element.query_root_size is Some(_) ||
      element.uniform_list is Some(_) ||
      element.scroll_offset is Some(_) {
      return Err(UnsupportedAnchoredComposition)
    }
    match element.item {
      Some(item) if item.id() != element.id => return Err(InvalidAnchoredShape)
      _ => ()
    }
    if element.deferred && element.anchored is None {
      return Err(UnsupportedAnchoredComposition)
    }
    match element.anchored {
      None => ()
      Some(_) => {
        if attachment_depth >= 0 {
          return Err(UnsupportedAnchoredComposition)
        }
        attachment_depth = placement.depth
        if element.item is Some(_) ||
          element.grid_item is Some(_) ||
          element.children_style is Some(_) ||
          element.grid_style is Some(_) ||
          element.children.length() != 1 ||
          element.background is Some(_) ||
          element.pointer_events ||
          element.focusable ||
          element.tab_stop ||
          element.tab_index != 0 ||
          element.tab_group_index is Some(_) {
          return Err(InvalidAnchoredShape)
        }
        match validate_anchored_popup(element.id, element.children[0]) {
          Err(error) => return Err(error)
          Ok(_) => ()
        }
      }
    }
    let mut has_attachment = false
    for child in element.children {
      has_attachment = has_attachment || child.anchored is Some(_)
    }
    if has_attachment {
      match validate_anchored_parent(element) {
        Err(error) => return Err(error)
        Ok(_) => ()
      }
    }
    placements.push(placement)
    push_children_reverse(element, placement.depth, pending)
  }
  Ok(placements)
}

///|
// Recursion is bounded by the completed structural validation above.
fn without_anchored_children(element : Element) -> Element {
  let children : Array[Element] = []
  for child in element.children {
    if child.anchored is None {
      children.push(without_anchored_children(child))
    }
  }
  { ..element, children, }
}

///|
fn requested_bounds(
  request : RequestedLayout,
  id : UInt64,
) -> @primitives.Rect? {
  if request.layout.root_id() == id {
    return Some(request.layout.root_bounds())
  }
  for box in request.layout.items() {
    if box.id() == id {
      return Some(box.bounds())
    }
  }
  None
}

///|
fn request_anchored_layout(
  root : Element,
  viewport : @primitives.Size,
  scale_factor : Double?,
) -> Result[RequestedLayout, ElementError] {
  let placements = match anchored_placements(root) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let ordinary = match
    without_anchored_children(root).request_layout_internal(
      viewport, scale_factor,
    ) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let measured : Array[(UInt64, RequestedLayout)] = []
  for placement in placements {
    match placement.element.anchored {
      None => ()
      Some(spec) => {
        let parent = match
          requested_bounds(ordinary, placement.parent.unwrap()) {
          Some(bounds) => bounds
          None => return Err(GeometryFailure)
        }
        let reference = match requested_bounds(ordinary, spec.after) {
          Some(bounds) => bounds
          None => return Err(GeometryFailure)
        }
        let origin = match
          @primitives.Point::new(parent.left(), reference.bottom()) {
          Ok(value) => value
          Err(_) => return Err(GeometryFailure)
        }
        let request = match
          measure_anchored_popup(
            placement.element.id,
            placement.element.children[0],
            scale_factor,
            origin~,
          ) {
          Ok(value) => value
          Err(error) => return Err(error)
        }
        measured.push((placement.element.id, request))
      }
    }
  }
  Ok({ ..ordinary, anchored_layout: Some({ placements, measured, }), })
}

///|
fn anchored_translation(
  spec : AnchoredSpec,
  static_origin : @primitives.Point,
  size : @primitives.Size,
  viewport : @primitives.Size,
  scale_factor : Double?,
) -> Result[@primitives.Point, ElementError] {
  let (horizontal, vertical) = match spec.anchor {
    TopLeft => (0.0, 0.0)
    TopCenter => (0.5, 0.0)
    TopRight => (1.0, 0.0)
    LeftCenter => (0.0, 0.5)
    RightCenter => (1.0, 0.5)
    BottomLeft => (0.0, 1.0)
    BottomCenter => (0.5, 1.0)
    BottomRight => (1.0, 1.0)
  }
  let origin = match spec.mode {
    Window => spec.position
    Local =>
      match static_origin.translated(spec.position) {
        Ok(value) => value
        Err(_) => return Err(GeometryFailure)
      }
  }
  let mut x = origin.x() - horizontal * size.width()
  let mut y = origin.y() - vertical * size.height()
  if !scroll_finite(x) ||
    !scroll_finite(y) ||
    !scroll_finite(x + size.width()) ||
    !scroll_finite(y + size.height()) {
    return Err(GeometryFailure)
  }
  // Source order matters for oversized popups: right, left, bottom, top.
  if x + size.width() > viewport.width() {
    x -= x + size.width() - viewport.width()
  }
  if x < 0.0 {
    x = 0.0
  }
  if y + size.height() > viewport.height() {
    y -= y + size.height() - viewport.height()
  }
  if y < 0.0 {
    y = 0.0
  }
  let round_away = fn(value : Double) {
    let rounded = (value.abs() + 0.5).floor()
    if value < 0.0 {
      -rounded
    } else {
      rounded
    }
  }
  let offset = match
    @primitives.Point::new(
      round_away(x - static_origin.x()),
      round_away(y - static_origin.y()),
    ) {
    Ok(value) => value
    Err(_) => return Err(GeometryFailure)
  }
  // A distinct second stage mirrors Window::layout_bounds element-offset
  // snapping. Do not combine this with the logical ties-away rounding above.
  scroll_translation(offset, scale_factor)
}

///|
fn prepaint_anchored(
  ordinary : RequestedLayout,
  anchored : AnchoredLayout,
) -> Result[Prepainted, ElementError] {
  // Window masks use the logical viewport, independently of device-snapped
  // layout bounds. Rounding the mask would add or remove a subpixel hit strip.
  let window_clip = match
    @primitives.Rect::new(
      0,
      0,
      ordinary.viewport.width(),
      ordinary.viewport.height(),
    ) {
    Ok(value) => value
    Err(_) => return Err(GeometryFailure)
  }
  let nodes : Array[ElementNode] = []
  let mut current : (Int32, Bool, RequestedLayout, @primitives.Point)? = None
  let mut overflow = ordinary.layout.overflow()
  for placement in anchored.placements {
    match current {
      Some((depth, _, _, _)) if placement.depth <= depth => current = None
      _ => ()
    }
    let element = placement.element
    let mut deferred = false
    let bounds = match element.anchored {
      Some(spec) => {
        let mut measurement : RequestedLayout? = None
        for (id, request) in anchored.measured {
          if id == element.id {
            measurement = Some(request)
          }
        }
        let measurement = match measurement {
          Some(value) => value
          None => return Err(GeometryFailure)
        }
        let popup = measurement.layout.items()[0].bounds()
        let origin = measurement.layout.root_bounds().origin()
        let offset = match
          anchored_translation(
            spec,
            origin,
            popup.size(),
            ordinary.viewport,
            ordinary.scale_factor,
          ) {
          Ok(value) => value
          Err(error) => return Err(error)
        }
        deferred = element.deferred
        current = Some((placement.depth, deferred, measurement, offset))
        match
          @primitives.Rect::new(
            origin.x(),
            origin.y(),
            popup.size().width(),
            popup.size().height(),
          ) {
          Ok(value) => value
          Err(_) => return Err(GeometryFailure)
        }
      }
      None =>
        match current {
          Some((_, delayed, measurement, offset)) => {
            deferred = delayed
            let bounds = match requested_bounds(measurement, element.id) {
              Some(value) => value
              None => return Err(GeometryFailure)
            }
            match bounds.translated(offset) {
              Ok(value) => value
              Err(_) => return Err(GeometryFailure)
            }
          }
          None =>
            match requested_bounds(ordinary, element.id) {
              Some(value) => value
              None => return Err(GeometryFailure)
            }
        }
    }
    if element.anchored is None &&
      !ordinary.layout.root_bounds().contains_rect(bounds) {
      overflow = true
    }
    nodes.push({
      ..placement_node(placement, bounds),
      deferred,
      window_clip: if placement.depth == 0 || element.anchored is Some(_) {
        Some(window_clip)
      } else {
        None
      },
      anchored_after: match element.anchored {
        Some(spec) => Some(spec.after)
        None => None
      },
    })
  }
  let tree = match ElementTree::new(nodes) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  Ok({
    tree,
    viewport: ordinary.viewport,
    viewport_bounds: ordinary.layout.root_bounds(),
    overflow,
  })
}
