# Terraform化の実測証跡

2026-10-26に既存Day 1環境をIaC管理へ移行しました。

- adoption-apply.txt: 43件import・SSM Document 1件追加・28件更新・削除0件
- start-apply.txt: TerraformによるEC2起動
- configuration-apply.txt: Terraform管理のSSM Association作成と成功待機
- association-executions.json: AWS SSM側の実行成功履歴
- verification.txt / verification.json: 構成適用後のOS・アプリ・DB・保存領域・Agent確認
- stop-apply.txt: 一時Association解除とEC2停止。destroyed 1件はこのAssociationであり、サーバーや保存領域の削除ではありません
- final-plan.txt: 終了後の実環境とTerraform定義の差分なし
- result.json: バージョン・件数・終了状態・検証範囲の要約

実行ログの識別子・コマンド/実行ID・IP等はプレースホルダーへ置換しています。stateやplanそのものは収録していません。新規の空環境からの再構築、スナップショットからの復旧、性能・負荷試験を証明する資料ではありません。
