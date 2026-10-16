# Signed tab-group ordering

This bounded portable element extension supports the group-order part of GPUI's
`tab_stop.rs` example. Evidence here is pinned source inspection and independently
authored MoonBit core tests. Actual unchanged-Rust/browser execution and paired
candidate execution are separate evidence, pending at this source checkpoint.
No browser, pixel, native-window or physical-input parity is claimed here.

## Public contract

`Element` and `ElementNode` add immutable
`with_tab_group_index(Int32?)` and `tab_group_index()` APIs. The default `None`
adds no group prefix; `Some(index)` adds a signed 32-bit group component; `None`
clears it. This metadata is independently configurable from the node's handle
`tab_index` and `tab_stop` flag. Setting a group does not enable focusability or
make it a traversal destination. This separation represents upstream tracked
handles whose handle index differs from their containing div's group index.

For every node, its complete key consists of:

1. All active group indices from root to node, including its own group if set
2. Its own handle `tab_index`

Ordinary ancestors contribute no components. Non-focusable and non-stop groups
still prefix their descendants. Complete keys compare lexicographically using
signed component comparisons. A proper prefix sorts before a longer path, even
when the next component is negative. Equal complete keys use stable tree
preorder; reverse traversal reverses that complete order. No signed subtraction
is used, so both signed extremes are ordered without overflow.

`focus_next()` and `focus_prev()` keep the existing
[focus-traversal contract](conformance-focus-traversal.md):

- Only live, focusable tab stops are destinations
- A focused non-stop remains an anchor at its complete key
- Missing focus chooses the first or last stop; both directions wrap globally
- Groups do not trap focus or automatically select their first child
- No eligible stops and already-focused destinations preserve the acquisition
- A changed destination uses the existing allocator and can report exhaustion
- Explicit `with_focus` still deliberately reacquires even the same node
- Existing lineage, removed-owner, defensive-array and immutable-snapshot
  guarantees are unchanged

The implementation builds private shared group-prefix links once per traversal
from the validated preorder, unwinds closed ancestors with a stack, and scans
eligible destinations without sorting owned nodes. Two reusable buffers hold
reversed paths for component comparisons. Construction takes O(n) time and
O(n) storage; traversal comparisons take O(n × d) worst-case time and O(d)
scratch space, where n is live-node count and d is maximum active group depth.
Peak temporary storage is O(n + d), including direct trees whose depth is not
limited by the declarative lifecycle. No-stop and already-focused singleton
traversal return before constructing keys or allocating path buffers. No new
depth rejection, public arbitrary-path API or persistent cached paths is added.
All existing builders, request-layout/prepaint,
device-scale prepaint and scroll reconstruction preserve group metadata.

## Literal example's source-derived sequence

The independently authored core skeleton represents the example's initial
non-stop app root, numbered cards, two ordinary buttons, and two sibling groups.
It retains the example's equal-index tie and non-stop nodes. From the root:

`item0 [1] → item1 [2] → item4 [2] → item2 [3] → el1 [4] → el2 [5] →
group-1-button-1 [6,1] → group-1-button-2 [6,2] → group-1-button-3 [6,3] →
group-2-button-1 [7,1] → group-2-button-2 [7,2] → group-2-button-3 [7,3] → wrap`

Reverse traversal reverses those twelve destinations. The root and item3 have
anchor path `[0]`. Group containers have `[6,6]` and `[7,7]`, because upstream
registers a group's own handle inside its group prefix. Explicit focus on group1
therefore advances to group2's first child and reverses to group1's last child.
Explicit focus on group2 advances to item0 and reverses to its own last child.
The literal example does not establish deeper nesting; independent core tests
cover deeper paths such as `[2,-1,5] < [2,3]` separately.

## Unchanged-main gap before product edits

The baseline is exact main
`a99e111a37c0ac98bd847e9ea493c78589207875`, tree
`29449e394c0faf2b25beb2a1b6a4bce2806b3231`. Product source was unchanged when
both probes ran; only independent test probes and retained evidence were added.

- [API source](evidence/tab-groups/unchanged-main-api-probe.mbt.txt) and
  [compiler output](evidence/tab-groups/unchanged-main-api-probe.log): the new
  builder is absent on both `Element` and `ElementNode`, exit `1` at
  `2026-10-16T14:30:46Z`. The identical probe
  [passes after implementation](evidence/tab-groups/implemented-api-probe.log).
- [Order source](evidence/tab-groups/unchanged-main-order-probe.mbt.txt) and
  [runtime output](evidence/tab-groups/unchanged-main-order-probe.log): unchanged
  flat traversal reaches item0 on first Tab, then group1's first child (ID101)
  instead of item1 (ID11), failing an assertion with exit `2` at
  `2026-10-16T14:31:01Z`–`14:31:02Z`. The hierarchy is present, but no group
  API exists to express its prefix. This is a source-derived core gap, not an
  executed comparison with Rust. Adding only the new prefix to that group in
  the [implemented probe](evidence/tab-groups/implemented-order-probe.mbt.txt)
  resolves the second-Tab regression; its
  [result](evidence/tab-groups/implemented-order-probe.log) is retained separately.

The first order-probe attempt had an independently authored invalid numeric
literal and did not run. Its [source](evidence/tab-groups/unchanged-main-order-probe-initial-compile-error.mbt.txt)
and [compile log](evidence/tab-groups/unchanged-main-order-probe-initial-compile-error.log)
are retained separately; that failure is not counted as behavioral evidence.

