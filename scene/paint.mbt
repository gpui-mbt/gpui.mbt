///|
/// Errors in the bounded enhanced paint surface. Legacy paint is unchanged.
pub(all) enum PaintError {
  InvalidColor
  InvalidGradient
  InvalidPattern
  InvalidGeometry
  InvalidOpacity
  UnsupportedPaint
  UnknownPaint
  AmbiguousPaint
  UnsupportedTransform
  InvalidRaster
} derive(Eq)

///|
pub extend PaintError with Eq::{equal, not_equal}

///|
pub(all) enum PaintFill {
  FloatSolid(@primitives.FloatColor)
  Gradient(LinearGradient)
  Slash(SlashPattern)
} derive(Eq)

///|
pub extend PaintFill with Eq::{equal, not_equal}

///|
/// At most 64 strictly convex vertices; either winding is accepted. Points are
/// copied on ingress and egress. Coordinates are bounded to +/- 1e9.
pub struct ConvexPolygon {
  priv points : Array[@primitives.Point]
  bounds : @primitives.Rect
} derive(Eq)

///|
pub extend ConvexPolygon with Eq::{equal, not_equal}

///|
pub(all) enum PaintShape {
  RoundedQuad(bounds~ : @primitives.Rect, radius~ : Double)
  Polygon(ConvexPolygon)
} derive(Eq)

///|
pub extend PaintShape with Eq::{equal, not_equal}

///|
pub fn PaintShape::rounded_quad(
  bounds : @primitives.Rect,
  radius : Double,
) -> Result[PaintShape, PaintError] {
  let shape = RoundedQuad(bounds~, radius~)
  match shape.validate() {
    Ok(_) => Ok(shape)
    Err(e) => Err(e)
  }
}

///|
pub fn PaintShape::convex_polygon(
  points : Array[@primitives.Point],
) -> Result[PaintShape, PaintError] {
  if points.length() < 3 || points.length() > 64 {
    return Err(InvalidGeometry)
  }
  for p in points {
    if !paint_coordinate(p.x()) || !paint_coordinate(p.y()) {
      return Err(InvalidGeometry)
    }
  }
  let bounds = match paint_points_bounds(points) {
    None => return Err(InvalidGeometry)
    Some(bounds) => bounds
  }
  let mut sign = 0.0
  for i = 0; i < points.length(); i = i + 1 {
    let a = points[i]
    let b = points[(i + 1) % points.length()]
    for j = 0; j < points.length(); j = j + 1 {
      if j != i && j != (i + 1) % points.length() {
        let cross = paint_orientation(a, b, points[j], bounds)
        if cross == 0.0 ||
          (sign < 0.0 && cross > 0.0) ||
          (sign > 0.0 && cross < 0.0) {
          return Err(InvalidGeometry)
        }
        sign = cross
      }
    }
  }
  Ok(Polygon({ points: paint_copy_points(points), bounds, }))
}

///|
pub fn ConvexPolygon::points(self : ConvexPolygon) -> Array[@primitives.Point] {
  paint_copy_points(self.points)
}

///|
pub fn ConvexPolygon::bounds(self : ConvexPolygon) -> @primitives.Rect {
  self.bounds
}

///|
pub fn PaintShape::bounds(self : PaintShape) -> @primitives.Rect {
  match self {
    RoundedQuad(bounds~, ..) => bounds
    Polygon(p) => p.bounds
  }
}

///|
pub fn PaintShape::validate(self : PaintShape) -> Result[Unit, PaintError] {
  match self {
    RoundedQuad(bounds~, radius~) =>
      if !paint_coordinate(bounds.left()) ||
        !paint_coordinate(bounds.top()) ||
        !paint_coordinate(bounds.right()) ||
        !paint_coordinate(bounds.bottom()) ||
        bounds.size().width() <= 0.0 ||
        bounds.size().height() <= 0.0 ||
        !snapshot_finite(radius) ||
        radius < 0.0 ||
        radius > bounds.size().width() / 2.0 ||
        radius > bounds.size().height() / 2.0 {
        Err(InvalidGeometry)
      } else {
        Ok(())
      }
    Polygon(p) =>
      match PaintShape::convex_polygon(p.points) {
        Err(e) => Err(e)
        Ok(_) => Ok(())
      }
  }
}

