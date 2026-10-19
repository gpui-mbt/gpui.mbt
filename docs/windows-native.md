# Windows native backend

Issue [0008](../issues/open/0008-windows-native-backend.md) now has an
experimental first-window implementation. `windows/` adapts the shared host,
window, event, and `SceneSnapshot` contracts to Win32 and D3D11. The C boundary
owns HWND, DXGI, and D3D11 objects; MoonBit callers exchange framework values.
The backend is not a Windows support-tier claim.

## Build and run

Use the pinned MoonBit `0.10.14+7d59c7ec9` toolchain and a Visual Studio native
tools environment. Install Python 3 with `python3` available on `PATH`; Moon
invokes the module's prebuild hook for native builds, including Windows, where
the macOS-specific hook is a no-op. From PowerShell:

```powershell
./scripts/test_windows.ps1
moon run examples/windows --target native
```

The native runner records its toolchain output under `_build/windows-native/`
and field-specific checks under `_build/windows-text-field/`. It checks
formatting and types, runs deterministic tests that work on any native host,
then on Windows runs the HWND/D3D11 tests and GUI smokes.
`./scripts/test_windows.ps1 -PortableOnly` runs only the portable checks on
Linux or macOS; those tests verify translation, snapshot serialization, error
mapping, and the explicit non-Windows `UnsupportedCapability` stub. They do
not simulate a Windows window or GPU.

The matrix also checks the reusable shared Button adapter and runs its
completed-frame pixel smoke. See the [Button fixture guide](windows-button.md)
for its demo controls, evidence boundary, and the separately gated visible
SendInput runner.

