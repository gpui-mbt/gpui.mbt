# Existing macOS accessory policy

An owned `LSUIElement` fixture bundle starts with activation policy Accessory.
On the measured Apple Silicon macOS 26.5.2 host, calling
`setActivationPolicy(Accessory)` in that state returns false while the observed
policy remains Accessory. The previous background startup guard required a
true setter result on every start, so this valid bundle failed with
`UnsupportedCapability` before creating a window.

Background startup now accepts an already observed Accessory policy without
requesting an unnecessary transition. When the initial policy differs, both
a successful setter result and the observed final Accessory policy are required.
The failure cleanup and inactive, hidden-window startup behavior remain in place.

`sh script/test_macos_background_policy.sh` exercises the production helper
against six inert policy fixtures: existing Accessory, a successful transition,
a refused transition, an ineffective successful setter, and a refused setter
that nevertheless reports Accessory afterward, and an initially Accessory policy
that changes before the final observation. The last four fail closed.
It never instantiates NSApplication or creates a native window and does not
establish native conformance. Actual fixture execution and AX qualification
are separate evidence.
