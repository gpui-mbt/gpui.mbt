///|
/// Errors produced by the platform-neutral M2 flex-line layout foundation.
pub enum LayoutError {
  NonFiniteValue
  NegativeValue
  InvalidMinMax
  IndefinitePercentage
  DuplicateId
  GeometryFailure
} derive(Eq)

///|
pub extend LayoutError with Eq::{not_equal, equal}

///|
/// Main-axis flow for a one-dimensional flex container.
pub enum FlowDirection {
  Row
  Column
} derive(Eq)

///|
pub extend FlowDirection with Eq::{not_equal, equal}

///|
pub fn FlowDirection::row() -> FlowDirection {
  Row
}

///|
pub fn FlowDirection::column() -> FlowDirection {
  Column
}

///|
/// Whether flex items stay on one line or form additional cross-axis lines.
/// Recursive intrinsic measurement currently retains its existing no-wrap
/// approximation for auto-sized containers.
pub enum FlexWrap {
  NoWrap
  Wrap
  WrapReverse
} derive(Eq)

///|
pub extend FlexWrap with Eq::{not_equal, equal}

///|
pub fn FlexWrap::no_wrap() -> FlexWrap {
  NoWrap
}

///|
pub fn FlexWrap::wrap() -> FlexWrap {
  Wrap
}

///|
pub fn FlexWrap::wrap_reverse() -> FlexWrap {
  WrapReverse
}

///|
/// Main-axis placement of remaining space, including negative overflow space.
pub enum JustifyContent {
  Start
  Center
  End
  SpaceBetween
  SpaceAround
  SpaceEvenly
} derive(Eq)

///|
pub extend JustifyContent with Eq::{not_equal, equal}

///|
pub fn JustifyContent::start() -> JustifyContent {
  Start
}

///|
pub fn JustifyContent::center() -> JustifyContent {
  Center
}

///|
pub fn JustifyContent::end() -> JustifyContent {
  End
}

///|
pub fn JustifyContent::space_between() -> JustifyContent {
  SpaceBetween
}

///|
/// Distribute positive free space with half-sized outer spaces. An overflowing
/// line falls back to start; a fitting singleton is centered.
pub fn JustifyContent::space_around() -> JustifyContent {
  SpaceAround
}

///|
/// Distribute positive free space equally before, between, and after items.
/// An overflowing line falls back to start; a fitting singleton is centered.
pub fn JustifyContent::space_evenly() -> JustifyContent {
  SpaceEvenly
}

///|
/// Cross-axis placement for all items in this first bounded subset.
pub enum AlignItems {
  Start
  Center
  End
  Stretch
} derive(Eq)

///|
pub extend AlignItems with Eq::{not_equal, equal}

///|
pub fn AlignItems::start() -> AlignItems {
  Start
}

///|
pub fn AlignItems::center() -> AlignItems {
  Center
}

///|
pub fn AlignItems::end() -> AlignItems {
  End
}

///|
pub fn AlignItems::stretch() -> AlignItems {
  Stretch
}

///|
/// Cross-axis placement of wrapped lines. Start and End are flex-relative,
/// including under wrap-reverse; Center and End retain signed overflow space.
/// Stretch is the default. Distributed modes preserve natural line sizes;
/// they and Stretch use safe physical-start placement on overflow.
pub enum AlignContent {
  Start
  Center
  End
  Stretch
  SpaceBetween
  SpaceAround
  SpaceEvenly
} derive(Eq)

///|
pub extend AlignContent with Eq::{not_equal, equal}

///|
pub fn AlignContent::start() -> AlignContent {
  Start
}

///|
pub fn AlignContent::center() -> AlignContent {
  Center
}

///|
pub fn AlignContent::end() -> AlignContent {
  End
}

///|
pub fn AlignContent::stretch() -> AlignContent {
  Stretch
}

///|
/// Distribute positive free cross space between wrapped lines. A fitting
/// singleton stays at flex-start; overflow falls back to physical start.
pub fn AlignContent::space_between() -> AlignContent {
  SpaceBetween
}

///|
/// Distribute positive free cross space with half-sized outer spaces.
/// A fitting singleton is centered; overflow falls back to physical start.
pub fn AlignContent::space_around() -> AlignContent {
  SpaceAround
}

///|
/// Distribute positive free cross space equally before, between, and after
/// wrapped lines. A fitting singleton is centered; overflow uses physical start.
pub fn AlignContent::space_evenly() -> AlignContent {
  SpaceEvenly
}

///|
/// A logical dimension. Percent values use 1.0 == 100%.
pub enum Dimension {
  Auto
  Points(Double)
  Percent(Double)
} derive(Eq)

///|
pub extend Dimension with Eq::{not_equal, equal}

///|
pub fn Dimension::auto() -> Dimension {
  Auto
}

