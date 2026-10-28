# Day 3：Terraformによる復元と終了処理

コンソールで検証したFreeプラン内の構成を専用ルートで再構築します。GitHub → CodePipeline → CodeBuild → ECR → ECS Fargate、およびREST API → VPC Link V2 → 内部ALB → Tomcatが対象です。実測結果は[実行記録](../../docs/day3-terraform-result.md)に記載します。

Aurora、CodeDeploy、DB接続は対象外です。アプリは `DB_STATUS=UNCONFIGURED` を表示します。Day 1のVPC・サブネット・S3、既存ECS実行ロール、認証済みCodeConnectionsは参照のみで、このstateでは削除しません。EC2は停止したまま検証できます。

## 前提

- Terraform 1.9以上2未満、AWS provider 6.70.0、PowerShell 7、AWS CLI v2、東京リージョン。
- Day 1基盤、既存 `ecsTaskExecutionRole`、対象リポジトリに限定したAVAILABLEなCodeConnections接続。
- この構成を管理できるAWS作業用プロファイル。実行主体と改善点は実行記録を参照してください。

新設するIAMロールはビルド用・パイプライン用の2つです。Docker用の特権モードを使います。S3は成果物プレフィックス、ECRは専用リポジトリに限定し、PassRoleにECS向け条件を付けています。一部の認証・タスク定義操作はAWSの仕様でリソース指定が `*` です。

## 二段階で構築

このディレクトリをカレントにしたPowerShellの例です。`$private` は公開リポジトリ外の絶対パスに置き、作業者だけがアクセスできるようにしてください。`terraform.tfvars.example` のJSONを実値に置き換えて `environment.tfvars.json` として保存します。最初は `deploy_enabled=false`、`pipeline_enabled=false` にします。

```powershell
$private = 'C:/private/aws-portfolio-day3'
$profile = 'portfolio'
./Invoke-Terraform.ps1 -Profile $profile -StateDirectory $private init
./Invoke-Terraform.ps1 -Profile $profile -StateDirectory $private validate
./Invoke-Terraform.ps1 -Profile $profile -StateDirectory $private plan `
  "-var-file=$private/environment.tfvars.json" "-out=$private/bootstrap.tfplan"
./Invoke-Terraform.ps1 -Profile $profile -StateDirectory $private apply "$private/bootstrap.tfplan"
./Start-BootstrapBuild.ps1 -Profile $profile -StateDirectory $private
```

最初の8リソースでビルド基盤を用意します。成功した実際のビルド番号でイメージURIを生成し、展開用フラグとともに非公開の `deployment.tfvars.json` に保存します。

```powershell
./Invoke-Terraform.ps1 -Profile $profile -StateDirectory $private plan `
  "-var-file=$private/environment.tfvars.json" `
  "-var-file=$private/deployment.tfvars.json" "-out=$private/deployment.tfplan"
./Invoke-Terraform.ps1 -Profile $profile -StateDirectory $private apply "$private/deployment.tfplan"
./Test-Day3.ps1 -Profile $profile -StateDirectory $private -ExpectedRelease 'day3-terraform-v1'
```

後半18リソースを追加して合計26リソースになります。初回パイプラインに加え、mainの `day3/**` を変更し、そのコミットIDを指定して検証するとコミットによる自動実行も確認できます。

```powershell
./Test-Day3.ps1 -Profile $profile -StateDirectory $private `
  -CommitId '<mainに反映したコミットID>' -ExpectedRelease '<応答内のリリース文字列>'
./Invoke-Terraform.ps1 -Profile $profile -StateDirectory $private plan -detailed-exitcode `
  "-var-file=$private/environment.tfvars.json" "-var-file=$private/deployment.tfvars.json"
```

検証項目はパイプライン成功、指定コミットの自動実行、ECS稼働1・保留0、ALB正常、キーなしHTTP 403、キーありHTTP 200、リリース文字列、DB未接続表示です。古いターゲットの登録解除待機も含めて確認します。APIキーはメモリ内で取得し公開しません。APIキーは利用量制御用で、利用者の本人認証には別の認証方式が必要です。

CI/CDがタスク定義を更新するため、その参照だけをTerraformの差分検知から除外しています。他の設定は通常どおり比較します。ALBの登録解除待機は300秒です。

## 削除

```powershell
./Remove-Day3.ps1 -Profile $profile -StateDirectory $private `
  -VarFiles @("$private/environment.tfvars.json", "$private/deployment.tfvars.json") -Apply
```

削除計画を26個のDay 3リソース名の許可リストと照合します。直前のCloudWatchログを上限10,000イベントで非公開保存し、CodePipelineがTerraform外で作った学習用ファミリーのタスク定義も登録解除します。

S3成果物、既存接続、Day 1のEBS・EFS・スナップショットは保持します。保存領域の料金は残り得ます。AWS上で追加分の削除とEC2停止を確認してください。稼働時の通常planは差分0、削除後はstateの管理対象0・destroy計画の差分0を確認します。有効化変数を使った削除後の通常planでは再作成が提案されます。

## 公開しないもの

stateにはAPIキーが含まれます。`*.tfstate`、保存plan、plan JSON、実値のtfvars、認証情報、APIキー、生ログは公開しません。補助スクリプトはCLIの一時認証情報をメモリ内の環境変数に渡し、終了時に元へ戻します。

この実装はアプリのbuildspecと対応する固定プレフィックス `portfolio-day3` の学習用です。別名への一般化や本番利用にはビルド設定・権限・認証・監視を合わせた設計が必要です。


## 長時間処理で認証が期限切れになった場合

補助スクリプトは呼び出し時点の一時認証情報をTerraformへ渡します。処理中に期限が切れることがあります。今回の削除でも途中でExpiredTokenExceptionが発生し、CLIのログインキャッシュへの書き込み権限を回復して自動更新した後、残存リソースの削除計画を作り直して完了しました。パスワードやキーをコードへ埋め込む対応は行いません。エラー時は認証と現在のstate・AWSの実状態を確認し、残りの削除計画をレビューしてから再実行してください。
