///|
/// Structural failures for the recursive flex-tree layer. Existing flex-line
/// numeric errors are preserved in the `Flex` variant.
pub(all) enum TreeLayoutError {
  DuplicateId
  MissingParent
  InvalidPreorder
  MissingContainer
  TreeTooDeep
  Flex(LayoutError)
  GeometryFailure
  Grid(GridLayoutError)
  MismatchedItem
  UnsupportedIntrinsicGrid
  UnsupportedIntrinsicFlexBasis
} derive(Eq)

///|
/// Bounded recursion keeps measurement and recursive box placement independent
/// of untrusted host stack depth.
pub const MAX_FLEX_TREE_DEPTH : Int32 = 64

///|
pub extend TreeLayoutError with Eq::{not_equal, equal}

///|
/// Container-only style for a recursive flex node. Its size is supplied by the
/// parent allocation or measured from descendant bases when the corresponding
/// child dimensions are auto.
pub struct FlexTreeStyle {
  direction : FlowDirection
  wrap : FlexWrap
  gap_x : Double
  gap_y : Double
  padding : Insets
  border : Insets
  justify : JustifyContent
  align : AlignItems
  align_content : AlignContent
}

///|
pub fn FlexTreeStyle::new(direction : FlowDirection) -> FlexTreeStyle {
  {
    direction,
    wrap: FlexWrap::no_wrap(),
    gap_x: 0.0,
    gap_y: 0.0,
    padding: Insets::zero(),
    border: Insets::zero(),
    justify: JustifyContent::start(),
    align: AlignItems::start(),
    align_content: AlignContent::stretch(),
  }
}

///|
/// Set both physical gaps, replacing any earlier axis-specific settings.
pub fn FlexTreeStyle::with_gap(
  self : FlexTreeStyle,
  gap : Double,
) -> Result[FlexTreeStyle, LayoutError] {
  self.with_gaps(gap, gap)
}

///|
/// Set the physical horizontal gap while preserving the vertical gap.
/// This is the item gap in rows and the line gap in wrapped columns.
pub fn FlexTreeStyle::with_gap_x(
  self : FlexTreeStyle,
  gap : Double,
) -> Result[FlexTreeStyle, LayoutError] {
  self.with_gaps(gap, self.gap_y)
}

///|
/// Set the physical vertical gap while preserving the horizontal gap.
/// This is the item gap in columns and the line gap in wrapped rows.
pub fn FlexTreeStyle::with_gap_y(
  self : FlexTreeStyle,
  gap : Double,
) -> Result[FlexTreeStyle, LayoutError] {
  self.with_gaps(self.gap_x, gap)
}

///|
fn FlexTreeStyle::with_gaps(
  self : FlexTreeStyle,
  gap_x : Double,
  gap_y : Double,
) -> Result[FlexTreeStyle, LayoutError] {
  if !finite(gap_x) || !finite(gap_y) {
    Err(NonFiniteValue)
  } else if gap_x < 0.0 || gap_y < 0.0 {
    Err(NegativeValue)
  } else {
    Ok({
      direction: self.direction,
      wrap: self.wrap,
      gap_x,
      gap_y,
      padding: self.padding,
      border: self.border,
      justify: self.justify,
      align: self.align,
      align_content: self.align_content,
    })
  }
}

///|
pub fn FlexTreeStyle::with_insets(
  self : FlexTreeStyle,
  padding : Insets,
  border : Insets,
) -> FlexTreeStyle {
  {
    direction: self.direction,
    wrap: self.wrap,
    gap_x: self.gap_x,
    gap_y: self.gap_y,
    padding,
    border,
    justify: self.justify,
    align: self.align,
    align_content: self.align_content,
  }
}

///|
pub fn FlexTreeStyle::with_justify(
  self : FlexTreeStyle,
  justify : JustifyContent,
) -> FlexTreeStyle {
  {
    direction: self.direction,
    wrap: self.wrap,
    gap_x: self.gap_x,
    gap_y: self.gap_y,
    padding: self.padding,
    border: self.border,
    justify,
    align: self.align,
    align_content: self.align_content,
  }
}

///|
pub fn FlexTreeStyle::with_align(
  self : FlexTreeStyle,
  align : AlignItems,
) -> FlexTreeStyle {
  {
    direction: self.direction,
    wrap: self.wrap,
    gap_x: self.gap_x,
    gap_y: self.gap_y,
    padding: self.padding,
    border: self.border,
    justify: self.justify,
    align,
    align_content: self.align_content,
  }
}

