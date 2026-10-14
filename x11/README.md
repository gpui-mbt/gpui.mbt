# Native X11 backend

Import `f4ah6o/gpui/x11` and call `Host::start()`. The host implements
`platform.Backend` and `platform/testing.FrameReadback`, with the same bounded
scene and direct-keyboard wire contract as the Wayland adapter. It connects to
`DISPLAY` with Xlib and creates an EGL X11 window surface; Wayland is not used.
An X server may itself be Xorg, Xvfb, or XWayland. Running this backend on a
native X server does not require XWayland.

## Scope

- One host and one live window, all calls on the creating thread. Stop is explicit.
- Logical scale 1; server-accepted ConfigureNotify dimensions are authoritative.
- Shared GLES2 quads, transforms, clipping, grayscale Linux text, and readback.
- One FrameCompleted event after each successful EGL swap. This reports renderer
  readiness, not a compositor presentation timestamp.
- XKB server keymap/group lookup, detectable repeat (and legacy repeat pairs),
  locale Compose, copied UTF8 TextInput, focus/epoch fencing, pointer/buttons/scroll.
- UTF8_STRING CLIPBOARD ownership and reads, including ICCCM INCR. Transfers are
  limited to 16 MiB, 3 seconds, and four concurrent outgoing requests. Clipboard
  contents are available while this host owns a live window; no clipboard-manager
  persistence, PRIMARY, or legacy STRING conversion is promised.
- Arrow, pointing-hand, and text cursors. WM_DELETE_WINDOW requests application
  close policy; destroy invalidates the handle and retains a terminal event.

IME/preedit/candidate windows, fractional/per-monitor scaling, multiple windows,
accessibility, menus, and cross-thread commands are not supported. Direct Compose
is not an IME implementation. Xlib connection-loss recovery is not supported;
normal Xlib IO-error behavior can terminate the process on an X-server disconnect.
Scoped X-error traps around clipboard races/teardown restore the prior application
handler; this adapter does not change global locale or install an IO-error handler.

## Build and checks

Dependencies: X11 development headers, EGL/GLES2, xkbcommon, PangoFT2 >=1.50,
fontconfig, pthread, and a C11 compiler. `script/linux_text_cc.py` discovers Linux
text flags through pkg-config. No Wayland protocol generation is needed by this
package alone. Both backends can be linked together: all X11 FFI exports have the
`gpui_x11_` prefix.

Run `tests/x11/run_contract.sh` for strict-warning headless C contract tests. They
mock X calls and never open a display. `GPUI_TEST_CFLAGS` can enable sanitizers.
Native display acceptance belongs in an isolated Xvfb/Xorg harness with real EGL,
XTest input, external clipboard ownership, resize, and WM_DELETE_WINDOW checks.

`GPUI_NATIVE_E2E=1` enables bounded last-frame RGBA readback and stderr diagnostics:
`GPUI_X11_WINDOW` reports PID, XID, width and height after successful creation;
`GPUI_X11_FRAME` reports XID and dimensions only after a successful swap. The window
also sets `_NET_WM_PID`. These diagnostics are off by default and expose no handles
through the portable API.
