alter table public.frozen_ingredient_materials
add column if not exists unit_name text;

update public.frozen_ingredient_materials
set unit_name = 'kg'
where unit_name is null or btrim(unit_name) = '';

alter table public.frozen_ingredient_materials
alter column unit_name set default 'kg';

alter table public.frozen_ingredient_materials
alter column unit_name set not null;

do $$
begin
  if not exists (
    select 1
      from pg_constraint
     where conname = 'frozen_ingredient_materials_unit_name_check'
  ) then
    alter table public.frozen_ingredient_materials
    add constraint frozen_ingredient_materials_unit_name_check
    check (char_length(btrim(unit_name)) between 1 and 20);
  end if;
end $$;

comment on column public.frozen_ingredient_materials.unit_name is '数量単位';
