-- 生産者マスタの表示名補修
-- Supabase SQL Editorで実行してください。
--
-- Excelから生産者名を取り込む際は、読み仮名やIME由来の追加情報ではなく、
-- セルに表示されている文字列だけを取り込んでください。
-- 例: xlsx処理では rich text / phonetic 情報ではなく formatted text / displayed text を使います。

begin;

update public.producers
   set producer_name = '佐々木俊明'
 where producer_no = '278'
   and producer_name <> '佐々木俊明';

commit;