///|
pub fn Dimension::points(value : Double) -> Result[Dimension, LayoutError] {
  if !finite(value) {
    Err(NonFiniteValue)
  } else if value < 0.0 {
    Err(NegativeValue)
  } else {
    Ok(Points(value))
  }
}

///|
pub fn Dimension::percent(value : Double) -> Result[Dimension, LayoutError] {
  if !finite(value) {
    Err(NonFiniteValue)
  } else if value < 0.0 {
    Err(NegativeValue)
  } else {
    Ok(Percent(value))
  }
}

///|
/// Resolve a logical dimension. Auto remains unresolved; percentages require
/// a definite containing extent.
pub fn resolve_dimension(
  dimension : Dimension,
  containing : Double?,
) -> Result[Double?, LayoutError] {
  match dimension {
    Auto => Ok(None)
    Points(value) =>
      if !finite(value) {
        Err(NonFiniteValue)
      } else if value < 0.0 {
        Err(NegativeValue)
      } else {
        Ok(Some(value))
      }
    Percent(ratio) =>
      if !finite(ratio) {
        Err(NonFiniteValue)
      } else if ratio < 0.0 {
        Err(NegativeValue)
      } else {
        match containing {
          None => Err(IndefinitePercentage)
          Some(base) =>
            if !finite(base) {
              Err(NonFiniteValue)
            } else if base < 0.0 {
              Err(NegativeValue)
            } else {
              let value = base * ratio
              if finite(value) {
                Ok(Some(value))
              } else {
                Err(NonFiniteValue)
              }
            }
        }
      }
  }
}

///|
/// Logical padding/border insets.
pub struct Insets {
  top : Double
  right : Double
  bottom : Double
  left : Double
} derive(Eq)

///|
pub extend Insets with Eq::{not_equal, equal}

///|
pub fn Insets::zero() -> Insets {
  { top: 0.0, right: 0.0, bottom: 0.0, left: 0.0, }
}

///|
pub fn Insets::all(value : Double) -> Result[Insets, LayoutError] {
  Insets::new(value, value, value, value)
}

///|
pub fn Insets::new(
  top : Double,
  right : Double,
  bottom : Double,
  left : Double,
) -> Result[Insets, LayoutError] {
  if !finite(top) || !finite(right) || !finite(bottom) || !finite(left) {
    Err(NonFiniteValue)
  } else if top < 0.0 || right < 0.0 || bottom < 0.0 || left < 0.0 {
    Err(NegativeValue)
  } else {
    Ok({ top, right, bottom, left, })
  }
}

///|
pub fn Insets::top(self : Insets) -> Double {
  self.top
}

///|
pub fn Insets::right(self : Insets) -> Double {
  self.right
}

///|
pub fn Insets::bottom(self : Insets) -> Double {
  self.bottom
}

///|
pub fn Insets::left(self : Insets) -> Double {
  self.left
}

///|
/// One child participating in a flex line. Auto main/cross dimensions use the
/// intrinsic size unless container alignment stretches an auto cross dimension.
pub struct FlexItem {
  id : UInt64
  main : Dimension
  cross : Dimension
  intrinsic : @primitives.Size
  grow : Double
  shrink : Double
  min_main : Double
  max_main : Double?
  min_cross : Double
  max_cross : Double?
}

///|
pub fn FlexItem::new(
  id : UInt64,
  main : Dimension,
  cross : Dimension,
  intrinsic : @primitives.Size,
) -> FlexItem {
  {
    id,
    main,
    cross,
    intrinsic,
    grow: 0.0,
    shrink: 1.0,
    min_main: 0.0,
    max_main: None,
    min_cross: 0.0,
    max_cross: None,
  }
}

///|
pub fn FlexItem::id(self : FlexItem) -> UInt64 {
  self.id
}

///|
/// Replace the intrinsic fallback used for auto dimensions while preserving
/// the item's flex factors and min/max constraints.
pub fn FlexItem::with_intrinsic(
  self : FlexItem,
  intrinsic : @primitives.Size,
) -> FlexItem {
  {
    id: self.id,
    main: self.main,
    cross: self.cross,
    intrinsic,
    grow: self.grow,
    shrink: self.shrink,
    min_main: self.min_main,
    max_main: self.max_main,
    min_cross: self.min_cross,
    max_cross: self.max_cross,
  }
}

///|
pub fn FlexItem::with_flex(
  self : FlexItem,
  grow : Double,
  shrink : Double,
) -> Result[FlexItem, LayoutError] {
  if !finite(grow) || !finite(shrink) {
    Err(NonFiniteValue)
  } else if grow < 0.0 || shrink < 0.0 {
    Err(NegativeValue)
  } else {
    Ok({
      id: self.id,
      main: self.main,
      cross: self.cross,
      intrinsic: self.intrinsic,
      grow,
      shrink,
      min_main: self.min_main,
      max_main: self.max_main,
      min_cross: self.min_cross,
      max_cross: self.max_cross,
    })
  }
}

