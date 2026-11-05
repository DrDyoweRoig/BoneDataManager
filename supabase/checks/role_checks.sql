-- Bone Data Manager — permission checks (Plan 2, Task 1)
-- 1. Create two users in Authentication → Users → Add user (any emails you own).
-- 2. Put their emails in the two lines marked EDIT below.
-- 3. Run in SQL Editor. The result table should show only PASS rows.
-- The editor is a member by email only; it needs no user account.
-- The check database it creates is deleted at the end.

create temp table if not exists check_results (n serial, result text);
truncate check_results;

do $$
declare
  owner_email    text := 'owner-test@example.com';   -- EDIT
  viewer_email   text := 'viewer-test@example.com';  -- EDIT
  outsider_email text := 'nobody-' || gen_random_uuid() || '@example.com';
  editor_email   text := 'editor-' || gen_random_uuid() || '@example.com';
  o   uuid;
  v   uuid;
  db  uuid := gen_random_uuid();
  n   int;
  n2  int;
  id1 uuid;
  r   jsonb;
  nums int[];
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
  insert into public.members (database_id, email, role) values (db, editor_email, 'editor');

  -- Claims: a retry gets the same number; an id already on the server gives that row's number.
  n := public.claim_number(db, 'pc', 1, '{}');
  n2 := public.claim_number(db, 'pc', 1, '{}');
  log := log || case when n = 2 and n2 = 2 then 'PASS a repeated claim returns the same number'
                     else 'FAIL claims returned ' || n || ' and ' || n2 end;
  select id into id1 from public.entries where database_id = db and number = 1;
  n := public.claim_number(db, 'pc', 2, array[id1]);
  log := log || case when n = 1 then 'PASS a claim for an uploaded entry returns its number'
                     else 'FAIL claim for an uploaded entry returned ' || n end;
  r := public.push_entry(db, jsonb_build_object('id', gen_random_uuid(), 'number', 2, 'ref_id', 'T-0002',
         'element_id', 'tibia', 'created_at', now(), 'modified_at', now()), 0, 0);
  log := log || case when r ->> 'status' = 'ok' then 'PASS a new entry with a claimed number is uploaded'
                     else 'FAIL push with a claimed number: ' || r::text end;
  reset role;

  -- Numbers 1, 2, 57, 58: the counter is moved by hand to make a gap.
  update public.databases set next_number = 57 where id = db;
  set local role authenticated;
  perform public.create_entries(db, '[{"element_id":"femur","side":"right"},{"element_id":"ulna"}]', 'OWN');
  r := public.compact_ref_ids(db);
  select array_agg(distinct number order by number) into nums from public.entries
  where database_id = db and not deleted;
  log := log || case when nums = '{1,2,3,4}' and (r ->> 'epoch')::int = 1
                          and jsonb_array_length(r -> 'changes') = 2
                     then 'PASS compaction turns 1, 2, 57, 58 into 1, 2, 3, 4'
                     else 'FAIL compaction: ' || coalesce(nums::text, 'none') || ' ' || r::text end;
  select count(*) into n from public.entries
  where database_id = db and number = 3 and ref_id = 'T-0003' and previous_ref_ids = '["T-0057"]';
  log := log || case when n = 1 then 'PASS a compacted entry keeps its old Ref ID in Previous Ref IDs'
                     else 'FAIL previous Ref ID not kept' end;
  select next_number into n from public.databases where id = db;
  log := log || case when n = 5 then 'PASS compaction resets the counter' else 'FAIL counter is ' || n end;
  r := public.compact_ref_ids(db);
  log := log || case when (r ->> 'epoch')::int = 1 and jsonb_array_length(r -> 'changes') = 0
                     then 'PASS compaction without gaps changes nothing'
                     else 'FAIL second compaction: ' || r::text end;

  -- Pushes after compaction: an old epoch is stale; an unclaimed number is refused.
  r := public.push_entry(db, jsonb_build_object('id', gen_random_uuid(), 'number', 3, 'ref_id', 'T-0057',
         'element_id', 'radius', 'created_at', now(), 'modified_at', now()), 0, 0);
  log := log || case when r ->> 'status' = 'stale' then 'PASS a new entry with an old epoch is stale'
                     else 'FAIL push with an old epoch: ' || r::text end;
  begin
    perform public.push_entry(db, jsonb_build_object('id', gen_random_uuid(), 'number', 99, 'ref_id', 'T-0099',
              'element_id', 'radius', 'created_at', now(), 'modified_at', now()), 0, 1);
    log := log || 'FAIL a new entry with an unclaimed number was uploaded'::text;
  exception when invalid_parameter_value then
    log := log || 'PASS a new entry with an unclaimed number is refused'::text;
  end;
  reset role;

  -- Editor
  perform set_config('request.jwt.claims',
    json_build_object('sub', gen_random_uuid(), 'email', editor_email, 'role', 'authenticated')::text, true);
  set local role authenticated;
  begin
    perform public.compact_ref_ids(db);
    log := log || 'FAIL editor could close Ref ID gaps'::text;
  exception when insufficient_privilege then
    log := log || 'PASS editor cannot close Ref ID gaps'::text;
  end;
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
  begin
    perform public.claim_number(db, 'viewer-pc', 1, '{}');
    log := log || 'FAIL viewer could claim a number'::text;
  exception when insufficient_privilege then
    log := log || 'PASS viewer cannot claim numbers'::text;
  end;
  begin
    perform public.compact_ref_ids(db);
    log := log || 'FAIL viewer could close Ref ID gaps'::text;
  exception when insufficient_privilege then
    log := log || 'PASS viewer cannot close Ref ID gaps'::text;
  end;
  reset role;

  -- Not a member
  perform set_config('request.jwt.claims',
    json_build_object('sub', gen_random_uuid(), 'email', outsider_email, 'role', 'authenticated')::text, true);
  set local role authenticated;
  select count(*) into n from public.databases where id = db;
  log := log || case when n = 0 then 'PASS non-member sees nothing' else 'FAIL non-member sees the database' end;
  begin
    perform public.claim_number(db, 'pc', 1, '{}');
    log := log || 'FAIL non-member could claim a number'::text;
  exception when insufficient_privilege then
    log := log || 'PASS non-member cannot claim numbers'::text;
  end;
  reset role;

  delete from public.databases where id = db;
  insert into check_results (result) select unnest(log);
end $$;

select result from check_results order by n;