///|
pub fn FlexTreeStyle::with_wrap(
  self : FlexTreeStyle,
  wrap : FlexWrap,
) -> FlexTreeStyle {
  {
    direction: self.direction,
    wrap,
    gap_x: self.gap_x,
    gap_y: self.gap_y,
    padding: self.padding,
    border: self.border,
    justify: self.justify,
    align: self.align,
    align_content: self.align_content,
  }
}

///|
/// Align wrapped child lines within this node's definite inner cross extent.
/// NoWrap ignores this setting; recursive auto measurement is unchanged.
pub fn FlexTreeStyle::with_align_content(
  self : FlexTreeStyle,
  align_content : AlignContent,
) -> FlexTreeStyle {
  {
    direction: self.direction,
    wrap: self.wrap,
    gap_x: self.gap_x,
    gap_y: self.gap_y,
    padding: self.padding,
    border: self.border,
    justify: self.justify,
    align: self.align,
    align_content,
  }
}

///|
/// One non-root node in a flat pre-order recursive layout tree. `item`
/// describes this node inside its parent; `children_style` describes the
/// container used for this node's direct children when present.
pub struct FlexTreeNode {
  item : FlexItem
  parent : UInt64
  children_style : FlexTreeStyle?
}

///|
pub fn FlexTreeNode::new(item : FlexItem, parent : UInt64) -> FlexTreeNode {
  { item, parent, children_style: None, }
}

///|
pub fn FlexTreeNode::with_children(
  self : FlexTreeNode,
  style : FlexTreeStyle,
) -> FlexTreeNode {
  { item: self.item, parent: self.parent, children_style: Some(style), }
}

///|
pub fn FlexTreeNode::id(self : FlexTreeNode) -> UInt64 {
  self.item.id()
}

///|
pub fn FlexTreeNode::parent(self : FlexTreeNode) -> UInt64 {
  self.parent
}

///|
/// Absolute result for one non-root node. Results are stored in stable pre-order.
pub struct TreeLayoutBox {
  id : UInt64
  bounds : @primitives.Rect
  overflow : Bool
}

///|
pub fn TreeLayoutBox::id(self : TreeLayoutBox) -> UInt64 {
  self.id
}

///|
pub fn TreeLayoutBox::bounds(self : TreeLayoutBox) -> @primitives.Rect {
  self.bounds
}

///|
pub fn TreeLayoutBox::overflow(self : TreeLayoutBox) -> Bool {
  self.overflow
}

///|
/// Recursive layout result. The root is the solved border box; `items` contains
/// every descendant in stable pre-order with absolute coordinates. The legacy
/// tree entry points fix the root to the viewport, while root-box entry points
/// may expand it to contain the root insets.
pub struct FlexTreeLayout {
  root_id : UInt64
  root_bounds : @primitives.Rect
  items : Array[TreeLayoutBox]
  overflow : Bool
  priv before_edge_snap : Array[(UInt64, @primitives.Rect)]
}

///|
pub fn FlexTreeLayout::root_id(self : FlexTreeLayout) -> UInt64 {
  self.root_id
}

///|
pub fn FlexTreeLayout::root_bounds(self : FlexTreeLayout) -> @primitives.Rect {
  self.root_bounds
}

///|
pub fn FlexTreeLayout::items(self : FlexTreeLayout) -> Array[TreeLayoutBox] {
  copy_tree_boxes(self.items)
}

///|
/// Solved absolute bounds after metric quantization but before final edge
/// snapping. Missing identities return None. Public root_bounds/items remain
/// snapped; only rectangles changed by edge snapping need retained storage.
pub fn FlexTreeLayout::bounds_before_edge_snap(
  self : FlexTreeLayout,
  id : UInt64,
) -> @primitives.Rect? {
  for (candidate, bounds) in self.before_edge_snap {
    if candidate == id {
      return Some(bounds)
    }
  }
  if self.root_id == id {
    return Some(self.root_bounds)
  }
  for item in self.items {
    if item.id == id {
      return Some(item.bounds)
    }
  }
  None
}

///|
pub fn FlexTreeLayout::overflow(self : FlexTreeLayout) -> Bool {
  self.overflow
}

