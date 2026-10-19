# 0027: Windows IME composition transport and desktop integration

Status: open — gpui host transport implemented; dsh integration and physical IME acceptance pending
Model: deepseek-v4.1-flash:1017-cloud
Created: 2026-10-19
Updated: 2026-10-19
Branch: feat/20261019-windows-ime-composition
Related: [0026 macOS text composition host](0026-macos-text-composition-host.md),
[0025 Windows Button integration](0025-windows-button-integration.md),
[Windows native guide](../../docs/windows-native.md),
[dsh issue 0005](https://github.com/f4ah6o/dsh.mbt/blob/main/issues/polished/0005-macos-ime-composition.md)

## 概要

Windows native host に bounded な IME composition transport を追加し、dsh の desktop
composer を `DSH_DESKTOP_IME=1` で Windows の Microsoft IME に接続する。
macOS 0.10.0 で確立した `EventKind::Composition` と同じ 4 状態だけを扱い、full editor や
surrounding-text semantics は追加しない。

## 背景

macOS の composition increment で次が利用可能になった。

- `primitives.CompositionEvent`（`Start` / `Update(text, cursor_utf16)` / `Commit(text)` / `Cancel`）。
- `platform.EventKind::Composition`。通常の key/pointer routing とは分離された document-owner event。
- `Host::set_text_composition` / `set_text_composition_caret` / `finish_text_composition`。
- dsh の `desktop/app_composition.mbt` にある platform-neutral な preedit / commit / cancel state machine と、
  `desktop_sync_composition_enabled` の opt-in gate。

Windows には既に private な IMM32 text session がある。

- [`windows/text_session.mbt`](../../windows/text_session.mbt): `CompositionStarted` / `Marked` /
  `Inserted` / `CompositionEnded` / `Cancelled` と `Host::begin_text_session` /
  `update_text_session` / `cancel_text_session` / `end_text_session`。
- `GPUI_WINDOWS_FIELD_IME=1` は field example 専用で default off。通常の
  `next_event` / `TextInput` capability には公開されていない。
- [`docs/windows-native.md`](../../docs/windows-native.md) の "Private experimental IMM32 input"。

dsh の Windows entrypoint は現在 `supports_text_composition: false` で、Linux / X11 と同じ
typed `UnsupportedCapability` fallback を設定している。

## 問題

- Windows の dsh desktop composer は IME composition を受け取れず、日本語入力は paste のみ。
- 既存 IMM32 session は full editor 向けの typed FIFO で、dsh が使う
  `Backend::next_event` / `EventKind` には composition が現れない。
- `TextInput` と composition commit の二重挿入、Enter / Escape の二重配送、focus loss 後の
  stale preedit を防ぐ経路が Windows では未検証。
- candidate window の位置と DPI / 複数 display の扱いが未実装。

## 目標

- Windows host で composition を opt-in 有効化でき、preedit / commit / cancel が
  `EventKind::Composition` として通常の event queue に順序どおり現れる。
- dsh composer が macOS と同じ表示・確定・取消・送信・focus fence を Windows でも行う。
- synthetic native E2E と dsh offline E2E が Windows で pass し、実機 Microsoft IME の
  manual acceptance 手順が記録される。

## 対象外

- full text editor、selection、undo/redo、reconversion、clause styling、attributed replacement range。
- surrounding text / deletion / postinsert cursor の完全適用。
- UI Automation accessibility、native menus、default-on composition。
- Windows 以外の IME（Linux / X11 は [0028](0028-wayland-ime-composition-handoff.md)）。
- 既存 `GPUI_WINDOWS_FIELD_IME=1` field session の仕様変更。

## 提案する方針

### 1. portable host API

macOS と同じ 3 API を Windows host に追加する。ABI op 番号は macOS と揃える必要はなく、
Windows の `gpui_windows_*` C boundary に新しい op を足す。

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

- `set_text_composition(true)` は composition-only の IMM32 session を arm し、content view を
  focused target にする。`false` は pending preview を cancel して disarm する。
- `set_text_composition_caret` は logical client 座標の caret を受け取り、DPI 変換後に
  `ImmSetCompositionWindow` / `ImmSetCandidateWindow` へ渡す。失敗しても composition 自体は継続する。
- `finish_text_composition(true)` は現在の marked text を commit、`false` は cancel する。
  marked text が無い場合は event を publish しない。

### 2. event queue

dsh が使う通常の `next_event` に composition frame を流す。既存の typed editor FIFO は
field example 用にそのまま残す。

- 第一候補: composition-only mode では native IMM32 callback から通常 queue の kind 17
  相当へ frame を直接 enqueue する。macOS の `emit_composition` と同じ形。
- 第二候補: host の `next_event` が composition mode 中だけ `next_editor_event` を内部で drain し、
  `TextSessionEvent` を `EventKind::Composition` に変換する。この場合は
  `EditorEvent::Platform` を通常 event として返し、typed queue head の不変条件を壊さないこと。
- どちらでも、既存 field session が armed のときに composition frame を混ぜない。

### 3. state mapping

| IMM32 record | CompositionEvent | 注意 |
| --- | --- | --- |
| `CompositionStarted(replacement_range)` | `Start` | 同じ transaction で 1 回だけ。replacement range は dsh が保持する captured selection と独立。 |
| `Marked(text, cursor_utf16, ..)` | `Update(text, cursor_utf16)` | `None` は text 末尾。空 text は `Cancel` と同じ。UTF-16 bounds を再検証。 |
| `Inserted(text, ..)` | `Commit(text)` | commit 後に `CompositionEnded` が来ても二重 `Cancel` を出さない。 |
| `CompositionEnded` | 状態に応じて `Cancel` または無視 | `Inserted` 済みなら無視。active preview だけなら `Cancel`。 |
| `Cancelled` | `Cancel` | preview だけを破棄し、commit 済み text は retract しない。 |

- preedit は 16,384 UTF-16 code units、commit は 65,536 を上限とし、超過は typed error。
- `Update` の cursor は `0 <= cursor <= text.length()`。負値・非整数・範囲外は `InvalidInput`。
- Enter / Escape は IMM が active な間は IME が消費し、アプリへ duplicate `KeyPressed` を
  流さない。commit 後の Enter は通常の送信 key として 1 回だけ届くこと。

### 4. dsh integration

[`desktop/windows/main.mbt`](https://github.com/f4ah6o/dsh.mbt/blob/main/desktop/windows/main.mbt)
で `supports_text_composition: true` とし、3 callback + `post_test_composition` を host に接続する。

- `desktop_sync_composition_enabled` は既に `DSH_DESKTOP_IME=1` / focus / settings を見るため、
  原則として変更不要。Windows でも同じ opt-in を使う。
- `desktop_handle_event` の `Composition` 経路は platform-neutral。`TextInput` は composition 中に
  無視される既存 guard を維持する。
- `desktop_finish_composition` は cancel 成功時に local state を即時 clear する。Windows でも
  native marked text が残らないことを E2E で確認する。
- `desktop/windows/main.mbt` の `post_test_composition` は `GPUI_NATIVE_E2E=1` のみ許可し、
  通常起動では typed error にする。

### 5. tests

- portable: composition mapping の bounds、空 preedit、cursor clamp、二重 commit / cancel、
  `Inserted` 後の `CompositionEnded`。
- native: `post_test_composition` で Start / Update / Commit / Cancel、printable key、
  Enter commit の非重複、Escape cancel の非重複。
- dsh: `--offline-e2e` に synthetic composition を含め、成功 marker に
  `"ime_composition":true` を追加。Windows では frame capture も確認する。
- 実機: Microsoft IME で `にほんご` → 変換 → `日本語` commit、Escape cancel、
  Send click の commit-then-send、focus loss / Settings / New / session switch での cancel。

## 受け入れ条件

- [x] Windows host の `set_text_composition` / `set_text_composition_caret` /
  `finish_text_composition` が bounds を検証し、失敗時に composition を壊さない。
  （gpui host 実装済み。invalid caret は FFI 前に拒否し、active composition を維持する。）
- [x] preedit / commit / cancel が `EventKind::Composition` として通常 queue に順序どおり出る。
  （kind 17 + UTF-8 sidecar。portable と synthetic native E2E で確認。）
- [x] composition 中に `TextInput` と commit が二重挿入しない。
  （合成 WndProc staging で commit 後の `WM_CHAR` / `WM_IME_CHAR` を END まで抑制。）
- [x] composition 中の Enter / Escape がアプリへ二重配送されない。
  （合成 WndProc staging で `WM_KEYDOWN` / `WM_IME_KEYDOWN` を消費。）
- [ ] focus loss / Settings / New / session switch / approval / response cancel で
  native marked text が残らない。host-side の focus loss / disable / destroy / stop は
  実装・staging 済みだが、dsh の Settings / New / session switch / approval 経路は未接続。
- [ ] candidate window が composer caret 付近に出る（1x / 高 DPI を各 1 回）。
  synthetic の DPI 変換は staging 済み。実機の candidate window は未確認。
- [ ] synthetic native E2E と dsh offline E2E が Windows で pass する。
  gpui synthetic native E2E は pass。dsh offline E2E は gpui 公開後の stage 2 で対応。
- [ ] 実機 Microsoft IME の manual acceptance が記録される。synthetic pass を実機受入として
  扱わない。
- [x] `CHANGES.md` の Migration / Limitations に Windows の scope と未検証事項を書く。

## gpui.mbt implementation notes

この変更は handoff order の stage 1（gpui host）だけを実装する。dsh の
`desktop/windows/main.mbt` はまだ `supports_text_composition: false` で、gpui の
公開後に stage 2 として接続する。

- 公開 API: `windows/ime.mbt` の `Host::set_text_composition`、
  `set_text_composition_caret`、`finish_text_composition`。
- C boundary: `gpui_windows_set_text_composition`、
  `gpui_windows_set_text_composition_caret`、`gpui_windows_finish_text_composition`、
  `gpui_windows_composition_text_size`、`gpui_windows_composition_text_copy`。
- event: 通常 queue の kind 17。field 4 = preedit cursor、field 5 = UTF-16 units、
  field 8 = code (0 Start / 1 Update / 2 Commit / 3 Cancel)。UTF-8 は sidecar。
- 上限: preedit 16,384 UTF-16 units、commit 65,536 units、sidecar 256 KiB、
  pending payload 1 MiB、queue 4096 records。
- 排他: composition-only session と `GPUI_WINDOWS_FIELD_IME` typed session は
  同時に armed にできない。2 つ目の owner は Busy。
- test hook: `Host::post_test_composition`。`GPUI_NATIVE_E2E=1` のみ許可し、
  `GPUI_WINDOWS_E2E=1` の native test から駆動する。
- 実装ファイル: `windows/ime.mbt`、`windows/text_composition.inc`、
  `windows/text_composition_e2e.inc`、`windows/backend.c`、`windows/backend.h`、
  `windows/backend.mbt`、`windows/testing.mbt`。
- 検証: `windows/ime_wbtest.mbt`（portable）、
  `windows/ime_e2e_wbtest.mbt`（synthetic native + C staging）、
  `scripts/test_windows.ps1` の 2 つの composition filter。

## テスト計画

```powershell
# gpui.mbt
moon version --all
moon update
moon install
moon check --target native --deny-warn
moon test windows --target native --deny-warn
moon test examples/windows_text_field --target native --deny-warn
pwsh -NoProfile -File scripts/run_windows_text_field.ps1 -Mode Smoke

# dsh.mbt
moon check --target native --deny-warn
moon test desktop/windows --target native --deny-warn
pwsh -NoProfile -File scripts/build-desktop-windows.ps1 -Mode E2E
python scripts/test-windows-desktop.py --no-build
python scripts/test-windows-runtime.py --exe _build/native/release/build/cmd/dsh/dsh.exe
```

- 実機 IME は interactive desktop session で実行する。SSH の非対話 session では
  D3D11 window と IME candidate window を検証できない。
- 1x と 150% / 200% DPI で candidate window の位置を screenshot または frame で記録する。

## リスク

- Win32 IMM32 message の到着順は OS 依存で、application epoch を持たない。stale message を
  完全には識別できない。focus / context fence と、新しい composition start を要求する既存方針を維持する。
- `next_event` と typed editor FIFO の二重 drain は field example を壊し得る。composition mode と
  field session を同時に armed にしない invariant を test で固定する。
- `ImmSetCandidateWindow` の座標は client / screen / DPI の変換ミスが起きやすい。
  caret rect の境界と DPI を unit test し、実機で確認する。
- SSH 経由の自動実行は session 0 になり、GUI / IME の受入にならない。RDP または
  interactive scheduled task で実行する。
- default-on にしない。実機 IME の受入が完了するまで `DSH_DESKTOP_IME=1` opt-in を維持する。

## 変更履歴

`CHANGES.md` impact: yes

項目案：

- Add opt-in Windows IME composition for the native desktop composer through the bounded
  `EventKind::Composition` transport. Windows / Linux IME remains opt-in and physical
  Japanese IME acceptance is recorded separately.

## 注記

### Remote execution prerequisites

- Windows 11 x64、interactive desktop が logged in されていること。
- Japanese IME（Microsoft IME）が installed / enabled であること。
- Visual Studio 2022 Build Tools の x64 C++ workload。
- MoonBit `0.10.15+943464bfa`（現行 CI pin）。
- Git、PowerShell 7、Python 3。
- 自動実行する場合:
  - OpenSSH Server を有効化し、`sshd` を起動する。
  - SSH は非対話 session になるため、GUI E2E は RDP セッション内の terminal か
    `schtasks /create ... /it` で interactive user として起動する。
  - 可能なら host 上に DSH / Codex の remote agent を置き、workspace を直接操作する。

### Handoff order

1. gpui の API + event queue + synthetic native E2E。
2. dsh entrypoint + offline E2E。
3. 実機 Microsoft IME の manual acceptance。
4. docs / CHANGES / status 更新。

各段階で synthetic pass と physical pass を分けて記録する。
