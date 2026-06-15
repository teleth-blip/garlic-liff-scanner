# Supabase版 準備手順

このフォルダは、既存のGoogleスプレッドシート版を残したまま、Supabase版を並行して準備するためのものです。

## 1. テーブル作成

Supabaseの対象プロジェクトを開きます。

1. 左メニューの `SQL Editor` を開く
2. `New query` を押す
3. `schema.sql` の内容をすべて貼り付ける
4. `Run` を押す

これでDB版のテーブル、初期マスタ、読み取り用RLSポリシーが作成されます。

## 2. 書き込みRPC作成

Supabase版で登録・入庫・出庫・移動を安全に実行するため、直接テーブルを書かずにRPC関数を使います。

1. 左メニューの `SQL Editor` を開く
2. `New query` を押す
3. `rpc.sql` の内容をすべて貼り付ける
4. `Run` を押す

これで以下のRPCが作成されます。

- `upsert_pallet`
- `delete_pallet_rpc`
- `record_inbound`
- `record_outbound`
- `start_move`
- `complete_move`

## 3. 現在のスプレッドシートデータを反映

`schema.sql` を実行した直後は、作業者などが初期データのままです。
既存のスプレッドシート版に入っている現在のデータへ揃える場合は、次を実行します。

1. 左メニューの `SQL Editor` を開く
2. `New query` を押す
3. `import-current-spreadsheet-data.sql` の内容をすべて貼り付ける
4. `Run` を押す

このSQLはSupabase側のテスト/初期データを消して、現在のスプレッドシートから取得した作業者、規格、冷蔵庫、保管場所、生産者、パレット、配置を入れ直します。
スプレッドシート本体には影響しません。

生産者マスタをExcelから再取り込みする場合は、セルの表示文字列だけを使います。
読み仮名、ふりがな、phonetic情報、rich textの内部情報は生産者名に含めないでください。

既存データの表示名だけを補修する場合は、`fix-producer-display-names.sql` をSupabaseの `SQL Editor` で実行します。

## 4. 接続確認

GitHub Pagesに反映後、次の確認URLを開きます。

```text
https://teleth-blip.github.io/garlic-liff-scanner/supabase/
```

`接続OK` と表示され、作業者が表示されればSupabase接続は成功です。
`RPC状態` が `RPC接続OK` になれば、書き込み用RPCも準備済みです。

正式版アプリ:

```text
https://teleth-blip.github.io/garlic-liff-scanner/
```

## 5. 現在の運用への影響

この作業は既存のスプレッドシート本体には影響しません。

正式版:

```text
https://teleth-blip.github.io/garlic-liff-scanner/
```

旧GAS版:

```text
https://teleth-blip.github.io/garlic-liff-scanner/gas-legacy.html
```

Supabase版準備確認:

```text
https://teleth-blip.github.io/garlic-liff-scanner/supabase/
```

## 6. 注意

`publishable key` はブラウザ側に置ける公開キーです。
`secret`、`service_role`、DB password はここに書かないでください。

公開キーでは直接テーブルを書き込めないようにし、登録・入庫・出庫・移動はRPC経由で実行します。
