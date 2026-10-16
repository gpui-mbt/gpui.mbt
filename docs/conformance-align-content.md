# Bounded wrapped-line content alignment

`AlignContent` adds `start()`, `center()`, `end()`, and `stretch()` to the
portable layout API. Select it with `FlexContainer::with_align_content` or
`FlexTreeStyle::with_align_content`. Stretch remains the default. This is a
capability addition: the earlier API always stretched wrapped line boxes.
The later [distributed-line extension](conformance-content-distribution.md) adds
`space_between()`, `space_around()`, and `space_evenly()` without changing these
four modes. The evidence below is the historical four-mode slice.

## Contract

- Content alignment positions the stack of wrapped lines within the inner
  cross extent, after padding and border. The stack includes cross-axis gaps.
- Start and end are flex-relative, matching the pinned public GPUI
  `content_start` and `content_end` methods. Wrap-reverse reverses their physical
  anchoring; center is symmetric. Column flow transposes the same rules.
- Start, center, and end preserve natural line sizes. Center and end use signed
  remaining space even when lines overflow. Reverse start can likewise place
  overflowing lines before the physical origin.
- Stretch divides positive remaining space equally among line boxes. On
  overflow it preserves the existing safe physical-start fallback, including
  wrap-reverse. Explicit stretch and the default are equivalent.
- Item alignment is independent: `AlignItems` places each child within its
  line. Only auto cross dimensions stretch, subject to child min/max limits.
- A wrapping container with only one line still honors content alignment.
  NoWrap ignores content alignment and keeps its existing item-alignment rules.
- Every immutable builder, nested tree placement, and device-scale preparation
  preserves content alignment. Stable source/preorder output and leading as
  well as trailing overflow flags remain intact.

For example, two row lines with child heights 10 and 14, gap 4, and inner
height 64 have these child top coordinates under start item alignment:

| Content mode | Wrap | Wrap-reverse |
| --- | --- | --- |
| Start | 0, 14 | 54, 36 |
| Center | 18, 32 | 36, 18 |
| End | 36, 50 | 18, 0 |
| Stretch | 0, 32 | 54, 18 |

At inner height 20 the same overflowing lines yield:

| Content mode | Wrap | Wrap-reverse |
| --- | --- | --- |
| Start | 0, 14 | 10, -8 |
| Center | -4, 10 | 14, -4 |
| End | -8, 6 | 18, 0 |
| Stretch | 0, 14 | 18, 0 |

## Evidence and limits

The unchanged reference is actual GPUI headless Render/layout at
`zed-industries/zed@d9afb21688e04f89d9e94d96d33eb530aef90886`.
The independently authored 36-case align-content corpus measures all four
modes against row/column, wrap-reverse, overflow, a single wrapped line, nowrap,
and limited auto cross sizing. Before the addition, 15 cases agree through the
existing default and 21 expose the missing capability.

On Linux x86_64, engine snapshot
`51c4c1dccfd61d81c36a0d6ae03971b9d13a952b` and conformance suite
`09e9535c0152431058472abba5dcb92604e3ac6b` produce:

- Focused align-content comparison: 36 pass, zero mismatch.
- Width-perturbation negative control: zero pass, 36 mismatch.
- Combined regression corpus: 191 pass, zero mismatch, one existing IME
  unsupported case, and two existing native unverified cases.
- Adversarial comparison checks: 38 pass.

The focused corpus SHA-256 is
`5dee1a29708da2a001970a63e520fa8b854f1ee3b3725d3f012dd056ac17451b`.
These are bounded local headless observations; unsupported/unverified cases
remain open. Subsequent changes add only regression tests and this evidence
record, leaving the measured engine implementation unchanged.

Direct and nested regression coverage is in
[`layout/align_content_test.mbt`](../layout/align_content_test.mbt). It also
checks per-child overflow, empty and exact-fit stacks, inset bounds, immutable
builder preservation, device-scale copying for both root and nested styles, fractional negative-edge
rounding, reverse single-line placement, and finite large-ratio edge anchoring.
Existing [wrap regressions](../layout/flex_wrap_test.mbt) retain default-behavior
coverage. The provenance entry is recorded as `independent_from_behavior` in
[`upstream.json`](upstream.json); no upstream code or fixtures were copied.

The later distributed align-content extension has its own contract and evidence.
Margins, baseline alignment, writing modes, flex order, and general CSS/GPUI
styling remain outside scope. Recursive auto
containers retain their existing no-wrap intrinsic measurement approximation.
Logical geometry remains binary64 with the existing narrow arithmetic tolerance,
not bit-identical upstream binary32 arithmetic. Headless layout evidence does
not establish native rendering, pixels, physical input, or IME behavior.
