# Shared UI host contract audit (GP-00)

Status: public API inventory and executable **headless** comparison. This audit
adds no native host capability, changes no control semantics, and promotes no
platform support tier. The four-platform product gate remains separate.

Original audit baseline: GPUI `a99e111a37c0ac98bd847e9ea493c78589207875`,
legacy Yami-kumo `21d85061e7445c479b483bcffa12679f7730d89a`. The API inventory
below is reconciled with integration main
`b55bcc13cc3dd9e7e9e0855aab5e2aee72befe78`, including merged PRs #95, #97 and
#98. The paired Button fixtures keep the pinned legacy Yami dependency; their
GPUI input is the exact candidate checkout, not the historical GPUI baseline.
The [four-platform plan][plan] contains the original GP-00/01/02/03 packets.
Those are scope and dependency references, not runtime evidence. Final-head CI
records the actual integration candidate and independently executes the fixtures.

## Evidence vocabulary

- **Public value API**: an exported portable type/function. Deterministic tests
  can establish its bounded value semantics; they do not establish host input.
- **Host implementation**: code exists for a specific backend. Only a named,
  exact-source runtime profile can qualify the corresponding OS behavior.
- **Experimental host-local API**: some names are exported in generated `.mbti`
  files, but the route remains opt-in/backend-specific and is not the shared
  `platform.Backend` text/IME capability. Exported visibility is not support.
- **Gap**: the required shared contract, transport, or qualifying evidence is
  absent. Use the gap IDs below rather than filling the matrix with a different
  platform's pass, a model pass, or a design-target paragraph.

The dependency direction remains Yami adapter → GPUI public packages → host.
GPUI has no Yami/Kumo runtime dependency. The comparison runner creates a
throwaway consumer module that imports both implementations for testing only.
No OS text-input or accessibility implementation belongs in the Yami adapter.
The Web DOM branch belongs above scene lowering; existing Canvas rendering is
not a semantic DOM reconstruction source.

## Integration-head public API mapping

“Yami call site” names existing native integration and the intended new shared
consumer. New TextField/Dialog entries are requirements, not claims that these
Yami components are already implemented.

