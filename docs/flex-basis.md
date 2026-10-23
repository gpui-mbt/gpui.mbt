# Explicit flex basis

`FlexItem::with_flex_basis(FlexBasis::points(value).unwrap())` sets an independent
main-axis flex base size. Points must be finite and nonnegative; zero is valid.
`FlexBasis::auto()` restores the existing authored main-size/intrinsic fallback.
The default remains Auto. Cross-axis dimensions do not change.

The basis participates in growth, scaled shrink weights, min/max clamping, line
wrapping, and forward/reverse row or column layout. Item builders preserve it.
Recursive layout and mixed flex trees retain it. Device-scale preparation snaps
point basis with the same authored-length policy as point dimensions, before
final absolute-edge rounding.

This bounded API does not represent percentage or content basis. Explicit basis
inside a container whose main axis is being intrinsically measured is rejected
with `TreeLayoutError::UnsupportedIntrinsicFlexBasis`; indefinite/content flex
basis sizing is not claimed. Existing Auto intrinsic behavior is unchanged.

Validation is covered by `layout/flex_basis_test.mbt` and
`layout/flex_basis_wbtest.mbt`. External GPUI differential evidence is maintained
in the separate gpui-conformance repository, not inferred from these unit tests.
