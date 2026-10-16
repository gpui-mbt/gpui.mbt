# Bounded distributed wrapped-line alignment

`AlignContent::space_between()`, `space_around()`, and `space_evenly()` extend
`FlexContainer::with_align_content` and `FlexTreeStyle::with_align_content`.
This is a capability addition. The existing start/center/end/stretch modes and
default stretch behavior retain their [earlier contract](conformance-align-content.md).

## Contract

- Distribution uses the definite inner cross extent after border and padding.
  Natural line sizes and existing cross-axis gaps are subtracted first.
- For positive free space F and N lines, between adds F/(N-1) between lines
  when N > 1. Around adds F/N between lines and F/(2N) at each outer edge.
  Evenly adds F/(N+1) between lines and at each outer edge.
- These shares are added to the existing line gap. They do not grow line boxes,
  change main-axis item gaps or flex sizing, or change child source order.
  `AlignItems` still places each child within its natural line; an auto cross
  dimension can stretch only to that line, subject to its own min/max limits.
- All three modes fall back to safe physical-start placement on overflow,
  including wrap-reverse. They do not inherit the signed center/end overflow
  behavior of the explicit positional content modes.
- A fitting single wrapped line stays at flex-start for between, including the
  far edge under wrap-reverse. Around and evenly center a fitting singleton.
  An overflowing singleton uses the same physical-start fallback as a stack,
  while reversed item alignment within its line remains independent.
- Empty containers return no boxes without division by zero. Exact-fit stacks
  keep the authored gaps. NoWrap ignores content alignment.
- Builders, recursive tree placement, and the optional device-scale boundary
  preserve the selected mode. Raw layout continues to return logical geometry.

For two row lines of heights 10 and 14, gap 4, and inner height 64 under start
item alignment, the child top coordinates are:

| Mode | Wrap | Wrap-reverse |
| --- | --- | --- |
| SpaceBetween | 0, 50 | 54, 0 |
| SpaceAround | 9, 41 | 45, 9 |
| SpaceEvenly | 12, 38 | 42, 12 |

At inner height 20, all three modes give `0, 14` for wrap and `18, 0` for
wrap-reverse. With both children on one line and inner height 64, between gives
`0, 0` for wrap and `54, 50` for reverse; around/evenly give `25, 25` and
`29, 25`. At inner height 10 the overflowing reverse singleton gives `4, 0`:
the line is safely anchored, and its shorter first child keeps reversed item
alignment. Column flow transposes these rules.

## Evidence and limits

The reference remains actual GPUI headless Render/layout at
`zed-industries/zed@d9afb21688e04f89d9e94d96d33eb530aef90886`. The independently
authored 42-case corpus measures all three modes across rows/columns, normal
and reversed wrapping, positive/exact/negative free space, empty and singleton
stacks, natural auto cross sizes, three lines, and NoWrap controls. Against the
pre-addition engine, 20 cases agree and 22 expose missing capability.

Linux x86_64 comparison of engine implementation
`f70e60ffb77fe984f8bac51ac242fbe4ee768c21` and public suite source
`685565bd8a9d3bd3d167e0601642f2cf6ea0b76c` records:

- Focused comparison: 42 pass, zero mismatch.
- Width-perturbation negative control: 39 nonempty cases mismatch; three empty
  controls remain passes because they have no child width to perturb.
- Combined regression corpus: 233 pass, zero mismatch, one existing unsupported
  IME case, and two existing native unverified cases.
- Adversarial comparator checks: 38 pass.
- Three extra reverse singleton-overflow runtime comparisons agree. These are
  separate ad hoc checks, not additions to the authoritative 42-case total.

The [independent corpus](https://github.com/gpui-mbt/gpui-conformance/blob/685565bd8a9d3bd3d167e0601642f2cf6ea0b76c/content_distribution_scenarios.json)
has SHA-256
`126600bb7eb004d105033c8aa82bc8a0b4d64c7eb85f26a8698b17aadb127d80`.
These are local headless observations, not a claim of public CI or native
conformance. Later changes in this engine slice add tests and documentation
without changing the measured implementation.

The [direct and nested regression tests](../layout/content_distribution_test.mbt)
cover these contracts, builder/inset preservation, unchanged intrinsic sizing,
independent main-axis distribution, fractional device-grid coordinates,
nonfinite aggregate rejection, and finite large-ratio edge anchoring. Positive
distribution accumulates from the physical near edge and independently anchors
the opposite outer line; this avoids losing tiny trailing lines through
subtraction from a very large first line. Overflow likewise accumulates from
the safe edge. Existing positional modes are untouched.

Logical geometry remains binary64 with the existing narrow exact-fit and
overflow tolerance, not bit-identical GPUI binary32 arithmetic. Recursive
auto-sized containers still use the existing no-wrap intrinsic approximation.
Margins, baseline alignment, writing modes, flex order, full CSS/GPUI styling,
native pixels, physical input, and IME behavior remain outside this slice.
The provenance record is `independent_from_behavior` in [upstream.json](upstream.json);
no upstream implementation or fixtures were copied.