| Required function / Yami call site | Reuse in GPUI | Boundary and next work | Evidence profile |
| --- | --- | --- | --- |
| Domain state and actions; native sample `App`/counter owner, new shared runtime | `core.App`, `Entity[T]`, `App::read/update`, scoped `Context`, explicit `notify` and `destroy_entity` | Keep effects with the same App/Entity. No duplicate state store or automatic host scheduler is supplied. | Existing portable core tests; no GUI claim. |
| Button pointer/key state; `native/components/button.mbt` and new Button adapter | `controls/button.Button::new/handle_input/with_enabled/with_loading/with_focus/with_bounds/cancel_press` | Existing Yami `ButtonInteraction` is not equivalent. Apply the versioned decision below, keeping legacy behavior. | Paired `headless-button-public-api-{js,native,wasm,wasm-gc}`; all use actual models. |
| Button label/flat paint; native `NativeText`/`NativeButton` | `text_layout.TextMeasurement`, `scene.SceneItem::text_run`, Button paint helpers | Yami owns theme and semantic view intent. CoreText/Pango/DirectWrite measurement and native raster admission stay in GPUI. | Existing source-specific text/renderer profiles; this audit runs no pixels. |
| Row/column/container sizing; native `layout_item`, `NativeAppShell` | `layout.FlexItem`, `FlexContainer`, `layout_flex_tree`, `layout_flex_tree_with_device_scale`; `element.Element` layout bridge | Reuse the deterministic layout engine; do not introduce a Yami native flex engine. DOM layout needs its own semantic/layout acceptance. | Portable layout and separate conformance fixtures. |
| Hit testing, capture/bubble routing and focused dispatch; native sample input owner | `element.ElementNode/ElementTree`, `hit_test`, `dispatch_pointer`, `dispatch_input`, `without_subtree`, `FocusOwner`, `ElementTree::with_layout_bounds(Prepainted)` | Same-topology, non-scroll bounds refresh preserves exact focus ownership; it is not general reconciliation. IDs/owner lineage, cancellation and focus synchronization remain explicit. No window pointer-leave event exists in `InputEvent`. | [Retained input geometry](element-layout-bounds.md), portable element tests; window delivery separately qualified. |
| Grouped tab traversal, focus-visible and restoration; new Button/Dialog | `ElementTree::focus_next/focus_prev/is_focus_visible/restore_focus`, `InputModality`, `Element::with_tab_group_index`, `ElementNode::with_tab_group_index` | Reuse existing flat traversal and merged signed nested group-prefix ordering. Groups remain ordering metadata. Opt-in `FocusScopeSession` adds bounded modal lifetimes, revision admission, background/ancestor suppression and disappearance fallback with an explicit owner cancellation hook; actual Dialog/native delivery is unverified. | [Bounded focus traversal](conformance-focus-traversal.md), [tab groups](conformance-tab-groups.md), [focus scopes](focus-scopes.md), portable ownership and real-controller integration fixtures. |
| Text values, directional ranges, composition; new TextField | `text.TextDocument`, `TextSelection`, `TextRange`, `TextComposition`; strict `utf8_offset/utf16_offset` | UTF-16 is current. `text_session.TextSession` now supplies live owner/session freshness over these values; `text_host` supplies the optional native transport. Immutable branches alone do not carry host authority. **GP-01A**, **GP-01B**. | Existing UTF-16/UTF-8 scalar-boundary and composition suites. |
| Bounded editing, history and composition presentation; new TextField | `controls/text_field.TextField::handle_input/update_composition/update_composition_utf8/commit_composition/cancel_composition`, `revision`, `committed_document`, `caret_rect` | Reuse existing field transactions, undo/redo, cursor-stop admission and failure rollback. It is a bounded single-line LTR field, not general grapheme/bidi/multiline support. **GP-01A**, **GP-01B**, **GP-01-GEOMETRY**. | Portable field tests; backend-specific measurement and presentation separately tested. |
| Measured caret/hit geometry; new TextField native adapter | `text_layout.TextMeasurement/CaretGeometry/TextHit`, Linux Pango, Windows DirectWrite and macOS CoreText packages | Returned coordinates/UTF-16 offsets remain explicit. No public universal shaping/segmentation engine; capability-gate unsupported layouts. **GP-01-GEOMETRY**. | Headless native measurement is distinct from rendered caret or candidate-window evidence. |
| Window lifetime, scale, events and frames; 3 native entrypoints | `platform.Backend`; `platform.Event` with window/sequence/scale; `platform/macos.Host`, `ubuntu.Host`, `windows.Host` | Existing host/window/rendering slices are reusable. `Backend` intentionally has no text-session methods; the additive `text_host.TextInputHost` trait carries epochs, committed state and ordered observations. **GP-01B**, **GP-03-AX**. | Existing exact-host window/frame profiles; this audit runs no window. |
| Role/name/enabled/loading/focus and Invoke; new semantic adapter | `accessibility.AccessibilityModel::publish/resolve_action`, owned `NodeId`, immutable snapshots | Preserve semantic nodes independently of pixels. Only bounded roles/Invoke exist; value/selection/relation fields and native notifications are incomplete. Action intent is a validation receipt, not a one-shot executable token. **GP-03-SEMANTICS**, **GP-03-AX**. | Portable model and transport-free projection tests only. |

Source entrypoints and generated public API inventories:
[core](../core/pkg.generated.mbti), [button](../controls/button/pkg.generated.mbti),
[layout](../layout/layout.mbt), [element](../element/pkg.generated.mbti),
[text](../text/pkg.generated.mbti), [field](../controls/text_field/pkg.generated.mbti),
[text layout](../text_layout/pkg.generated.mbti),
[platform](../platform/pkg.generated.mbti),
[accessibility](../accessibility/pkg.generated.mbti).

