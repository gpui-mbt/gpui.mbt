///|
/// Explicit zero-minimum equal-fraction tracks. This bounded subset has no
/// implicit tracks, intrinsic track sizing, dense flow, margins or alignment.
pub const MAX_GRID_CELLS : Int32 = 4096

///|
pub(all) enum GridLayoutError {
  InvalidTrackCount
  CellLimitExceeded
  InvalidSpan
  PlacementExhausted
  DuplicateId
  Numeric(LayoutError)
} derive(Eq)

///|
pub extend GridLayoutError with Eq::{equal, not_equal}

///|
pub struct GridTreeStyle {
  columns : Int32
  rows : Int32
  gap_x : Double
  gap_y : Double
  padding : Insets
  border : Insets
}

///|
pub fn GridTreeStyle::new(
  columns : Int32,
  rows : Int32,
) -> Result[GridTreeStyle, GridLayoutError] {
  if columns <= 0 || rows <= 0 {
    Err(InvalidTrackCount)
  } else if columns > MAX_GRID_CELLS || rows > MAX_GRID_CELLS / columns {
    Err(CellLimitExceeded)
  } else {
    Ok({
      columns,
      rows,
      gap_x: 0.0,
      gap_y: 0.0,
      padding: Insets::zero(),
      border: Insets::zero(),
    })
  }
}

///|
pub fn GridTreeStyle::with_gap(
  self : GridTreeStyle,
  gap : Double,
) -> Result[GridTreeStyle, GridLayoutError] {
  self.with_gaps(gap, gap)
}

///|
pub fn GridTreeStyle::with_gap_x(
  self : GridTreeStyle,
  gap : Double,
) -> Result[GridTreeStyle, GridLayoutError] {
  self.with_gaps(gap, self.gap_y)
}

///|
pub fn GridTreeStyle::with_gap_y(
  self : GridTreeStyle,
  gap : Double,
) -> Result[GridTreeStyle, GridLayoutError] {
  self.with_gaps(self.gap_x, gap)
}

///|
fn GridTreeStyle::with_gaps(
  self : GridTreeStyle,
  gap_x : Double,
  gap_y : Double,
) -> Result[GridTreeStyle, GridLayoutError] {
  if !finite(gap_x) || !finite(gap_y) {
    Err(Numeric(NonFiniteValue))
  } else if gap_x < 0.0 || gap_y < 0.0 {
    Err(Numeric(NegativeValue))
  } else {
    Ok({ ..self, gap_x, gap_y, })
  }
}

///|
pub fn GridTreeStyle::with_insets(
  self : GridTreeStyle,
  padding : Insets,
  border : Insets,
) -> GridTreeStyle {
  { ..self, padding, border, }
}

///|
pub(all) enum GridColumnPlacement {
  AutoColumns(Int32)
  FullColumns
} derive(Eq)

///|
pub extend GridColumnPlacement with Eq::{equal, not_equal}

///|
/// Width and height are physical axes, unrelated to FlexItem.main/cross.
pub struct GridItem {
  id : UInt64
  width : Dimension
  height : Dimension
  columns : GridColumnPlacement
  row_span : Int32
}

///|
pub fn GridItem::new(
  id : UInt64,
  width : Dimension,
  height : Dimension,
) -> GridItem {
  { id, width, height, columns: AutoColumns(1), row_span: 1, }
}

///|
pub fn GridItem::id(self : GridItem) -> UInt64 {
  self.id
}

///|
pub fn GridItem::with_span(
  self : GridItem,
  columns : Int32,
  rows : Int32,
) -> Result[GridItem, GridLayoutError] {
  if columns <= 0 ||
    rows <= 0 ||
    columns > MAX_GRID_CELLS ||
    rows > MAX_GRID_CELLS {
    Err(InvalidSpan)
  } else {
    Ok({ ..self, columns: AutoColumns(columns), row_span: rows, })
  }
}

///|
/// Definite grid lines 1..-1, rather than an automatic span of column count.
pub fn GridItem::full_columns(self : GridItem) -> GridItem {
  { ..self, columns: FullColumns, }
}

///|
pub struct GridContainer {
  size : @primitives.Size
  style : GridTreeStyle
}

///|
pub fn GridContainer::new(
  size : @primitives.Size,
  style : GridTreeStyle,
) -> GridContainer {
  { size, style, }
}

///|
pub struct GridLayout {
  content_bounds : @primitives.Rect
  items : Array[LayoutBox]
  overflow : Bool
}

///|
pub fn GridLayout::content_bounds(self : GridLayout) -> @primitives.Rect {
  self.content_bounds
}

///|
pub fn GridLayout::items(self : GridLayout) -> Array[LayoutBox] {
  self.items.copy()
}