///|
/// Recursively lay out a flat pre-order tree. The root viewport is definite;
/// descendants with auto dimensions derive intrinsic sizes from their content
/// and insets. Percentages against an auto-measured axis are rejected as
/// indefinite. Any node with children must opt into a `FlexTreeStyle`.
pub fn layout_flex_tree(
  root_id : UInt64,
  root_size : @primitives.Size,
  root_style : FlexTreeStyle,
  nodes : Array[FlexTreeNode],
) -> Result[FlexTreeLayout, TreeLayoutError] {
  layout_flex_tree_with_root_sizing(
    root_id,
    root_size,
    root_style,
    nodes,
    FixedViewport,
  )
}

///|
/// Lay out an authored root border box using the offered size as a minimum.
/// Each axis is at least the sum of its root padding and border, even when the
/// tree has no children. The returned root may therefore exceed the offered
/// physical viewport; callers must retain that viewport independently.
/// Descendant layout and validation follow `layout_flex_tree`.
pub fn layout_flex_root_box(
  root_id : UInt64,
  offered_size : @primitives.Size,
  root_style : FlexTreeStyle,
  nodes : Array[FlexTreeNode],
) -> Result[FlexTreeLayout, TreeLayoutError] {
  layout_flex_tree_with_root_sizing(
    root_id,
    offered_size,
    root_style,
    nodes,
    InsetsMinimum,
  )
}

///|
priv enum FlexRootSizing {
  FixedViewport
  InsetsMinimum
}

///|
fn flex_tree_root_bounds(
  root_size : @primitives.Size,
  root_style : FlexTreeStyle,
  root_sizing : FlexRootSizing,
) -> Result[@primitives.Rect, TreeLayoutError] {
  let mut width = root_size.width()
  let mut height = root_size.height()
  match root_sizing {
    FixedViewport => ()
    InsetsMinimum => {
      let horizontal = root_style.padding.left() +
        root_style.padding.right() +
        root_style.border.left() +
        root_style.border.right()
      let vertical = root_style.padding.top() +
        root_style.padding.bottom() +
        root_style.border.top() +
        root_style.border.bottom()
      if !finite(horizontal) || !finite(vertical) {
        return Err(Flex(NonFiniteValue))
      }
      if horizontal > width {
        width = horizontal
      }
      if vertical > height {
        height = vertical
      }
    }
  }
  match @primitives.Rect::new(0.0, 0.0, width, height) {
    Ok(bounds) => Ok(bounds)
    Err(_) => Err(GeometryFailure)
  }
}

///|
fn flex_tree_root_exceeds_offer(
  root_bounds : @primitives.Rect,
  root_size : @primitives.Size,
  root_sizing : FlexRootSizing,
) -> Bool {
  match root_sizing {
    FixedViewport => false
    InsetsMinimum =>
      root_bounds.size().width() > root_size.width() ||
      root_bounds.size().height() > root_size.height()
  }
}

///|
fn layout_flex_tree_with_root_sizing(
  root_id : UInt64,
  root_size : @primitives.Size,
  root_style : FlexTreeStyle,
  nodes : Array[FlexTreeNode],
  root_sizing : FlexRootSizing,
  device_grid~ : Bool = false,
) -> Result[FlexTreeLayout, TreeLayoutError] {
  match validate_tree_preorder(root_id, nodes) {
    Err(error) => Err(error)
    Ok(_) =>
      match flex_tree_root_bounds(root_size, root_style, root_sizing) {
        Err(error) => Err(error)
        Ok(root_bounds) => {
          let output : Array[TreeLayoutBox] = []
          let overflow = Ref(
            flex_tree_root_exceeds_offer(root_bounds, root_size, root_sizing),
          )
          match
            layout_tree_children(
              root_id, root_bounds, root_style, nodes, output, overflow, 0, device_grid,
            ) {
            Err(error) => Err(error)
            Ok(_) =>
              Ok({
                root_id,
                root_bounds,
                items: output,
                overflow: overflow.val,
                before_edge_snap: [],
              })
          }
        }
      }
  }
}

///|
/// Lay out a flex tree with GPUI's device-grid layout boundaries while keeping
/// `layout_flex_tree` available for raw logical layout. Absolute style lengths
/// are rounded before flex resolution, measured intrinsic sizes are ceiled,
/// and the resulting absolute outer edges are rounded after layout. Paint and
/// raster quantization are outside this API.
pub fn layout_flex_tree_with_device_scale(
  root_id : UInt64,
  root_size : @primitives.Size,
  root_style : FlexTreeStyle,
  nodes : Array[FlexTreeNode],
  scale_factor : Double,
) -> Result[FlexTreeLayout, TreeLayoutError] {
  layout_flex_tree_with_device_scale_and_root_sizing(
    root_id,
    root_size,
    root_style,
    nodes,
    scale_factor,
    FixedViewport,
  )
}

