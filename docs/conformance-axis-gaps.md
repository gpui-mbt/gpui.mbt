# Independent physical flex gaps

`FlexContainer` and `FlexTreeStyle` now provide `with_gap_x` and `with_gap_y`.
Both return `Result[..., LayoutError]`, like the existing `with_gap` builder.
This is a bounded capability addition; existing equal-gap layouts are unchanged.

## Contract

- `with_gap_x(value)` sets the physical horizontal gap and retains the vertical
  gap. `with_gap_y(value)` sets the physical vertical gap and retains the
  horizontal gap. Zero is an explicit override, not a missing value.
- `with_gap(value)` sets both axes, replacing any prior axis-specific overrides.
  Every builder returns a new value and preserves all unrelated style settings.
- Negative values return `NegativeValue`; NaN and either infinity return
  `NonFiniteValue`. Finite nonnegative fractional values are accepted.
- Row flow uses the horizontal gap between items and the vertical gap between
  wrapped lines. Column flow uses the vertical gap between items and the
  horizontal gap between wrapped lines. Wrap-reverse reverses line placement,
  without exchanging physical axes or changing source order.
- Only the main-axis gap contributes to greedy line breaking, line-local
  grow/shrink/min/max budgets, and main-axis justification. Only the cross-axis
  gap contributes to line-stack extent and content alignment. NoWrap has no
  inter-line gap; empty/singleton sequences have no intervening gap.
- Recursive containers carry both values into child layout. Existing intrinsic
  measurement retains its no-wrap approximation: it adds only the flow-selected
  main gap between children, and no cross gap to the maximum cross size.
- The opt-in [device-scale boundary](conformance-device-scale.md) independently
  snaps both authored gaps before line breaking, intrinsic measurement, and
  flex sizing. Raw layout preserves the authored logical values. Absolute edges
  are still snapped only after the complete nested layout.

For a row container of size 60 by 64 with children of size 40 by 10 and 40 by
14, horizontal gap 4, vertical gap 12, and start item alignment, wrapped child
top coordinates are `0, 22`; wrap-reverse gives `54, 28`. Center content
alignment gives `14, 36`, and space-around gives `7, 43`. The corresponding
column cases transpose the geometry and physical gap settings.

## Evidence and limits

The reference is actual GPUI headless Render/layout at
`zed-industries/zed@d9afb21688e04f89d9e94d96d33eb530aef90886`, using its public
`gap_x`/`gap_y` APIs. The independently authored 36-case corpus covers row and
column flow, nowrap/wrap/wrap-reverse, item and line overrides, explicit zero,
fractional gaps, line breaks, full grow/shrink, content alignment, and bounded
auto cross stretch. Four unchanged controls agree before the addition, while
32 cases expose the missing capability.

Linux x86_64 comparison of engine implementation
`5fd20cf8561aba22feab4e3628cc595ef2f46c7d` and measured local suite snapshot
`5cec1e4e3ca70b3574bee55802022f98bbedd653` records the results below. The identical
suite source was published as `bdd9cfa7974dc184deddb9147f065d55134d6054`.

- Focused comparison: 36 pass, zero mismatch.
- Measured-width negative control: zero pass, 36 mismatch.
- Combined regression corpus: 269 pass, zero mismatch, one existing unsupported
  IME case, and two existing native unverified cases.
- Adversarial comparator checks: 38 pass.
- Nine supplemental subpixel exact-fit probes agree across authored gap snapping
  and line-break thresholds. They are separate from the authoritative 36 cases.

The [independent corpus](https://github.com/gpui-mbt/gpui-conformance/blob/bdd9cfa7974dc184deddb9147f065d55134d6054/axis_gap_scenarios.json)
has SHA-256
`1f834f0f9064cc7d433cfe6977d13a1ac3eaf5f688edcf05ea6c414e2012e95e`.
These are local headless observations, not public CI or native-platform
qualification. Later changes in this engine slice add tests and documentation
without changing the measured implementation.

The [engine regressions](../layout/axis_gaps_test.mbt) additionally exercise
partial grow/shrink, constrained redistribution, every content mode, overflow,
builder order and snapshot preservation, validation and aggregate finiteness,
nested styles, intrinsic sizing, device-scale rounding, and equal-gap controls.

This does not add margins, percentage gaps, reverse main-axis flow, baseline
alignment, writing modes, flex order, or min-content negotiation. Logical
geometry remains binary64 with the existing narrow arithmetic tolerance, rather
than bit-identical upstream binary32 arithmetic. Full CSS/GPUI styling and
native visual/input parity remain outside scope. Provenance remains
`independent_from_behavior` in [upstream.json](upstream.json); no upstream
implementation or fixtures were copied.
