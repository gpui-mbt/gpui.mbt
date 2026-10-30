# 公開APIだけで共有GUIを受け入れるための不足を確定する

Status: open
Model: GPT-6 Astra Pro
Created: 2026-10-30
Updated: 2026-10-30
Branch: research/20261030-public-consumer-gap

## 概要

先行する現在地調査を使い、日本語TextField・検証・確認Dialog・focus復帰を一つのconsumerで受け入れるために、既存公開APIで足りる範囲と残る不足を確定する。実装案は最小の再現と責務を確認してから作る。

## 背景

[既存coordination](20261019-m3-textfield-dialog-coordination.md)はYami-kumoの共有model / view / updateと公開GPUI APIによる接続を目標にしている。[shared-ui host audit](https://github.com/gpui-mbt/gpui.mbt/blob/3db0c94a43cda694d615205ecb9d1abf778638e8/docs/shared-ui-host-contract.md)と[focus contract](https://github.com/gpui-mbt/gpui.mbt/blob/3db0c94a43cda694d615205ecb9d1abf778638e8/docs/focus-scopes.md)は再利用する境界を定義している。

mainには[TextInputHost](https://github.com/gpui-mbt/gpui.mbt/blob/3db0c94a43cda694d615205ecb9d1abf778638e8/text_host/pkg.generated.mbti)、[TextSession](https://github.com/gpui-mbt/gpui.mbt/blob/3db0c94a43cda694d615205ecb9d1abf778638e8/text_session/pkg.generated.mbti)、[FocusScopeSession](https://github.com/gpui-mbt/gpui.mbt/blob/3db0c94a43cda694d615205ecb9d1abf778638e8/element/pkg.generated.mbti)がある。API追加を前提にせず、選定したYami consumerの現在のコードと照合する。

## 問題

1. repository内fixtureが動いていても、外部consumerが公開APIだけで同じflowを実現できるとは限らない。
2. private API、相対pathや未記録のsource patch、古い依存版が不足を隠す可能性があり、現状の監査が必要である。
3. DOMとnativeでstate/focus/IME処理を別に作ると、成功の意味が一致しない。
4. TextField、Dialog、OS transport、AX providerの不足を一つの巨大PRにまとめると、どの層で受入が止まったか分からなくなる。

## 目標

既存consumerを優先して一つの共有GUI flowを選び、公開APIの呼出しと必要profileを固定する。不足を「既存APIで可能」「adapterの接続不足」「frameworkの契約/実装不足」「証拠・環境不足」に分け、担当repo・既存Issue・後続の受入条件へ接続する。

## 対象外

新しいGUI frameworkやDOM engine、第二のTextField/履歴/focus state machine、gpui内のYami専用Dialog、MZed/dshを必須とする実アプリ計画は作らない。調査内で全OSの受入完了や1.0公開を要求しない。新規ランタイム実装やconsumerの依存更新は不足確定後の通常実装Issueで扱う。

## 提案する方針

1. [現在地調査](20261030-development-evidence-baseline.md)で確定したrevision/API inventoryを使う。YamiのShared Settings等、既存のmodel / view / updateを使えるconsumerを選定し、選定理由と実行範囲を記録する。
2. Webは既存DOM adapter、nativeは既存gpui adapterを用いる。consumer→公開GPUI package→hostの依存方向を確認する。component API、テーマ、validationはYami側に置く。
3. consumerのmanifest/lock、公開`pkg.generated.mbti`、実際のimport/call site、配布対象を照合する。通常製品依存とテスト/性能/観測toolを分け、必要なOS libraryまで除去しない。
4. 公開済み版または明示した候補revisionをクリーンな外部consumerから解決する。repository内のprivate APIや暗黙のローカル差分が必要なら、その最小再現を記録する。調査のためのpinを未確認の公開済み版と表現しない。
5. 次の観測表を既存fixtureと結び付ける。最初の実受入はWeb＋Linux、Apple Silicon macOSは同じ契約の別行として追跡する。

| 観測点 | 必要な意味 |
| --- | --- |
| 日本語編集 | preeditは未確定として表示し、commitは一度だけdocumentへ入る。cancelで確定済みdocumentを壊さない。 |
| 履歴・入力順序 | undo/redo、Enter/Escape、世代・epoch・sequence、blur/close後の古いイベント拒否を維持する。 |
| Dialog | 開閉、Tab/Shift-Tab、背景へのpointer/key配送抑止、focus復帰、復帰先消失、再openを同じ意味で扱う。 |
| 候補UI | 入力・lookup state・表示行/選択行・選択後/取消後の消失・caretとの位置を必要なprofileごとに結ぶ。 |
| semantic/AX | portable semantic state、sample固有AX観測、OS provider、AT操作を分離する。未実装providerをPASSにしない。 |
| 配布・依存 | クリーンconsumerで公開APIを解決し、開発toolが通常runtimeへ混入しないことを確認する。 |

6. Linux実行がPR #155のbind失敗等で止まる場合は環境/証拠不足として記録し、framework API不足と推測しない。必要なnative実行は既存のOS受入レーンへ依頼する。
7. 不足が見つかった場合は最小fixture、現APIで不可の理由、互換影響、担当repo、既存Issueへの追記先を記録する。既存課題で扱える場合はそこへ戻す。独立して実装・レビューできる新しい不足だけを`create-issue`で通常の実装Issueにする。
8. 既存APIで足りる場合は「gpui.mbt変更不要」と結論し、Yamiの接続または検証作業へ絞る。1.0向けの高度機能追加をこの結論の条件にしない。

## 受け入れ条件

- [ ] 選定consumer、framework/consumer/dependency revision、公開API呼出し対応表、選定理由が記録されている。
- [ ] private API・ローカルpatch・配布依存の監査結果があり、未確認箇所を明示している。
- [ ] Web/Linux/Apple Silicon macOSの対象flowとprofileごとに能力（available / unsupported / unknown）と実行結果（PASS / FAIL / NOT_RUN）を分け、実行コマンドまたは未実行理由を記録している。unsupportedを返す負のテストのPASSと機能の対応を混同していない。
- [ ] 不足の原因をframework/adapter/consumer/検証環境へ根拠付きで分類し、既存Issueまたは新しい通常実装Issueへ対応付けている。
- [ ] 必要な追加APIは最小再現に基づき、既存state machine・host・layoutを再利用する方針と整合する。
- [ ] 地図のDecisions so far、Not yet specified、Tickets、次の着手先を調査結果に合わせて更新している。

## テスト計画

1. 選定consumerの既存build/checkコマンドをクリーン環境で実行し、manifest/lockと実際の解決依存を保存する。コマンドは現在地調査で確認したものを使い、未確認のCLIを先に固定しない。
2. 既存Button/TextField/focusのportable testとDOM側の意味テストを同じscenario IDで照合する。
3. native GUI/IMEは既存のOS別profileを使い、harnessと実行appのrevisionを別々に記録する。実行環境がないprofileはNOT_RUNのままにする。
4. 古いepoch/target、二重commit、Dialog背景配送、復帰先消失を既存fixtureで検出できるか確認する。不足するテストは担当実装Issueへ返す。
5. 調査完了時に`local_issues.py validate`とリンク・依存関係確認を行う。

## リスク

consumer内の成功だけでは配布物の依存解決を保証しない。公開APIで表現できることと、OSが実際にイベントを届けることも別である。OS差や未対応を共通UI側で隠すと、単一のPASSが範囲外へ広がる。調査前にAPI形状や全OS対応を固定しない。

## 変更履歴

`CHANGES.md` impact: no

公開consumerの不足を確定する調査。後続の公開API・依存版・挙動変更は各実装Issueで変更履歴への影響を判定する。

## 注記

### Wayfinder

- Role: ticket
- Parent map: [実アプリ利用までの開発方針・順序・完了判定を統一する](20261030-development-policy-map.md)
- Type: research
- Mode: AFK
- Depends on:
  - [実装・実行証拠・既存課題の現在地を照合する](20261030-development-evidence-baseline.md)

### 完了記録

未着手。先行調査がdoneになってから、確定したrevision/API inventoryを使って着手する。
