///|
/// Opt-in mixed dispatch. Existing flex-only entry points remain unchanged.
pub(all) enum MixedTreeStyle {
  FlexStyle(FlexTreeStyle)
  GridStyle(GridTreeStyle)
}

///|
pub(all) enum MixedTreeItem {
  FlexChild(FlexItem)
  GridChild(GridItem)
}

///|
pub struct MixedTreeNode {
  item : MixedTreeItem
  parent : UInt64
  children_style : MixedTreeStyle?
}

///|
pub fn MixedTreeNode::new(
  item : MixedTreeItem,
  parent : UInt64,
  children_style : MixedTreeStyle?,
) -> MixedTreeNode {
  { item, parent, children_style, }
}

///|
pub fn MixedTreeNode::id(self : MixedTreeNode) -> UInt64 {
  match self.item {
    FlexChild(item) => item.id
    GridChild(item) => item.id
  }
}

///|
/// Lay out all descendants in raw absolute coordinates before snapping any
/// final edge. A supplied origin participates in this tree's edge rounding.
/// Independent query roots lay out at zero and translate the rounded result.
/// Optional root_size is an authored physical size, snapped before descendants
/// are resolved; omitted root_size keeps the offered definite root bounds.
pub fn layout_mixed_tree_at(
  root_id : UInt64,
  root_bounds : @primitives.Rect,
  root_style : MixedTreeStyle,
  nodes : Array[MixedTreeNode],
  scale_factor : Double?,
  root_size? : @primitives.Size,
) -> Result[FlexTreeLayout, TreeLayoutError] {
  let zero = @primitives.Size::new(0.0, 0.0).unwrap()
  let structural : Array[FlexTreeNode] = []
  for node in nodes {
    structural.push(
      FlexTreeNode::new(FlexItem::new(node.id(), Auto, Auto, zero), node.parent),
    )
  }
  match validate_tree_preorder(root_id, structural) {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  let prepared : Array[MixedTreeNode] = []
  let style = match scale_factor {
    None => root_style
    Some(scale) => {
      if !finite(scale) {
        return Err(Flex(NonFiniteValue))
      }
      if scale <= 0.0 {
        return Err(Flex(NegativeValue))
      }
      match snap_mixed_style(root_style, scale) {
        Ok(style) => style
        Err(error) => return Err(error)
      }
    }
  }
  for node in nodes {
    match scale_factor {
      None => prepared.push(node)
      Some(scale) => {
        let item = match node.item {
          FlexChild(item) =>
            match snap_tree_item_to_device_scale(item, scale) {
              Ok(item) => FlexChild(item)
              Err(error) => return Err(Flex(error))
            }
          GridChild(item) => {
            let width = match
              snap_dimension_to_device_scale(item.width, scale) {
              Ok(value) => value
              Err(error) => return Err(Flex(error))
            }
            let height = match
              snap_dimension_to_device_scale(item.height, scale) {
              Ok(value) => value
              Err(error) => return Err(Flex(error))
            }
            GridChild({ ..item, width, height, })
          }
        }
        let children_style = match node.children_style {
          None => None
          Some(style) =>
            match snap_mixed_style(style, scale) {
              Ok(style) => Some(style)
              Err(error) => return Err(error)
            }
        }
        prepared.push({ ..node, item, children_style, })
      }
    }
  }
  let root_bounds = match root_size {
    None => root_bounds
    Some(size) => {
      let width = match scale_factor {
        None => size.width()
        Some(scale) =>
          match snap_authored_length_to_device_grid(size.width(), scale) {
            Ok(value) => value
            Err(error) => return Err(Flex(error))
          }
      }
      let height = match scale_factor {
        None => size.height()
        Some(scale) =>
          match snap_authored_length_to_device_grid(size.height(), scale) {
            Ok(value) => value
            Err(error) => return Err(Flex(error))
          }
      }
      match
        @primitives.Rect::new(
          root_bounds.left(),
          root_bounds.top(),
          width,
          height,
        ) {
        Ok(value) => value
        Err(_) => return Err(GeometryFailure)
      }
    }
  }
  let output : Array[TreeLayoutBox] = []
  let overflow = Ref(false)
  match
    layout_mixed_children(
      root_id, root_bounds, style, prepared, output, overflow, 0,
    ) {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  let mut final_root = root_bounds
  let final_items : Array[TreeLayoutBox] = []
  let before_edge_snap : Array[(UInt64, @primitives.Rect)] = []
  match scale_factor {
    None =>
      for item in output {
        final_items.push(item)
      }
    Some(scale) => {
      final_root = match snap_absolute_rect_to_device_grid(root_bounds, scale) {
        Ok(bounds) => bounds
        Err(error) => return Err(Flex(error))
      }
      if final_root != root_bounds {
        before_edge_snap.push((root_id, root_bounds))
      }
      for item in output {
        let bounds = match
          snap_absolute_rect_to_device_grid(item.bounds, scale) {
          Ok(bounds) => bounds
          Err(error) => return Err(Flex(error))
        }
        if bounds != item.bounds {
          before_edge_snap.push((item.id, item.bounds))
        }
        final_items.push({ ..item, bounds, })
      }
    }
  }
  Ok({
    root_id,
    root_bounds: final_root,
    items: final_items,
    overflow: overflow.val,
    before_edge_snap,
  })
}

///|
fn snap_mixed_style(
  style : MixedTreeStyle,
  scale : Double,
) -> Result[MixedTreeStyle, TreeLayoutError] {
  match style {
    FlexStyle(style) =>
      match snap_tree_style_to_device_scale(style, scale) {
        Ok(style) => Ok(FlexStyle(style))
        Err(error) => Err(Flex(error))
      }
    GridStyle(style) => {
      let gap_x = match
        snap_authored_length_to_device_grid(style.gap_x, scale) {
        Ok(value) => value
        Err(error) => return Err(Flex(error))
      }
      let gap_y = match
        snap_authored_length_to_device_grid(style.gap_y, scale) {
        Ok(value) => value
        Err(error) => return Err(Flex(error))
      }
      let padding = match
        snap_layout_insets_to_device_scale(style.padding, scale, false) {
        Ok(value) => value
        Err(error) => return Err(Flex(error))
      }
      let border = match
        snap_layout_insets_to_device_scale(style.border, scale, true) {
        Ok(value) => value
        Err(error) => return Err(Flex(error))
      }
      Ok(GridStyle({ ..style, gap_x, gap_y, padding, border, }))
    }
  }
}

///|
fn layout_mixed_children(
  parent : UInt64,
  bounds : @primitives.Rect,
  style : MixedTreeStyle,
  nodes : Array[MixedTreeNode],
  output : Array[TreeLayoutBox],
  overflow : Ref[Bool],
  depth : Int32,
) -> Result[Unit, TreeLayoutError] {
  if depth > MAX_FLEX_TREE_DEPTH {
    return Err(TreeTooDeep)
  }
  let children : Array[MixedTreeNode] = []
  for node in nodes {
    if node.parent == parent {
      children.push(node)
    }
  }
  let boxes : Array[LayoutBox] = match style {
    GridStyle(style) => {
      let items : Array[GridItem] = []
      for node in children {
        match node.item {
          GridChild(item) => items.push(item)
          _ => return Err(MismatchedItem)
        }
      }
      match layout_grid(GridContainer::new(bounds.size(), style), items) {
        Err(error) => return Err(Grid(error))
        Ok(layout) => {
          overflow.val = overflow.val || layout.overflow
          layout.items
        }
      }
    }
    FlexStyle(style) => {
      let items : Array[FlexItem] = []
      for node in children {
        let item = match node.item {
          FlexChild(item) => item
          _ => return Err(MismatchedItem)
        }
        let mut width = item.intrinsic.width()
        let mut height = item.intrinsic.height()
        let (width_dimension, height_dimension) = if style.direction.is_row() {
          (item.main, item.cross)
        } else {
          (item.cross, item.main)
        }
        if width_dimension is Auto {
          width = match measure_mixed_child(node, WidthAxis, nodes, depth + 1) {
            Ok(value) => value
            Err(error) => return Err(error)
          }
        }
        if height_dimension is Auto {
          height = match
            measure_mixed_child(node, HeightAxis, nodes, depth + 1) {
            Ok(value) => value
            Err(error) => return Err(error)
          }
        }
        let intrinsic = match @primitives.Size::new(width, height) {
          Ok(value) => value
          Err(_) => return Err(GeometryFailure)
        }
        items.push(item.with_intrinsic(intrinsic))
      }
      let container = FlexContainer::new(style.direction, bounds.size())
        .with_wrap(style.wrap)
        .with_insets(style.padding, style.border)
        .with_justify(style.justify)
        .with_align(style.align)
        .with_align_content(style.align_content)
      let container = match container.with_gaps(style.gap_x, style.gap_y) {
        Ok(value) => value
        Err(error) => return Err(Flex(error))
      }
      match layout_flex(container, items) {
        Err(error) => return Err(Flex(error))
        Ok(layout) => {
          overflow.val = overflow.val || layout.overflow
          layout.items
        }
      }
    }
  }
  for index = 0; index < children.length(); index = index + 1 {
    let child = children[index]
    let local_box = boxes[index]
    let absolute = match
      @primitives.Rect::new(
        bounds.left() + local_box.bounds.left(),
        bounds.top() + local_box.bounds.top(),
        local_box.bounds.size().width(),
        local_box.bounds.size().height(),
      ) {
      Ok(value) => value
      Err(_) => return Err(GeometryFailure)
    }
    output.push({
      id: child.id(),
      bounds: absolute,
      overflow: local_box.overflow,
    })
    match child.children_style {
      Some(style) =>
        match
          layout_mixed_children(
            child.id(),
            absolute,
            style,
            nodes,
            output,
            overflow,
            depth + 1,
          ) {
          Err(error) => return Err(error)
          Ok(_) => ()
        }
      None =>
        for descendant in nodes {
          if descendant.parent == child.id() {
            return Err(MissingContainer)
          }
        }
    }
  }
  Ok(())
}

///|
fn measure_mixed_child(
  node : MixedTreeNode,
  axis : MeasureAxis,
  nodes : Array[MixedTreeNode],
  depth : Int32,
) -> Result[Double, TreeLayoutError] {
  if depth > MAX_FLEX_TREE_DEPTH {
    return Err(TreeTooDeep)
  }
  match node.children_style {
    Some(GridStyle(_)) => Err(UnsupportedIntrinsicGrid)
    Some(FlexStyle(style)) =>
      measure_mixed_container(node.id(), style, axis, nodes, depth)
    None =>
      match node.item {
        FlexChild(item) =>
          Ok(
            match axis {
              WidthAxis => item.intrinsic.width()
              HeightAxis => item.intrinsic.height()
            },
          )
        GridChild(_) => Err(UnsupportedIntrinsicGrid)
      }
  }
}

///|
fn measure_mixed_container(
  parent : UInt64,
  style : FlexTreeStyle,
  axis : MeasureAxis,
  nodes : Array[MixedTreeNode],
  depth : Int32,
) -> Result[Double, TreeLayoutError] {
  if depth > MAX_FLEX_TREE_DEPTH {
    return Err(TreeTooDeep)
  }
  let main_axis = match (style.direction, axis) {
    (Row, WidthAxis)
    | (RowReverse, WidthAxis)
    | (Column, HeightAxis)
    | (ColumnReverse, HeightAxis) => true
    _ => false
  }
  let mut count = 0
  let mut total = 0.0
  let mut maximum = 0.0
  for node in nodes {
    if node.parent == parent {
      count += 1
      let item = match node.item {
        FlexChild(item) => item
        _ => return Err(MismatchedItem)
      }
      let (dimension, minimum, limit) = if main_axis {
        (item.main, item.min_main, item.max_main)
      } else {
        (item.cross, item.min_cross, item.max_cross)
      }
      if !valid_limits(minimum, limit) {
        return Err(Flex(InvalidMinMax))
      }
      let value = match resolve_dimension(dimension, None) {
        Err(error) => return Err(Flex(error))
        Ok(Some(value)) => value
        Ok(None) =>
          match measure_mixed_child(node, axis, nodes, depth + 1) {
            Ok(value) => value
            Err(error) => return Err(error)
          }
      }
      let value = clamp_once(value, minimum, limit)
      if main_axis {
        total += value
      } else if value > maximum {
        maximum = value
      }
      if !finite(total) || !finite(value) {
        return Err(Flex(NonFiniteValue))
      }
    }
  }
  let insets = match axis {
    WidthAxis =>
      style.padding.left +
      style.padding.right +
      style.border.left +
      style.border.right
    HeightAxis =>
      style.padding.top +
      style.padding.bottom +
      style.border.top +
      style.border.bottom
  }
  let gaps = if main_axis && count > 1 {
    (count - 1).to_double() *
    (if style.direction.is_row() { style.gap_x } else { style.gap_y })
  } else {
    0.0
  }
  let value = (if main_axis { total + gaps } else { maximum }) + insets
  if !finite(value) {
    Err(Flex(NonFiniteValue))
  } else {
    Ok(value)
  }
}
