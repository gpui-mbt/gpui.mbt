# Changes

## Unreleased

### Added

- Add independent Auto/finite nonnegative point `FlexBasis` on flex items.
  Preserve it through builders, recursive layout and device-scale preparation;
  explicitly reject intrinsic-main-axis basis sizing outside this bounded slice.
  See `docs/flex-basis.md`.

## 0.10.6 - 2026-10-22

### Fixed

- Replace the Python macOS prebuild hook with `script/macos_text_prebuild.mbtx`,
  a MoonBit script that moon compiles to WebAssembly and runs with `moonrun`.
  Native and LLVM builds no longer require Python or Node, and macOS consumers
  still receive the CoreText, CoreGraphics and CoreFoundation link flags.
- Replace the Python Linux C toolchain wrappers with POSIX shell scripts.
  `script/linux_text_cc.sh` discovers PangoFT2 and Fontconfig flags through
  `pkg-config`, and `script/ar`/`script/ranlib` forward to `AR`/`RANLIB`, so
  Linux native builds no longer require Python.

### Migration

- Native builds require a moon toolchain that supports `.mbtx` prebuild scripts;
  the toolchain pinned in CI does. No interpreter has to be installed.
- Linux native builds use `script/linux_text_cc.sh`; `moon.pkg` files that named
  the removed `script/linux_text_cc.py` must update their `cc` and `stub-cc`
  paths. `script/ar` and `script/ranlib` keep their names.

## 0.10.5 - 2026-10-21

### Added

- Add opt-in authored flex-root border-box sizing with independently retained
  physical viewport for snapshots, pointer eligibility and scrolling. Existing
  fixed-viewport root APIs remain unchanged. See `docs/root-box-viewport.md`.

- Add `JustifyContent::flex_start` and `flex_end` for flow-relative main-axis
  alignment, including reverse and wrapped lines. Physical start/end defaults
  remain unchanged.

- Add per-item `layout.AlignSelf` and `FlexItem::with_align_self` for inherited,
  physical start/end, flex-relative start/end, center, and auto-size stretch.
  Overrides survive recursive layout, device-scale preparation, and item builders.

- Publish a bounded macOS Dialog accessibility projection:
  `Host::publish_dialog_accessibility` and
  `Host::revoke_dialog_accessibility`, with `DialogAccessibilitySnapshot`. An
  open dialog is exposed as one group with the `AXDialog` subrole carrying its
  title, focus and frame; the element is revoked when the application closes
  the dialog. A window keeps at most one dialog element. Dialog actions,
  field value writes and assistive-technology acceptance remain out of scope.

## 0.10.4 - 2026-10-21

### Added

- Publish a bounded macOS TextField accessibility projection:
  `Host::publish_text_field_accessibility` and
  `Host::revoke_text_field_accessibility`, with
  `TextFieldAccessibilitySnapshot`. A window keeps a registry of AX elements,
  so a Button and a TextField can be exposed together; the TextField element
  reports role, value, UTF-16 selection, editable state, focus and frame. A
  negative or out-of-range selection is rejected before any native call. AX
  actions, Dialog elements and assistive-technology acceptance remain out of
  scope.
- Add macOS test hooks for exact-source text-input harnesses:
  `Host::post_test_key_code` posts one ANSI key code with explicit characters
  through the owned `NSWindow`, so a live input method can process the key, and
  `Host::text_caret_screen` reads the caret rectangle the AppKit client reports
  to the input method. Both require `GPUI_NATIVE_E2E=1` and a test-hooks
  library. They do not synthesize composition and are not IME evidence alone.
- Add `text_host.TextHostQueue`, shared epoch/sequence/text/parked-event state
  for hosts whose native route exposes one ordered editor stream. It bounds
  parked platform records, keeps an unsupported-record failure readable instead
  of substituting an insertion, and discards copied text when the host replaces
  its native epoch.
