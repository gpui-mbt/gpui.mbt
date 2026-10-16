///|
struct Child {
  basis : Double
  grow : Double
  shrink : Double
  minimum : Double
  maximum : Double?
} derive(Eq, ToJson)

///|
pub extend Child with Eq::{equal, not_equal}

///|
pub extend Child with ToJson::{to_json}

///|
struct Config {
  extent : Double
  cross : Double
  column : Bool
  gap : Double
  wrap : Int32
  justify : Int32
  children : Array[Child]
} derive(Eq, ToJson)

///|
pub extend Config with Eq::{equal, not_equal}

///|
pub extend Config with ToJson::{to_json}

///|
priv struct Preset {
  id : String
  config : Config
  upstream : Array[Array[Double]]
  before : Array[Array[Double]]
}

///|
priv struct ProjectedPreset {
  id : String
  config : Config
  projection : Int32
  recorded : Array[Double]
  document : String
}

///|
pub struct Playground {
  mut config : Config
  mut selected : Int32
}

///|
pub fn Playground::new() -> Playground {
  { config: presets[0].config, selected: 0, }
}

///|
pub fn Playground::select(self : Playground, index : Int32) -> Bool {
  if index < 0 || index >= presets.length() + projected_presets.length() {
    return false
  }
  if index < presets.length() {
    self.config = presets[index].config
  } else {
    self.config = projected_presets[index - presets.length()].config
  }
  self.selected = index
  true
}

///|
fn bounded(value : Double, maximum : Double) -> Bool {
  value == value && value >= 0.0 && value <= maximum
}

///|
pub fn Playground::change(
  self : Playground,
  field : String,
  index : Int32,
  value : Double,
) -> Bool {
  let config = self.config
  let next = match field {
    "extent" if bounded(value, 200.0) && value >= 20.0 =>
      { ..config, extent: value, }
    "cross" if bounded(value, 100.0) && value >= 10.0 =>
      { ..config, cross: value, }
    "gap" if bounded(value, 40.0) => { ..config, gap: value, }
    "wrap" if value == 0.0 || value == 1.0 || value == 2.0 =>
      { ..config, wrap: value.to_int(), }
    "direction" if value == 0.0 || value == 1.0 =>
      { ..config, column: value == 1.0, }
    "justify" if value == 0.0 || value == 1.0 || value == 2.0 || value == 3.0 =>
      { ..config, justify: value.to_int(), }
    "basis" | "grow" | "shrink" | "minimum" | "maximum" if index >= 0 &&
      index < 2 => {
      let child = config.children[index]
      let next = match field {
        "basis" if bounded(value, 200.0) => { ..child, basis: value, }
        "grow" if bounded(value, 4.0) => { ..child, grow: value, }
        "shrink" if bounded(value, 4.0) => { ..child, shrink: value, }
        "minimum" if bounded(value, 200.0) => { ..child, minimum: value, }
        "maximum" if value == -1.0 => { ..child, maximum: None, }
        "maximum" if bounded(value, 200.0) => { ..child, maximum: Some(value), }
        _ => return false
      }
      if next.maximum is Some(maximum) && maximum < next.minimum {
        return false
      }
      let children = config.children.copy()
      children[index] = next
      { ..config, children, }
    }
    _ => return false
  }
  self.config = next
  true
}

///|
fn size(width : Double, height : Double) -> @primitives.Size {
  match @primitives.Size::new(width, height) {
    Ok(size) => size
    Err(_) => abort("playground dimensions are bounded at ingress")
  }
}

///|
fn points(value : Double) -> @layout.Dimension {
  match @layout.Dimension::points(value) {
    Ok(value) => value
    Err(_) => abort("playground dimensions are bounded at ingress")
  }
}

///|
fn resolve(config : Config) -> @layout.FlexLayout {
  let direction = if config.column {
    @layout.FlowDirection::column()
  } else {
    @layout.FlowDirection::row()
  }
  let container = @layout.FlexContainer::new(
    direction,
    if config.column {
      size(config.cross, config.extent)
    } else {
      size(config.extent, config.cross)
    },
  )
    .with_wrap(match config.wrap {
      1 => @layout.FlexWrap::wrap()
      2 => @layout.FlexWrap::wrap_reverse()
      _ => @layout.FlexWrap::no_wrap()
    })
    .with_justify(match config.justify {
      1 => @layout.JustifyContent::center()
      2 => @layout.JustifyContent::end()
      3 => @layout.JustifyContent::space_between()
      _ => @layout.JustifyContent::start()
    },
  )
  let container = match container.with_gap(config.gap) {
    Ok(value) => value
    Err(_) => abort("playground gap is bounded at ingress")
  }
  let items : Array[@layout.FlexItem] = []
  for i, child in config.children {
    let item = @layout.FlexItem::new(
      (i + 2).to_uint64(),
      points(child.basis),
      points(10.0),
      if config.column {
        size(10.0, child.basis)
      } else {
        size(child.basis, 10.0)
      },
    )
    let item = match item.with_flex(child.grow, child.shrink) {
      Ok(value) => value
      Err(_) => abort("playground factors are bounded at ingress")
    }
    let item = match item.with_main_limits(child.minimum, child.maximum) {
      Ok(value) => value
      Err(_) => abort("playground limits are validated atomically")
    }
    items.push(item)
  }
  match @layout.layout_flex(container, items) {
    Ok(value) => value
    Err(_) => abort("bounded two-child playground layout must resolve")
  }
}

