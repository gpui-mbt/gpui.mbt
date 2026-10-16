///|
/// Create a definite viewport root with explicit equal-fraction grid tracks.
pub fn Element::grid_root(
  id : UInt64,
  style : @layout.GridTreeStyle,
) -> Element {
  {
    ..Element::root(
      id,
      @layout.FlexTreeStyle::new(@layout.FlowDirection::row()),
    ),
    children_style: None,
    grid_style: Some(style),
  }
}

///|
/// A child allocated on physical axes by a grid parent.
pub fn Element::grid_item(item : @layout.GridItem) -> Element {
  let zero = @primitives.Size::new(0.0, 0.0).unwrap()
  {
    ..Element::new(
      @layout.FlexItem::new(
        item.id(),
        @layout.Dimension::auto(),
        @layout.Dimension::auto(),
        zero,
      ),
    ),
    item: None,
    grid_item: Some(item),
  }
}

///|
pub fn Element::with_grid_children_style(
  self : Element,
  style : @layout.GridTreeStyle,
) -> Element {
  {
    ..self,
    children: copy_elements(self.children),
    children_style: None,
    grid_style: Some(style),
  }
}

///|
/// A query is a childless request-layout leaf. Its callback receives the
/// assigned size during prepaint, then its returned declarative root is laid
/// out and rounded independently against that definite size, then translated
/// to the query's snapped origin.
/// Each query-bearing RequestedLayout can prepaint only once, including after
/// failure or reentrant attempts. Fresh requests may reuse this Element.
/// This is a MoonBit per-request contract, not Rust object-reuse equivalence.
pub fn Element::with_container_query(
  self : Element,
  callback : (@primitives.Size) -> Result[Element, ElementError],
) -> Element {
  {
    ..self,
    children: copy_elements(self.children),
    container_query: Some(callback),
  }
}

///|
pub fn Element::container_query_root(
  id : UInt64,
  callback : (@primitives.Size) -> Result[Element, ElementError],
) -> Element {
  Element::root(id, @layout.FlexTreeStyle::new(@layout.FlowDirection::row())).with_container_query(
    callback,
  )
}

///|
fn has_mixed_layout(root : Element) -> Bool {
  let pending = [(root, 0)]
  while pending.length() > 0 {
    let (element, depth) = pending.pop().unwrap()
    if depth > MAX_ELEMENT_DEPTH {
      return false
    }
    if element.query_root_size is Some(_) ||
      element.grid_item is Some(_) ||
      element.grid_style is Some(_) ||
      element.container_query is Some(_) {
      return true
    }
    for child in element.children {
      pending.push((child, depth + 1))
    }
  }
  false
}

///|
fn mixed_element_style(element : Element) -> @layout.MixedTreeStyle? {
  if element.container_query is Some(_) {
    return None
  }
  match element.grid_style {
    Some(style) => Some(@layout.GridStyle(style))
    None =>
      match element.children_style {
        Some(style) => Some(@layout.FlexStyle(style))
        None => None
      }
  }
}

