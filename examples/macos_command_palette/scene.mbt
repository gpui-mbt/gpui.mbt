///|
fn mac_palette_color(
  red : Int32,
  green : Int32,
  blue : Int32,
) -> @primitives.Color {
  @primitives.Color::rgba(red, green, blue, 255).unwrap()
}

///|
fn mac_palette_label(
  id : UInt64,
  label : String,
  x : Double,
  y : Double,
  size : Double,
  color : @primitives.Color,
  clip : Int32?,
) -> Result[@scene.SceneItem, @diagnostics.FrameworkError] {
  let document = match @text.TextDocument::new(label) {
    Ok(value) => value
    Err(_) =>
      return Err(mac_palette_error("palette_label", "label text was rejected"))
  }
  let measurement = match @macos_text.measure(document, "sans", size) {
    Ok(value) => value
    Err(_) =>
      return Err(
        mac_palette_error("palette_label", "CoreText rejected a label"),
      )
  }
  let (origin, bounds) = match
    @text_field.scene_text_run_geometry(measurement) {
    Ok(value) => value
    Err(_) =>
      return Err(
        mac_palette_error("palette_label", "label geometry was rejected"),
      )
  }
  let transform = match @scene.AffineTransform::new(1.0, 0.0, 0.0, 1.0, x, y) {
    Ok(value) => value
    Err(_) =>
      return Err(
        mac_palette_error("palette_label", "label transform was rejected"),
      )
  }
  match
    @scene.SceneItem::text_run(
      id, bounds, origin, label, size, color, transform, 1.0, clip,
    ) {
    Ok(value) => Ok(value)
    Err(_) => Err(mac_palette_error("palette_label", "scene rejected a label"))
  }
}

///|
fn MacPaletteSession::scene(
  self : MacPaletteSession,
) -> Result[@scene.SceneSnapshot, @diagnostics.FrameworkError] {
  let viewport = match
    @primitives.Rect::new(0.0, 0.0, self.width, self.height) {
    Ok(value) => value
    Err(_) =>
      return Err(
        mac_palette_error("palette_scene", "invalid viewport geometry"),
      )
  }
  let items : Array[@scene.SceneItem] = []
  let clips : Array[@scene.ClipChain] = []
  items.push(
    @scene.SceneItem::quad(
      1,
      viewport,
      mac_palette_color(24, 28, 36),
      @scene.AffineTransform::identity(),
      1.0,
      None,
    ).unwrap(),
  )
  if !self.palette.is_open() {
    items.push(
      match
        mac_palette_label(
          20,
          "macOS command palette",
          32.0,
          44.0,
          24.0,
          mac_palette_color(238, 242, 248),
          None,
        ) {
        Ok(value) => value
        Err(error) => return Err(error)
      },
    )
    items.push(
      match
        mac_palette_label(
          21,
          "Press Command+K to open",
          32.0,
          92.0,
          16.0,
          mac_palette_color(177, 187, 202),
          None,
        ) {
        Ok(value) => value
        Err(error) => return Err(error)
      },
    )
    items.push(
      match
        mac_palette_label(
          22,
          "Background keys: \{self.background_keys.val}",
          32.0,
          128.0,
          14.0,
          mac_palette_color(177, 187, 202),
          None,
        ) {
        Ok(value) => value
        Err(error) => return Err(error)
      },
    )
  } else {
    let panel = @primitives.Rect::new(28.0, 32.0, 584.0, 416.0).unwrap()
    items.push(
      @scene.SceneItem::quad(
        2,
        panel,
        mac_palette_color(36, 42, 54),
        @scene.AffineTransform::identity(),
        1.0,
        None,
      ).unwrap(),
    )
    items.push(
      match
        mac_palette_label(
          20,
          "Command palette",
          52.0,
          48.0,
          20.0,
          mac_palette_color(238, 242, 248),
          None,
        ) {
        Ok(value) => value
        Err(error) => return Err(error)
      },
    )
    items.push(
      match
        mac_palette_label(
          21,
          "Search (ASCII keys, case-insensitive)",
          52.0,
          72.0,
          13.0,
          mac_palette_color(177, 187, 202),
          None,
        ) {
        Ok(value) => value
        Err(error) => return Err(error)
      },
    )
    let (field_clip, field_items) = match
      self.palette.field().paint_items(100, 7) {
      Ok(value) => value
      Err(_) =>
        return Err(
          mac_palette_error("palette_scene", "search field paint failed"),
        )
    }
    clips.push(field_clip)
    for item in field_items {
      items.push(item)
    }
    let picker = self.palette.picker()
    let list_bounds = @primitives.Rect::new(52.0, 140.0, 536.0, 288.0).unwrap()
    let (list_clip, rows) = match
      picker.paint_items(200, 8, list_bounds, 36.0, (
        id,
        command,
        position,
        clip,
      ) => {
        let color = if command.is_enabled() {
          mac_palette_color(238, 242, 248)
        } else {
          mac_palette_color(128, 136, 150)
        }
        mac_palette_label(
          id,
          command.label(),
          position.x(),
          position.y(),
          15.0,
          color,
          Some(clip),
        ).map_err(_ => @command_palette.InvalidField)
      }) {
      Ok(value) => value
      Err(_) =>
        return Err(
          mac_palette_error(
            "palette_scene", "command rows could not be painted",
          ),
        )
    }
    clips.push(list_clip)
    for item in rows {
      items.push(item)
    }
    if picker.match_count() == 0 {
      items.push(
        match
          mac_palette_label(
            220,
            "no matching commands",
            60.0,
            150.0,
            15.0,
            mac_palette_color(177, 187, 202),
            Some(8),
          ) {
          Ok(value) => value
          Err(error) => return Err(error)
        },
      )
    }
    items.push(
      match
        mac_palette_label(
          230,
          "Type ASCII to filter  |  Up/Down select  |  Enter run  |  Esc close",
          52.0,
          432.0,
          12.0,
          mac_palette_color(177, 187, 202),
          None,
        ) {
        Ok(value) => value
        Err(error) => return Err(error)
      },
    )
    items.push(
      match
        mac_palette_label(
          231,
          "Actions: \{self.actions.val}  Background keys: \{self.background_keys.val}",
          52.0,
          448.0,
          12.0,
          mac_palette_color(177, 187, 202),
          None,
        ) {
        Ok(value) => value
        Err(error) => return Err(error)
      },
    )
  }
  match @scene.SceneSnapshot::new(viewport, self.scale, [], clips, items) {
    Ok(value) => Ok(value)
    Err(_) =>
      Err(mac_palette_error("palette_scene", "scene snapshot was rejected"))
  }
}
