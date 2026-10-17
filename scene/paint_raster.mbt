///|
/// Sample one enhanced item by ID. Duplicate IDs are permitted by the legacy
/// scene contract, but selecting an ambiguous ID fails instead of choosing one.
/// Result channels are unpremultiplied shader-linear RGB, with opacity applied
/// once to alpha. None means clipped or outside binary geometric coverage.
pub fn SceneSnapshot::sample_paint(
  self : SceneSnapshot,
  id : UInt64,
  point : @primitives.Point,
) -> Result[@primitives.FloatColor?, PaintError] {
  let mut selected : SceneItem? = None
  for item in self.items {
    if item.id() == id {
      if selected is Some(_) {
        return Err(AmbiguousPaint)
      }
      selected = Some(item)
    }
  }
  match selected {
    None => Err(UnknownPaint)
    Some(PaintItem(..) as item) => self.sample_item_shader_linear(item, point)
    Some(_) => Err(UnsupportedPaint)
  }
}

///|
fn paint_inverse_point(
  point : @primitives.Point,
  transform : AffineTransform,
) -> Result[@primitives.Point, PaintError] {
  if transform.b() != 0.0 ||
    transform.c() != 0.0 ||
    transform.a() == 0.0 ||
    transform.d() == 0.0 {
    return Err(UnsupportedTransform)
  }
  match
    @primitives.Point::new(
      (point.x() - transform.tx()) / transform.a(),
      (point.y() - transform.ty()) / transform.d(),
    ) {
    Ok(p) => Ok(p)
    Err(_) => Err(InvalidGeometry)
  }
}

///|
fn paint_local_clip(
  clip : @primitives.Rect,
  transform : AffineTransform,
) -> Result[@primitives.Rect, PaintError] {
  let a = match paint_inverse_point(clip.origin(), transform) {
    Ok(p) => p
    Err(e) => return Err(e)
  }
  let corner = match @primitives.Point::new(clip.right(), clip.bottom()) {
    Ok(p) => p
    Err(_) => return Err(InvalidGeometry)
  }
  let b = match paint_inverse_point(corner, transform) {
    Ok(p) => p
    Err(e) => return Err(e)
  }
  let x = if a.x() < b.x() { a.x() } else { b.x() }
  let y = if a.y() < b.y() { a.y() } else { b.y() }
  let w = if a.x() < b.x() { b.x() - a.x() } else { a.x() - b.x() }
  let h = if a.y() < b.y() { b.y() - a.y() } else { a.y() - b.y() }
  match @primitives.Rect::new(x, y, w, h) {
    Ok(r) => Ok(r)
    Err(_) => Err(InvalidGeometry)
  }
}

///|
fn SceneSnapshot::sample_item_shader_linear(
  self : SceneSnapshot,
  item : SceneItem,
  point : @primitives.Point,
) -> Result[@primitives.FloatColor?, PaintError] {
  let (transform, opacity, clip_id) = match item {
    PaintItem(transform~, opacity~, clip_chain_id~, ..)
    | QuadItem(transform~, opacity~, clip_chain_id~, ..) =>
      (transform, opacity, clip_chain_id)
    _ => return Err(UnsupportedPaint)
  }
  let local_point = match paint_inverse_point(point, transform) {
    Ok(p) => p
    Err(e) => return Err(e)
  }
  if !self.viewport.contains(point) {
    return Ok(None)
  }
  let viewport_clip = match paint_local_clip(self.viewport, transform) {
    Ok(c) => c
    Err(e) => return Err(e)
  }
  let local_clips = [viewport_clip]
  match clip_id {
    None => ()
    Some(id) =>
      for chain in self.clip_chains {
        if chain.id() == id {
          for clip in chain.rects() {
            if !clip.contains(point) {
              return Ok(None)
            }
            match paint_local_clip(clip, transform) {
              Ok(c) => local_clips.push(c)
              Err(e) => return Err(e)
            }
          }
        }
      }
  }
  let color = match item {
    PaintItem(shape~, fill~, ..) => {
      if !shape.contains(local_point) {
        return Ok(None)
      }
      let basis = match shape.normalization_bounds(local_clips) {
        None => return Ok(None)
        Some(b) => b
      }
      match fill.sample(local_point, basis) {
        Ok(c) => c
        Err(e) => return Err(e)
      }
    }
    QuadItem(bounds~, color~, ..) => {
      if !bounds.contains(local_point) {
        return Ok(None)
      }
      match
        @primitives.FloatColor::rgba(
          color.red().to_double() / 255.0,
          color.green().to_double() / 255.0,
          color.blue().to_double() / 255.0,
          color.alpha().to_double() / 255.0,
        ) {
        Ok(c) => c
        Err(_) => return Err(InvalidColor)
      }
    }
    _ => return Err(UnsupportedPaint)
  }
  match
    @primitives.FloatColor::rgba(
      color.red(),
      color.green(),
      color.blue(),
      color.alpha() * opacity,
    ) {
    Ok(c) => Ok(Some(c))
    Err(_) => Err(InvalidColor)
  }
}

