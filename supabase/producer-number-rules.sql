-- 生産者番号ルール対応
-- Supabase SQL Editorで実行してください。
--
-- A列: Excel上の1〜999番を、登録時に「令和年 + 3桁番号」で保存します。
--      例: 278番、令和8年 -> 8278
-- D列: Excel上の2桁番号を、登録時に「令和年 + 月日 + 2桁番号」で保存します。
--      例: 01番、令和8年6月15日 -> 8061501

begin;

alter table public.producers
  add column if not exists producer_source text not null default 'A';

alter table public.producers
  drop constraint if exists producers_producer_source_check;

alter table public.producers
  add constraint producers_producer_source_check
  check (producer_source in ('A', 'D'));

alter table public.producers
  drop constraint if exists producers_pkey;

alter table public.producers
  add constraint producers_pkey
  primary key (producer_source, producer_no);

create or replace view public.pallet_detail_view as
select
  d.pallet_no,
  d.detail_no,
  d.producer_no,
  coalesce(p.producer_name, '') as producer_name,
  d.standard,
  d.weight,
  d.price,
  d.memo
from public.pallet_details d
left join public.producers p on (
  case
    when length(regexp_replace(d.producer_no, '\D', '', 'g')) >= 7 then
      p.producer_source = 'D'
      and lpad(regexp_replace(p.producer_no, '\D', '', 'g'), 2, '0') = right(regexp_replace(d.producer_no, '\D', '', 'g'), 2)
    when length(regexp_replace(d.producer_no, '\D', '', 'g')) >= 4 then
      p.producer_source = 'A'
      and lpad(regexp_replace(p.producer_no, '\D', '', 'g'), 3, '0') = right(regexp_replace(d.producer_no, '\D', '', 'g'), 3)
    else
      p.producer_source = 'A'
      and regexp_replace(p.producer_no, '\D', '', 'g') = regexp_replace(d.producer_no, '\D', '', 'g')
  end
);

commit;
