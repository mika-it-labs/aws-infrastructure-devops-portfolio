# 詳細設計書

文書ID：DET-01／版：1.0／作成日：2026-10-29／状態：レビュー用・事後整理。

設定値は既存コード・検証記録を基に整理した。アカウント番号、リソースID、メール、秘密値は記載しない。設定変更時は本書と[試験仕様書兼結果書](test-specification-results.md)を同時に更新する。

## D01 共通条件・命名

| 項目 | 設計値・扱い |
|---|---|
| リージョン／共通タグ | ap-northeast-1／Project=portfolio |
| 段階別名称 | portfolio-day2-*、portfolio-day3-*、portfolio-day4-*。既存資源名はコード参照 |
| OS・Java | Day 1更新後RHEL 9.8／Java 17。OS・パッケージ全版を固定した構成ではない |
| Terraform検証版 | 1.16.2／AWS provider 6.70系。各ディレクトリの宣言・lockを優先 |
| 実行環境 | AWS認証済み作業環境。state・plan・実値tfvarsは公開リポジトリ外 |

検証日はDay 1・Day 2コンソールが10月26日、Day 2 IaC・Day 3コンソールが27日、Day 3 IaC・Day 4コンソールが28日、Day 4 IaCが29日。文書内の時刻はJST。

## D02 VPC・経路・通信

| 領域 | CIDR | 既定経路／用途 |
|---|---|---|
| VPC | 10.40.0.0/16 | DNS利用 |
| Public A／B | 10.40.1.0/24／10.40.2.0/24 | IGW。EC2・Fargate・内部LB |
| Private A／B | 10.40.11.0/24／10.40.12.0/24 | localのみ。EFS・VPC Link等 |

| 通信 | 許可・設定 |
|---|---|
| VPC内 → EC2 Apache | TCP 80、送信元10.40.0.0/16 |
| Apache → EC2 Tomcat → DB | loopback TCP 8080 → 5432 |
| EC2 → EFS | TCP 2049、EFS SGの送信元をWeb SGに限定 |
| VPC内 → Day 3 Fargate | TCP 8080、送信元10.40.0.0/16。ALB SGのみへの限定は未実施 |
| Day 4バッチ | 受信ルールなし。送信TCP 443を0.0.0.0/0へ許可 |
| 管理 | SSM。受信TCP 22なし |

Web用等の既存SGは送信全許可を含む。Day 4バッチSGの制限と混同しない。詳細は[network.tf](../../terraform/network.tf)と各段階のTerraformを参照。

## D03 OS・ミドルウェア

`httpd`、`tomcat`、`postgresql-server`、`postgresql-jdbc`等をdnfで導入する。初期化・設定の実装は[bootstrap.sh](../../scripts/bootstrap.sh)を参照。

| 項目 | 設定 |
|---|---|
| SELinux | Enforcing、httpd_can_network_connectを有効化 |
| firewalld | HTTP許可。SSH・Cockpitの既定サービスを除去 |
| メタデータ | IMDSv2必須、hop limit 1 |
| Apache | /etc/httpd/conf.d/portfolio.conf。ProxyRequests Off、ProxyPreserveHost On |
| 転送 | /portfolio/ → http://127.0.0.1:8080/portfolio/。ルートを/portfolio/へリダイレクト |
| Tomcat | server.xmlのConnectorを127.0.0.1に限定 |
| JSP | /var/lib/tomcat/webapps/portfolio/index.jsp。JDBC jarはWEB-INF/lib |
| 起動 | httpd・tomcat・postgresqlを有効化。再起動後にactiveを確認 |

## D04 DB・接続情報

DB名`portfolio`、アプリ用ロール`portfolio_app`。`public.learning_log`は`id integer PRIMARY KEY`、`message text NOT NULL`。id=1の検証行をJSPで参照する。アプリの通常処理は参照で、業務更新処理・トランザクション要件は定義しない。

