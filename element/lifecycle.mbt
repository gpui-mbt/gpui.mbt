///|
/// A value that can participate in the framework's element tree.
///
/// This is a MoonBit-native conversion contract. It does not imply Rust GPUI
/// source compatibility.
pub(open) trait IntoElement {
  fn into_element(Self) -> Element
}

///|
/// A view that produces one portable element value.
pub(open) trait Render {
  fn render(Self) -> Element
}

///|
/// Declarative element input for the headless layout/prepaint/paint pipeline.
/// A root has a stable ID and child-container style; every non-root element
/// carries the flex item that describes its allocation by its parent.
pub struct Element {
  id : UInt64
  item : @layout.FlexItem?
  is_root : Bool
  children_style : @layout.FlexTreeStyle?
  children : Array[Element]
  background : @primitives.Color?
  focusable : Bool
  tab_index : Int32
  tab_group_index : Int32?
  tab_stop : Bool
  pointer_events : Bool
  priv scroll_offset : @primitives.Point?
  priv uniform_list : UniformList?
  priv grid_item : @layout.GridItem?
  priv grid_style : @layout.GridTreeStyle?
  priv container_query : ((@primitives.Size) -> Result[Element, ElementError])?
  priv query_root_size : @primitives.Size?
  priv anchored : AnchoredSpec?
  priv deferred : Int32?
}

///|
/// Create the root of a declarative element tree. The root fills the supplied
/// viewport; its style lays out direct children.
pub fn Element::root(
  id : UInt64,
  children_style : @layout.FlexTreeStyle,
) -> Element {
  {
    id,
    item: None,
    is_root: true,
    children_style: Some(children_style),
    children: [],
    background: None,
    focusable: false,
    tab_index: 0,
    tab_group_index: None,
    tab_stop: false,
    pointer_events: true,
    scroll_offset: None,
    uniform_list: None,
    grid_item: None,
    grid_style: None,
    container_query: None,
    query_root_size: None,
    anchored: None,
    deferred: None,
  }
}

///|
/// Create an element allocated by its parent's flex layout.
pub fn Element::new(item : @layout.FlexItem) -> Element {
  {
    id: item.id(),
    item: Some(item),
    is_root: false,
    children_style: None,
    children: [],
    background: None,
    focusable: false,
    tab_index: 0,
    tab_group_index: None,
    tab_stop: false,
    pointer_events: true,
    scroll_offset: None,
    uniform_list: None,
    grid_item: None,
    grid_style: None,
    container_query: None,
    query_root_size: None,
    anchored: None,
    deferred: None,
  }
}

///|
/// Give this element's children a flex container style.
pub fn Element::with_children_style(
  self : Element,
  style : @layout.FlexTreeStyle,
) -> Element {
  {
    id: self.id,
    item: self.item,
    is_root: self.is_root,
    children_style: Some(style),
    children: copy_elements(self.children),
    background: self.background,
    focusable: self.focusable,
    tab_index: self.tab_index,
    tab_group_index: self.tab_group_index,
    tab_stop: self.tab_stop,
    pointer_events: self.pointer_events,
    scroll_offset: self.scroll_offset,
    uniform_list: self.uniform_list,
    grid_item: self.grid_item,
    grid_style: None,
    container_query: self.container_query,
    query_root_size: self.query_root_size,
    anchored: self.anchored,
    deferred: self.deferred,
  }
}

