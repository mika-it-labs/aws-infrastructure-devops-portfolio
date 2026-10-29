# Day 4をTerraformで再現

SNS、Step FunctionsのECS同期実行と成功/失敗通知、EventBridge定期起動とEC2停止通知、内部ALB、CPU・ルートディスク・ALB 5xxアラーム、運用ダッシュボードを24リソースで管理します。Auroraは含めません。既存EC2の起動・障害演習・停止と実行テストは補助スクリプトで行います。

## 前提

- Day 1のVPC、Publicサブネット2個、VPC内HTTPを受信するSG、RHELのApache/Tomcat/PostgreSQL、SSM、CloudWatchエージェントが構築済み。
- 既存の `ecsTaskExecutionRole` を参照。タスクロール・DB認証情報は与えません。
- Terraform 1.9以上2未満、AWS provider 6.70.0、AWS CLI v2、PowerShell 7。作業用ロールでの実行を推奨します。
- メール購読の確認リンクは利用者が開きます。メールアドレスはsensitive変数ですが、stateには平文で残るため公開しません。
- このルート専用のstateを使います。Day 1/2/3のstateへ混在させません。

## 構築

`terraform.tfvars.example`を公開リポジトリ外の `C:/private/day4/environment.tfvars` へコピーし、自分の既存環境の値に置換します。以下のprofile名は例です。

```powershell
$profile = 'portfolio-work'
$private = 'C:/private/day4'
./Invoke-Terraform.ps1 -Profile $profile -StateDirectory $private init
./Invoke-Terraform.ps1 -Profile $profile -StateDirectory $private validate
./Invoke-Terraform.ps1 -Profile $profile -StateDirectory $private plan -var-file=C:/private/day4/environment.tfvars -out=C:/private/day4/create.tfplan
# 新規Day4リソースだけで、既存基盤の変更・削除がないことを確認する
./Invoke-Terraform.ps1 -Profile $profile -StateDirectory $private apply C:/private/day4/create.tfplan
```

`schedule_enabled=false`が既定です。FargateはPublic IPでイメージを取得し、受信ルールは0件、送信はHTTPSだけです。NAT Gatewayは作りません。

## 検証

SNSの購読確認を完了してから実行します。

```powershell
./Test-Day4.ps1 -Profile $profile -StateDirectory $private -Phase Batch
./Test-Schedule.ps1 -Profile $profile -StateDirectory $private -VarFile C:/private/day4/environment.tfvars
./Test-Day4.ps1 -Profile $profile -StateDirectory $private -Phase Fault
./Test-Day4.ps1 -Profile $profile -StateDirectory $private -Phase Logs
./Test-Day4.ps1 -Profile $profile -StateDirectory $private -Phase Stop
```

Batchは終了コード0と意図的な42を使い、ワークフロー結果とSNS発行ステップを検証します。Faultは既存EC2を起動してHTTP/DB接続を確認し、Tomcatを停止、10秒間隔36回のリクエスト後に再起動して復旧を検証します。EXIT時の起動処理を設けています。通信先は今回の内部ALBです。

`Test-Schedule.ps1`は定期起動の検証時だけ、plan/applyで `-var=schedule_enabled=true -var='schedule_expression=rate(1 minute)'` を指定します。変更対象が定期ルール1件だけであることを検査します。起動された実行の入力がEventBridgeであることと結果を確認したら、finally処理で既定変数を再びplan/applyし、毎日設定・無効状態に戻します。毎日24時間の反復を試験したと解釈しません。

ALARM/OK・停止イベント・バッチ通知は、別途メール実受信を照合してください。SNS発行成功と実受信を同一視しません。OK遷移は欠損データの設定にも依存し、HTTP/DBの正常性は実応答で確認します。

## 終了

検証ログ・実行履歴を非公開領域へ保存してから、削除計画を確認します。

```powershell
./Remove-Day4.ps1 -Profile $profile -StateDirectory $private -VarFile C:/private/day4/environment.tfvars
./Remove-Day4.ps1 -Profile $profile -StateDirectory $private -VarFile C:/private/day4/environment.tfvars -Apply
./Get-Day4Inventory.ps1 -Profile $profile -VarFile C:/private/day4/environment.tfvars -OutputFile C:/private/day4/final-inventory.json
```

削除対象を24アドレスの許可リストに照合します。プロバイダーが登録解除するタスク定義は、このstateから保存したリビジョンだけを追加削除します。既存のEC2は停止し、EBS・EFS・S3・スナップショット・共有ロールとAWS管理ルールは保持します。保存領域の課金は継続し得ます。

定義・plan・state・tfvars・実行履歴には識別情報やメールアドレスが含まれるため、公開するのは置換済みの要約だけです。実施状況は[実行結果](../../docs/day4-terraform-result.md)を参照してください。

同期実行の権限は[AWS公式ECS統合](https://docs.aws.amazon.com/step-functions/latest/dg/connect-ecs.html)に基づき、対象クラスターとタスク定義に限定しています。