DBはloopback:5432待受。接続情報は`/etc/portfolio/db.properties`に保存しroot:tomcat・0640、親ディレクトリ0750とする。パスワードは構築時に生成し、公開ソースやTerraform stateに直接記載しない。Secrets Managerは使用していない。

Day 3は環境変数によるDB接続の余地を持つが実値を投入していない。Auroraへの接続・データ移行完了を表す設計ではない。

## D05 EBS・EFS・S3

| 資源 | パラメータ・実装 |
|---|---|
| EC2 | t3.small、CPUクレジットstandard、Public A、公開IPv4 |
| OS EBS | 暗号化gp3・15 GiB |
| DB EBS | 暗号化gp3・8 GiB、XFS、/var/lib/pgsql |
| DBマウント | NVMeのSERIALで対象を確認。UUIDでfstab登録し、マウント後にDB初期化。postgres所有、0700、restorecon |
| EFS | 保存時暗号化、generalPurpose／bursting、Private Aにマウントターゲット1件 |
| EFSマウント | /mnt/shared、NFS 4.1。_netdev,nofail,nfsvers=4.1,hard,timeo=600,retrans=2,noresvport。通信TLSなし |
| S3 | 静的ファイル用／ログ・成果物用。Block Public Access全項目有効、SSE-S3、非TLS要求拒否 |

`mkfs`は新規の正しい対象にだけ実行する。復元済みEBSには実行しない。S3のファイル操作はEC2ロールを使用し、アクセスキーを配布しない。[storage.tf](../../terraform/storage.tf)を参照。

## D06 Backup・リストア

プラン`portfolio-day2-backup`、Default vault、対象DB EBS・EFS各1件。日次ルールは`cron(30 0 * * ? *)`、タイムゾーンAsia/Tokyo、開始許容480分・完了許容10080分・保持7日。オンデマンド取得・復元ジョブは補助手順で起動し、Terraformがジョブそのものを作るとは説明しない。

1. EC2を正常停止してEBSバックアップ、EFSも取得する。
2. 別の暗号化gp3・8 GiBを同一AZへ復元する。デバイス識別後、XFSの重複UUIDを考慮し`nouuid`で別パスへマウントする。
3. 一時PostgreSQLを127.0.0.1:55432で起動し検証行を照会する。元DBの5432と分離する。
4. EFSは別ファイルシステムへ復元し、マウントターゲットを用意する。読み取り専用でday1.txtを`cmp`比較する。IaC時の復元ではKMSキー指定を補い成功した。
5. 一時DB停止・アンマウント後、復元資源と今回の復旧ポイントのみを削除する。

IaCでは実際に復元したEBS・EFSをimportし、空の代替領域を復元成功と扱わない。[day2.tf](../../terraform/day2.tf)・[結果](../day2-terraform-result.md)を参照。

## D07 LB・ヘルスチェック

| 段階・LB | リスナー → ターゲット | ヘルスチェック・補足 |
|---|---|---|
| Day 2 ALB | HTTP80 → instance Apache80 | HTTP /portfolio/、30秒、timeout5秒、正常5／異常2 |
| Day 2 NLB | TCP80 → instance Apache80 | TCP、30秒、正常3／異常3。クロスゾーン有効、client IP preservation無効 |
| Day 3 ALB | HTTP80 → IP Fargate8080 | HTTP /portfolio/health.jsp、30秒、timeout5秒、正常5／異常2、登録解除猶予300秒 |
| Day 4 ALB | HTTP80 → instance Apache80 | HTTP /portfolio/、15秒、timeout5秒、正常2／異常2 |

すべて内部LB。NLBのクライアントIP保持無効は単一EC2から同じターゲットへ戻る試験のためで、一般的な必須設定ではない。単一ターゲットのため障害時に別サーバーへ切り替わる試験にはならない。

## D08 ビルド・コンテナ・サービス