///|
/// Return a new element with `child` appended in stable paint/layout order.
pub fn Element::with_child(self : Element, child : Element) -> Element {
  let children = copy_elements(self.children)
  children.push(child)
  {
    id: self.id,
    item: self.item,
    is_root: self.is_root,
    children_style: self.children_style,
    children,
    background: self.background,
    focusable: self.focusable,
    tab_index: self.tab_index,
    tab_group_index: self.tab_group_index,
    tab_stop: self.tab_stop,
    pointer_events: self.pointer_events,
    scroll_offset: self.scroll_offset,
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
pub fn Element::with_background(
  self : Element,
  color : @primitives.Color?,
) -> Element {
  {
    id: self.id,
    item: self.item,
    is_root: self.is_root,
    children_style: self.children_style,
    children: copy_elements(self.children),
    background: color,
    focusable: self.focusable,
    tab_index: self.tab_index,
    tab_group_index: self.tab_group_index,
    tab_stop: self.tab_stop,
    pointer_events: self.pointer_events,
    scroll_offset: self.scroll_offset,
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
pub fn Element::with_focusable(self : Element, focusable : Bool) -> Element {
  {
    id: self.id,
    item: self.item,
    is_root: self.is_root,
    children_style: self.children_style,
    children: copy_elements(self.children),
    background: self.background,
    focusable,
    tab_index: self.tab_index,
    tab_group_index: self.tab_group_index,
    tab_stop: self.tab_stop,
    pointer_events: self.pointer_events,
    scroll_offset: self.scroll_offset,
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
pub fn Element::with_pointer_events(self : Element, enabled : Bool) -> Element {
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
    pointer_events: enabled,
    scroll_offset: self.scroll_offset,
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
/// Implementing `Render` on `Element` makes an already-built element a valid
/// render result.
pub impl Render for Element with fn render(self) -> Element {
  self
}

///|
pub extend Element with Render::{render}

///|
pub impl IntoElement for Element with fn into_element(self) -> Element {
  self
}

///|
pub extend Element with IntoElement::{into_element}

///|
/// Convert a custom view into its element value.
pub fn[T : Render] render_element(view : T) -> Element {
  view.render()
}

///|
/// Convert any value with an `IntoElement` implementation.
pub fn[T : IntoElement] into_element(value : T) -> Element {
  value.into_element()
}

///|
/// Result of the request-layout phase. Layout is resolved against the definite
/// root viewport and the original declarative tree is retained for prepaint.
/// For anchored attachments, `layout` describes the ordinary in-flow tree;
/// separately measured popup subtrees join structural order during prepaint.
/// Read the resulting ElementTree for complete final bounds and static
/// attachment bounds. Neither host-supplied final boxes nor relayout bypasses
/// participate in the attachment path.
pub struct RequestedLayout {
  priv placements : Array[ElementPlacement]
  priv scale_factor : Double?
  priv query_lease : Ref[Bool]?
  priv anchored_layout : AnchoredLayout?
  viewport : @primitives.Size
  layout : @layout.FlexTreeLayout
}

///|
/// Lifecycle traversal is iterative, while the current recursive layout
/// engine descends through nested containers. Keep the accepted depth bounded
/// so malformed or generated trees cannot exhaust the host stack.
pub const MAX_ELEMENT_DEPTH : Int32 = @layout.MAX_FLEX_TREE_DEPTH

///|
priv struct ElementPlacement {
  element : Element
  parent : UInt64?
  depth : Int32
}

///|
/// Result of the prepaint phase. The laid-out tree is ready for hit testing;
/// paint output is still a portable scene and contains no renderer handles.
pub struct Prepainted {
  tree : ElementTree
  viewport : @primitives.Size
  viewport_bounds : @primitives.Rect
  overflow : Bool
}

///|
pub fn Prepainted::tree(self : Prepainted) -> ElementTree {
  self.tree
}

///|
pub fn Prepainted::overflow(self : Prepainted) -> Bool {
  self.overflow
}

///|
pub fn Prepainted::viewport(self : Prepainted) -> @primitives.Size {
  self.viewport
}

///|
/// Logical origin-zero viewport used to freeze the painted scene.
pub fn Prepainted::viewport_bounds(self : Prepainted) -> @primitives.Rect {
  self.viewport_bounds
}

///|
/// The element lifecycle's request-layout phase. The root's children are
/// lowered to the recursive layout contract, which produces absolute logical
/// bounds before prepaint begins.
pub fn Element::request_layout(
  self : Element,
  viewport : @primitives.Size,
) -> Result[RequestedLayout, ElementError] {
  self.request_layout_internal(viewport, None)
}

///|
/// Run request-layout with an explicit device scale. The default
/// `request_layout` path continues to return raw logical layout bounds.
pub fn Element::request_layout_with_device_scale(
  self : Element,
  viewport : @primitives.Size,
  scale_factor : Double,
) -> Result[RequestedLayout, ElementError] {
  self.request_layout_internal(viewport, Some(scale_factor))
}

///|
fn Element::request_layout_internal(
  self : Element,
  viewport : @primitives.Size,
  scale_factor : Double?,
) -> Result[RequestedLayout, ElementError] {
  if has_anchored_elements(self) {
    return request_anchored_layout(self, viewport, scale_factor)
  }
  if has_mixed_layout(self) {
    return request_mixed_layout(self, viewport, scale_factor)
  }
  if !self.is_root {
    Err(RootRequired)
  } else {
    match self.children_style {
      None => Err(RootRequired)
      Some(style) =>
        match flatten_layout_tree(self) {
          Err(error) => Err(error)
          Ok((placements, nodes)) => {
            match validate_uniform_lists(placements) {
              Err(error) => return Err(error)
              Ok(_) => ()
            }
            for placement in placements {
              match placement.element.uniform_list {
                None => ()
                Some(list) => {
                  match scale_factor {
                    Some(scale) if !scroll_finite(scale) || scale <= 0.0 =>
                      return match
                        @layout.layout_flex_tree_with_device_scale(
                          self.id,
                          viewport,
                          style,
                          nodes,
                          scale,
                        ) {
                        Err(error) => Err(LayoutFailure(error))
                        Ok(_) => Err(GeometryFailure)
                      }
                    _ => ()
                  }
                  match measure_uniform_prototype(list, scale_factor) {
                    Err(error) => return Err(error)
                    Ok(_) => ()
                  }
                }
              }
            }
            match scale_factor {
              None =>
                match
                  @layout.layout_flex_tree(self.id, viewport, style, nodes) {
                  Err(error) => Err(LayoutFailure(error))
                  Ok(layout) =>
                    Ok({
                      placements,
                      viewport,
                      layout,
                      scale_factor,
                      query_lease: None,
                      anchored_layout: None,
                    })
                }
              Some(scale) =>
                match
                  @layout.layout_flex_tree_with_device_scale(
                    self.id,
                    viewport,
                    style,
                    nodes,
                    scale,
                  ) {
                  Err(error) => Err(LayoutFailure(error))
                  Ok(layout) =>
                    Ok({
                      placements,
                      viewport,
                      layout,
                      scale_factor,
                      query_lease: None,
                      anchored_layout: None,
                    })
                }
            }
          }
        }
    }
  }
}

///|
/// Run the prepaint phase after successful layout. It joins each resolved
/// absolute box with its declarative paint/focus metadata and validates the
/// resulting live element tree.
pub fn RequestedLayout::prepaint(
  self : RequestedLayout,
) -> Result[Prepainted, ElementError] {
  match self.anchored_layout {
    Some(anchored) => return prepaint_anchored(self, anchored)
    None => ()
  }
  match self.query_lease {
    Some(lease) => {
      if lease.val {
        return Err(AlreadyPrepainted)
      }
      lease.val = true
      return prepaint_container_queries(self)
    }
    None => ()
  }
  let nodes : Array[ElementNode] = []
  let layout_boxes = self.layout.items()
  let root_bounds = self.layout.root_bounds()
  let mut failure : ElementError? = None
  let mut index = 0
  while index < self.placements.length() && failure is None {
    let placement = self.placements[index]
    let element = placement.element
    let bounds = if element.is_root {
      Some(root_bounds)
    } else {
      let box_index = index - 1
      if box_index < 0 || box_index >= layout_boxes.length() {
        None
      } else if layout_boxes[box_index].id() != element.id {
        None
      } else {
        Some(layout_boxes[box_index].bounds())
      }
    }
    match bounds {
      None => failure = Some(GeometryFailure)
      Some(rect) => {
        let node = ElementNode::new(element.id, placement.parent, rect)
          .with_background(element.background)
          .with_focusable(element.focusable)
          .with_tab_index(element.tab_index)
          .with_tab_group_index(element.tab_group_index)
          .with_tab_stop(element.tab_stop)
          .with_pointer_events(element.pointer_events)
        nodes.push(node)
      }
    }
    index += 1
  }
  let failure = if failure is None &&
    layout_boxes.length() + 1 != self.placements.length() {
    Some(GeometryFailure)
  } else {
    failure
  }
  match failure {
    Some(error) => Err(error)
    None =>
      match resolve_scroll_nodes(nodes, self.placements, self.scale_factor) {
        Err(error) => Err(error)
        Ok(resolved) =>
          match expand_uniform_rows(resolved, self.scale_factor) {
            Err(error) => Err(error)
            Ok(expanded) =>
              match ElementTree::new(expanded) {
                Err(error) => Err(error)
                Ok(tree) =>
                  Ok({
                    tree,
                    viewport: self.viewport,
                    viewport_bounds: root_bounds,
                    overflow: self.layout.overflow(),
                  })
              }
          }
      }
  }
}

///|
/// Run the paint phase and produce an immutable-by-contract platform-neutral
/// command scene. A renderer can consume this scene without appearing in the
/// element API.
pub fn Prepainted::paint(self : Prepainted) -> @scene.Scene {
  self.tree.to_scene()
}

///|
/// Paint and freeze the current quad scene in the versioned portable v1
/// envelope, ready for a backend-neutral renderer boundary.
pub fn Prepainted::paint_snapshot(
  self : Prepainted,
  scale : Double,
) -> Result[@scene.SceneSnapshot, @scene.SceneError] {
  self.paint().snapshot_v1(self.viewport_bounds, scale)
}

///|
fn flatten_layout_tree(
  root : Element,
) -> Result[
  (Array[ElementPlacement], Array[@layout.FlexTreeNode]),
  ElementError,
] {
  let placements : Array[ElementPlacement] = [
    { element: root, parent: None, depth: 0, },
  ]
  let nodes : Array[@layout.FlexTreeNode] = []
  let pending : Array[ElementPlacement] = []
  push_children_reverse(root, 0, pending)
  let mut failure : ElementError? = None
  while pending.length() > 0 && failure is None {
    match pending.pop() {
      None => ()
      Some(placement) =>
        if placement.depth > MAX_ELEMENT_DEPTH {
          failure = Some(TreeTooDeep)
        } else if placement.element.is_root {
          failure = Some(InvalidChildRoot)
        } else {
          match placement.element.item {
            None => failure = Some(MissingLayoutItem)
            Some(item) => {
              let base = @layout.FlexTreeNode::new(
                item,
                match placement.parent {
                  None => root.id
                  Some(parent_id) => parent_id
                },
              )
              let node = match placement.element.children_style {
                None => base
                Some(style) => base.with_children(style)
              }
              nodes.push(node)
              placements.push(placement)
              push_children_reverse(placement.element, placement.depth, pending)
            }
          }
        }
    }
  }
  match failure {
    Some(error) => Err(error)
    None => Ok((placements, nodes))
  }
}

///|
fn push_children_reverse(
  parent : Element,
  parent_depth : Int32,
  pending : Array[ElementPlacement],
) -> Unit {
  let mut index = parent.children.length()
  while index > 0 {
    index -= 1
    pending.push({
      element: parent.children[index],
      parent: Some(parent.id),
      depth: parent_depth + 1,
    })
  }
}

///|
fn copy_elements(elements : Array[Element]) -> Array[Element] {
  let owned : Array[Element] = []
  for element in elements {
    owned.push(element)
  }
  owned
}
