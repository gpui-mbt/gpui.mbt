# Partial flex-grow gap budget

The retained `grow-partial-with-gap` comparison used actual GPUI
`zed-industries/zed@d9afb21688e04f89d9e94d96d33eb530aef90886` (0.2.2) and
MoonBit main `1c34285b5520f933d7644ab23aef678b04072532` (0.7.2) on macOS
26.5.2 arm64. Two 20-point children with grow factors 0.25 in a 108-point
row with an 8-point gap measured 31/31 in GPUI and 35/35 in MoonBit.

The independently authored 17-case `gap_budget_scenarios.json` at suite
revision `3d28d4f6b8db42fe88862a6b891bb726e97789c1` records six passes and eleven mismatches on that baseline.
It includes rows/columns, gaps of 0/8/16/30/32/64/80, zero and asymmetric
grow factors, center/end placement, exact-fit and shrink controls, and grow
totals equal to or above one. The earlier 38 measured headless scenarios
remain unchanged and must be rerun alongside this new corpus.

The pinned reference's locked Taffy0.13.0 behavior uses a distribution budget
of `initial_free * grow_total - total_gaps` for grow totals below one. Here,
initial free space is 108 minus the two 20-point bases minus the 8-point gap:
60. The partial budget is 60 times 0.5 minus 8: 22. Each equal factor gets
11, yielding widths 31. This is an explicit pinned compatibility behavior,
not a claim about general CSS specifications.

The independently implemented correction distributes that budget by grow
ratios. It keeps its sign: a 32-point gap with the same initial free space
leaves a budget of -2, giving widths 19. Zero budgets leave bases unchanged;
negative proposed sizes retain the existing nonnegative/min/max clamp.
Zero grow, totals of at least one, exact fits and shrink allocation keep
their existing behavior. No public API, freeze loop, or second-pass
redistribution is added.

`layout/fractional_grow_test.mbt` replaces the former explicit independent
single-gap expectation with the retained 31/31 reproduction and its measured
center/end offsets. `layout/gap_budget_test.mbt` covers signed budgets,
asymmetric ratios and unchanged controls in both directions. Three tests
fail before the source correction. Large/small-factor numerical tests still
check MoonBit's binary64 finite geometry contract rather than GPUI's exact
floating-point representation.

The suite retains raw executable, build, execution and comparison evidence.
Its intentional one-pixel measured-width control must mismatch. This slice
does not establish native rendering, pixels, physical input or IME behavior;
native build-only results remain unverified. Fractional shrink is a separate
measured follow-up, not a claimed result of this grow correction.