///|
/// Bounded point-sampled reference presentation for the observed software
/// WebGL2 route: shader-linear values are composited without a transfer-function
/// encoding, then rounded to RGBA bytes. This is an explicit output choice, not
/// a claim about other backends. Rounded/polygon antialiasing is not modeled.
/// Text and non-axis-aligned/singular transforms are rejected before allocation.
/// Dimensions <=2048, <=1,048,576 pixels, <=64,000,000 item-pixel evaluations.
pub fn SceneSnapshot::rasterize_webgl2_linear(
  self : SceneSnapshot,
  bounds : @primitives.Rect,
  width : Int32,
  height : Int32,
  background : @primitives.FloatColor,
) -> Result[Array[Int32], PaintError] {
  if width <= 0 ||
    height <= 0 ||
    width > 2048 ||
    height > 2048 ||
    width * height > 1048576 ||
    self.items.length() > 64000000 / (width * height) ||
    bounds.size().width() <= 0.0 ||
    bounds.size().height() <= 0.0 {
    return Err(InvalidRaster)
  }
  match background.validate() {
    Err(_) => return Err(InvalidColor)
    Ok(_) => ()
  }
  for item in self.items {
    let transform = match item {
      PaintItem(transform~, ..) | QuadItem(transform~, ..) => transform
      _ => return Err(UnsupportedPaint)
    }
    if transform.b() != 0.0 ||
      transform.c() != 0.0 ||
      transform.a() == 0.0 ||
      transform.d() == 0.0 {
      return Err(UnsupportedTransform)
    }
  }
  let bytes : Array[Int32] = []
  for y = 0; y < height; y = y + 1 {
    for x = 0; x < width; x = x + 1 {
      let point = match
        @primitives.Point::new(
          bounds.left() +
          (x.to_double() + 0.5) * bounds.size().width() / width.to_double(),
          bounds.top() +
          (y.to_double() + 0.5) * bounds.size().height() / height.to_double(),
        ) {
        Ok(p) => p
        Err(_) => return Err(InvalidRaster)
      }
      let mut a = background.alpha()
      let mut r = background.red() * a
      let mut g = background.green() * a
      let mut b = background.blue() * a
      for item in self.items {
        match self.sample_item_shader_linear(item, point) {
          Err(e) => return Err(e)
          Ok(None) => ()
          Ok(Some(c)) => {
            let remaining = 1.0 - c.alpha()
            r = c.red() * c.alpha() + r * remaining
            g = c.green() * c.alpha() + g * remaining
            b = c.blue() * c.alpha() + b * remaining
            a = c.alpha() + a * remaining
          }
        }
      }
      if a > 0.0 {
        r = r / a
        g = g / a
        b = b / a
      }
      bytes.push(paint_byte(r))
      bytes.push(paint_byte(g))
      bytes.push(paint_byte(b))
      bytes.push(paint_byte(a))
    }
  }
  Ok(bytes)
}

///|
fn paint_byte(v : Double) -> Int32 {
  let clamped = if v < 0.0 { 0.0 } else if v > 1.0 { 1.0 } else { v }
  (clamped * 255.0 + 0.5).to_int()
}

