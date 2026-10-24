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

This bounded API does not represent content basis. Explicit basis
inside a container whose main axis is being intrinsically measured is rejected
with `TreeLayoutError::UnsupportedIntrinsicFlexBasis`; indefinite/content flex
basis sizing is not claimed. Existing Auto intrinsic behavior is unchanged.

Validation is covered by `layout/flex_basis_test.mbt`,
`layout/flex_basis_wbtest.mbt`, and `layout/percent_basis_test.mbt`. External GPUI
differential evidence is maintained in the separate gpui-conformance repository,
not inferred from these unit tests.
