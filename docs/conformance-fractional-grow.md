# Fractional flex-grow comparison

The GPUI Conformance Suite executed independently authored flex layouts against
Rust GPUI `zed-industries/zed@d9afb21688e04f89d9e94d96d33eb530aef90886`
(0.2.2) and gpui.mbt `553bff7e35cea7b1d6aeaf20dc22b2348af9b865` (0.7.2),
on macOS 26.5.2 arm64. Rust used headless `VisualTestContext` layout;
MoonBit used its element request-layout path. Only logical rectangles were
compared.

In a 100-by-20-point row, two children with 20-point bases and grow factors
of 0.25 each resolve to 35 points each in GPUI. The MoonBit baseline resolves
them to 50 points each. The factors consume half of the 60 points of free
space in GPUI; the baseline normalizes them to consume all of it. Two grow
factors of 1 resolve to 50 points each in both implementations.

The 17 paired cases at suite revision
`e9123a81dcc1221993edfa6a67b53da372600f30` recorded 11 differences and six
passing controls. Partial-grow cases cover rows and columns, unequal factors
and bases, a zero factor, totals of 0.5, 0.75 and 0.875, center/end alignment,
gaps, zero bases, and small factors. Controls cover zero grow, grow totals of
one or more, exact fits, and negative free space with shrink enabled.

The independently implemented adjustment uses a grow denominator of at least
one. A total below one therefore retains unallocated positive space for the
existing justification step. A total of one or more keeps proportional
allocation of all positive space. Shrink allocation, the single-pass min/max
clamp, signed overflow alignment, finite-value validation, and overflow
tolerance retain their existing behavior. This does not add freeze passes
or redistribute space left by min/max constraints.

The partial-grow-with-gap case remains a known difference. With a 108-point
row, an 8-point gap, two 20-point bases, and factors of 0.25 each, pinned GPUI
resolves widths of 31 points each. The independent MoonBit contract subtracts
the gap once from the available budget and allocates each factor's share of
the remaining 60 points, resolving widths of 35 points each. This adjustment
preserves that gap budget rather than reproducing the pinned gap behavior.
The formal `grow-partial-with-gap` scenario retains the comparison evidence;
candidate suite results must continue to report any difference.

`layout/fractional_grow_test.mbt` covers the observed partial-grow behavior
and controls, including row/column placement and center/end leftovers. Its
single-gap-budget test explicitly checks the independent MoonBit contract,
not agreement with pinned GPUI. Additional numerical and bounded-subset tests
cover large finite and subnormal factors, a tiny factor with a large finite
extent, and one-pass max clamping. Six of its nine tests fail against the
baseline before the adjustment. The provenance record is in `upstream.json`;
no upstream implementation or test fixtures were copied.

The suite lives in `gpui-mbt/gpui-conformance`. Its retained result directories
contain executable hashes, source revisions/trees, toolchain/platform versions,
raw process output, and field-level comparisons. The evidence does not
establish full CSS flex behavior, native rendering, pixel equivalence,
physical input, or IME compatibility. Very small factors are represented by
binary64 in this MoonBit API; the extra numerical tests enforce its finite
geometry contract and do not claim GPUI's exact floating-point representation.
