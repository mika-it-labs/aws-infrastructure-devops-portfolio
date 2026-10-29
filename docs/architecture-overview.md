# Day 1〜4 構成図と解説

各段階の実施内容を説明するための模式図です。コンソールの実画面や、全構成が同時に稼働していることを示す証跡ではありません。添付された4枚をそのまま収録しています。

## Day 1｜Webアプリの構成

![Day 1：RHEL EC2内のApache・Tomcat・PostgreSQLと保存・監視](../assets/architecture/day1-webapp.png)

同じEC2内のApache → Tomcat → PostgreSQLを連携し、JSPがDBの検証データを読み出します。DBは追加EBS、共有ファイルはEFS、成果物等は非公開S3へ保存し、CloudWatchへログ・指標を送ります。管理はSSMを使用します。

TomcatとPostgreSQLはloopback待受です。図のミドルウェアは同じEC2内にあり、複数サーバーへ分離した構成ではありません。EFSの複数クライアント同時共有は未検証です。

[検証結果](verification.md) ／ [Terraform結果](terraform-result.md)

## Day 2｜LBと復元の構成

![Day 2：内部ALB/NLBとEBS/EFSのバックアップ・別領域への復元](../assets/architecture/day2-backup-load-balancers.png)

内部ALBはHTTP 80、内部NLBはTCP 80で、同じEC2のApacheへ転送します。AWS Backupから別EBS・別EFSへ復元し、元データを維持して内容を確認しました。復元DBは一時ポート55432でSQLを照合し、EFSはファイルを比較しました。

図のApache・Tomcat・PostgreSQLは元の同一EC2内です。単一ターゲットのため別サーバーへの障害切替は未検証です。Aurora移行は保留、SNSメール通知はDay 4で検証しました。

[コンソール記録](day2-console.md) ／ [Terraform結果](day2-terraform-result.md)

## Day 3｜自動配備と利用経路

![Day 3：GitHubからECSへの自動配備とAPI Gateway経由の利用経路](../assets/architecture/day3-cicd-api.png)

上段はGitHub → CodePipeline → CodeBuild → ECR → ECSの配備経路、下段はクライアント → API Gateway → VPC Link V2 → 内部ALB → ECSの利用経路です。上下のECSは同じサービスを役割別に表現しています。

コミット起点の自動配備後、実APIのリリース表示まで確認しました。DBの点線は未設定を表す模式表現で、実際のDB接続や移行成功を示しません。DB_STATUS=UNCONFIGUREDであり、CodeDeployの実配備も保留です。Day 3の実経路にNLBは使用していません。

[コンソール記録](day3-console.md) ／ [Terraform結果](day3-terraform-result.md)

## Day 4｜バッチ・監視・通知の構成

![Day 4：定期バッチの成功失敗、ALB 5xx、EC2停止イベントからのSNS通知](../assets/architecture/day4-batch-monitoring-notifications.png)

定期起動からStep FunctionsでECSバッチの完了を待ち、成功・失敗をSNSへ通知します。別の経路ではTomcat停止によるALBターゲット5xxをCloudWatchが検知し、EC2停止はEventBridgeが検知してメールへ通知します。

図のバッチ後の分岐・SNS発行はStep Functionsが制御する処理を簡略化したもので、バッチコンテナが直接SNSへ発行する実装ではありません。成功・意図的な終了42の失敗・メール受信・HTTP/DB復旧を確認しました。CPU/ディスクの閾値超過と24時間の日次反復運用は未試験です。

[コンソール記録](day4-console.md) ／ [Terraform結果](day4-terraform-result.md)

## 設計と終了状態

[要件・設計・試験・運用の文書一式](design-documents/README.md)に設定値、設計判断、試験結果を整理しています。

各段階の追加検証環境は検証後に削除し、最後の終了記録では元EC2を停止、元EBS/EFS・スナップショット・S3等を保持しています。図は過去の検証構成を説明する資料であり、現在のAWS実在状態は別途確認が必要です。