///|
/// Raster one item selected by canonical order, with a transparent background.
/// A leaf can interleave these pixels with explicit legacy text presentation
/// without regrouping items or precompositing across them. Text is an explicit
/// UnsupportedPaint result; invalid index is UnknownPaint. All geometry,
/// clipping, gradient normalization and opacity remain in this core operation.
pub fn SceneSnapshot::rasterize_item_webgl2_linear(
  self : SceneSnapshot,
  index : Int32,
  bounds : @primitives.Rect,
  width : Int32,
  height : Int32,
) -> Result[Array[Int32], PaintError] {
  if index < 0 || index >= self.items.length() {
    return Err(UnknownPaint)
  }
  let selected = { ..self, items: [self.items[index]], }
  let transparent = match @primitives.FloatColor::rgba(0.0, 0.0, 0.0, 0.0) {
    Ok(c) => c
    Err(_) => return Err(InvalidColor)
  }
  selected.rasterize_webgl2_linear(bounds, width, height, transparent)
}

///|
/// An ordered item's tight physical tile. RGBA is straight (not premultiplied),
/// raw shader-linear channel bytes for the explicitly selected WebGL2 profile.
/// Upload/source-over once with identity transform, full opacity and no clips:
/// geometry, clipping, transform and opacity have already been applied here.
pub struct PaintRasterTile {
  x : Int32
  y : Int32
  width : Int32
  height : Int32
  priv rgba : Array[Int32]
}

///|
pub fn PaintRasterTile::x(self : PaintRasterTile) -> Int32 {
  self.x
}

///|
pub fn PaintRasterTile::y(self : PaintRasterTile) -> Int32 {
  self.y
}

///|
pub fn PaintRasterTile::width(self : PaintRasterTile) -> Int32 {
  self.width
}

///|
pub fn PaintRasterTile::height(self : PaintRasterTile) -> Int32 {
  self.height
}

///|
pub fn PaintRasterTile::rgba(self : PaintRasterTile) -> Array[Int32] {
  let bytes = []
  for b in self.rgba {
    bytes.push(b)
  }
  bytes
}

///|
/// Resolve one canonical item to a clipped-tight physical tile, preserving its
/// index for interleaving with legacy text. None is a fully clipped item; text
/// returns UnsupportedPaint, never a silent omission. Uses snapshot scale and
/// viewport. Same per-tile resource bounds as rasterize_webgl2_linear.
fn SceneSnapshot::paint_tile_bounds(
  self : SceneSnapshot,
  index : Int32,
) -> Result[(Int32, Int32, Int32, Int32)?, PaintError] {
  if index < 0 || index >= self.items.length() {
    return Err(UnknownPaint)
  }
  let item = self.items[index]
  let (shape_bounds, transform, clip_id) = match item {
    PaintItem(shape~, transform~, clip_chain_id~, ..) =>
      (shape.bounds(), transform, clip_chain_id)
    QuadItem(bounds~, transform~, clip_chain_id~, ..) =>
      (bounds, transform, clip_chain_id)
    _ => return Err(UnsupportedPaint)
  }
  if transform.b() != 0.0 ||
    transform.c() != 0.0 ||
    transform.a() == 0.0 ||
    transform.d() == 0.0 {
    return Err(UnsupportedTransform)
  }
  let clips = [self.viewport]
  match clip_id {
    None => ()
    Some(id) =>
      for chain in self.clip_chains {
        if chain.id() == id {
          for clip in chain.rects() {
            clips.push(clip)
          }
        }
      }
  }
  let local_clips = []
  for clip in clips {
    match paint_local_clip(clip, transform) {
      Ok(c) => local_clips.push(c)
      Err(e) => return Err(e)
    }
  }
  let tight = match item {
    PaintItem(shape=Polygon(_) as shape, ..) =>
      match shape.normalization_bounds(local_clips) {
        Some(b) => b
        None => return Ok(None)
      }
    _ => shape_bounds
  }
  let ax = tight.left() * transform.a() + transform.tx()
  let bx = tight.right() * transform.a() + transform.tx()
  let ay = tight.top() * transform.d() + transform.ty()
  let by = tight.bottom() * transform.d() + transform.ty()
  let left = if ax < bx { ax } else { bx }
  let top = if ay < by { ay } else { by }
  let mut bounds = match
    @primitives.Rect::new(left, top, (bx - ax).abs(), (by - ay).abs()) {
    Ok(r) => r
    Err(_) => return Err(InvalidGeometry)
  }
  for clip in clips {
    match bounds.intersection(clip) {
      Some(b) => bounds = b
      None => return Ok(None)
    }
  }
  if bounds.size().width() == 0.0 || bounds.size().height() == 0.0 {
    return Ok(None)
  }
  let x0 = @math.floor(bounds.left() * self.scale)
  let y0 = @math.floor(bounds.top() * self.scale)
  let x1 = @math.ceil(bounds.right() * self.scale)
  let y1 = @math.ceil(bounds.bottom() * self.scale)
  for v in [x0, y0, x1, y1] {
    if !snapshot_finite(v) || v < -2147483647.0 || v > 2147483647.0 {
      return Err(InvalidRaster)
    }
  }
  if x1 - x0 > 2048.0 || y1 - y0 > 2048.0 {
    return Err(InvalidRaster)
  }
  let x = x0.to_int()
  let y = y0.to_int()
  let width = (x1 - x0).to_int()
  let height = (y1 - y0).to_int()
  Ok(Some((x, y, width, height)))
}

