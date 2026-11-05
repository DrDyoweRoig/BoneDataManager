-- Bone Data Manager — gapless Ref IDs: offline entries get provisional (TEMP) numbers that claim a real
-- number on sync, the Owner can close gaps ("Close Ref ID gaps"), and a numbering epoch tells devices
-- that numbers changed. Safe to run after 001–003. Replaces reserved offline blocks (id_blocks).

-- ───────────────────────── Schema ─────────────────────────

alter table public.entries add column if not exists previous_ref_ids jsonb not null default '[]';
alter table public.databases add column if not exists numbering_epoch int not null default 0;

-- Real numbers given to provisional groups. A retried claim (lost answer) gets the same number back.
create table if not exists public.temp_claims (
  database_id uuid not null references public.databases(id) on delete cascade,
  device_id   text not null,
  temp_number int  not null,
  number      int  not null,
  primary key (database_id, device_id, temp_number)
);
alter table public.temp_claims enable row level security;
drop policy if exists temp_claims_read on public.temp_claims;
create policy temp_claims_read on public.temp_claims for select to authenticated
  using (public.my_role(database_id) is not null);
-- temp_claims is written only through the functions below.
grant select on public.temp_claims to authenticated;

-- Reserved blocks are no longer used.
drop function if exists public.reserve_block(uuid, text, int);
drop table if exists public.id_blocks;

-- ───────────────────────── Functions (RPC) ─────────────────────────

-- The real number for provisional group `temp` of `device`. `ids` are the group's entry ids: if one of
-- them already reached the server (an online create whose answer was lost), its number is reused.
create or replace function public.claim_number(db uuid, device text, temp int, ids uuid[])
returns int language plpgsql security definer set search_path = public as $$
declare
  n int;
begin
  perform public._require(db, array['owner', 'editor']);
  -- One claim at a time per database, and never during compact_ref_ids.
  perform 1 from public.databases d where d.id = db for no key update;

  select c.number into n from public.temp_claims c
  where c.database_id = db and c.device_id = device and c.temp_number = temp;
  if found then
    return n;
  end if;

  select x.number into n from public.entries x
  where x.database_id = db and x.id = any (ids)
  order by x.deleted, x.number
  limit 1;
  if not found then
    -- Skips numbers still held by deleted rows (possible after a compaction), so a claim whose rows are
    -- not uploaded yet never shares its number with an entry: compact_ref_ids relies on that.
    loop
      update public.databases d set next_number = d.next_number + 1
      where d.id = db
      returning d.next_number - 1 into n;
      exit when not exists (select 1 from public.entries x where x.database_id = db and x.number = n);
    end loop;
  end if;

  insert into public.temp_claims (database_id, device_id, temp_number, number) values (db, device, temp, n);
  return n;
end $$;

