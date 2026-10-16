///|
fn mac_palette_pixel_matches(
  frame : @testing.FrameCapture,
  logical_x : Double,
  logical_y : Double,
  red : Int32,
  green : Int32,
  blue : Int32,
) -> Bool {
  let x = (logical_x * frame.scale()).to_int()
  let y = (logical_y * frame.scale()).to_int()
  match frame.pixel_rgba8(x, y) {
    Err(_) => false
    Ok((actual_red, actual_green, actual_blue, alpha)) =>
      actual_red >= red - 8 &&
      actual_red <= red + 8 &&
      actual_green >= green - 8 &&
      actual_green <= green + 8 &&
      actual_blue >= blue - 8 &&
      actual_blue <= blue + 8 &&
      alpha >= 250
  }
}

///|
fn mac_palette_region_changed(
  before : @testing.FrameCapture,
  after : @testing.FrameCapture,
  left : Double,
  top : Double,
  right : Double,
  bottom : Double,
) -> Bool {
  if before.width() != after.width() ||
    before.height() != after.height() ||
    before.scale() != after.scale() {
    return false
  }
  let scale = before.scale()
  let x0 = (left * scale).to_int()
  let y0 = (top * scale).to_int()
  let x1 = (right * scale).to_int()
  let y1 = (bottom * scale).to_int()
  let old_pixels = before.rgba8_top_left()
  let new_pixels = after.rgba8_top_left()
  let required_bytes = before.width() * before.height() * 4
  if x0 < 0 ||
    y0 < 0 ||
    x1 <= x0 ||
    y1 <= y0 ||
    x1 > before.width() ||
    y1 > before.height() ||
    old_pixels.length() != required_bytes ||
    new_pixels.length() != required_bytes {
    return false
  }
  let mut changed = 0
  for y in y0..<y1 {
    for x in x0..<x1 {
      let offset = (y * before.width() + x) * 4
      if old_pixels.unsafe_get(offset) != new_pixels.unsafe_get(offset) ||
        old_pixels.unsafe_get(offset + 1) != new_pixels.unsafe_get(offset + 1) ||
        old_pixels.unsafe_get(offset + 2) != new_pixels.unsafe_get(offset + 2) {
        changed += 1
      }
    }
  }
  changed >= 2
}

///|
fn mac_palette_field_changed(
  before : @testing.FrameCapture,
  after : @testing.FrameCapture,
) -> Bool {
  mac_palette_region_changed(before, after, 56.0, 90.0, 584.0, 126.0)
}

///|
fn mac_palette_e2e_failure(
  operation : String,
  message : String,
) -> @diagnostics.FrameworkError {
  mac_palette_error(operation, message)
}

///|
fn mac_palette_post_key(
  host : @macos.Host,
  window : @platform.WindowId,
  key : @primitives.Key,
  modifiers~ : @primitives.Modifiers = @primitives.Modifiers::none(),
) -> Result[Unit, @diagnostics.FrameworkError] {
  host.post_test_key(window, key, modifiers)
}

