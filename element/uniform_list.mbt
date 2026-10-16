///|
/// Checked failures of the bounded vertical uniform-list surface.
pub(all) enum UniformListError {
  InvalidCount
  InvalidIdSpace
  ReservedIdCollision(UInt64)
  InvalidRangeIndex(Int32)
  InvalidLocalSlot(UInt64)
  FactoryFailure(String)
  InvalidFactoryLength(Int32, Int32)
  InvalidRowRoot(Int32, UInt64)
  RowIdOutsideNamespace(Int32, UInt64)
  UnsupportedListShape
  UnsupportedRowShape(Int32)
  NonFiniteOffset
  InvalidMeasuredHeight
  GeometryOverflow
  NonUniformVisibleRow(Int32)
} derive(Eq)

///|
pub extend UniformListError with Eq::{not_equal, equal}

///|
/// One checked, contiguous namespace per stable row. Slot zero is its root.
pub struct UniformListIdSpace {
  priv first : UInt64
  priv stride : UInt64
}

///|
pub fn UniformListIdSpace::new(
  first_id : UInt64,
  slots_per_row : UInt64,
) -> Result[UniformListIdSpace, UniformListError] {
  if slots_per_row == 0 {
    Err(InvalidIdSpace)
  } else {
    Ok({ first: first_id, stride: slots_per_row, })
  }
}

///|
/// Core-created half-open factory range. IDs depend on index, never a live slot.
pub struct UniformListRange {
  priv first : Int32
  priv limit : Int32
  priv ids : UniformListIdSpace
}

///|
pub fn UniformListRange::start(self : UniformListRange) -> Int32 {
  self.first
}

///|
pub fn UniformListRange::end(self : UniformListRange) -> Int32 {
  self.limit
}

///|
pub fn UniformListRange::id(
  self : UniformListRange,
  index : Int32,
  local_slot : UInt64,
) -> Result[UInt64, UniformListError] {
  if index < self.first || index >= self.limit {
    Err(InvalidRangeIndex(index))
  } else if local_slot >= self.ids.stride {
    Err(InvalidLocalSlot(local_slot))
  } else {
    // The entire namespace was checked before a range could be constructed.
    Ok(self.ids.first + index.to_uint64() * self.ids.stride + local_slot)
  }
}

///|
/// Vertical top-to-bottom rows in a fixed/full-size viewport. Factories must
/// return auto-sized row roots in ascending order, with bounded ordinary
/// descendants, and stable content within one lifecycle. Two prototype calls
/// measure real recursive layout; only the visible range enters the live tree.
/// Errors preserve earlier trees and caller state, but cannot undo side effects
/// in user factories. Nested scroll/list rows and percentage row sizing are
/// deliberately unsupported. Retain scroll_wheel's returned Y in caller state.
pub struct UniformList {
  priv item : @layout.FlexItem
  priv count : Int32
  priv ids : UniformListIdSpace
  priv last_id : UInt64?
  priv render_items : (UniformListRange) -> Result[
    Array[Element],
    UniformListError,
  ]
  priv requested : Double
}

///|
pub fn UniformList::new(
  item : @layout.FlexItem,
  item_count : Int32,
  ids : UniformListIdSpace,
  render_items : (UniformListRange) -> Result[Array[Element], UniformListError],
) -> Result[UniformList, UniformListError] {
  if item_count < 0 {
    return Err(InvalidCount)
  }
  // Auto/indefinite viewport inference is outside this first surface.
  if item.main == @layout.Dimension::auto() ||
    item.cross == @layout.Dimension::auto() {
    return Err(UnsupportedListShape)
  }
  let max_id : UInt64 = 0xffff_ffff_ffff_ffff
  let last_id = if item_count == 0 {
    None
  } else {
    let count = item_count.to_uint64()
    if count > max_id / ids.stride {
      return Err(InvalidIdSpace)
    }
    let span_minus_one = count * ids.stride - 1
    if span_minus_one > max_id - ids.first {
      return Err(InvalidIdSpace)
    }
    let last = ids.first + span_minus_one
    if item.id() >= ids.first && item.id() <= last {
      return Err(ReservedIdCollision(item.id()))
    }
    Some(last)
  }
  Ok({ item, count: item_count, ids, last_id, render_items, requested: 0.0, })
}

