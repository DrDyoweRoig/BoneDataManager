-- Bone Data Manager — cloud schema (Plan 2, Task 1)
-- Paste into Supabase → SQL Editor → Run. Safe to run once on an empty project.

-- ───────────────────────── Tables ─────────────────────────

create table public.databases (
  id                uuid primary key,
  name              text not null,
  prefix            text not null default '',
  digits            int  not null default 4 check (digits between 1 and 9),
  next_number       int  not null default 1,
  selected_elements jsonb not null default '[]',
  layers            jsonb not null default '[]',
  created_by        uuid default auth.uid(),
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now()
);

create table public.members (
  database_id uuid not null references public.databases(id) on delete cascade,
  email       text not null check (email = lower(email)),
  user_id     uuid,
  role        text not null check (role in ('owner', 'editor', 'viewer')),
  primary key (database_id, email)
);

create table public.entries (
  id          uuid primary key,
  database_id uuid not null references public.databases(id) on delete cascade,
  number      int  not null,
  ref_id      text not null,
  element_id  text not null,
  dentition   text,
  tooth_type  text,
  jaw         text,
  side        text,
  "values"    jsonb not null default '{}',
  created_by  text not null default '',
  created_at  timestamptz not null default now(),
  modified_by text not null default '',
  modified_at timestamptz not null default now(),
  version     int  not null default 1,
  deleted     boolean not null default false,
  updated_at  timestamptz not null default now(),
  unique (database_id, number),
  unique (database_id, ref_id)
);
create index entries_database_updated on public.entries (database_id, updated_at);

-- Numbers handed to a computer for offline work.
create table public.id_blocks (
  database_id  uuid not null references public.databases(id) on delete cascade,
  device_id    text not null,
  start_number int  not null,
  end_number   int  not null,
  primary key (database_id, device_id, start_number)
);

-- ───────────────────────── Helpers ─────────────────────────

-- The caller's role in a database (matched by user id or, for invitations, by email).
create or replace function public.my_role(db uuid) returns text
language sql stable security definer set search_path = public as $$
  select role from public.members
  where database_id = db
    and (user_id = auth.uid() or email = lower(coalesce(auth.jwt() ->> 'email', '')))
  order by case role when 'owner' then 0 when 'editor' then 1 else 2 end
  limit 1
$$;

create or replace function public._require(db uuid, allowed text[]) returns text
language plpgsql stable security definer set search_path = public as $$
declare r text := public.my_role(db);
begin
  if r is null or not (r = any (allowed)) then
    raise exception 'You do not have permission for this database' using errcode = '42501';
  end if;
  return r;
end $$;

-- 'MAS-' + 4 + 7 → 'MAS-0007'; numbers wider than digits are kept whole.
create or replace function public._ref(prefix text, digits int, n int) returns text
language sql immutable as $$
  select prefix || case when length(n::text) >= digits then n::text else lpad(n::text, digits, '0') end
$$;

-- A database must always keep at least one owner.
create or replace function public._keep_an_owner() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if exists (select 1 from public.databases where id = old.database_id)
     and not exists (select 1 from public.members where database_id = old.database_id and role = 'owner') then
    raise exception 'A database needs at least one owner' using errcode = '23514';
  end if;
  return null;
end $$;
create trigger members_keep_an_owner after update or delete on public.members
  for each row execute function public._keep_an_owner();

-- ───────────────────────── Row Level Security ─────────────────────────

alter table public.databases enable row level security;
alter table public.members   enable row level security;
alter table public.entries   enable row level security;
alter table public.id_blocks enable row level security;

create policy databases_read on public.databases for select to authenticated
  using (public.my_role(id) is not null);

create policy members_read on public.members for select to authenticated
  using (public.my_role(database_id) is not null);
create policy members_insert on public.members for insert to authenticated
  with check (public.my_role(database_id) = 'owner');
create policy members_update on public.members for update to authenticated
  using (public.my_role(database_id) = 'owner') with check (public.my_role(database_id) = 'owner');
create policy members_delete on public.members for delete to authenticated
  using (public.my_role(database_id) = 'owner');

create policy entries_read on public.entries for select to authenticated
  using (public.my_role(database_id) is not null);

-- databases, entries and id_blocks are written only through the functions below.

-- ───────────────────────── Functions (RPC) ─────────────────────────