///|
fn mac_palette_e2e_advance(
  host : @macos.Host,
  window : @platform.WindowId,
  session : MacPaletteSession,
  frame : @testing.FrameCapture,
  comparison_frame : Ref[@testing.FrameCapture?],
  stage : Int32,
) -> Result[Int32, @diagnostics.FrameworkError] {
  match stage {
    0 => {
      if frame.width() != (session.width * frame.scale()).to_int() ||
        frame.height() != (session.height * frame.scale()).to_int() ||
        !mac_palette_pixel_matches(frame, 8.0, 8.0, 24, 28, 36) {
        return Err(
          mac_palette_e2e_failure(
            "palette_initial_pixels", "initial completed Metal frame did not match the viewport",
          ),
        )
      }
      match
        mac_palette_post_key(
          host,
          window,
          @primitives.Character("k"),
          modifiers=@primitives.Modifiers::new(
            shift=false,
            control=false,
            alt=false,
            meta=true,
          ),
        ) {
        Ok(_) => Ok(1)
        Err(error) => Err(error)
      }
    }
    1 if session.is_open() && session.epoch() == 1 => {
      if !mac_palette_pixel_matches(frame, 54.0, 142.0, 48, 74, 114) ||
        !mac_palette_pixel_matches(frame, 70.0, 100.0, 255, 255, 255) {
        return Err(
          mac_palette_e2e_failure(
            "palette_open_pixels", "open frame did not show the focused search field and active row",
          ),
        )
      }
      comparison_frame.val = Some(frame)
      match mac_palette_post_key(host, window, @primitives.Character("s")) {
        Ok(_) => Ok(2)
        Err(error) => Err(error)
      }
    }
    2 if session.palette.picker().query() == "s" => {
      if session.palette.picker().match_count() != 10 {
        return Err(
          mac_palette_e2e_failure(
            "palette_query", "ASCII search did not filter the expected shared command set",
          ),
        )
      }
      let before = match comparison_frame.val {
        Some(value) => value
        None =>
          return Err(
            mac_palette_e2e_failure(
              "palette_query_pixels", "the empty search frame was not retained",
            ),
          )
      }
      if !mac_palette_field_changed(before, frame) {
        return Err(
          mac_palette_e2e_failure(
            "palette_query_pixels", "search text did not change the completed Metal frame",
          ),
        )
      }
      match mac_palette_post_key(host, window, @primitives.ArrowDown) {
        Ok(_) => Ok(3)
        Err(error) => Err(error)
      }
    }
    3 if session.palette.picker().active_command() is Some(command) &&
      command.id() == "palette.toggle_sidebar" => {
      if !mac_palette_pixel_matches(frame, 54.0, 142.0, 30, 34, 44) ||
        !mac_palette_pixel_matches(frame, 54.0, 214.0, 48, 74, 114) {
        return Err(
          mac_palette_e2e_failure(
            "palette_navigation_pixels", "the selected row did not move past the disabled command",
          ),
        )
      }
      match mac_palette_post_key(host, window, @primitives.Enter) {
        Ok(_) => Ok(4)
        Err(error) => Err(error)
      }
    }
    4 if !session.is_open() &&
      session.actions.val == 1 &&
      session.last_action.val == "palette.toggle_sidebar" => {
      if !mac_palette_pixel_matches(frame, 8.0, 8.0, 24, 28, 36) {
        return Err(
          mac_palette_e2e_failure(
            "palette_activation_pixels", "activation did not return to the closed screen",
          ),
        )
      }
      match
        mac_palette_post_key(
          host,
          window,
          @primitives.Character("k"),
          modifiers=@primitives.Modifiers::new(
            shift=false,
            control=false,
            alt=false,
            meta=true,
          ),
        ) {
        Ok(_) => Ok(5)
        Err(error) => Err(error)
      }
    }
    5 if session.is_open() && session.epoch() == 2 => {
      if session.palette.picker().query() != "" ||
        !mac_palette_pixel_matches(frame, 54.0, 142.0, 48, 74, 114) {
        return Err(
          mac_palette_e2e_failure(
            "palette_reopen", "reopened palette did not start with an empty query",
          ),
        )
      }
      match mac_palette_post_key(host, window, @primitives.Escape) {
        Ok(_) => Ok(6)
        Err(error) => Err(error)
      }
    }
    6 if !session.is_open() && session.actions.val == 1 =>
      match
        mac_palette_post_key(
          host,
          window,
          @primitives.Character("k"),
          modifiers=@primitives.Modifiers::new(
            shift=false,
            control=false,
            alt=false,
            meta=true,
          ),
        ) {
        Ok(_) => Ok(7)
        Err(error) => Err(error)
      }
    7 if session.is_open() && session.epoch() == 3 => {
      if session.palette.picker().query() != "" {
        return Err(
          mac_palette_e2e_failure(
            "palette_cancel_reopen", "cancelled palette state leaked into a later epoch",
          ),
        )
      }
      match mac_palette_post_key(host, window, @primitives.Escape) {
        Ok(_) => Ok(8)
        Err(error) => Err(error)
      }
    }
    8 if !session.is_open() &&
      session.actions.val == 1 &&
      session.background_keys.val == 0 => {
      comparison_frame.val = Some(frame)
      match mac_palette_post_key(host, window, @primitives.Character("z")) {
        Ok(_) => Ok(9)
        Err(error) => Err(error)
      }
    }
    9 if !session.is_open() &&
      session.actions.val == 1 &&
      session.background_keys.val == 1 => {
      let before = match comparison_frame.val {
        Some(value) => value
        None =>
          return Err(
            mac_palette_e2e_failure(
              "palette_background_pixels", "the pre-key status frame was not retained",
            ),
          )
      }
      if !mac_palette_region_changed(before, frame, 30.0, 114.0, 220.0, 138.0) {
        return Err(
          mac_palette_e2e_failure(
            "palette_background_pixels", "an unhandled background key did not update its visible count",
          ),
        )
      }
      match host.destroy_window(window) {
        Ok(_) => Ok(10)
        Err(error) => Err(error)
      }
    }
    _ => Ok(stage)
  }
}

