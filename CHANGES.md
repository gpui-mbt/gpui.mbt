# Changes

## Unreleased

### Added

- Add start/center/end/stretch wrapped-line content alignment to direct flex
  containers and recursive tree styles, preserving default stretch and nowrap.
  (`docs/conformance-align-content.md`)

- Add an opt-in GPUI device-scale layout boundary while preserving raw logical
  layout by default. (`docs/conformance-device-scale.md`)
- Add macOS background-host startup with hidden windows and explicit
  nonactivating window ordering for owned observation fixtures.

### Changed

### Fixed

- Allow macOS background hosts to start inside an application bundle that
  already has Accessory policy, while still rejecting refused or ineffective
  policy transitions. (`docs/conformance-accessory-policy.md`)

- Redistribute flex space after main-axis min/max limits freeze children,
  using clamped sizes to select growth or shrink and retaining partial-factor
  budgets and unavoidable overflow. (`docs/conformance-flex-limits.md`)

- Limit flex-shrink allocation when shrink factors total less than one,
  preserving measured overflow, weighted shares and signed alignment.
  (`docs/conformance-fractional-shrink.md`)
- Match pinned GPUI partial flex-grow allocation when a line has gaps, including
  zero or negative distribution budgets and center/end placement.
  (`docs/conformance-gap-budget.md`)
- Keep unallocated free space when flex-grow factors total less than one,
  preserving each child's fractional share and the selected justification.
  (`docs/conformance-fractional-grow.md`)
- Preserve center/end flex alignment when children exceed the available main
  or cross size, including negative origins and leading overflow reporting.
  (`docs/conformance-layout.md`)
- Use half-open element bounds for pointer hit testing: right/bottom edges
  and zero-extent nodes no longer receive hits. Shared edges belong to the
  element starting at that edge. (`docs/conformance-pointer.md`)

### Deprecated

### Removed

### Security

### Migration

## 0.7.2 - 2026-10-13

### Added

### Changed

### Fixed

- Reject stale macOS Button session copies before routing input, applying
  metrics or close events, or publishing/revoking AppKit accessibility
  bindings; read native accessibility snapshots from the current fixture
  source. (`issues/open/0024-apple-silicon-macos-button-integration.md`)

### Deprecated

### Removed

### Security

### Migration

## 0.7.1 - 2026-10-13

### Added

- Added Windows text-field controller coverage for grouped committed typing,
  Backspace, forward Delete, and edit-group boundaries.

### Changed