- Add `windows.TextHostRoute`, an opt-in portable `TextInputHost` adapter over
  the existing IMM32 editor session. It defers the native begin until the first
  update, maps Marked/empty-Inserted/Cancelled to Preedit/Commit/Cancel, parks
  ordinary platform records for a paired `next_platform_event`, and reports a
  replacement insert as `UnsupportedCapability` instead of flattening it.
  `Capability::TextInput` stays unadvertised until an exact-source IME run
  qualifies the route.
- Add `ubuntu.TextHostRoute`, an opt-in portable `TextInputHost` adapter over
  the existing text-input-v1 session. It maps preedit and no-deletion commits,
  forwards command keys as platform events in the paired `next_platform_event`
  queue, and reports a commit that deletes surrounding text as
  `UnsupportedCapability`. `Capability::TextInput` stays unadvertised until an
  exact-source Wayland/IBus IME run qualifies the route.

## 0.10.3 - 2026-10-20

### Added

- Implement `text_host.TextInputHost` for `platform/macos.Host` over the AppKit
  composition client. An armed session owns enablement and an epoch-tagged,
  ordered text queue that stays separate from `next_event`; the host advertises
  `Capability::TextInput` when the loaded library exports the route and never
  advertises `TextInputGeometry`. Window focus loss publishes `FocusLost`.
- Add `element.FocusScopeSession::adopt_tree` for hosts that rebuild their
  element tree every frame: it replaces the node set of the current revision,
  keeps live modal frames and handles, transplants the focus lineage onto
  surviving ids, and restores once when a scope root disappears. Add
  `FocusScopeSession::clear_focus` and `FocusScopeSession::focused` for owners
  that drop the acquisition on window blur without closing a scope.
- Add the optional `text_host/` native text transport contract
  (`TextInputHost`, `TextInputState`, `TextInputEvent`) between
  `platform.Backend` and `text_session/`, plus
  `Capability::TextInputGeometry`. The package is additive; existing hosts keep
  returning `UnsupportedCapability` until they implement it.

## 0.10.2 - 2026-10-20

### Fixed

- Preserve fresh Wayland composition raw keyboard input while an application
  cancellation waits for text-input-v1 leave/rearm. Keep replacement-epoch
  held-key ownership across re-entry without admitting stale forwarded input.

## 0.10.1 - 2026-10-20

### Added

- Add an opt-in Windows IMM32 composition transport:
  `windows.Host::set_text_composition`, `set_text_composition_caret`, and
  `finish_text_composition`. Start, Update, Commit, and Cancel are published as
  `platform.EventKind::Composition` on the ordinary `next_event` / `dispatch`
  queue through a bounded UTF-8 sidecar.
- Add the Windows `Host::post_test_composition` E2E hook and synthetic
  composition staging for WndProc suppression, finish paths, candidate
  geometry, and mutual exclusion with the private field session.
- Add default-off Wayland text-input-v1 composition APIs on `ubuntu.Host`:
  `set_text_composition`, `set_text_composition_caret`, and
  `finish_text_composition`, with `Composition` events on `next_event`.
- Add a gated `post_test_composition` native transaction hook
  (`GPUI_NATIVE_E2E=1`) and callback/queue/decoder regression tests.

### Changed

- Windows `Host::next_event` and `Host::dispatch` decode composition records
  without changing the typed editor FIFO. The portable composition session and
  `GPUI_WINDOWS_FIELD_IME` editor session cannot both be armed; the second
  owner receives Busy.

### Fixed

- Windows composition consumes Enter and Escape while active and suppresses
  `WM_CHAR` / `WM_IME_CHAR` until the commit END, preventing duplicate key and
  text delivery. Focus loss, disable, destroy, and stop cancel native marked
  text.
- Keep the IMM32 association after a portable finish so the next composition
  can start without re-enabling the client. Delayed composition payloads are
  ignored until a fresh start, an empty marked preview still produces a
  terminal Commit, and a transport failure publishes Cancel before disarming.

