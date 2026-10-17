///|
/// Window creation settings for a reusable one-window Windows application.
pub(all) struct WindowsWindowConfig {
  title : String
  width : Double
  height : Double
  require_text : Bool
}

///|
fn windows_window_error(
  operation : String,
  message : String,
) -> @diagnostics.FrameworkError {
  @diagnostics.FrameworkError::new(
    @diagnostics.InvalidInput,
    operation,
    subsystem="platform/windows_app",
    backend="win32-d3d11",
    message~,
  )
}

///|
pub fn WindowsWindowConfig::new(
  title : String,
  width : Double,
  height : Double,
  require_text~ : Bool = true,
) -> Result[WindowsWindowConfig, @diagnostics.FrameworkError] {
  if title.length() == 0 ||
    title.length() > 4096 ||
    width.is_nan() ||
    width.is_inf() ||
    height.is_nan() ||
    height.is_inf() ||
    width < 1.0 ||
    height < 1.0 ||
    width > 8192.0 ||
    height > 8192.0 {
    return Err(
      windows_window_error(
        "windows_window_config", "invalid window configuration",
      ),
    )
  }
  Ok({ title, width, height, require_text, })
}

///|
pub fn WindowsWindowConfig::title(self : WindowsWindowConfig) -> String {
  self.title
}

///|
pub fn WindowsWindowConfig::width(self : WindowsWindowConfig) -> Double {
  self.width
}

///|
pub fn WindowsWindowConfig::height(self : WindowsWindowConfig) -> Double {
  self.height
}

///|
pub fn WindowsWindowConfig::require_text(self : WindowsWindowConfig) -> Bool {
  self.require_text
}

///|
fn windows_integer_dimension(
  value : Double,
  operation : String,
) -> Result[Int32, @diagnostics.FrameworkError] {
  if value < 1.0 || value > 8192.0 {
    return Err(windows_window_error(operation, "invalid window dimension"))
  }
  let integer = value.to_int()
  if integer.to_double() != value {
    Err(windows_window_error(operation, "window dimension must be an integer"))
  } else {
    Ok(integer)
  }
}

///|
/// Create one window, run the shared `app.WindowView` loop, and return its
/// outcome. The caller owns host startup/shutdown. A bounded `MaxTicks` run or
/// a failed run destroys the window best-effort so a test cannot leak it.
pub fn[V : @app.WindowView] run_main_window(
  host : @windows.Host,
  config : WindowsWindowConfig,
  view : V,
  timeout_ms~ : Int32 = 16,
  max_ticks~ : Int32? = None,
  present_on_start~ : Bool = false,
) -> Result[@app.WindowRunOutcome, @diagnostics.FrameworkError] {
  for
    capability in [
      @platform.NativeWindow,
      @platform.QuadFrames,
      @platform.PointerKeyboard,
    ] {
    match host.require_capability(capability) {
      Err(error) => return Err(error)
      Ok(_) => ()
    }
  }
  if config.require_text {
    match host.require_capability(@platform.GrayscaleTextFrames) {
      Err(error) => return Err(error)
      Ok(_) => ()
    }
  }
  let width = match windows_integer_dimension(config.width, "create_window") {
    Err(error) => return Err(error)
    Ok(value) => value
  }
  let height = match windows_integer_dimension(config.height, "create_window") {
    Err(error) => return Err(error)
    Ok(value) => value
  }
  let window = match host.create_window(width, height, config.title) {
    Err(error) => return Err(error)
    Ok(value) => value
  }
  let outcome = @app.run_window(
    host,
    window,
    view,
    timeout_ms~,
    max_ticks~,
    present_on_start~,
  )
  match outcome {
    Err(error) => {
      ignore(host.destroy_window(window))
      Err(error)
    }
    Ok(value) =>
      if value.reason() is @app.MaxTicks {
        ignore(host.destroy_window(window))
        Ok(value)
      } else {
        Ok(value)
      }
  }
}
