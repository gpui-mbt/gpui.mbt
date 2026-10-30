# 実アプリ利用までの開発方針・順序・完了判定を統一する

Status: open
Model: GPT-6 Astra Pro
Created: 2026-10-30
Updated: 2026-10-30
Branch: docs/20261030-development-policy

## 概要

既存の実装と受入証拠を基準に、gpui.mbtを実アプリで使うまでの開発順序、リポジトリ間の責務、完了判定を整理する。既存の実装Issueを索引として再利用し、不足している横断調査だけを子チケットにする。

## 背景

調査基準はmain `3db0c94a43cda694d615205ecb9d1abf778638e8`、確認日は2026-10-30 JST。[`moon.mod`](https://github.com/gpui-mbt/gpui.mbt/blob/3db0c94a43cda694d615205ecb9d1abf778638e8/moon.mod)のバージョンは0.10.6。これは宣言された版であり、Mooncakes公開状態の再確認結果ではない。

長期目標は[product charter](0001-product-charter-and-compatibility.md)、責務とマージ運用は[ecosystem charter](20261015-ecosystem-charter-and-merge-gates.md)、直近の共有UIは[TextField / Dialog coordination](20261019-m3-textfield-dialog-coordination.md)、1.0判定は[release gates](0005-production-readiness-and-release-gates.md)に既に存在する。本地図はそれらを現在の実装・証拠・次の作業へ結び付ける。

`docs/status.md`のM3は「scene/rendering基盤」、20261019 coordinationのM3は「共有TextField/Dialog受入」を指す。本地図では後者を「共有GUI受入」と呼び、異なるmilestoneを同一の完了条件として扱わない。

## 問題

1. 古い現状説明に「text_sessionを利用するhostがない」「mainにNSTextInputClient bridgeがない」等が残り、新しい実装・追記と矛盾している。
2. APIの存在、headless成功、synthetic OS入力、実IME、物理入力、候補一覧、支援技術、production supportの証拠が異なる。単一の完了フラグでは次の不足を判断できない。
3. PR #155はharnessと実行appのrevisionが別に固定される。旧run成功や最新workflowの失敗を、現mainの実装・実IMEの成否へそのまま転用できない。
4. 公開APIとconsumerの現在の依存関係を再照合せず、既存実装を再作成したり、古い固定版を前提に新APIを増やす危険がある。

## 目標

既存コード・公開API・consumer・OS別証拠・実装Issueを対応付け、次のセッションが着手先と検証条件を選べる状態にする。調査で判明した不足は既存Issueへ戻し、独立した不足だけを通常の実装Issueへ切り出す。

直近の共有GUI受入の目標は、同じmodel / view / updateを使う一つのconsumerで、日本語編集 → 検証 → 確認Dialog → フォーカス復帰をWebと少なくとも一つのnative profileで確認すること。最初のnative対象はLinux、次にApple Silicon macOSの独立受入を進める。この地図の完了、共有GUI受入、1.0公開は別々に判定する。

## 対象外

全面的なGPUI/Zed移植、Rustソース・バイナリ互換、DOM engineの再実装、Yami固有themeや画面のgpui.mbtへの移設は対象外。Windowsの既存機能は維持し、Windows実IME、TUI、mobile/foldable、汎用editor、広範なMCP endpoint拡張は直近共有GUI受入の前提に追加しない。

本地図の登録でランタイム実装、PR #153–#155の修正・マージ、support tier昇格、1.0 gate変更は行わない。

## 提案する方針

### 1. 責務と設計原則

| 対象 | 責務 |
| --- | --- |
| gpui.mbt | MoonBitのstate、layout、input、text、scene、汎用focus/semantic/host API。既存core、TextField、TextSession、TextInputHost、FocusScopeSessionを再利用する。 |
| Yami-kumo | 共通View/runtime、componentとtheme、Web DOM/native adapter、共有GUI consumer。gpuiの状態遷移やOS IMEを二重実装しない。Webへgpui依存を強制しない。 |
| gpui-conformance | 固定したreference/candidateとfixtureによる意味・layout等の比較、差異分類、証拠保持。 |
| vlmkit | 指定した実画面の操作・観測。確定文字列や状態遷移のoracleを画像だけで代替しない。 |
| MZed / dsh.mbt | 後段の実アプリ検証と不足の発見。直近共有GUI受入の必須consumerにしない。 |
| turtles.mbt / hotpath.mbt | 開発用のmutation / 性能検証。通常consumerのruntime依存に混入させない。 |

[architecture](https://github.com/gpui-mbt/gpui.mbt/blob/3db0c94a43cda694d615205ecb9d1abf778638e8/docs/architecture.md)のruntime依存境界を継承する。公開APIは実consumerに必要な不足から追加し、既存APIで足りる場合はgpui.mbtの実装変更を不要と判断する。Dialog画面構築はYami側、gpui側は汎用focus・入力抑止・semantic・host境界を担当する。gpui.rsは固定した読取専用の比較対象として扱う。

### 2. 現在地と証拠の限界

| 領域 | 確認済み | 次に必要な区別・検証 |
| --- | --- | --- |
| 基盤 | mainにTextField、TextSession、TextInputHost、FocusScopeSession、CommandPalette、UniformListが存在する。[公開host API](https://github.com/gpui-mbt/gpui.mbt/blob/3db0c94a43cda694d615205ecb9d1abf778638e8/text_host/pkg.generated.mbti)、[focus API](https://github.com/gpui-mbt/gpui.mbt/blob/3db0c94a43cda694d615205ecb9d1abf778638e8/element/pkg.generated.mbti)。 | API存在と実consumer受入を分離。bounded single-line等の制約を保持。 |
| OS transport | macOS hostと[Ubuntu route](https://github.com/gpui-mbt/gpui.mbt/blob/3db0c94a43cda694d615205ecb9d1abf778638e8/ubuntu/text_host.mbt)、[Windows route](https://github.com/gpui-mbt/gpui.mbt/blob/3db0c94a43cda694d615205ecb9d1abf778638e8/windows/text_host.mbt)が存在する。 | 各routeの実IME、候補位置、focus/teardownを個別評価する。 |
| main CI | mainの[workflow一覧](https://api.github.com/repos/gpui-mbt/gpui.mbt/actions/runs?head_sha=3db0c94a43cda694d615205ecb9d1abf778638e8&per_page=30)は6件すべてcompleted / success。 | 既存の範囲の成功。共有GUI全体・物理入力・1.0の成功ではない。 |
| Linux PR群 | [#153](https://github.com/gpui-mbt/gpui.mbt/pull/153) → [#154](https://github.com/gpui-mbt/gpui.mbt/pull/154) → [#155](https://github.com/gpui-mbt/gpui.mbt/pull/155)はすべてDraft/open。#154はprepare-only。 | main統合済みの証拠と区別し、積み重ね順序と各候補SHAを維持する。 |
| Linux IME旧run | [40620178443](https://github.com/gpui-mbt/gpui.mbt/actions/runs/40620178443)は成功。PR本文の監査記録はXTest→Weston→IBus/Mozc→GPUIのpreedit/commit/cancel等を限定PASSとしている。 | harnessは`db5318d0e2883cbed0b1ce961c9bcd6f3ddb554b`、app sourceは`825d99d499bf02bdf1d232827261043b38a6cdeb`。候補一覧・物理入力・独立再現・PR HEAD製appは未受入。 |
| Linux IME現HEAD | `0b5135b08a3562ca3e166199090b0f37eb9ca192`の7 workflow中6 success、[IME実行40831715054](https://github.com/gpui-mbt/gpui.mbt/actions/runs/40831715054)はcompleted / failure。 | recovery bindで`gpui_evidence.py`の期待ハッシュ不一致。`native_status: NOT_RUN`であり、candidate oracle判定まで未到達。 |
| Apple Silicon macOS | [現status](https://github.com/gpui-mbt/gpui.mbt/blob/3db0c94a43cda694d615205ecb9d1abf778638e8/docs/status.md)は2026-10-21のYami sampleでsynthetic HID経由のlive Kotoeri、preedit、`日本語`commit、document、candidate visibilityの限定PASSを記録。 | 今回は過去の生traceを再監査していない。physical keyboard、candidate anchoring、支援技術、Dialog操作の範囲を分ける。 |
| Accessibility | [portable API](https://github.com/gpui-mbt/gpui.mbt/blob/3db0c94a43cda694d615205ecb9d1abf778638e8/accessibility/pkg.generated.mbti)とmacOS sampleの限定AX観測が存在する。 | portable value/selectionとOS provider・AT受入の不足を分離する。sample観測を一般AX対応へ昇格しない。 |
| 1.0 | [release ledger](https://github.com/gpui-mbt/gpui.mbt/blob/3db0c94a43cda694d615205ecb9d1abf778638e8/docs/release-gates.json)はcandidate_revision=null、12 gateすべてpending。 | API・text・AX・性能・安定性・依存・来歴等の必要証拠を別途満たす。 |

最新失敗の[artifact 12878982618](https://github.com/gpui-mbt/gpui.mbt/actions/runs/40831715054/artifacts/12878982618)は4,733 bytes。ZIP SHA-256を実計算し、GitHub metadataの`15f9b9dda79c1e34639942e6395bc02688bff0a9b676f5af8913fee1783209e9`と一致した。`execution-status.json`と`bind.log`を確認済み。artifact uploadは成功している。

### 3. 開発順序

| 順序 | 作業と終了条件 | 主担当・追跡先 |
| --- | --- | --- |
| 1 | 現在のsource、API、consumer依存、実行証拠を照合し、古い説明を履歴として分離する。 | [実装・証拠の現在地を照合する](20261030-development-evidence-baseline.md) |
| 2 | Linux受入のbindを復旧し、候補一覧の表示行・選択行とIBus lookup state、選択/取消後の消失を結ぶoracleで再実行する。 | 既存[Wayland/Linux IME](0028-wayland-ime-composition-handoff.md)、PR #153→#154→#155 |
| 3 | 公開APIだけで共有consumerを接続するための不足を確定し、Web＋Linuxで日本語編集→Dialog→復帰を受け入れる。 | [公開consumerの不足を確定する](20261030-public-consumer-gap.md)、[既存coordination](20261019-m3-textfield-dialog-coordination.md)、Yami側パケット |
| 4 | 同じ意味契約をApple Silicon macOSで独立に検証し、既存Kotoeri証拠の未検証範囲を埋める。 | [macOS composition](0026-macos-text-composition-host.md)、Yami native consumer |
| 5 | 共有GUI受入後に対象API/profileを固定し、継続利用・性能・AX・依存監査等の1.0証拠を積み上げる。 | [production readiness](0005-production-readiness-and-release-gates.md)、[検証戦略](0003-testing-pbt-mutation-and-visual-validation.md) |

順序は依存の目安。1の調査と、既存0028で根拠が揃った修正は並行可能。macOSの独立した再現・証拠取得もLinux完了を待つ必要はない。共有APIを変える場合は契約PRを先行させ、一人のintegratorが共有enum/manifestをまとめる。

PR #155のbind修復では、変更された入力とreviewed recipeのハッシュ連鎖を照合して必要な再レビュー・pin更新を行う。ハッシュ検証を緩和したり、内容確認なしで期待値だけを更新して通さない。bind修復後もcandidate-table gateは独立して残る。

### 4. 受入と変更の運用

1. 機能ごとに実装所在（main / PR-only / absent）、profileの能力（available / unsupported / unknown）、実行結果（PASS / FAIL / NOT_RUN）を別列に置く。unsupportedな経路でも検証がNOT_RUNの場合があり、unsupportedを正しく返す負のテストはPASSになり得る。
2. `framework_sha / consumer_sha / harness_sha / app_source_sha / app_binary_sha256 / dependency_lock / profile / OS_arch / toolchain / command / result / run_url / artifact_digest`を記録する。別revisionで成立した証拠は対応関係を明示し、新HEADの証拠へ流用しない。
3. headless、synthetic callback、OSイベント注入、live IME、physical keyboard、候補一覧、candidate geometry、AX/ATを別profileで判定する。
4. TextField→Dialogフローではpreedit/commit/cancel、二重挿入、undo/redo、Enter/Escape、Tab/Shift-Tab、背景への入力抑止、復帰先消失、stale event、close/reopenを確認する。
5. 不具合は最小fixtureに縮約し、engineはgpui、共有UXはYami、比較はconformance、観測はvlmkitへ戻す。
6. 既存`ecosystem-merge-v1`を継承する。最新HEADの必要CI成功と同一HEADへの`gpt-6.1-sol / xhigh`独立レビューを要求し、未実行を承認に置き換えない。文書検証とnative受入は別に報告する。

## 受け入れ条件

- [ ] 子調査の結論・根拠を記録し、既存Issue・文書の矛盾箇所と更新先が対応付いている。
- [ ] 公開API、選定consumer、dependency revision、各OS/profileの実行状態を確認できる。
- [ ] 次の着手先が既存Issueまたは独立した通常実装Issueに紐付き、未確定の実装を推測で固定していない。
- [ ] Linux先行、Apple Silicon別受入、Windowsの確認済み範囲維持、各repoの責務が矛盾しない。
- [ ] この地図の調査完了・共有GUI受入・1.0 gateの完了をそれぞれ別に判定できる。

## テスト計画

1. `local_issues.py discover / reserve-path / validate`で保存先、重複、必須構造、状態を確認する。
2. 相対リンク、Parent map、Depends on、Tickets、循環依存を確認する。
3. main/PR/実行appのSHA、Actionsの状態、artifact digestを一次情報と照合する。
4. 本地図の登録ではMoonBitテスト、native GUI、実IMEの再実行は対象外。後続作業では実コマンドとPASS/FAIL/未実行を記録する。

## リスク

古い文書の削除は過去の結果を失わせるため、当時の記録を残して現在地への参照を追加する。新しいrunやmergeで基準が変わるため、着手時にSHAを再確認する。共有GUI受入の成功だけでproduction supportを宣言しない。OS差を共通APIで隠さず、未対応を明示する。

## 変更履歴

`CHANGES.md` impact: no

本Issue群は内部の開発計画と調査課題の登録。公開API・実行時動作・配布物に変更を加える後続Issueでは個別に再判定する。

## 注記

### Wayfinder

- Role: map
- Parent map: none
- Type: map
- Mode: AFK
- Depends on:
  - [実装・実行証拠・既存課題の現在地を照合する](20261030-development-evidence-baseline.md)
  - [公開APIだけで共有GUIを受け入れるための不足を確定する](20261030-public-consumer-gap.md)

### Destination

既存方針と現在の実装・証拠を接続し、共有GUI受入までの残作業を担当・依存・受入条件付きで実装可能にする。

### Decisions so far

- [アーキテクチャ・依存方針](../done/0002-architecture-and-dependency-policy.md) — portable MoonBitとnative FFIの境界を維持する。
- [upstream来歴とporting方針](../done/0006-upstream-provenance-and-porting-policy.md) — 参照実装のrevisionと来歴を固定する。
- [ecosystem charter](20261015-ecosystem-charter-and-merge-gates.md) — 既存の責務・マージ基準を継承する。この参照は当該Issue全体の完了を意味しない。
- [共有GUI coordination](20261019-m3-textfield-dialog-coordination.md) — 一つの共有consumerの日本語編集・Dialog・focus復帰を直近の受入軸とする。

### Not yet specified

- consumerで再現した不足を確認した後に決める、追加APIの具体的な形・変更範囲・互換移行。
- 共有GUI受入後に決める1.0候補revision、production対象profile、継続利用の測定対象と実行計画。
- 必要性が実consumerから示された後に切り出す、一般editor・非同期処理・高度描画の追加範囲。

### Out of scope

直近共有GUI受入に、MZed全面置換、dsh必須化、TUI/mobile/Windows実IMEの完了、全GPUI機能網羅を追加すること。

### Tickets

- [ ] [実装・実行証拠・既存課題の現在地を照合する](20261030-development-evidence-baseline.md) — research / AFK / depends on: none
- [ ] [公開APIだけで共有GUIを受け入れるための不足を確定する](20261030-public-consumer-gap.md) — research / AFK / depends on: 実装・実行証拠・既存課題の現在地を照合する

### Frontier

最初の子チケットは「実装・実行証拠・既存課題の現在地を照合する」。既存0028とPR群の実装は別の実行レーンとして扱い、この調査地図へ重複登録しない。
