# Day 2をTerraformで復元した実施記録

実施日：2026-10-27 / 東京（ap-northeast-1） / Terraform 1.16.2・AWS Provider 6.70.0

**Day 2の再作成、復元データの検証、追加分の削除・EC2停止まで完了しました。Auroraは作成せずFreeプランを維持しています。**

[再実行手順](../terraform/DAY2.md) / [公開コード](../terraform/day2.tf) / [検証証跡](../evidence/terraform-day2/README.md)

## 実施方式

Day 1のTerraform管理済み環境を再利用しました。既存の空のBackupプランをimportし、内部ALB/NLB・転送先・リスナー・5xxアラーム・ログ配信許可・Backup対象割り当てをTerraformで再作成しました。

バックアップ／復元ジョブはAWS CLIで実行しています。復元された実データを持つEBS・EFSをTerraformのimportブロックで取り込み、追加接続・接続口・タグ・終了時の削除を管理しました。バックアップジョブ自体をTerraformリソースとして管理した実績ではありません。

Day 1の元EC2・DB用EBS・EFSを置き換えず、復元先は別リソースに限定しました。

## 適用結果

| 段階 | 実測 |
|---|---|
| 既存Backupプラン | Terraformへimport成功 |
| Day 2基盤の適用 | 10 added / 3 changed / 0 destroyed |
| 復元実体と接続設定 | 2 imported / 3 added / 2 changed / 0 destroyed |
| 復元後の再計画 | No changes / detailed-exitcode=0 |
| 終了計画の確認 | Day 2の追加15件だけを削除対象として照合 |
| 終了処理 | 0 added / 2 changed / 15 destroyed |
| 終了後の再計画 | No changes / detailed-exitcode=0 |

件数はTerraformの管理アドレス数です。実施前は44件、復元・検証時は60件、終了時は45件を管理しています。終了時の45件はDay 1の44件と、取り込んで保持した空のBackupプラン1件です。

## 確認した動作

- ALBとNLBのターゲットがhealthyであることをAWS APIで確認。
- 両LB経由でJSPがPostgreSQLの実データを取得し、LOAD_BALANCERS=PASS。
- 復元したEBS上のDBを別ポート55432で一時起動し、SQLを実行。EBS_RESTORE_SQL=PASS。
- 復元したEFSを読み取り専用でマウントし、元のday1.txtとcmpで照合。EFS_RESTORE_CONTENT_MATCH=PASS。
- Tomcat停止中、10秒間隔の10回の要求がすべてHTTP 503。
- Tomcat起動後にDB由来の応答を再確認し、FAULT_RECOVERY=PASS。
- 最後にhttpd・tomcat・postgresqlがactive、SSM実行はSuccess・レスポンスコード0、DAY2_VERIFICATION=PASS。

検証はTerraform管理のSSM DocumentをAWS CLIから実行しました。[実行JSON](../evidence/terraform-day2/verification.json)にマスキング済みの結果を収録しています。復旧直後のcurlに503の再試行が1件記録されていますが、最終応答・終了コード・PASSを確認しています。

## 監視とログ

2026-10-27 10:30 JSTの1分間に5xxが6件、10:31 JSTに5件を記録しました。アラームは同日10:33:45 JSTにOKからALARMへ遷移しました。HTTP復旧を確認した後に終了処理へ進み、今回の自然なOK復帰の履歴は待たずにアラームを削除しています。前日のコンソール演習の履歴とは区別しています。

今回のALBに対応する新しいアクセスログ.log.gzをS3で2件確認しました。同名アラームの古い履歴と前日のS3ログが残るため、実行開始時刻と今回のLB識別子で抽出し、タイムゾーンを保持して照合しました。

## 復元時に修正した点

暗号化EFSの最初の復元は、KMSキー指定が不足して失敗しました。alias/aws/elasticfilesystemを明示して再実行し、完了を確認しています。補助スクリプトにも指定を反映しました。最初からすべて成功したという記録にはしていません。

EBS・EFSを空で新規作成する計画を適用しないよう、完了した復元ジョブの実IDをimportに渡し、削除・置き換えがないことを確認しました。復元DBは元DBと別のポートで実行し、検証後に停止・アンマウントしています。

## 終了状態

| 項目 | AWS側の最終照合 |
|---|---|
| EC2 | stopped |
| 元のDB用EBS | 保持 |
| 元のEFS | available |
| Day 1スナップショット | completed |
| Day 2 ALB/NLB・ターゲットグループ | 0件 |
| 復元用EBS・EFS | 0件 |
| 今回の復旧ポイント | 0件 |
| Day 2アラーム・一時ログ配信許可 | 0件 |
| Backup対象割り当て | 0件。空のプランは保持 |
| S3の検証ログ | 保持 |

ユーザー指定に従い、復元状態を放置せず、Day 2のフラグを無効化した計画で整理しました。ルート全体のterraform destroyは実行していません。今回の復旧ポイントはジョブ台帳のARNを使ってAWS Backupから削除しました。

[最終照合結果](../evidence/terraform-day2/final-inventory.json)と、終了後のNo changesを証跡に収録しています。

## 検証範囲と限界

構文・形式はTerraform fmt/validate、PowerShell構文、Bash構文で確認し、SSMで実行検証しました。state・plan・実行時変数・未加工ジョブ台帳は非公開です。

Aurora移行、SNSメール通知、複数EC2間のフェイルオーバー、負荷試験、空のAWSアカウントからの一括構築は未実施です。今回の費用は確定しておらず、Freeプランを料金ゼロとは扱いません。保持するDay 1保存領域とログの料金は残ります。

