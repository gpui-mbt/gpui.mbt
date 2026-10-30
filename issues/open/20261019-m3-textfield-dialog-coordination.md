# M3 TextField / Dialog coordination across gpui-mbt and f4ah6o

Status: open — coordination and contract issue. This file records scope,
dependencies and evidence rules; it does not claim that any implementation or
runtime qualification is complete.

Priority: P1
Decision date: 2026-10-19
Related: [GP-01B text host](20261019-gp-01b-text-host-contract.md),
[0004 platform rendering](0004-platform-rendering-and-native-boundaries.md),
[0006 macOS](0006-macos-native-backend.md),
[0007 Ubuntu](0007-ubuntu-native-backend.md),
[0008 Windows](0008-windows-native-backend.md)

## 1. Goal

Coordinate the existing four-platform plan in
[`f4ah6o/Yami-kumo/docs/roadmaps/20261017-four-platform-gui`](https://github.com/f4ah6o/Yami-kumo/blob/main/docs/roadmaps/20261017-four-platform-gui/ROADMAP.md)
with the actual gpui.mbt implementation state. The next product milestone is one
shared `model / view / update` that edits Japanese text, validates it, opens a
confirmation Dialog, restores focus correctly, and reports each platform
separately.

The controlling repositories are:

| Repository | Owns | Does not own |
| --- | --- | --- |
| `gpui-mbt/gpui.mbt` | portable TextField/`text_session`, host transport, focus scope, semantic tree, OS renderer | Yami component API, app-specific validation |
| `gpui-mbt/gpui-conformance` | fixtures, comparison rules, retained evidence | framework fixes or app UI |
| `gpui-mbt/gpui-mbt-app-demo` | one real consumer on macOS/Web/Windows, later Linux | production support claims |
| `f4ah6o/Yami-kumo` | shared View/runtime, DOM and native adapters, Shared Settings | OS text-input or GPU backend reimplementation |
| `f4ah6o/dsh.mbt` | late app canary | TextField/IME testbed (it does not import `controls/text_field`) |
| `f4ah6o/vlmkit` | optional screen/AX observation | correctness oracle for text bytes |

`MZed`, `turtles.mbt`, `hotpath.mbt`, `raden.mbt`, `container.mbt`, `mp4.mbt`
and the `deepseek-harness` fork are outside this milestone. `turtles.mbt` may
run scoped mutation on the new text packages; `MZed` and `hotpath.mbt` remain
post-M3.

## 2. Actual state to reconcile

The numbered observations below describe the 2026-10-19 audit, not current
main. In particular, the macOS composition bridge and public `TextInputHost`
route have since landed; see [0026](0026-macos-text-composition-host.md) and
the current [text host contract](../../docs/text-host-contract.md). The later
live Kotoeri sample observation does not establish exact-source acceptance of
the shared TextField/Dialog flow.

1. `text_session/` is merged and portable-tested, but no host or example imports
   it. `platform.Backend` has no text-session method.
2. `element.FocusScopeSession` exists as a portable modal controller, but no
   native Dialog consumes it.
3. `accessibility/` has role/name/bounds and `Invoke` only; TextField value and
   selection are not represented.
4. macOS text input exists only in draft PRs #89/#107. Main has no
   `NSTextInputClient` bridge, and real Kotoeri acceptance is `NOT_RUN`.
5. Ubuntu/Wayland has an opt-in text-input-v1 route; Windows has a private
   default-off IMM32 route. Neither is a shared public text contract.
6. Yami's `manifest.json` still marks YK-01/02 as not started, although
   `ui/core`, `ui/runtime`, `ui/dom` and `native/ui` are merged and tested.
7. Consumers point at four different GPUI revisions: Yami native `0.7.2`, Yami
   shared source `4c2e525f`, published `0.9.0`, conformance `0.7.2`.

## 3. Work packets

### GP-01B — native text host seam

Add the optional `text_host.TextInputHost` package, `TextInputState` /
`TextInputEvent`, and `Capability::TextInputGeometry`. Keep `Backend` unchanged.
See [the contract](../docs/text-host-contract.md).

### GP-02-L / GP-02-W / GP-02-M — per-OS routes

Connect the existing Linux and Windows experimental routes through the host seam.
Rebase and qualify the macOS draft. Each OS has its own evidence row; one OS
does not fill another. Real Japanese IME and candidate placement remain separate
from build or synthetic-event success.

### GP-03-FOCUS / GP-03-SEMANTICS / GP-03-AX

Wire `FocusScopeSession` into the Dialog host path. Extend the semantic tree only
for the fields/actions needed by Button, TextField and Dialog. Native OS
accessibility providers remain post-M3 unless an exact-source profile is run.

### YK-06 / YK-07 / YK-08

Yami adds `NodeKind::TextField` / `NodeKind::Dialog`, DOM and native adapters,
and one Shared Settings consumer. YK-08 produces the six-layer matrix; missing
profiles and `NOT_RUN` rows cannot become `PASS`.

## 4. Merge and evidence rules

- Contract PRs land before adapter PRs. Shared enums and manifests are changed
  by one integrator, not by parallel platform lanes.
- Every PR names its candidate revision, dependency revision, profile, command,
  result and artifact. `PASS` requires an exact-source execution.
- `UNSUPPORTED` and `NOT_RUN` are retained. A build-only or synthetic-input run
  is not a physical-input or IME pass.
- A consumer uses public APIs from a published or explicitly pinned candidate.
  Private host APIs and local patches cannot hide a missing contract.
- Existing `ecosystem-merge-v1` rules apply: latest HEAD checks green, independent
  review of the same HEAD, no unresolved P0/P1.

## 5. Completion checks

- [ ] `text_host` is implemented by at least one non-test host and consumed by a
      real adapter.
- [ ] Yami's TextField uses only public gpui APIs for its native path.
- [ ] Shared Settings edits Japanese text and validates it on Web and at least
      one native profile.
- [ ] Dialog blocks background input and restores focus on the same profiles.
- [ ] macOS, Linux and Windows rows state their actual IME/AX evidence, including
      `NOT_RUN` where no profile was executed.
- [ ] gpui 0.10.0 and the Yami preview pin agree; no consumer retains a source
      revision pin.
- [ ] conformance owns `text-field` / `ime` / `dialog` layers with negative
      controls for missing or stale evidence.

## 6. Non-goals

No new `controls/dialog` package in gpui.mbt; Dialog layout belongs to Yami. No
full OS accessibility provider in this milestone. No `MZed` editor work, no
`raden.mbt`/`mp4.mbt`/`container.mbt` integration, and no changes to the
`deepseek-harness` fork. No production support-tier promotion from this
coordination issue alone.
