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
// A single popup subtree is measured through ordinary recursive
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
  let measured = { ..without_anchored_children(popup), item: Some(item), }
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
  if popup.anchored is Some(_) {
    return Err(UnsupportedAnchoredComposition)
  }
  let pending = [(popup, 1, 1)]
  let ids : Array[UInt64] = [wrapper_id]
  while pending.length() > 0 {
    let (element, depth, level) = pending.pop().unwrap()
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
    let attachment = element.anchored is Some(_)
    if (attachment && (level >= 2 || element.deferred is None)) ||
      (!attachment && element.deferred is Some(_)) {
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
    if attachment {
      match validate_anchored_wrapper(element) {
        Err(error) => return Err(error)
        Ok(_) => ()
      }
      for child in element.children {
        pending.push((child, depth + 1, level + 1))
      }
      continue
    }
    if element.children.any(child => child.anchored is Some(_)) {
      match validate_anchored_parent(element) {
        Err(_) => return Err(UnsupportedAnchoredComposition)
        Ok(_) => ()
      }
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
      pending.push((child, depth + 1, level))
    }
  }
  Ok(())
}

///|
fn validate_anchored_wrapper(element : Element) -> Result[Unit, ElementError] {
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
    Err(InvalidAnchoredShape)
  } else {
    Ok(())
  }
}

///|
priv struct AnchoredSpec {
  after : UInt64
  measured_leaf : Bool
  anchor : Anchor
  mode : AnchoredPositionMode
  position : @primitives.Point
  margin : Double
}

///|
priv struct AnchoredLayout {
  placements : Array[ElementPlacement]
  measured : Array[(UInt64, RequestedLayout)]
}

///|
/// Attach one measured popup after a parent's single fixed ordinary child.
/// Fitting is always SnapToWindow, with an optional scalar margin and no extra
/// offset. Margin defaults to zero and must be finite and nonnegative. It is
/// applied only when a raw edge crosses the viewport, not as an always-inset
/// rectangle. Invalid margin or placement arithmetic returns GeometryFailure.
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
  margin~ : Double = 0.0,
) -> Result[Element, ElementError] {
  if !scroll_finite(margin) || margin < 0.0 {
    return Err(GeometryFailure)
  }
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
    anchored: Some({
      after: after_child,
      measured_leaf: false,
      anchor,
      mode,
      position,
      margin,
    }),
  })
}

///|
/// Attach a popup after one intrinsic measured leaf inside a decorated owner.
/// The owner is a zero-gap, start-aligned, nonwrapping column; its finite,
/// nonnegative padding and border participate in ordinary recursive layout.
/// Auto-sized owners are supported. The reference is its sole ordinary child:
/// an Auto/Auto leaf with zero grow/shrink and default size limits. Subsequent
/// children must all be attachments created by this constructor for that leaf.
/// Mixing this mode with anchored_after on one owner is rejected at layout.
///
/// The static origin is the actual requested leaf's left/bottom, before popup
/// fitting. Intrinsic metrics are inputs to ordinary layout, never final boxes.
/// This contract can represent measured text but does not shape text, identify
/// text semantically, or implement general Block static positioning. Popup
/// measurement, position modes, margin, deferred depth and fitting retain the
/// existing anchored contract. In particular this does not promise Rust f32 or
/// native-font parity. Use a fresh request after metrics or viewport changes.
pub fn Element::anchored_after_measured_leaf(
  id : UInt64,
  after_child : UInt64,
  popup : Element,
  anchor : Anchor,
  mode : AnchoredPositionMode,
  position : @primitives.Point,
  margin~ : Double = 0.0,
) -> Result[Element, ElementError] {
  match
    Element::anchored_after(
      id,
      after_child,
      popup,
      anchor,
      mode,
      position,
      margin~,
    ) {
    Err(error) => Err(error)
    Ok(element) =>
      Ok({
        ..element,
        anchored: Some({ ..element.anchored.unwrap(), measured_leaf: true, }),
      })
  }
}

