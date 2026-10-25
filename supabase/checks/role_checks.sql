-- Bone Data Manager — permission checks (Plan 2, Task 1)
-- 1. Create two users in Authentication → Users → Add user (any emails you own).
-- 2. Put their emails in the two lines marked EDIT below.
-- 3. Run in SQL Editor. The result table should show only PASS rows.
-- The check database it creates is deleted at the end.

create temp table if not exists check_results (n serial, result text);
truncate check_results;

do $$
declare
  owner_email    text := 'owner-test@example.com';   -- EDIT
  viewer_email   text := 'viewer-test@example.com';  -- EDIT
  outsider_email text := 'nobody-' || gen_random_uuid() || '@example.com';
  o   uuid;
  v   uuid;
  db  uuid := gen_random_uuid();
  n   int;
  log text[] := '{}';
begin
  select id into o from auth.users where email = owner_email;
  select id into v from auth.users where email = viewer_email;
  if o is null or v is null then
    raise exception 'Create both test users first and put their emails in this script';
  end if;

  -- Owner
  perform set_config('request.jwt.claims',
    json_build_object('sub', o, 'email', owner_email, 'role', 'authenticated')::text, true);
  set local role authenticated;
  perform public.create_database(jsonb_build_object('id', db, 'name', 'Permission check', 'prefix', 'T-'), '[]');
  insert into public.members (database_id, email, role) values (db, lower(viewer_email), 'viewer');
  perform public.create_entries(db, '[{"element_id":"femur","side":"left"}]', 'OWN');
  select count(*) into n from public.entries where database_id = db;
  log := log || case when n = 1 then 'PASS owner creates database, adds a member and an entry'
                     else 'FAIL owner entry count ' || n end;
  reset role;

  -- Viewer
  perform set_config('request.jwt.claims',
    json_build_object('sub', v, 'email', viewer_email, 'role', 'authenticated')::text, true);
  set local role authenticated;
  select count(*) into n from public.entries where database_id = db;
  log := log || case when n = 1 then 'PASS viewer can read entries' else 'FAIL viewer read ' || n end;
  begin
    perform public.create_entries(db, '[{"element_id":"femur"}]', 'V');
    log := log || 'FAIL viewer could create an entry'::text;
  exception when insufficient_privilege then
    log := log || 'PASS viewer cannot create entries'::text;
  end;
  begin
    insert into public.members (database_id, email, role) values (db, 'someone@example.com', 'editor');
    log := log || 'FAIL viewer could add a member'::text;
  exception when insufficient_privilege then
    log := log || 'PASS viewer cannot add members'::text;
  end;
  begin
    update public.entries set deleted = true where database_id = db;
    get diagnostics n = row_count;
    log := log || case when n = 0 then 'PASS viewer cannot edit entries directly'
                       else 'FAIL viewer edited ' || n || ' entries' end;
  end;
  reset role;

  -- Not a member
  perform set_config('request.jwt.claims',
    json_build_object('sub', gen_random_uuid(), 'email', outsider_email, 'role', 'authenticated')::text, true);
  set local role authenticated;
  select count(*) into n from public.databases where id = db;
  log := log || case when n = 0 then 'PASS non-member sees nothing' else 'FAIL non-member sees the database' end;
  begin
    perform public.reserve_block(db, 'pc', 10);
    log := log || 'FAIL non-member could reserve numbers'::text;
  exception when insufficient_privilege then
    log := log || 'PASS non-member cannot reserve numbers'::text;
  end;
  reset role;

  delete from public.databases where id = db;
  insert into check_results (result) select unnest(log);
end $$;

select result from check_results order by n;
