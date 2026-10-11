///|
const MAC_PALETTE_FONT_SIZE : Double = 18.0

///|
const MAC_PALETTE_WIDTH : Double = 640.0

///|
const MAC_PALETTE_HEIGHT : Double = 480.0

///|
fn mac_palette_error(
  operation : String,
  message : String,
) -> @diagnostics.FrameworkError {
  @diagnostics.FrameworkError::new(
    @diagnostics.NativeFailure,
    operation,
    subsystem="macos-command-palette",
    backend="appkit-metal",
    message~,
  )
}

///|
/// The native sample owns only its window, command bindings, and focus tree.
/// Query/navigation/close semantics remain in the shared portable palette.
struct MacPaletteSession {
  palette : @command_palette.CommandPalette
  tree : Ref[@element.ElementTree]
  actions : Ref[Int]
  last_action : Ref[String]
  background_keys : Ref[Int]
  mut width : Double
  mut height : Double
  mut scale : Double
}

///|
fn mac_palette_measure(
  document : @text.TextDocument,
) -> Result[@text_layout.TextMeasurement, @text_field.TextFieldError] {
  match @macos_text.measure(document, "sans", MAC_PALETTE_FONT_SIZE) {
    Ok(value) => Ok(value)
    Err(_) => Err(@text_field.MeasurementFailed)
  }
}

///|
fn mac_palette_admit(
  document : @text.TextDocument,
  measurement : @text_layout.TextMeasurement,
) -> Result[Unit, @text_field.TextFieldError] {
  if measurement.document() != document {
    return Err(@text_field.AdmissionFailed)
  }
  match @text_field.scene_text_run_geometry(measurement) {
    Ok(_) => Ok(())
    Err(_) => Err(@text_field.UnsupportedLayout)
  }
}

///|
fn mac_palette_hit(
  document : @text.TextDocument,
  point : @primitives.Point,
) -> Result[@text_layout.TextHit, @text_field.TextFieldError] {
  let measurement = match mac_palette_measure(document) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let carets = measurement.carets()
  if carets.length() == 0 {
    return Err(@text_field.HitTestFailed)
  }
  let mut nearest_offset = carets[0].utf16_offset()
  let mut nearest_x = carets[0].strong().left()
  let mut nearest_distance = if nearest_x >= point.x() {
    nearest_x - point.x()
  } else {
    point.x() - nearest_x
  }
  for caret in carets {
    if caret.is_cursor_position() {
      let x = caret.strong().left()
      let distance = if x >= point.x() { x - point.x() } else { point.x() - x }
      if distance < nearest_distance {
        nearest_offset = caret.utf16_offset()
        nearest_x = x
        nearest_distance = distance
      }
    }
  }
  ignore(nearest_x)
  ignore(nearest_distance)
  match
    @text_layout.TextHit::new(
      document, nearest_offset, 0, nearest_offset, true, true,
    ) {
    Ok(value) => Ok(value)
    Err(_) => Err(@text_field.HitTestFailed)
  }
}

///|
fn mac_palette_binding(
  id : String,
  label : String,
  actions : Ref[Int],
  last_action : Ref[String],
) -> @capability.GuiBinding[Unit, Unit] {
  let descriptor = @capability.Descriptor::new(
    id,
    label,
    "macOS command palette sample",
    @capability.Command,
    @capability.Schema::unit(),
    @capability.Schema::unit(),
    @capability.StateChange,
    false,
    @capability.Local,
    None,
    1,
  ).unwrap()
  @capability.TypedCapability::new(
    descriptor,
    _ => Ok(()),
    _ => Ok(@capability.Value::unit()),
    _ => {
      actions.val += 1
      last_action.val = id
      Ok(())
    },
    () => Ok(()),
    _ => Ok(()),
  ).gui_binding()
}