///|
/// Device-grid variant of `layout_flex_root_box`. Authored padding and border
/// are snapped before the root inset minimum is computed, including the
/// existing one-device-pixel minimum for positive borders. Final absolute
/// edges are snapped afterward; `bounds_before_edge_snap` retains the solved
/// root. The offered physical viewport remains the caller's responsibility.
pub fn layout_flex_root_box_with_device_scale(
  root_id : UInt64,
  offered_size : @primitives.Size,
  root_style : FlexTreeStyle,
  nodes : Array[FlexTreeNode],
  scale_factor : Double,
) -> Result[FlexTreeLayout, TreeLayoutError] {
  layout_flex_tree_with_device_scale_and_root_sizing(
    root_id,
    offered_size,
    root_style,
    nodes,
    scale_factor,
    InsetsMinimum,
  )
}

///|
fn layout_flex_tree_with_device_scale_and_root_sizing(
  root_id : UInt64,
  root_size : @primitives.Size,
  root_style : FlexTreeStyle,
  nodes : Array[FlexTreeNode],
  scale_factor : Double,
  root_sizing : FlexRootSizing,
) -> Result[FlexTreeLayout, TreeLayoutError] {
  if !finite(scale_factor) {
    Err(Flex(NonFiniteValue))
  } else if scale_factor <= 0.0 {
    Err(Flex(NegativeValue))
  } else {
    let device_root_size = match
      @primitives.Size::new(
        root_size.width() * scale_factor,
        root_size.height() * scale_factor,
      ) {
      Ok(value) => value
      Err(_) => return Err(Flex(NonFiniteValue))
    }
    match prepare_tree_style_in_device_pixels(root_style, scale_factor) {
      Err(error) => Err(Flex(error))
      Ok(snapped_root_style) => {
        let snapped_nodes : Array[FlexTreeNode] = []
        let mut failure : TreeLayoutError? = None
        for node in nodes {
          if failure is None {
            match prepare_tree_item_in_device_pixels(node.item, scale_factor) {
              Err(error) => failure = Some(Flex(error))
              Ok(item) =>
                match node.children_style {
                  None =>
                    snapped_nodes.push({
                      item,
                      parent: node.parent,
                      children_style: None,
                    })
                  Some(style) =>
                    match
                      prepare_tree_style_in_device_pixels(style, scale_factor) {
                      Err(error) => failure = Some(Flex(error))
                      Ok(children_style) =>
                        snapped_nodes.push({
                          item,
                          parent: node.parent,
                          children_style: Some(children_style),
                        })
                    }
                }
            }
          }
        }
        match failure {
          Some(error) => Err(error)
          None =>
            match
              layout_flex_tree_with_root_sizing(
                root_id,
                device_root_size,
                snapped_root_style,
                snapped_nodes,
                root_sizing,
                device_grid=true,
              ) {
              Err(error) => Err(error)
              Ok(layout) => {
                let root_bounds = match
                  logical_rect_from_device_pixels(
                    layout.root_bounds,
                    scale_factor,
                    snap_edges=true,
                  ) {
                  Ok(bounds) => bounds
                  Err(error) => return Err(Flex(error))
                }
                let before_edge_snap : Array[(UInt64, @primitives.Rect)] = []
                let raw_root = match
                  logical_rect_from_device_pixels(
                    layout.root_bounds,
                    scale_factor,
                  ) {
                  Ok(bounds) => bounds
                  Err(error) => return Err(Flex(error))
                }
                if root_bounds != raw_root {
                  before_edge_snap.push((layout.root_id, raw_root))
                }
                let items : Array[TreeLayoutBox] = []
                for item in layout.items {
                  let bounds = match
                    logical_rect_from_device_pixels(
                      item.bounds,
                      scale_factor,
                      snap_edges=true,
                    ) {
                    Ok(bounds) => bounds
                    Err(error) => return Err(Flex(error))
                  }
                  let raw_bounds = match
                    logical_rect_from_device_pixels(item.bounds, scale_factor) {
                    Ok(bounds) => bounds
                    Err(error) => return Err(Flex(error))
                  }
                  if bounds != raw_bounds {
                    before_edge_snap.push((item.id, raw_bounds))
                  }
                  items.push({ id: item.id, bounds, overflow: item.overflow, })
                }
                Ok({
                  root_id: layout.root_id,
                  root_bounds,
                  items,
                  overflow: layout.overflow ||
                  flex_tree_root_exceeds_offer(
                    root_bounds, root_size, root_sizing,
                  ),
                  before_edge_snap,
                })
              }
            }
        }
      }
    }
  }
}

