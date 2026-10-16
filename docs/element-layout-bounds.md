# Retained input geometry refresh

`ElementTree::with_layout_bounds(Prepainted)` returns
`Result[ElementTree, ElementError]`. It refreshes a retained input tree after a
new request-layout/prepaint pass, while retaining its exact focus acquisition.
Paint the fresh `Prepainted` separately. The input tree deliberately retains its
old paint-only backgrounds, including when the new frame changes hover colors.

This is a bounded same-topology, non-scroll operation. Before constructing any
updated nodes, it validates:

- Identical node count and positional preorder IDs and parents
- Identical focusable, tab index, tab-group index, tab-stop and pointer-event metadata
- Unchanged root viewport bounds, including origin
- No scroll viewport anywhere in either tree

Topology/input/viewport mismatches return `LayoutBoundsMismatch`; an encountered
scroll viewport returns `ScrollLayoutBoundsUnsupported`. When multiple conditions
are invalid, error precedence is not a public contract. Failed validation leaves
both inputs unchanged. Success copies only fresh bounds into new retained-node
records. Every other field, exact focused ID, lineage and `FocusOwner` survives;
no identity allocation or focus reacquisition takes place. Old snapshots remain
unchanged. Repeated refreshes retain ownership until a separate focus operation
changes it. A rebuilt `ElementTree::new` still starts a fresh lineage and rejects
old owners even when numeric IDs match.

The argument is the lifecycle's read-only `Prepainted` type. Arbitrary rectangle
arrays and caller-fabricated prepaint records do not compile. This API does not
reconcile IDs, add/remove/reparent nodes, import fresh focus, or implement a click
recognizer. Caller-owned pending activation guards can compare their existing
owner with the refreshed tree and check the release target against fresh bounds.
The reusable `Button::with_bounds` gesture-cancellation contract is unchanged.

Validation and copying each take O(n) time, with O(n) new node storage on success.
No scroll-offset/clip refresh, viewport resize, native/browser parity, or general
reconciliation is claimed. A caller must handle rejection and deliberately reset
its own input state before replacing an incompatible tree.

[Evidence and provenance](evidence/tab-stop-geometry-20261016/README.md) distinguish
the compiled core contracts from the failed actual Rust/browser baseline that
motivated the moving-edge probes.
