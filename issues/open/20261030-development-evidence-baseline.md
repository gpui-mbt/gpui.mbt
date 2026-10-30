# 実装・実行証拠・既存課題の現在地を照合する

Status: open
Model: GPT-6 Astra Pro
Created: 2026-10-30
Updated: 2026-10-30
Branch: research/20261030-development-evidence-baseline

## 概要

共有GUI受入に必要な実装、公開API、consumer依存、OS別実行証拠を照合し、どの既存課題が未完了なのかを確定する。過去の説明を現在の不足として誤って再実装しないための調査である。

## 背景

[開発方針の地図](20261030-development-policy-map.md)の最初の子チケット。2026-10-30調査時のmainは`3db0c94a43cda694d615205ecb9d1abf778638e8`、module宣言は0.10.6。

[20261019 coordination](https://github.com/gpui-mbt/gpui.mbt/blob/3db0c94a43cda694d615205ecb9d1abf778638e8/issues/open/20261019-m3-textfield-dialog-coordination.md)の現状説明にはtext_session未利用、macOS bridge不在、古いconsumer pinが残る。一方、[status](https://github.com/gpui-mbt/gpui.mbt/blob/3db0c94a43cda694d615205ecb9d1abf778638e8/docs/status.md)、[text-host contract](https://github.com/gpui-mbt/gpui.mbt/blob/3db0c94a43cda694d615205ecb9d1abf778638e8/docs/text-host-contract.md)、実sourceには後続の実装が存在する。[shared-ui host audit](https://github.com/gpui-mbt/gpui.mbt/blob/3db0c94a43cda694d615205ecb9d1abf778638e8/docs/shared-ui-host-contract.md)内にも古いOS一覧と新しい追記が併存している。

## 問題

1. 「当時の設計」「現在のコード」「現在の実行証拠」の区別が文書間で揃っていない。
2. PR #153–#155のbranch上の成果とmainの成果、harness SHAとapp source SHAが異なる。
3. Linuxの最新IME workflow失敗はbindでの停止であり、nativeテストのFAILと解釈すると作業対象を誤る。
4. macOSにはlive Kotoeriの限定PASS記録があるが、物理入力・候補位置・AT受入まで完了したわけではない。
5. consumerの依存版と公開APIの照合が古く、実装済み・接続待ち・検証待ちを分けられない。

## 目標

機能ごとにsource、API、consumer、実行profile、証拠、既存Issue、残る不足を追える現在地表を作る。文書の矛盾を具体的な更新先へ対応付け、次の公開consumer調査に渡す。

## 対象外

ランタイム修正、native受入の再実行、PRのマージ、依存版の更新、release gateの昇格は行わない。既存のIME実装Issueを複製しない。過去の結果を新HEADの結果として扱わない。

## 提案する方針

1. 着手時のmainと関連PRのHEAD、Yami-kumoの選定consumer、gpui-conformanceのfixture/reference/candidateを固定し、調査日時を記録する。変更が進んでいる場合は2026-10-30との差分を残す。
2. TextField、TextSession、TextInputHost、FocusScopeSession、semantic/AXを対象に、公開`pkg.generated.mbti`、実装、import/call siteを照合する。CommandPalette/UniformList等は再利用可能な既存機能として索引化し、受入範囲を必要以上に広げない。
3. 実装所在`main / PR-only / absent`、profileの能力`available / unsupported / unknown`、実行結果`PASS / FAIL / NOT_RUN`を別列にする。unsupportedの能力とNOT_RUNの実行状態は併存できる。既存文書に書かれたPASSは、artifact再監査済みのPASSと区別する。
4. 次の既知の不整合から調べる。

| 箇所 | 調べること |
| --- | --- |
| `issues/open/20261019-m3-textfield-dialog-coordination.md` | Actual state、古いconsumer pin、macOS bridge不在の説明、0.10.0固定の完了条件が現在の成果と整合するか。 |
| `issues/open/20261019-gp-01b-text-host-contract.md` | public seamの実装済み条件とopen status、Linux/Windows routeについて残る作業の単位。 |
| `docs/text-host-contract.md` / `docs/shared-ui-host-contract.md` | 冒頭・OS一覧と後続追記の整合。transport、能力広告、consumer接続、実IMEを分離する。 |
| `issues/open/0026-macos-text-composition-host.md` | 当初のNOT_RUNと後続のYami live Kotoeri限定PASSの関係。 |
| `issues/open/0028-wayland-ime-composition-handoff.md` / PR #153–#155 | 既存synthetic transport、OS入力注入、live IME、候補一覧、物理入力の範囲と実行revision。 |
| `docs/codebase-gap-analysis.md` | historical snapshotの位置付けを保ち、現在の不足一覧として再利用しない。 |
| `docs/status.md` / `docs/compatibility.md` | 一般的なmilestoneと共有GUI受入の区別、実装済みと比較未検証の区別。 |

5. Linux最新runは[40831715054](https://github.com/gpui-mbt/gpui.mbt/actions/runs/40831715054)と[artifact 12878982618](https://github.com/gpui-mbt/gpui.mbt/actions/runs/40831715054/artifacts/12878982618)を起点にする。`recovery binding failed / native_status: NOT_RUN`、`gpui_evidence.py`のハッシュ不一致は確認済み。修復は既存0028/PR #155へ返し、candidate-table gateと別のブロッカーとして記録する。
6. 旧runのharness `db5318d0e2883cbed0b1ce961c9bcd6f3ddb554b`とapp source `825d99d499bf02bdf1d232827261043b38a6cdeb`を分離する。最新PR HEAD `0b5135b08a3562ca3e166199090b0f37eb9ca192`から作ったappの受入と同一視しない。
7. macOSの2026-10-21記録はsynthetic HID→live Kotoeriのscopeを保持し、candidate visibility、candidate anchoring、物理入力、AX/ATを別行にする。
8. 結果はこのIssueの結論と既存current-status文書に反映する。過去のcheckpointは日付を付けて残す。新たな重複台帳は必要性を確認してから作る。

## 受け入れ条件

- [ ] 調査対象のframework、consumer、harness、実行app、fixture/referenceのrevisionが明示されている。
- [ ] 機能ごとに実装所在、profileの能力、実行結果、証拠の出所、既存Issue、次の不足が対応付いている。
- [ ] Linux最新bind失敗とcandidate-table未受入、旧runの限定PASSが別々に記録されている。
- [ ] macOSの限定live Kotoeri記録と未受入のphysical/candidate geometry/AX範囲が分かれている。
- [ ] GP-01B等の既存Issueについて、完了可能・残余あり・履歴維持の判断を根拠付きで記録している。未確認のままcloseしていない。
- [ ] 現在のstatus説明を証拠と整合させ、過去checkpointを日付付きで残して現在地への参照を示している。公開consumer調査が参照する基準revisionとAPI inventoryが確定している。

## テスト計画

1. GitHub APIでmain/PRのSHA、merge状態、run/jobのstatus/conclusionを照合する。
2. 重要なartifactはmetadata、取得ZIPのSHA-256、内部のsource manifest・execution status・resultを照合する。取得できなかった証拠は未監査と記載する。
3. 公開APIとconsumer import/call siteをsourceで突合する。ビルドを実施しない行はsource reviewと明示する。
4. Issue変更後は`local_issues.py validate`、相対リンク・依存関係確認を行う。
5. 本調査でnative/IMEテストを再実行しない場合、テスト結果は「未実行」とする。

## リスク

文書とartifactの時点が違うため、最新文書だけでも古いcheckpointだけでも状態を確定できない。cross-repoの変更で調査中にpinが変わり得る。古い成功を消すことと、古い成功で新しい候補を認証することの両方を避ける。

## 変更履歴

`CHANGES.md` impact: no

現在地の調査と内部文書の整合が対象。利用者向けsupport範囲や公開APIを変更する場合は別Issueで影響を再判定する。

## 注記

### Wayfinder

- Role: ticket
- Parent map: [実アプリ利用までの開発方針・順序・完了判定を統一する](20261030-development-policy-map.md)
- Type: research
- Mode: AFK
- Depends on: none

### 完了記録

未着手。地図登録時のsource/CI/artifact確認は上記の調査起点であり、consumer全体の照合や文書整合作業の完了を意味しない。


### 2026-10-30 UTC 再照合 checkpoint（未完了）

この節はsource/APIとGitHub metadataの確認であり、実GUIの再実行ではない。調査時点は2026-10-30 14:21 UTC。main、各PRの状態は着手前に再取得する。

| 対象 | revision / 状態 |
| --- | --- |
| gpui main | `3db0c94a43cda694d615205ecb9d1abf778638e8`、module宣言 `0.10.6` |
| 方針PR #156 | open、HEAD `ae699e06c0b869bafc83bf8adae317bb0a53efbc`。この3文書はmain未収録 |
| Linux #153 / #154 / #155 | draft/open、順に `64323e64f17a4f02094fea5257837ea057dfadea` / `825d99d499bf02bdf1d232827261043b38a6cdeb` / `0b5135b08a3562ca3e166199090b0f37eb9ca192`。baseはmain → #153 branch → #154 branch |
| Yami main / candidate consumer | `4405de81b231967388feddde08958d0786b03639`、`examples/shared_settings`のmodel、`examples/shared_settings_dom`、`native/examples/common/settings_runner.mbt` |
| consumer dependencies | Yami native `moon.mod` はgpui `0.10.6` / Yami `0.2.3`。source fixtureの `tests/native-ui/gpui-revision.txt` と `tests/shared-ui/gpui-revision.txt` は `cfc66b872bfd9613e2a81b499cac0602c84d653b`。`tests/published-settings/moon.mod` はgpui `0.10.5` / Yami native `0.2.13` の別組合せ。これらを同一実行と扱わない |
| 比較・観測tool | gpui-conformance main `711584ee421157f6f9fab86f76ed9b7277ea5bc5`、vlmkit main `6b5985c1aa5df2b9ddf4c51574b391599ae2bbd6`。これらはこのcheckpointの実行harnessではない |
| 過去のLinux IME | #155最新HEADの [run 40831715054](https://github.com/gpui-mbt/gpui.mbt/actions/runs/40831715054) はfailure。artifact metadataのSHA-256は `15f9b9dda79c1e34639942e6395bc02688bff0a9b676f5af8913fee1783209e9`。この再照合ではZIP取得先がHTTP 403を返し、内容と実digestを再監査できていない。bind失敗とnative `NOT_RUN`は方針PRの過去監査記録を引用しており、今回の独立再確認ではない |
| 既存旧run | 地図記載の旧IME成功はharness `db5318d0e2883cbed0b1ce961c9bcd6f3ddb554b`、app source `825d99d499bf02bdf1d232827261043b38a6cdeb`。#155 HEADからbuildしたappの証拠ではない。app binary hash / dependency lockの今回再監査は `NOT_RUN` |

| 機能 / profile | 実装所在 | capability | 今回の実行結果と根拠 / 次の不足 |
| --- | --- | --- | --- |
| TextField、TextSession、TextInputHost、FocusScopeSession | main。公開 `pkg.generated.mbti` にAPIあり | portable契約はsource上 available | 実行 `NOT_RUN`。API存在はconsumer integrationの証拠ではない |
| Ubuntu / Windows text host | mainの各`TextHostRoute`が公開`TextInputHost`を実装 | opt-in routeあり、実IME support全体は unknown | この調査で native GUI/IME `NOT_RUN`。0028等で各profileを検証する |
| macOS text host | mainの`platform/macos.Host`が `TextInputHost`を実装 | routeあり、physical/candidate geometryは unknown | 今回 `NOT_RUN`。既存statusは2026-10-21のsynthetic HID→live Kotoeri限定PASSを記録しているが、今回生traceを再監査していない |
| Yami Shared Settings | Yami mainに共通model、DOM bridge、native settings runner | source上の接続あり。対象revisionの日本語IMEとDialogの実運用能力は unknown | 今回 Web / Linux / macOS 操作 `NOT_RUN`。公開consumer調査とexact-source実行が必要 |
| Dialog focus | main `FocusScopeSession`、Yami native `Mounted`に利用箇所あり | portable controllerあり、native実deliveryは unknown | `docs/focus-scopes.md`はportable testsと実Dialog/native未検証を区別。今回再実行 `NOT_RUN` |
| 1.0 | `docs/release-gates.json` | release readiness未判定 | candidate null、全12 gate pending。共有GUIと別判定 |

公開API inventoryは `controls/text_field/pkg.generated.mbti`、`text_session/pkg.generated.mbti`、`text_host/pkg.generated.mbti`、`element/pkg.generated.mbti`。Yami `native/ui/moon.pkg` は`text_host`、`controls/text_field`、`element`をimportし、`Mounted::text_input`はhost observationを直接TextField操作へ写す。`text_session` importはない。現在の処理は引数epochの変化で内部sequenceをresetし、focused fieldへ配送するため、古いepoch/targetがblur・field変更・再生成を跨ぐ場合のadmissionを実call siteと最小fixtureで確認する必要がある。これはsourceレビューで見つけた検証課題であり、再現した不具合とはまだ断定しない。Yami DOMは既存browser input/composition pathを用いる。

mainの6 workflowは同じmain SHAでcompleted/success（[Actions一覧](https://github.com/gpui-mbt/gpui.mbt/actions?query=branch%3Amain)）。#155のrequired statusではLinux reviewed IMEがfailure、他にreal OS-input等がsuccess。これらを候補一覧や共有consumerの実IME成功に昇格しない。今回の環境はDebian 13 x86_64、GUI/IME・MoonBitテスト未実行であり、app binary SHA、lock、toolchain、run URL、artifact digestをこのcheckoutの実行証拠として主張できない。

既存issueの扱い: GP-01Bは公開seamとmacOS実装のchecked条件があるが、冒頭のLinux/Windows説明と古い問題記述は現mainと差があるため履歴として保持し、OS qualificationは0026/0028等に残す。coordinationは共有consumerの実行が未確認なのでopen維持。`docs/shared-ui-host-contract.md`のOS一覧はhost-local時点のsnapshotで、後続追記と併読する。`docs/codebase-gap-analysis.md`はhistorical snapshotである。artifact再取得、consumerのclean依存解決、詳細なprofile別fixtureの監査およびcurrent-status文書の完全な整合は未完了とし、この調査の受入条件を完了にしない。