-- New cloud database (wizard) or upload of a local one (Move to cloud). Idempotent for its owner.
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

  insert into public.entries (id, database_id, number, ref_id, element_id, dentition, tooth_type, jaw, side,
                              "values", created_by, created_at, modified_by, modified_at, version, deleted)
  select r.id, db, r.number, r.ref_id, r.element_id, r.dentition, r.tooth_type, r.jaw, r.side,
         coalesce(r."values", '{}'), coalesce(r.created_by, ''), r.created_at, coalesce(r.modified_by, ''),
         r.modified_at, coalesce(r.version, 1), coalesce(r.deleted, false)
  from jsonb_to_recordset("rows") as r(id uuid, number int, ref_id text, element_id text, dentition text,
       tooth_type text, jaw text, side text, "values" jsonb, created_by text, created_at timestamptz,
       modified_by text, modified_at timestamptz, version int, deleted boolean)
  on conflict (id) do nothing;

  update public.databases
  set next_number = greatest(next_number,
        coalesce((select max(number) + 1 from public.entries where database_id = db), 1))
  where id = db;
end $$;

-- Structure edits (owner). Never touches the counter.
create or replace function public.update_definition(db uuid, def jsonb)
returns void language plpgsql security definer set search_path = public as $$
begin
  perform public._require(db, array['owner']);
  update public.databases
  set name = def ->> 'name',
      prefix = coalesce(def ->> 'prefix', ''),
      digits = coalesce((def ->> 'digits')::int, 4),
      selected_elements = coalesce(def -> 'selected_elements', '[]'),
      layers = coalesce(def -> 'layers', '[]'),
      updated_at = now()
  where id = db;
end $$;

-- Online entry creation: the server hands out consecutive numbers atomically.
create or replace function public.create_entries(db uuid, drafts jsonb, observer text)
returns setof public.entries language plpgsql security definer set search_path = public as $$
declare
  n     int := jsonb_array_length(drafts);
  start_n int;
  p     text;
  dg    int;
begin
  perform public._require(db, array['owner', 'editor']);
  update public.databases set next_number = next_number + n
  where id = db
  returning next_number - n, prefix, digits into start_n, p, dg;

  return query
  insert into public.entries (id, database_id, number, ref_id, element_id, dentition, tooth_type, jaw, side,
                              "values", created_by, created_at, modified_by, modified_at, version, deleted)
  select gen_random_uuid(), db, start_n + (d.ord - 1)::int, public._ref(p, dg, start_n + (d.ord - 1)::int),
         d.v ->> 'element_id', d.v ->> 'dentition', d.v ->> 'tooth_type', d.v ->> 'jaw', d.v ->> 'side',
         coalesce(d.v -> 'values', '{}'), observer, now(), observer, now(), 1, false
  from jsonb_array_elements(drafts) with ordinality as d(v, ord)
  returning *;
end $$;

-- Offline numbers: takes `size` numbers from the counter for one computer.
create or replace function public.reserve_block(db uuid, device text, size int)
returns table (block_start int, block_end int)
language plpgsql security definer set search_path = public as $$
declare s int;
begin
  perform public._require(db, array['owner', 'editor']);
  update public.databases set next_number = next_number + size
  where id = db
  returning next_number - size into s;
  insert into public.id_blocks (database_id, device_id, start_number, end_number)
  values (db, device, s, s + size - 1);
  block_start := s;
  block_end := s + size - 1;
  return next;
end $$;

-- Upload one entry created or changed on a computer.
-- New id: inserted (its number must come from a reserved block).
-- Existing id: updated only if nobody changed it since `base_version`; otherwise returns the server row.
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
    if not exists (select 1 from public.id_blocks b
                   where b.database_id = db and num between b.start_number and b.end_number) then
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

  if cur.version <> base_version then
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

-- Only signed-in users may call the functions.
revoke execute on function public.create_database(jsonb, jsonb), public.update_definition(uuid, jsonb),
  public.create_entries(uuid, jsonb, text), public.reserve_block(uuid, text, int),
  public.push_entry(uuid, jsonb, int), public.my_role(uuid) from public, anon;
grant execute on function public.create_database(jsonb, jsonb), public.update_definition(uuid, jsonb),
  public.create_entries(uuid, jsonb, text), public.reserve_block(uuid, text, int),
  public.push_entry(uuid, jsonb, int), public.my_role(uuid) to authenticated;
revoke execute on function public._require(uuid, text[]), public._ref(text, int, int) from public, anon;

-- ───────────────────────── Realtime ─────────────────────────

alter publication supabase_realtime add table public.entries, public.databases;