///|
pub fn SceneSnapshot::rasterize_item_tile_webgl2_linear(
  self : SceneSnapshot,
  index : Int32,
) -> Result[PaintRasterTile?, PaintError] {
  self.rasterize_paint_run_webgl2_linear(index, 1)
}

///|
/// Rasterize exactly a contiguous run from the canonical item array, preserving
/// source order and performing float source-over before final byte quantization.
/// Text inside the selected run is UnsupportedPaint, never skipped. Include an
/// existing opaque background item in the run when testing exact alpha output;
/// separately composited RGBA8 tiles introduce an additional alpha quantization
/// boundary. No items may be regrouped across intervening text or other items.
/// The clipped union tile uses snapshot scale; maximum dimensions 2048, pixels
/// 1,048,576, and selected item-pixel evaluations 64,000,000.
pub fn SceneSnapshot::rasterize_paint_run_webgl2_linear(
  self : SceneSnapshot,
  start : Int32,
  count : Int32,
) -> Result[PaintRasterTile?, PaintError] {
  if start < 0 ||
    count <= 0 ||
    start >= self.items.length() ||
    count > self.items.length() - start {
    return Err(UnknownPaint)
  }
  let mut union : (Double, Double, Double, Double)? = None
  for i = start; i < start + count; i = i + 1 {
    match self.paint_tile_bounds(i) {
      Err(e) => return Err(e)
      Ok(None) => ()
      Ok(Some((x, y, w, h))) => {
        let left = x.to_double()
        let top = y.to_double()
        let right = left + w.to_double()
        let bottom = top + h.to_double()
        union = Some(
          match union {
            None => (left, top, right, bottom)
            Some((a, b, c, d)) =>
              (
                if left < a {
                  left
                } else {
                  a
                },
                if top < b {
                  top
                } else {
                  b
                },
                if right > c {
                  right
                } else {
                  c
                },
                if bottom > d {
                  bottom
                } else {
                  d
                },
              )
          },
        )
      }
    }
  }
  let (x0, y0, x1, y1) = match union {
    None => return Ok(None)
    Some(v) => v
  }
  if x1 - x0 > 2048.0 || y1 - y0 > 2048.0 {
    return Err(InvalidRaster)
  }
  let width = (x1 - x0).to_int()
  let height = (y1 - y0).to_int()
  if width <= 0 ||
    height <= 0 ||
    width * height > 1048576 ||
    count > 64000000 / (width * height) {
    return Err(InvalidRaster)
  }
  let bounds = match
    @primitives.Rect::new(
      x0 / self.scale,
      y0 / self.scale,
      (x1 - x0) / self.scale,
      (y1 - y0) / self.scale,
    ) {
    Ok(r) => r
    Err(_) => return Err(InvalidRaster)
  }
  let items = []
  for i = start; i < start + count; i = i + 1 {
    items.push(self.items[i])
  }
  let selected = { ..self, items, }
  let transparent = match @primitives.FloatColor::rgba(0, 0, 0, 0) {
    Ok(c) => c
    Err(_) => return Err(InvalidColor)
  }
  match selected.rasterize_webgl2_linear(bounds, width, height, transparent) {
    Err(e) => Err(e)
    Ok(rgba) =>
      Ok(Some({ x: x0.to_int(), y: y0.to_int(), width, height, rgba, }))
  }
}