- Ship the shared TextField adjacent typing and same-direction deletion
  coalescing from [PR #66](https://github.com/gpui-mbt/gpui.mbt/pull/66) in the
  Mooncakes package so Windows registry consumers receive that behavior.

### Fixed

- Declare the missing `fonts-dejavu-extra` geometry-test dependency and check
  neutral `sans` resolution before Linux text/Ubuntu E2E tests, preserving the
  negative-bearing assertions and logging the actual font file hashes.
- Avoid Weston's seatless kiosk-shell use-after-free in ordinary Ubuntu E2E
  and failure diagnostics by using an explicit, animation-free desktop-shell
  profile. Keep the historical paired kiosk comparison unchanged and include
  the compositor profile in benchmark workload checksums.
  ([PR #63](https://github.com/gpui-mbt/gpui.mbt/pull/63))
- Reject fresh Ubuntu Button accessibility snapshot reads after source closure
  or an unpublished semantic change, while retaining readable detached copies.
  ([PR #61](https://github.com/gpui-mbt/gpui.mbt/pull/61))
- Report actual source-data loss in bounded Ubuntu comparison logs and omit
  truncation markers when the complete output is retained.
  ([PR #63](https://github.com/gpui-mbt/gpui.mbt/pull/63))

### Deprecated

### Removed

### Security

### Migration

## 0.7.0 - 2026-10-11

### Added

- Added a transport-free Windows accessibility projection for copied semantic
  snapshots, stable opaque export IDs, live action validation, and stale or
  foreign owner rejection. Application owners remain responsible for effects;
  native UI Automation remains unsupported. See the [accessibility design](docs/accessibility.md).

### Changed

### Fixed

- Prevent stale Windows Button session copies from publishing older semantic
  snapshots or closing the current owner's binding, including after session-
  only changes such as backing-scale updates.

### Deprecated

### Removed

### Security

### Migration

## 0.6.0 - 2026-10-11

### Added

- Added a copied, bounded macOS `Host::display_snapshot()` for AppKit screen
  geometry, CoreGraphics pixel modes and refresh rate, backing scale, primary
  status and the host key-window screen. Display changes during a query return
  `Busy`; persistent display identifiers and change notifications are not
  included. See [macOS native support](docs/macos-native.md).

### Changed

### Fixed

### Deprecated

### Removed

### Security

### Migration

## 0.5.0 - 2026-10-11

### Added

- Added a native macOS command-palette sample that composes the shared palette,
  TextField, CoreText measurement and AppKit/Metal host. Its synthetic NSWindow
  E2E checks filtering, navigation, activation, cancellation, reopening, pixels
  and teardown; palette-specific committed text input, Japanese IME and
  accessibility remain unqualified. See
  [the sample guide](examples/macos_command_palette/README.md).
- Added a window-scoped synthetic key-event hook for opt-in macOS native E2E.

### Changed

### Fixed

- Include the existing macOS Button accessibility adapter in both dylib builds
  from script/build_and_run.sh and verify that its public bridge symbols are
  exported.

### Deprecated

### Removed

### Security

### Migration

## 0.4.0 - 2026-10-11

### Added

- Added a bounded Windows `Host::display_snapshot()` API for copied virtual
  screen geometry, work areas, current display modes, primary-monitor status,
  and the monitor containing the host window. Effective DPI is reported only
  for the current window monitor through the DPI-aware `GetDpiForWindow` API;
  other monitors report it as unavailable. Physical panel dimensions and
  stable monitor identifiers are not inferred. See the
  [Windows native guide](docs/windows-native.md).

### Changed

### Fixed

### Deprecated

### Removed

### Security

### Migration

## 0.3.0 - 2026-10-10

### Added

- Added a bounded macOS AppKit accessibility adapter for the sample Button,
  with public snapshot, publish/revoke, and semantic Invoke APIs. See the
  [macOS Button guide](examples/macos_button/README.md); general widget and
  VoiceOver support remain unqualified.

### Changed

### Fixed

- Propagate CoreText framework link flags to downstream macOS native builds so
  package consumers can use `platform/macos_text` outside a Moon workspace.
- Post focus-change notifications with the newly focused live element, or a
  current live target after the previous Button element is removed.
- Bound cleanup of the macOS AX harness's app, client, and watchdog processes,
  including stopped children that ignore termination.

### Deprecated

### Removed

### Security

### Migration

- Provide Python 3 when building GPUI for native or LLVM targets; Moon runs the
  module pre-build configuration script for those backends.

## 0.2.2 - 2026-10-10

### Fixed

- Windows wheel deltas now update only the event slot accepted by the shared
  input queue. Queue or sequence exhaustion can no longer overwrite an earlier
  event's input payload.

## 0.2.1 - 2026-10-10

### Added

- Added a Windows-native fixture that reuses the portable Button model, exposes
  completed-frame D3D11 pixel evidence, and provides a separately gated
  SendInput runner. The current interactive desktop blocked input acceptance;
  physical input, window lifecycle, UI Automation and Japanese IME remain open.
  See the [Windows Button guide](docs/windows-button.md).

### Changed

## 0.2.0 - 2026-10-10

### Added

- Added CoreText measurement and grayscale Metal rendering for bounded macOS
  single-line scene text, plus opt-in native frame readback and host-scoped
  AppKit input hooks for E2E evidence. See [macOS native support](docs/macos-native.md).

- Added bounded immutable undo/redo to the experimental single-line text field,
  with original directional selections, private copy-safe history, independent
  entry/UTF-8 payload caps and current-style admission on restoration. Clipboard
  and presentation transactions retain or roll back matching history. See the
  [field guide](docs/linux-text-field.md); live keyboard/IME and broader editor
  behavior remain open.

- Added browser plain-text clipboard services, committed-text input through the
  shared event queue, and event-driven Canvas 2D restoration that preserves the
  live app state. The demo includes explicit clipboard/text controls and focused
  service/browser regressions. Full text/IME and production support remain open;
  see [the browser guide](docs/browser-demo.md).

- Added 41 capability/MCP mutation regression tests, independently reviewed per-operator baselines, survivor-identity checks, and retained CI reports. Bounded semantic conformance closes on verified merge after final-head stability and CI gates; async endpoint lifecycle/topology remains open in 0016. See the [semantic mutation contract](docs/semantic-mutation.md).

- Added portable `AppLifetime` tokens and app-owned capability registry creation/adoption. Stop now invalidates registered typed, GUI, and adapter handles and rejects cached or late results. See the [owner lifecycle contract](docs/capability-lifecycle.md).

- Added the first macOS AppKit/Metal backend and MoonBit quad demo, with a portable backend interface, logical input/scale events, typed failures, native frame/lifecycle/input E2E, app-bundle build script, and macOS CI build/evidence workflows. See [issue 0006](issues/open/0006-macos-native-backend.md). Text/IME, accessibility, automatic renderer recovery, and production support gates remain pending.

- Added macOS scroll-wheel delivery to the shared input event stream. Precise
  point deltas and coarse line/row deltas retain their AppKit units; physical
  device delivery remains unqualified. See [macOS native support](docs/macos-native.md).

- Added a Stage A macOS example that composes the portable reusable Button fixture with the AppKit/Metal host, plus adapter regressions and completed-frame native smoke checks. See the [macOS Button guide](examples/macos_button/README.md).

- Added the headless M1 `core/` API for app and entity lifetimes, scoped contexts, subscriptions, structured errors, and deterministic foreground tasks. See [issue 0001](issues/open/0001-product-charter-and-compatibility.md).
- Added MoonBit `primitives/` and `diagnostics/` packages and an executable package-boundary check for the runtime graph. See [issue 0002](issues/open/0002-architecture-and-dependency-policy.md).
- Added the first M2 `layout/` package: deterministic row/column flex-line layout with points/percent/auto child dimensions, gap, padding/border, grow/shrink, one-pass min/max clamping, alignment, overflow reporting, unit tests, and a seeded QuickCheck invariant.
- Added the M2 `element/` foundation with flat pre-order tree validation, reverse-paint hit testing, capture/bubble route planning, focus state, layout-box bridging, and deterministic element-to-scene generation.
- Added the M3 `scene/` foundation with ordered platform-neutral quad and clip commands and headless ordering/data tests.

### Changed

- Defined deterministic FIFO event delivery, explicit `notify`, one revision per entered update (including failure), release cleanup, cooperative cancellation, and manually advanced timer semantics for the M1 core.
- Extended the executable package-boundary policy with approved `layout -> primitives`, `scene -> primitives`, and `element -> core/primitives/layout/scene` runtime edges; all remain third-party-runtime-free.

### Fixed

- Synchronize the macOS Button sample with the host's current logical size and
  backing scale before rendering, so queued resize events cannot submit a
  stale viewport. The adapter and native smoke cover resize bursts.
- Balance browser pointer and key presses across renderer loss, including a
  press queued before the cancelled frame. The first restored drain receives
  matching releases, and later native releases cannot release the same hold
  twice.
- Preserve semantic target clearing and subsequent selections across browser
  renderer loss, including a return from the legacy island to the canvas before
  the restored frame. Enter cannot reactivate the cleared action.
- Deliver independent committed paste text during an active browser composition
  without discarding it or clearing the provisional composition range.

### Deprecated

### Removed

### Security

### Migration

- A typed capability now belongs to at most one registry. Create fresh typed instances for independent registries; all copies of a registered handle follow its registry's irreversible lifetime. App-owned registries use `Registry::new_owned(app)` or `attach_owner(app)`.

- Entity payloads of generic type `T` must use immutable or copy-on-write values. Mutating a retained `Array`, `Map`, `Ref`, or other mutable alias outside `App::update` can bypass revision and notification tracking; M1 cannot enforce deep-copy ownership.


## Unreleased M2/M3 dispatch and snapshot slice

- Add callback-driven capture/bubble pointer dispatch with shared stop-propagation state and deterministic visited-path results.
- Add provisional `CommandSnapshot` values with validated positive scale, owned command storage, and canonical compact serialization while reserving `SceneSnapshot` v1 for the full R0 contract.
- Extend headless tests and implementation evidence without changing any platform support or release-gate claim.


## 2026-10-03 — M2 focus and M3 clip invariants

- add immutable element subtree removal that clears focus when the focused node dies
- add seeded event/focus properties for route reversal, stop-propagation, and focus validity
- validate scene clip stacks with typed underflow/mismatch/unclosed errors
- reject invalid clip structure before creating provisional command snapshots
- add seeded scene clip-stack properties

## 2026-10-03 — first Ubuntu Wayland native slice

- Add shared backend/window/event contracts and an owned Wayland/xdg-shell host.
- Add an EGL/GLES2 SceneSnapshot v1 quad renderer, ordered basic input, integer scale, frame completion, and explicit renderer recreation.
- Add the native MoonBit example, shared host conformance gate, GPU readback/lifecycle/FD tests, and Ubuntu 24.04 Weston CI at 1×/2×.
- Keep clipboard, IME/accessibility, fractional scale and production support gates open; see [Ubuntu evidence and limits](docs/ubuntu.md).
