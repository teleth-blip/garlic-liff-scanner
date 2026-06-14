-- にんにく冷蔵庫パレット管理 Supabase版 書き込みRPC
-- schema.sqlを実行した後に、このファイル全体をSupabase SQL Editorで実行してください。

create or replace function public.require_active_worker(p_worker_id text)
returns public.workers
language plpgsql
security definer
set search_path = public
as $$
declare
  v_worker public.workers%rowtype;
begin
  select *
    into v_worker
    from public.workers
   where worker_id = btrim(coalesce(p_worker_id, ''))
     and active = true;

  if not found then
    raise exception '作業者が選択されていません。';
  end if;

  return v_worker;
end;
$$;

create or replace function public.require_location_can_receive(p_location_id text)
returns public.locations
language plpgsql
security definer
set search_path = public
as $$
declare
  v_location public.locations%rowtype;
  v_below_location_id text;
begin
  select *
    into v_location
    from public.locations
   where location_id = btrim(coalesce(p_location_id, ''));

  if not found then
    raise exception '保管場所が見つかりません: %', p_location_id;
  end if;

  if not v_location.usable then
    raise exception '使用不可の場所には配置できません。';
  end if;

  if exists (select 1 from public.placements where location_id = v_location.location_id) then
    raise exception '選択した場所は使用中です。';
  end if;

  if v_location.level_no > 1 then
    select location_id
      into v_below_location_id
      from public.locations
     where cooler_id = v_location.cooler_id
       and level_no = v_location.level_no - 1
       and row_no = v_location.row_no
       and col_no = v_location.col_no
       and usable = true;

    if v_below_location_id is null then
      raise exception '下段が使用不可のため配置できません。';
    end if;

    if not exists (select 1 from public.placements where location_id = v_below_location_id) then
      raise exception '%段目に配置するには、同じ位置の%段目にパレットが必要です。', v_location.level_no, v_location.level_no - 1;
    end if;
  end if;

  return v_location;
end;
$$;

create or replace function public.require_location_can_remove(p_location_id text)
returns public.locations
language plpgsql
security definer
set search_path = public
as $$
declare
  v_location public.locations%rowtype;
begin
  select *
    into v_location
    from public.locations
   where location_id = btrim(coalesce(p_location_id, ''));

  if not found then
    raise exception '保管場所が見つかりません: %', p_location_id;
  end if;

  if exists (
    select 1
      from public.locations upper_loc
      join public.placements upper_pl on upper_pl.location_id = upper_loc.location_id
     where upper_loc.cooler_id = v_location.cooler_id
       and upper_loc.level_no = v_location.level_no + 1
       and upper_loc.row_no = v_location.row_no
       and upper_loc.col_no = v_location.col_no
  ) then
    raise exception '%段目を動かすには、同じ位置の%段目を先に空けてください。', v_location.level_no, v_location.level_no + 1;
  end if;

  return v_location;
end;
$$;

