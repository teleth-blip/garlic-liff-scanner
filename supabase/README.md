# Supabase版 準備手順

このフォルダは、既存のGoogleスプレッドシート版を残したまま、Supabase版を並行して準備するためのものです。

## 1. テーブル作成

Supabaseの対象プロジェクトを開きます。

1. 左メニューの `SQL Editor` を開く
2. `New query` を押す
3. `schema.sql` の内容をすべて貼り付ける
4. `Run` を押す

これでDB版のテーブル、初期マスタ、読み取り用RLSポリシーが作成されます。

## 2. 接続確認

GitHub Pagesに反映後、次のURLを開きます。

```text
https://teleth-blip.github.io/garlic-liff-scanner/supabase/
```

`接続OK` と表示され、作業者が表示されればSupabase接続は成功です。

## 3. 現在の運用への影響

この作業は既存のスプレッドシート版には影響しません。

既存版:

```text
https://teleth-blip.github.io/garlic-liff-scanner/
```

Supabase版準備確認:

```text
https://teleth-blip.github.io/garlic-liff-scanner/supabase/
```

## 4. 注意

`publishable key` はブラウザ側に置ける公開キーです。
`secret`、`service_role`、DB password はここに書かないでください。

現在のSQLは読み取り確認用です。登録・入庫・出庫・移動の書き込み処理は、次の段階で制約付きRPCとして追加します。