///|
fn prepare_tree_item_in_device_pixels(
  item : FlexItem,
  scale_factor : Double,
) -> Result[FlexItem, LayoutError] {
  let flex_basis = match item.flex_basis {
    Auto => FlexBasis::Auto
    Percent(ratio) => FlexBasis::Percent(ratio)
    Points(value) =>
      match authored_length_in_device_pixels(value, scale_factor) {
        Ok(snapped) => FlexBasis::Points(snapped)
        Err(error) => return Err(error)
      }
  }
  let main = match prepare_dimension_in_device_pixels(item.main, scale_factor) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let cross = match
    prepare_dimension_in_device_pixels(item.cross, scale_factor) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let min_main = match
    authored_length_in_device_pixels(item.min_main, scale_factor) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let max_main = match
    prepare_optional_length_in_device_pixels(item.max_main, scale_factor) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let min_cross = match
    authored_length_in_device_pixels(item.min_cross, scale_factor) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let max_cross = match
    prepare_optional_length_in_device_pixels(item.max_cross, scale_factor) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let intrinsic_width = match
    measured_length_in_device_pixels(item.intrinsic.width(), scale_factor) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let intrinsic_height = match
    measured_length_in_device_pixels(item.intrinsic.height(), scale_factor) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  match @primitives.Size::new(intrinsic_width, intrinsic_height) {
    Err(_) => Err(GeometryFailure)
    Ok(intrinsic) =>
      Ok({
        id: item.id,
        main,
        cross,
        intrinsic,
        grow: item.grow,
        shrink: item.shrink,
        min_main,
        max_main,
        min_cross,
        max_cross,
        align_self: item.align_self,
        flex_basis,
      })
  }
}

///|
fn prepare_dimension_in_device_pixels(
  dimension : Dimension,
  scale_factor : Double,
) -> Result[Dimension, LayoutError] {
  match dimension {
    Auto => Ok(Auto)
    Points(value) =>
      match authored_length_in_device_pixels(value, scale_factor) {
        Ok(snapped) => Ok(Points(snapped))
        Err(error) => Err(error)
      }
    Percent(value) => Ok(Percent(value))
  }
}

///|
fn prepare_optional_length_in_device_pixels(
  value : Double?,
  scale_factor : Double,
) -> Result[Double?, LayoutError] {
  match value {
    None => Ok(None)
    Some(value) =>
      match authored_length_in_device_pixels(value, scale_factor) {
        Ok(snapped) => Ok(Some(snapped))
        Err(error) => Err(error)
      }
  }
}

///|
fn prepare_insets_in_device_pixels(
  insets : Insets,
  scale_factor : Double,
  stroke : Bool,
) -> Result[Insets, LayoutError] {
  let snap = fn(value) {
    if stroke && value > 0.0 {
      match authored_length_in_device_pixels(value, scale_factor) {
        Err(error) => Err(error)
        Ok(snapped) => Ok(if snapped < 1.0 { 1.0 } else { snapped })
      }
    } else {
      authored_length_in_device_pixels(value, scale_factor)
    }
  }
  let top = match snap(insets.top()) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let right = match snap(insets.right()) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let bottom = match snap(insets.bottom()) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let left = match snap(insets.left()) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  Insets::new(top, right, bottom, left)
}

///|
fn prepare_tree_style_in_device_pixels(
  style : FlexTreeStyle,
  scale_factor : Double,
) -> Result[FlexTreeStyle, LayoutError] {
  let gap_x = match
    authored_length_in_device_pixels(style.gap_x, scale_factor) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let gap_y = match
    authored_length_in_device_pixels(style.gap_y, scale_factor) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let padding = match
    prepare_insets_in_device_pixels(style.padding, scale_factor, false) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let border = match
    prepare_insets_in_device_pixels(style.border, scale_factor, true) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  Ok({
    direction: style.direction,
    wrap: style.wrap,
    gap_x,
    gap_y,
    padding,
    border,
    justify: style.justify,
    align: style.align,
    align_content: style.align_content,
  })
}

