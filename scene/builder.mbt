///|
/// Horizontal alignment used by SceneBuilder text items.
pub(all) enum TextAlign {
  Left
  Center
  Right
} derive(Eq)

///|
pub extend TextAlign with Eq::{not_equal, equal}

///|
/// Vertical alignment used by SceneBuilder text items.
pub(all) enum TextVerticalAlign {
  Top
  Center
  Bottom
} derive(Eq)

///|
pub extend TextVerticalAlign with Eq::{not_equal, equal}

///|
/// Errors from deterministic scene assembly. Snapshot validation errors are
/// preserved so callers can distinguish bad metrics from a bad item.
pub(all) enum SceneBuilderError {
  InvalidScale
  InvalidId
  DuplicateId(UInt64)
  IdExhausted
  ItemLimitExceeded
  ClipIdExhausted
  ClipLimitExceeded
  InvalidMetrics
  Snapshot(SnapshotError)
} derive(Eq)

///|
pub extend SceneBuilderError with Eq::{not_equal, equal}

///|
const MAX_BUILDER_ITEMS : Int32 = 65536

///|
const MAX_BUILDER_CLIP_RECTS : Int32 = 64

///|
const MAX_BUILDER_ITEM_ID : UInt64 = 9223372036854775807UL

///|
const MAX_BUILDER_CLIP_ID : Int32 = 2147483647

///|
/// Deterministic scene composition helper. It owns item and clip-chain ID
/// allocation, rejects duplicate external IDs, deduplicates identical clip
/// rectangles and applies measured text alignment. The resulting snapshot uses
/// the existing SceneSnapshot v1 envelope.
pub struct SceneBuilder {
  priv viewport : @primitives.Rect
  priv scale : Double
  priv items : Array[SceneItem]
  priv clips : Array[ClipChain]
  priv ids : Map[UInt64, Bool]
  priv mut next_item_id : UInt64
  priv mut next_clip_id : Int32
}

///|
pub fn SceneBuilder::new(
  viewport : @primitives.Rect,
  scale : Double,
) -> Result[SceneBuilder, SceneBuilderError] {
  if !builder_finite(scale) || scale <= 0.0 {
    return Err(InvalidScale)
  }
  Ok({
    viewport,
    scale,
    items: [],
    clips: [],
    ids: Map([]),
    next_item_id: 1UL,
    next_clip_id: 1,
  })
}

///|
fn builder_finite(value : Double) -> Bool {
  !value.is_nan() && !value.is_inf()
}

///|
fn SceneBuilder::allocate_item_id(
  self : SceneBuilder,
) -> Result[UInt64, SceneBuilderError] {
  if self.next_item_id == 0UL {
    return Err(IdExhausted)
  }
  let id = self.next_item_id
  self.next_item_id = if id == MAX_BUILDER_ITEM_ID { 0UL } else { id + 1UL }
  Ok(id)
}

///|
fn SceneBuilder::track_item(
  self : SceneBuilder,
  id : UInt64,
) -> Result[Unit, SceneBuilderError] {
  if id == 0UL {
    Err(InvalidId)
  } else if self.ids.get(id) is Some(_) {
    Err(DuplicateId(id))
  } else {
    self.ids[id] = true
    Ok(())
  }
}

///|
fn SceneBuilder::check_item_capacity(
  self : SceneBuilder,
) -> Result[Unit, SceneBuilderError] {
  if self.items.length() >= MAX_BUILDER_ITEMS {
    Err(ItemLimitExceeded)
  } else {
    Ok(())
  }
}

///|
/// Next item ID that will be allocated. Zero means the allocator is exhausted.
pub fn SceneBuilder::next_item_id(self : SceneBuilder) -> UInt64 {
  self.next_item_id
}

///|
pub fn SceneBuilder::item_count(self : SceneBuilder) -> Int32 {
  self.items.length()
}

///|
pub fn SceneBuilder::clip_count(self : SceneBuilder) -> Int32 {
  self.clips.length()
}

///|
/// Reserve a contiguous item-ID range for controls that build their own scene
/// items (for example TextField's eight-item reservation).
pub fn SceneBuilder::reserve_ids(
  self : SceneBuilder,
  count : Int32,
) -> Result[UInt64, SceneBuilderError] {
  if count < 0 {
    return Err(InvalidId)
  }
  if self.next_item_id == 0UL {
    return Err(IdExhausted)
  }
  let base = self.next_item_id
  let available = MAX_BUILDER_ITEM_ID - base + 1UL
  if count.to_uint64() > available {
    return Err(IdExhausted)
  }
  self.next_item_id = if count.to_uint64() == available {
    0UL
  } else {
    base + count.to_uint64()
  }
  Ok(base)
}