///|
pub fn FlexItem::with_main_limits(
  self : FlexItem,
  min : Double,
  max : Double?,
) -> Result[FlexItem, LayoutError] {
  if !valid_limits(min, max) {
    Err(InvalidMinMax)
  } else {
    Ok({
      id: self.id,
      main: self.main,
      cross: self.cross,
      intrinsic: self.intrinsic,
      grow: self.grow,
      shrink: self.shrink,
      min_main: min,
      max_main: max,
      min_cross: self.min_cross,
      max_cross: self.max_cross,
    })
  }
}

///|
pub fn FlexItem::with_cross_limits(
  self : FlexItem,
  min : Double,
  max : Double?,
) -> Result[FlexItem, LayoutError] {
  if !valid_limits(min, max) {
    Err(InvalidMinMax)
  } else {
    Ok({
      id: self.id,
      main: self.main,
      cross: self.cross,
      intrinsic: self.intrinsic,
      grow: self.grow,
      shrink: self.shrink,
      min_main: self.min_main,
      max_main: self.max_main,
      min_cross: min,
      max_cross: max,
    })
  }
}

///|
/// A definite flex container. Percent child dimensions are resolved against
/// its definite inner dimensions; recursive auto containers are measured by the
/// flex-tree layer before this line engine is called.
pub struct FlexContainer {
  direction : FlowDirection
  wrap : FlexWrap
  size : @primitives.Size
  gap_x : Double
  gap_y : Double
  padding : Insets
  border : Insets
  justify : JustifyContent
  align : AlignItems
  align_content : AlignContent
}

///|
pub fn FlexContainer::new(
  direction : FlowDirection,
  size : @primitives.Size,
) -> FlexContainer {
  {
    direction,
    wrap: FlexWrap::no_wrap(),
    size,
    gap_x: 0.0,
    gap_y: 0.0,
    padding: Insets::zero(),
    border: Insets::zero(),
    justify: Start,
    align: AlignItems::Start,
    align_content: AlignContent::stretch(),
  }
}

///|
/// Set both physical gaps, replacing any earlier axis-specific settings.
pub fn FlexContainer::with_gap(
  self : FlexContainer,
  gap : Double,
) -> Result[FlexContainer, LayoutError] {
  self.with_gaps(gap, gap)
}

///|
/// Set the physical horizontal gap while preserving the vertical gap.
/// This is the item gap in rows and the line gap in wrapped columns.
pub fn FlexContainer::with_gap_x(
  self : FlexContainer,
  gap : Double,
) -> Result[FlexContainer, LayoutError] {
  self.with_gaps(gap, self.gap_y)
}

///|
/// Set the physical vertical gap while preserving the horizontal gap.
/// This is the item gap in columns and the line gap in wrapped rows.
pub fn FlexContainer::with_gap_y(
  self : FlexContainer,
  gap : Double,
) -> Result[FlexContainer, LayoutError] {
  self.with_gaps(self.gap_x, gap)
}

