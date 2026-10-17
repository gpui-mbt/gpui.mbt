///|
/// Resolve a paint against this frame's actual prepainted geometry. The binding
/// replaces only that node's background, preserving the established traversal,
/// deferred order, descendant clips, and hit tree. Resolution is atomic.
pub struct ElementPaintBinding {
  id : UInt64
  priv resolve : (@primitives.Rect) -> Result[
    (@scene.PaintShape, @scene.PaintFill, Double),
    @scene.PaintError,
  ]
}

///|
pub fn ElementPaintBinding::new(
  id : UInt64,
  resolve : (@primitives.Rect) -> Result[
    (@scene.PaintShape, @scene.PaintFill, Double),
    @scene.PaintError,
  ],
) -> ElementPaintBinding {
  { id, resolve, }
}

///|
pub fn ElementPaintBinding::id(self : ElementPaintBinding) -> UInt64 {
  self.id
}

///|
pub fn ElementTree::to_scene_with_paints(
  self : ElementTree,
  bindings : Array[ElementPaintBinding],
) -> Result[@scene.Scene, ElementError] {
  // Validate every identity before invoking any resolver.
  for i = 0; i < bindings.length(); i = i + 1 {
    if self.node(bindings[i].id) is None {
      return Err(UnknownElement)
    }
    for j = 0; j < i; j = j + 1 {
      if bindings[i].id == bindings[j].id {
        return Err(DuplicatePaintBinding)
      }
    }
  }
  let commands : Array[@scene.PaintCommand] = []
  for binding in bindings {
    match self.node(binding.id) {
      None => return Err(UnknownElement)
      Some(node) =>
        match (binding.resolve)(node.bounds) {
          Err(e) => return Err(PaintFailure(e))
          Ok((shape, fill, opacity)) =>
            match @scene.PaintCommand::paint(binding.id, shape, fill, opacity) {
              Err(e) => return Err(PaintFailure(e))
              Ok(command) => commands.push(command)
            }
        }
    }
  }
  Ok(self.paint_bound_commands(commands))
}

///|
pub fn Prepainted::paint_with_paints(
  self : Prepainted,
  bindings : Array[ElementPaintBinding],
) -> Result[@scene.Scene, ElementError] {
  self.tree.to_scene_with_paints(bindings)
}
