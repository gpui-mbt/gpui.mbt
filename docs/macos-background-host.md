# Nonactivating macOS host

`Host::start_background()` starts an accessory app and leaves created windows
hidden. It does not call `makeKeyAndOrderFront` or activate the app. Rendering,
window metrics, resizing and destruction retain the ordinary native ownership
and generation checks. `Host::start()` keeps its existing foreground behavior.

A background host can explicitly call `show_window_unfocused(window)` to order
only that owned window behind others. It does not request key status or app
activation. The call is unsupported on a foreground host. A distinct startup
operation makes older native libraries reject the feature instead of silently
using foreground behavior. These operations extend the existing ABI-v1 function
table without changing its shape. Host shutdown destroys only its owned windows.

The conformance fixture uses this path to test real native window lifecycle and
Metal readback while retaining observed visibility/key/activation metadata.
Visible observation is a separate opt-in bounded ready/ack mode. This API does
not grant accessibility, screen-recording or input permissions and does not
qualify external AX/window binding or physical input.
