///|
/// Bind an immutable resource reference to actual prepainted element geometry.
/// Replaces this node's background, retaining traversal, clips and hit behavior.
pub struct ElementImageBinding {
  id : UInt64
  priv resource : @scene.SceneResource
  priv frame_index : Int32
  priv fit : @scene.ImageFit
  priv opacity : Double
}

///|
pub fn ElementImageBinding::new(
  id : UInt64,
  resource : @scene.SceneResource,
  frame_index : Int32,
  fit : @scene.ImageFit,
  opacity : Double,
) -> Result[ElementImageBinding, @scene.ImageError] {
  let empty = @primitives.Rect::new(0, 0, 0, 0).unwrap()
  match
    @scene.PaintCommand::image(id, resource, frame_index, empty, empty, opacity) {
    Err(e) => Err(e)
    Ok(_) => Ok({ id, resource, frame_index, fit, opacity, })
  }
}

///|
pub fn ElementImageBinding::id(self : ElementImageBinding) -> UInt64 {
  self.id
}

///|
pub fn ElementTree::to_scene_with_images(
  self : ElementTree,
  bindings : Array[ElementImageBinding],
) -> Result[@scene.Scene, ElementError] {
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
    let node = self.node(binding.id).unwrap()
    let data = match binding.resource.image_data() {
      None => return Err(ImageFailure(MissingResource))
      Some(data) => data
    }
    let bounds = match data.fit_bounds(node.bounds, binding.fit) {
      Err(e) => return Err(ImageFailure(e))
      Ok(bounds) => bounds
    }
    match
      @scene.PaintCommand::image(
        binding.id,
        binding.resource,
        binding.frame_index,
        bounds,
        node.bounds,
        binding.opacity,
      ) {
      Err(e) => return Err(ImageFailure(e))
      Ok(command) => commands.push(command)
    }
  }
  let scene = self.paint_bound_commands(commands)
  match scene.validate() {
    Err(@scene.SceneError::InvalidImage(e)) => Err(ImageFailure(e))
    Err(_) => Err(GeometryFailure)
    Ok(_) => Ok(scene)
  }
}

///|
pub fn Prepainted::paint_with_images(
  self : Prepainted,
  bindings : Array[ElementImageBinding],
) -> Result[@scene.Scene, ElementError] {
  self.tree.to_scene_with_images(bindings)
}