///|
fn flatten_mixed_elements(
  root : Element,
) -> Result[
  (Array[ElementPlacement], Array[@layout.MixedTreeNode]),
  ElementError,
] {
  if !root.is_root {
    return Err(RootRequired)
  }
  let placements : Array[ElementPlacement] = []
  let nodes : Array[@layout.MixedTreeNode] = []
  let pending : Array[ElementPlacement] = [
    { element: root, parent: None, depth: 0, },
  ]
  while pending.length() > 0 {
    let placement = pending.pop().unwrap()
    let element = placement.element
    if placement.depth > MAX_ELEMENT_DEPTH {
      return Err(TreeTooDeep)
    }
    if placement.depth > 0 && element.is_root {
      return Err(InvalidChildRoot)
    }
    if placement.depth > 0 && element.query_root_size is Some(_) {
      return Err(InvalidQueryShape)
    }
    for previous in placements {
      if previous.element.id == element.id {
        return Err(DuplicateId)
      }
    }
    if element.container_query is Some(_) && element.children.length() > 0 {
      return Err(InvalidQueryShape)
    }
    if element.grid_style is Some(_) && element.scroll_offset is Some(_) {
      return Err(UnsupportedGridScroll)
    }
    if placement.depth > 0 {
      let item = match (element.item, element.grid_item) {
        (Some(item), None) => @layout.FlexChild(item)
        (None, Some(item)) => @layout.GridChild(item)
        _ => return Err(MissingLayoutItem)
      }
      nodes.push(
        @layout.MixedTreeNode::new(
          item,
          placement.parent.unwrap(),
          mixed_element_style(element),
        ),
      )
    }
    placements.push(placement)
    push_children_reverse(element, placement.depth, pending)
  }
  match validate_query_compositions(placements) {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  Ok((placements, nodes))
}

///|
fn validate_query_compositions(
  placements : Array[ElementPlacement],
) -> Result[Unit, ElementError] {
  let mut has_query = false
  let mut has_list = false
  for query in placements {
    has_list = has_list || query.element.uniform_list is Some(_)
    if query.element.container_query is Some(_) {
      has_query = true
      for other in placements {
        if other.element.scroll_offset is Some(_) &&
          (
            placement_descends_from(query, other.element.id, placements) ||
            placement_descends_from(other, query.element.id, placements)
          ) {
          return Err(UnsupportedQueryComposition)
        }
      }
    }
  }
  if has_query && has_list {
    Err(UnsupportedQueryComposition)
  } else {
    Ok(())
  }
}

///|
fn placement_descends_from(
  placement : ElementPlacement,
  ancestor : UInt64,
  placements : Array[ElementPlacement],
) -> Bool {
  if placement.element.id == ancestor {
    return true
  }
  let mut parent = placement.parent
  while parent is Some(_) {
    let id = parent.unwrap()
    if id == ancestor {
      return true
    }
    parent = None
    for candidate in placements {
      if candidate.element.id == id {
        parent = candidate.parent
        break
      }
    }
  }
  false
}

///|
fn request_mixed_layout(
  root : Element,
  viewport : @primitives.Size,
  scale_factor : Double?,
) -> Result[RequestedLayout, ElementError] {
  if root.query_root_size is Some(_) {
    return Err(InvalidQueryShape)
  }
  let bounds = match
    @primitives.Rect::new(0.0, 0.0, viewport.width(), viewport.height()) {
    Ok(bounds) => bounds
    Err(_) => return Err(GeometryFailure)
  }
  mixed_layout_at(root, bounds, scale_factor)
}

///|
fn mixed_layout_at(
  root : Element,
  bounds : @primitives.Rect,
  scale_factor : Double?,
) -> Result[RequestedLayout, ElementError] {
  match scale_factor {
    Some(scale) if !scroll_finite(scale) || scale <= 0.0 =>
      return match
        @layout.layout_mixed_tree_at(
          root.id,
          bounds,
          @layout.FlexStyle(
            @layout.FlexTreeStyle::new(@layout.FlowDirection::row()),
          ),
          [],
          Some(scale),
        ) {
        Err(error) => Err(LayoutFailure(error))
        Ok(_) => Err(GeometryFailure)
      }
    _ => ()
  }
  let (placements, nodes) = match flatten_mixed_elements(root) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  match validate_uniform_lists(placements) {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  let mut has_query = false
  for placement in placements {
    has_query = has_query || placement.element.container_query is Some(_)
    match placement.element.uniform_list {
      None => ()
      Some(list) =>
        match measure_uniform_prototype(list, scale_factor) {
          Err(error) => return Err(error)
          Ok(_) => ()
        }
    }
  }
  let style = match mixed_element_style(root) {
    Some(style) => style
    None =>
      if root.container_query is Some(_) {
        @layout.FlexStyle(
          @layout.FlexTreeStyle::new(@layout.FlowDirection::row()),
        )
      } else {
        return Err(RootRequired)
      }
  }
  let layout = match
    @layout.layout_mixed_tree_at(
      root.id,
      bounds,
      style,
      nodes,
      scale_factor,
      root_size?=root.query_root_size,
    ) {
    Ok(layout) => layout
    Err(error) => return Err(LayoutFailure(error))
  }
  Ok({
    placements,
    scale_factor,
    viewport: bounds.size(),
    layout,
    query_lease: if has_query {
      Some(Ref(false))
    } else {
      None
    },
  })
}

///|
fn placement_node(
  placement : ElementPlacement,
  bounds : @primitives.Rect,
) -> ElementNode {
  let element = placement.element
  ElementNode::new(element.id, placement.parent, bounds)
  .with_background(element.background)
  .with_focusable(element.focusable)
  .with_tab_index(element.tab_index)
  .with_tab_group_index(element.tab_group_index)
  .with_tab_stop(element.tab_stop)
  .with_pointer_events(element.pointer_events)
}

///|
fn prepaint_container_queries(
  request : RequestedLayout,
) -> Result[Prepainted, ElementError] {
  let nodes : Array[ElementNode] = []
  let placements : Array[ElementPlacement] = []
  let seen : Array[UInt64] = []
  for placement in request.placements {
    seen.push(placement.element.id)
  }
  let overflow = Ref(request.layout.overflow())
  match
    expand_query_layout(
      request,
      @primitives.Point::new(0.0, 0.0).unwrap(),
      None,
      0,
      nodes,
      placements,
      seen,
      overflow,
    ) {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  match validate_query_compositions(placements) {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  let resolved = match
    resolve_scroll_nodes(nodes, placements, request.scale_factor) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let tree = match ElementTree::new(resolved) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  Ok({
    tree,
    viewport: request.viewport,
    viewport_bounds: request.layout.root_bounds(),
    overflow: overflow.val,
  })
}

///|
fn expand_query_layout(
  request : RequestedLayout,
  origin : @primitives.Point,
  parent : UInt64?,
  base_depth : Int32,
  output : Array[ElementNode],
  expanded : Array[ElementPlacement],
  seen : Array[UInt64],
  overflow : Ref[Bool],
) -> Result[Unit, ElementError] {
  let boxes = request.layout.items()
  if boxes.length() + 1 != request.placements.length() {
    return Err(GeometryFailure)
  }
  for index = 0; index < request.placements.length(); index = index + 1 {
    let original = request.placements[index]
    let depth = base_depth + original.depth
    if depth > MAX_ELEMENT_DEPTH {
      return Err(TreeTooDeep)
    }
    let placement = {
      ..original,
      parent: if index == 0 {
        parent
      } else {
        original.parent
      },
      depth,
    }
    let local_bounds = if index == 0 {
      request.layout.root_bounds()
    } else {
      if boxes[index - 1].id() != placement.element.id {
        return Err(GeometryFailure)
      }
      boxes[index - 1].bounds()
    }
    let bounds = match local_bounds.translated(origin) {
      Ok(value) => value
      Err(_) => return Err(GeometryFailure)
    }
    output.push(placement_node(placement, bounds))
    expanded.push(placement)
    match placement.element.container_query {
      None => ()
      Some(callback) => {
        if depth >= MAX_ELEMENT_DEPTH {
          return Err(TreeTooDeep)
        }
        let generated = match callback(bounds.size()) {
          Ok(element) => element
          Err(error) => return Err(error)
        }
        let (generated_placements, _) = match
          flatten_mixed_elements(generated) {
          Ok(value) => value
          Err(error) => return Err(error)
        }
        // Reserve the entire generated subtree before invoking nested callbacks.
        // This also catches collisions with later static siblings.
        for generated_placement in generated_placements {
          if depth + 1 + generated_placement.depth > MAX_ELEMENT_DEPTH {
            return Err(TreeTooDeep)
          }
          let element = generated_placement.element
          if element.scroll_offset is Some(_) || element.uniform_list is Some(_) {
            return Err(UnsupportedQueryComposition)
          }
          for id in seen {
            if id == element.id {
              return Err(DuplicateId)
            }
          }
          seen.push(element.id)
        }
        // Each returned root has an independent layout coordinate system.
        // Round its edges before adding the separately snapped prepaint offset;
        // half-toward-zero rounding is not invariant under signed translation.
        let child_size = generated.query_root_size.unwrap_or(bounds.size())
        let child_bounds = match
          @primitives.Rect::new(
            0.0,
            0.0,
            child_size.width(),
            child_size.height(),
          ) {
          Ok(value) => value
          Err(_) => return Err(GeometryFailure)
        }
        let child_origin = match
          scroll_translation(bounds.origin(), request.scale_factor) {
          Ok(value) => value
          Err(error) => return Err(error)
        }
        let child_request = match
          mixed_layout_at(generated, child_bounds, request.scale_factor) {
          Ok(value) => value
          Err(error) => return Err(error)
        }
        // Nested query requests belong to this same consumed prepaint lease.
        match child_request.query_lease {
          Some(lease) => lease.val = true
          None => ()
        }
        let generated_bounds = match
          child_request.layout.root_bounds().translated(child_origin) {
          Ok(value) => value
          Err(_) => return Err(GeometryFailure)
        }
        overflow.val = overflow.val ||
          child_request.layout.overflow() ||
          generated_bounds.right() > bounds.right() ||
          generated_bounds.bottom() > bounds.bottom()
        match
          expand_query_layout(
            child_request,
            child_origin,
            Some(placement.element.id),
            depth + 1,
            output,
            expanded,
            seen,
            overflow,
          ) {
          Err(error) => return Err(error)
          Ok(_) => ()
        }
      }
    }
  }
  Ok(())
}

///|
/// Override a generated query root's physical size. The query remains its
/// parent's measurement leaf, even if this independent root overflows it.
/// Only roots returned by query callbacks accept this metadata.
pub fn Element::with_query_root_size(
  self : Element,
  size : @primitives.Size,
) -> Element {
  {
    ..self,
    children: copy_elements(self.children),
    query_root_size: Some(size),
  }
}
