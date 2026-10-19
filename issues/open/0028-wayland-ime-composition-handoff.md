# 0028: Wayland/Linux IME composition transport and desktop integration

Status: bounded implementation; compositor and physical IME acceptance pending
Model: deepseek-v4.1-flash:1017-cloud
Created: 2026-10-19
Updated: 2026-10-19
Branch: feat/20261019-wayland-ime-composition
Related: [0026 macOS text composition host](0026-macos-text-composition-host.md),
[0027 Windows IME composition](0027-windows-ime-composition-handoff.md),
[Ubuntu Wayland text sessions](../../docs/ubuntu-ime.md),
[dsh issue 0005](https://github.com/f4ah6o/dsh.mbt/blob/main/issues/polished/0005-macos-ime-composition.md)

## 概要

Wayland native host の既存 text-input-v1 session を、dsh が使う bounded な
`EventKind::Composition` transport に接続する。対象は `DSH_DESKTOP_IME=1` の opt-in だけで、
full editor、surrounding text、X11/XIM は追加しない。

## 背景

macOS 0.10.0 で platform-neutral な composition 契約ができた。

- `primitives.CompositionEvent`（`Start` / `Update(text, cursor_utf16)` / `Commit(text)` / `Cancel`）。
- `platform.EventKind::Composition` と 3 つの host API。
- dsh の `desktop/app_composition.mbt` は既に preedit / commit / cancel / focus fence /
  commit-then-send を platform-neutral に実装している。

Linux には既に experimental な Wayland text session がある。

- [`ubuntu/ime.mbt`](../../ubuntu/ime.mbt): `Preedit` / `Commit` / `Entered` / `Left` /
  `ForwardedPressed` / `ForwardedReleased`、`Host::begin_text_session` /
  `update_text_session` / `cancel_text_session` / `set_text_session_panel` /
  `end_text_session` / `next_editor_event`。
- [`docs/ubuntu-ime.md`](../../docs/ubuntu-ime.md): Weston 14 desktop-shell + text-input-v1、
  stock IBus 1.5.32 の Wayland adapter + Mozc、同期 IBus mode が bounded target。
- `GPUI_FIELD_WAYLAND_IME=1` は field example 専用。dsh の `next_event` には composition が
  現れない。
- X11 は text-input-v1 を持たない。XIM はこの packet の対象外。

dsh の Linux entrypoint は Wayland / X11 とも現在 `supports_text_composition: false`。

## 問題

- dsh の Linux Wayland desktop は IME composition を受け取れず、日本語入力は paste のみ。
- 既存 text session は committed document / selection / surrounding text を要求する full editor
  owner 向けで、dsh の bounded composer API と直接は一致しない。
- `next_event` と `next_editor_event` の二重 queue、DirectKeyboardText との競合、
  Enter / Escape / Send の commit 解決が未検証。
- candidate popup の位置・表示は compositor / IBus 側で、物理 display での受入が未実行。

## 目標

- Wayland host で composition を opt-in 有効化でき、preedit / commit / cancel が
  `EventKind::Composition` として通常の `next_event` に順序どおり現れる。
- dsh composer が macOS と同じ preedit 表示、commit / cancel、commit-then-send、
  focus fence を Wayland でも行う。X11 は typed unsupported のまま。
- headless Weston の synthetic E2E と、IBus + Mozc の manual acceptance 手順を記録する。

## 対象外

- full text editor、selection、undo/redo、reconversion、clause styling、surrounding deletion /
  postinsert cursor の適用。
- text-input-v2/v3、XWayland、X11/XIM、他の compositor の一般対応。
- candidate table の選択操作、IME repeat、accessibility。
- default-on composition、physical IME 未受入での「日本語 IME 対応」表明。

## 提案する方針

### 1. portable host API

Wayland host に macOS と同じ API を追加する。

```moonbit
pub fn Host::set_text_composition(
  self : Host, window : @platform.WindowId, enabled : Bool,
) -> Result[Unit, @diagnostics.FrameworkError]

pub fn Host::set_text_composition_caret(
  self : Host, window : @platform.WindowId, caret : @primitives.Rect,
) -> Result[Unit, @diagnostics.FrameworkError]

pub fn Host::finish_text_composition(
  self : Host, window : @platform.WindowId, commit : Bool,
) -> Result[Unit, @diagnostics.FrameworkError]
```

- `set_text_composition(true)` は composition-only session を arm する。committed document は
  空、selection は caret に collapse した状態で `begin_text_session` を呼ぶ。
- `set_text_composition_caret` は `update_text_session(..., external_edit=false)` で caret 矩形だけを
  更新する。surface-logical の整数座標・正の整数サイズを検証する。
- `finish_text_composition(true)` は host が保持する最新 preedit を `Commit` として publish し、
  native session を cancel / end する。text-input-v1 には app からの commit request が無いため、
  この synthetic commit で commit-then-send を決定的にする。
- `finish_text_composition(false)` は `Cancel` を publish して session を cancel / end する。
- pending preedit が無い場合は event を publish しない。

### 2. event queue

dsh は `Backend::next_event` しか呼ばない。Wayland host の `next_event` から composition frame を
返せるようにする。

- composition-only mode では `next_event` が内部で `next_editor_event` を drain し、
  `TextSessionEvent` を `EventKind::Composition` に変換する。
- `EditorEvent::Platform(event)` はそのまま通常 event として返す。
- field example の `EditorEvent` 利用と同時に armed にしない。composition mode 中は
  field session を拒否する invariant を test で固定する。
- `DirectKeyboardText` は `begin_text_session` が disarm する既存挙動を維持し、
  composition 中の printable key が dsh の `desktop_insert_text` に二重に入らないこと。

### 3. state mapping

| text-input-v1 record | CompositionEvent | 注意 |
| --- | --- | --- |
| `Entered` | なし | v1 focus の証明だけ。preedit 開始とは限らない。 |
| 最初の `Preedit(text, cursor_utf16, ..)` | `Start` + `Update` | Start は 1 transaction に 1 回。 |
| 続く `Preedit(...)` | `Update` | `cursor_utf16=None` は text 末尾。空 text は `Cancel`。 |
| `Preedit` 空 / `Left` | `Cancel` | active なときだけ。commit 後の `Left` は無視。 |
| `Commit(text, deletion, position)` | `Commit(text)` | `deletion` / `position` が non-null なら bounded composer では適用しない。typed reject して Cancel するか、明示的に unsupported と記録する。 |
| `ForwardedPressed/Released` | 通常の `Input` / key handling | Enter / Escape の二重配送を防ぐ。 |
| `ForwardedReleased` | 通常の `Input` | text を生成しない。 |

- preedit は 16,384 UTF-16 code units、commit は 65,536 を上限とする。
- 既存 decoder が UTF-8 cursor を UTF-16 に変換している。composition でも
  `text.length()` と `cursor_utf16` の関係を再検証する。
- empty committed document のため surrounding text は送らない。deletion / position を
  silently 適用しない。

### 4. dsh integration

[`desktop/linux/main.mbt`](https://github.com/f4ah6o/dsh.mbt/blob/main/desktop/linux/main.mbt)
の Wayland host だけ `supports_text_composition: true` とし、3 callback +
`post_test_composition` を接続する。`start_x11()` は `false` と typed fallback を維持する。

- `desktop_sync_composition_enabled` は `DSH_DESKTOP_IME=1` / focus / settings を見る既存 gate を
  そのまま使う。
- `desktop_handle_event` の `Composition` 分岐と `TextInput` guard は platform-neutral。
- `desktop_send` は composition 中に `finish_text_composition(true)` を呼び、host が返す
  synthetic `Commit` で draft を更新してから送る。
- focus loss / Settings / New / session switch / approval / response cancel では
  `desktop_finish_composition(false)` が native session も終了させる。
- `desktop/linux/main.mbt` の `text_input_events: true` は Wayland の direct keyboard 用。
  composition 中に direct text が復活しないことを E2E で確認する。

### 5. tests

- native ingress: `sh scripts/test_ubuntu_ingress.sh` に composition 変換の unit を追加。
- native E2E: headless Weston で `post_test_composition` 相当の Start / Update / Commit / Cancel、
  cursor bounds、空 preedit、Enter / Escape の非重複。
- dsh offline E2E: `DSH_DESKTOP_IME=1`（synthetic は `GPUI_NATIVE_E2E=1`）で
  `"ime_composition":true` を記録。frame / candidate caret を確認。
- 実機: Weston 14 + IBus 1.5.32 sync + Mozc で `にほんご` → 変換 → `日本語` commit、
  Escape cancel、Send の commit-then-send、focus loss / Settings / session switch の cancel。
- 物理 display が無い場合は headless の protocol / E2E だけを pass とし、candidate popup と
  物理 IME は NOT RUN と記録する。

## 受け入れ条件

- [ ] Wayland host の 3 API が bounds を検証し、失敗時に composition を壊さない。
- [ ] `next_event` に composition が順序どおり出て、field example の `EditorEvent` と競合しない。
- [ ] DirectKeyboardText と composition が二重挿入しない。
- [ ] Enter / Escape / Send が 1 回だけ commit / cancel / send する。
- [ ] focus loss / Settings / New / session switch / approval / response cancel で
  native preedit が残らない。
- [ ] X11 は引き続き typed unsupported で、Wayland だけが opt-in 有効になる。
- [ ] headless Weston synthetic E2E と dsh offline E2E が pass する。
- [ ] IBus + Mozc の manual acceptance、または NOT RUN の理由が記録される。
- [ ] `CHANGES.md` の Migration / Limitations に Wayland-only scope を書く。

## テスト計画

```sh
# gpui.mbt
sh scripts/prepare_ubuntu.sh
sh scripts/test_ubuntu_ingress.sh
sh scripts/test_ubuntu.sh
moon test ubuntu --target native --deny-warn
moon test examples/linux_text_field --target native --deny-warn

# dsh.mbt
moon check --target native --deny-warn
moon test desktop --target native --deny-warn
sh scripts/build-desktop-linux.sh --build
python3 scripts/test-linux-desktop-payload.py
python3 scripts/smoke-release-linux.py
```

- headless compositor:
  `sh scripts/start_ubuntu_test_compositor.sh --socket=gpui-e2e`
- 実機 IME:
  `IBUS_ENABLE_SYNC_MODE=1`、compositor が adapter を `WAYLAND_SOCKET` 付きで起動、
  `DSH_DESKTOP_IME=1` で dsh desktop を起動。
- candidate popup は screenshot / frame で記録する。

## リスク

- text-input-v1 は compositor / IBus adapter 依存。Weston 14 desktop-shell + stock IBus の
  bounded profile 以外は未検証のままにする。
- `next_event` と `next_editor_event` の二重 drain、DirectKeyboardText の復活、
  forwarded key の二重配送が最も壊れやすい。mode invariant と E2E で固定する。
- app から commit を要求できないため、`finish_text_composition(true)` は host の cached preedit を
  synthetic commit する。IME 側の未確定 clause / candidate 状態と一致しない可能性を
  Limitations に書く。
- deletion / position / surrounding text を bounded composer に適用しない。必要な IME では
  別 packet で full text session を使う。
- X11 / XWayland は対象外。Wayland でしか capability を advertise しない。
- SSH だけの headless 環境は candidate window の物理受入にならない。NOT RUN を明示する。

## 変更履歴

`CHANGES.md` impact: yes

項目案：

- Add opt-in Wayland IME composition for the native desktop composer by bridging the
  experimental text-input-v1 session to `EventKind::Composition`. X11 and physical
  Japanese IME acceptance remain out of scope.

## 注記

### Remote execution prerequisites

- Ubuntu 24.04 x86-64 / ARM64、Weston 14、IBus 1.5.32、Mozc、fontconfig、CJK fonts。
- 依存 package は release workflow の Linux install と同じ:
  `libssl-dev pkg-config libwayland-dev wayland-protocols libegl1-mesa-dev
  libgles2-mesa-dev libxkbcommon-dev libpango1.0-dev libx11-dev libfontconfig1-dev
  libgl1-mesa-dri libegl-mesa0 weston xvfb xauth xdotool x11-utils xclip fonts-noto-cjk`。
- MoonBit `0.10.15+943464bfa`（現行 CI pin）。
- SSH-only の場合:
  - `dbus-run-session` と headless Weston で protocol / synthetic E2E は実行できる。
  - 実機 IBus の candidate popup は interactive Wayland session（physical display / VNC）で
    確認する。SSH だけの結果を physical IME pass にしない。
  - compositor が IBus adapter を `WAYLAND_SOCKET` 付きで起動できる権限・環境が必要。

### Handoff order

1. host API + `next_event` 変換 + bounds tests。
2. dsh Wayland entrypoint + offline E2E。
3. headless Weston + IBus の synthetic acceptance。
4. physical display の candidate / 変換 acceptance、または NOT RUN 記録。
5. docs / CHANGES / status 更新。

X11 は同じ branch に混ぜず、必要なら別 issue にする。


## Implementation checkpoint (2026-10-19)

Core implementation is in `ubuntu/composition.mbt` and the native shared queue.
The native queue, rather than a read-time MoonBit expansion, assigns distinct
sequence numbers to Start/Update and preserves ordinary event ordering. The
existing editor transport remains independently usable and mutually exclusive.
The transport retains its existing 4096 UTF-8 byte ceiling. Unsupported
surrounding deletion/postinsert-position commits are discarded with preview
cancellation; no full-document semantics are claimed.

Finish keeps composition opt-in while fencing/rearming the native session, so
applications can accept the terminal event and continue typing without a focus
toggle. Disable ends mode and allows deferred direct-text restoration.

Native callback fixtures and FFI-linked MoonBit tests are recorded separately
from runtime acceptance in `docs/ubuntu-ime.md`. Compositor E2E was blocked by
cloud Unix-socket restrictions and a pre-execution escalation setup failure;
physical IBus/Mozc and candidate placement remain NOT RUN. The dsh integration
is a separate companion change; do not mark its offline E2E complete based only
on these core transport tests.