### Deprecated

### Removed

### Security

### Migration

- Windows composition is opt-in per window and remains default-off. Callers
  must enable it explicitly and keep the logical caret rectangle current for
  candidate placement. Exhaustive `EventKind` matches already needed a
  `Composition` arm since 0.10.0.
- The public `TextInput` and `DirectKeyboardText` capabilities are unchanged;
  do not infer text-input support from composition availability.
- Composition and full `EditorEvent` sessions are mutually exclusive. Use
  ordinary `next_event` for composition; public `next_editor_event` returns
  `Busy` while composition owns ingress. Each event has its own native sequence
  and captured window. Direct keyboard text is disarmed on opt-in.
- `finish_text_composition` resolves cached preedit and fences the native epoch
  while retaining opt-in; disabling ends the session. Re-enable direct text
  explicitly when leaving composition mode. During a leave fence this request
  is deferred until old IME input can no longer be admitted.

### Limitations

- Windows composition evidence is synthetic (event queue, WndProc, and a fake
  IMM layer). Physical Microsoft IME, candidate placement at real DPI, the dsh
  desktop integration, and the full focus/settings/session-switch acceptance
  remain pending.
- No full editor, surrounding text, reconversion, clause styling, or
  attributed replacement range is added.
- Wayland text-input-v1 only; X11/XWayland and v2/v3 are unchanged. The existing
  transport retains its stricter 4096 UTF-8 byte ceiling, in addition to the
  portable 16,384/65,536 UTF-16 preedit/commit maxima.
- There is no surrounding-document contract. Commits carrying deletion or
  postinsert cursor metadata are discarded and cancel an active preview;
  they are not applied or advertised as supported.
- Application-requested commit uses cached preedit, not an IME-selected
  candidate. Candidate placement, physical IBus/Mozc and compositor E2E are
  not qualified by callback fixtures. See [Wayland IME](docs/ubuntu-ime.md).

## 0.10.0 - 2026-10-19

This pre-1.0 feature release adds a bounded macOS text-composition transport.
It does not add a general editor, Windows/Linux IME, accessibility, or a
platform support-tier promotion.

### Added

- Add `primitives.CompositionEvent` (`Start`, `Update`, `Commit`, `Cancel`) and
  `platform.EventKind::Composition`. The value is document-owner input, not
  element-routed key/pointer input.
- Add `platform/macos.Host::set_text_composition`,
  `set_text_composition_caret`, and `finish_text_composition`. The macOS host
  implements `NSTextInputClient`, bounds preedit/commit sizes, places the
  candidate window from a caller-supplied logical caret rectangle, and resolves
  Enter/Escape while marked text is active.
- Add the opt-in `Host::post_test_composition` E2E hook. It drives the same
  `NSTextInputClient` callbacks as AppKit.

### Changed

- macOS `keyDown` routes non-Command keys through `interpretKeyEvents` while
  composition is enabled. Command shortcuts remain normal key events, and the
  previous key path is unchanged when composition is disabled.

### Fixed

- Enter commits marked text without also reaching the application, and Escape
  cancels marked text without clearing the application draft.

### Migration

- Exhaustive `EventKind` matches must handle `Composition`. The event is
  additive on Apple platforms, but existing source matches may need a wildcard
  or an explicit no-op arm.
- The macOS composition client is disabled by default. Callers must enable it
  per window and keep the caret rectangle current for candidate-window placement.

### Limitations

- Synthetic `NSTextInputClient` coverage passes in the native E2E. Real Kotoeri
  qualification was not completed in the headless harness; do not claim Japanese
  IME support until that run is recorded.
- Windows IMM32, Linux/Wayland, X11, accessibility, and full editor behavior
  remain unchanged.

## 0.9.0 - 2026-10-18

This pre-1.0 feature release adds reusable Windows application helpers and
deterministic Windows input hooks. Native hosts remain experimental; this
release does not promote a platform support tier or satisfy the pending 1.0
production-readiness gates.

