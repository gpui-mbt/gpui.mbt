///|
type TestOutcome = @app.EventOutcome

///|
struct TestView {
  mut repaint_events : Bool
  mut close_on_close : Bool
  mut exit_on_exit : Bool
  after : @app.EventOutcome
  mut idle : @app.EventOutcome
  mut scale_delta : Double
  events_seen : Ref[Int32]
  presents_seen : Ref[Int32]
  metrics_seen : Array[(Double, Double, Double)]
}

///|
fn TestView::new() -> TestView {
  {
    repaint_events: false,
    close_on_close: false,
    exit_on_exit: false,
    after: @app.EventOutcome::none(),
    idle: @app.EventOutcome::none(),
    scale_delta: 0.0,
    events_seen: Ref(0),
    presents_seen: Ref(0),
    metrics_seen: [],
  }
}

///|
fn runtime_test_error(
  operation : String,
  message : String,
) -> @diagnostics.FrameworkError {
  @diagnostics.FrameworkError::new(
    @diagnostics.InvalidInput,
    operation,
    subsystem="app-test",
    backend="window-runtime",
    message~,
  )
}

///|
fn test_snapshot(
  metrics : @app.WindowMetrics,
  scale_delta : Double,
) -> Result[@scene.SceneSnapshot, @diagnostics.FrameworkError] {
  let viewport = match metrics.logical_rect() {
    Err(error) => return Err(error)
    Ok(value) => value
  }
  let color = @primitives.Color::rgba(20, 30, 40, 255).unwrap()
  let item = match
    @scene.SceneItem::quad(
      1UL,
      viewport,
      color,
      @scene.AffineTransform::identity(),
      1.0,
      None,
    ) {
    Ok(value) => value
    Err(_) => return Err(runtime_test_error("test_scene", "invalid test quad"))
  }
  match
    @scene.SceneSnapshot::new(viewport, metrics.scale + scale_delta, [], [], [
      item,
    ]) {
    Ok(value) => Ok(value)
    Err(_) => Err(runtime_test_error("test_scene", "invalid test snapshot"))
  }
}

///|
impl @app.WindowView for TestView with fn handle_event(self, event, metrics) -> Result[
  @app.EventOutcome,
  @diagnostics.FrameworkError,
] {
  self.events_seen.val += 1
  self.metrics_seen.push((metrics.width, metrics.height, metrics.scale))
  match event.kind() {
    @platform.CloseRequested =>
      if self.close_on_close {
        Ok(@app.EventOutcome::close())
      } else if self.repaint_events {
        Ok(@app.EventOutcome::repaint())
      } else {
        Ok(@app.EventOutcome::none())
      }
    @platform.ExitRequested =>
      if self.exit_on_exit {
        Ok(@app.EventOutcome::exit())
      } else {
        Ok(@app.EventOutcome::none())
      }
    _ =>
      if self.repaint_events {
        Ok(@app.EventOutcome::repaint())
      } else {
        Ok(@app.EventOutcome::none())
      }
  }
}

///|
impl @app.WindowView for TestView with fn scene(self, metrics) -> Result[
  @scene.SceneSnapshot,
  @diagnostics.FrameworkError,
] {
  test_snapshot(metrics, self.scale_delta)
}

///|
impl @app.WindowView for TestView with fn after_present(self, metrics) -> Result[
  TestOutcome,
  @diagnostics.FrameworkError,
] {
  ignore(metrics)
  self.presents_seen.val += 1
  Ok(self.after)
}

///|
impl @app.WindowView for TestView with fn on_idle(self, metrics) -> Result[
  TestOutcome,
  @diagnostics.FrameworkError,
] {
  ignore(metrics)
  Ok(self.idle)
}

///|
fn test_key_space() -> @primitives.InputEvent {
  @primitives.KeyPressed(
    key=@primitives.Space,
    modifiers=@primitives.Modifiers::none(),
    repeat=false,
  )
}

///|
test "runtime presents and repaints on application request" {
  let backend = @testing.ScriptedBackend::new(100.0, 50.0, 1.0).unwrap()
  let view = TestView::new()
  view.repaint_events = true
  ignore(backend.enqueue(@platform.Created, 1.0).unwrap())
  ignore(backend.enqueue(@platform.Input(test_key_space()), 1.0).unwrap())
  ignore(backend.enqueue(@platform.Destroyed, 1.0).unwrap())
  let outcome = @app.run_window(
    backend,
    backend.window(),
    view,
    max_ticks=Some(20),
  ).unwrap()
  assert_true(outcome.reason() == @app.Destroyed)
  assert_eq(outcome.frames(), 3)
  assert_eq(outcome.events(), 2)
  assert_eq(backend.present_count(), 3)
  assert_eq(view.presents_seen.val, 3)
}

///|
test "runtime does not repaint when the view returns none" {
  let backend = @testing.ScriptedBackend::new(80.0, 40.0, 2.0).unwrap()
  let view = TestView::new()
  ignore(backend.enqueue(@platform.Created, 2.0).unwrap())
  ignore(backend.enqueue(@platform.Destroyed, 2.0).unwrap())
  let outcome = @app.run_window(
    backend,
    backend.window(),
    view,
    max_ticks=Some(20),
  ).unwrap()
  assert_eq(outcome.frames(), 1)
  assert_eq(backend.present_count(), 1)
}