///|
pub fn GridLayout::overflow(self : GridLayout) -> Bool {
  self.overflow
}

///|
pub fn layout_grid(
  container : GridContainer,
  items : Array[GridItem],
) -> Result[GridLayout, GridLayoutError] {
  let style = container.style
  // Validate counts before multiplying or allocating the occupancy bitmap.
  match GridTreeStyle::new(style.columns, style.rows) {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  let horizontal = style.padding.left +
    style.padding.right +
    style.border.left +
    style.border.right
  let vertical = style.padding.top +
    style.padding.bottom +
    style.border.top +
    style.border.bottom
  let gap_width = style.gap_x * (style.columns - 1).to_double()
  let gap_height = style.gap_y * (style.rows - 1).to_double()
  if !finite(horizontal) ||
    !finite(vertical) ||
    !finite(gap_width) ||
    !finite(gap_height) {
    return Err(Numeric(NonFiniteValue))
  }
  let width = non_negative(container.size.width() - horizontal)
  let height = non_negative(container.size.height() - vertical)
  let x = style.padding.left + style.border.left
  let y = style.padding.top + style.border.top
  let track_width = non_negative(width - gap_width) / style.columns.to_double()
  let track_height = non_negative(height - gap_height) / style.rows.to_double()
  let content_bounds = match @primitives.Rect::new(x, y, width, height) {
    Ok(bounds) => bounds
    Err(_) => return Err(Numeric(GeometryFailure))
  }
  let occupied = Array::make(style.columns * style.rows, false)
  let output : Array[LayoutBox] = []
  let mut cursor_row = 0
  let mut cursor_column = 0
  let mut overflow = horizontal > container.size.width() ||
    vertical > container.size.height() ||
    gap_width > width ||
    gap_height > height
  for item in items {
    for previous in output {
      if previous.id == item.id {
        return Err(DuplicateId)
      }
    }
    let span = match item.columns {
      AutoColumns(span) => span
      FullColumns => style.columns
    }
    if span <= 0 ||
      span > style.columns ||
      item.row_span <= 0 ||
      item.row_span > style.rows {
      return Err(InvalidSpan)
    }
    if item.columns is FullColumns {
      if cursor_column > 0 {
        cursor_row += 1
      }
      cursor_column = 0
    }
    let mut found = false
    while cursor_row <= style.rows - item.row_span && !found {
      if cursor_column > style.columns - span {
        cursor_row += 1
        cursor_column = 0
      } else {
        let mut free = true
        for row = cursor_row; row < cursor_row + item.row_span; row = row + 1 {
          for column = cursor_column
              column < cursor_column + span
              column = column + 1 {
            if occupied[row * style.columns + column] {
              free = false
            }
          }
        }
        if free {
          found = true
        } else if item.columns is FullColumns {
          cursor_row += 1
        } else {
          cursor_column += 1
        }
      }
    }
    if !found {
      return Err(PlacementExhausted)
    }
    for row = cursor_row; row < cursor_row + item.row_span; row = row + 1 {
      for column = cursor_column
          column < cursor_column + span
          column = column + 1 {
        occupied[row * style.columns + column] = true
      }
    }
    let area_width = track_width * span.to_double() +
      style.gap_x * (span - 1).to_double()
    let area_height = track_height * item.row_span.to_double() +
      style.gap_y * (item.row_span - 1).to_double()
    let item_width = match resolve_dimension(item.width, Some(area_width)) {
      Ok(Some(value)) => value
      Ok(None) => area_width
      Err(error) => return Err(Numeric(error))
    }
    let item_height = match resolve_dimension(item.height, Some(area_height)) {
      Ok(Some(value)) => value
      Ok(None) => area_height
      Err(error) => return Err(Numeric(error))
    }
    let bounds = match
      @primitives.Rect::new(
        x +
        cursor_column.to_double() * track_width +
        cursor_column.to_double() * style.gap_x,
        y +
        cursor_row.to_double() * track_height +
        cursor_row.to_double() * style.gap_y,
        item_width,
        item_height,
      ) {
      Ok(bounds) => bounds
      Err(_) => return Err(Numeric(GeometryFailure))
    }
    let item_overflow = exceeds_with_tolerance(item_width, area_width) ||
      exceeds_with_tolerance(item_height, area_height) ||
      exceeds_with_tolerance(bounds.right(), content_bounds.right()) ||
      exceeds_with_tolerance(bounds.bottom(), content_bounds.bottom())
    overflow = overflow || item_overflow
    output.push({ id: item.id, bounds, overflow: item_overflow, })
    // Sparse auto-placement resumes here; it must never backfill earlier holes.
    cursor_column += span
  }
  Ok({ content_bounds, items: output, overflow, })
}