///|
fn mac_palette_commands(
  actions : Ref[Int],
  last_action : Ref[String],
) -> Array[@command_palette.PaletteCommand] {
  let values = [
    ("palette.open_settings", "open settings", true),
    ("palette.save_file", "save file", false),
    ("palette.toggle_sidebar", "toggle sidebar", true),
    ("palette.search_files", "search files", true),
    ("palette.switch_theme", "switch theme", true),
    ("palette.show_diagnostics", "show diagnostics", true),
    ("palette.new_window", "new window", true),
    ("palette.close_window", "close window", true),
    ("palette.increase_zoom", "increase zoom", true),
    ("palette.decrease_zoom", "decrease zoom", true),
    ("palette.open_recent", "open recent project", true),
    ("palette.toggle_terminal", "toggle terminal", true),
    ("palette.toggle_sidebar_again", "toggle sidebar panel", true),
  ]
  let commands : Array[@command_palette.PaletteCommand] = []
  for (id, label, enabled) in values {
    let metadata = @command_palette.CommandMetadata::new(id, label, enabled).unwrap()
    commands.push(
      @command_palette.PaletteCommand::new(
        metadata,
        mac_palette_binding(id, label, actions, last_action),
      ),
    )
  }
  commands
}

///|
fn MacPaletteSession::new(
  width : Double,
  height : Double,
  scale : Double,
) -> Result[MacPaletteSession, @diagnostics.FrameworkError] {
  if width.is_nan() ||
    width.is_inf() ||
    width <= 0.0 ||
    height.is_nan() ||
    height.is_inf() ||
    height <= 0.0 ||
    scale.is_nan() ||
    scale.is_inf() ||
    scale <= 0.0 {
    return Err(mac_palette_error("palette_metrics", "invalid window metrics"))
  }
  let field_bounds = @primitives.Rect::new(52.0, 88.0, 536.0, 40.0).unwrap()
  let document = match @text.TextDocument::new("") {
    Ok(value) => value
    Err(_) =>
      return Err(
        mac_palette_error("palette_field", "empty search document was rejected"),
      )
  }
  let field = match
    @text_field.TextField::new(
      2,
      field_bounds,
      MAC_PALETTE_FONT_SIZE,
      document,
      mac_palette_measure,
      mac_palette_admit,
    ) {
    Ok(value) => value
    Err(_) =>
      return Err(
        mac_palette_error("palette_field", "CoreText rejected the search field"),
      )
  }
  let viewport = @primitives.Rect::new(0.0, 0.0, width, height).unwrap()
  let tree = match
    @element.ElementTree::new([
      @element.ElementNode::new(1, None, viewport),
      @element.ElementNode::new(9, Some(1), viewport).with_focusable(true),
      field.element_node(Some(1)),
    ]) {
    Ok(value) => Ref(value.with_focus(9).unwrap())
    Err(_) =>
      return Err(
        mac_palette_error("palette_focus", "could not create the focus tree"),
      )
  }
  let actions = Ref(0)
  let last_action = Ref("")
  let palette = match
    @command_palette.CommandPalette::new(
      field,
      mac_palette_commands(actions, last_action),
    ) {
    Ok(value) => value
    Err(_) =>
      return Err(
        mac_palette_error(
          "palette_model", "shared palette rejected sample data",
        ),
      )
  }
  Ok({
    palette,
    tree,
    actions,
    last_action,
    background_keys: Ref(0),
    width,
    height,
    scale,
  })
}

///|
fn MacPaletteSession::is_open(self : MacPaletteSession) -> Bool {
  self.palette.is_open()
}

///|
fn MacPaletteSession::epoch(self : MacPaletteSession) -> Int {
  self.palette.open_epoch()
}

///|
/// Command+K is the sample's only native opener. Plain key events provide
/// lowercased ASCII query characters; the native host does not create TextInput.
fn mac_palette_is_opener(input : @primitives.InputEvent) -> Bool {
  match input {
    @primitives.KeyPressed(
      key=@primitives.Character(letter),
      modifiers~,
      repeat=false
    ) =>
      (letter == "k" || letter == "K") &&
      modifiers.meta() &&
      !modifiers.control() &&
      !modifiers.shift() &&
      !modifiers.alt()
    _ => false
  }
}

///|
fn mac_palette_is_opener_release(input : @primitives.InputEvent) -> Bool {
  match input {
    @primitives.KeyReleased(key=@primitives.Character(letter), modifiers~) =>
      (letter == "k" || letter == "K") &&
      modifiers.meta() &&
      !modifiers.control() &&
      !modifiers.shift() &&
      !modifiers.alt()
    _ => false
  }
}

///|
fn mac_palette_printable_ascii(text : String) -> Bool {
  let bytes = @utf8.encode(text)
  bytes.length() == 1 && bytes[0].to_int() >= 0x21 && bytes[0].to_int() <= 0x7e
}

