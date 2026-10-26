# 構築手順

## 前提とコードの位置付け

Windows・PowerShell 7、AWS CLI v2、Session Manager Pluginを使用します。東京リージョンに学習専用の環境を作成する権限を持つAWSプロファイルを準備してください。実行すると課金リソースを作成します。

公開スクリプトは実際に使用したコードから、ローカルの保存場所・実行識別子・プロファイル指定を公開用に整理したものです。**公開版一式を使った新規環境への再構築は未検証**です。AWS上の動作実績は公開前の実行版に対するものです。完全な宣言型IaC、トランザクション、並列実行、全失敗パターンからの自動復旧には対応していません。

同じ名前やCIDRの既存リソースを確認し、作業前に無料利用枠の残クレジット・期限と予算通知を確認します。実状態は `.local/` に保存し、Gitには登録しません。

## 1. ネットワークとEC2ロール

リポジトリルートで実行します。`YOUR_PROFILE`は自身の作業用プロファイル名に置き換えます。

```powershell
./scripts/Deploy-Day1.ps1 -Phase Network -Profile YOUR_PROFILE
./scripts/Deploy-Day1.ps1 -Phase Server -Profile YOUR_PROFILE
```

Public/Private各2サブネット、ルート、SG、専用EC2ロールを作ります。ロールの反映を確認してから次へ進みます。

## 2. ストレージとEC2

```powershell
./scripts/Provision-Day1.ps1 -Profile YOUR_PROFILE
```

S3×2、EFS、マウントターゲット、t3.small、追加EBSを作ります。AMIはRHEL公式所有者の9.6系列を検索します。パッケージやAMIの提供状況は実行時点で確認してください。

EC2がrunningとなり、SSMのPingStatusがOnline、EFSマウントターゲットがavailableになるまで確認します。自動で待機を完結するスクリプトではありません。

## 3. Linux・ミドルウェア

```powershell
./scripts/Configure-Day1.ps1 -Profile YOUR_PROFILE
./scripts/Check-Day1.ps1 -Profile YOUR_PROFILE
```

OS更新、Apache/Tomcat/PostgreSQL、EBS/EFS、JSP/JDBC、S3コピー、CloudWatch AgentをSSM経由で設定します。コマンドがSuccessであることと、末尾の `DAY1_BOOTSTRAP_SUCCESS` をサーバーログで確認します。長い標準出力はSSM側で省略される場合があります。

初期化途中で失敗した場合はログと状態を確認し、失敗箇所を修復してください。DB初期化を含むため、無条件な再実行は避けます。対象ボリュームの識別・既存データの有無を確認します。

## 4. 動作と監視

```powershell
./scripts/Verify-Day1.ps1 -Profile YOUR_PROFILE
./scripts/Set-Monitoring.ps1 -Profile YOUR_PROFILE
```

Verifyは非同期コマンドを発行します。完了後にCollectを使います。AgentのメトリクスがCloudWatchに現れてからSet-Monitoringを再実行し、DB・ルート用のディスクアラームを作成します。

```powershell
./scripts/Collect-Day1.ps1 -Profile YOUR_PROFILE
```

SSMポート転送は、`.local/resources.json`から今回のInstance IDを確認して開始します。

```powershell
aws ssm start-session --target YOUR_INSTANCE_ID --document-name AWS-StartPortForwardingSession --parameters portNumber=80,localPortNumber=18080 --profile YOUR_PROFILE --region ap-northeast-1
```

ブラウザーで `http://127.0.0.1:18080/portfolio/` を開き、DB由来のメッセージを確認します。

## 5. 再起動・終了

OS更新後にEC2を再起動し、VerifyとCollectでサービス・マウント・データが維持されることを確認します。最後に[運用・終了手順](operations.md)に従い、EC2停止とスナップショットを確認します。
