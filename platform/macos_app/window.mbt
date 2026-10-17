///|
/// Window creation settings for a reusable one-window macOS application.
pub(all) struct MacosWindowConfig {
  title : String
  width : Double
  height : Double
  require_text : Bool
}

///|
pub fn MacosWindowConfig::new(
  title : String,
  width : Double,
  height : Double,
  require_text~ : Bool = true,
) -> Result[MacosWindowConfig, @diagnostics.FrameworkError] {
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
      @diagnostics.FrameworkError::new(
        @diagnostics.InvalidInput,
        "macos_window_config",
        subsystem="platform/macos_app",
        backend="appkit-metal",
        message="invalid window configuration",
      ),
    )
  }
  Ok({ title, width, height, require_text, })
}

///|
pub fn MacosWindowConfig::title(self : MacosWindowConfig) -> String {
  self.title
}

///|
pub fn MacosWindowConfig::width(self : MacosWindowConfig) -> Double {
  self.width
}

///|
pub fn MacosWindowConfig::height(self : MacosWindowConfig) -> Double {
  self.height
}

///|
pub fn MacosWindowConfig::require_text(self : MacosWindowConfig) -> Bool {
  self.require_text
}

///|
fn macos_require_capability(
  host : @macos.Host,
  capability : @platform.Capability,
) -> Result[Unit, @diagnostics.FrameworkError] {
  host.require_capability(capability)
}

///|
/// Create one window, run the shared `app.WindowView` loop, and return its
/// outcome. The caller owns host startup/shutdown. A bounded `MaxTicks` run or
/// a failed run destroys the window best-effort so a test cannot leak it.
pub fn[V : @app.WindowView] run_main_window(
  host : @macos.Host,
  config : MacosWindowConfig,
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
    match macos_require_capability(host, capability) {
      Err(error) => return Err(error)
      Ok(_) => ()
    }
  }
  if config.require_text {
    match macos_require_capability(host, @platform.GrayscaleTextFrames) {
      Err(error) => return Err(error)
      Ok(_) => ()
    }
  }
  let window = match
    host.create_window(config.title, config.width, config.height) {
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