///|
fn layout_tree_children(
  parent_id : UInt64,
  parent_bounds : @primitives.Rect,
  style : FlexTreeStyle,
  nodes : Array[FlexTreeNode],
  output : Array[TreeLayoutBox],
  overflow : Ref[Bool],
  depth : Int32,
  device_grid : Bool,
) -> Result[Unit, TreeLayoutError] {
  let direct_nodes : Array[FlexTreeNode] = []
  for node in nodes {
    if node.parent == parent_id {
      direct_nodes.push(node)
    }
  }
  if direct_nodes.length() == 0 {
    Ok(())
  } else {
    let base = FlexContainer::new(style.direction, parent_bounds.size())
      .with_wrap(style.wrap)
      .with_insets(style.padding, style.border)
      .with_justify(style.justify)
      .with_align(style.align)
      .with_align_content(style.align_content)
    match base.with_gaps(style.gap_x, style.gap_y) {
      Err(error) => Err(Flex(error))
      Ok(container) =>
        match
          measure_direct_items(direct_nodes, style.direction, nodes, depth) {
          Err(error) => Err(error)
          Ok(direct_items) =>
            match
              layout_flex_internal(
                container,
                direct_items,
                device_grid &&
                (if style.direction.is_row() {
                  parent_bounds.left() == 0.0
                } else {
                  parent_bounds.top() == 0.0
                }),
              ) {
              Err(error) => Err(Flex(error))
              Ok(line) => {
                if line.overflow() {
                  overflow.val = true
                }
                let local_boxes = line.items()
                let mut failure : TreeLayoutError? = None
                let mut index = 0
                while index < direct_nodes.length() && failure is None {
                  let node = direct_nodes[index]
                  let child_box = local_boxes[index]
                  let local_bounds = child_box.bounds()
                  match
                    @primitives.Rect::new(
                      parent_bounds.left() + local_bounds.left(),
                      parent_bounds.top() + local_bounds.top(),
                      local_bounds.size().width(),
                      local_bounds.size().height(),
                    ) {
                    Err(_) => failure = Some(GeometryFailure)
                    Ok(bounds) => {
                      if child_box.overflow() {
                        overflow.val = true
                      }
                      output.push({
                        id: node.id(),
                        bounds,
                        overflow: child_box.overflow(),
                      })
                      let has_children = tree_has_direct_children(
                        node.id(),
                        nodes,
                      )
                      if has_children {
                        match node.children_style {
                          None => failure = Some(MissingContainer)
                          Some(child_style) =>
                            match
                              layout_tree_children(
                                node.id(),
                                bounds,
                                child_style,
                                nodes,
                                output,
                                overflow,
                                depth + 1,
                                device_grid,
                              ) {
                              Err(error) => failure = Some(error)
                              Ok(_) => ()
                            }
                        }
                      }
                    }
                  }
                  index += 1
                }
                match failure {
                  Some(error) => Err(error)
                  None => Ok(())
                }
              }
            }
        }
    }
  }
}

///|
/// Before laying out a flex line, fill intrinsic fallbacks for auto dimensions
/// of container children from descendant content. Explicit points and percent
/// dimensions keep the behavior of the regular definite flex line.
fn measure_direct_items(
  nodes_for_parent : Array[FlexTreeNode],
  direction : FlowDirection,
  all_nodes : Array[FlexTreeNode],
  parent_depth : Int32,
) -> Result[Array[FlexItem], TreeLayoutError] {
  let items : Array[FlexItem] = []
  let mut failure : TreeLayoutError? = None
  for node in nodes_for_parent {
    if failure is None {
      match
        measure_item_intrinsic(node, direction, all_nodes, parent_depth + 1) {
        Err(error) => failure = Some(error)
        Ok(item) => items.push(item)
      }
    }
  }
  match failure {
    Some(error) => Err(error)
    None => Ok(items)
  }
}

///|
fn measure_item_intrinsic(
  node : FlexTreeNode,
  parent_direction : FlowDirection,
  all_nodes : Array[FlexTreeNode],
  depth : Int32,
) -> Result[FlexItem, TreeLayoutError] {
  let item = node.item
  let mut width = item.intrinsic.width()
  let mut height = item.intrinsic.height()
  let width_axis = match parent_direction {
    Row | RowReverse => item.main
    Column | ColumnReverse => item.cross
  }
  let height_axis = match parent_direction {
    Row | RowReverse => item.cross
    Column | ColumnReverse => item.main
  }
  let mut failure : TreeLayoutError? = None
  match (width_axis, node.children_style) {
    (Auto, Some(style)) =>
      match
        measure_container_axis(node.id(), style, WidthAxis, all_nodes, depth) {
        Err(error) => failure = Some(error)
        Ok(value) => width = value
      }
    _ => ()
  }
  match (height_axis, node.children_style) {
    (Auto, Some(style)) if failure is None =>
      match
        measure_container_axis(node.id(), style, HeightAxis, all_nodes, depth) {
        Err(error) => failure = Some(error)
        Ok(value) => height = value
      }
    _ => ()
  }
  match failure {
    Some(error) => Err(error)
    None =>
      match @primitives.Size::new(width, height) {
        Err(_) => Err(GeometryFailure)
        Ok(intrinsic) => Ok(item.with_intrinsic(intrinsic))
      }
  }
}