///|
fn rectangle(rect : @primitives.Rect) -> Array[Double] {
  [rect.left(), rect.top(), rect.size().width(), rect.size().height()]
}

///|
fn bounds(layout : @layout.FlexLayout) -> Array[Array[Double]] {
  let result = [rectangle(layout.content_bounds())]
  for item in layout.items() {
    result.push(rectangle(item.bounds()))
  }
  result
}

///|
fn delta(left : Array[Array[Double]], right : Array[Array[Double]]) -> Double {
  let mut maximum = 0.0
  for i, row in left {
    for j, value in row {
      let diff = (value - right[i][j]).abs()
      if diff > maximum {
        maximum = diff
      }
    }
  }
  maximum
}

///|
fn projected_origins(
  rectangles : Array[Array[Double]],
  column : Bool,
  projection : Int32,
) -> Array[Double] {
  let dimension = if (projection == 0 && column) ||
    (projection == 1 && !column) {
    1
  } else {
    0
  }
  [rectangles[1][dimension], rectangles[2][dimension]]
}

///|
fn origin_delta(left : Array[Double], right : Array[Double]) -> Double {
  let mut maximum = 0.0
  for i, value in left {
    let diff = (value - right[i]).abs()
    if diff > maximum {
      maximum = diff
    }
  }
  maximum
}

///|
pub fn Playground::snapshot(self : Playground) -> String {
  if self.selected >= presets.length() {
    let record = projected_presets[self.selected - presets.length()]
    let layout = resolve(self.config)
    let live = bounds(layout)
    let origins = projected_origins(live, self.config.column, record.projection)
    let comparison = if self.config == record.config {
      let difference = origin_delta(origins, record.recorded)
      "{\"status\":\{Json(if difference <= 0.0001 { "match" } else { "mismatch" }).stringify()},\"maxDelta\":\{difference}}"
    } else {
      "{\"status\":\"unmeasured\",\"maxDelta\":null}"
    }
    let projection = if record.projection == 0 {
      "main-origins"
    } else {
      "line-origins"
    }
    return "{\"config\":\{Json(self.config).stringify()},\"selected\":\{self.selected},\"id\":\{Json(record.id).stringify()},\"bounds\":\{Json(live).stringify()},\"overflow\":\{layout.overflow()},\"comparison\":\{comparison},\"recordedConfig\":\{Json(record.config).stringify()},\"upstream\":null,\"before\":null,\"projection\":\{Json(projection).stringify()},\"recordedOrigins\":\{Json(record.recorded).stringify()},\"liveOrigins\":\{Json(origins).stringify()},\"recordSource\":\{Json(record.document).stringify()}}"
  }
  let preset = presets[self.selected]
  let layout = resolve(self.config)
  let live = bounds(layout)
  let eligible = self.config == preset.config
  let comparison = if eligible {
    let difference = delta(live, preset.upstream)
    "{\"status\":\{Json(if difference <= 0.0001 { "match" } else { "mismatch" }).stringify()},\"maxDelta\":\{difference}}"
  } else {
    "{\"status\":\"unmeasured\",\"maxDelta\":null}"
  }
  "{\"config\":\{Json(self.config).stringify()},\"selected\":\{self.selected},\"id\":\{Json(preset.id).stringify()},\"bounds\":\{Json(live).stringify()},\"overflow\":\{layout.overflow()},\"comparison\":\{comparison},\"recordedConfig\":\{Json(preset.config).stringify()},\"upstream\":\{Json(preset.upstream).stringify()},\"before\":\{Json(preset.before).stringify()},\"projection\":\"bounds\",\"recordedOrigins\":null,\"liveOrigins\":null,\"recordSource\":null}"
}

///|
///|
pub fn preset_ids() -> String {
  let ids = presets.map(preset => preset.id)
  for record in projected_presets {
    ids.push(record.id)
  }
  Json(ids).stringify()
}