///|
/// Add a quad with a freshly allocated ID.
pub fn SceneBuilder::quad(
  self : SceneBuilder,
  bounds : @primitives.Rect,
  color : @primitives.Color,
) -> Result[UInt64, SceneBuilderError] {
  match self.check_item_capacity() {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  let id = match self.allocate_item_id() {
    Err(error) => return Err(error)
    Ok(value) => value
  }
  match self.track_item(id) {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  let item = match
    SceneItem::quad(id, bounds, color, AffineTransform::identity(), 1.0, None) {
    Ok(value) => value
    Err(error) => return Err(Snapshot(error))
  }
  self.items.push(item)
  Ok(id)
}

///|
/// Add a one-pixel style quad border around `bounds`. The border must fit
/// inside the rectangle on both axes.
pub fn SceneBuilder::border(
  self : SceneBuilder,
  bounds : @primitives.Rect,
  width : Double,
  color : @primitives.Color,
) -> Result[Unit, SceneBuilderError] {
  if !builder_finite(width) || width <= 0.0 {
    return Err(InvalidMetrics)
  }
  let inner_width = bounds.size().width()
  let inner_height = bounds.size().height()
  if width * 2.0 > inner_width || width * 2.0 > inner_height {
    return Err(InvalidMetrics)
  }
  let top = match
    @primitives.Rect::new(bounds.left(), bounds.top(), inner_width, width) {
    Ok(value) => value
    Err(_) => return Err(InvalidMetrics)
  }
  let bottom = match
    @primitives.Rect::new(
      bounds.left(),
      bounds.bottom() - width,
      inner_width,
      width,
    ) {
    Ok(value) => value
    Err(_) => return Err(InvalidMetrics)
  }
  let left = match
    @primitives.Rect::new(bounds.left(), bounds.top(), width, inner_height) {
    Ok(value) => value
    Err(_) => return Err(InvalidMetrics)
  }
  let right = match
    @primitives.Rect::new(
      bounds.right() - width,
      bounds.top(),
      width,
      inner_height,
    ) {
    Ok(value) => value
    Err(_) => return Err(InvalidMetrics)
  }
  for edge in [top, bottom, left, right] {
    match self.quad(edge, color) {
      Err(error) => return Err(error)
      Ok(_) => ()
    }
  }
  Ok(())
}

///|
fn clip_rects_equal(
  left : Array[@primitives.Rect],
  right : Array[@primitives.Rect],
) -> Bool {
  if left.length() != right.length() {
    return false
  }
  let mut index = 0
  while index < left.length() {
    if left[index] != right[index] {
      return false
    }
    index += 1
  }
  true
}

///|
/// Register a rectangle clip chain. Identical rectangle arrays reuse the same
/// chain ID, matching SceneSnapshot's deterministic clip behavior.
pub fn SceneBuilder::clip(
  self : SceneBuilder,
  rects : Array[@primitives.Rect],
) -> Result[Int32, SceneBuilderError] {
  if rects.length() > MAX_BUILDER_CLIP_RECTS {
    return Err(ClipLimitExceeded)
  }
  for existing in self.clips {
    if clip_rects_equal(existing.rects(), rects) {
      return Ok(existing.id())
    }
  }
  if self.next_clip_id == MAX_BUILDER_CLIP_ID {
    return Err(ClipIdExhausted)
  }
  let id = self.next_clip_id
  self.next_clip_id += 1
  self.clips.push(ClipChain::new(id, rects))
  Ok(id)
}

///|
/// Add one measured text item. `measured_width` and `line_height` normally come
/// from a text-layout implementation; alignment is computed in logical points.
pub fn SceneBuilder::text(
  self : SceneBuilder,
  bounds : @primitives.Rect,
  text : String,
  font_size : Double,
  color : @primitives.Color,
  align : TextAlign,
  vertical : TextVerticalAlign,
  measured_width : Double,
  line_height : Double,
  clip_chain_id : Int32?,
) -> Result[UInt64, SceneBuilderError] {
  if !builder_finite(measured_width) ||
    !builder_finite(line_height) ||
    measured_width < 0.0 ||
    line_height < 0.0 ||
    !builder_finite(font_size) ||
    font_size <= 0.0 {
    return Err(InvalidMetrics)
  }
  match self.check_item_capacity() {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  let width = if measured_width <= 0.0 { 1.0 } else { measured_width + 2.0 }
  let height = if line_height <= 0.0 { font_size } else { line_height }
  let x = match align {
    TextAlign::Left => bounds.left()
    TextAlign::Center => bounds.left() + (bounds.size().width() - width) / 2.0
    TextAlign::Right => bounds.right() - width
  }
  let y = match vertical {
    TextVerticalAlign::Top => bounds.top()
    TextVerticalAlign::Center =>
      bounds.top() + (bounds.size().height() - height) / 2.0
    TextVerticalAlign::Bottom => bounds.bottom() - height
  }
  let text_bounds = match @primitives.Rect::new(x, y, width, height) {
    Ok(value) => value
    Err(_) => return Err(InvalidMetrics)
  }
  let id = match self.allocate_item_id() {
    Err(error) => return Err(error)
    Ok(value) => value
  }
  match self.track_item(id) {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  let item = match
    SceneItem::text(
      id,
      text_bounds,
      text,
      font_size,
      color,
      AffineTransform::identity(),
      1.0,
      clip_chain_id,
    ) {
    Ok(value) => value
    Err(error) => return Err(Snapshot(error))
  }
  self.items.push(item)
  Ok(id)
}

///|
/// Append items built by another bounded control. IDs must be non-zero and
/// unique; the allocator advances past the largest external ID.
pub fn SceneBuilder::push_items(
  self : SceneBuilder,
  items : Array[SceneItem],
) -> Result[Unit, SceneBuilderError] {
  for item in items {
    match self.check_item_capacity() {
      Err(error) => return Err(error)
      Ok(_) => ()
    }
    let id = item.id()
    match self.track_item(id) {
      Err(error) => return Err(error)
      Ok(_) => ()
    }
    if self.next_item_id != 0UL && id >= self.next_item_id {
      self.next_item_id = if id == MAX_BUILDER_ITEM_ID { 0UL } else { id + 1UL }
    }
    self.items.push(item)
  }
  Ok(())
}

///|
/// Freeze the current items and clips into the existing scene v1 envelope.
pub fn SceneBuilder::snapshot(
  self : SceneBuilder,
) -> Result[SceneSnapshot, SceneBuilderError] {
  match
    SceneSnapshot::new(self.viewport, self.scale, [], self.clips, self.items) {
    Ok(value) => Ok(value)
    Err(error) => Err(Snapshot(error))
  }
}
