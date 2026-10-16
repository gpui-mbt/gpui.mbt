# Bounded geometry refresh evidence

## What this proves

These are independently authored MoonBit source/core tests for the bounded
`ElementTree::with_layout_bounds(Prepainted)` API. They are not a paired candidate
run or physical-pointer evidence from upstream Rust. The original actual run's
failure is preserved and is not converted into a pass by these core tests.

Before product edits, local base `23530c0d91de0c60dd768b65b0f38c8d58becefd`, tree
`e2cf5764e9b25504de6468403b3c6572e651f782` (equivalent public core PR95 head
`0ee9ac0c0cfc83763cd38437dfd7517541a1c2fa`) had no refresh API.
[Unchanged-core gap](unchanged-core-gap.json) retains a passing source-derived
frozen-vs-fresh hit-test/old-owner rejection probe and the actual missing-method
compiler diagnostic. A preliminary invalid CLI-option attempt is retained
separately in the same JSON; it is not counted as the API gap.
[Expected-success assertion](expected-success-baseline.json) separately retains
the real failing edge assertion on an isolated exact-base source snapshot
(exit 2, one failed test), and the corresponding post-refresh assertion passing
(exit 0). An initial positive-probe helper-name collision is also retained; it
is not counted as either a runtime failure or a passing refresh result.

The new core tests exercise 2px ordinary-button movement, 1px card movement,
exact owner/lineage preservation even at identity exhaustion, immutable snapshots,
pending-owner/same-target guards, ABA/reset/rebuild rejection, all input-metadata
mismatches, IDs/order/parents/counts, changed root viewport/origin, and scroll in
either/both trees. Paint-only background differences are accepted but not copied.
Ordinary-button tests translate the observed y=280 row to y=0; card probes use a
narrower synthetic width. These are genuine MoonBit prepaint/layout frames, not
an attempt to reproduce the actual full UI or its border rasterization.

## Actual unchanged Rust baseline, still failed

The separately audited artifact is from workflow run
[38919267792](https://github.com/gpui-mbt/gpui-conformance/actions/runs/38919267792),
artifact `12054297704`, SHA-256
`4f607c244fb609218852165378d9f38c4bf7b34e353725513425e1a065c5b4c3`.
Its CI checkout is `79b09d1133d650a94c91991ed6c42c03e618d0ff`, tree
`ae5899e1ebb4a1839e61194a7f85b26b2abc745a`. The unchanged source is
[`tab_stop.rs`](https://github.com/zed-industries/zed/blob/5a5fbe79917971a4d52a96b6ddb04da198a5012e/crates/gpui/examples/tab_stop.rs),
blob `cc7c34a9979ce4027578ec2c358f503d944ee26f`, SHA-256
`be187a56c091ee0b609fa396cae4a13b49dcf98ff9e602d8caed3126de3f6a8e`.
The source blob is identical at the core compatibility pin
`d9afb21688e04f89d9e94d96d33eb530aef90886`.

The artifact contains 27 stable capture states, 54 original PNG samples, 53
operations and 80 events. It failed a cross-frame geometry assumption before
the click extension ran: mixed-frame `Source row gap3` was 8 rather than 12.
Same-frame ordinary-button gaps are always 12px. At y=280, height=40:

- Initial: el1 x16/w378, el2 x406/w378
- el1 focused: el1 x16/w380, el2 x408/w376
- el2 focused: el1 x16/w376, el2 x404/w380

Initial cards have (y,height) `(54,33),(99,33),(144,34),(190,33),(235,33)`.
Focus on item0 gives `(54,34),(100,33),(145,33),(190,33),(235,33)`.
Focus on item4 gives `(54,33),(99,33),(144,33),(189,33),(234,34)`.
Thus (407,300) changes from initial el2 coverage to a gap, (404,300) changes from
a gap to focused el2 coverage, and (20,87)/(20,234) cross card paint boundaries.
These membership consequences are inferred from paint geometry, not observed
pointer deliveries. Rounded-edge and border pixels do not establish a general
hit-test shape contract.

[Actual-baseline provenance](actual-baseline-provenance.json) retains the audit's
status, qualification, selected per-frame measurements and exact local artifact
paths, plus independent SHA-256 checks of source/report/runtime and cited PNGs.
No Rust rebuild, browser execution, native Mac run, candidate pair, or parity
claim is part of this change.

## Verification and negative controls

[Verification](verification.json) records exact commands, timestamps, statuses,
toolchain and raw diagnostics as escaped strings. [Negative controls](negative-controls.json)
record unmutated/restored passing tests, 15 compiled mutants rejected at runtime,
and two API misuse programs rejected by the compiler. The
[reproduction script](run-negative-controls.py) works in a preserved non-Git copy
under this checkout's ignored `_build` directory, never another product checkout.
[Initial control attempt](negative-controls.initial.json) preserves an allow-scroll
mutant that was rejected by the unused-constructor warning gate; the final
allow-scroll mutant keeps the constructor live and fails the runtime assertion.
The initial warning rejection is not counted as a compiled runtime control.
