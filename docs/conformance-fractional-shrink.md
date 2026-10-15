# Fractional flex-shrink comparison

Actual pinned GPUI `zed-industries/zed@d9afb21688e04f89d9e94d96d33eb530aef90886`
(0.2.2) and gpui.mbt `9fb1f278789da554975bfe388dfcf58c3e0e9287` (0.7.2)
were executed on macOS 26.5.2 arm64 using the unchanged Rust headless layout
and MoonBit element request-layout adapters. The shared 17-case corpus at
suite `8843d05d7e1c84e7bce36c1acbce32ff0bf2ea60` records 7 passes and 10 mismatches on that baseline.

In a 40-point row or column, two 40-point bases with shrink factors 0.25 each
resolve to 30 points each in GPUI. The baseline normalizes shrink weights to
consume the entire 40-point deficit and produces 20/20. The reference consumes
only half that deficit, leaving 20 points of visible overflow. Unit-sum and
above-unit factors consume the full deficit; zero factors retain their bases.

The independent correction tracks the raw shrink-factor total separately from
`shrink * basis` weights. For raw totals below one, the partial budget is the
initial negative free space times that total, minus line gaps, bounded below
by the initial free space. Children receive that signed budget by their scaled
weight ratio. Thus unequal bases and zero bases affect shares without changing
the raw-factor threshold. Existing center/end alignment handles the retained
negative leftover; overflow is not concealed or forcibly fitted.

An 8-point gap on a 48-point line with the same bases/factors yields a -28 budget
and 26-point children. A 32-point gap on a 72-point line would yield a -52 partial
budget, so the initial -40 deficit bounds it: children 20/20 exactly fill the
line with its gap. These are observed pinned Taffy 0.13.0 compatibility examples,
not a claim of general CSS specification or full floating-point parity.

`layout/fractional_shrink_test.mbt` checks both axes, raw versus weighted sums,
zero/unit/above-unit controls, signed overflow origins, bounded gap budgets,
exact/positive free space and small positive factors. Five tests fail before
the source correction. An additional MoonBit numerical contract keeps huge
finite shrink factors with zero bases valid by saturating only the raw threshold
sum at one; it does not claim matching GPUI's floating-point representation.

Positive grow allocation, its gap correction, validation of scaled weights and
geometry, and the one-pass min/max clamp retain their existing behavior. No
public API, freeze loop or second-pass redistribution is introduced. All earlier
38 headless cases and 17 new grow-gap cases must be rerun with deliberate width
controls. Raw executables, independent process challenges, source/tree/platform
identities and logs remain part of the evidence. Native build-only is unverified;
native rendering, physical input and IME are not established by these results.