///|
pub fn UniformList::with_scroll_offset(
  self : UniformList,
  offset_y : Double,
) -> Result[UniformList, UniformListError] {
  if !scroll_finite(offset_y) {
    Err(NonFiniteOffset)
  } else {
    Ok({ ..self, requested: offset_y, })
  }
}

///|
pub impl IntoElement for UniformList with fn into_element(self) -> Element {
  { ..Element::new(self.item), uniform_list: Some(self), }
}

///|
pub extend UniformList with IntoElement::{into_element}

///|
/// Immutable resolved observation, including the full virtual extent.
pub struct UniformListLayout {
  priv spec : UniformList
  priv viewport_bounds : @primitives.Rect
  priv measured : @primitives.Size?
  priv content : @primitives.Size
  priv range : UniformListRange
  priv position : Double
  priv maximum : Double
}

///|
pub fn ElementTree::uniform_list(
  self : ElementTree,
  id : UInt64,
) -> UniformListLayout? {
  match self.node(id) {
    None => None
    Some(node) => node.uniform_list
  }
}

///|
pub fn UniformListLayout::id(self : UniformListLayout) -> UInt64 {
  self.spec.item.id()
}

///|
pub fn UniformListLayout::item_count(self : UniformListLayout) -> Int32 {
  self.spec.count
}

///|
pub fn UniformListLayout::measured_item_size(
  self : UniformListLayout,
) -> @primitives.Size? {
  self.measured
}

///|
pub fn UniformListLayout::content_size(
  self : UniformListLayout,
) -> @primitives.Size {
  self.content
}

///|
pub fn UniformListLayout::bounds(self : UniformListLayout) -> @primitives.Rect {
  self.viewport_bounds
}

///|
pub fn UniformListLayout::visible_range(
  self : UniformListLayout,
) -> UniformListRange {
  self.range
}

///|
pub fn UniformListLayout::offset(self : UniformListLayout) -> Double {
  self.position
}

///|
pub fn UniformListLayout::max_offset(self : UniformListLayout) -> Double {
  self.maximum
}

///|
fn uniform_contains(list : UniformList, id : UInt64) -> Bool {
  match list.last_id {
    None => false
    Some(last) => id >= list.ids.first && id <= last
  }
}

///|
fn validate_uniform_lists(
  placements : Array[ElementPlacement],
) -> Result[Unit, ElementError] {
  let mut has_uniform_list = false
  for placement in placements {
    if placement.element.uniform_list is Some(_) {
      has_uniform_list = true
    }
  }
  // Keep the existing ordinary-tree validation errors and cost unchanged.
  if !has_uniform_list {
    return Ok(())
  }
  let lists : Array[UniformList] = []
  for i = 0; i < placements.length(); i = i + 1 {
    let element = placements[i].element
    for j = 0; j < i; j = j + 1 {
      if placements[j].element.id == element.id {
        return Err(DuplicateId)
      }
    }
    match element.uniform_list {
      None => ()
      Some(list) => {
        if element.is_root ||
          element.children.length() != 0 ||
          element.children_style is Some(_) ||
          element.scroll_offset is Some(_) {
          return Err(UniformListFailure(UnsupportedListShape))
        }
        for other in lists {
          if uniform_contains(other, list.ids.first) ||
            uniform_contains(list, other.ids.first) {
            if list.last_id is Some(_) && other.last_id is Some(_) {
              return Err(
                UniformListFailure(ReservedIdCollision(list.ids.first)),
              )
            }
          }
        }
        lists.push(list)
      }
    }
  }
  for placement in placements {
    for list in lists {
      if uniform_contains(list, placement.element.id) {
        return Err(
          UniformListFailure(ReservedIdCollision(placement.element.id)),
        )
      }
    }
  }
  Ok(())
}

