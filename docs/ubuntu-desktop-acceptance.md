# Ubuntu desktop acceptance boundaries

This is a bounded VM smoke record and a list of remaining release gates, not
production-readiness approval. The headless renderer/lifecycle suite and the
historical paired kiosk-shell benchmark do not substitute for these gates.

## VM smoke profile

The application sources at `dedac3deb92ce64a44efe2038757b418e8efc2d4`
(tree `0fdfe726a77529d76bdf91dd72d6420dd52bb9e6`) were tested without app-source
changes. The accompanying font-preflight/dependency changes were present.
Evidence is retained in the [validation session](https://app.devin.ai/sessions/f325270920834084acde8bc525db234e).

- Ubuntu 24.04.5 container; Weston 13.0.0-4build3, X11 backend, desktop-shell,
  GL renderer; Mesa 25.2.8 llvmpipe.
- Authenticated host Xephyr (Ubuntu package 2:21.1.4-2ubuntu1.7~22.04.16), with
  MIT-SHM disabled on that private display. Direct container-to-host X rendering
  could not attach shared memory. The private display avoids that transport;
  neither X authentication nor container IPC isolation was relaxed.
- Two virtual outputs, each at scale 1; no physical GPU/display qualification.
- Pango 1.52.1, Fontconfig 2.15.0, MoonBit `0.10.14+7d59c7ec9`;
  DejaVu Math TeX Gyre SHA-256
  `75a6cb527b0175f9d13af29c33a6915ae38645016c6fe9881653155cd1f62485`.
- Field executable SHA-256:
  `d437026ae334f9a862b4d594ad7dc8619f7079688fce0c1c19e8e15362367ea2`.
- Button executable SHA-256:
  `9404b53f1b49bbaa2f1ebd9e977bf27c42e983c9944a09cbf8d801a2ef434d39`.

Actual GUI key/mouse events were checked against rendered pixels, Wayland
delivery, and the field's opt-in read-only accepted-presentation observer.
No clipboard replacement or direct model callback substituted for typing.

| Area | Observed result | Remaining acceptance requirement |
| --- | --- | --- |
| Direct input | Click focus and Ctrl+A selected `Hello 日本`; individual a/b/c presses produced `abc` with caret `(3,3)`. Left/Right, Backspace, Undo/Redo, blur without mutation, and refocus passed. | Repeat on the intended real desktop/compositor and physical input devices; this selected smoke is not blanket input qualification. |
| Button | Mouse, Enter and Space activation passed; isolated click incremented once. Escape exited with code 0 while Weston stayed alive. | Native OS accessibility and other desktop profiles remain separate. |
| Virtual output transition | Real window drag moved the field from output9 to output10, with enter/leave delivery and continued rendering/typing (`acde`). Both outputs were scale 1. | Real mixed-DPI displays, scale changes, output removal/hotplug, and pointer/caret geometry across transitions remain unqualified. |
| Field normal close | Unverified: Alt+F4 and Super+F4 did not close the undecorated field in this shell. Cleanup stopped the auxiliary container. | Establish a supported compositor close route, observe close delivery and graceful app exit, with compositor remaining alive. Do not count forced cleanup as a pass or infer an app defect from an unconfirmed shell binding. |
| Japanese IME | Blocked: no pinned Debian13 profile, IBus or Mozc; the available compositor was Weston13. | Provision and independently qualify the exact Weston14/IBus1.5.32 synchronous privileged Wayland adapter/Mozc stack, then test genuine GPUI preedit, conversion, commit, cancel, focus fences, undo/redo and candidate placement. A stock-editor result is not GPUI acceptance. See [IME scope](ubuntu-ime.md). |
| AT-SPI / screen reader | Blocked by missing implementation: the Ubuntu Button adapter is in-process and transport-free, with no D-Bus/AT-SPI bridge. | Implement the OS bridge, then prove discovery, role/name/state/bounds, focus notifications, Invoke routing and stale-node rejection through a real assistive client and screen reader. Installing a reader alone cannot qualify the current adapter. |

The missing areas above are **not accepted or silently waived**. This branch
remains an experimental native slice and the integration PR remains Draft.
Promoting it to a production support claim requires evidence for the intended
release's desktop/input/IME/accessibility/display scope, or an explicit approved
narrower release scope that lists unsupported features. This record does not
make that release decision.
