# gpui.mbt ecosystem：責務・依存境界・マージ基準を揃える

Status: open — 設計課題。本文の追加は実装完了・互換性達成・承認取得を意味しない。
Priority: P1
Decision date: 2026-10-15

## 1. 何を実現するか

MoonBitで実アプリを作れるUI基盤を中心に、「互換性を調べる」「実画面で確かめる」「Web/Nativeの使い勝手を揃える」「実アプリで不足を見つける」「テストと性能を改善する」を別の責務として育てる。全部をgpui.mbtへ取り込む計画ではない。

2026-10-14〜15の議論で整理した、gpui.rsを参照実装にした比較、OS別の実機検証、動くZedを残す小領域置換を前提にする。upstream Zedはread-only。macOSの対象はApple Siliconのみとし、Linuxを並行して進める。Windowsは既存実装を壊さず、確認できた範囲を別に表示する。

## 2. 各リポジトリの役割

| リポジトリ | 答える問い | 担当しないこと |
| --- | --- | --- |
| [gpui.mbt](https://github.com/gpui-mbt/gpui.mbt) | MoonBitの状態・レイアウト・入力・描画・host APIを実アプリで使えるか | アプリ固有の会話、アカウント、エディタ仕様 |
| [gpui-conformance](https://github.com/gpui-mbt/gpui-conformance) | 同じ条件でgpui.rsとgpui.mbtがどう一致／相違するか | 画面写真だけからの全面互換宣言、OS全体の適合認証 |
| [vlmkit](https://github.com/f4ah6o/vlmkit) | 指定した実画面で表示・操作・観測結果を確認できるか | gpui.rs互換性の最終判定、アプリへの必須組込み |
| [Yami-kumo](https://github.com/f4ah6o/Yami-kumo) | Web/Nativeで操作の意味・状態・UXを揃えられるか | GPUI engineやOS backendの再実装 |
| [MZed](https://github.com/gpui-mbt/MZed) | 動くZedの一部をMoonBitへ置き換えられるか | 全面移植・完成エディタの約束、基盤の仕様決定権 |
| [dsh.mbt](https://github.com/f4ah6o/dsh.mbt) | 趣味の実アプリとして使いながら基盤の不足を発見できるか | ecosystem全体の必須PoC・リリースの単一ブロッカー |
| [turtles.mbt](https://github.com/gpui-mbt/turtles.mbt) | バグを埋めたときテストが検知するか | GUI操作や性能計測、アプリの実行時依存 |
| [hotpath.mbt](https://github.com/gpui-mbt/hotpath.mbt) | 定義した処理の時間・分布・回帰を測れるか | 通常アプリへの常時組込み、未計測の高速化主張 |

Yami-kumo.mbtという構想名の現在の作業先は`f4ah6o/Yami-kumo`。この課題では改名・リポジトリ移転を行わない。turtlesはcargo-mutantsのMoonBit移植という位置付けを維持する。

## 3. 現状と依存境界

[README](../../README.md)ではMoonBitのportable coreとnative/browser hostが既に分離され、hostは開発段階の対応範囲として説明されている。この課題は[既存のproduct charter](0001-product-charter-and-compatibility.md)、[テスト計画](0003-testing-pbt-mutation-and-visual-validation.md)、[release gates](0005-production-readiness-and-release-gates.md)を置き換えない。

1. 通常の製品依存は「アプリ → 必要なYami-kumo／gpui.mbt → MoonBit標準と明示したOS API」。Web版Yami-kumoまでgpui.mbt依存にする必要はない。
2. gpui-conformanceは固定したgpui.rsとgpui.mbtを開発時に起動する。Rust GPUIをgpui.mbtの配布runtimeへ取り込まない。
3. vlmkit、turtles、hotpathは開発・検証側から対象を見る。テスト専用importだけでmodule依存が消えたとは扱わず、通常module・workspace・配布物を監査する。
4. MZedだけは動くRust Zedを土台にした部分置換PoCであり、Rustを含むこと自体は境界違反ではない。
5. dshのhotpath分離は既にREADMEと`tools/perf`に記載されている。再実装ではなく再混入防止・独立計測を継続する。
6. アプリで見つけた不具合は最小fixtureへ縮約し、engineはgpui.mbt、共通UXはYami-kumo、観測はvlmkitへ戻す。dsh固有仕様をcoreへ持ち込まない。

## 4. 実装単位

1. **責務表と対応表**：各repoのREADME／既存roadmapに役割を反映し、機能ごとに担当repo・公開API・対象OS・証拠への参照を持たせる。
2. **依存境界検査**：通常consumerの解決依存・workspace・配布archiveを調べ、開発ツールなしでbuild/runできることを検証する。製品の必要なOSライブラリまで削除しない。
3. **証拠の受け渡し**：fixture ID、suite revision、reference/candidate SHA、OS/arch/toolchain、入力条件、コマンド、終了状態、artifactを対応付ける。別repoの新しいHEADへ古い結果を流用しない。
4. **共通マージ運用**：下記の条件をPR templateと既存CI運用へ反映する。自動強制が未実装の間は証拠付き手動チェックとし、branch protectionを設定済みとは表現しない。

## 5. 受入条件と検証

| 検証対象 | 合格条件 | 不合格／未検証の例 |
| --- | --- | --- |
| 公開APIとconsumer | 同じ候補revisionの公開APIと最小consumerが整合する | repo内private APIにしか接続できない |
| 開発依存の分離 | 開発ツールを導入せず通常build/runと配布物検査が通る | test-only importだが通常moduleがhotpathを解決する |
| headlessとnative | 結果を別profileで記録する | headless成功をIME・実入力成功へ昇格させる |
| 反例 | fixture差分、古いSHA、欠損artifactを検査が拒否する | CI終了コードだけを互換性の証拠にする |
| production-ready | 既存release ledgerの全必要条件を満たす | この設計PRのmergeだけでproduction-readyにする |

上表は今後追加する受入検証であり、このMarkdown追加時点で実行済みではない。既存テストは変更した範囲の実コマンド・対象・PASS/FAIL/未実行を記録する。

## 6. 共通マージ基準（ecosystem-merge-v1）

**Merge可 = 最新PR HEADの必要CIがすべてGreen AND 同じHEADに対する`gpt-6.1-sol/xhigh`のApprove相当。** 既存のより厳しい保護・レビュー・release基準は維持する。

1. PRごとに適用する必須checkと理由を事前に示し、全checkの`completed / success`をrun/job URLと対象SHAで確認する。CI未設定、未起動、pending/running、cancelled、失敗、必要checkのskipはGreenではない。非該当は理由を明示し、失敗後に必須checkから外して通さない。
2. レビューは実際に`gpt-6.1-sol`、reasoning effort=`xhigh`で対象HEADを確認した独立レビューを必要とする。モデル名・effort・対象SHA・判定・指摘・検証範囲・証拠URLをGitHubへ残す。他モデルや著者の自己申告を黙って代用しない。
3. Approve相当は「承認可能」という明示判定と、未解決のmerge-blocking指摘がないこと。P0/P1は解消必須。非ブロッカーも処置か追跡先を明示する。正式なAPPROVED review、または実レビューに基づく証拠付きコメントを受け付けるが、GitHub側の必須承認をコメントで迂回しない。
4. HEADが更新されたら以前のCI／承認を最終承認に流用せず、新しいHEADで再検証・再レビューする。必要なら統合用merge commitのチェックも満たす。
5. コマンドのexit 0と製品の正しさは別。必要ケースの欠落、環境制約、未実行、unsupported/unverifiedは表示し、必要な受入条件が未検証ならmergeを保留する。文書のみの変更は文書向けの適切なCIを定義し、nativeテストを走らせたと偽らない。
6. 証拠記録は`head_sha / required_checks / ci_evidence / reviewer_model / reasoning_effort / reviewed_sha / verdict / blocking_findings / review_url`を持つ。指定レビュー環境を使えない場合は「未実行・承認待ち」。人間による例外変更は明示決定として記録し、通常合格に偽装しない。

## 7. 完了条件

1. [ ] 8リポジトリの役割・対象外・受入条件が相互に矛盾しない。
2. [ ] 通常consumerと開発toolの依存境界を回帰テストで保持する。
3. [ ] app由来の不具合を担当repoへ返す最小fixtureの実例を残す。
4. [ ] CI Greenと同一HEADの指定モデル承認を確認してからmergeする運用を実証する。
5. [ ] この課題の完了とgpui.mbtのproduction-ready判定を別に管理する。