///|
test "runtime refreshes metrics before a resize repaint" {
  let backend = @testing.ScriptedBackend::new(100.0, 50.0, 1.0).unwrap()
  let view = TestView::new()
  view.repaint_events = true
  backend.set_metrics(220.0, 140.0, 2.0).unwrap()
  ignore(
    backend.enqueue(@platform.Resized(width=220.0, height=140.0), 2.0).unwrap(),
  )
  ignore(backend.enqueue(@platform.Destroyed, 2.0).unwrap())
  let outcome = @app.run_window(
    backend,
    backend.window(),
    view,
    max_ticks=Some(20),
  ).unwrap()
  assert_eq(outcome.frames(), 2)
  let last = backend.last_present().unwrap()
  assert_eq(last.viewport().size().width(), 220.0)
  assert_eq(last.viewport().size().height(), 140.0)
  assert_eq(last.scale(), 2.0)
}

///|
test "runtime rejects a regressing event sequence" {
  let backend = @testing.ScriptedBackend::new(100.0, 50.0, 1.0).unwrap()
  let view = TestView::new()
  backend.enqueue_with_sequence(@platform.Created, 1.0, 2L).unwrap()
  backend
  .enqueue_with_sequence(@platform.Resized(width=10.0, height=10.0), 1.0, 1L)
  .unwrap()
  let result = @app.run_window(
    backend,
    backend.window(),
    view,
    max_ticks=Some(20),
  )
  assert_true(result is Err(_))
  match result {
    Err(error) => assert_eq(error.operation(), "window_event_sequence")
    Ok(_) => fail("regressing sequence accepted")
  }
}

///|
test "runtime rejects a scene that does not match sampled metrics" {
  let backend = @testing.ScriptedBackend::new(100.0, 50.0, 1.0).unwrap()
  let view = TestView::new()
  view.scale_delta = 1.0
  let result = @app.run_window(
    backend,
    backend.window(),
    view,
    max_ticks=Some(5),
  )
  assert_true(result is Err(_))
  match result {
    Err(error) => assert_eq(error.operation(), "window_scene")
    Ok(_) => fail("mismatched scene accepted")
  }
}

///|
test "runtime destroys on close and waits for the terminal event" {
  let backend = @testing.ScriptedBackend::new(100.0, 50.0, 1.0).unwrap()
  let view = TestView::new()
  view.close_on_close = true
  ignore(backend.enqueue(@platform.CloseRequested, 1.0).unwrap())
  let outcome = @app.run_window(
    backend,
    backend.window(),
    view,
    max_ticks=Some(20),
  ).unwrap()
  assert_true(outcome.reason() == @app.Destroyed)
  assert_eq(outcome.frames(), 1)
  assert_eq(backend.destroy_count(), 1)
  assert_eq(backend.request_exit_count(), 0)
}

///|
test "runtime requests host exit before destroying on exit outcome" {
  let backend = @testing.ScriptedBackend::new(100.0, 50.0, 1.0).unwrap()
  let view = TestView::new()
  view.exit_on_exit = true
  ignore(backend.enqueue(@platform.ExitRequested, 1.0).unwrap())
  let outcome = @app.run_window(
    backend,
    backend.window(),
    view,
    max_ticks=Some(20),
  ).unwrap()
  assert_true(outcome.reason() == @app.Destroyed)
  assert_eq(backend.request_exit_count(), 1)
  assert_eq(backend.destroy_count(), 1)
}

///|
test "runtime honors bounded ticks without a window" {
  let backend = @testing.ScriptedBackend::new(100.0, 50.0, 1.0).unwrap()
  let view = TestView::new()
  let outcome = @app.run_window(
    backend,
    backend.window(),
    view,
    max_ticks=Some(2),
    present_on_start=false,
  ).unwrap()
  assert_true(outcome.reason() == @app.MaxTicks)
  assert_eq(outcome.frames(), 0)
  assert_eq(backend.present_count(), 0)
}

///|
test "runtime propagates backend event failures" {
  let backend = @testing.ScriptedBackend::new(100.0, 50.0, 1.0).unwrap()
  let view = TestView::new()
  backend.fail_next_event(
    runtime_test_error("window_events", "scripted failure"),
  )
  let result = @app.run_window(
    backend,
    backend.window(),
    view,
    max_ticks=Some(2),
    present_on_start=false,
  )
  assert_true(result is Err(_))
}

///|
test "runtime applies idle repaint requests" {
  let backend = @testing.ScriptedBackend::new(100.0, 50.0, 1.0).unwrap()
  let view = TestView::new()
  view.idle = @app.EventOutcome::repaint()
  let outcome = @app.run_window(
    backend,
    backend.window(),
    view,
    max_ticks=Some(3),
    present_on_start=false,
  ).unwrap()
  assert_true(outcome.reason() == @app.MaxTicks)
  assert_eq(outcome.frames(), 2)
}
