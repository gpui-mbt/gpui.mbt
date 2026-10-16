# GP-00 paired public Button audit

Run `scripts/audit_shared_ui_buttons.py --help` from the repository root. Supply
an isolated Yami-kumo source checkout; no dependency is fetched by this runner.
The runner creates a temporary Moon workspace and consumer module outside both
source repositories. Only that throwaway module imports both implementations.

`button-fixtures.json` version `gp00-button-v1` is a predeclared, exact oracle for
24 shared operation sequences and 186 observations. An expected row contains:

1. action emitted at that step
2. pressed state after that step
3. operation status (`accepted`, `ok`, `invalid-bounds`, `caller-bounds`,
   `caller-focus`, or `unsupported`)
4. focus (`null` when not owned by the Yami interaction model)

The first row is construction/admission (trace step `-1`). A rejected GPUI
constructor has no later steps. Expectations are not generated from the runtime
output, and the runner has no update/re-record option. Unknown differences fail.

`button_probe.mbt` is an adapter, not a reference implementation. All armed
pointer/key state remains inside the two original Button implementations. The
Yami API receives a target ID derived from supplied geometry/focus, as its
public API requires; GPUI receives the same event with the original position.
The Yami adapter records loading as unsupported and leaves its state unchanged.
Geometry is caller-owned there; only an explicit cancel invalidates a gesture
on a bounds change. Focus loss invokes the existing cancellation API. The text
measurement stub serves only the constant ASCII `OK` label, and is not a font or
shaping proof. No pixels or native input are tested.

The full observations and vNext migration recommendation are documented in
[`docs/shared-ui-host-contract.md`](../../docs/shared-ui-host-contract.md).
