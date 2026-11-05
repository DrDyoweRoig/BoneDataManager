-- Bone Data Manager — gapless Ref IDs: offline entries get provisional (TEMP) numbers that claim a real
-- number on sync, the Owner can close gaps ("Close Ref ID gaps"), and a numbering epoch tells devices
-- that numbers changed. Safe to run after 001–003. Replaces reserved offline blocks (id_blocks).

-- ───────────────────────── Schema ─────────────────────────

alter table public.entries add column if not exists previous_ref_ids jsonb not null default '[]';
alter table public.databases add column if not exists numbering_epoch int not null default 0;

-- The numbering epoch a row was deleted in (null while live): undeleting it after a compaction gives it
-- a new number (push_entry). Rows deleted before this migration were deleted before any compaction.
do $$
begin
  if not exists (select 1 from information_schema.columns
                 where table_schema = 'public' and table_name = 'entries' and column_name = 'deleted_epoch') then
    alter table public.entries add column deleted_epoch int;
    update public.entries x set deleted_epoch = 0
    from public.databases d
    where d.id = x.database_id and x.deleted and d.numbering_epoch = 0;
  end if;
end $$;

-- Real numbers given to provisional groups. A retried claim (lost answer) gets the same number back.
-- `ids` are the group's entry ids: while none of them is uploaded, the claim keeps its number live.
create table if not exists public.temp_claims (
  database_id uuid not null references public.databases(id) on delete cascade,
  device_id   text not null,
  temp_number int  not null,
  number      int  not null,
  ids         uuid[] not null default '{}',
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
-- them already reached the server (an online create whose answer was lost) and is live, its number is
-- reused (a deleted row's number may belong to another specimen after compaction). `temp_ref` (the TEMP
-- Ref ID the user saw) is added to the previous_ref_ids of the rows already there, so no ID is lost.
drop function if exists public.claim_number(uuid, text, int, uuid[]);
create or replace function public.claim_number(db uuid, device text, temp int, ids uuid[], temp_ref text default null)
returns int language plpgsql security definer set search_path = public as $$
declare
  n    int;
  held uuid[];
begin
  perform public._require(db, array['owner', 'editor']);
  -- One claim at a time per database, and never during compact_ref_ids.
  perform 1 from public.databases d where d.id = db for no key update;

  select c.number, c.ids into n, held from public.temp_claims c
  where c.database_id = db and c.device_id = device and c.temp_number = temp;
  if found then
    -- The same key for other entries: a copied file whose TEMP group is another specimen.
    if cardinality(held) > 0 and cardinality(claim_number.ids) > 0 and not (held && claim_number.ids) then
      raise exception 'Claim key reused by a different copy' using errcode = '22023';
    end if;
    return n;
  end if;

  select x.number into n from public.entries x
  where x.database_id = db and x.id = any (claim_number.ids) and not x.deleted
  order by x.number
  limit 1;
  if not found then
    update public.databases d set next_number = d.next_number + 1
    where d.id = db
    returning d.next_number - 1 into n;
  end if;
  if temp_ref is not null then
    -- Bumps updated_at (devices pull it) but not version (no conflict with pending edits).
    update public.entries x
    set previous_ref_ids = x.previous_ref_ids || jsonb_build_array(temp_ref), updated_at = now()
    where x.database_id = db and x.id = any (claim_number.ids) and not (x.previous_ref_ids ? temp_ref);
  end if;

  insert into public.temp_claims (database_id, device_id, temp_number, number, ids)
  values (db, device, temp, n, coalesce(claim_number.ids, '{}'));
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
  lv        int[];
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

  -- Live numbers: those of live entries, plus claims none of whose entries is uploaded under the claim's
  -- own number (a claim without ids: no entry holds its number). A pending claim stays live even if a
  -- deleted row has its number, or its ids are deleted rows kept under an older number. Every claim is
  -- renumbered with the same map below, so an uploaded group's claim keeps matching its rows.
  -- A claim that is neither pending nor at a live number is dead and is deleted: a re-claim then takes
  -- a new number instead of one compaction may give to another specimen.
  with live as (
    select x.number from public.entries x where x.database_id = db and not x.deleted
    union
    select c.number from public.temp_claims c
    where c.database_id = db
      and case when cardinality(c.ids) > 0
               then not exists (select 1 from public.entries y
                                where y.database_id = db and y.id = any (c.ids) and y.number = c.number)
               else not exists (select 1 from public.entries y where y.database_id = db and y.number = c.number)
          end
  ), m as (
    select l.number as old_n, (row_number() over (order by l.number))::int as new_n from live l
  )
  select count(*)::int,
         coalesce(array_agg(m.old_n order by m.old_n), '{}'),
         coalesce(array_agg(m.old_n order by m.old_n) filter (where m.old_n <> m.new_n), '{}'),
         coalesce(array_agg(m.new_n order by m.old_n) filter (where m.old_n <> m.new_n), '{}')
  into k, lv, olds, news
  from m;

  update public.databases d set next_number = k + 1 where d.id = db;
  delete from public.temp_claims c where c.database_id = db and not (c.number = any (lv));

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

-- create_database (from 001) also uploads previous_ref_ids ("Move to cloud" of a compacted database),
-- and locks the database row before touching entries, like the other functions.
create or replace function public.create_database(def jsonb, "rows" jsonb default '[]')
returns void language plpgsql security definer set search_path = public as $$
declare
  db   uuid := (def ->> 'id')::uuid;
  mail text := lower(coalesce(auth.jwt() ->> 'email', ''));
begin
  if auth.uid() is null then
    raise exception 'Sign in required' using errcode = '42501';
  end if;
  if exists (select 1 from public.databases where id = db) then
    perform public._require(db, array['owner']);
  else
    insert into public.databases (id, name, prefix, digits, next_number, selected_elements, layers, created_by)
    values (db, def ->> 'name', coalesce(def ->> 'prefix', ''), coalesce((def ->> 'digits')::int, 4),
            coalesce((def ->> 'next_number')::int, 1), coalesce(def -> 'selected_elements', '[]'),
            coalesce(def -> 'layers', '[]'), auth.uid());
    insert into public.members (database_id, email, user_id, role) values (db, mail, auth.uid(), 'owner');
  end if;
  perform 1 from public.databases d where d.id = db for no key update;

  insert into public.entries (id, database_id, number, ref_id, element_id, dentition, tooth_type, jaw, side,
                              "values", created_by, created_at, modified_by, modified_at, version, deleted,
                              previous_ref_ids, deleted_epoch)
  select r.id, db, r.number, r.ref_id, r.element_id, r.dentition, r.tooth_type, r.jaw, r.side,
         coalesce(r."values", '{}'), coalesce(r.created_by, ''), r.created_at, coalesce(r.modified_by, ''),
         r.modified_at, coalesce(r.version, 1), coalesce(r.deleted, false), coalesce(r.previous_ref_ids, '[]'),
         case when coalesce(r.deleted, false)
              then (select d.numbering_epoch from public.databases d where d.id = db) end
  from jsonb_to_recordset("rows") as r(id uuid, number int, ref_id text, element_id text, dentition text,
       tooth_type text, jaw text, side text, "values" jsonb, created_by text, created_at timestamptz,
       modified_by text, modified_at timestamptz, version int, deleted boolean, previous_ref_ids jsonb)
  on conflict (id) do update
    set number = excluded.number, ref_id = excluded.ref_id, element_id = excluded.element_id,
        dentition = excluded.dentition, tooth_type = excluded.tooth_type, jaw = excluded.jaw,
        side = excluded.side, "values" = excluded."values", modified_by = excluded.modified_by,
        modified_at = excluded.modified_at, version = excluded.version, deleted = excluded.deleted,
        previous_ref_ids = excluded.previous_ref_ids, updated_at = now(),
        deleted_epoch = case when not excluded.deleted then null
                             when public.entries.deleted then public.entries.deleted_epoch
                             else excluded.deleted_epoch end
    where public.entries.database_id = db;

  update public.databases
  set next_number = greatest(next_number,
        coalesce((select max(number) + 1 from public.entries where database_id = db), 1))
  where id = db;
end $$;

-- push_entry gains `epoch`: the numbering_epoch the device knows. The old 3-argument version is
-- removed on purpose, so an outdated app cannot upload numbers that may have changed.
-- New id: inserted if its number was claimed (temp_claims) or joins a live Ref ID; if numbers
-- changed since the device's epoch, returns {"status": "stale"} so the device renumbers and retries.
-- Existing id: as before; an update never touches number, ref_id or previous_ref_ids, except an undelete
-- after a compaction (deleted_epoch is older): its old number may be another specimen's now, so it takes
-- a new one from next_number and keeps the old Ref ID in previous_ref_ids.
drop function if exists public.push_entry(uuid, jsonb, int);
create or replace function public.push_entry(db uuid, e jsonb, base_version int, epoch int)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  eid       uuid    := (e ->> 'id')::uuid;
  num       int     := (e ->> 'number')::int;
  gone      boolean := coalesce((e ->> 'deleted')::boolean, false);
  p         text;
  dg        int;
  cur_epoch int;
  cur       public.entries;
  dup       public.entries;
  v         int;
  new_num   int;
  new_ref   text;
  new_prev  jsonb;
begin
  perform public._require(db, array['owner', 'editor']);
  -- Never runs alongside compact_ref_ids (which locks this row for update); pushes do not block each other.
  select d.numbering_epoch, d.prefix, d.digits into cur_epoch, p, dg
  from public.databases d where d.id = db for key share;
  -- An undelete may take a new number below: lock the counter before the entry row, like claim_number.
  if not gone and exists (select 1 from public.entries x where x.id = eid and x.database_id = db and x.deleted) then
    perform 1 from public.databases d where d.id = db for no key update;
  end if;
  select * into cur from public.entries x where x.id = eid and x.database_id = db for update;

  if not found then
    if epoch is distinct from cur_epoch then
      return jsonb_build_object('status', 'stale');
    end if;
    -- A new row's number was claimed, or it joins an existing (shared) Ref ID that is still live: a
    -- number held only by deleted rows may be reused by compaction for another specimen.
    if not exists (select 1 from public.temp_claims c where c.database_id = db and c.number = num)
       and not exists (select 1 from public.entries x where x.database_id = db and x.number = num
                       and not x.deleted) then
      raise exception 'Number % was not claimed', num using errcode = '22023';
    end if;
    begin
      insert into public.entries (id, database_id, number, ref_id, element_id, dentition, tooth_type, jaw, side,
                                  "values", created_by, created_at, modified_by, modified_at, version, deleted,
                                  previous_ref_ids, deleted_epoch)
      values (eid, db, num, e ->> 'ref_id', e ->> 'element_id', e ->> 'dentition', e ->> 'tooth_type',
              e ->> 'jaw', e ->> 'side', coalesce(e -> 'values', '{}'), coalesce(e ->> 'created_by', ''),
              (e ->> 'created_at')::timestamptz, coalesce(e ->> 'modified_by', ''),
              (e ->> 'modified_at')::timestamptz, 1, gone,
              case when jsonb_typeof(e -> 'previous_ref_ids') = 'array' then e -> 'previous_ref_ids'
                   else '[]'::jsonb end,
              case when gone then cur_epoch end);
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
       and cur.deleted = gone then
      return jsonb_build_object('status', 'ok', 'version', cur.version);
    end if;
    return jsonb_build_object('status', 'conflict', 'row', to_jsonb(cur));
  end if;

  begin
    new_num := cur.number;
    new_ref := cur.ref_id;
    new_prev := cur.previous_ref_ids;
    if cur.deleted and not gone and cur.deleted_epoch is distinct from cur_epoch then
      -- Undeleted after a compaction: a number nobody holds (taken inside this block, so a failed
      -- update does not spend it); the old Ref ID is kept.
      update public.databases d set next_number = d.next_number + 1
      where d.id = db
      returning d.next_number - 1 into new_num;
      new_ref := public._ref(p, dg, new_num);
      new_prev := cur.previous_ref_ids || to_jsonb(cur.ref_id);
    end if;
    update public.entries x
    set element_id = e ->> 'element_id', dentition = e ->> 'dentition', tooth_type = e ->> 'tooth_type',
        jaw = e ->> 'jaw', side = e ->> 'side', "values" = coalesce(e -> 'values', '{}'),
        modified_by = coalesce(e ->> 'modified_by', ''), modified_at = (e ->> 'modified_at')::timestamptz,
        deleted = gone,
        number = new_num, ref_id = new_ref, previous_ref_ids = new_prev,
        deleted_epoch = case when not gone then null
                             when cur.deleted then cur.deleted_epoch
                             else cur_epoch end,
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
revoke execute on function public.claim_number(uuid, text, int, uuid[], text), public.compact_ref_ids(uuid),
  public.push_entry(uuid, jsonb, int, int) from public, anon;
grant execute on function public.claim_number(uuid, text, int, uuid[], text), public.compact_ref_ids(uuid),
  public.push_entry(uuid, jsonb, int, int) to authenticated;

-- The app expects this setup.
create or replace function public.app_schema_version() returns int
language sql immutable as $$ select 4 $$;
grant execute on function public.app_schema_version() to anon, authenticated;
