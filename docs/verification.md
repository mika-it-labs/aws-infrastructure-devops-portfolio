# 検証結果

検証日: 2026-10-26。以下はDay 1の実行記録をもとにしています。AWSリソースの現在状態を継続監視するページではありません。

| 検証項目 | 実測結果 | 証跡 |
|---|---|---|
| OS更新・再起動 | RHEL 9.8、新カーネルで起動 | verification.txt / OS |
| OS設定 | Asia/Tokyo、SELinux Enforcing | verification.txt / security |
| サービス | httpd・tomcat・postgresql・SSM・CloudWatch Agentがactive/enabled | verification.txt / services |
| アプリとDB | HTTP応答とSELECT結果が一致 | verification.txt / HTTP・database |
| EBS | DB用8 GiB、XFS、/var/lib/pgsql | verification.txt / storage |
| EFS | /mnt/sharedがnfs4、共有ファイルの内容を確認 | verification.txt / storage |
| 待受範囲 | Tomcat 8080・DB 5432はloopback | verification.txt / listeners |
| ログ | 4グループ全てで少なくとも1イベント | log-groups.json |
| OSメトリクス | メモリ1系列、ディスク2系列 | metrics.json |
| アラーム | CPU・メモリ・ディスク2件・状態異常の5件 | alarms.json |
| 終了状態 | EC2 stopped、CPU credit standard | final-state.json |
| スナップショット | completed、100% | final-state.json |

証跡は[evidence/](../evidence/)に収録しています。原本からの置換内容は[証跡の扱い](../evidence/README.md)に記載しています。

## アラームの条件

| アラーム | しきい値 | 期間・評価 |
|---|---|---|
| CPU | >80% | 300秒×2期間、Average |
| メモリ | >85% | 60秒×2期間、Average |
| ルートディスク | >80% | 60秒×2期間、Average |
| DBディスク | >80% | 60秒×2期間、Average |
| StatusCheckFailed | >0 | 60秒×2期間、Average |

欠損データはmissingとして扱います。SNSの通知アクションはまだ接続していません。アラーム作成・指標の到着を確認した範囲であり、しきい値を意図的に超過させた通知試験は未実施です。

## 未実施・証明していない項目

- EFSを2台のEC2から同時にマウントする試験
- スナップショットからのリストア・DB復旧試験
- 高負荷・性能・可用性・フェイルオーバー試験
- HTTPS、利用者認証、Webアプリの脆弱性診断
- Aurora、ALB/NLB、ECS、CI/CD、SNS・Step Functions・EventBridge
- 公開向けに整理したスクリプト一式での新規再構築

ブラウザー表示はSSMポート転送で確認しましたが、保存済みの画面キャプチャはこのリポジトリに収録していません。生成した図やHTML応答をAWSコンソールのスクリーンショットとして扱っていません。
