# TerraformによるDay 1環境のIaC管理

Day 1の既存環境をTerraformへ取り込み、サーバーとデータを置き換えずに管理します。VPC・IAM・ストレージ・EC2・監視に加え、Linux設定を実行するSSM Documentも定義しています。

## ファイル

| ファイル | 管理対象 |
|---|---|
| versions.tf | Terraform / AWS Provider制約、変数、共通タグ |
| network.tf | VPC・4サブネット・IGW・ルート・SG |
| iam.tf | EC2専用ロール・ポリシー関連付け・プロファイル |
| storage.tf | 非公開S3×2・暗号化EFS・追加EBS・接続・スナップショット |
| compute.tf | EC2・起動/停止・SSM Document・任意の構成適用 |
| monitoring.tf | ログ4種類・7日保持・アラーム5件 |
| outputs.tf | リソースと終了状態の確認用出力 |
| .terraform.lock.hcl | 実検証したProviderバージョンとチェックサム |
| Import-Existing.ps1 | ローカル台帳から43件のimportブロックを生成 |
| Invoke-Terraform.ps1 | AWS CLIの選択プロファイルから一時認証を受け渡すWindows用ヘルパー |

## 検証した範囲

今回の実施は**既存Day 1環境を取り込む方式**です。新規の空環境から全リソースを再作成した試験とは区別します。完了結果は[Terraform実施記録](../docs/terraform-result.md)に記載します。

## 準備

PowerShell 7、AWS CLI v2、Terraformを準備し、管理者が用意した作業用AWSプロファイルを認証します。必要な権限には既存リソースの読み取り・タグ更新、EC2状態変更、SSM DocumentとAssociationの操作等が含まれます。今回の実行では利用者が指定した管理者認証を継続使用しています。

`terraform.tfvars.example`を**リポジトリ外**へコピーし、自分のAMI、バケット名、既存環境と一致する名前・Run・AZを設定します。実行時変数、importブロック、state、planは公開しません。

```powershell
./terraform/Invoke-Terraform.ps1 -Profile YOUR_PROFILE init -backend-config=path=C:/private/aws-rhel/terraform.tfstate
./terraform/Invoke-Terraform.ps1 -Profile YOUR_PROFILE validate
```

local backendを使い、stateをリポジトリ外に保存します。stateには識別子や構成内容が入るため、バックアップとアクセス制限が必要です。複数人で運用する場合の共有バックエンドは未構築です。

## 既存環境の取り込み

1. Day 1の台帳と実リソースを照合します。
2. スナップショットを含む既存環境では `snapshot_enabled=true` にします。
3. importブロックを生成します。

```powershell
./terraform/Import-Existing.ps1 -ResourceFile C:/private/aws-rhel/resources.json
./terraform/Invoke-Terraform.ps1 -Profile YOUR_PROFILE plan -var-file=C:/private/aws-rhel/environment.tfvars.json -out=C:/private/aws-rhel/adopt.tfplan
```

計画の削除・置き換えが0件であることと、変更属性を確認してから保存済み計画を適用します。

```powershell
./terraform/Invoke-Terraform.ps1 -Profile YOUR_PROFILE apply C:/private/aws-rhel/adopt.tfplan
```

importブロックは実IDを含むため `.gitignore` 対象です。EC2・S3・EBS・EFS・スナップショットにはprevent_destroyを設定しています。保護で計画が止まったら、保護を外す前に差分の理由を調べます。

## 起動とLinux構成

まず `instance_state=running, configure_instance=false` でplan/applyし、SSMがOnlineになることを確認します。その後 `configure_instance=true` でplan/applyすると、Terraform管理のSSM DocumentをAssociationで実行します。

Linux設定は既存の `scripts/bootstrap.sh` をSSM Documentに埋め込みます。DBパスワードはサーバー内で生成・保存し、Terraform変数へ渡しません。既存の設定ファイルとDBを保持する分岐がありますが、全障害ケースからの自動復旧や無条件の再実行安全性は保証していません。失敗時は実行ログとデータの状態を先に確認します。

## 終了状態

構成適用と検証を終えたら `configure_instance=false, instance_state=stopped` でplan/applyします。これにより一時的なSSM Associationを解除し、EC2を停止します。SSM Documentは管理下に残します。

新規環境でスナップショットを作る場合は、正常停止を確認した後に `snapshot_enabled=true` としてapplyします。今回の移行ではDay 1で正常停止後に作成した既存スナップショットを取り込んで保持します。過去のスナップショットを定期更新する仕組みではありません。

最後に、同じ変数ファイルのplanで `No changes` を確認します。

## 管理境界と注意点

- 既存EC2のSSM導入用user-dataは保持します。変更しても自動でOS再構成を行いません。
- EBSの二重管理を避けるため、EC2のebs_block_device変更は無視し、別リソースでデータディスクを管理します。
- 停止中EC2の公開IP属性の読み取り差分による置き換えを避けるため、associate_public_ip_addressをignore_changes対象としています。公開IPはAWS側のENI設定と実際の起動後状態を別途確認します。
- 予算通知は既存のアカウント共有設定を保持し、このTerraform管理対象には含めません。
- VPCに自動生成されるデフォルトSG・メインルートテーブル・NACLや、SSMが導入したOSパッケージ自体を個別のTerraformリソースとしては管理しません。
- S3オブジェクトのコピーとDB・EFSの読み書きはSSM側が実施します。Terraformはバケット等の基盤を管理します。
- prevent_destroyがあるため、そのままのterraform destroyで全削除できる構成ではありません。最終削除では保存要否と依存関係を確認し、保護を解除する変更を別途レビューします。

## 公式資料

- [既存リソースのimport](https://developer.hashicorp.com/terraform/language/import/single-resource)
- [EC2とEBSの管理境界](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/instance)
- [起動・停止状態の管理](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ec2_instance_state)
- [lifecycle / ignore_changes](https://developer.hashicorp.com/terraform/language/meta-arguments/lifecycle)

## Day 2の再作成・復元検証

内部ALB/NLB、S3アクセスログ、5xxアラーム、AWS Backupを[Day 2のTerraform手順](DAY2.md)に追加しています。復元ジョブはCLIで実行し、復元したEBS・EFSはTerraformへimportして接続・タグ・削除を管理します。[実施結果](../docs/day2-terraform-result.md)を参照してください。Day 2を無効化した計画で、元のDay 1データを保持しながら追加分を整理できます。



## Day 3の独立した再構築

Day 3はDay 1/2のstateと分離した [terraform/day3](day3/README.md) に実装しています。26リソースを作成し、コミット起点の自動配備・API 403/200・稼働時の差分0を確認後、追加分を削除しました。[実施結果と最終状態](../docs/day3-terraform-result.md)を参照してください。

## Day 4：非同期連携・監視の再現

[Day 4専用ルートと手順](day4/README.md) / [再構築・実測・終了結果](../docs/day4-terraform-result.md)。2026-10-29に24リソースを再作成し、バッチ成功/失敗・定期起動・メール受信・障害復旧を検証しました。追加分を削除し、専用stateの管理対象0件、元EC2停止を確認しています。このルートと同じstateへ混在させません。