///|
fn mac_palette_plain_key_text(input : @primitives.InputEvent) -> String? {
  match input {
    @primitives.KeyPressed(
      key=@primitives.Character(value),
      modifiers~,
      repeat=_
    ) if !modifiers.control() && !modifiers.meta() && !modifiers.alt() =>
      if mac_palette_printable_ascii(value) {
        Some(value.to_lower())
      } else {
        None
      }
    @primitives.KeyPressed(key=@primitives.Space, modifiers~, repeat=_) if !modifiers.control() &&
      !modifiers.meta() &&
      !modifiers.alt() => Some(" ")
    _ => None
  }
}

///|
/// Route one app-owned input. The palette consumes all events while open and
/// its shared controller owns focus restoration and one-shot activation.
fn MacPaletteSession::handle_input(
  self : MacPaletteSession,
  input : @primitives.InputEvent,
) -> Result[Bool, @diagnostics.FrameworkError] {
  if !self.palette.is_open() {
    let palette_result = match
      self.palette.handle_input(
        input, mac_palette_measure, mac_palette_admit, mac_palette_hit,
      ) {
      Ok(value) => value
      Err(_) =>
        return Err(
          mac_palette_error(
            "palette_closed_input", "shared palette rejected a closed-state event",
          ),
        )
    }
    if palette_result.consumed {
      return Ok(true)
    }
    if mac_palette_is_opener_release(input) {
      return Ok(true)
    }
    if mac_palette_is_opener(input) {
      match self.palette.open(self.tree) {
        Ok(_) => return Ok(true)
        Err(_) =>
          return Err(
            mac_palette_error("palette_open", "shared palette refused to open"),
          )
      }
    }
    match input {
      @primitives.KeyPressed(..) | @primitives.KeyReleased(..) =>
        self.background_keys.val += 1
      _ => ()
    }
    return Ok(false)
  }
  match input {
    @primitives.KeyPressed(key=@primitives.Character(_), modifiers~, ..) if modifiers.control() ||
      modifiers.meta() ||
      modifiers.alt() => return Ok(true)
    _ => ()
  }
  let event = match mac_palette_plain_key_text(input) {
    Some(text) => @primitives.TextInput(text~)
    None => input
  }
  let handled = match
    self.palette.handle_input(
      event, mac_palette_measure, mac_palette_admit, mac_palette_hit,
    ) {
    Ok(value) => value
    Err(_) =>
      return Err(
        mac_palette_error(
          "palette_input", "shared palette rejected a native key event",
        ),
      )
  }
  match handled.effect {
    @command_palette.Closed(epoch~, command_id=_) =>
      match self.palette.finish_close(epoch, self.tree) {
        Ok(_) => ()
        Err(_) =>
          return Err(
            mac_palette_error(
              "palette_finish_close", "shared palette could not finish a close",
            ),
          )
      }
    _ => ()
  }
  Ok(handled.consumed)
}

///|
fn MacPaletteSession::blur(
  self : MacPaletteSession,
) -> Result[Unit, @diagnostics.FrameworkError] {
  let effect = match self.palette.blur() {
    Ok(value) => value
    Err(_) =>
      return Err(
        mac_palette_error("palette_blur", "shared palette could not blur"),
      )
  }
  match effect {
    @command_palette.Closed(epoch~, command_id=_) =>
      match self.palette.finish_close(epoch, self.tree) {
        Ok(_) => Ok(())
        Err(_) =>
          Err(
            mac_palette_error(
              "palette_blur_close", "shared palette could not finish blur",
            ),
          )
      }
    _ => Ok(())
  }
}

///|
fn MacPaletteSession::sync_metrics(
  self : MacPaletteSession,
  width : Double,
  height : Double,
  scale : Double,
) -> Result[Unit, @diagnostics.FrameworkError] {
  if width.is_nan() ||
    width.is_inf() ||
    width <= 0.0 ||
    height.is_nan() ||
    height.is_inf() ||
    height <= 0.0 ||
    scale.is_nan() ||
    scale.is_inf() ||
    scale <= 0.0 {
    return Err(mac_palette_error("palette_metrics", "invalid window metrics"))
  }
  self.width = width
  self.height = height
  self.scale = scale
  Ok(())
}
