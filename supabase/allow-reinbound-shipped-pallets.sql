-- 出庫済パレットの再入庫を許可する更新SQLです。
-- Supabase SQL Editorでこのファイル全体を1回実行してください。

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
  if v_pallet.status not in ('未配置', '出庫済') then
    raise exception '入庫できるのは未配置または出庫済のパレットだけです。現在の状態: %', v_pallet.status;
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

grant execute on function public.record_inbound(text, text, text, text) to anon;
