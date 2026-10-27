# Day 2をTerraformで再作成する

Day 1の既存VPC・EC2・EBS・EFS・S3を再利用します。Freeプランを維持し、Auroraは作成しません。新規の独立環境を複製する手順ではありません。

## 管理範囲

- day2.tf：内部ALB/NLB、転送先・リスナー、5xxアラーム、Backupプランと対象割り当て。
- storage.tf：Day 2有効時だけALBログ配信のS3許可を追加。
- day2-restore.tf：AWS Backupが復元したEBS・EFSをimportし、追加接続とEFS接続口を管理。
- day2-verification.tf：[検証スクリプト](../scripts/day2-verify.sh)をSSM Documentに登録。
- Invoke-Day2-DataRestore.ps1：Terraformリソースではないバックアップ・復元ジョブの実行と状態確認を補助。

**バックアップ／復元ジョブそのものはTerraformのリソースとして管理していません。** 復元された実データを持つリソースを取り込み、以降の接続・タグ・削除をTerraformで管理します。空のEFSを作って復元済みと扱う方式ではありません。

## 前提

Terraform 1.7以上、PowerShell 7、AWS CLI、Day 1の取り込み済みstateを使います。importブロックのfor_eachが必要なため、最低Terraformバージョンを1.7にしています。

既存のDefault Backupボールトと、AWSBackupDefaultServiceRoleが必要です。role・ボールト名は変数で変更できます。state・変数・ジョブ台帳は公開リポジトリ外に保存します。実ID、ARN、認証情報をコミットしません。

## 1. 停止中の元データをバックアップ

台帳用の非公開ディレクトリを事前に作成します。Day 1 EC2が正常停止した状態で、正確なEBS ARN・EFS ARNを指定します。StartBackupsはEC2が停止済みか確認します。

```powershell
./terraform/Invoke-Day2-DataRestore.ps1 -Action StartBackups -JournalPath C:/private/day2/jobs.json -InstanceId YOUR_INSTANCE_ID -DatabaseVolumeArn YOUR_DB_VOLUME_ARN -FileSystemArn YOUR_EFS_ARN -BackupRoleArn YOUR_EXISTING_BACKUP_ROLE_ARN
./terraform/Invoke-Day2-DataRestore.ps1 -Action Status -JournalPath C:/private/day2/jobs.json
```

両方のバックアップ完了を確認してから、別リソースへの復元を開始します。同じ台帳へのStartBackupsの重複実行は拒否します。

```powershell
./terraform/Invoke-Day2-DataRestore.ps1 -Action StartRestores -JournalPath C:/private/day2/jobs.json
./terraform/Invoke-Day2-DataRestore.ps1 -Action Status -JournalPath C:/private/day2/jobs.json
```

EFSはnewFileSystem=true、暗号化有効、KMSキーalias/aws/elasticfilesystemで復元します。FAILEDの場合はAWS BackupのStatusMessageと作成途中のリソースを確認し、成功扱いにせず修正します。

## 2. 既存Backupプランを取り込み、Day 2を有効化

day2.tfvars.exampleをリポジトリ外へコピーします。Day 1の変数ファイルを先に、Day 2の上書きを後に指定します。既存プランがある場合は先にimportします。

```powershell
./terraform/Invoke-Terraform.ps1 -Profile default import -var-file=C:/private/day1/environment.tfvars.json -var-file=C:/private/day2/enabled.tfvars 'aws_backup_plan.day2[0]' YOUR_EXISTING_PLAN_ID
./terraform/Invoke-Terraform.ps1 -Profile default plan -var-file=C:/private/day1/environment.tfvars.json -var-file=C:/private/day2/enabled.tfvars -out=C:/private/day2/create.tfplan
./terraform/Invoke-Terraform.ps1 -Profile default apply C:/private/day2/create.tfplan
```

削除・置き換え0件を確認して適用します。ALB/NLBは内部構成で、既存のVPC内HTTP許可を使います。Tomcat:8080とPostgreSQL:5432はループバックのままです。

## 3. 復元されたEBS・EFSを取り込む

ジョブ台帳から完了したCreatedResourceArnを読み、復元EBS ID・復元EFS ID・元になった復旧ポイントのスナップショットIDを、非公開の追加変数へ設定します。

```hcl
day2_restore_enabled       = true
day2_restored_ebs_id       = "vol-REPLACE_WITH_RESTORED_VOLUME_ID"
day2_restored_efs_id       = "fs-REPLACE_WITH_RESTORED_FILESYSTEM_ID"
day2_restored_snapshot_id  = "snap-REPLACE_WITH_RECOVERY_POINT_SNAPSHOT_ID"
```

day2-restore.tfのimportブロックが実体を取り込みます。EBS・EFSが「新規作成」や「置き換え」になる計画は適用しません。期待する差分は、復元実体2件のimportとタグ更新、追加EBS接続・EFS接続口・SSM Documentの作成です。

## 4. 動作確認

ALB/NLBのターゲットがhealthy、SSMがOnlineになってから、day2_verification_document出力のDocumentを実行します。

```powershell
aws ssm send-command --document-name YOUR_DAY2_VERIFICATION_DOCUMENT --instance-ids YOUR_INSTANCE_ID --parameters FaultDrill=false
```

検証は、LB経由のJSP、復元DBを55432で一時起動してSQL取得、復元EFSと元ファイルのcmpを行います。FaultDrill=trueでは学習用Tomcatを一時停止し、503発生後に再起動して応答を確認します。実行完了・レスポンスコード0とPASS出力を確認してください。

## 5. 終了と課金抑制

day2-cleanup.tfvars.exampleでDay 2の追加分を無効化し、EC2を停止します。元データを含むルート全体へのterraform destroyは使いません。

```powershell
./terraform/Invoke-Terraform.ps1 -Profile default plan -var-file=C:/private/day1/environment.tfvars.json -var-file=C:/private/day2/cleanup.tfvars -out=C:/private/day2/cleanup.tfplan
./terraform/Invoke-Terraform.ps1 -Profile default apply C:/private/day2/cleanup.tfplan
```

削除対象がDay 2のLB・転送先・アラーム・復元コピー・接続口・検証Document・Backup割り当てだけであることを確認します。空のBackupプランはmanage_day2_backup=trueで保持します。以降のDay 1操作でもこの設定を維持してください。

今回作成した復旧ポイント2件は、復元コピーを整理した後、ジョブ台帳のARNを使ってAWS Backupで削除します。既存のDay 1スナップショットと取り違えないでください。保存したS3アクセスログは保持します。

最後に同じ終了用変数でplanのNo changesを確認します。FreeプランでもLBや保存領域はクレジットを消費し得るため、復元状態を放置しません。

[今回の実施結果](../docs/day2-terraform-result.md) / [Day 1のTerraform手順](README.md)

## 公式資料

- [Terraform import](https://developer.hashicorp.com/terraform/language/import)
- [AWS BackupでEBSを復元](https://docs.aws.amazon.com/aws-backup/latest/devguide/restoring-ebs.html)
- [AWS BackupでEFSを復元](https://docs.aws.amazon.com/aws-backup/latest/devguide/restoring-efs.html)