[Day 3ソース](../../day3/)と[Terraform](../../terraform/day3/)を参照。Java17 Corretto／CodeBuild amazonlinux-x86_64-standard:6.0、Linux small、Docker特権モード、ビルド15分・キュー30分。Maven WAR作成後、コンテナ起動と本文照合を行う。

Dockerベースは`tomcat:9.0-jdk17-temurin-noble`、実行UID/GID10001、WAR名portfolio.war、ポート8080。ベースタグの将来更新を固定ダイジェストで保証する構成ではない。ECRは非公開・AES256・タグ不変。タグはbuild-N方式。

FargateはLinux/x86_64・0.25 vCPU／1 GiB・awsvpc、通常desired_count=1、公開IP付き。ローリング更新はminimumHealthyPercent=100、maximumPercent=200。ECS実行ロールは既存ecsTaskExecutionRole。CloudWatchのCodeBuild・ECSログは7日保持。

## D09 パイプライン・API

GitHub接続対象は`mika-it-labs/aws-infrastructure-devops-portfolio`。mainのDay 3対象変更をSource→Build→ECS Deployへ連携する。ビルド識別子とコミットをレスポンスで比較する。ECSタスク定義はパイプラインが更新し、Terraform側はその変更をignore_changesで扱う。

成果物の既存S3プレフィックスは`day3/artifacts/`と`portfolio-day3-pipel/`。後者はパイプライン名全体ではなく実際の先頭20文字であり、IAMのGetObject/GetObjectVersion/PutObject等を実パスに合わせる。過去の権限不足の切り分けは[コンソール記録](../day3-console.md)を参照。

REST APIはRegional、ステージlab、GET、HTTP_PROXYで内部ALBの/portfolio/に接続。VPC Link V2はPrivate A/B。タイムアウト29000ms、authorization NONE、APIキー必須・HEADER、利用量プラン1req/s・burst2・100req/day。上限は厳密な課金防止装置ではない。キーなし403、キーあり200を実URLで試験し、コンソール内部テストだけで判定しない。

## D10 Step Functions・EventBridge

[Day 4コード](../../terraform/day4/)を正本とする。Standard／JSONPath、ステートマシンTimeout1200秒、ECS待機タスク900秒。入力forceFailureは文字列のtrue／falseで、環境変数DEMO_FAILへ渡す。

バッチはAmazon Linux 2023公開イメージ、0.25 vCPU／0.5 GiB。BATCH_START出力→5秒待機→通常0、故障指定42で終了する。ECS起動結果は$.ecs、Catchのエラーは$.error。Catch ALLはSNSエラー通知後Failへ進む。正常戻り時もContainers[0].ExitCodeの存在と0を確認し、非0を失敗扱いにする。実際の42試験はStates.TaskFailedとしてCatch経由になった。

SNS件名はPortfolio Day4 SUCCESS／FAILURE。定期ルールはrate(1 day)・DISABLED、検証時のみrate(1 minute)へ変更して必ず復旧する。停止検知は元EC2のstoppedイベントだけを対象にする。イベント入力や通知本文へ秘密値を含めない。

## D11 IAM・通知権限

| 実行主体 | 許可範囲 |
|---|---|
| EC2 | SSM・監視送信・指定S3等。既存ロールを利用 |
| CodeBuild | 指定成果物とECRの読み書き。ECR認証トークン取得はリソース*が必要 |
| CodePipeline | 指定接続・成果物・ビルド・ECS更新、必要なタスク登録・PassRole |
| Step Functions専用 | 指定タスク定義を指定クラスターで起動、同クラスターのタスク参照停止、同期待機用の標準EventBridgeルール操作、指定SNS発行 |
| EventBridge専用 | 指定ステートマシンへのStartExecutionだけ |
| SNSリソースポリシー | 同一アカウントのportfolio-day4-*アラーム、指定EC2停止ルールからのPublish |