### Added

- Add `platform/windows_app` reusable Windows application helpers: bounded
  DirectWrite scene-label measurement, `TextField` measure/admit/hit callbacks,
  cursor state, window configuration, and a one-window `app.WindowView` runner.
- Add opt-in Windows `Host::post_test_key` and `Host::post_test_click` E2E
  input hooks that enqueue through the production event queue and decoder.

### Changed

- Windows printable shortcut chords with Control/Alt/Meta now produce one
  `Character` key-down event in addition to committed `WM_CHAR` text, so
  applications can implement Ctrl-based commands. The event is emitted from a
  single WndProc path and the character is translated through the active
  keyboard layout.

### Fixed

- Windows no longer commits C0 control characters from `WM_CHAR`, preventing
  Enter/Tab and Ctrl chords from inserting control characters after their
  key-down event.

### Deprecated

### Removed

### Security

### Migration

## 0.8.0 - 2026-10-17

This pre-1.0 feature release includes the reusable native application APIs and
portable layout, input, and paint additions since 0.7.2. Native hosts remain
experimental; this release does not promote a platform support tier or satisfy
the pending 1.0 production-readiness gates.

### Added

- Add a reusable portable native application runtime (`app/`) with a
  `WindowView` trait, sampled `WindowMetrics`, close/exit policy, event
  sequence checks, frame viewport/scale validation, bounded ticks, and
  after-present/idle hooks. The runtime is generic over the shared
  `platform.Backend` contract.
- Add a deterministic `scene.SceneBuilder` with monotonic item IDs, reserved-ID
  ranges, external item merging, clip-chain deduplication, border quads, and
  measured horizontal/vertical text alignment.
- Add `platform/macos_app/` helpers for reusable macOS applications: CoreText
  measure/admit/hit callbacks for `TextField`, a bounded scene-label painter
  cache, cursor state, and one-window startup over the shared app runtime.
- Add `platform/testing` frame analysis helpers (logical-pixel comparison,
  region diffs, ink counts) and a deterministic `ScriptedBackend`.
- Add `TextFieldPaintPalette` and `TextField::paint_items_with_palette` while
  preserving the existing default field scene byte-for-byte.
- Add `script/build_macos_app.sh` for reusable macOS app-bundle builds, smoke
  runs, frame artifact conversion, and PID/log handling.

- Add immutable caller-supplied Button paint palettes with ten RGBA roles and
  an additive paint entry point, preserving default scenes, geometry, validation,
  and input behavior. (`docs/button-paint-palette.md`)

- Add bounded measured anchored attachments with all eight anchors, explicit
  Local/Window positions, SnapToWindow fitting with an optional scalar margin,
  two-stage offset rounding, stable nonnegative flat deferred priorities,
  viewport clips, and preserved structural input identities. Priority defaults
  to zero; nested deferred attachments and unsupported compositions fail
  explicitly.
  (`docs/anchored-deferred.md`)

- Add typed `DragSession[T]` source/target bindings with shared one-shot drop
  consumption, explicit cancellation, detached snapshots, and validation that
  preserves state on errors. The existing immutable `DragGesture` behavior is
  unchanged. (`docs/drag-session.md`)

- Add two-axis element scroll viewports with retained caller-owned offsets,
  layout-derived limits, ancestor scene/hit clips, and bounded wheel updates.
  Add same-topology, non-scroll `ElementTree::with_layout_bounds` refresh that
  preserves the exact focus acquisition. (`docs/element-scroll-viewports.md`,
  `docs/element-layout-bounds.md`)

- Add explicit signed tab indices and tab stops, next/previous traversal,
  keyboard/mouse input modality, focus-visible queries, and hover policy.
  Hosts still choose when to traverse and update modality.
  (`docs/conformance-focus-traversal.md`)

