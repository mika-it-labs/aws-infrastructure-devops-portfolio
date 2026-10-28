# Day 4の定義と確認手順

実施結果と現在の終了状態は[コンソール記録](../docs/day4-console.md)を参照してください。現時点はSNS・ECSバッチ・Step Functionsの成功/失敗通知まで検証済みです。

| ファイル | 内容 |
|---|---|
| task-definition.example.json | Amazon LinuxのFargateバッチ定義 |
| state-machine.example.asl.json | 完了待機、終了コード判定、成功・失敗のSNS通知 |
| sfn-role-policy.example.json | 今回のタスク・クラスター・通知先に限定した許可 |
| sfn-trust-policy.example.json | 同一アカウントの今回のワークフローだけを信頼 |
| events-role-policy.example.json | 定期起動用のStartExecution限定許可。AWS上の作成は未実施 |
| events-trust-policy.example.json | 同一アカウントの今回の定期ルールだけを信頼。AWS上の作成は未実施 |

`ACCOUNT_ID`、`PUBLIC_SUBNET_A`、`PUBLIC_SUBNET_B`、`BATCH_SECURITY_GROUP_ID` は自身の学習環境に置き換えます。ECS実行ロールは既存の `ecsTaskExecutionRole` を参照します。ロググループ `/portfolio/day4/batch` を事前に作成して保持7日にします。

AWSコンソールのECSでクラスター、JSONを使用したタスク定義を作り、Step FunctionsではStandard・JSONPathでASLを入力しました。専用ロールを指定し、次の入力で個別に実行します。`forceFailure` は文字列です。

成功ケース：

```json
{"forceFailure":"false"}
```

失敗ケース：

```json
{"forceFailure":"true"}
```

後者はサンプルバッチが意図的に42で終了します。今回の実行では `RunBatch` が `States.TaskFailed` になり、Catch → NotifyError → BatchFailedに進みました。SNS通知ステップの成功と実際のメール受信の両方を照合しています。

このバッチにタスクロールやDB認証情報は与えていません。定期実行やアラーム等の未実施項目は、上の実施記録で区別しています。

