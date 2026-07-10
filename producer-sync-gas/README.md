# 生産者マスタ同期 Apps Script

Google Drive上のExcelファイルを定期確認し、更新されている場合だけ生産者マスタをSupabaseへ反映します。

## 初期設定

1. このフォルダをApps Scriptプロジェクトとして作成または `clasp push` します。
2. Apps Scriptの「サービス」で Drive API を有効化します。
3. スクリプトプロパティに以下を設定します。
   - `SUPABASE_SERVICE_ROLE_KEY`: Supabaseの Legacy API Keys にある `service_role` key
   - `SUPABASE_URL`: `https://yedrlbrzrkbtgswzplia.supabase.co`（省略可）
4. `installHourlyProducerSyncTrigger` を1回実行して承認します。
5. Webアプリとしてデプロイし、URLを本体画面の「即時反映URL」に保存します。

## 動作

- 時間トリガーは1時間ごとに起動します。
- 本体画面の「更新間隔（時間）」に達していない場合は確認をスキップします。
- Excelファイルの更新日時が前回同期時と同じ場合は読み込みをスキップします。
- 更新がある場合のみ、Excelを一時的にGoogleスプレッドシートへ変換し、表示文字列だけを読み込んでSupabaseの `producers` にupsertします。

## 読み取り列

- A列/B列: `producer_source = 'A'`, `producer_no = 3桁`
- D列/E列: `producer_source = 'D'`, `producer_no = 2桁`

一時変換したGoogleスプレッドシートは同期後にゴミ箱へ移動します。

## Supabaseキー

Apps Scriptでは `sb_secret_...` のSecret keyを使わず、Legacy API Keys の `service_role` keyを使います。
`sb_secret_...` はSupabase側でブラウザ扱いとして拒否される場合があります。
`sb_publishable_...` は公開画面用のキーなので、同期用には使えません。