///|
fn uniform_factory(
  list : UniformList,
  range : UniformListRange,
) -> Result[Array[Element], ElementError] {
  // Guard the namespace before invoking user code, including future callers.
  if range.first < 0 || range.first > list.count {
    return Err(UniformListFailure(InvalidRangeIndex(range.first)))
  }
  if range.limit < range.first || range.limit > list.count {
    return Err(UniformListFailure(InvalidRangeIndex(range.limit)))
  }
  let rows = match (list.render_items)(range) {
    Ok(rows) => copy_elements(rows)
    Err(error) => return Err(UniformListFailure(error))
  }
  if rows.length() != range.limit - range.first {
    return Err(
      UniformListFailure(
        InvalidFactoryLength(range.limit - range.first, rows.length()),
      ),
    )
  }
  for slot = 0; slot < rows.length(); slot = slot + 1 {
    let index = range.first + slot
    let first = list.ids.first + index.to_uint64() * list.ids.stride
    let last = first + (list.ids.stride - 1)
    let row = rows[slot]
    if row.id != first {
      return Err(UniformListFailure(InvalidRowRoot(index, row.id)))
    }
    let pending : Array[(Element, Int32)] = [(row, 1)]
    let seen : Array[UInt64] = []
    while pending.length() > 0 {
      let (element, depth) = pending.pop().unwrap()
      if depth > MAX_ELEMENT_DEPTH {
        return Err(TreeTooDeep)
      }
      if element.id < first || element.id > last {
        return Err(UniformListFailure(RowIdOutsideNamespace(index, element.id)))
      }
      for id in seen {
        if id == element.id {
          return Err(DuplicateId)
        }
      }
      seen.push(element.id)
      if element.is_root ||
        element.uniform_list is Some(_) ||
        element.scroll_offset is Some(_) {
        return Err(UniformListFailure(UnsupportedRowShape(index)))
      }
      let item = match element.item {
        None => return Err(MissingLayoutItem)
        Some(item) => item
      }
      if item.main is @layout.Percent(_) || item.cross is @layout.Percent(_) {
        return Err(UniformListFailure(UnsupportedRowShape(index)))
      }
      if depth == 1 &&
        (
          item.main != @layout.Dimension::auto() ||
          item.cross != @layout.Dimension::auto() ||
          item.grow != 0.0 ||
          item.min_main != 0.0 ||
          item.max_main is Some(_) ||
          item.min_cross != 0.0 ||
          item.max_cross is Some(_)
        ) {
        return Err(UniformListFailure(UnsupportedRowShape(index)))
      }
      for child in element.children {
        pending.push((child, depth + 1))
      }
    }
  }
  Ok(rows)
}

///|
// A temporary ordinary parent exercises genuine recursive intrinsic/layout
// measurement. It is never part of the published live tree or identity space.
fn uniform_row_layout(
  list : UniformList,
  row : Element,
  available : @primitives.Size,
  fit_width : Bool,
  scale_factor : Double?,
) -> Result[RequestedLayout, ElementError] {
  let item = row.item.unwrap()
  let item = match item.with_flex(0.0, 0.0) {
    Ok(item) => item
    Err(_) => return Err(UniformListFailure(GeometryOverflow))
  }
  let row = { ..row, item: Some(item), }
  let style = @layout.FlexTreeStyle::new(@layout.FlowDirection::column()).with_align(
    if fit_width {
      @layout.AlignItems::stretch()
    } else {
      @layout.AlignItems::start()
    },
  )
  let wrapper = Element::root(list.item.id(), style).with_child(row)
  wrapper.request_layout_internal(available, scale_factor)
}

///|
fn measure_uniform_prototype(
  list : UniformList,
  scale_factor : Double?,
) -> Result[@primitives.Size?, ElementError] {
  if list.count == 0 {
    return Ok(None)
  }
  let rows = match
    uniform_factory(list, { first: 0, limit: 1, ids: list.ids, }) {
    Ok(rows) => rows
    Err(error) => return Err(error)
  }
  let zero = @primitives.Size::new(0.0, 0.0).unwrap()
  let layout = match
    uniform_row_layout(list, rows[0], zero, false, scale_factor) {
    Ok(layout) => layout
    Err(error) => return Err(error)
  }
  let size = layout.layout.items()[0].bounds().size()
  if !scroll_finite(size.height()) || size.height() <= 0.0 {
    Err(UniformListFailure(InvalidMeasuredHeight))
  } else {
    Ok(Some(size))
  }
}

///|
// Clamp in floating point before conversion: ceil can round the final endpoint
// one past count, including past Int::max_value, at fractional boundaries.
fn uniform_bounded_index(value : Double, count : Int32) -> Int32 {
  if value <= 0.0 {
    0
  } else if value >= count.to_double() {
    count
  } else {
    value.to_int()
  }
}

