///|
/// Bounded metadata for an externally decoded image. The SHA-256 identity names
/// immutable encoded bytes; hosts verify those bytes and prepare frames before
/// presentation. No URL, decoder, mutable pixel buffer or native handle is held.
pub struct ImageData {
  content_identity : String
  pixel_width : Int32
  pixel_height : Int32
  frame_count : Int32
} derive(Eq)

///|
pub extend ImageData with Eq::{not_equal, equal}

///|
pub(all) enum ImageError {
  InvalidIdentity
  InvalidDimensions
  InvalidFrame
  MissingResource
  DuplicateResource
  ConflictingResource
  InvalidGeometry
  InvalidOpacity
} derive(Eq)

///|
pub extend ImageError with Eq::{not_equal, equal}

///|
/// Prepared frames have uniform dimensions. At most 256 frames and 16,777,216
/// total prepared pixels; dimensions are 1..16,384. Hosts may support less.
pub fn ImageData::new(
  content_identity : String,
  pixel_width : Int32,
  pixel_height : Int32,
  frame_count : Int32,
) -> Result[ImageData, ImageError] {
  if content_identity.length() != 64 {
    return Err(InvalidIdentity)
  }
  for i = 0; i < content_identity.length(); i = i + 1 {
    let c = content_identity[i].to_int()
    if !((c >= 48 && c <= 57) || (c >= 97 && c <= 102)) {
      return Err(InvalidIdentity)
    }
  }
  if pixel_width < 1 ||
    pixel_width > 16384 ||
    pixel_height < 1 ||
    pixel_height > 16384 ||
    frame_count < 1 ||
    frame_count > 256 ||
    pixel_width.to_double() * pixel_height.to_double() * frame_count.to_double() >
    16777216.0 {
    return Err(InvalidDimensions)
  }
  Ok({ content_identity, pixel_width, pixel_height, frame_count, })
}

///|
pub fn ImageData::content_identity(self : ImageData) -> String {
  self.content_identity
}

///|
pub fn ImageData::pixel_width(self : ImageData) -> Int32 {
  self.pixel_width
}

///|
pub fn ImageData::pixel_height(self : ImageData) -> Int32 {
  self.pixel_height
}

///|
pub fn ImageData::frame_count(self : ImageData) -> Int32 {
  self.frame_count
}

///|
pub fn SceneResource::image(id : UInt64, data : ImageData) -> SceneResource {
  { id, image: Some(data), }
}

///|
pub fn SceneResource::image_data(self : SceneResource) -> ImageData? {
  self.image
}

///|
pub(all) enum ImageFit {
  Contain
  Cover
  Fill
} derive(Eq)

///|
pub extend ImageFit with Eq::{not_equal, equal}

///|
/// Center the intrinsic aspect ratio in the actual element bounds. Cover keeps
/// full sprite bounds; image_bounds remains the element crop in the command.
pub fn ImageData::fit_bounds(
  self : ImageData,
  bounds : @primitives.Rect,
  fit : ImageFit,
) -> Result[@primitives.Rect, ImageError] {
  match validate_image_rect(bounds) {
    Err(e) => return Err(e)
    Ok(_) => ()
  }
  if fit == Fill {
    return Ok(bounds)
  }
  let width = bounds.size().width()
  let height = bounds.size().height()
  if width == 0.0 || height == 0.0 {
    return match @primitives.Rect::new(bounds.left(), bounds.top(), 0, 0) {
      Ok(r) => Ok(r)
      Err(_) => Err(InvalidGeometry)
    }
  }
  let sx = width / self.pixel_width.to_double()
  let sy = height / self.pixel_height.to_double()
  let scale = match fit {
    Contain => if sx < sy { sx } else { sy }
    Cover => if sx > sy { sx } else { sy }
    Fill => 1.0
  }
  let w = self.pixel_width.to_double() * scale
  let h = self.pixel_height.to_double() * scale
  match
    @primitives.Rect::new(
      bounds.left() + (width - w) / 2.0,
      bounds.top() + (height - h) / 2.0,
      w,
      h,
    ) {
    Err(_) => Err(InvalidGeometry)
    Ok(rect) =>
      match validate_image_rect(rect) {
        Err(e) => Err(e)
        Ok(_) => Ok(rect)
      }
  }
}

///|
fn validate_image_rect(rect : @primitives.Rect) -> Result[Unit, ImageError] {
  if !snapshot_finite(rect.left()) ||
    !snapshot_finite(rect.top()) ||
    !snapshot_finite(rect.right()) ||
    !snapshot_finite(rect.bottom()) ||
    !snapshot_finite(rect.size().width()) ||
    !snapshot_finite(rect.size().height()) ||
    rect.size().width() < 0.0 ||
    rect.size().height() < 0.0 {
    Err(InvalidGeometry)
  } else {
    Ok(())
  }
}

///|
fn validate_image_geometry(
  bounds : @primitives.Rect,
  image_bounds : @primitives.Rect,
  opacity : Double,
) -> Result[Unit, ImageError] {
  if !snapshot_finite(opacity) || opacity < 0.0 || opacity > 1.0 {
    return Err(InvalidOpacity)
  }
  match validate_image_rect(bounds) {
    Err(e) => return Err(e)
    Ok(_) => ()
  }
  validate_image_rect(image_bounds)
}

