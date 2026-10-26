# Explicit flex basis

`FlexItem::with_flex_basis(FlexBasis::points(value).unwrap())` sets an independent
main-axis flex base size. Points must be finite and nonnegative; zero is valid.
`FlexBasis::auto()` restores the existing authored main-size/intrinsic fallback.
The default remains Auto. Cross-axis dimensions do not change.

`FlexBasis::percent(ratio).unwrap()` resolves a finite nonnegative ratio against
the container's inner main extent, after padding and border but before subtracting
item gaps. A ratio of 1.0 means 100%; zero and ratios above one are valid. The
resolved basis then participates in flex growth, weighted shrink, limits and
wrapping. A nested percentage resolves against its own allocated parent, not the
root viewport. Percent ratios are not snapped as point lengths; only the
containing geometry and resulting absolute edges undergo device-grid rounding.

The basis participates in growth, scaled shrink weights, min/max clamping, line
wrapping, and forward/reverse row or column layout. Item builders preserve it.
Recursive layout and mixed flex trees retain it. Device-scale preparation snaps
point basis with the same authored-length policy as point dimensions, before
final absolute-edge rounding.

## Bounded intrinsic parents

An auto-main-size parent supports Auto, point and percentage bases in a nowrap line when
**every direct child has zero grow and zero shrink**. Both pure and mixed trees
use the same rule. A point child's max-content contribution is the maximum of
its basis, its definite authored main size (if any), and its minimum main size.
An Auto child's contribution uses its authored/intrinsic main size floored by
its minimum. Gaps, padding and border are then added to the parent extent.

A child's maximum main size bounds its final box, **not** this zero-flex
max-content contribution. For example, authored width 40, point basis 60 and
maximum width 24 contribute 60 to the parent but produce a 24-wide child. A zero
basis can likewise leave a positive parent contribution when the authored main
size is positive. Point bases with an Auto authored main size do not use the
intrinsic fallback as an additional preferred size.

This also corrects the max-limit contribution of Auto-only, nowrap, zero-flex
lines. Existing Auto-only flexible/wrapped intrinsic approximation is otherwise
unchanged. Point bases in wrapped intrinsic lines or in lines with any nonzero
grow/shrink factor still return `TreeLayoutError::UnsupportedIntrinsicFlexBasis`.
A percentage basis is indefinite during intrinsic measurement: its contribution
uses the definite authored main size (floored by the minimum, not capped by the
maximum), or zero for an empty Auto leaf. The ratio is retained and resolves
against the eventual parent's inner extent during final layout, including the
space occupied by gaps. Thus even a zero ratio can have a positive authored
parent contribution, and ratios above one can overflow the measured parent.
Both pure and mixed trees use this two-stage behavior. Percentage bases with
wrapping or any nonzero grow/shrink are rejected just like point bases.

Percentage basis with an Auto authored main size is currently qualified only
for empty-main-axis leaves (zero intrinsic main extent, no child style). A
definite orthogonal cross size does not count as intrinsic main content. Nonempty
intrinsic content or nested Auto children remain explicitly unsupported.
Percentage authored dimensions without a definite containing extent remain
indefinite. Content basis is not represented. Text/min-content negotiation,
margins and general CSS intrinsic sizing are not claimed.

Validation is covered by `layout/flex_basis_test.mbt`,
`layout/flex_basis_wbtest.mbt`, `layout/percent_basis_test.mbt`, and
`layout/intrinsic_basis_test.mbt`, and `layout/intrinsic_percent_basis_test.mbt`. External GPUI
differential evidence is maintained in the separate gpui-conformance repository,
not inferred from these unit tests.

Device-scale entry points expose final snapped coordinates/sizes in GPUI's f32
logical representation for these newly supported intrinsic-Percent subtrees.
Eligibility follows the measured physical main axis, not merely any Auto axis.
Unrelated siblings, previously supported definite-parent Percent layouts, raw
Double entry points, and `bounds_before_edge_snap` retain their existing behavior.
