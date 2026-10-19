# Reverse main-axis flex flow

`FlowDirection::row_reverse()` and `column_reverse()` place source-order items
right-to-left and bottom-to-top, respectively. This independently implemented
bounded extension works in direct, recursive flex, and mixed flex/grid trees.
It does not reorder item arrays, paint commands, input routes, or focus traversal.
The public enum gains two variants: downstream exhaustive matches over
`FlowDirection` must handle them. Rust or MoonBit source compatibility is not
claimed by this addition.

## Contract

- Reversal changes main-axis placement only. Width/height, physical padding and
  border, horizontal/vertical gaps, intrinsic measurement, grow/shrink budgets,
  min/max constraints, and greedy source-order line breaking retain their axes.
- Each wrapped line reverses independently. Wrap-reverse still controls only
  cross-axis line placement and cross-axis alignment.
- `JustifyContent::start()` and `end()` mean physical left/top and right/bottom,
  including signed overflow. Center preserves signed free space.
- Positive distributed free space retains between/around/evenly spacing. A fitting
  space-between singleton sits at the reverse edge; around/evenly center it.
  All three distributed modes fall back to physical start on overflow.
- The existing default remains explicit physical Start. Upstream GPUI with no
  authored justification defaults to flex-relative start; for reverse flow that
  corresponds to this API's explicit End. This is a documented default-policy
  difference, not a claim that absent styles are equivalent.
- Authored dimensions/gaps and final absolute edges continue using the existing
  opt-in device-scale boundary. Raw layout stays binary64; bit-identical binary32
  arithmetic and ULP-scale line-break thresholds are not claimed.

## Evidence

An independently authored 68-case corpus executes actual GPUI headless
Render/layout at `5a5fbe79917971a4d52a96b6ddb04da198a5012e` and the MoonBit
implementation, comparing complete root/child rectangles at device scale 2.
This is an explicit bounded diagnostic pin, consistent with the recent runtime
comparisons; it does not change the repository compatibility target d9afb216.
The candidate run passed 68/68 with zero differences. It covers reverse rows and
columns, asymmetric padding, independent physical gaps, all main justifications,
wrap and wrap-reverse with all seven line-content modes, constrained grow/shrink,
overflow, and fitting/oversized singletons. The suite's
`reverse_flow_scenarios.json`, `build_reverse_flow.py`, and
`run_reverse_flow.py` retain the
reproducible comparison; exact committed identities and final checks accompany
that separate suite change.

[Core tests](../layout/reverse_flow_test.mbt) additionally cover reflection with
physical Start/End exchanged across both axes, three wrap policies, all cross
alignment/content modes and full/partial/no flex budgets; empty layouts;
recursive auto measurement; mixed-tree dispatch; device-scale rounding; and
large finite-ratio physical-edge anchoring in raw binary64 layout. The last
checks are core numeric invariants, not f32/f64 upstream equality claims.
[Element tests](../element/reverse_flow_test.mbt) verify actual reversed hit
geometry while preserving source and paint order.

No upstream implementation, fixture, or asset was copied. This is headless
geometry and portable routing evidence, not GPU pixels, native-window rendering,
physical input, RTL writing modes, full CSS flexbox, or general GPUI parity.