///|
fn resolve_uniform_list(
  list : UniformList,
  bounds : @primitives.Rect,
  scale_factor : Double?,
) -> Result[UniformListLayout, ElementError] {
  let measured = match measure_uniform_prototype(list, scale_factor) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let height = match measured {
    None => 0.0
    Some(size) => size.height()
  }
  let content_height = height * list.count.to_double()
  if !scroll_finite(content_height) {
    return Err(UniformListFailure(GeometryOverflow))
  }
  let content = match
    @primitives.Size::new(bounds.size().width(), content_height) {
    Ok(value) => value
    Err(_) => return Err(UniformListFailure(GeometryOverflow))
  }
  let maximum = rounded_scroll_limit(content_height - bounds.size().height())
  // Guard rounding overflow, including the final addition in the rounding path.
  if !scroll_finite(maximum) {
    return Err(UniformListFailure(GeometryOverflow))
  }
  let position = scroll_clamp(list.requested, maximum)
  let first = if height == 0.0 || position >= content_height {
    list.count
  } else {
    uniform_bounded_index((position / height).floor(), list.count)
  }
  let limit = if height == 0.0 ||
    bounds.size().height() >= content_height - position {
    list.count
  } else {
    uniform_bounded_index(
      ((position + bounds.size().height()) / height).ceil(),
      list.count,
    )
  }
  Ok({
    spec: list,
    viewport_bounds: bounds,
    measured,
    content,
    range: { first, limit, ids: list.ids, },
    position,
    maximum,
  })
}

///|
fn expand_uniform_rows(
  nodes : Array[ElementNode],
  scale_factor : Double?,
) -> Result[Array[ElementNode], ElementError] {
  let expanded : Array[ElementNode] = []
  let ancestors : Array[UInt64] = []
  for node in nodes {
    while ancestors.length() > 0 &&
          Some(ancestors[ancestors.length() - 1]) != node.parent {
      let _ = ancestors.pop()
    }
    let list_depth = ancestors.length()
    ancestors.push(node.id)
    expanded.push(node)
    match node.uniform_list {
      None => ()
      Some(list) if list.spec.count == 0 => ()
      Some(list) => {
        let rows = match uniform_factory(list.spec, list.range) {
          Ok(rows) => rows
          Err(error) => return Err(error)
        }
        let height = list.measured.unwrap().height()
        let available = @primitives.Size::new(
          list.viewport_bounds.size().width(),
          height,
        ).unwrap()
        for slot = 0; slot < rows.length(); slot = slot + 1 {
          let index = list.range.first + slot
          let requested = match
            uniform_row_layout(
              list.spec,
              rows[slot],
              available,
              true,
              scale_factor,
            ) {
            Ok(value) => value
            Err(error) => return Err(error)
          }
          let boxes = requested.layout.items()
          if boxes[0].bounds().size().height() != height {
            return Err(UniformListFailure(NonUniformVisibleRow(index)))
          }
          let local_y = index.to_double() * height - list.position
          let translation = match
            @primitives.Point::new(
              list.viewport_bounds.left(),
              list.viewport_bounds.top() + local_y,
            ) {
            Ok(value) => value
            Err(_) => return Err(UniformListFailure(GeometryOverflow))
          }
          // Ordinary ancestor scroll was already applied to the placeholder.
          // The virtual offset is applied here exactly once, after local layout.
          for j = 1; j < requested.placements.length(); j = j + 1 {
            let placement = requested.placements[j]
            let element = placement.element
            if list_depth + placement.depth > MAX_ELEMENT_DEPTH {
              return Err(TreeTooDeep)
            }
            let bounds = match boxes[j - 1].bounds().translated(translation) {
              Ok(value) => value
              Err(_) => return Err(UniformListFailure(GeometryOverflow))
            }
            expanded.push(
              ElementNode::new(element.id, placement.parent, bounds)
              .with_background(element.background)
              .with_focusable(element.focusable)
              .with_tab_index(element.tab_index)
              .with_tab_group_index(element.tab_group_index)
              .with_tab_stop(element.tab_stop)
              .with_pointer_events(element.pointer_events),
            )
          }
        }
      }
    }
  }
  Ok(expanded)
}
