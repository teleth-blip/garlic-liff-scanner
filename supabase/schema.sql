-- にんにく冷蔵庫パレット管理 Supabase版 初期スキーマ
-- 既存のGoogleスプレッドシート版とは別環境です。
-- Supabase SQL Editorでこのファイル全体を実行してください。

create extension if not exists pgcrypto;

create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create table if not exists public.workers (
  worker_id text primary key,
  worker_name text not null,
  role text not null default 'operator' check (role in ('admin', 'operator', 'viewer')),
  display_order integer not null default 999,
  active boolean not null default true,
  note text not null default '',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.standards (
  standard_id text primary key,
  standard_name text not null,
  display_order integer not null default 999,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.coolers (
  cooler_id text primary key,
  cooler_name text not null,
  max_levels integer not null check (max_levels between 1 and 3),
  row_count integer not null check (row_count between 1 and 30),
  col_count integer not null check (col_count between 1 and 30),
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.locations (
  location_id text primary key,
  cooler_id text not null references public.coolers(cooler_id) on delete cascade,
  level_no integer not null check (level_no between 1 and 3),
  row_no integer not null check (row_no between 1 and 30),
  col_no integer not null check (col_no between 1 and 30),
  display_name text not null default '',
  usable boolean not null default true,
  note text not null default '',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (cooler_id, level_no, row_no, col_no)
);

create table if not exists public.producers (
  producer_source text not null default 'A' check (producer_source in ('A', 'D')),
  producer_no text not null,
  producer_name text not null,
  source_updated_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (producer_source, producer_no)
);

create table if not exists public.pallets (
  pallet_no text primary key,
  crop_year integer not null,
  serial_no integer not null,
  weight numeric(12, 2) not null default 0,
  memo text not null default '',
  status text not null default '未配置' check (status in ('未配置', '保管中', '仮移動中', '出庫済')),
  current_location_id text references public.locations(location_id),
  registered_at timestamptz not null default now(),
  registered_worker_id text references public.workers(worker_id),
  updated_at timestamptz not null default now(),
  updated_worker_id text references public.workers(worker_id),
  unique (crop_year, serial_no)
);

create table if not exists public.pallet_details (
  pallet_no text not null references public.pallets(pallet_no) on delete cascade,
  detail_no integer not null,
  producer_no text not null,
  standard text not null,
  weight numeric(12, 2) not null default 0,
  price numeric(12, 2) not null default 0,
  memo text not null default '',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (pallet_no, detail_no)
);

create table if not exists public.placements (
  location_id text primary key references public.locations(location_id) on delete cascade,
  pallet_no text not null unique references public.pallets(pallet_no) on delete cascade,
  status text not null default '使用中' check (status in ('使用中', '仮移動中')),
  updated_at timestamptz not null default now(),
  updated_worker_id text references public.workers(worker_id)
);

create table if not exists public.moving_pallets (
  pallet_no text primary key references public.pallets(pallet_no) on delete cascade,
  from_location_id text references public.locations(location_id),
  started_at timestamptz not null default now(),
  worker_id text references public.workers(worker_id),
  memo text not null default ''
);

create table if not exists public.operation_histories (
  history_id bigserial primary key,
  operated_at timestamptz not null default now(),
  worker_id text references public.workers(worker_id),
  worker_name text not null default '',
  action_type text not null,
  pallet_no text not null default '',
  from_location_id text not null default '',
  to_location_id text not null default '',
  content text not null default '',
  memo text not null default ''
);

create table if not exists public.app_settings (
  setting_key text primary key,
  setting_value jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now()
);

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

drop trigger if exists workers_set_updated_at on public.workers;
create trigger workers_set_updated_at before update on public.workers
for each row execute function public.set_updated_at();

drop trigger if exists standards_set_updated_at on public.standards;
create trigger standards_set_updated_at before update on public.standards
for each row execute function public.set_updated_at();

drop trigger if exists coolers_set_updated_at on public.coolers;
create trigger coolers_set_updated_at before update on public.coolers
for each row execute function public.set_updated_at();

drop trigger if exists locations_set_updated_at on public.locations;
create trigger locations_set_updated_at before update on public.locations
for each row execute function public.set_updated_at();

drop trigger if exists producers_set_updated_at on public.producers;
create trigger producers_set_updated_at before update on public.producers
for each row execute function public.set_updated_at();

drop trigger if exists pallets_set_updated_at on public.pallets;
create trigger pallets_set_updated_at before update on public.pallets
for each row execute function public.set_updated_at();

drop trigger if exists pallet_details_set_updated_at on public.pallet_details;
create trigger pallet_details_set_updated_at before update on public.pallet_details
for each row execute function public.set_updated_at();

insert into public.workers (worker_id, worker_name, role, display_order, active, note) values
  ('W001', '管理者', 'admin', 10, true, '初期管理者'),
  ('W002', '作業者', 'operator', 20, true, '初期作業者'),
  ('W003', '閲覧者', 'viewer', 30, true, '初期閲覧者')
on conflict (worker_id) do nothing;

insert into public.standards (standard_id, standard_name, display_order, active) values
  ('STD-2L', '2L', 10, true),
  ('STD-L', 'L', 20, true),
  ('STD-M', 'M', 30, true),
  ('STD-S', 'S', 40, true)
on conflict (standard_id) do nothing;

insert into public.coolers (cooler_id, cooler_name, max_levels, row_count, col_count, active) values
  ('COLD-A', '1号冷蔵庫', 3, 4, 5, true),
  ('COLD-B', '2号冷蔵庫', 2, 3, 4, true)
on conflict (cooler_id) do nothing;

insert into public.locations (location_id, cooler_id, level_no, row_no, col_no, display_name, usable, note)
select
  c.cooler_id || '-' || l.level_no || '-R' || lpad(r.row_no::text, 2, '0') || '-C' || lpad(col.col_no::text, 2, '0'),
  c.cooler_id,
  l.level_no,
  r.row_no,
  col.col_no,
  'R' || lpad(r.row_no::text, 2, '0') || '-C' || lpad(col.col_no::text, 2, '0'),
  true,
  ''
from public.coolers c
cross join lateral generate_series(1, c.max_levels) as l(level_no)
cross join lateral generate_series(1, c.row_count) as r(row_no)
cross join lateral generate_series(1, c.col_count) as col(col_no)
on conflict (location_id) do nothing;

alter table public.workers enable row level security;
alter table public.standards enable row level security;
alter table public.coolers enable row level security;
alter table public.locations enable row level security;
alter table public.producers enable row level security;
alter table public.pallets enable row level security;
alter table public.pallet_details enable row level security;
alter table public.placements enable row level security;
alter table public.moving_pallets enable row level security;
alter table public.operation_histories enable row level security;
alter table public.app_settings enable row level security;

do $$
declare
  table_name text;
begin
  foreach table_name in array array[
    'workers',
    'standards',
    'coolers',
    'locations',
    'producers',
    'pallets',
    'pallet_details',
    'placements',
    'moving_pallets',
    'operation_histories',
    'app_settings'
  ]
  loop
    execute format('drop policy if exists anon_read_%I on public.%I', table_name, table_name);
    execute format('create policy anon_read_%I on public.%I for select to anon using (true)', table_name, table_name);
  end loop;
end $$;

grant usage on schema public to anon;
grant select on all tables in schema public to anon;
grant select on public.pallet_detail_view to anon;
