# Day 1のTerraform化・実施記録

実施日: 2026-10-26 / 東京リージョン。

## 実施方式

Day 1で稼働確認した既存環境をTerraformへimportし、差分を確認してからapplyしました。別の環境を重複作成したものでも、コードだけを作成して終えたものでもありません。

**検証実績は「既存環境のIaC管理への移行」と「Terraform管理のSSMによるLinux再構成」です。空のAWS環境からの新規一括構築試験は未実施です。**

## 実行結果

| 段階 | 結果 |
|---|---|
| Terraform / AWS Provider | Terraform 1.16.2 / hashicorp/aws 6.70.0 |
| fmt / validate | 整形・Providerを含む構成検証を実施 |
| 取り込み計画 | 43 to import、1 to add、28 to change、0 to destroy |
| 取り込み適用 | 43 imported、1 added、28 changed、0 destroyed |
| EC2起動 | Terraformでstopped → running、変更1件 |
| Linux設定適用 | SSM AssociationをTerraformで作成、実行Success |
| 適用後検証 | HTTP・DB・EBS/EFS・SELinux・サービス・監視Agentが正常 |
| 終了処理 | 一時SSM Associationを解除し、TerraformでEC2停止 |
| 最終差分 | No changes、detailed-exitcode=0 |

43件はTerraformのリソースアドレス数です。同じEC2に対する本体・状態管理、IAMのポリシー関連付け等の管理単位を含みます。新規追加1件はSSM Documentです。28件の更新は主にManagedBy=Terraformタグの追加と、Provider側の管理属性の確定でした。サーバー・DB用ボリューム等の置き換えは行っていません。

## 検証内容

- RHEL 9.8、既存の更新済みカーネルで稼働。
- httpd・tomcat・postgresql・SSM Agent・CloudWatch Agentがactive/enabled。
- SELinux Enforcing、Asia/Tokyo、firewalldのHTTP許可を確認。
- JSPのHTTP応答とDBのSELECT結果に `Apache -> Tomcat -> PostgreSQL OK` を確認。
- 追加EBS上のDBデータとEFS上の検証ファイルを保持。
- Tomcat・PostgreSQLの待受はloopback。
- 構成スクリプトがS3への成果物コピーとCloudWatch Agent設定を再実行。

詳細は[Terraform証跡](../evidence/terraform/)に収録します。既存スナップショットはDay 1の正常停止時点のものを管理下に取り込んで保持しており、今回新しいスナップショットを作り直した実績ではありません。

## 計画から分かったこと

最初の計画では、停止中EC2のパブリックIPv4関連付け属性がfalseとして読まれ、置き換えが提案されました。prevent_destroyで適用が止まり、既存サーバーは変更されませんでした。差分の原因を確認し、その属性をignore_changesで扱って再計画し、削除・置き換え0件となってから適用しました。

このため、Terraformがその属性の将来のドリフトを自動修復するとは主張しません。新規作成時の設定と、既存環境の取り込み後に追跡する設定の境界は[Terraform手順](../terraform/README.md)に記載しています。

## 管理対象外・限界

予算通知など既存のアカウント共有設定は保持し、今回のTerraform管理対象から除外しました。rootでの認証利用は利用者の指示を継続したもので、作業用ロールの権限設計が完了したという実績ではありません。運用向けの共有stateバックエンド、復元試験、性能試験、空環境での再構築は未実施です。

state、plan、実IDを含むimportブロック・変数ファイルは非公開です。公開する実行記録はマスキングしています。

終了時は44のリソースアドレスを管理しています。一時Associationは解除済みで、EC2はstopped、既存スナップショットはcompletedでした。