///|
priv enum MeasureAxis {
  WidthAxis
  HeightAxis
}

///|
// Point bases in a nowrap, completely inflexible intrinsic line have a
// bounded max-content contribution. Other intrinsic flex negotiation is not
// implemented. Auto-only flexible/wrapped lines retain prior measurement.
fn intrinsic_zero_flex_mode(
  style : FlexTreeStyle,
  items : Array[FlexItem],
) -> Result[Bool, TreeLayoutError] {
  let mut has_points = false
  for item in items {
    match item.flex_basis {
      Auto => ()
      Points(_) => has_points = true
      Percent(_) => return Err(UnsupportedIntrinsicFlexBasis)
    }
  }
  let mut bounded = style.wrap is NoWrap
  for item in items {
    if item.grow != 0.0 || item.shrink != 0.0 {
      bounded = false
    }
  }
  if has_points && !bounded {
    Err(UnsupportedIntrinsicFlexBasis)
  } else {
    Ok(bounded)
  }
}

///|
// The preferred authored main size can enlarge a zero-flex child's intrinsic
// contribution beyond its point basis. Its max-main limit bounds the eventual
// child box, not this contribution (pinned GPUI/Taffy max-content behavior).
fn intrinsic_point_contribution(
  item : FlexItem,
  preferred : Double?,
) -> Result[Double, TreeLayoutError] {
  let authored = preferred.unwrap_or(0.0)
  match item.resolved_flex_basis(authored, 0.0) {
    Err(error) => Err(Flex(error))
    Ok(basis) => Ok(if basis > authored { basis } else { authored })
  }
}

///|
/// Measure only the requested physical axis. This is important for mixed
/// definite/auto containers: a percentage on a definite orthogonal axis is
/// left for layout, while a percentage against the measured auto axis fails.
fn measure_container_axis(
  parent_id : UInt64,
  style : FlexTreeStyle,
  axis : MeasureAxis,
  nodes : Array[FlexTreeNode],
  depth : Int32,
) -> Result[Double, TreeLayoutError] {
  if depth > MAX_FLEX_TREE_DEPTH {
    Err(TreeTooDeep)
  } else {
    let axis_is_main = match (style.direction, axis) {
      (Row, WidthAxis)
      | (RowReverse, WidthAxis)
      | (Column, HeightAxis)
      | (ColumnReverse, HeightAxis) => true
      _ => false
    }
    let zero_flex_mode = if axis_is_main {
      let items : Array[FlexItem] = []
      for node in nodes {
        if node.parent == parent_id {
          items.push(node.item)
        }
      }
      match intrinsic_zero_flex_mode(style, items) {
        Err(error) => return Err(error)
        Ok(value) => value
      }
    } else {
      false
    }
    let mut count = 0
    let mut total = 0.0
    let mut maximum = 0.0
    let mut failure : TreeLayoutError? = None
    for node in nodes {
      if node.parent == parent_id && failure is None {
        count += 1
        let item = node.item
        let (dimension, minimum, maximum_value) = if axis_is_main {
          (item.main, item.min_main, item.max_main)
        } else {
          (item.cross, item.min_cross, item.max_cross)
        }
        if !valid_limits(minimum, maximum_value) {
          failure = Some(Flex(InvalidMinMax))
        } else {
          match resolve_dimension(dimension, None) {
            Err(error) => failure = Some(Flex(error))
            Ok(resolved) => {
              let natural = if zero_flex_mode && item.flex_basis is Points(_) {
                intrinsic_point_contribution(item, resolved)
              } else {
                match resolved {
                  Some(value) => Ok(value)
                  None =>
                    measure_child_intrinsic_axis(node, axis, nodes, depth + 1)
                }
              }
              match natural {
                Err(error) => failure = Some(error)
                Ok(value) => {
                  let bounded = if zero_flex_mode {
                    if value < minimum {
                      minimum
                    } else {
                      value
                    }
                  } else {
                    clamp_once(value, minimum, maximum_value)
                  }
                  if !finite(bounded) {
                    failure = Some(Flex(NonFiniteValue))
                  } else if axis_is_main {
                    total += bounded
                    if !finite(total) {
                      failure = Some(Flex(NonFiniteValue))
                    }
                  } else if bounded > maximum {
                    maximum = bounded
                  }
                }
              }
            }
          }
        }
      }
    }
    match failure {
      Some(error) => Err(error)
      None => {
        let horizontal_insets = style.padding.left() +
          style.padding.right() +
          style.border.left() +
          style.border.right()
        let vertical_insets = style.padding.top() +
          style.padding.bottom() +
          style.border.top() +
          style.border.bottom()
        let insets = match axis {
          WidthAxis => horizontal_insets
          HeightAxis => vertical_insets
        }
        let gaps = if axis_is_main && count > 1 {
          (count - 1).to_double() *
          (if style.direction.is_row() { style.gap_x } else { style.gap_y })
        } else {
          0.0
        }
        let content = if axis_is_main { total + gaps } else { maximum }
        let measured = content + insets
        if !finite(horizontal_insets) ||
          !finite(vertical_insets) ||
          !finite(gaps) ||
          !finite(measured) {
          Err(Flex(NonFiniteValue))
        } else {
          Ok(measured)
        }
      }
    }
  }
}

