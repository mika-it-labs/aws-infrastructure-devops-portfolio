# TerraformによるDay 2復元の証跡

2026-10-27にAWS CLI・Terraform・SSMで取得した結果を、公開用に整理しています。

- execution-summary.txt：実際のimport・apply・No changesの出力から抽出。
- verification.json：SSM get-command-invocationの応答。識別子は置換。
- metrics.json：今回のALBのHTTPCode_Target_5XX_Count、1分ごとのSum。
- alarm-events.json：今回の検証開始以降の状態変更。前日の同名アラーム履歴は除外。
- log-arrival.json：今回のALBの.log.gz到着時刻とサイズ。キー名のアカウントID・IP等は非公開。
- final-inventory.json：追加分の削除、EC2停止、元データ保持をAWS APIで照合した結果。

state・plan・認証情報・実行時変数・未加工のAWS応答は含めていません。画面画像の代わりとして加工画像を作ることはせず、API応答と実行結果を記録しています。

ジョブの開始はCLIによる操作であり、復元実体をTerraformへ取り込んで管理しています。Terraformだけでジョブ履歴そのものを再現した実績ではありません。[実施記録](../../docs/day2-terraform-result.md)を参照してください。