create or replace function public.write_history(
  p_worker public.workers,
  p_action_type text,
  p_pallet_no text,
  p_from_location_id text,
  p_to_location_id text,
  p_content text,
  p_memo text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.operation_histories (
    worker_id,
    worker_name,
    action_type,
    pallet_no,
    from_location_id,
    to_location_id,
    content,
    memo
  ) values (
    p_worker.worker_id,
    p_worker.worker_name,
    coalesce(p_action_type, ''),
    coalesce(p_pallet_no, ''),
    coalesce(p_from_location_id, ''),
    coalesce(p_to_location_id, ''),
    coalesce(p_content, ''),
    coalesce(p_memo, '')
  );
end;
$$;

create or replace function public.ping_write_api()
returns jsonb
language sql
security definer
set search_path = public
as $$
  select jsonb_build_object('ok', true, 'message', 'RPC接続OK', 'at', now());
$$;

create or replace function public.upsert_pallet(p_payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_worker public.workers%rowtype;
  v_existing public.pallets%rowtype;
  v_worker_id text := btrim(coalesce(p_payload->>'workerId', p_payload->>'worker_id', ''));
  v_pallet_no text := btrim(coalesce(p_payload->>'palletNo', p_payload->>'pallet_no', ''));
  v_crop_year integer := nullif(btrim(coalesce(p_payload->>'cropYear', p_payload->>'crop_year', '')), '')::integer;
  v_serial_no integer := nullif(btrim(coalesce(p_payload->>'serialNo', p_payload->>'serial_no', '')), '')::integer;
  v_memo text := coalesce(p_payload->>'memo', '');
  v_status text := coalesce(nullif(btrim(coalesce(p_payload->>'status', '')), ''), '未配置');
  v_details jsonb := coalesce(p_payload->'details', '[]'::jsonb);
  v_detail jsonb;
  v_detail_no integer := 0;
  v_detail_weight numeric(12, 2);
  v_detail_price numeric(12, 2);
  v_total_weight numeric(12, 2) := 0;
  v_producer_no text;
  v_standard text;
  v_detail_memo text;
  v_is_new boolean;
begin
  select * into v_worker from public.require_active_worker(v_worker_id);

  if v_pallet_no = '' then
    raise exception 'パレット番号を入力してください。';
  end if;
  if v_crop_year is null or v_serial_no is null then
    raise exception '産年と連番を入力してください。';
  end if;
  if jsonb_typeof(v_details) <> 'array' then
    raise exception '明細データの形式が不正です。';
  end if;

  perform pg_advisory_xact_lock(hashtext(v_pallet_no)::bigint);

  select *
    into v_existing
    from public.pallets
   where pallet_no = v_pallet_no
   for update;

  v_is_new := not found;

  if v_status not in ('未配置', '保管中', '仮移動中', '出庫済') then
    raise exception '状態が不正です: %', v_status;
  end if;

  if v_is_new then
    if v_status not in ('未配置', '出庫済') then
      raise exception '新規登録時の状態は未配置または出庫済にしてください。';
    end if;
    insert into public.pallets (
      pallet_no,
      crop_year,
      serial_no,
      weight,
      memo,
      status,
      registered_worker_id,
      updated_worker_id
    ) values (
      v_pallet_no,
      v_crop_year,
      v_serial_no,
      0,
      v_memo,
      v_status,
      v_worker.worker_id,
      v_worker.worker_id
    );
  else
    if v_existing.status in ('保管中', '仮移動中') and v_status <> v_existing.status then
      raise exception '保管中または仮移動中のパレット状態は、入庫・出庫・移動処理で変更してください。';
    end if;

    update public.pallets
       set crop_year = v_crop_year,
           serial_no = v_serial_no,
           memo = v_memo,
           status = v_status,
           updated_worker_id = v_worker.worker_id
     where pallet_no = v_pallet_no;

    delete from public.pallet_details where pallet_no = v_pallet_no;
  end if;

  for v_detail in select value from jsonb_array_elements(v_details)
  loop
    v_detail_no := v_detail_no + 1;
    v_producer_no := btrim(coalesce(v_detail->>'producerNo', v_detail->>'producer_no', ''));
    v_standard := btrim(coalesce(v_detail->>'standard', ''));
    v_detail_weight := coalesce(nullif(btrim(coalesce(v_detail->>'weight', '')), '')::numeric, 0);
    v_detail_price := coalesce(nullif(btrim(coalesce(v_detail->>'price', '')), '')::numeric, 0);
    v_detail_memo := coalesce(v_detail->>'memo', '');

    if v_producer_no = '' then
      raise exception '明細%行目の生産者番号を入力してください。', v_detail_no;
    end if;
    if v_standard = '' then
      raise exception '明細%行目の規格を入力してください。', v_detail_no;
    end if;
    if v_detail_weight < 0 or v_detail_price < 0 then
      raise exception '明細%行目の重量または価格が不正です。', v_detail_no;
    end if;

    insert into public.pallet_details (
      pallet_no,
      detail_no,
      producer_no,
      standard,
      weight,
      price,
      memo
    ) values (
      v_pallet_no,
      v_detail_no,
      v_producer_no,
      v_standard,
      v_detail_weight,
      v_detail_price,
      v_detail_memo
    );

    v_total_weight := v_total_weight + v_detail_weight;
  end loop;

  update public.pallets
     set weight = v_total_weight,
         updated_worker_id = v_worker.worker_id
   where pallet_no = v_pallet_no;

  perform public.write_history(
    v_worker,
    case when v_is_new then '登録' else '修正' end,
    v_pallet_no,
    '',
    '',
    'パレット情報を保存しました。重量=' || v_total_weight,
    v_memo
  );

  return jsonb_build_object(
    'ok', true,
    'message', case when v_is_new then 'パレットを登録しました。' else 'パレットを更新しました。' end,
    'palletNo', v_pallet_no,
    'weight', v_total_weight
  );
end;
$$;

create or replace function public.delete_pallet_rpc(p_worker_id text, p_pallet_no text, p_memo text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_worker public.workers%rowtype;
  v_pallet public.pallets%rowtype;
  v_pallet_no text := btrim(coalesce(p_pallet_no, ''));
begin
  select * into v_worker from public.require_active_worker(p_worker_id);
  perform pg_advisory_xact_lock(hashtext(v_pallet_no)::bigint);

  select *
    into v_pallet
    from public.pallets
   where pallet_no = v_pallet_no
   for update;

  if not found then
    raise exception 'パレットが見つかりません: %', v_pallet_no;
  end if;
  if v_pallet.status <> '未配置' then
    raise exception '削除できるのは未配置のパレットだけです。';
  end if;
  if exists (select 1 from public.placements where pallet_no = v_pallet_no)
     or exists (select 1 from public.moving_pallets where pallet_no = v_pallet_no) then
    raise exception '配置中または仮移動中の記録が残っているため削除できません。';
  end if;

  delete from public.pallets where pallet_no = v_pallet_no;
  perform public.write_history(v_worker, '削除', v_pallet_no, '', '', '未配置パレットを削除しました。', p_memo);

  return jsonb_build_object('ok', true, 'message', 'パレットを削除しました。', 'palletNo', v_pallet_no);
end;
$$;

create or replace function public.record_inbound(p_worker_id text, p_pallet_no text, p_location_id text, p_memo text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_worker public.workers%rowtype;
  v_pallet public.pallets%rowtype;
  v_location public.locations%rowtype;
  v_pallet_no text := btrim(coalesce(p_pallet_no, ''));
  v_location_id text := btrim(coalesce(p_location_id, ''));
begin
  select * into v_worker from public.require_active_worker(p_worker_id);
  perform pg_advisory_xact_lock(hashtext(v_pallet_no)::bigint);
  perform pg_advisory_xact_lock(hashtext(v_location_id)::bigint);

  select *
    into v_pallet
    from public.pallets
   where pallet_no = v_pallet_no
   for update;

  if not found then
    raise exception 'パレットが見つかりません: %', v_pallet_no;
  end if;
  if v_pallet.status <> '未配置' then
    raise exception '入庫できるのは未配置のパレットだけです。現在の状態: %', v_pallet.status;
  end if;

  select * into v_location from public.require_location_can_receive(v_location_id);

  insert into public.placements (location_id, pallet_no, status, updated_worker_id)
  values (v_location.location_id, v_pallet_no, '使用中', v_worker.worker_id);

  update public.pallets
     set status = '保管中',
         current_location_id = v_location.location_id,
         updated_worker_id = v_worker.worker_id
   where pallet_no = v_pallet_no;

  perform public.write_history(v_worker, '入庫', v_pallet_no, '', v_location.location_id, '入庫を登録しました。', p_memo);

  return jsonb_build_object('ok', true, 'message', '入庫を登録しました。', 'palletNo', v_pallet_no, 'locationId', v_location.location_id);
end;
$$;

create or replace function public.record_outbound(p_worker_id text, p_pallet_no text, p_memo text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_worker public.workers%rowtype;
  v_pallet public.pallets%rowtype;
  v_location public.locations%rowtype;
  v_pallet_no text := btrim(coalesce(p_pallet_no, ''));
  v_from_location_id text;
begin
  select * into v_worker from public.require_active_worker(p_worker_id);
  perform pg_advisory_xact_lock(hashtext(v_pallet_no)::bigint);

  select *
    into v_pallet
    from public.pallets
   where pallet_no = v_pallet_no
   for update;

  if not found then
    raise exception 'パレットが見つかりません: %', v_pallet_no;
  end if;
  if v_pallet.status <> '保管中' or v_pallet.current_location_id is null then
    raise exception '出庫できるのは保管中のパレットだけです。現在の状態: %', v_pallet.status;
  end if;

  v_from_location_id := v_pallet.current_location_id;
  perform pg_advisory_xact_lock(hashtext(v_from_location_id)::bigint);
  if not exists (
    select 1
      from public.placements
     where pallet_no = v_pallet_no
       and location_id = v_from_location_id
  ) then
    raise exception '現在場所と配置情報が一致しません。配置確認を行ってください。';
  end if;
  select * into v_location from public.require_location_can_remove(v_from_location_id);

  delete from public.placements where pallet_no = v_pallet_no;

  update public.pallets
     set status = '出庫済',
         current_location_id = null,
         updated_worker_id = v_worker.worker_id
   where pallet_no = v_pallet_no;

  perform public.write_history(v_worker, '出庫', v_pallet_no, v_from_location_id, '', '出庫を登録しました。', p_memo);

  return jsonb_build_object('ok', true, 'message', '出庫を登録しました。', 'palletNo', v_pallet_no);
end;
$$;

create or replace function public.start_move(p_worker_id text, p_pallet_no text, p_memo text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_worker public.workers%rowtype;
  v_pallet public.pallets%rowtype;
  v_pallet_no text := btrim(coalesce(p_pallet_no, ''));
  v_from_location_id text;
begin
  select * into v_worker from public.require_active_worker(p_worker_id);
  perform pg_advisory_xact_lock(hashtext(v_pallet_no)::bigint);

  select *
    into v_pallet
    from public.pallets
   where pallet_no = v_pallet_no
   for update;

  if not found then
    raise exception 'パレットが見つかりません: %', v_pallet_no;
  end if;
  if v_pallet.status <> '保管中' or v_pallet.current_location_id is null then
    raise exception '仮移動できるのは保管中のパレットだけです。現在の状態: %', v_pallet.status;
  end if;

  v_from_location_id := v_pallet.current_location_id;
  perform pg_advisory_xact_lock(hashtext(v_from_location_id)::bigint);
  if not exists (
    select 1
      from public.placements
     where pallet_no = v_pallet_no
       and location_id = v_from_location_id
  ) then
    raise exception '現在場所と配置情報が一致しません。配置確認を行ってください。';
  end if;
  perform public.require_location_can_remove(v_from_location_id);

  delete from public.placements where pallet_no = v_pallet_no;

  update public.pallets
     set status = '仮移動中',
         current_location_id = null,
         updated_worker_id = v_worker.worker_id
   where pallet_no = v_pallet_no;

  insert into public.moving_pallets (pallet_no, from_location_id, worker_id, memo)
  values (v_pallet_no, v_from_location_id, v_worker.worker_id, coalesce(p_memo, ''))
  on conflict (pallet_no) do update
     set from_location_id = excluded.from_location_id,
         started_at = now(),
         worker_id = excluded.worker_id,
         memo = excluded.memo;

  perform public.write_history(v_worker, '仮移動', v_pallet_no, v_from_location_id, '', '仮移動を開始しました。', p_memo);

  return jsonb_build_object('ok', true, 'message', '仮移動を開始しました。', 'palletNo', v_pallet_no, 'fromLocationId', v_from_location_id);
end;
$$;

create or replace function public.complete_move(p_worker_id text, p_pallet_no text, p_location_id text, p_memo text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_worker public.workers%rowtype;
  v_pallet public.pallets%rowtype;
  v_moving public.moving_pallets%rowtype;
  v_location public.locations%rowtype;
  v_pallet_no text := btrim(coalesce(p_pallet_no, ''));
  v_location_id text := btrim(coalesce(p_location_id, ''));
begin
  select * into v_worker from public.require_active_worker(p_worker_id);
  perform pg_advisory_xact_lock(hashtext(v_pallet_no)::bigint);
  perform pg_advisory_xact_lock(hashtext(v_location_id)::bigint);

  select *
    into v_pallet
    from public.pallets
   where pallet_no = v_pallet_no
   for update;

  if not found then
    raise exception 'パレットが見つかりません: %', v_pallet_no;
  end if;
  if v_pallet.status <> '仮移動中' then
    raise exception '移動確定できるのは仮移動中のパレットだけです。現在の状態: %', v_pallet.status;
  end if;

  select *
    into v_moving
    from public.moving_pallets
   where pallet_no = v_pallet_no
   for update;

  if not found then
    raise exception '仮移動中の記録が見つかりません。';
  end if;

  select * into v_location from public.require_location_can_receive(v_location_id);

  insert into public.placements (location_id, pallet_no, status, updated_worker_id)
  values (v_location.location_id, v_pallet_no, '使用中', v_worker.worker_id);

  update public.pallets
     set status = '保管中',
         current_location_id = v_location.location_id,
         updated_worker_id = v_worker.worker_id
   where pallet_no = v_pallet_no;

  delete from public.moving_pallets where pallet_no = v_pallet_no;

  perform public.write_history(v_worker, '移動確定', v_pallet_no, v_moving.from_location_id, v_location.location_id, '移動を確定しました。', p_memo);

  return jsonb_build_object('ok', true, 'message', '移動を確定しました。', 'palletNo', v_pallet_no, 'locationId', v_location.location_id);
end;
$$;

revoke all on function public.require_active_worker(text) from public, anon, authenticated;
revoke all on function public.require_location_can_receive(text) from public, anon, authenticated;
revoke all on function public.require_location_can_remove(text) from public, anon, authenticated;
revoke all on function public.write_history(public.workers, text, text, text, text, text, text) from public, anon, authenticated;

grant execute on function public.ping_write_api() to anon;
grant execute on function public.upsert_pallet(jsonb) to anon;
grant execute on function public.delete_pallet_rpc(text, text, text) to anon;
grant execute on function public.record_inbound(text, text, text, text) to anon;
grant execute on function public.record_outbound(text, text, text) to anon;
grant execute on function public.start_move(text, text, text) to anon;
grant execute on function public.complete_move(text, text, text, text) to anon;
