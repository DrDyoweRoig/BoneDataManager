-- Bone Data Manager — shared Ref IDs for teeth (spec §18). Run after 001_init.sql.

-- A Ref ID may now be shared by several rows; one element appears once per ID among live rows.
alter table public.entries drop constraint if exists entries_database_id_number_key;
alter table public.entries drop constraint if exists entries_database_id_ref_id_key;
create unique index if not exists entries_one_element_per_id on public.entries
  (database_id, number, element_id, coalesce(dentition, ''), coalesce(tooth_type, ''),
   coalesce(jaw, ''), coalesce(side, ''))
  where not deleted;

-- create_entries gains `shared`: all drafts get one number.
drop function if exists public.create_entries(uuid, jsonb, text);
create or replace function public.create_entries(db uuid, drafts jsonb, observer text, shared boolean default false)
returns setof public.entries language plpgsql security definer set search_path = public as $$
declare
  n       int := jsonb_array_length(drafts);
  start_n int;
  p       text;
  dg      int;
  ids     uuid[];
begin
  perform public._require(db, array['owner', 'editor']);
  select array_agg((v ->> 'id')::uuid) into ids
  from jsonb_array_elements(drafts) v where v ? 'id';

  if ids is not null and array_length(ids, 1) = n
     and (select count(*) from public.entries where database_id = db and id = any (ids)) = n then
    return query select * from public.entries where database_id = db and id = any (ids) order by number;
    return;
  end if;

  update public.databases set next_number = next_number + case when shared then 1 else n end
  where id = db
  returning next_number - case when shared then 1 else n end, prefix, digits into start_n, p, dg;

  return query
  insert into public.entries (id, database_id, number, ref_id, element_id, dentition, tooth_type, jaw, side,
                              "values", created_by, created_at, modified_by, modified_at, version, deleted)
  select coalesce((d.v ->> 'id')::uuid, gen_random_uuid()), db,
         start_n + case when shared then 0 else (d.ord - 1)::int end,
         public._ref(p, dg, start_n + case when shared then 0 else (d.ord - 1)::int end),
         d.v ->> 'element_id', d.v ->> 'dentition', d.v ->> 'tooth_type', d.v ->> 'jaw', d.v ->> 'side',
         coalesce(d.v -> 'values', '{}'), observer, now(), observer, now(), 1, false
  from jsonb_array_elements(drafts) with ordinality as d(v, ord)
  on conflict (id) do nothing
  returning *;
end $$;
revoke execute on function public.create_entries(uuid, jsonb, text, boolean) from public, anon;
grant execute on function public.create_entries(uuid, jsonb, text, boolean) to authenticated;

-- push_entry: a new row may join an existing Ref ID ("Add teeth to …", also offline).
create or replace function public.push_entry(db uuid, e jsonb, base_version int)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  eid uuid := (e ->> 'id')::uuid;
  num int  := (e ->> 'number')::int;
  cur public.entries;
  v   int;
begin
  perform public._require(db, array['owner', 'editor']);
  select * into cur from public.entries where id = eid and database_id = db for update;

  if not found then
    -- A new row's number comes from a reserved block, or joins an existing (shared) Ref ID.
    if not exists (select 1 from public.id_blocks b
                   where b.database_id = db and num between b.start_number and b.end_number)
       and not exists (select 1 from public.entries x where x.database_id = db and x.number = num) then
      raise exception 'Number % was not reserved for offline use', num using errcode = '22023';
    end if;
    insert into public.entries (id, database_id, number, ref_id, element_id, dentition, tooth_type, jaw, side,
                                "values", created_by, created_at, modified_by, modified_at, version, deleted)
    values (eid, db, num, e ->> 'ref_id', e ->> 'element_id', e ->> 'dentition', e ->> 'tooth_type',
            e ->> 'jaw', e ->> 'side', coalesce(e -> 'values', '{}'), coalesce(e ->> 'created_by', ''),
            (e ->> 'created_at')::timestamptz, coalesce(e ->> 'modified_by', ''),
            (e ->> 'modified_at')::timestamptz, 1, coalesce((e ->> 'deleted')::boolean, false));
    return jsonb_build_object('status', 'ok', 'version', 1);
  end if;

  if base_version = 0 then
    base_version := 1;
  end if;
  if cur.version <> base_version then
    if cur.element_id is not distinct from e ->> 'element_id'
       and cur.dentition is not distinct from e ->> 'dentition'
       and cur.tooth_type is not distinct from e ->> 'tooth_type'
       and cur.jaw is not distinct from e ->> 'jaw'
       and cur.side is not distinct from e ->> 'side'
       and cur."values" = coalesce(e -> 'values', '{}')
       and cur.deleted = coalesce((e ->> 'deleted')::boolean, false) then
      return jsonb_build_object('status', 'ok', 'version', cur.version);
    end if;
    return jsonb_build_object('status', 'conflict', 'row', to_jsonb(cur));
  end if;

  update public.entries
  set element_id = e ->> 'element_id', dentition = e ->> 'dentition', tooth_type = e ->> 'tooth_type',
      jaw = e ->> 'jaw', side = e ->> 'side', "values" = coalesce(e -> 'values', '{}'),
      modified_by = coalesce(e ->> 'modified_by', ''), modified_at = (e ->> 'modified_at')::timestamptz,
      deleted = coalesce((e ->> 'deleted')::boolean, false),
      version = cur.version + 1, updated_at = now()
  where id = eid
  returning version into v;
  return jsonb_build_object('status', 'ok', 'version', v);
end $$;