///|
fn mac_palette_present(
  host : @macos.Host,
  window : @platform.WindowId,
  session : MacPaletteSession,
  e2e : Bool,
  comparison_frame : Ref[@testing.FrameCapture?],
  stage : Int32,
) -> Result[Int32, @diagnostics.FrameworkError] {
  let snapshot = match session.scene() {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  match host.present(window, snapshot) {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  if e2e {
    let frame = match @testing.capture_frame(host, window) {
      Ok(value) => value
      Err(error) => return Err(error)
    }
    mac_palette_e2e_advance(
      host, window, session, frame, comparison_frame, stage,
    )
  } else {
    Ok(stage)
  }
}

///|
fn mac_palette_handle_event(
  host : @macos.Host,
  window : @platform.WindowId,
  session : MacPaletteSession,
  event : @platform.Event,
) -> Result[Bool, @diagnostics.FrameworkError] {
  match event.kind() {
    @platform.Created | @platform.Wake => Ok(true)
    @platform.Resized(width~, height~) =>
      match session.sync_metrics(width, height, event.scale()) {
        Ok(_) => Ok(true)
        Err(error) => Err(error)
      }
    @platform.ScaleChanged =>
      match host.window_metrics(window) {
        Ok((width, height, scale)) =>
          match session.sync_metrics(width, height, scale) {
            Ok(_) => Ok(true)
            Err(error) => Err(error)
          }
        Err(error) => Err(error)
      }
    @platform.FocusChanged(false) =>
      match session.blur() {
        Ok(_) => Ok(true)
        Err(error) => Err(error)
      }
    @platform.Input(input) => {
      let background_keys_before = session.background_keys.val
      match session.handle_input(input) {
        Ok(consumed) =>
          Ok(
            consumed ||
            session.is_open() ||
            session.background_keys.val != background_keys_before,
          )
        Err(error) => Err(error)
      }
    }
    _ => Ok(false)
  }
}

///|
fn mac_palette_run(
  host : @macos.Host,
  e2e : Bool,
) -> Result[Unit, @diagnostics.FrameworkError] {
  if e2e && @env.get_env_var("GPUI_NATIVE_E2E") != Some("1") {
    return Err(
      mac_palette_error(
        "palette_native_e2e", "set GPUI_NATIVE_E2E=1 to enable the window-scoped test hooks",
      ),
    )
  }
  let window = match
    host.create_window(
      "gpui.mbt command palette — macOS",
      MAC_PALETTE_WIDTH,
      MAC_PALETTE_HEIGHT,
    ) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let (width, height, scale) = match host.window_metrics(window) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let session = match MacPaletteSession::new(width, height, scale) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let mut done = false
  let mut ticks = 0
  let mut stage = if e2e { 0 } else { -1 }
  let mut sequence : Int64 = 0
  let mut dirty = true
  let comparison_frame : Ref[@testing.FrameCapture?] = Ref(None)
  let mut last_error : @diagnostics.FrameworkError? = None

  while !done && (!e2e || ticks < 2000) {
    if e2e {
      ticks += 1
    }
    match host.next_event(timeout_ms=16) {
      Err(error) => {
        last_error = Some(error)
        done = true
      }
      Ok(None) =>
        if dirty {
          match
            mac_palette_present(
              host, window, session, e2e, comparison_frame, stage,
            ) {
            Err(error) => {
              last_error = Some(error)
              done = true
            }
            Ok(next_stage) => {
              dirty = false
              stage = next_stage
            }
          }
        }
      Ok(Some(event)) =>
        if event.window() == window {
          if event.sequence() <= sequence {
            last_error = Some(
              mac_palette_error(
                "palette_event_order", "native event sequence did not increase",
              ),
            )
            done = true
          } else {
            sequence = event.sequence()
            let kind = event.kind()
            if kind is @platform.Destroyed {
              done = true
            } else if kind is @platform.CloseRequested {
              match session.blur() {
                Err(error) => {
                  last_error = Some(error)
                  done = true
                }
                Ok(_) =>
                  match host.destroy_window(window) {
                    Ok(_) => ()
                    Err(error) => {
                      last_error = Some(error)
                      done = true
                    }
                  }
              }
            } else {
              match mac_palette_handle_event(host, window, session, event) {
                Err(error) => {
                  last_error = Some(error)
                  done = true
                }
                Ok(repaint) => dirty = dirty || repaint
              }
              if dirty && !done {
                match
                  mac_palette_present(
                    host, window, session, e2e, comparison_frame, stage,
                  ) {
                  Err(error) => {
                    last_error = Some(error)
                    done = true
                  }
                  Ok(next_stage) => {
                    dirty = false
                    stage = next_stage
                    println(
                      "macOS palette: open=\{session.is_open()} query=\{session.palette.picker().query()} actions=\{session.actions.val} backgroundKeys=\{session.background_keys.val}",
                    )
                  }
                }
              }
            }
          }
        } else if event.kind() is @platform.ExitRequested {
          match session.blur() {
            Err(error) => {
              last_error = Some(error)
              done = true
            }
            Ok(_) =>
              match host.destroy_window(window) {
                Ok(_) => ()
                Err(error) => {
                  last_error = Some(error)
                  done = true
                }
              }
          }
        }
    }
  }

  if !done && e2e {
    return Err(
      mac_palette_e2e_failure(
        "palette_native_e2e", "synthetic native palette flow exceeded its event bound",
      ),
    )
  }
  match last_error {
    Some(error) => Err(error)
    None if e2e && stage != 10 =>
      Err(
        mac_palette_e2e_failure(
          "palette_native_e2e", "window teardown did not complete after the palette flow",
        ),
      )
    None => Ok(())
  }
}

///|
fn main {
  let e2e = @env.args().contains("--e2e")
  match @macos.Host::start() {
    Err(error) => abort("macOS host startup: " + error.code().label())
    Ok(host) => {
      let result = mac_palette_run(host, e2e)
      let stopped = host.stop()
      match result {
        Err(error) =>
          println(
            "macOS command palette failed: \{error.operation()}: \{error.code().label()}",
          )
        Ok(_) => if e2e { println("GPUI_MACOS_COMMAND_PALETTE_E2E PASS") }
      }
      match stopped {
        Err(error) =>
          abort(
            "macOS host cleanup: " +
            error.operation() +
            ": " +
            error.code().label(),
          )
        Ok(_) => ()
      }
      match result {
        Err(error) => abort("macOS command palette: " + error.operation())
        Ok(_) => ()
      }
    }
  }
}