///|
fn FlexContainer::with_gaps(
  self : FlexContainer,
  gap_x : Double,
  gap_y : Double,
) -> Result[FlexContainer, LayoutError] {
  if !finite(gap_x) || !finite(gap_y) {
    Err(NonFiniteValue)
  } else if gap_x < 0.0 || gap_y < 0.0 {
    Err(NegativeValue)
  } else {
    Ok({
      direction: self.direction,
      wrap: self.wrap,
      size: self.size,
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
pub fn FlexContainer::with_insets(
  self : FlexContainer,
  padding : Insets,
  border : Insets,
) -> FlexContainer {
  {
    direction: self.direction,
    wrap: self.wrap,
    size: self.size,
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
pub fn FlexContainer::with_justify(
  self : FlexContainer,
  justify : JustifyContent,
) -> FlexContainer {
  {
    direction: self.direction,
    wrap: self.wrap,
    size: self.size,
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
pub fn FlexContainer::with_align(
  self : FlexContainer,
  align : AlignItems,
) -> FlexContainer {
  {
    direction: self.direction,
    wrap: self.wrap,
    size: self.size,
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
pub fn FlexContainer::with_wrap(
  self : FlexContainer,
  wrap : FlexWrap,
) -> FlexContainer {
  {
    direction: self.direction,
    wrap,
    size: self.size,
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
/// Align wrapped lines within the inner cross extent. NoWrap ignores this
/// setting and continues to use AlignItems for its single line.
pub fn FlexContainer::with_align_content(
  self : FlexContainer,
  align_content : AlignContent,
) -> FlexContainer {
  {
    direction: self.direction,
    wrap: self.wrap,
    size: self.size,
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
fn FlexContainer::main_gap(self : FlexContainer) -> Double {
  if self.direction is Row {
    self.gap_x
  } else {
    self.gap_y
  }
}

///|
fn FlexContainer::cross_gap(self : FlexContainer) -> Double {
  if self.direction is Row {
    self.gap_y
  } else {
    self.gap_x
  }
}

///|
pub struct LayoutBox {
  id : UInt64
  bounds : @primitives.Rect
  overflow : Bool
}

///|
pub fn LayoutBox::id(self : LayoutBox) -> UInt64 {
  self.id
}

///|
pub fn LayoutBox::bounds(self : LayoutBox) -> @primitives.Rect {
  self.bounds
}

///|
pub fn LayoutBox::overflow(self : LayoutBox) -> Bool {
  self.overflow
}

///|
/// Round an authored nonnegative length to the nearest device pixel, with
/// midpoint ties toward zero. The result remains in logical pixels.
fn snap_authored_length_to_device_grid(
  value : Double,
  scale_factor : Double,
) -> Result[Double, LayoutError] {
  if !finite(value) || !finite(scale_factor) {
    Err(NonFiniteValue)
  } else if value < 0.0 || scale_factor <= 0.0 {
    Err(NegativeValue)
  } else {
    let device_value = value * scale_factor
    if !finite(device_value) {
      Err(NonFiniteValue)
    } else {
      let result = round_half_toward_zero(device_value) / scale_factor
      if finite(result) {
        Ok(result)
      } else {
        Err(NonFiniteValue)
      }
    }
  }
}

///|
/// Round a nonnegative measured size upward to the next device pixel. The
/// result remains in logical pixels.
fn ceil_measured_length_to_device_grid(
  value : Double,
  scale_factor : Double,
) -> Result[Double, LayoutError] {
  if !finite(value) || !finite(scale_factor) {
    Err(NonFiniteValue)
  } else if value < 0.0 || scale_factor <= 0.0 {
    Err(NegativeValue)
  } else {
    let device_value = value * scale_factor
    if !finite(device_value) {
      Err(NonFiniteValue)
    } else {
      let result = device_value.ceil() / scale_factor
      if finite(result) {
        Ok(result)
      } else {
        Err(NonFiniteValue)
      }
    }
  }
}

///|
/// Snap an already-computed absolute rectangle by rounding its near and far
/// edges independently. This preserves the absolute-edge layout boundary used
/// by GPUI; callers should pass unrounded absolute origins, including for
/// nested nodes.
fn snap_absolute_rect_to_device_grid(
  bounds : @primitives.Rect,
  scale_factor : Double,
) -> Result[@primitives.Rect, LayoutError] {
  if !finite(scale_factor) {
    Err(NonFiniteValue)
  } else if scale_factor <= 0.0 {
    Err(NegativeValue)
  } else {
    let near_x = bounds.left()
    let near_y = bounds.top()
    let far_x = near_x + bounds.size().width()
    let far_y = near_y + bounds.size().height()
    let near_x_device = near_x * scale_factor
    let near_y_device = near_y * scale_factor
    let far_x_device = far_x * scale_factor
    let far_y_device = far_y * scale_factor
    if !finite(near_x) ||
      !finite(near_y) ||
      !finite(far_x) ||
      !finite(far_y) ||
      !finite(near_x_device) ||
      !finite(near_y_device) ||
      !finite(far_x_device) ||
      !finite(far_y_device) {
      Err(NonFiniteValue)
    } else {
      let left = round_half_toward_zero(near_x_device) / scale_factor
      let top = round_half_toward_zero(near_y_device) / scale_factor
      let right = round_half_toward_zero(far_x_device) / scale_factor
      let bottom = round_half_toward_zero(far_y_device) / scale_factor
      match @primitives.Rect::new(left, top, right - left, bottom - top) {
        Ok(value) => Ok(value)
        Err(_) => Err(GeometryFailure)
      }
    }
  }
}

///|
fn round_half_toward_zero(value : Double) -> Double {
  let magnitude = if value < 0.0 { -value } else { value }
  let rounded = (magnitude - 0.5).ceil()
  if value < 0.0 {
    -rounded
  } else {
    rounded
  }
}

///|
pub struct FlexLayout {
  content_bounds : @primitives.Rect
  items : Array[LayoutBox]
  overflow : Bool
}

///|
pub fn FlexLayout::content_bounds(self : FlexLayout) -> @primitives.Rect {
  self.content_bounds
}

///|
pub fn FlexLayout::items(self : FlexLayout) -> Array[LayoutBox] {
  self.items
}

///|
pub fn FlexLayout::overflow(self : FlexLayout) -> Bool {
  self.overflow
}

///|
priv struct PreparedItem {
  item : FlexItem
  basis : Double
  cross : Double
  weight : Double
}

///|
/// Lay out one deterministic row/column flex line. Positive free space is
/// distributed by grow factors. For totals below one, the signed budget is
/// free space times that total minus line gaps, matching pinned GPUI.
/// Negative initial free space is distributed by shrink*basis; shrink totals
/// below one limit that budget while retaining any resulting overflow.
/// Main-axis limits freeze constrained children and redistribute the remaining
/// budget, retaining partial-factor shares of the initial free space.
pub fn layout_flex(
  container : FlexContainer,
  items : Array[FlexItem],
) -> Result[FlexLayout, LayoutError] {
  if has_duplicate_ids(items) {
    Err(DuplicateId)
  } else {
    let horizontal = container.padding.left +
      container.padding.right +
      container.border.left +
      container.border.right
    let vertical = container.padding.top +
      container.padding.bottom +
      container.border.top +
      container.border.bottom
    if !finite(horizontal) || !finite(vertical) {
      Err(NonFiniteValue)
    } else {
      let inner_width = non_negative(container.size.width() - horizontal)
      let inner_height = non_negative(container.size.height() - vertical)
      let inner_x = container.border.left + container.padding.left
      let inner_y = container.border.top + container.padding.top
      match @primitives.Rect::new(inner_x, inner_y, inner_width, inner_height) {
        Err(_) => Err(GeometryFailure)
        Ok(content_bounds) => {
          let main_extent = if container.direction is Row {
            inner_width
          } else {
            inner_height
          }
          let cross_extent = if container.direction is Row {
            inner_height
          } else {
            inner_width
          }
          match prepare_items(container, items, main_extent, cross_extent) {
            Err(error) => Err(error)
            Ok(prepared) =>
              match container.wrap {
                FlexWrap::NoWrap =>
                  place_items(
                    container, prepared, content_bounds, main_extent, cross_extent,
                  )
                FlexWrap::Wrap | FlexWrap::WrapReverse =>
                  place_wrapped_items(
                    container, prepared, content_bounds, main_extent, cross_extent,
                  )
              }
          }
        }
      }
    }
  }
}

///|
fn prepare_items(
  container : FlexContainer,
  items : Array[FlexItem],
  main_extent : Double,
  cross_extent : Double,
) -> Result[Array[PreparedItem], LayoutError] {
  let prepared : Array[PreparedItem] = []
  let mut error : LayoutError? = None
  let mut index = 0
  while index < items.length() {
    let item = items[index]
    match error {
      Some(_) => ()
      None =>
        if !valid_limits(item.min_main, item.max_main) ||
          !valid_limits(item.min_cross, item.max_cross) {
          error = Some(InvalidMinMax)
        } else if !finite(item.grow) || !finite(item.shrink) {
          error = Some(NonFiniteValue)
        } else if item.grow < 0.0 || item.shrink < 0.0 {
          error = Some(NegativeValue)
        } else {
          match
            (
              resolve_dimension(item.main, Some(main_extent)),
              resolve_dimension(item.cross, Some(cross_extent)),
            ) {
            (Err(value), _) => error = Some(value)
            (_, Err(value)) => error = Some(value)
            (Ok(main_value), Ok(cross_value)) => {
              let intrinsic_main = if container.direction is Row {
                item.intrinsic.width()
              } else {
                item.intrinsic.height()
              }
              let intrinsic_cross = if container.direction is Row {
                item.intrinsic.height()
              } else {
                item.intrinsic.width()
              }
              let basis = match main_value {
                Some(value) => value
                None => intrinsic_main
              }
              let cross = match cross_value {
                Some(value) => value
                None =>
                  if container.align is Stretch &&
                    container.wrap is FlexWrap::NoWrap {
                    cross_extent
                  } else {
                    intrinsic_cross
                  }
              }
              let weight = item.shrink * basis
              if !finite(weight) {
                error = Some(NonFiniteValue)
              } else {
                prepared.push({
                  item,
                  basis,
                  cross: clamp_once(cross, item.min_cross, item.max_cross),
                  weight,
                })
              }
            }
          }
        }
    }
    index += 1
  }
  match error {
    Some(value) => Err(value)
    None => Ok(prepared)
  }
}

///|
// Return the leading offset and extra inter-item space for one resolved line.
// Keep wrapped and unwrapped placement on the same bounded GPUI semantics.
fn main_spacing(
  justify : JustifyContent,
  count : Int32,
  leftover : Double,
) -> (Double, Double) {
  match justify {
    Start => (0.0, 0.0)
    Center => (leftover / 2.0, 0.0)
    End => (leftover, 0.0)
    SpaceBetween =>
      if count > 1 && leftover > 0.0 {
        (0.0, leftover / (count - 1).to_double())
      } else {
        (0.0, 0.0)
      }
    SpaceAround | SpaceEvenly =>
      if count == 0 || leftover <= 0.0 {
        (0.0, 0.0)
      } else if justify is SpaceAround {
        let space = leftover / count.to_double()
        (space / 2.0, space)
      } else {
        let space = leftover / (count.to_double() + 1.0)
        (space, space)
      }
  }
}

///|
fn place_items(
  container : FlexContainer,
  prepared : Array[PreparedItem],
  content_bounds : @primitives.Rect,
  main_extent : Double,
  cross_extent : Double,
) -> Result[FlexLayout, LayoutError] {
  let count = prepared.length()
  let gaps = if count > 1 {
    (count - 1).to_double() * container.main_gap()
  } else {
    0.0
  }
  if !finite(gaps) {
    Err(NonFiniteValue)
  } else {
    match resolve_main_sizes(prepared, main_extent, gaps) {
      Err(error) => Err(error)
      Ok((resolved, used)) => {
        let leftover = main_extent - used
        let (leading, between_extra) = main_spacing(
          container.justify,
          count,
          leftover,
        )
        let mut cursor = leading
        let output : Array[LayoutBox] = []
        let mut any_overflow = exceeds_with_tolerance(used, main_extent)
        let mut error : LayoutError? = None
        let mut index = 0
        while index < prepared.length() {
          let entry = prepared[index]
          let main_size = resolved[index]
          let cross_size = entry.cross
          let cross_offset = match container.align {
            AlignItems::Start | Stretch => 0.0
            AlignItems::Center => (cross_extent - cross_size) / 2.0
            AlignItems::End => cross_extent - cross_size
          }
          let x = if container.direction is Row {
            content_bounds.left() + cursor
          } else {
            content_bounds.left() + cross_offset
          }
          let y = if container.direction is Row {
            content_bounds.top() + cross_offset
          } else {
            content_bounds.top() + cursor
          }
          let width = if container.direction is Row {
            main_size
          } else {
            cross_size
          }
          let height = if container.direction is Row {
            cross_size
          } else {
            main_size
          }
          match @primitives.Rect::new(x, y, width, height) {
            Err(_) => error = Some(GeometryFailure)
            Ok(bounds) => {
              // Measure leading overflow on the container's scale, so a
              // fractional exact-fit residue keeps the same tolerance.
              let overflow = exceeds_with_tolerance(
                  main_extent - cursor,
                  main_extent,
                ) ||
                exceeds_with_tolerance(cursor + main_size, main_extent) ||
                exceeds_with_tolerance(cross_size, cross_extent)
              if overflow {
                any_overflow = true
              }
              output.push({ id: entry.item.id, bounds, overflow, })
            }
          }
          cursor += main_size + container.main_gap() + between_extra
          index += 1
        }
        match error {
          Some(value) => Err(value)
          None => Ok({ content_bounds, items: output, overflow: any_overflow, })
        }
      }
    }
  }
}

///|
/// Lay out bounded wrapped lines. Line breaks use hypothetical main sizes;
/// flexible sizing is then resolved independently for each line. The default
/// cross-line alignment is stretch, matching GPUI/Taffy's default for this
/// fixed-viewport subset.
fn place_wrapped_items(
  container : FlexContainer,
  prepared : Array[PreparedItem],
  content_bounds : @primitives.Rect,
  main_extent : Double,
  cross_extent : Double,
) -> Result[FlexLayout, LayoutError] {
  let lines : Array[Array[PreparedItem]] = []
  let mut current : Array[PreparedItem] = []
  let mut line_length = 0.0
  let mut line_error : LayoutError? = None
  for entry in prepared {
    let hypothetical = clamp_once(
      entry.basis,
      entry.item.min_main,
      entry.item.max_main,
    )
    let gap = if current.length() == 0 { 0.0 } else { container.main_gap() }
    let proposed = line_length + gap + hypothetical
    if !finite(proposed) || !finite(hypothetical) {
      line_error = Some(NonFiniteValue)
    } else {
      // Suppress only binary64 accumulation residue at an exact-fit boundary;
      // this is the engine's tiny scale-relative geometry tolerance, not a
      // general conversion to GPUI's f32 pixel representation.
      if current.length() > 0 && exceeds_with_tolerance(proposed, main_extent) {
        lines.push(current)
        current = []
        line_length = 0.0
      }
      let next_gap = if current.length() == 0 {
        0.0
      } else {
        container.main_gap()
      }
      line_length += next_gap + hypothetical
      current.push(entry)
    }
  }
  if current.length() > 0 {
    lines.push(current)
  }
  match line_error {
    Some(error) => Err(error)
    None => {
      let resolved_lines : Array[Array[Double]] = []
      let used_main : Array[Double] = []
      let line_cross_sizes : Array[Double] = []
      let mut error : LayoutError? = None
      for line in lines {
        let gaps = if line.length() > 1 {
          (line.length() - 1).to_double() * container.main_gap()
        } else {
          0.0
        }
        if !finite(gaps) {
          error = Some(NonFiniteValue)
        } else {
          match resolve_main_sizes(line, main_extent, gaps) {
            Err(value) => error = Some(value)
            Ok((sizes, used)) => {
              resolved_lines.push(sizes)
              used_main.push(used)
              let mut cross = 0.0
              for entry in line {
                if entry.cross > cross {
                  cross = entry.cross
                }
              }
              line_cross_sizes.push(cross)
            }
          }
        }
      }
      match error {
        Some(value) => Err(value)
        None => {
          let line_gap_total = if lines.length() > 1 {
            (lines.length() - 1).to_double() * container.cross_gap()
          } else {
            0.0
          }
          let mut cross_total = line_gap_total
          for value in line_cross_sizes {
            cross_total += value
          }
          if !finite(line_gap_total) || !finite(cross_total) {
            Err(NonFiniteValue)
          } else {
            if container.align_content is AlignContent::Stretch &&
              lines.length() > 0 &&
              cross_total < cross_extent {
              let addition = (cross_extent - cross_total) /
                lines.length().to_double()
              for index = 0
                  index < line_cross_sizes.length()
                  index = index + 1 {
                line_cross_sizes[index] = line_cross_sizes[index] + addition
              }
              cross_total = cross_extent
            }
            place_wrapped_lines(
              container, lines, resolved_lines, used_main, line_cross_sizes, cross_total,
              content_bounds, main_extent, cross_extent,
            )
          }
        }
      }
    }
  }
}

///|
fn place_wrapped_lines(
  container : FlexContainer,
  lines : Array[Array[PreparedItem]],
  resolved_lines : Array[Array[Double]],
  used_main : Array[Double],
  line_cross_sizes : Array[Double],
  cross_total : Double,
  content_bounds : @primitives.Rect,
  main_extent : Double,
  cross_extent : Double,
) -> Result[FlexLayout, LayoutError] {
  let line_offsets : Array[Double] = Array::make(lines.length(), 0.0)
  let cross_free = cross_extent - cross_total
  let distributed = match container.align_content {
    AlignContent::SpaceBetween
    | AlignContent::SpaceAround
    | AlignContent::SpaceEvenly => true
    _ => false
  }
  let (leading, between_extra) = match container.align_content {
    AlignContent::SpaceBetween =>
      main_spacing(SpaceBetween, lines.length(), cross_free)
    AlignContent::SpaceAround =>
      main_spacing(SpaceAround, lines.length(), cross_free)
    AlignContent::SpaceEvenly =>
      main_spacing(SpaceEvenly, lines.length(), cross_free)
    _ => (0.0, 0.0)
  }
  let line_gap = container.cross_gap() + between_extra
  if container.wrap is FlexWrap::WrapReverse {
    if container.align_content is AlignContent::End ||
      (
        container.align_content is AlignContent::Stretch &&
        exceeds_with_tolerance(cross_total, cross_extent)
      ) ||
      (distributed && cross_free <= 0.0) {
      // Flex-relative end, overflowing default stretch, and nonpositive
      // distributed spacing anchor the stack at physical start. Accumulate
      // from that edge: cancellation must not move the safe outer boundary.
      let mut cross_cursor = 0.0
      let mut index = lines.length() - 1
      while index >= 0 {
        let line_size = line_cross_sizes[index]
        line_offsets[index] = cross_cursor
        cross_cursor += line_size + line_gap
        index -= 1
      }
    } else if distributed && lines.length() > 1 {
      // Build positive distributed spacing from the physical near edge too.
      // Subtracting a very large first line from the far edge can erase the
      // small lines and gaps that follow it. Anchor the opposite outer line
      // independently so both boundaries survive that cancellation.
      let mut cross_cursor = leading
      let mut index = lines.length() - 1
      while index >= 0 {
        line_offsets[index] = cross_cursor
        cross_cursor += line_cross_sizes[index] + line_gap
        index -= 1
      }
      line_offsets[0] = cross_extent - leading - line_cross_sizes[0]
    } else {
      // Flex-relative start is anchored directly at the inner far edge.
      // The half-sum centers the stack without overflowing a full sum or
      // cancelling a small cross extent against a much larger line total.
      let mut cross_cursor = if container.align_content is AlignContent::Center {
        cross_extent / 2.0 + cross_total / 2.0
      } else {
        cross_extent - leading
      }
      let mut index = 0
      while index < lines.length() {
        let line_size = line_cross_sizes[index]
        cross_cursor -= line_size
        line_offsets[index] = cross_cursor
        cross_cursor -= line_gap
        index += 1
      }
    }
  } else {
    let mut cross_cursor = match container.align_content {
      AlignContent::Start | AlignContent::Stretch => 0.0
      AlignContent::Center => cross_free / 2.0
      AlignContent::End => cross_free
      AlignContent::SpaceBetween
      | AlignContent::SpaceAround
      | AlignContent::SpaceEvenly => leading
    }
    let mut index = 0
    while index < lines.length() {
      let line_size = line_cross_sizes[index]
      line_offsets[index] = cross_cursor
      cross_cursor += line_size + line_gap
      index += 1
    }
    if distributed && cross_free > 0.0 && lines.length() > 1 {
      let last = lines.length() - 1
      line_offsets[last] = cross_extent - leading - line_cross_sizes[last]
    }
  }
  let output : Array[LayoutBox] = []
  let mut any_overflow = exceeds_with_tolerance(cross_total, cross_extent)
  let mut error : LayoutError? = None
  for line_index = 0; line_index < lines.length(); line_index = line_index + 1 {
    let line = lines[line_index]
    let sizes = resolved_lines[line_index]
    let line_used = used_main[line_index]
    let line_cross = line_cross_sizes[line_index]
    let cross_line_start = line_offsets[line_index]
    let leftover = main_extent - line_used
    let (leading, between_extra) = main_spacing(
      container.justify,
      line.length(),
      leftover,
    )
    let mut main_cursor = leading
    for item_index = 0; item_index < line.length(); item_index = item_index + 1 {
      let entry = line[item_index]
      let main_size = sizes[item_index]
      let cross_size = if container.align is AlignItems::Stretch &&
        entry.item.cross is Dimension::Auto {
        clamp_once(line_cross, entry.item.min_cross, entry.item.max_cross)
      } else {
        entry.cross
      }
      let cross_free = line_cross - cross_size
      let cross_alignment = match container.align {
        AlignItems::Start =>
          if container.wrap is FlexWrap::WrapReverse {
            cross_free
          } else {
            0.0
          }
        AlignItems::Center => cross_free / 2.0
        AlignItems::End =>
          if container.wrap is FlexWrap::WrapReverse {
            0.0
          } else {
            cross_free
          }
        AlignItems::Stretch =>
          if container.wrap is FlexWrap::WrapReverse {
            cross_free
          } else {
            0.0
          }
      }
      let cross_start = cross_line_start + cross_alignment
      let x = if container.direction is Row {
        content_bounds.left() + main_cursor
      } else {
        content_bounds.left() + cross_start
      }
      let y = if container.direction is Row {
        content_bounds.top() + cross_start
      } else {
        content_bounds.top() + main_cursor
      }
      let width = if container.direction is Row {
        main_size
      } else {
        cross_size
      }
      let height = if container.direction is Row {
        cross_size
      } else {
        main_size
      }
      match @primitives.Rect::new(x, y, width, height) {
        Err(_) => error = Some(GeometryFailure)
        Ok(bounds) => {
          let main_overflow = exceeds_with_tolerance(
              main_extent - main_cursor,
              main_extent,
            ) ||
            exceeds_with_tolerance(main_cursor + main_size, main_extent)
          let cross_overflow = exceeds_with_tolerance(
              cross_extent - cross_start,
              cross_extent,
            ) ||
            exceeds_with_tolerance(cross_start + cross_size, cross_extent)
          let overflow = main_overflow || cross_overflow
          if overflow {
            any_overflow = true
          }
          output.push({ id: entry.item.id, bounds, overflow, })
        }
      }
      main_cursor += main_size + container.main_gap() + between_extra
    }
  }
  match error {
    Some(value) => Err(value)
    None => Ok({ content_bounds, items: output, overflow: any_overflow, })
  }
}

///|
fn finite(value : Double) -> Bool {
  !value.is_nan() && !value.is_inf()
}

///|
/// Layout overflow compares reconstructed floating-point sums with a bounded
/// scale-relative tolerance of roughly 32 binary64 epsilons. This suppresses
/// arithmetic residue from exact-fit distributions without masking meaningful
/// layout excess.
fn exceeds_with_tolerance(value : Double, limit : Double) -> Bool {
  if value <= limit {
    false
  } else {
    let scale = if value > 1.0 {
      value
    } else if limit > 1.0 {
      limit
    } else {
      1.0
    }
    value - limit > scale * 7.105427357601002e-15
  }
}

///|
fn non_negative(value : Double) -> Double {
  if value > 0.0 {
    value
  } else {
    0.0
  }
}

///|
fn valid_limits(min : Double, max : Double?) -> Bool {
  if !finite(min) || min < 0.0 {
    false
  } else {
    match max {
      None => true
      Some(value) => finite(value) && value >= min
    }
  }
}

///|
fn clamp_once(value : Double, min : Double, max : Double?) -> Double {
  let lower = if value < min { min } else { value }
  match max {
    Some(limit) if lower > limit => limit
    _ => lower
  }
}

///|
fn has_duplicate_ids(items : Array[FlexItem]) -> Bool {
  let mut outer = 0
  let mut duplicate = false
  while outer < items.length() && !duplicate {
    let mut inner = outer + 1
    while inner < items.length() && !duplicate {
      if items[outer].id == items[inner].id {
        duplicate = true
      }
      inner += 1
    }
    outer += 1
  }
  duplicate
}