### Other merged core surfaces to reuse

The integration main also provides these bounded public contracts. They do not
add a shared Yami widget or change the Button oracle in this audit.

- [Typed drag sessions](drag-session.md): `DragSession[T]`, `DragSource[T]` and
  `DropTarget[T]` own the strict move-activation and one-shot typed drop channel.
  Reuse them for a future drag adapter instead of adding another gesture owner.
  Numeric-ID reuse still requires explicit lifecycle cancellation; this is not
  an opaque incarnation token. Existing `DragGesture` behavior is unchanged.
- [Uniform lists](uniform-list.md): `UniformList`, `UniformListIdSpace` and
  `UniformListRange` use ordinary core layout for measured equal-height rows;
  `ElementTree::uniform_list` exposes the materialized layout. The bounded
  `UniformListClickSession` must reconcile every successfully published fresh
  frame and cancel when the logical list/model is replaced. It does not replace
  Button, drag or focus ownership. Variable-height rows, arbitrary nested list
  shapes, selection/navigation and generic reconciliation are not implied.
- [Retained bounds refresh](element-layout-bounds.md) copies only bounds and
  retains the exact `FocusOwner`; topology, input metadata and viewport must
  match and scroll trees are rejected. The separate `Button::with_bounds`
  gesture-cancellation contract remains unchanged.

These mappings identify reusable APIs, not new runtime qualification by this
audit. Consult each surface's own exact-source evidence before making parity or
host-support claims.

## Three OS host gaps

| Host | Implemented/reusable surface | Missing or unqualified requirement | Packet / existing issue |
| --- | --- | --- | --- |
| Linux / Ubuntu | `Host` window/event/scene API; Pango geometry; bounded text field; `DirectKeyboardText`; exported host-local `begin_text_session`, `update_text_session`, `next_editor_event`, `cancel_text_session`, `end_text_session` | Text-input-v1/Weston/IBus/Mozc route is experimental opt-in. Its epoch/FIFO/serial mechanics should be reused, but it is not a shared `platform.Backend` text contract or general public `TextInput` claim. Integrated Japanese composition, candidate placement/selection and wider compositor profiles need exact-source evidence. **GP-02-L-IME**. | [GP-02-L][gp02l], [0007 Ubuntu](../issues/open/0007-ubuntu-native-backend.md), [Ubuntu IME scope](ubuntu-ime.md), [field scope](linux-text-field.md). |
| Windows | `Host` window/event/scene API; DirectWrite geometry; bounded field; exported host-local session methods and `TextSessionTarget/Event`; opt-in `TextHostRoute` portable adapter | IMM32 is private/experimental, default-off. A target/epoch-bearing API exists and should be adapted, not reimplemented in Yami. Common ownership/revision contract plus real Japanese IME and candidate-window qualification remain **GP-02-W-IME**. | [GP-02-W][gp02w], [0008 Windows](../issues/open/0008-windows-native-backend.md), [Windows guide](windows-native.md). |
| macOS | `Host` AppKit/Metal window/event/scene API; copied CoreText measurement; opt-in `NSTextInputClient` composition and public `TextInputHost` route with caret rectangle; bounded sample Button AX publish/take/revoke and TextField AX publish/revoke (role, value, UTF-16 selection, focus, frame) | A live Kotoeri sample observation exists, with synthetic HID input; exact-source shared consumer Dialog flow, candidate anchoring, physical keyboard and AX editing need separate evidence. Lower-ASCII sample key handling alone does not qualify committed-text/IME. | [GP-02-M][gp02m], [0026 macOS composition](../issues/open/0026-macos-text-composition-host.md), [0006 macOS](../issues/open/0006-macos-native-backend.md), [macOS guide](macos-native.md). |
| All native hosts | `AccessibilityModel`; transport-free Linux/Windows projections; sample-specific macOS Button, TextField and Dialog AX observation | Linux AT-SPI and Windows UIA providers, TextField set-value/actions, dialog actions, and assistive-technology acceptance remain **GP-03-AX**. Sample AXPress and copied TextField attributes are not a general AX bridge. | [GP-03][gp03], [0004 platform boundary](../issues/open/0004-platform-rendering-and-native-boundaries.md), [accessibility scope](accessibility.md), OS issues above. |

