-- One-time correction of detail weights from pallet weight and container counts.
-- A pallet is updated only when every detail has a positive integer container count in memo.
begin;

create temporary table detail_weight_backfill on commit drop as
with parsed_details as (
  select
    d.pallet_no,
    d.detail_no,
    case
      when btrim(d.memo) ~ '^[0-9]+$' and btrim(d.memo)::numeric > 0
        then btrim(d.memo)::numeric
      else null
    end as container_count
  from public.pallet_details d
), eligible_pallets as (
  select
    p.pallet_no,
    p.weight as pallet_weight,
    sum(d.container_count) as total_containers
  from public.pallets p
  join parsed_details d on d.pallet_no = p.pallet_no
  group by p.pallet_no, p.weight
  having count(*) > 0
     and count(*) = count(d.container_count)
), rounded_weights as (
  select
    d.pallet_no,
    d.detail_no,
    e.pallet_weight,
    round(e.pallet_weight * d.container_count / e.total_containers, 0) as rounded_weight,
    min(d.detail_no) over (partition by d.pallet_no) as adjustment_detail_no
  from parsed_details d
  join eligible_pallets e on e.pallet_no = d.pallet_no
), adjusted_weights as (
  select
    pallet_no,
    detail_no,
    case
      when detail_no = adjustment_detail_no then
        rounded_weight + pallet_weight - sum(rounded_weight) over (partition by pallet_no)
      else rounded_weight
    end as new_weight
  from rounded_weights
)
select * from adjusted_weights;

update public.pallet_details d
set weight = b.new_weight,
    updated_at = now()
from detail_weight_backfill b
where d.pallet_no = b.pallet_no
  and d.detail_no = b.detail_no;

select
  count(distinct pallet_no) as updated_pallets,
  count(*) as updated_details
from detail_weight_backfill;

commit;