The Windows workflow initializes the MSVC environment and pins MoonBit and its
core library. MoonBit selects the Windows native compiler from that environment.
The script also compiles the C shim and standalone clipboard fixture against
the installed Windows SDK. It saves the fixture as
`_build/windows-native/clipboard-fixture.exe`, passes its absolute path only to
the opt-in native E2E, and retains its build and test logs in the evidence
directory. The
workflow retains both evidence directories as an artifact. It runs default and
opt-in IMM field smoke in separate processes, as well as the native E2E and
shared backend conformance checks, because each exercises the process-wide
host. Wake and exit messages carry the host token, so messages queued during
teardown cannot affect a later host generation. The
hosted [Windows Server 2025 run](https://github.com/f4ah6o/gpui.mbt/actions/runs/37189457500)
for PR head `a1f6e523dc41317064c5657179baa20456dcf6b1` passed the MSVC shim build,
the portable tests (6/6), native GPU E2E (1/1), shared backend conformance
(1/1), and the example app smoke. That run predates the text adapter, field
work, and bounded independent-process clipboard fixture below. It is runtime
evidence only for the earlier experimental one-HWND slice on that hosted
configuration; it does not promote a Windows support tier or production claim.

For repeatable local acceptance, run
`./scripts/run_windows_actrun.ps1 -PythonPath <python.exe>` from PowerShell.
It runs the checked-in Windows workflow through the pinned `@mizchi/actrun`
version in local-workspace mode, then runs a separate portable profile for
all-target checks, WasmGC/JavaScript/Wasm tests, the contract-checker tests,
and repository contract validation. The wrapper verifies the npm integrity
and CLI SHA-256 from the shared actrun lock, loads the pinned local MoonBit
toolchain and MSVC environment, and saves task records and logs under
`_build/windows-actrun/`. It requires Node/npm, Python 3, Git for Windows GNU
utilities (`usr/bin/env.exe`), the pinned MoonBit toolchain under
`_build/tools/moonbit`, and Visual Studio's x64 MSVC/Windows SDK. The workflow's
checkout, toolchain setup, and
artifact-upload actions are skipped because the local workspace and tools are
already prepared. The pinned actrun release assumes POSIX paths and `.script`
PowerShell files on this host, so a small local Node preload normalizes its
workspace path and copies only generated step scripts to `.ps1` before
execution; the third-party CLI remains unmodified. The wrapper checks the
expected workflow task IDs, zero exit codes, run-record source head, and
unchanged checkout state. This host adaptation does not replace the actual
workflow steps.

The basic `examples/windows` app opens one visible 640 by 400 logical-pixel
window and paints a dark background with a blue quad. Press Escape or use the
system close button to exit. The CI smoke sets `GPUI_WINDOWS_SMOKE=1` and exits
after a completed GPU frame. D3D11 first tries the hardware driver and falls
back to Microsoft's WARP software driver when hardware device creation fails.

## Implemented slice

- One process-wide host and at most one live HWND at a time. Window IDs are
  monotonic; repeating destruction of the most recently destroyed window in
  the same host generation is harmless, while other stale handles remain
  invalid. Later host starts are supported when the process already has the
  required per-monitor-v2 DPI context.
- An owner-thread message pump, posted wake and exit messages, typed errors,
  close-request versus destroy events, title changes, client-size changes, and
  idempotent stop. Wake and exit posting remain safe while stop releases the
  host; HWND and GPU operations reject calls from the wrong thread.
- A DXGI swap chain and D3D11 renderer. The v1 subset draws ordered solid-color
  quads with affine transforms, opacity, premultiplied-alpha blending, and
  intersected rectangle clips. Nonzero viewport origins and unsupported scene
  resources return typed errors. D3D11 event-query completion of submitted
  draw work produces `FrameCompleted` (not a display-scanout timestamp); a
  second frame is rejected while one remains pending.
- Per-monitor-v2 DPI awareness and logical viewport metrics. A DPI transition
  updates and queues the scale event before later resize/input events. Pointer
  coordinates are reported in logical units. The opt-in native test exercises
  ordinary resize; visual movement between physical monitors at different DPI
  is still pending.
- A copied `Host::display_snapshot()` lists up to 16 current Win32 monitors.
  Monitor and work-area rectangles and current mode dimensions are in physical
  pixels in the host's per-monitor-v2 coordinate context. Effective DPI is
  reported for the monitor containing the current HWND through
  `GetDpiForWindow`; other monitors have no DPI value in this API. Refresh is
  the integer-Hz value reported by `DEVMODE`, with zero meaning unavailable or
  the OS default. Orientation is degrees or `-1` when Win32 does not report it.
  Each entry marks the primary monitor and the monitor nearest the current
  window. Enumeration order is temporary; the API does not report a persistent
  device ID or physical panel dimensions, and the individual Win32 queries do
  not form an atomic display-change transaction.
- Basic pointer movement, mouse buttons, vertical/horizontal wheel, focus,
  common navigation keys, committed `WM_CHAR` text events, and arrow/hand/text
  cursors. Printable shortcut chords with Control/Alt/Meta also produce a
  single `Character` key-down so applications can distinguish `Ctrl+K` from
  committed text; plain typing still arrives only through `WM_CHAR`. The
  shortcut character is translated through the active keyboard layout, so
  punctuation follows the user's layout instead of a fixed US mapping, and
  Ctrl+Alt (AltGr) is left to `WM_CHAR`. C0 control characters are not
  committed as text. Wheel deltas are attached only after their event slot is
  accepted, so queue or sequence exhaustion leaves earlier input records
  intact. Key labels are not a source of committed text. The public
  `TextInput` capability remains unadvertised; the bounded field example uses
  the existing committed-text event path directly.
- Native Unicode plain-text clipboard read/write. The Windows E2E round-trips
  Japanese and emoji through `CF_UNICODETEXT`; invalid UTF-8, invalid UTF-16,
  unterminated clipboard buffers, and embedded NUL input are rejected instead
  of being silently truncated. Titles and clipboard writes are capped at 1 MiB
  of UTF-8 input. Clipboard reads bound their UTF-16 scan to the HGLOBAL and
  16 Mi code units; the MoonBit wrapper caps the converted UTF-8 result at 16
  MiB. The opt-in E2E also uses a separately compiled Win32 process to compare
  the exact Japanese, emoji, combining-mark, and multiline `CF_UNICODETEXT`
  payload written by gpui, then to publish its own exact payload for the
  production `Host::read_clipboard` path. While that fixture owns an actual
  `OpenClipboard` lock, production reads and writes return `Busy`; after release
  the fixture sentinel remains intact and normal read/write operations recover.
  A second bounded fixture hold expires, closes the clipboard, and is reaped.
  Child launch uses the configured absolute executable path, a verified process
  image, and a PID/nonce pipe handshake. The helper never launches through a
  shell; clipboard acquisition retries for at most two seconds, parent startup
  and exit waits are five seconds, and the independent lock expires after six
  seconds. This is evidence for the exact fixture payload and Win32 lock
  behavior on the tested host; broad third-party application compatibility
  remains open.
- Opt-in native E2E readback copies the swap-chain target to a staging texture
  and checks known background/accent/background pixels before presentation.
  The test also checks GPU completion, resize rejection for an old viewport,
  Unicode title/clipboard handling, wrong-thread rejection, stale handles,
  close/destroy ordering, cross-thread wake during stop, and repeated
  create/destroy plus host restarts.

The public capability handshake reports native windows, logical viewports,
quad frames, bounded grayscale text frames, frame scheduling, pointer/keyboard
input, clipboard, and cursors. `GrayscaleTextFrames` advertises scene painting
only; it does not imply text input or IME support. `DirectKeyboardText`,
`TextInput`, accessibility, menus, cross-thread command submission, and
renderer recovery are not advertised. An explicit renderer-recreation method
exists for experimentation, but no loss-injection or automatic recovery
state-machine evidence exists.

## Reusable Windows app helpers

`platform/windows_app` mirrors the macOS-only `platform/macos_app` package for
reusable one-window applications:

- `WindowsWindowConfig` validates a bounded title and logical size.
- `run_main_window` preflights native-window, quad, pointer/keyboard, and
  optional grayscale-text capabilities, creates the window, runs the shared
  `app` `WindowView` loop, and destroys the window on a failed or `MaxTicks` run.
- `WindowsTextPainter` caches bounded DirectWrite measurements and appends
  measured, aligned scene labels through `SceneBuilder`.
- `WindowsTextFieldAdapter` supplies DirectWrite measure/admit/hit callbacks for
  `controls/text_field` and `controls/command_palette`.
- `CursorState` suppresses repeated `SetCursor` calls.

The package is a convenience layer over the existing `windows` backend and
`platform/windows_text`; it does not add a new renderer or a support tier.

`windows.Host::post_test_key` and `post_test_click` are opt-in E2E hooks gated
by `GPUI_NATIVE_E2E=1`. They enqueue through the production event queue and
decoder, not through physical `SendInput`; they exist so native smoke tests can
drive shortcuts, typed text, and clicks deterministically. Physical input, IME,
and UI Automation remain outside this evidence boundary.

## Bounded text rendering and field example

`platform/windows_text` is a private DirectWrite adapter for copied text
measurement, hit testing, and scene-run admission. The field example uses
Segoe UI at 18 logical pixels for both geometry and rendering. Geometry calls
can name another family, but scene paint is fixed to Segoe UI so layout and
rasterization use the same supported font. This is a bounded plain-text slice:
one line, left-to-right geometry, known glyphs, and grayscale glyph coverage.
Runs with unsupported right-to-left/bidi geometry, missing glyphs, color
glyphs, or unsupported raster output fail admission. It does not provide
general script shaping, wrapping, bidi layout, color-font rendering, or a
system-wide text service.

The public `SceneSnapshot` remains schema v1. Quad-only snapshots keep their
legacy private 19-double-per-item frame representation. Frames containing text
use private mixed-frame ABI v2: a five-value logical viewport/scale header,
ordered 25-double item records (kind plus the existing item fields and text
metadata), and a borrowed UTF-8 sidecar. Record order is scene order. Bounds,
text origins, clips, and viewport use logical coordinates; the backend applies
the window scale when creating D3D11 geometry and scissors. Glyph masks are
item-local and transformed with the item. D3D11 uploads them as `R8_UNORM`
grayscale coverage textures. The DirectWrite shim has private measurement/hit
ABI v1 and raster ABI v2; none of these private wire formats changes the
portable scene schema. Raster calls carry the window's physical-pixels-per-DIP
scale. DirectWrite creates the glyph mask at that density, while run bounds
and scene geometry remain in DIPs; mask dimensions, tile clipping, and
aggregate pixel budgets use physical pixels, while normalized UVs derive from
those physical tile bounds. Measurement and hit testing continue to use
logical coordinates. The public `admit_scene_text_run_at` helper checks at 1x;
callers that need scale-specific preflight can use
`admit_scene_text_run_at_scale`, and presentation always rechecks limits at
the actual window density.

The renderer rejects frames above 64 text items, 4 KiB of UTF-8 per run,
256 KiB of copied UTF-8 per frame, 32 logical pixels per font, and a 2048 by
128 logical-pixel item clip. Raster density is bounded to 0.25–8 physical
pixels per DIP. The aggregate glyph-mask budget is 262,144 physical grayscale
pixels per frame, with each mask dimension at most 2048 physical pixels.
The adapter's standalone measurement input is capped at 16 KiB and 512 pixels
font size. These limits bound allocation and raster work; they are not a claim
that arbitrary text is supported. DirectWrite comes from the Windows SDK and
`dwrite.dll`; glyph masks are painted by the existing D3D11 renderer and its
`d3d11.dll`, DXGI, and shader dependencies.

`examples/windows_text_field` is a visible, single-line field over the
portable `TextField` control. It provides pointer placement/selection,
committed text insertion, navigation/edit commands, bounded undo/redo, and
clipboard actions. Adjacent committed text and same-direction deletion
commands coalesce into one undo step; navigation and selection changes end a
group. The Windows controller suite checks typing, Backspace, forward Delete,
and the boundary between edit groups. Paste checks the field revision and
actual native focus around the clipboard read; in experimental-session mode it
also checks the native editor epoch. Cut changes the field only after a
successful clipboard write. If layout, scene admission, or presentation fails,
the example retains the pending value while Busy and rolls back the entire
field/history to the last shown snapshot after a hard rejection.

The script `scripts/run_windows_text_field.ps1` verifies the pinned MoonBit
compiler, records revision/compiler/MSVC and command logs in
`_build/windows-text-field/`, runs portable owner tests, and offers `Smoke`,
`Build`, and interactive `Run` modes. Smoke exits only after a field frame is
accepted and a `FrameCompleted` event arrives. Its semantic state log is useful
for controller automation but is not a text-pixel oracle. The backend readback
test exercises DirectWrite/D3D11 text-mask coverage, clipping, mixed-item order,
coordinate mapping, and rejection atomicity. That checks the renderer; the
field's exact caret and selection pixels have not been independently qualified
by the smoke hook. Smoke does not type characters or exercise composition.

### Private experimental IMM32 input

Set `GPUI_WINDOWS_FIELD_IME=1` to opt into the private Windows editor session
used by the field example. It remains off by default, private to the Windows
backend, and does not change the public capability handshake. Normal
`WM_CHAR` records represent committed text; physical key labels are commands
only and never insert text. While a composition is active, IMM owns ordinary
navigation and Enter. Empty marked text remains an active transaction even
though the field preview shows the original committed value.

The copied FIFO records carry the window, a stable positive field-owner
generation, a positive epoch, and a monotonically increasing sequence that is
exact through `2^53 - 1`. Replacement ranges and marked-cursor offsets are
UTF-16 code-unit offsets into the copied committed snapshot. Each text or
attribute payload is capped at 4 KiB, queued copied text and attributes at
1 MiB, and the FIFO at 4096 records. Exhaustion fails closed. An accepted IMM
result is committed immediately as one undoable edit. If a single native
message also carries new preedit, it produces an ordered result commit, a new
transaction at the post-result caret, and the marked preview. End or cancel
discards only the current unconfirmed preview; it never retracts an accepted
result. Focus loss invalidates the epoch, and the app rearms only after focus
and a newly accepted field frame.

Win32 IMM messages do not carry an application epoch. The adapter validates
the current focus/context, cancels and disassociates/re-associates the input
context on a fence, drains enumerated queued IME messages, and requires a fresh
composition start. A stale message posted after that drain and after a new
start cannot be distinguished from a current one by Win32. The epoch/sequence
checks fence copied application records, but cannot provide source-epoch guarantees
for every delayed OS message. Synthetic controller and queue tests are not
evidence of a real Japanese IME, candidate-window, or driver integration; that
qualification remains pending. The public `DirectKeyboardText` and `TextInput`
capabilities remain unsupported.

### Opt-in portable text composition

`windows.Host::set_text_composition`, `set_text_composition_caret`, and
`finish_text_composition` add a bounded IMM32 transport for the portable
`primitives.CompositionEvent` values. It is disabled by default and is separate
from both the private field session above and the public `TextInput`
capability. Only one IMM owner may be armed at a time: enabling composition
while a field session is armed returns Busy, and `begin_text_session` returns
Busy while composition is armed.

Start, Update, Commit, and Cancel are published as `platform.EventKind::Composition`
on the ordinary `next_event` / `dispatch` queue. The private ABI uses kind 17,
the preedit cursor in field 4, UTF-16 units in field 5, code 0..3 in field 8,
and a copied UTF-8 sidecar. Preedit text is capped at 16,384 UTF-16 units,
commits at 65,536 units, and each sidecar at 256 KiB within the existing 1 MiB
pending-payload budget and 4096-record queue.

`set_text_composition_caret` takes logical client coordinates. The native side
converts them with the window scale and applies `ImmSetCompositionWindow` and
`ImmSetCandidateWindow` best-effort; a placement failure does not break an
active composition. While a composition is active, Enter and Escape are
consumed so the application does not receive a duplicate key event, and
`WM_CHAR` / `WM_IME_CHAR` are suppressed until `WM_IME_ENDCOMPOSITION` so the
committed text is not inserted twice. Focus loss, disable, destroy, and stop
cancel the native composition and clear the stored marked text.

The synthetic native E2E and the C-level WndProc staging test run only with
both `GPUI_WINDOWS_E2E=1` and `GPUI_NATIVE_E2E=1`:

```powershell
moon test --package f4ah6o/gpui/windows --target native --deny-warn `
  --no-parallelize --filter "Windows synthetic IME composition preserves event order"
moon test --package f4ah6o/gpui/windows --target native --deny-warn `
  --no-parallelize --filter "Windows IME composition staging suppresses duplicates"
```

`scripts/test_windows.ps1` runs both filters in the opt-in native profile. These
are queue and WndProc qualifications, not physical IME acceptance. The physical
procedure remains: run an interactive Windows 11 desktop with Microsoft IME,
enable composition through the application's opt-in gate, type `にほんご`,
convert and commit `日本語`, press Escape to cancel a preview, verify
commit-then-send, and verify that focus loss, Settings, New, and session
switches clear the native marked text. Candidate placement must be recorded at
100% and 150% / 200% DPI. Synthetic passes must not be reported as physical
acceptance.

## Remaining support gates

This remains a one-window development slice. Physical Japanese IME behavior,
candidate placement, UI Automation accessibility, menus, broad DPI/display
coverage, automated physical-GPU coverage, fault-injected renderer recovery,
sustained resource-lifetime testing, and performance evidence remain open. The
portable composition transport has synthetic queue/WndProc coverage only; the
dsh desktop integration and real Microsoft IME acceptance are still pending. The
historical hosted run above verified deterministic D3D11 quad readback, but did
not exercise the text renderer added later and does not establish physical GPU
coverage or desktop performance. Clipboard evidence now includes a separate
Win32 fixture process reading and publishing the tested Unicode payload and
holding a real clipboard lock through Busy/no-clobber/recovery checks. That
evidence is bounded to the fixture's exact `CF_UNICODETEXT` cases on the tested
host; broad third-party application interoperability remains open. Only the
Windows GitHub Actions and pinned local actrun runners are configured;
supported Windows versions, GPUs, and driver combinations have not been
established. Do not infer Tier 1 support from a successful build or smoke.

| Evidence | State |
| --- | --- |
| Portable MoonBit formatting, type checks, and headless tests | Passed locally and in hosted run (6/6) |
| MinGW Windows-header syntax and link check | Locally verified; compile-only, not the MoonBit Windows toolchain |
| MSVC/Windows SDK build, native readback, clipboard and lifecycle E2E, app smoke | Passed in hosted run 37189457500 for PR head `a1f6e523dc41317064c5657179baa20456dcf6b1` |
| Independent Win32 clipboard process: exact Unicode read/write, real-lock Busy/no-clobber/recovery, queued-wake preservation, lock expiry | Passed in the pinned local actrun native profile on 2026-10-07 against implementation source `dfa0695bc1903a55824635a5506f68b377548279`; no fixture processes remained |
| Text-field owner/controller tests | 12/12 passed locally; synthetic geometry/session tests only |
| Current monitor snapshot | Native E2E checks real monitor bounds, work area, primary flag, and the monitor containing the live HWND; portable decoder tests cover copied values and malformed records |
| DirectWrite/D3D11 mixed-frame text readback and rejection atomicity | Passed in local MSVC/D3D11 backend tests; validates renderer pixels, not exact field caret/selection pixels |
| Field startup smoke (default and opt-in session) | Both passed locally through `FrameCompleted`; default epoch 0, experimental session epoch 1; no typing or IME behavior exercised |
| Portable Windows composition transport | Synthetic Start/Update/Commit/Cancel ordering, sidecar copy, finish commit/cancel, WndProc duplicate suppression, candidate geometry, mutual exclusion with the field session, and queue exhaustion pass in the Windows package tests; no physical IME evidence |
| Pinned local actrun execution of the Windows workflow and portable profile | Passed locally on 2026-10-07 against implementation source `dfa0695bc1903a55824635a5506f68b377548279`; native and portable run 1 both exited 0 with all required tasks successful. WasmGC, JavaScript, and Wasm tests were each 382/382; contracts 30/30 plus repository validation; Windows package 12/12; DirectWrite 4/4; field 12/12; native GPU/clipboard E2E and lifecycle 1/1 each; both startup smokes reached `FrameCompleted`. Manifest and task logs: `_build/windows-actrun/manifest.json` and adjacent logs |
| Physical multi-monitor DPI, real IME, accessibility, multi-window and fault recovery | Pending |
| Broad third-party clipboard application compatibility | Pending |
