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
