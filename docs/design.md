# 設計判断

## ネットワークと配置

| 要素 | 配置・設定 | 理由・制約 |
|---|---|---|
| VPC | 10.40.0.0/16 | 学習専用の範囲を分離 |
| Public A/B | 10.40.1.0/24、10.40.2.0/24 | Internet Gatewayへのデフォルトルート |
| Private A/B | 10.40.11.0/24、10.40.12.0/24 | 外向きデフォルトルートなし。将来のDB配置用 |
| EC2 | Public A、パブリックIPv4あり | NATなしでOS更新・SSM・AWS APIへ接続 |
| EFS | Private Aにマウントターゲット1個 | EC2と同一AZから共有ファイルを検証 |

2 AZにサブネットを用意していますが、EC2とEFSマウントターゲットは各1個です。アプリ全体のマルチAZ冗長化を達成した構成ではありません。

## 通信ルール

| 通信元 → 宛先 | ポート | 制御 |
|---|---|---|
| VPC内 → Apache | TCP 80 | EC2用SGでVPC CIDRに限定 |
| Apache → Tomcat | loopback 8080 | Tomcatの待受を127.0.0.1に限定 |
| Tomcat → PostgreSQL | loopback 5432 | JDBC接続、SCRAM認証 |
| EC2 → EFS | TCP 2049 | EFS用SGでEC2用SGを送信元指定 |
| EC2 → SSM/S3/CloudWatch等 | HTTPS 443 | Internet Gateway経由のアウトバウンド |

EC2のSGではSSH受信を許可しません。OS側でもfirewalldのSSH・Cockpitサービス許可を削除しました。SGのアウトバウンドは既定許可であり、厳密な送信先制限は今後の改善対象です。

## データとアクセス

- ルートEBS 15 GiBとDB用EBS 8 GiBはgp3・暗号化。
- DB用ボリュームはNVMeのSERIALとAWSボリュームIDを照合し、対象を確認してからXFSを作成。
- PostgreSQL初期化前に追加EBSをマウント。UUIDでfstabを設定。
- EFSは保存時暗号化。今回は標準NFSv4.1マウントで、通信のTLS暗号化は未導入。
- S3は公開アクセス禁止、SSE-S3、HTTPS以外のアクセスを明示的に拒否。
- EC2専用ロールにSSM/CloudWatchのAWS管理ポリシーを付与。S3のオブジェクト操作は対象バケットのリソースポリシーで許可。
- DB認証情報はEC2内の設定ファイルに保存し、rootとtomcatグループだけに読み取りを制限。
- IMDSv2必須。SELinux Enforcingを維持し、Apacheのプロキシ通信に必要なbooleanを有効化。

## 運用上の限界

WebとDBが同じEC2にあり、単一障害点です。HTTPのみで認証のない学習アプリのため、一般公開せずSSMのポート転送で確認しました。実施時は作業用ユーザーに必要な権限が不足し、利用者の指示でroot認証を使用しました。日常運用でrootを使用する設計ではなく、再実施には管理者が準備した作業用ロールの利用を前提とします。