## Verification and reproduction

Tool versions and platform are retained in the
[toolchain record](evidence/tab-groups/toolchain.txt). Commands use MoonBit
`0.10.15+943464bfa` and `-j 2` on Linux x86_64.

- `moon test element --target all --deny-warn -j 2`: 112/112 each on JS, native,
  wasm and wasm-gc, including 17 new tests. See the
  [element log](evidence/tab-groups/element-all-targets.log).
- Portable regression command below: 554/554 each JS/wasm/wasm-gc and 553/553
  native. This includes the pre-existing flat-order, ownership, modality, scroll,
  layout, controls, text, scene, capability and MCP tests. See the
  [regression log](evidence/tab-groups/portable-regressions-all-targets.log).
- Static/document and Python checks are retained separately in
  [static checks](evidence/tab-groups/static-checks.log) and
  [Python regressions](evidence/tab-groups/python-regressions.log). Passing the
  contract checker does not satisfy the repository's pending release gates.
  Exact compiler diagnostic bytes, including trailing gutter spaces, are
  retained in [JSON-escaped raw containers](evidence/tab-groups/raw-log-containers.json)
  with decoded SHA-256. Corresponding display logs explicitly label their
  trailing-space normalization. The earlier
  [raw-log whitespace observation](evidence/tab-groups/staged-raw-log-whitespace-observation.log)
  is preserved; final full staged/base whitespace checking includes all files.
- The [generated element interface](../element/pkg.generated.mbti) includes the
  two new methods on both types; its
  [generation result](evidence/tab-groups/interface.log) is retained.

```sh
moon test primitives diagnostics core layout element scene text text_layout \
  controls/button controls/text_field controls/command_palette accessibility \
  capability mcp testing/core_model examples/task_board \
  --target all --deny-warn -j 2
```

The 17 tests cover the literal twelve-destination sequence and both wraps;
non-stop group anchors and global exit; deeper nested groups and ordinary
ancestors; proper prefixes and a group's own handle; equal complete paths;
signed extremes at three depths; independent and cleared group/handle metadata;
all builders, device scaling, scroll reconstruction; no/one stops; ownership,
identity exhaustion, subtree removal, new-tree lineage; and defensive child,
node and comparison-buffer arrays. Two iterative 1,024-group direct-tree
regressions check deep traversal/no-stop ownership and linear shared-prefix
storage with reusable scratch; no declarative-depth restriction is imposed.
Existing flat traversal and modality tests are
unchanged and still pass.

Nine independently mutated implementations compile and fail assertions: flat
keys, omitted own prefix, reversed signed components, reversed equal-path ties,
reversed proper-prefix order, conflated group/handle indices, retained closed
group prefixes, missing prepaint metadata, and missing scroll metadata. Each
exits `2`; the restored exact source passes 112/112. The
[manifest](evidence/tab-groups/negative-controls.json) retains exact replacements,
hashes, timestamps and logs. Reproduce with
`python3 docs/evidence/tab-groups/run-negative-controls.py`; it uses a fresh
non-Git source copy and never mutates the product checkout. These are focused
negative controls, not a full mutation score or an upstream execution oracle.

The initial copied-path implementation and its 110-test/mutation evidence are
retained under [the pre-resource-review checkpoint](evidence/tab-groups/pre-resource-review/verification.json).
Review identified O(sum of active group depths) temporary storage, quadratic
for deep direct trees. The final shared-prefix implementation replaces that
resource behavior; earlier results are historical and not attributed to it.

## Source and license boundary

The compatibility pin stays
`zed-industries/zed@d9afb21688e04f89d9e94d96d33eb530aef90886`; the separate browser
suite uses `5a5fbe79917971a4d52a96b6ddb04da198a5012e`. At both pins the literal
example is blob `cc7c34a9979ce4027578ec2c358f503d944ee26f`, SHA-256
`be187a56c091ee0b609fa396cae4a13b49dcf98ff9e602d8caed3126de3f6a8e`.

The production portion of `crates/gpui/src/tab_stop.rs` is byte-identical,
SHA-256 `741c19f765ee98a82a36986ced9600c258bafbc22745d13dc2017b1943a3f1de`.
It establishes lexicographic signed paths with insertion-order ties. Scoped
`div.rs` registration enters the group before inserting its own focus handle;
`Window::with_tab_group` delegates the signed group index. Whole `window.rs`
and `div.rs` files differ; they are not claimed equivalent. The
[source manifest](evidence/tab-groups/source-provenance.json) records exact
full blobs, eight byte-equivalent scopes, line ranges, SHA-256 and Apache-2.0
package/license provenance. The appended record in
[upstream.json](upstream.json) preserves earlier records and the pin.

Implementation and test scenarios are independently authored. No upstream
implementation, test bodies, example source, screenshots, fonts or image assets
are copied into runtime or test fixtures.

## Limits

This adds signed group-prefix ordering to the existing portable focus traversal.
It does not add focus traps, keymaps/action dispatch, focus scrolling, automatic
host input integration, retained-tree reconciliation, native accessibility,
pointer capture, Touch, full CSS/GPUI semantics, or general rendering/layout
parity. Existing scroll/layout and modality behavior is unchanged. Deeper-group
correctness is core-test evidence; the literal example only has one group prefix
per child. Actual unchanged-Rust execution and a paired candidate require their
own retained browser artifacts before any runtime correspondence claim.