///|
pub fn PaintFill::validate(self : PaintFill) -> Result[Unit, PaintError] {
  match self {
    FloatSolid(c) =>
      match c.validate() {
        Ok(_) => Ok(())
        Err(_) => Err(InvalidColor)
      }
    Gradient(g) => g.validate()
    Slash(p) => p.validate()
  }
}

///|
pub fn PaintFill::sample(
  self : PaintFill,
  point : @primitives.Point,
  bounds : @primitives.Rect,
) -> Result[@primitives.FloatColor, PaintError] {
  match self {
    FloatSolid(c) =>
      match self.validate() {
        Ok(_) => Ok(c)
        Err(e) => Err(e)
      }
    Gradient(g) => g.sample(point, bounds)
    Slash(p) => p.sample(point, bounds)
  }
}

///|
/// Polygon gradients use the tight bounds of the actually rectangle-clipped
/// polygon, matching the pinned path renderer. Quad gradients retain quad bounds.
pub fn PaintShape::normalization_bounds(
  self : PaintShape,
  clips : Array[@primitives.Rect],
) -> @primitives.Rect? {
  match self {
    RoundedQuad(bounds~, ..) => Some(bounds)
    Polygon(p) => {
      let mut points = p.points()
      for clip in clips {
        for edge = 0; edge < 4; edge = edge + 1 {
          points = paint_clip_edge(points, clip, edge)
        }
      }
      paint_points_bounds(points)
    }
  }
}

///|
/// Binary interior coverage only. Antialiasing is a presentation boundary.
pub fn PaintShape::contains(
  self : PaintShape,
  point : @primitives.Point,
) -> Bool {
  match self {
    RoundedQuad(bounds~, radius~) => {
      if !bounds.contains(point) {
        return false
      }
      let cx = if point.x() < bounds.left() + radius {
        bounds.left() + radius
      } else if point.x() > bounds.right() - radius {
        bounds.right() - radius
      } else {
        point.x()
      }
      let cy = if point.y() < bounds.top() + radius {
        bounds.top() + radius
      } else if point.y() > bounds.bottom() - radius {
        bounds.bottom() - radius
      } else {
        point.y()
      }
      if radius == 0.0 {
        return true
      }
      let dx = (point.x() - cx) / radius
      let dy = (point.y() - cy) / radius
      dx * dx + dy * dy <= 1.0
    }
    Polygon(p) => {
      if !p.bounds.contains(point) {
        return false
      }
      let mut sign = 0.0
      for i = 0; i < p.points.length(); i = i + 1 {
        let a = p.points[i]
        let b = p.points[(i + 1) % p.points.length()]
        let cross = paint_orientation(a, b, point, p.bounds)
        if (sign < 0.0 && cross > 0.0) || (sign > 0.0 && cross < 0.0) {
          return false
        }
        if cross != 0.0 {
          sign = cross
        }
      }
      true
    }
  }
}

///|
fn paint_coordinate(v : Double) -> Bool {
  snapshot_finite(v) && v >= -1000000000.0 && v <= 1000000000.0
}

///|
fn paint_copy_points(
  points : Array[@primitives.Point],
) -> Array[@primitives.Point] {
  let result = []
  for p in points {
    result.push(p)
  }
  result
}

