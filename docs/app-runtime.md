# Reusable native application runtime

`app/` is the portable application layer above `platform.Backend`. It removes
the event-loop, metrics, close-policy and frame-validation boilerplate that each
native sample previously duplicated. `mac-native-app-demo` is an integration
fixture for these APIs; the reusable behavior lives in this repository.

## WindowView and run_window

Implement `app.WindowView` for one window:

```moonbit
impl @app.WindowView for DemoSession with fn handle_event(self, event, metrics) { ... }
impl @app.WindowView for DemoSession with fn scene(self, metrics) { ... }
impl @app.WindowView for DemoSession with fn after_present(self, metrics) { ... }
impl @app.WindowView for DemoSession with fn on_idle(self, metrics) { ... }
```

`run_window` owns one already-created window. The caller owns host
startup/shutdown.

- `WindowMetrics` samples logical width, height and backing scale. The runtime
  samples fresh metrics before each present and passes them to `scene`.
- Every scene must use exactly the sampled viewport and scale. A mismatch is a
  typed `InvalidInput` error rather than a silently distorted frame.
- Events for the target window must have strictly increasing sequence numbers.
- `EventOutcome.repaint` requests another frame. `close` destroys the window.
  `exit` requests host exit and then destroys the window.
- The view decides close policy. `Destroyed` ends the loop.
- `after_present` runs after every successful frame. `on_idle` runs when
  `next_event` returns `None`. Both can request repaint, close or exit.
- `max_ticks` is a deterministic bound for tests and synthetic smoke flows.
- Events for other windows are ignored except host-level `ExitRequested`.

`platform/testing.ScriptedBackend` supplies a deterministic backend for runtime
tests, and `platform/testing.FrameCapture` now provides logical-pixel
comparison, region-difference and ink-count helpers.

## SceneBuilder

`scene.SceneBuilder` builds the existing `SceneSnapshot` v1 envelope without
manual item-ID or clip-chain bookkeeping:

- Monotonic item IDs, explicit `reserve_ids`, and checked `push_items` for
  controls that build their own items.
- Clip-chain deduplication by rectangle array.
- Full-rectangle border quads.
- Measured left/center/right and top/center/bottom text placement.
- Typed builder errors for ID exhaustion, duplicates, item/clip limits and
  invalid text metrics.

The resulting snapshot still contains only the existing v1 item variants.

## macOS app helpers

`platform/macos_app/` contains macOS-leaf helpers that are reusable by future
macOS applications:

- `MacosTextFieldAdapter` maps `platform/macos_text.measure` into the
  `controls/text_field` measure/admit/hit callbacks.
- `MacosTextPainter` caches bounded CoreText logical metrics and emits aligned
  scene labels through `SceneBuilder`.
- `CursorState` suppresses redundant cursor calls.
- `run_main_window` checks the macOS capabilities, creates one window, and runs
  the shared app runtime. Host start/stop remains caller-owned.

`controls/text_field` also exposes `TextFieldPaintPalette` and
`paint_items_with_palette`; `standard()` preserves the original white/blue field
scene.

## Build and smoke helper

`script/build_macos_app.sh` builds the native shim, MoonBit executable and
`.app` bundle for an app root whose `moon.work` includes the local `gpui.mbt`
checkout:

```sh
../gpui.mbt/script/build_macos_app.sh \
  --root . --name MyApp --bundle-id org.example.myapp \
  --package src/app --build
```

Modes are `--build`, `--run`, `--verify` and `--smoke`. Smoke builds the shim
with `GPUI_TESTING`, sets `GPUI_NATIVE_E2E=1`, passes `--smoke`, and converts
PPM frame artifacts to PNG when `sips` is available. `--native-source` and
`--framework` add app-specific native inputs.

## Limits

This packet does not add committed text input or IME, a native menu bar, a
general accessibility tree, multi-window orchestration, or renderer recovery.
Those require separate native transport and evidence packets. The macOS demo
uses an application-level printable-key adapter and the existing bounded Button
accessibility binding; it does not claim a macOS support tier.