///|
fn validate_image_selection(
  resource : SceneResource,
  frame_index : Int32,
) -> Result[Unit, ImageError] {
  match resource.image {
    None => Err(MissingResource)
    Some(data) => {
      match
        ImageData::new(
          data.content_identity,
          data.pixel_width,
          data.pixel_height,
          data.frame_count,
        ) {
        Err(e) => return Err(e)
        Ok(_) => ()
      }
      if frame_index < 0 || frame_index >= data.frame_count {
        Err(InvalidFrame)
      } else {
        Ok(())
      }
    }
  }
}

///|
pub fn PaintCommand::image(
  id : UInt64,
  resource : SceneResource,
  frame_index : Int32,
  bounds : @primitives.Rect,
  image_bounds : @primitives.Rect,
  opacity : Double,
) -> Result[PaintCommand, ImageError] {
  match validate_image_selection(resource, frame_index) {
    Err(e) => return Err(e)
    Ok(_) => ()
  }
  match validate_image_geometry(bounds, image_bounds, opacity) {
    Err(e) => return Err(e)
    Ok(_) => ()
  }
  Ok(
    ImageCommand(id~, resource~, frame_index~, bounds~, image_bounds~, opacity~),
  )
}

///|
/// The resource reference and prepared frame are checked by SceneSnapshot::new.
pub fn SceneItem::image(
  id : UInt64,
  resource_id : UInt64,
  frame_index : Int32,
  bounds : @primitives.Rect,
  image_bounds : @primitives.Rect,
  transform : AffineTransform,
  opacity : Double,
  clip_chain_id : Int32?,
) -> Result[SceneItem, SnapshotError] {
  if frame_index < 0 {
    return Err(InvalidImage(InvalidFrame))
  }
  match validate_image_geometry(bounds, image_bounds, opacity) {
    Err(e) => return Err(InvalidImage(e))
    Ok(_) => ()
  }
  if !snapshot_transform_finite(transform) {
    return Err(NonFiniteTransform)
  }
  Ok(
    ImageItem(
      id~,
      resource_id~,
      frame_index~,
      bounds~,
      image_bounds~,
      transform~,
      opacity~,
      clip_chain_id~,
    ),
  )
}

///|
fn image_resource_present(
  id : UInt64,
  resources : Array[SceneResource],
) -> Bool {
  for resource in resources {
    if resource.id == id {
      return true
    }
  }
  false
}

///|
fn validate_image_resources(
  resources : Array[SceneResource],
  items : Array[SceneItem],
) -> Result[Unit, ImageError] {
  let mut has_images = false
  for resource in resources {
    if resource.image is Some(_) {
      has_images = true
    }
  }
  for item in items {
    if item is ImageItem(..) {
      has_images = true
    }
  }
  // Preserve legacy id-only resource tables. Image tables require unique IDs.
  if !has_images {
    return Ok(())
  }
  for i = 0; i < resources.length(); i = i + 1 {
    if resources[i].image is Some(_) {
      match validate_image_selection(resources[i], 0) {
        Err(e) => return Err(e)
        Ok(_) => ()
      }
    }
    for j = 0; j < i; j = j + 1 {
      if resources[i].id == resources[j].id {
        return Err(DuplicateResource)
      }
      if image_resources_conflict(resources[i], resources[j]) {
        return Err(ConflictingResource)
      }
    }
  }
  for item in items {
    match item {
      ImageItem(resource_id~, frame_index~, ..) => {
        let mut found = false
        for resource in resources {
          if resource.id == resource_id {
            found = true
            match validate_image_selection(resource, frame_index) {
              Err(e) => return Err(e)
              Ok(_) => ()
            }
          }
        }
        if !found {
          return Err(MissingResource)
        }
      }
      _ => ()
    }
  }
  Ok(())
}

///|
fn validate_image_commands(
  commands : Array[PaintCommand],
) -> Result[Unit, ImageError] {
  let resources : Array[SceneResource] = []
  for command in commands {
    match command {
      ImageCommand(
        resource~,
        frame_index~,
        bounds~,
        image_bounds~,
        opacity~,
        ..
      ) => {
        match validate_image_selection(resource, frame_index) {
          Err(e) => return Err(e)
          Ok(_) => ()
        }
        match validate_image_geometry(bounds, image_bounds, opacity) {
          Err(e) => return Err(e)
          Ok(_) => ()
        }
        for previous in resources {
          if image_resources_conflict(previous, resource) {
            return Err(ConflictingResource)
          }
        }
        if !image_resource_present(resource.id, resources) {
          resources.push(resource)
        }
      }
      _ => ()
    }
  }
  Ok(())
}

///|
fn image_resource_json(resource : SceneResource) -> String {
  match resource.image {
    None => "{\"id\":\{resource.id}}"
    Some(data) =>
      "{\"id\":\{resource.id},\"kind\":\"image\",\"content_identity\":\{snapshot_text_json(data.content_identity)},\"pixel_width\":\{data.pixel_width},\"pixel_height\":\{data.pixel_height},\"frame_count\":\{data.frame_count}}"
  }
}

///|
fn image_resources_conflict(
  left : SceneResource,
  right : SceneResource,
) -> Bool {
  if left.id == right.id && left != right {
    return true
  }
  match (left.image, right.image) {
    (Some(a), Some(b)) => a.content_identity == b.content_identity && a != b
    _ => false
  }
}
