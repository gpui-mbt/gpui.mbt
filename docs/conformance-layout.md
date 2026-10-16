# Overflow alignment comparison

The GPUI Conformance Suite executed independently authored flex layouts against
Rust GPUI `zed-industries/zed@d9afb21688e04f89d9e94d96d33eb530aef90886`
(0.2.2) and gpui.mbt `2badfaf54482d4fe11d64a39b2c247350cc01bea` (0.7.2),
on macOS 26.5.2 arm64. Rust used headless `VisualTestContext` layout;
MoonBit used its element request-layout path. The observations compare logical
rectangles, without a native window or GPU rendering.

The six paired cases at suite revision
`28570eec44b6cdcd1ea47c91f5809b5ffc3acaba` found four differences confined to
child origins. Main-axis cases disable shrink; all child sizes agree.

| Container and alignment | Child sizes on that axis | GPUI origins | gpui.mbt baseline origins |
| --- | --- | --- | --- |
| Row, 40-point main extent, center | 40, 40 | x = -20, 20 | x = 0, 40 |
| Column, 40-point main extent, end | 40, 40 | y = -40, 0 | y = 0, 40 |
| Row, 20-point cross extent, center | 40, 60 | y = -10, -20 | y = 0, 0 |
| Column, 20-point cross extent, end | 40, 60 | x = -20, -40 | x = 0, 0 |

Exact-fit center alignment and a start-aligned gap exceeding the available
main size agreed. These are layout observations after size resolution.

The independently implemented adjustment preserves signed remaining space for
main-axis center/end justification and cross-axis center/end alignment. It
also reports per-item overflow before the leading main-axis edge, including
when end alignment leaves the child's trailing edge inside the content box.
Start/stretch placement, gap handling, and the existing single-pass flex
allocation and min/max rules remain the same. Overflow comparisons retain the
existing scale-relative floating-point tolerance.

`layout/overflow_alignment_test.mbt` covers center/end overflow on both axes
in rows and columns, per-item leading/trailing flags, start/stretch controls,
exact fits, positive remaining space, padding/border offsets, finite negative
origins, and fractional exact-fit tolerance. Five of its initial eight tests
fail against the baseline before the adjustment; three controls pass. The
provenance record is in `upstream.json`; no upstream implementation or test
fixtures were copied.

The suite lives in `gpui-mbt/gpui-conformance`. Its retained result directories
contain executable hashes, source revisions/trees, toolchain/platform versions,
raw process output, and field-level comparison results. This evidence does
not establish full CSS flex behavior, broader GPUI layout compatibility,
pixel equivalence, physical input, or IME support.

## `space-between` capability addition

`JustifyContent::space_between()` adds a previously absent main-axis mode. When
there are at least two items and the resolved line has positive free space, the
engine distributes that free space equally across its inter-item spaces. Empty
and singleton lists do not divide by a zero or nonexistent gap; zero/negative
free space preserves the independently measured GPUI start-placement fallback.
Wrapped containers compute the share per line, rather than carrying spacing
between lines. Existing start/center/end behavior, raw logical geometry, and
scale-relative overflow/exact-fit tolerance are unchanged. The tests cover
rows, columns, empty/singleton lists, overflow, and wrapped lines. This adds only
this bounded mode; it does not claim complete CSS flexbox or GPUI styling
parity.

## `space-around` and `space-evenly` capability addition

`JustifyContent::space_around()` gives each item equal surrounding free space,
so each outer space is half an inter-item share. `space_evenly()` gives equal
free space before, between, and after items. Fixed `gap` remains additional to
the distributed inter-item share. Both modes center a fitting singleton and
fall back to start when a line has no positive free space, matching the pinned
GPUI implementation. Empty lists do not divide by zero. Each wrapped line is
resolved independently after grow/shrink and min/max sizing.

These modes were absent from baseline `bb3fa1ef552ae22d372cfcea8723e99498aa5fe7`;
this is a capability addition, not a correction of an existing named mode.
The new 24-case real GPUI corpus measures rows/columns, nonzero gaps, zero through
three children, exact fit, overflowing pairs and singletons, wrap/wrap-reverse,
capped growth, and fractional growth. The baseline's start fallback records
8 matches and 16 differences; the new library implementation matches all 24.
The corpus explicitly requests device scale 2, which is measured/asserted on
the pinned GPUI TestWindow and uses the existing MoonBit layout snapping API.
Raw `layout_flex` geometry remains unsnapped.

See the independent [distributed spacing corpus and evidence](https://github.com/gpui-mbt/gpui-conformance/blob/test/layout-distributed-spacing-20261016/DISTRIBUTED_SPACING_RESULTS.md).
These finite, definite-size cases do not qualify intrinsic sizing, reversed
main-axis flow/RTL, margins, align-content modes, text shaping, physical input,
GPU pixels, or native/IME conformance.