PassRoleは既存実行ロールとecs-tasks.amazonaws.com条件に限定する。Step Functions・EventBridgeの信頼は同一アカウント・対象Arnを条件にする。共有のStepFunctionsGetEventsForECSTaskRuleを学習終了時に削除しない。実行権限の完全な一覧は対応するTerraform定義を参照し、この表だけをIAM投入用JSONには使用しない。

## D12 ログ・監視・閾値

| 対象 | 統計／閾値／期間×回数 | 欠損値・通知 |
|---|---|---|
| Day 1 CPU | Average >80%、300秒×2 | missing、SNSなし |
| Day 1 memory | Average >85%、60秒×2 | missing、SNSなし |
| Day 1 root／DB disk | Average >80%、60秒×2 | missing、SNSなし |
| Day 1 StatusCheckFailed | Average >0、60秒×2 | missing、SNSなし |
| Day 2 ALB target5xx | Sum >0、60秒×1 | notBreaching、SNSなし |
| Day 4 CPU／root disk | CPU >80% 300秒×2／disk >80% 60秒×2、Average | missing、ALARM時SNS |
| Day 4 ALB target5xx | Sum >0、60秒×1 | notBreaching、ALARM・OK時SNS |

Agentの独自名前空間はPortfolio/Day1、収集間隔60秒。mem_used_percentとdisk_used_percentを送る。ディスクはInstanceId・path・fstypeで識別しdrop_deviceを使う。ルートと/var/lib/pgsqlを分ける。

ログは`/portfolio/day1/httpd-access`、`httpd-error`、`tomcat`、`bootstrap`、Day 4は`/portfolio/day4/batch`等。各7日保持。Day 2のALBアクセスログは既存S3のalb/以下へ出力し、新しいLB・日付と照合する。Day 4ダッシュボードはEC2・ALB・Step Functions・SNS・バッチログを表示する。AuroraやECSサービスのCPU監視が完成した図にはしない。

## D13 運用手順・復旧・終了

開始条件：東京リージョン、認証期限、対象名・タグ、元データ・元スナップショット、バックアップ、課金対象と保護対象を確認する。障害試験はSSMスクリプトでTomcat停止・HTTP繰返し・復旧を実行し、EXIT trapでも起動する。復旧後はHTTP200、SQL内容、3サービスactiveを確認する。

Day 4 IaCの停止試験は10秒間隔36回が503、再起動後HTTP200・DB正常。ALARMとOK通知はそれぞれ別に時刻を記録する。定期ルールは試験後無効に戻す。

終了時は追加環境の対象一覧を照合し、LB・タスク・定期起動・通知・追加ロール等を削除する。動的に登録されたタスク定義も整理する。元EC2は停止、EBS2件・EFS・元スナップショット・S3証跡を保持する。費用確認は請求反映待ちと残存保存領域を考慮し、金額未確認のものを0円と記載しない。

## D14 Terraform構成・差分管理

| 段階 | 構成・扱い |
|---|---|
| Day 1 | terraform/。既存基盤を取込み、保護属性を付与。初回43 resource addressの記録は当時のstateであり、全段階共通の固定数ではない |
| Day 2 | 同一基盤state、day2_enabled／manage_day2_backup／day2_backup_assignment_enabled／day2_restore_enabled。追加分だけ無効化。基盤全体destroy禁止 |
| Day 3 | terraform/day3/。26管理資源を再現・検証後destroy。CI/CD登録分のタスク定義は別途整理 |
| Day 4 | terraform/day4/。24管理資源を再現・検証後destroy。プロバイダー外のタスク定義最終削除も補助操作として記録 |

実行の順序は認証→対象確認→fmt/validate→plan確認→apply→実応答・通知検証→稼働時差分確認→終了処理→stateとAWS実在確認。Day 2のバックアップ・復元実行にはCLI補助がある。Day 1が空アカウントから完全自動で生成されたと解釈しない。

変更時には要件ID、コード差分、plan、対応試験ID、結果、保護対象の終了状態を残す。公開前に実値・メール・APIキー・state・認証情報を除去する。コードと結果の参照は[索引](README.md)にまとめる。
