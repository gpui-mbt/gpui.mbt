// GP-00 comparison adapter, not a third Button state machine. Gesture state is
// owned exclusively by the existing GPUI Button and Yami ButtonInteraction.
// Generated fixtures call these adapters with the same operation array.

///|
enum Step {
  Down(@primitives.Key, Bool)
  Up(@primitives.Key)
  PointerDown(@primitives.Point, @primitives.MouseButton)
  PointerUp(@primitives.Point, @primitives.MouseButton)
  Bounds(@primitives.Rect)
  Cancel
  Focus(Bool)
  Loading(Bool)
}

///|
fn rect(
  x : Double,
  y : Double,
  width : Double,
  height : Double,
) -> @primitives.Rect {
  match @primitives.Rect::new(x, y, width, height) {
    Ok(value) => value
    Err(_) => abort("invalid fixture rectangle")
  }
}

///|
fn point(x : Double, y : Double) -> @primitives.Point {
  match @primitives.Point::new(x, y) {
    Ok(value) => value
    Err(_) => abort("invalid fixture point")
  }
}

///|
fn measure(
  value : String,
  size : Double,
) -> Result[@text_layout.TextMeasurement, @diagnostics.FrameworkError] {
  let document = match @text.TextDocument::new(value) {
    Ok(value) => value
    Err(_) => abort("invalid fixture text")
  }
  let carets : Array[@text_layout.CaretGeometry] = []
  for offset = 0; offset <= value.length(); offset = offset + 1 {
    let bounds = rect(offset.to_double() * size * 0.6, 0.0, 1.0, size)
    match @text_layout.CaretGeometry::new(offset, true, bounds, bounds) {
      Ok(value) => carets.push(value)
      Err(_) => abort("invalid fixture caret")
    }
  }
  let bounds = rect(0.0, 0.0, value.length().to_double() * size * 0.6, size)
  match
    @text_layout.TextMeasurement::new(
      document,
      bounds,
      bounds,
      size * 0.8,
      1,
      0,
      carets,
    ) {
    Ok(value) => Ok(value)
    Err(_) => abort("invalid fixture measurement")
  }
}

///|
fn emit(
  name : String,
  model : String,
  index : Int32,
  activated : Bool,
  pressed : Bool,
  status : String,
  focused : String,
) -> Unit {
  println(
    "\{name}|\{model}|\{index}|\{activated}|\{pressed}|\{status}|\{focused}",
  )
}

///|
fn run_yami(
  name : String,
  initial : @primitives.Rect,
  disabled : Bool,
  steps : Array[Step],
) -> Unit {
  let button = match
    @components.NativeButton::new(
      20UL,
      "OK",
      @yami_kumo.Primary,
      @yami_kumo.Xs,
      disabled,
      @components.Theme::light(),
      measure,
    ) {
    Ok(value) => value
    Err(_) => abort("Yami fixture button construction failed")
  }
  if button.intrinsic_size().height() != 20.0 {
    abort("legacy Xs height changed; review the size migration fixture")
  }
  let interaction = button.interaction()
  let mut bounds = initial
  // Focus/geometry are caller-owned in this legacy API, not gesture state.
  let mut focused = !disabled
  let _ = button.element_node(bounds, None)
  emit(name, "yami", -1, false, interaction.is_pressed(), "accepted", "unowned")
  for index = 0; index < steps.length(); index = index + 1 {
    let mut activated = false
    let mut status = "ok"
    match steps[index] {
      Down(key, _) =>
        activated = interaction.key_down(
          if focused {
            Some(20UL)
          } else {
            None
          },
          key,
        )
      Up(key) =>
        activated = interaction.key_up(
          if focused {
            Some(20UL)
          } else {
            None
          },
          key,
        )
      PointerDown(position, button) => {
        let _ = interaction.pointer_down(
          if bounds.contains(position) {
            Some(20UL)
          } else {
            None
          },
          button,
        )
      }
      PointerUp(position, button) =>
        activated = interaction.pointer_up(
          if bounds.contains(position) {
            Some(20UL)
          } else {
            None
          },
          button,
        )
      Bounds(next) => {
        // The controller has no bounds setter. This changes caller routing
        // geometry only; an explicit Cancel is required to invalidate a press.
        bounds = next
        status = "caller-bounds"
      }
      Cancel => interaction.cancel()
      Focus(value) => {
        focused = value && !disabled
        if !focused {
          interaction.cancel()
        }
        status = "caller-focus"
      }
      Loading(_) => status = "unsupported"
    }
    emit(
      name,
      "yami",
      index,
      activated,
      interaction.is_pressed(),
      status,
      "unowned",
    )
  }
}

///|
fn run_gpui(
  name : String,
  bounds : @primitives.Rect,
  disabled : Bool,
  steps : Array[Step],
) -> Unit {
  let mut button = match @button.Button::new(20UL, bounds, "OK") {
    Ok(value) => value.with_enabled(!disabled).with_focus(true)
    Err(_) => {
      emit(name, "gpui", -1, false, false, "invalid-bounds", "false")
      return
    }
  }
  emit(
    name,
    "gpui",
    -1,
    false,
    button.is_pressed(),
    "accepted",
    button.is_focused().to_string(),
  )
  for index = 0; index < steps.length(); index = index + 1 {
    let mut event : @primitives.InputEvent? = None
    let mut status = "ok"
    match steps[index] {
      Down(key, repeat) =>
        event = Some(
          @primitives.KeyPressed(
            key~,
            repeat~,
            modifiers=@primitives.Modifiers::none(),
          ),
        )
      Up(key) =>
        event = Some(
          @primitives.KeyReleased(key~, modifiers=@primitives.Modifiers::none()),
        )
      PointerDown(position, mouse) =>
        event = Some(
          @primitives.PointerButtonPressed(
            position~,
            button=mouse,
            modifiers=@primitives.Modifiers::none(),
          ),
        )
      PointerUp(position, mouse) =>
        event = Some(
          @primitives.PointerButtonReleased(
            position~,
            button=mouse,
            modifiers=@primitives.Modifiers::none(),
          ),
        )
      Bounds(next) =>
        match button.with_bounds(next) {
          Ok(value) => button = value
          Err(_) => status = "invalid-bounds"
        }
      Cancel => button = button.cancel_press()
      Focus(value) => button = button.with_focus(value)
      Loading(value) => button = button.with_loading(value)
    }
    let activated = match event {
      None => false
      Some(event) => {
        let (next, result) = button.handle_input(event)
        button = next
        result.effect() == @button.Activated
      }
    }
    emit(
      name,
      "gpui",
      index,
      activated,
      button.is_pressed(),
      status,
      button.is_focused().to_string(),
    )
  }
}

///|
fn run(
  name : String,
  bounds : @primitives.Rect,
  disabled : Bool,
  steps : Array[Step],
) -> Unit {
  run_yami(name, bounds, disabled, steps)
  run_gpui(name, bounds, disabled, steps)
}
