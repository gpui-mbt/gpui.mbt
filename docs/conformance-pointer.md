# Pointer boundary comparison

The first local GPUI Conformance Suite slice executed the same independently
authored rectangle layout and pointer samples against Rust GPUI
`zed-industries/zed@d9afb21688e04f89d9e94d96d33eb530aef90886` (0.2.2) and
gpui.mbt `f9f59fe074da3858ca82fe1d5fadd84cd17f0438` (0.7.2), on macOS 26.5.2
arm64. Rust used `TestAppContext` and `VisualTestContext` mouse listeners;
MoonBit used its element request-layout/prepaint and input-dispatch paths.

Two child elements were `[0,0,20,30]` and `[25,0,25,40]` in a 100×60 root.
GPUI dispatched no child listener for `[20,10]`, `[10,30]` or `[50,10]`;
gpui.mbt selected child 2, 2 or 3 respectively. With children sized 0×30
and 25×0, GPUI dispatched no child listener for `[0,10]`, `[10,0]` or `[0,0]`;
gpui.mbt selected child 2, 3 or 3. Interior and left/top samples agreed.

Element pointer coverage now uses `[left,right) × [top,bottom)`, matching these
observations and upstream's `Bounds::contains` at the pinned commit. This
affects `hit_test` and pointer/input dispatch. The public geometric
`Rect::contains` operation retains its documented closed-edge behavior.
This is an independently implemented behavior adjustment; the provenance
record is in `upstream.json`.

`element/hit_boundary_test.mbt` covers near/far edges, zero width/height/area,
root boundaries, pointer-event routing, and adjacent siblings in reversed
paint order. The far-edge test fails on the baseline before the adjustment.

The suite lives in `gpui-mbt/gpui-conformance`. Its retained result directories
contain both executable hashes, source revisions/trees, toolchain and platform
versions, raw process output and field-level comparison results. Local suite
results initially had 6 passing, 2 mismatching, 1 unsupported and 2 unverified
scenarios. Native windows, GPU pixels, physical input and IME are outside this
headless pointer evidence; it does not establish general GPUI compatibility.