- Add the headless `text_session` composition-owner seam with checked delivery
  targets, explicit rearm/rebind/close, and stale/replayed ingress rejection.
  This does not add a native IME route or qualify Japanese input.
  (`docs/text-session.md`)

- Add an experimental Linux/X11 native host implementing the shared backend
  and frame-readback contracts, with bounded frame-readiness checks. This does
  not establish a production X11 support tier. (`x11/`)

- Add canonical floating-point solid/gradient paints, rounded quads and bounded
  convex polygons, element paint bindings, and bounded reference rasterization.
  Existing Quad/Text/TextRun serialization is unchanged. Native presenters
  explicitly reject enhanced paint instead of dropping or substituting it.
  (`docs/enhanced-paint.md`)

- Add an opt-in live focus-scope session with checked revision admission, bounded
  nested modal lifetimes, destructive suffix teardown, exact focus restoration,
  scoped event/wheel routes, and explicit interaction cancellation hooks.
  (`docs/focus-scopes.md`)

- Add bounded explicit equal-fraction grid layout, opt-in mixed flex/grid trees,
  and deferred container queries with per-request one-shot prepaint, global
  generated-tree validation, physical overflow, and absolute device-edge
  snapping. (`docs/grid-container-query.md`)

- Add bounded vertical uniform lists with real recursive prototype measurement,
  lazy visible-row layout, checked stable IDs, complete scroll extent, existing
  scene/input clips, and one-shot row click sessions. (`docs/uniform-list.md`)
  Fractional endpoints are bounded before integer conversion and factory calls,
  including tiny positive viewports at maximum item counts.

- Add optional signed tab-group prefixes independently of handle tab indices,
  with global lexicographic traversal, stable preorder ties, preserved focus
  ownership, and linear shared-prefix storage. (`docs/conformance-tab-groups.md`)

- Add independent physical horizontal and vertical flex gaps to direct containers
  and recursive styles, including builder resets, intrinsic sizing, and device-scale
  snapping. (`docs/conformance-axis-gaps.md`)

- Add space-between/space-around/space-evenly wrapped-line content distribution,
  preserving natural line sizes, safe overflow, and nested device-scale layout.
  (`docs/conformance-content-distribution.md`)

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

- Existing public function signatures remain available. New enum cases and
  element metadata can require updates to exhaustive matches or code that
  depends on record shapes; use the public constructors/builders and check
  consumers against the updated generated interfaces.
- Update pointer-edge expectations: hit bounds and scroll clips are half-open,
  so right/bottom edges and zero-area nodes no longer receive hits.
- Revalidate layout snapshots that relied on overflowing center/end items being
  clamped to zero, full allocation by fractional flex factors, or pre-limit
  flex distribution. The corrected behavior is documented in the conformance
  guides linked above. Device-scale layout remains opt-in.
- New tab-stop metadata defaults to disabled; hosts must opt in and explicitly
  route traversal and input modality. Rebuilding an element tree still creates
  a new focus lineage; use the bounded retained-geometry API only when its
  same-topology, non-scroll checks succeed.
- Enhanced paints are opt-in. Keep native frames within the legacy v1 subset
  until a backend advertises and validates a broader implementation; the new
  paint model does not imply Metal, D3D11, GLES, or browser GPU parity.
- The reusable macOS app helpers provide bounded CoreText labels and TextField
  callbacks. They do not add committed text input/IME, native menus, a general
  accessibility tree, multi-window orchestration, or renderer recovery.

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

## Bounded enhanced paint (Stage B)

- Extend the canonical scene with validated two-stop Srgb/Oklab gradient and
  float-solid rounded-quad/convex-polygon paints, preserving legacy snapshot bytes.
- Add current-geometry element paint bindings, explicit fallible legacy-subset
  projection, and early native unsupported-paint guards.
- Add bounded core-owned shader-linear sampling and ordered reference raster runs
  for the explicitly qualified software WebGL2 output profile. Native rendering
  and edge antialiasing remain unsupported/unqualified. See docs/enhanced-paint.md.