-- Close Ref ID gaps (Owner): live numbers become 1, 2, 3… in order. A changed row keeps its old Ref ID
-- in previous_ref_ids; its version is not bumped, so pending edits on devices do not conflict.
-- Returns {"epoch": n, "changes": [{id, number, ref_id, previous_ref_ids}, …]}.
create or replace function public.compact_ref_ids(db uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  p         text;
  dg        int;
  cur_epoch int;
  k         int;
  olds      int[];
  news      int[];
  changes   jsonb;
begin
  perform public._require(db, array['owner']);
  -- Waits for running pushes and claims; new ones wait until this finishes.
  select d.prefix, d.digits, d.numbering_epoch into p, dg, cur_epoch
  from public.databases d where d.id = db for update;

  if exists (select 1 from public.entries x where x.database_id = db and not x.deleted and x.number < 1) then
    raise exception 'Some entries have an invalid Ref ID number' using errcode = '22023';
  end if;

  -- Live numbers: those of live entries, plus claims whose entries have not been uploaded yet.
  with live as (
    select x.number from public.entries x where x.database_id = db and not x.deleted
    union
    select c.number from public.temp_claims c
    where c.database_id = db
      and not exists (select 1 from public.entries y where y.database_id = db and y.number = c.number)
  ), m as (
    select l.number as old_n, (row_number() over (order by l.number))::int as new_n from live l
  )
  select count(*)::int,
         coalesce(array_agg(m.old_n order by m.old_n) filter (where m.old_n <> m.new_n), '{}'),
         coalesce(array_agg(m.new_n order by m.old_n) filter (where m.old_n <> m.new_n), '{}')
  into k, olds, news
  from m;

  update public.databases d set next_number = k + 1 where d.id = db;

  if cardinality(olds) = 0 then
    return jsonb_build_object('epoch', cur_epoch, 'changes', '[]'::jsonb);
  end if;

  -- Two phases so no row lands on a number another live row still holds (entries_one_element_per_id).
  -- Phase 1: changed rows go negative (live numbers are all positive, so negatives are free).
  update public.entries x set number = -x.number
  where x.database_id = db and not x.deleted and x.number = any (olds);

  -- Phase 2: final numbers; the old Ref ID is kept.
  with u as (
    update public.entries x
    set number = m.new_n,
        ref_id = public._ref(p, dg, m.new_n),
        previous_ref_ids = x.previous_ref_ids || to_jsonb(x.ref_id),
        updated_at = now()
    from unnest(olds, news) as m(old_n, new_n)
    where x.database_id = db and not x.deleted and x.number = -m.old_n
    returning x.id, x.number, x.ref_id, x.previous_ref_ids
  )
  select coalesce(jsonb_agg(jsonb_build_object('id', u.id, 'number', u.number, 'ref_id', u.ref_id,
                                               'previous_ref_ids', u.previous_ref_ids)
                            order by u.number, u.id), '[]'::jsonb)
  into changes
  from u;

  -- A repeated claim must return the group's current number.
  update public.temp_claims c set number = m.new_n
  from unnest(olds, news) as m(old_n, new_n)
  where c.database_id = db and c.number = m.old_n;

  update public.databases d set numbering_epoch = d.numbering_epoch + 1
  where d.id = db
  returning d.numbering_epoch into cur_epoch;

  return jsonb_build_object('epoch', cur_epoch, 'changes', changes);
end $$;

-- push_entry gains `epoch`: the numbering_epoch the device knows. The old 3-argument version is
-- removed on purpose, so an outdated app cannot upload numbers that may have changed.
-- New id: inserted if its number was claimed (temp_claims) or joins an existing Ref ID; if numbers
-- changed since the device's epoch, returns {"status": "stale"} so the device renumbers and retries.
-- Existing id: as before; an update never touches number, ref_id or previous_ref_ids.
drop function if exists public.push_entry(uuid, jsonb, int);
create or replace function public.push_entry(db uuid, e jsonb, base_version int, epoch int)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  eid       uuid := (e ->> 'id')::uuid;
  num       int  := (e ->> 'number')::int;
  cur_epoch int;
  cur       public.entries;
  dup       public.entries;
  v         int;
begin
  perform public._require(db, array['owner', 'editor']);
  -- Never runs alongside compact_ref_ids (which locks this row for update); pushes do not block each other.
  select d.numbering_epoch into cur_epoch from public.databases d where d.id = db for key share;
  select * into cur from public.entries x where x.id = eid and x.database_id = db for update;

  if not found then
    if epoch is distinct from cur_epoch then
      return jsonb_build_object('status', 'stale');
    end if;
    -- A new row's number was claimed, or it joins an existing (shared) Ref ID.
    if not exists (select 1 from public.temp_claims c where c.database_id = db and c.number = num)
       and not exists (select 1 from public.entries x where x.database_id = db and x.number = num) then
      raise exception 'Number % was not claimed', num using errcode = '22023';
    end if;
    begin
      insert into public.entries (id, database_id, number, ref_id, element_id, dentition, tooth_type, jaw, side,
                                  "values", created_by, created_at, modified_by, modified_at, version, deleted,
                                  previous_ref_ids)
      values (eid, db, num, e ->> 'ref_id', e ->> 'element_id', e ->> 'dentition', e ->> 'tooth_type',
              e ->> 'jaw', e ->> 'side', coalesce(e -> 'values', '{}'), coalesce(e ->> 'created_by', ''),
              (e ->> 'created_at')::timestamptz, coalesce(e ->> 'modified_by', ''),
              (e ->> 'modified_at')::timestamptz, 1, coalesce((e ->> 'deleted')::boolean, false),
              coalesce(e -> 'previous_ref_ids', '[]'));
    exception when unique_violation then
      -- The same tooth was added to this Ref ID from another device.
      select * into dup from public.entries x
      where x.database_id = db and x.number = num and not x.deleted and x.id <> eid
        and x.element_id is not distinct from e ->> 'element_id' and x.dentition is not distinct from e ->> 'dentition'
        and x.tooth_type is not distinct from e ->> 'tooth_type' and x.jaw is not distinct from e ->> 'jaw'
        and x.side is not distinct from e ->> 'side'
      limit 1;
      return jsonb_build_object('status', 'duplicate', 'row', to_jsonb(dup));
    end;
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

  begin
    update public.entries x
    set element_id = e ->> 'element_id', dentition = e ->> 'dentition', tooth_type = e ->> 'tooth_type',
        jaw = e ->> 'jaw', side = e ->> 'side', "values" = coalesce(e -> 'values', '{}'),
        modified_by = coalesce(e ->> 'modified_by', ''), modified_at = (e ->> 'modified_at')::timestamptz,
        deleted = coalesce((e ->> 'deleted')::boolean, false),
        version = cur.version + 1, updated_at = now()
    where x.id = eid
    returning x.version into v;
  exception when unique_violation then
    -- The edit turns this row into a tooth another row already holds under the same Ref ID.
    select * into dup from public.entries x
    where x.database_id = db and x.number = cur.number and not x.deleted and x.id <> eid
      and x.element_id is not distinct from e ->> 'element_id' and x.dentition is not distinct from e ->> 'dentition'
      and x.tooth_type is not distinct from e ->> 'tooth_type' and x.jaw is not distinct from e ->> 'jaw'
      and x.side is not distinct from e ->> 'side'
    limit 1;
    return jsonb_build_object('status', 'duplicate', 'row', to_jsonb(dup));
  end;
  return jsonb_build_object('status', 'ok', 'version', v);
end $$;

-- Only signed-in users may call the functions.
revoke execute on function public.claim_number(uuid, text, int, uuid[]), public.compact_ref_ids(uuid),
  public.push_entry(uuid, jsonb, int, int) from public, anon;
grant execute on function public.claim_number(uuid, text, int, uuid[]), public.compact_ref_ids(uuid),
  public.push_entry(uuid, jsonb, int, int) to authenticated;

-- The app expects this setup.
create or replace function public.app_schema_version() returns int
language sql immutable as $$ select 4 $$;
grant execute on function public.app_schema_version() to anon, authenticated;
