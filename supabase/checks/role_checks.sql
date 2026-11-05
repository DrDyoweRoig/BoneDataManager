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
  -- The same claim key for other entries (a copied file's TEMP group) is refused.
  begin
    perform public.claim_number(db, 'pc', 2, array[gen_random_uuid()]);
    log := log || 'FAIL a claim key reused for other entries returned a number'::text;
  exception when invalid_parameter_value then
    log := log || 'PASS a claim key reused for other entries is refused'::text;
  end;
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

  -- A number held only by a deleted row (never claimed) is not a Ref ID a new row can join.
  reset role;
  insert into public.entries (id, database_id, number, ref_id, element_id, deleted)
  values (gen_random_uuid(), db, 500, 'T-0500', 'rib', true);
  set local role authenticated;
  begin
    perform public.push_entry(db, jsonb_build_object('id', gen_random_uuid(), 'number', 500, 'ref_id', 'T-0500',
              'element_id', 'radius', 'created_at', now(), 'modified_at', now()), 0, 1);
    log := log || 'FAIL a new entry joined a number held only by a deleted row'::text;
  exception when invalid_parameter_value then
    log := log || 'PASS a new entry cannot join a number held only by a deleted row'::text;
  end;
  reset role;
  delete from public.entries where database_id = db and number = 500;
  set local role authenticated;

  -- A claim for an uploaded entry adds the TEMP Ref ID to it once, without a new version.
  select id into id1 from public.entries where database_id = db and number = 1;
  n := public.claim_number(db, 'pc', 3, array[id1], 'T-TEMP-3');
  n2 := public.claim_number(db, 'pc-other', 3, array[id1], 'T-TEMP-3');
  select count(*) into n2 from public.entries
  where id = id1 and previous_ref_ids = '["T-TEMP-3"]' and version = 1;
  log := log || case when n = 1 and n2 = 1 then 'PASS a claim keeps the TEMP Ref ID on an uploaded entry'
                     else 'FAIL TEMP Ref ID on an uploaded entry: number ' || n || ', rows ' || n2 end;

  -- A claim whose only uploaded entry is deleted takes a new number (the old one may be reused).
  reset role;
  insert into public.entries (id, database_id, number, ref_id, element_id, deleted)
  values (gen_random_uuid(), db, 600, 'T-0600', 'rib', true) returning id into id1;
  set local role authenticated;
  select next_number into n2 from public.databases where id = db;
  n := public.claim_number(db, 'pc', 4, array[id1], 'T-TEMP-4');
  log := log || case when n = n2 then 'PASS a claim does not reuse the number of a deleted entry'
                     else 'FAIL claim for a deleted entry returned ' || n || ' (next was ' || n2 || ')' end;
  -- Its entries are not uploaded under that number, so compaction keeps the claim's number live.
  r := public.compact_ref_ids(db);
  select c.number into n from public.temp_claims c where c.database_id = db and c.device_id = 'pc' and c.temp_number = 4;
  log := log || case when (select d.next_number from public.databases d where d.id = db) > n
                     then 'PASS a claim whose uploaded entries are deleted stays live in a compaction'
                     else 'FAIL compaction dropped a claim whose entries are deleted' end;
  reset role;
  delete from public.entries where database_id = db and number = 600;
  update public.databases set next_number = n2 where id = db; -- keep the numbers the next checks expect
  delete from public.temp_claims where database_id = db and device_id = 'pc' and temp_number = 4;
  set local role authenticated;

  -- A claim whose uploaded entry was deleted (no live row at its number, not pending) is dead:
  -- compaction deletes it, so a re-claim takes a new number.
  reset role;
  select next_number into n2 from public.databases where id = db;
  insert into public.entries (id, database_id, number, ref_id, element_id, deleted)
  values (gen_random_uuid(), db, n2, public._ref('T-', 4, n2), 'rib', true) returning id into id1;
  insert into public.temp_claims (database_id, device_id, temp_number, number, ids)
  values (db, 'pc', 5, n2, array[id1, gen_random_uuid()]);
  update public.databases set next_number = n2 + 1 where id = db;
  set local role authenticated;
  r := public.compact_ref_ids(db);
  select count(*) into n from public.temp_claims c where c.database_id = db and c.device_id = 'pc' and c.temp_number = 5;
  log := log || case when n = 0 then 'PASS compaction deletes a claim whose entries are gone from its number'
                     else 'FAIL a dead claim survived compaction' end;
  reset role;
  delete from public.entries where id = id1;
  delete from public.temp_claims where database_id = db and device_id = 'pc' and temp_number = 5;
  update public.databases set next_number = n2 where id = db;
  set local role authenticated;

  -- Numbers 1..10; #3 and #10 deleted; compaction gives 1..8, then offline claims get 9 and 10.
  perform public.create_entries(db, '[{"element_id":"rib"},{"element_id":"rib"},{"element_id":"rib"},
    {"element_id":"rib"},{"element_id":"rib"},{"element_id":"rib"}]', 'OWN');
  reset role;
  update public.entries set deleted = true where database_id = db and number in (3, 10);
  set local role authenticated;
  r := public.compact_ref_ids(db);
  n := public.claim_number(db, 'pc2', 1, array[gen_random_uuid()]);
  n2 := public.claim_number(db, 'pc2', 2, array[gen_random_uuid()]);
  log := log || case when n = 9 and n2 = 10 then 'PASS offline claims after compaction get consecutive numbers'
                     else 'FAIL claims after compaction got ' || n || ' and ' || n2 end;
  -- The claim for 10 shares its number with the deleted row but is not uploaded yet: it stays live.
  reset role;
  update public.entries set deleted = true where database_id = db and number = 8;
  set local role authenticated;
  r := public.compact_ref_ids(db);
  select array_agg(number order by number) into nums from public.temp_claims
  where database_id = db and device_id = 'pc2';
  select next_number into n from public.databases where id = db;
  log := log || case when nums = '{8,9}' and n = 10
                     then 'PASS a claim not yet uploaded is renumbered with the live numbers'
                     else 'FAIL pending claims: ' || coalesce(nums::text, 'none') || ', counter ' || n end;
  reset role;

  log := log || case when to_regprocedure('public.reserve_block(uuid,text,int)') is null
                          and to_regclass('public.id_blocks') is null
                     then 'PASS reserved blocks are gone' else 'FAIL reserve_block or id_blocks still exists' end;

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
  n := public.claim_number(db, 'editor-pc', 1, '{}');
  log := log || case when n > 0 then 'PASS editor can claim a number' else 'FAIL editor claim returned ' || n end;
  reset role;

  -- Viewer
  perform set_config('request.jwt.claims',
    json_build_object('sub', v, 'email', viewer_email, 'role', 'authenticated')::text, true);
  set local role authenticated;
  select count(*) into n from public.entries where database_id = db and id = id1;
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