///|
fn paint_points_bounds(points : Array[@primitives.Point]) -> @primitives.Rect? {
  if points.length() < 3 {
    return None
  }
  let mut x0 = points[0].x()
  let mut x1 = x0
  let mut y0 = points[0].y()
  let mut y1 = y0
  for p in points {
    x0 = if p.x() < x0 { p.x() } else { x0 }
    x1 = if p.x() > x1 { p.x() } else { x1 }
    y0 = if p.y() < y0 { p.y() } else { y0 }
    y1 = if p.y() > y1 { p.y() } else { y1 }
  }
  if x1 <= x0 || y1 <= y0 {
    return None
  }
  match @primitives.Rect::new(x0, y0, x1 - x0, y1 - y0) {
    Ok(b) => Some(b)
    Err(_) => None
  }
}

///|
fn paint_edge_distance(
  p : @primitives.Point,
  r : @primitives.Rect,
  edge : Int32,
) -> Double {
  match edge {
    0 => p.x() - r.left()
    1 => r.right() - p.x()
    2 => p.y() - r.top()
    _ => r.bottom() - p.y()
  }
}

///|
fn paint_clip_edge(
  points : Array[@primitives.Point],
  r : @primitives.Rect,
  edge : Int32,
) -> Array[@primitives.Point] {
  let result = []
  if points.length() == 0 {
    return result
  }
  let mut a = points[points.length() - 1]
  let mut da = paint_edge_distance(a, r, edge)
  for b in points {
    let db = paint_edge_distance(b, r, edge)
    if (da >= 0.0) != (db >= 0.0) {
      let t = da / (da - db)
      match
        @primitives.Point::new(
          a.x() + (b.x() - a.x()) * t,
          a.y() + (b.y() - a.y()) * t,
        ) {
        Ok(p) => result.push(p)
        Err(_) => ()
      }
    }
    if db >= 0.0 {
      result.push(b)
    }
    a = b
    da = db
  }
  result
}

///|
fn paint_shape_json(shape : PaintShape) -> String {
  match shape {
    RoundedQuad(bounds~, radius~) =>
      "{\"kind\":\"rounded_quad\",\"bounds\":\{snapshot_rect_json(bounds)},\"radius\":\{snapshot_double(radius)}}"
    Polygon(p) => {
      let mut vertices = ""
      for i = 0; i < p.points.length(); i = i + 1 {
        if i > 0 {
          vertices += ","
        }
        vertices += "{\"x\":\{snapshot_double(p.points[i].x())},\"y\":\{snapshot_double(p.points[i].y())}}"
      }
      "{\"kind\":\"convex_polygon\",\"bounds\":\{snapshot_rect_json(p.bounds)},\"points\":[\{vertices}]}"
    }
  }
}

///|
fn paint_float_json(c : @primitives.FloatColor) -> String {
  "{\"red\":\{snapshot_double(c.red())},\"green\":\{snapshot_double(c.green())},\"blue\":\{snapshot_double(c.blue())},\"alpha\":\{snapshot_double(c.alpha())}}"
}

///|
fn paint_fill_json(fill : PaintFill) -> String {
  match fill {
    Slash(p) => "{\"kind\":\"slash_pattern\",\"pattern\":\{p.canonical_json()}}"
    FloatSolid(c) =>
      "{\"kind\":\"float_solid\",\"color\":\{paint_float_json(c)}}"
    Gradient(g) =>
      "{\"kind\":\"linear_gradient\",\"gradient\":\{g.canonical_json()}}"
  }
}

///|
/// Consistently scale each axis by the positive tight extent before evaluating
/// orientation. This supports tiny representable shapes without an epsilon.
/// Unresolved zero determinants are rejected by polygon construction.
fn paint_orientation(
  a : @primitives.Point,
  b : @primitives.Point,
  point : @primitives.Point,
  bounds : @primitives.Rect,
) -> Double {
  let dx = (b.x() - a.x()) / bounds.size().width()
  let dy = (b.y() - a.y()) / bounds.size().height()
  let px = (point.x() - a.x()) / bounds.size().width()
  let py = (point.y() - a.y()) / bounds.size().height()
  dx * py - dy * px
}