A method named `set_candidate_rect` or an exported text-session decoder does
not prove an active, qualified IME. The adapter must use the correct negotiated
route and report `UnsupportedCapability` when the required route is unavailable.
Do not map an unavailable service to a successful empty result. The test result
for an unexecuted runtime profile is `NOT_RUN`, even if its implementation is
unsupported; these are two different facts.

### Bounded remaining work

- **GP-01A (shipped)**: `text_session.TextSession` owns the shared adapter over
  existing text/field transactions with live window/root/field generations,
  revision, session and ordered preview/commit/cancel outcomes. It rejects
  stale/foreign/destroyed targets and preserves an observed OS commit instead of
  rewriting every blur to cancel. See [text_session](../text_session/).
- **GP-01B (implemented)**: `text_host` defines the optional native transport
  (`TextInputHost`, `TextInputState`, `TextInputEvent`), the shared
  `TextHostQueue` and `Capability::TextInputGeometry`. `platform/macos.Host`
  implements it over the AppKit composition client with an epoch-tagged, ordered
  text queue that stays separate from `next_event`. Windows and Ubuntu expose
  opt-in `TextHostRoute` adapters over their host-local editor sessions; they
  park platform records for a paired `next_platform_event` and reject records
  the insertion-only vocabulary cannot express. Their `Capability::TextInput`
  stays unadvertised until a real IME run qualifies the route. An unanswered
  route returns `UnsupportedCapability`. See
  [native text host](text-host-contract.md).
- **GP-01-GEOMETRY**: expose which exact cursor-stop, shaping, candidate-rectangle
  and range capabilities the host supports; reuse strict conversions. Broader
  grapheme/bidi behavior is a separate gate. Tie to GP-01 and 0004.
- **GP-02-L/W/M-IME**: adapt and qualify each OS against GP-01 separately. Linux
  and Windows are publication/ownership/qualification work over existing
  experimental routes, not blank-slate editor projects. macOS has the native text
  client; a live Kotoeri run through the Yami-kumo sample on 2026-10-21 recorded
  preedit, commit, committed-document and candidate-visibility `PASS` with
  synthetic HID posting, while candidate anchoring, physical-keyboard entry and
  AX editing remain unqualified. Keep each OS result independent.
- **GP-03-FOCUS**: portable `FocusScopeSession` now supplies the bounded live
  modal controller around existing focus/traversal. Hosts must wire its explicit
  cancellation hook, scoped input and Tab commands, and per-window ownership.
  Actual Dialog rendering/native input remains NOT_RUN; semantic/native AX work
  stays separate. See [focus scopes](focus-scopes.md).
- **GP-03-SEMANTICS / GP-03-AX**: extend only fields/actions needed by Button,
  TextField and Dialog; bind external actions to the current window/layout/owner
  and same domain handler. Keep model, external API and screen-reader tests
  separate. Tie to [GP-03][gp03], 0004 and relevant OS issues.

## Current text contract versus the M0 target