///|
fn has_anchored_elements(root : Element) -> Bool {
  let pending = [(root, 0)]
  while pending.length() > 0 {
    let (element, depth) = pending.pop().unwrap()
    if element.anchored is Some(_) || element.deferred is Some(_) {
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
    style.gap_x != 0.0 ||
    style.gap_y != 0.0 ||
    parent.children.length() < 2 {
    return Err(InvalidAnchoredShape)
  }
  let reference = parent.children[0]
  if reference.anchored is Some(_) || reference.deferred is Some(_) {
    return Err(InvalidAnchoredShape)
  }
  let item = match reference.item {
    Some(item) => item
    None => return Err(InvalidAnchoredShape)
  }
  let measured_leaf = match parent.children[1].anchored {
    Some(spec) => spec.measured_leaf
    None => return Err(InvalidAnchoredShape)
  }
  if item.grow != 0.0 || item.shrink != 0.0 {
    return Err(InvalidAnchoredShape)
  }
  if measured_leaf {
    if !(item.main is @layout.Auto) ||
      !(item.cross is @layout.Auto) ||
      item.min_main != 0.0 ||
      item.max_main is Some(_) ||
      item.min_cross != 0.0 ||
      item.max_cross is Some(_) ||
      reference.children.length() != 0 ||
      reference.children_style is Some(_) ||
      reference.grid_item is Some(_) ||
      reference.grid_style is Some(_) ||
      reference.container_query is Some(_) ||
      reference.query_root_size is Some(_) ||
      reference.uniform_list is Some(_) ||
      reference.scroll_offset is Some(_) {
      return Err(InvalidAnchoredShape)
    }
    match parent.item {
      Some(owner) if owner.main is @layout.Percent(_) ||
        owner.cross is @layout.Percent(_) => return Err(InvalidAnchoredShape)
      _ => ()
    }
    for
      value in [
        style.padding.top(),
        style.padding.right(),
        style.padding.bottom(),
        style.padding.left(),
        style.border.top(),
        style.border.right(),
        style.border.bottom(),
        style.border.left(),
        item.intrinsic.width(),
        item.intrinsic.height(),
      ] {
      if !scroll_finite(value) || value < 0.0 {
        return Err(GeometryFailure)
      }
    }
  } else if style.padding != @layout.Insets::zero() ||
    style.border != @layout.Insets::zero() ||
    !(item.main is @layout.Points(_)) ||
    !(item.cross is @layout.Points(_)) {
    return Err(InvalidAnchoredShape)
  }
  for index = 1; index < parent.children.length(); index = index + 1 {
    match parent.children[index].anchored {
      Some(spec) if spec.after == reference.id &&
        spec.measured_leaf == measured_leaf => ()
      _ => return Err(InvalidAnchoredShape)
    }
  }
  Ok(())
}

///|
fn anchored_placements(
  root : Element,
) -> Result[Array[ElementPlacement], ElementError] {
  if !root.is_root || root.anchored is Some(_) || root.deferred is Some(_) {
    return Err(RootRequired)
  }
  let placements : Array[ElementPlacement] = []
  let pending : Array[ElementPlacement] = [
    { element: root, parent: None, depth: 0, },
  ]
  let attachments : Array[(Int32, Int32?)] = []
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
    while attachments.length() > 0 &&
          placement.depth <= attachments[attachments.length() - 1].0 {
      let _ = attachments.pop()
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
    match element.deferred {
      Some(priority) if priority < 0 => return Err(InvalidDeferredPriority)
      _ => ()
    }
    if element.deferred is Some(_) && element.anchored is None {
      return Err(UnsupportedAnchoredComposition)
    }
    match element.anchored {
      None => ()
      Some(_) => {
        if attachments.length() >= 2 ||
          (
            attachments.length() > 0 &&
            (element.deferred is None || attachments[0].1 is None)
          ) {
          return Err(UnsupportedAnchoredComposition)
        }
        attachments.push((placement.depth, element.deferred))
        match validate_anchored_wrapper(element) {
          Err(error) => return Err(error)
          Ok(_) => ()
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
  let enclosing : Array[(Int32, RequestedLayout)] = []
  for placement in placements {
    while enclosing.length() > 0 &&
          placement.depth <= enclosing[enclosing.length() - 1].0 {
      let _ = enclosing.pop()
    }
    match placement.element.anchored {
      None => ()
      Some(spec) => {
        let containing = if enclosing.length() == 0 {
          ordinary
        } else {
          enclosing[enclosing.length() - 1].1
        }
        let parent = match
          requested_bounds(containing, placement.parent.unwrap()) {
          Some(bounds) => bounds
          None => return Err(GeometryFailure)
        }
        let reference = match requested_bounds(containing, spec.after) {
          Some(bounds) => bounds
          None => return Err(GeometryFailure)
        }
        let origin = match
          @primitives.Point::new(
            if spec.measured_leaf {
              reference.left()
            } else {
              parent.left()
            },
            reference.bottom(),
          ) {
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
        enclosing.push((placement.depth, request))
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
  if !scroll_finite(spec.margin) || spec.margin < 0.0 {
    return Err(GeometryFailure)
  }
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
  // Only raw crossed edges receive margin. Source order matters both for
  // oversized popups and when a margin correction crosses the opposite edge:
  // right, left, bottom, top. Do not fit to an inset viewport or iterate.
  if x + size.width() > viewport.width() {
    let correction = x + size.width() - viewport.width() + spec.margin
    x -= correction
    // Check before the opposite-edge correction can hide an overflow.
    if !scroll_finite(correction) || !scroll_finite(x) {
      return Err(GeometryFailure)
    }
  }
  if x < 0.0 {
    x = spec.margin
  }
  if y + size.height() > viewport.height() {
    let correction = y + size.height() - viewport.height() + spec.margin
    y -= correction
    if !scroll_finite(correction) || !scroll_finite(y) {
      return Err(GeometryFailure)
    }
  }
  if y < 0.0 {
    y = spec.margin
  }
  if !scroll_finite(x + size.width()) || !scroll_finite(y + size.height()) {
    return Err(GeometryFailure)
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
  // Preserve logical offset until its inherited sum is complete. Device
  // snapping belongs to each layout-bounds read, not to this captured offset.
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
  // Build structural identity/membership before scheduling any geometry.
  // A nested wrapper starts its own group even when its priority equals its
  // parent. Ordinary descendants inherit both fields independently.
  let nodes : Array[ElementNode] = []
  for placement in anchored.placements {
    let element = placement.element
    let mut deferred : Int32? = None
    let mut deferred_group : UInt64? = None
    for parent in nodes {
      if Some(parent.id) == placement.parent {
        deferred = parent.deferred
        deferred_group = parent.deferred_group
        break
      }
    }
    if element.deferred is Some(_) {
      deferred = element.deferred
      deferred_group = Some(element.id)
    }
    nodes.push({
      ..placement_node(placement, ordinary.layout.root_bounds()),
      deferred,
      deferred_group,
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
  let contexts : Array[(UInt64, RequestedLayout, @primitives.Point)] = []
  let zero = @primitives.Point::new(0, 0).unwrap()
  let mut overflow = ordinary.layout.overflow()
  // Ordinary work, then stable-priority discovery rounds. The stored array
  // remains structural preorder; final global paint ordering is separate.
  for index in deferred_indices(nodes, false) {
    let placement = anchored.placements[index]
    let element = placement.element
    let mut containing = ordinary
    let mut inherited = zero
    let mut ancestor = placement.parent
    let mut found = false
    while ancestor is Some(_) && !found {
      let id = ancestor.unwrap()
      for (context_id, request, offset) in contexts {
        if context_id == id {
          containing = request
          inherited = offset
          found = true
          break
        }
      }
      if !found {
        ancestor = None
        for parent in nodes {
          if parent.id == id {
            ancestor = parent.parent
            break
          }
        }
      }
    }
    let inherited_snapped = match
      scroll_translation(inherited, ordinary.scale_factor) {
      Ok(value) => value
      Err(error) => return Err(error)
    }
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
        let origin = match
          measurement.layout
          .root_bounds()
          .origin()
          .translated(inherited_snapped) {
          Ok(value) => value
          Err(_) => return Err(GeometryFailure)
        }
        let relative = match
          anchored_translation(
            spec,
            origin,
            popup.size(),
            ordinary.viewport,
            None,
          ) {
          Ok(value) => value
          Err(error) => return Err(error)
        }
        let absolute = match inherited.translated(relative) {
          Ok(value) => value
          Err(_) => return Err(GeometryFailure)
        }
        contexts.push((element.id, measurement, absolute))
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
      None => {
        let bounds = match requested_bounds(containing, element.id) {
          Some(value) => value
          None => return Err(GeometryFailure)
        }
        match bounds.translated(inherited_snapped) {
          Ok(value) => value
          Err(_) => return Err(GeometryFailure)
        }
      }
    }
    if element.anchored is None &&
      !ordinary.layout.root_bounds().contains_rect(bounds) {
      overflow = true
    }
    nodes[index] = { ..nodes[index], bounds, }
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