///|
fn measure_child_intrinsic_axis(
  node : FlexTreeNode,
  axis : MeasureAxis,
  nodes : Array[FlexTreeNode],
  depth : Int32,
) -> Result[Double, TreeLayoutError] {
  match node.children_style {
    Some(style) => measure_container_axis(node.id(), style, axis, nodes, depth)
    None =>
      if tree_has_direct_children(node.id(), nodes) {
        Err(MissingContainer)
      } else {
        Ok(
          match axis {
            WidthAxis => node.item.intrinsic.width()
            HeightAxis => node.item.intrinsic.height()
          },
        )
      }
  }
}

///|
fn validate_tree_preorder(
  root_id : UInt64,
  nodes : Array[FlexTreeNode],
) -> Result[Unit, TreeLayoutError] {
  let seen : Array[UInt64] = [root_id]
  let mut ancestors : Array[UInt64] = [root_id]
  let mut failure : TreeLayoutError? = None
  let mut index = 0
  while index < nodes.length() && failure is None {
    let node = nodes[index]
    let id = node.id()
    let mut duplicate = false
    let mut seen_index = 0
    while seen_index < seen.length() && !duplicate {
      if seen[seen_index] == id {
        duplicate = true
      }
      seen_index += 1
    }
    if duplicate {
      failure = Some(DuplicateId)
    } else {
      let mut parent_depth = -1
      let mut ancestor_index = ancestors.length()
      while ancestor_index > 0 && parent_depth < 0 {
        ancestor_index -= 1
        if ancestors[ancestor_index] == node.parent {
          parent_depth = ancestor_index
        }
      }
      if parent_depth < 0 {
        let mut parent_seen = false
        seen_index = 0
        while seen_index < seen.length() && !parent_seen {
          if seen[seen_index] == node.parent {
            parent_seen = true
          }
          seen_index += 1
        }
        failure = if parent_seen {
          Some(InvalidPreorder)
        } else {
          Some(MissingParent)
        }
      } else if parent_depth >= MAX_FLEX_TREE_DEPTH {
        failure = Some(TreeTooDeep)
      } else {
        let next : Array[UInt64] = []
        let mut depth = 0
        while depth <= parent_depth {
          next.push(ancestors[depth])
          depth += 1
        }
        next.push(id)
        ancestors = next
        seen.push(id)
      }
    }
    index += 1
  }
  match failure {
    Some(error) => Err(error)
    None => Ok(())
  }
}

///|
fn tree_has_direct_children(id : UInt64, nodes : Array[FlexTreeNode]) -> Bool {
  let mut found = false
  let mut index = 0
  while index < nodes.length() && !found {
    if nodes[index].parent == id {
      found = true
    }
    index += 1
  }
  found
}

///|
fn copy_tree_boxes(values : Array[TreeLayoutBox]) -> Array[TreeLayoutBox] {
  let copy : Array[TreeLayoutBox] = []
  for value in values {
    copy.push(value)
  }
  copy
}