The [implemented text model](text-model.md) uses UTF-16 code-unit offsets in
`TextDocument`, `TextSelection`, `TextRange`, `TextComposition`, field state and
copied text geometry. The [platform M0 design](platform.md#text-and-ime) describes
a future UTF-8 byte-range/grapheme-alignment target. It is not permission to
change the current public offset unit globally.

At a UTF-8 boundary, use `TextDocument::utf8_offset` / `utf16_offset` against
the exact owning document/revision. Preserve direction by converting anchor and
head independently. Reject `SplitSurrogate`, `SplitUtf8`, negative/out-of-bounds
and overflow errors. Do not truncate, clamp or silently round. Scalar-valid
conversion alone does not establish a grapheme stop or a measured caret stop.
Native UTF-16 payloads still require well-formedness and exact revision/session
validation. Text encoding at a C ABI or JSON wire is separate from range units.

## Button comparison and vNext decision input

The [versioned fixtures](../tests/shared-ui-host/button-fixtures.json) were
specified before running the implementations. The [probe](../tests/shared-ui-host/button_probe.mbt)
executes both existing APIs directly; it contains no third Button controller.
The same key, repeat, pointer, bounds, cancel and loading operations are passed
to both adapters. `activated` is the action returned at that step, not a guessed
DOM click. `pressed` comes directly from each model. The legacy API does not own
focus or geometry: those adapter operations are explicitly marked
`caller-focus` / `caller-bounds`, and its focus observation is null. Focus loss
calls the existing legacy `cancel`; a bounds change deliberately does not until
a separate Cancel step, exposing the caller obligation.

| Fixture / observation | Existing Yami | Existing GPUI |
| --- | --- | --- |
| Enter down, repeat, up | Two activations; never remains pressed | One activation on nonrepeat down; pressed until matching up |
| Orphan repeated Enter | Activates | Suppressed |
| Orphan repeated Space, then up | Arms and activates on up | Repeat does not arm; no activation |
| Space down, repeat, up | One activation on up | Same |
| Space → Enter → Enter-up → Space-up | Enter activates and cancels Space | First held key wins; Space activates on final up |
| Enter → Space → Space-up → Enter-up | Two activations | One Enter activation; Space does not take ownership |
| Space → unrelated Escape-up → Space-up | Unrelated release cancels Space | Unrelated release leaves Space armed; final release activates |
| Pointer-down → Space-down → Space-up → pointer-up | Space supersedes pointer: one activation | Pointer and Space may both be armed: two activations |
| Space-down → pointer-down → pointer-up → Space-up | Pointer supersedes Space | Pointer-down is ignored while pressed; final Space-up activates |
| Primary-down → secondary-down → primary-up | Secondary down cancels ownership | Secondary down is ignored; primary-up activates |
| Disabled; outside primary release; explicit cancel | No activation | Same |
| Loading set / unset | No loading method; recorded `unsupported`, legacy state is unchanged | Both transitions cancel gestures; loading blocks activation and retains enabled focus |
| Identical bounds | Caller retains state | Retains state |
| Changed valid bounds | Caller must cancel; uncoordinated change leaves a pending press | Setter cancels pending gestures |
| Rejected subminimum bounds during press | No bounds validation in interaction; caller routing geometry changes | Setter rejects and preserves old state/bounds |
| 24×24 constructor | Accepted | Accepted |
| 23×24, 24×20 or 0×0 supplied hit bounds | `NativeButton::element_node` accepts caller bounds | `Button::new` rejects below 24×24 |

Legacy Yami `Xs` is intrinsically 20 logical points high. Its visual constructor
and hit-node builder do not impose GPUI's 24×24 minimum. An implicit replacement
would therefore change legacy dimensions or reject existing consumers. Source
inspection also shows different ID constraints: GPUI rejects logical ID zero;
Yami reserves the visual item range `id..id+5` and rejects overflow. The vNext
adapter must keep nonzero logical identity and visual item allocation separate.

Recommended additive vNext mapping for [YK-00][yk00]:

1. Keep legacy `NativeButton` / `ButtonInteraction` unchanged. Do not make
   legacy consumers inherit repeat, simultaneous-key, size or loading changes.
2. Use one existing GPUI Button as the new native model. Specify nonrepeat Enter,
   first-held-key ownership and loading-retains-focus explicitly in the vNext
   contract; reject undersized native bounds or choose ≥24×24 during vNext layout.
3. Copy no gesture state machine into Yami. A narrow native adapter may translate
   semantic input into existing public methods and dispatch `Activated` to the
   existing domain owner. Reconcile focus, bounds, removal and disposal explicitly.
4. Decide cross-modality ownership before promising DOM/native action parity.
   The existing GPUI pointer-plus-Space result is two actions; an audit must not
   silently deduplicate it or label it one action. A single-gesture policy would
   need a separately reviewed additive GPUI contract or explicitly documented
   adapter cancellation policy and new paired fixtures. It is not changed here.
5. DOM browser activation/focus/loading, scene rendering and native delivery
   each need real runtime evidence. These pure API observations are decision
   inputs, not proof that browser default events already match GPUI.

## Reproduce and retain evidence

From this GPUI checkout, with the documented MoonBit toolchain on `PATH` and a
separate Yami checkout at the desired pinned SHA:

```sh
python3 scripts/audit_shared_ui_buttons.py \
  --yami-source /path/to/Yami-kumo --target js \
  --output /path/to/evidence/button-js
# Repeat with --target native, wasm and wasm-gc for portable compiler targets.
python3 -m unittest discover -s tests/shared-ui-host -v
moon test controls/button text text_layout controls/text_field element core accessibility --target all --deny-warn
```

Each run retains `report.json`, raw stdout/stderr and the generated probe.
Reports record candidate/dependency SHA, dirty-worktree status, tracked-diff,
fixture/probe/runner hashes, command, toolchain, OS/architecture, exit code,
actual and expected per-step observations. No expectation-update mode exists;
any unknown difference fails. Missing output does not pass. A loading
`unsupported` observation is retained as such even when the audit itself passes.
A native compiler run here remains a headless Linux process, not Linux GUI,
Windows, macOS, browser DOM, IME or assistive-technology qualification.

The audit runner does not modify source manifests. The contracts workflow runs
the fixture command on all four compiler targets against the exact proposed GPUI
head and the pinned Yami revision, then retains the comparison artifacts.
Existing aggregate tests alone do not execute this external-consumer comparison.
Final publication still requires exact-head CI and independent review.

[plan]: https://github.com/f4ah6o/Yami-kumo/blob/21d85061e7445c479b483bcffa12679f7730d89a/docs/roadmaps/20261017-four-platform-gui/ROADMAP.md
[yk00]: https://github.com/f4ah6o/Yami-kumo/blob/21d85061e7445c479b483bcffa12679f7730d89a/issues/open/20261017-ui4-yk-00-architecture.md
[gp01]: https://github.com/f4ah6o/Yami-kumo/blob/21d85061e7445c479b483bcffa12679f7730d89a/docs/roadmaps/20261017-four-platform-gui/repos/gpui-mbt/gpui.mbt/issues/open/20261017-ui4-gp-01-text-host-contract.md
[gp02l]: https://github.com/f4ah6o/Yami-kumo/blob/21d85061e7445c479b483bcffa12679f7730d89a/docs/roadmaps/20261017-four-platform-gui/repos/gpui-mbt/gpui.mbt/issues/open/20261017-ui4-gp-02-l-linux-text-ime.md
[gp02w]: https://github.com/f4ah6o/Yami-kumo/blob/21d85061e7445c479b483bcffa12679f7730d89a/docs/roadmaps/20261017-four-platform-gui/repos/gpui-mbt/gpui.mbt/issues/open/20261017-ui4-gp-02-w-windows-text-ime.md
[gp02m]: https://github.com/f4ah6o/Yami-kumo/blob/21d85061e7445c479b483bcffa12679f7730d89a/docs/roadmaps/20261017-four-platform-gui/repos/gpui-mbt/gpui.mbt/issues/open/20261017-ui4-gp-02-m-macos-text-ime.md
[gp03]: https://github.com/f4ah6o/Yami-kumo/blob/21d85061e7445c479b483bcffa12679f7730d89a/docs/roadmaps/20261017-four-platform-gui/repos/gpui-mbt/gpui.mbt/issues/open/20261017-ui4-gp-03-focus-accessibility.md
