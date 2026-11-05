# Gapless Ref IDs Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ref IDs stay consecutive: offline entries get provisional `HOL-TEMP-n` IDs that become real numbers on sync, and an owner-only "Close Ref ID gaps" button renumbers existing entries, keeping every old ID in a new Previous Ref IDs field.

**Architecture:** Reserved number blocks are removed. Offline rows are stored locally with negative numbers; on sync the engine calls a new `claim_number` RPC per provisional group, renumbers the group locally, then pushes as before. A new `compact_ref_ids` RPC (or a local equivalent for non-cloud databases) renumbers live rows in order and bumps `databases.numbering_epoch`; `push_entry` now takes the client's epoch so stale clients (and old app versions, through the changed signature) cannot upload outdated numbers.

**Tech Stack:** Flutter/Dart, drift (SQLite), Supabase (Postgres plpgsql RPCs), syncfusion xlsio, flutter_test.

**Spec:** `docs/superpowers/specs/2026-11-05-gapless-ref-ids-design.md`

## Global Constraints

- App UI text in English. Spec, plan and chat in Catalan/English as here.
- Provisional Ref ID: `provisionalRefId(prefix, n)` = `'$prefix-TEMP-$n'` when `prefix` ends in a letter or digit, `'${prefix}TEMP-$n'` otherwise (`'MAS-'` → `MAS-TEMP-1`), and `'TEMP-$n'` for an empty prefix.
- Provisional rows have `number < 0` (`-n` for `TEMP-n`). Positive numbers are always real.
- Previous Ref IDs: ordered list, oldest first; never shrinks; joined with `'; '` in Excel.
- Renumbering (claim or compaction) never changes `version`; it only changes `number`, `ref_id`, `previous_ref_ids` (+ `updated_at` on the server).
- Deleted rows are never renumbered.
- Server schema version becomes **4** (`app_schema_version()` and `kSchemaVersion`); local drift `schemaVersion` becomes **4**.
- `supabase/migrations/004_gapless_ref_ids.sql` must be appended verbatim to `app/assets/supabase_setup.sql`.
- Run tests from `app/`: `flutter test`.

## Review Focus

1. **Pull after another device compacted.** Pulled rows arrive renumbered one by one; applying them one at a time through `applyRemote` could hit `_clashes` and wrongly mark live rows deleted. Expected: numbers refresh as a whole before the batch is applied, no row is deleted. → test in Task 6.
2. **Lost response on the online create, then offline fallback.** The server already has the rows; the provisional copy must claim the *same* number, not a new one (no gap). → test in Task 6.
3. **Pending local edit on a row another device renumbered.** Expected: number/ref_id update, the local edit stays pending and uploads, no conflict dialog. → test in Task 6.
4. **Provisional group extended offline with "Add teeth to HOL-TEMP-2"** then synced: all rows end up with one real number. → test in Task 3 (local) and Task 6 (sync).
5. **Upgrade of a PC that has unsynced rows from an old block.** Expected: they become TEMP, keep their block ID in Previous Ref IDs, group rows share one TEMP. → test in Task 2.

---

### Task 1: Ref ID helpers, Previous Ref IDs on entries, Excel column

**Files:**
- Modify: `app/lib/ids/ref_id.dart`, `app/lib/entries/entry.dart`, `app/lib/entries/entry_json.dart`, `app/lib/export/excel_export.dart`
- Test: `app/test/ids/ref_id_test.dart`, `app/test/entries/entry_test.dart`, `app/test/export/excel_export_test.dart`

**Interfaces:**
- Produces (`ids/ref_id.dart`):
  - `String provisionalRefId(String prefix, int n)` (see Global Constraints)
  - `bool isProvisional(int number)` → `number < 0`
  - `Map<int, int> compactionMap(Iterable<int> liveNumbers)` — distinct positive numbers sorted ascending mapped to 1..k; only entries whose number changes are included. Negative numbers ignored.
- Produces (`entries/entry.dart`):
  - `Entry.previousRefIds` (`List<String>`, default `const []`)
  - `typedef NumberChange = ({String id, int number, String refId, List<String> previousRefIds});`
- Produces (`entry_json.dart`): key `'previous_ref_ids'` (JSON list) in `entryToJson`/`entryFromJson`, missing → `[]`.

- [ ] **Step 1: Write failing tests**

```dart
// ref_id_test.dart
expect(provisionalRefId('HOL', 3), 'HOL-TEMP-3');
expect(provisionalRefId('MAS-', 1), 'MAS-TEMP-1');
expect(provisionalRefId('', 2), 'TEMP-2');
expect(isProvisional(-1), isTrue);
expect(isProvisional(1), isFalse);
expect(compactionMap([1, 2, 3, 4, 5, 6, 57, 57, 58, 59]), {57: 7, 58: 8, 59: 9});
expect(compactionMap([1, 3, -2, 4]), {3: 2, 4: 3});
expect(compactionMap([1, 2, 3]), isEmpty);

// entry_test.dart
test('previous_ref_ids round-trips and defaults to empty', ...)
// entryFromJson(entryToJson(e with ['HOL-TEMP-1','HOL0057'])).previousRefIds == ['HOL-TEMP-1','HOL0057']
// entryFromJson(json without the key).previousRefIds == []

// excel_export_test.dart
test('Previous Ref IDs column follows Ref ID', ...)
// header[1] == 'Previous Ref IDs'; cell for an entry with ['HOL-TEMP-1','HOL0057'] == 'HOL-TEMP-1; HOL0057';
// column present (empty cells) when no entry has previous IDs
```

- [ ] **Step 2:** `flutter test test/ids test/entries test/export/excel_export_test.dart` → FAIL (undefined names / header mismatch).
- [ ] **Step 3:** Implement. Excel: insert `'Previous Ref IDs'` right after `'Ref ID'` in the header and `e.previousRefIds.join('; ')` in each row. Fix any test helper that builds `Entry` positionally (none expected — all named).
- [ ] **Step 4:** Same command → PASS. Then `flutter test` (whole suite; `live_excel_test` may need its expected header updated — update it to include the new column).
- [ ] **Step 5: Commit** `feat: Previous Ref IDs field, provisional Ref ID helpers`

---

### Task 2: Local schema v4 and upgrade of old blocks

**Files:**
- Modify: `app/lib/data/local_db.dart` (+ regenerate `local_db.g.dart` with `dart run build_runner build --delete-conflicting-outputs`), `app/lib/data/local_store.dart` (`_rowFor`, `_rowFromEntry`, `_toEntry` map the new column)
- Test: `app/test/data/migration_test.dart`

**Interfaces:**
- Produces columns: `Entries.previousRefIds` (`text`, default `'[]'`, JSON list); `Meta.tempNext` (`integer`, default `1`); `Meta.numberingEpoch` (`integer`, nullable). `blockNext`/`blockEnd` columns stay in the table (dropping columns in SQLite is a rebuild; not worth it) but are no longer read.
- `schemaVersion => 4`.

- [ ] **Step 1: Write failing tests** in `migration_test.dart`, using a v3 file builder (follow `writeV1File`'s pattern: create the v3 tables with `block_next`/`block_end`, plus entries):

```dart
test('v3 → v4: unsynced rows from the old block become provisional', ...)
// v3 meta: prefix 'HOL', block_next 10, block_end 56, cloud_id set
// rows: a (#7, pending, base 0, tooth M1), b (#7, pending, base 0, tooth M2)  ← one shared group
//       c (#8, pending, base 0), d (#3, synced, base 1), e (#4, pending, base 2)  ← edit of an uploaded row
// after open:
//   a.number == b.number == -1, refId 'HOL-TEMP-1', previousRefIds ['HOL0007']
//   c.number == -2, refId 'HOL-TEMP-2', previousRefIds ['HOL0008']
//   d and e unchanged (number 3 / 4, previousRefIds [])
//   store.block == null; meta.tempNext == 3
test('v3 → v4 without a block leaves every row alone', ...)
```

  "From the old block" = `sync_state = 'pending' AND base_version = 0 AND number > 0` on a cloud-linked file. Groups are converted in ascending number order.
- [ ] **Step 2:** `flutter test test/data/migration_test.dart` → FAIL.
- [ ] **Step 3:** Add the columns and the `from < 4` upgrade step: add columns, then the conversion above (formatting with `provisionalRefId` and `formatRefId` from Task 1), then set `block_next`/`block_end` to NULL. Two-phase is not needed here (targets are negative, sources positive).
- [ ] **Step 4:** `flutter test test/data` → PASS.
- [ ] **Step 5: Commit** `feat: local schema v4, convert unsynced block rows to provisional`

---

### Task 3: LocalStore — provisional creation, renumbering, local compaction

**Files:**
- Modify: `app/lib/data/local_store.dart`
- Test: `app/test/data/local_store_sync_test.dart`, `app/test/data/local_store_test.dart`, `app/test/data/shared_id_test.dart`

**Interfaces:**
- Consumes: Task 1 helpers and `NumberChange`; Task 2 columns.
- Produces on `LocalStore`:
  - `Future<List<Entry>> createProvisional(List<EntryDraft> drafts, String observer, {List<String>? ids, bool sharedId = false})` — numbers `-tempNext, -(tempNext+1)…` (one for all when `sharedId`), refId `provisionalRefId`, `syncState 'pending'`; advances `meta.tempNext`, never reuses.
  - `int get nextProvisional` — the TEMP number the next offline create will show (for the form preview).
  - `Future<List<NumberChange>> assignNumber(int provisional, int number)` — every row (deleted too) with `number == provisional` gets `number`, `formatRefId(...)`, and its old refId appended to `previousRefIds`. Sync state and version untouched. Returns the changes.
  - `Future<void> applyNumbering(List<NumberChange> changes, {int? epoch})` — one transaction, two-phase (first set every changed row to a unique temporary negative number below all provisional ones, e.g. `-1000000 - i`, then to the final value) so `entries_one_element_per_id` never trips; then stores `meta.numberingEpoch` when given. Does not touch `syncState`/`version`.
  - `Future<List<NumberChange>> compactLocal()` — for databases without `cloudId` only (throws `StateError` otherwise): `compactionMap` over live numbers → `applyNumbering`; `meta.nextNumber = max live + 1` (1 when empty).
  - `int? get numberingEpoch`.
  - Removed: `createEntriesFromBlock`, `setBlock`, `block`, `NoNumbersLeft`.

- [ ] **Step 1: Write failing tests**

```dart
test('offline entries get HOL-TEMP numbers that never repeat', ...)
// createProvisional x2 (single) → refIds HOL-TEMP-1, HOL-TEMP-2; delete the 2nd; next → HOL-TEMP-3
test('a shared offline group gets one TEMP', ...)            // 3 teeth, sharedId → all number -1
test('add teeth to a TEMP group', ...)                        // addToGroup('HOL-TEMP-1', -1, ...) → number -1
test('assignNumber renumbers the whole group and keeps the TEMP', ...)
// → all rows number 60, refId HOL0060, previousRefIds ['HOL-TEMP-1'], still pending, version unchanged
test('applyNumbering swaps numbers without tripping the unique index', ...)
// rows #1 M1 and #2 M1 (same tooth, different IDs); changes 1→2 and 2→1 → succeeds
test('compactLocal closes gaps in order and keeps groups', ...)
// live #1, #3 (2 teeth), #4; deleted #2 → #3 group → 2, #4 → 3, previous IDs recorded,
// deleted row still number 2 and its refId unchanged, nextNumber == 4
test('compactLocal on a cloud copy throws', ...)
```

- [ ] **Step 2:** `flutter test test/data` → FAIL.
- [ ] **Step 3:** Implement; delete the block API and fix references (`sync_engine.dart` will not compile until Task 6 — keep a temporary call to `createProvisional` there in place of `createEntriesFromBlock` and remove the reserve-block section, so the suite compiles).
- [ ] **Step 4:** `flutter test` → data tests PASS; sync tests that asserted block numbers will fail — mark them with `skip: 'Task 6'` and list them in the commit message.
- [ ] **Step 5: Commit** `feat: provisional offline Ref IDs and local renumbering`

---

### Task 4: Server migration 004

**Files:**
- Create: `supabase/migrations/004_gapless_ref_ids.sql`
- Modify: `app/assets/supabase_setup.sql` (append 004 verbatim), `app/lib/cloud/cloud_connection.dart` (`kSchemaVersion = 4`), `supabase/checks/role_checks.sql`, `app/test/cloud/setup_sql_test.dart` (add `'004_gapless_ref_ids.sql'` to the list; assert the version from 004)

**Interfaces (SQL):**
- `alter table entries add column previous_ref_ids jsonb not null default '[]'`
- `alter table databases add column numbering_epoch int not null default 0`
- `create table temp_claims (database_id uuid references databases(id) on delete cascade, device_id text, temp_number int, number int not null, primary key (database_id, device_id, temp_number))`, RLS on, read policy for members (`my_role(database_id) is not null`), no write policies.
- `claim_number(db uuid, device text, temp int, ids uuid[]) returns int` — `_require(owner, editor)`; return existing claim's number; else if any of `ids` is in `entries` for `db`, insert the claim with that row's number and return it; else lock `databases` row, take `next_number`, increment, insert claim, return.
- `compact_ref_ids(db uuid) returns jsonb` — `_require(owner)`. Lock `databases` row `for update`. Live numbers = distinct `number` of non-deleted entries ∪ `temp_claims.number` with no entry row. Map in ascending order to 1..k. Phase 1: changed non-deleted entries `number := -number` (all are positive so negatives are free). Phase 2: `number := new`, `ref_id := _ref(prefix, digits, new)`, `previous_ref_ids := previous_ref_ids || to_jsonb(old ref_id)`, `updated_at := now()`. Same map applied to `temp_claims.number`. `next_number := k + 1`; `numbering_epoch += 1`. Returns `{"epoch": n, "changes": [{id, number, ref_id, previous_ref_ids}, …]}`.
- `drop function push_entry(uuid, jsonb, int)`; `create push_entry(db uuid, e jsonb, base_version int, epoch int)` — as in 002, plus: if `epoch <> databases.numbering_epoch` and the row is new → `{"status":"stale"}`; a new row is valid only if its number is in `temp_claims` for `db` or already exists in `entries`; insert also writes `previous_ref_ids` from `e`. Updates never touch `number`, `ref_id`, `previous_ref_ids`.
- `numbering_epoch` is read by the client from `databases` (existing `databases_read` policy covers it).
- `drop function reserve_block(uuid, text, int)`; `drop table id_blocks`.
- `create_entries` unchanged except: no change needed (still uses `next_number`).
- `app_schema_version()` → `select 4`.
- Grants: `claim_number`, `compact_ref_ids`, new `push_entry` to `authenticated`, revoked from `public, anon`.

- [ ] **Step 1: Write failing test:** update `setup_sql_test.dart` list and version assertion → `flutter test test/cloud/setup_sql_test.dart` FAIL.
- [ ] **Step 2:** Write 004, append to setup SQL, bump `kSchemaVersion`.
- [ ] **Step 3:** Add to `role_checks.sql` (run manually against a scratch Supabase project, as the file already documents): viewer cannot call `claim_number`/`compact_ref_ids`; editor cannot call `compact_ref_ids`; `claim_number` twice with the same temp returns the same number; with an id already on the server returns that row's number; compaction of numbers {1,2,57,58} gives {1,2,3,4} with previous IDs; `push_entry` with old epoch on a new row → `stale`; new row with unclaimed number → error. Remove the existing `reserve_block` check (line 72).
- [ ] **Step 4:** `flutter test test/cloud/setup_sql_test.dart` → PASS.
- [ ] **Step 5: Commit** `feat: server migration 004 — claims, compaction, epoch-checked push`

---

### Task 5: CloudApi — claims, compaction, epoch

**Files:**
- Modify: `app/lib/cloud/cloud_api.dart`, `app/lib/cloud/supabase_cloud_api.dart`, `app/test/support/fake_cloud_api.dart`
- Test: `app/test/cloud/supabase_mapping_test.dart`

**Interfaces:**
- Produces on `CloudApi` (removing `reserveBlock`):
  - `Future<int> claimNumber(String db, String device, int provisional, List<String> ids)`
  - `Future<int> numberingEpoch(String db)`
  - `Future<List<NumberChange>> currentNumbers(String db)` — every row (deleted too), paged like `changesSince`.
  - `Future<({int epoch, List<NumberChange> changes})> compactRefIds(String db)`
  - `Future<PushResult> pushEntry(String db, Entry e, {required int baseVersion, required int epoch})`
  - `class PushStale extends PushResult {}`
- `FakeCloudServer` mirrors 004: `epoch` map, `claims` map keyed `(db, device, temp)`, `compact(db)` mirroring the SQL (incl. `updated_at` bump via `_put`), `pushEntry` rules (stale, claimed-or-existing). Remove `blocks`.

- [ ] **Step 1: Write failing tests** in `supabase_mapping_test.dart`: `push_entry` params include `'epoch'`; `{'status':'stale'}` maps to `PushStale`; `compact_ref_ids` response maps to the record (ids, numbers, refIds, previousRefIds). Follow the file's existing request-capture pattern.
- [ ] **Step 2:** `flutter test test/cloud/supabase_mapping_test.dart` → FAIL.
- [ ] **Step 3:** Implement both APIs and the fake.
- [ ] **Step 4:** Same command → PASS.
- [ ] **Step 5: Commit** `feat: cloud API for number claims, compaction and epochs`

---

### Task 6: SyncEngine — claim before push, refresh on renumber, compact

**Files:**
- Modify: `app/lib/cloud/sync_engine.dart`
- Test: `app/test/cloud/sync_engine_test.dart` (un-skip Task 3's skipped tests, rewriting block expectations as TEMP expectations)

**Interfaces:**
- Consumes: Tasks 3 and 5.
- `SyncEngine` loses `blockSize`. Offline `createEntries` → `store.createProvisional`.
- New `Future<List<NumberChange>> compactRefIds()` — `api.compactRefIds`, then `store.applyNumbering(changes, epoch: epoch)`; `CloudOffline` propagates (UI says it needs a connection).
- `_round` order:
  1. definition (as now);
  2. `epoch = api.numberingEpoch`; if `epoch != store.numberingEpoch` → `_refreshNumbers()` (= `store.applyNumbering(diff of api.currentNumbers vs local, epoch: epoch)`, only rows whose number/refId/previousRefIds differ);
  3. for each distinct negative number among pending rows: `n = api.claimNumber(db, deviceId, temp, ids of that group)` → `store.assignNumber(temp, n)`;
  4. push loop with `epoch: store.numberingEpoch ?? 0`; `PushStale` → `_refreshNumbers()` and stop pushing this round (retry next round);
  5. pull: before applying `changes`, if any change has a local row with a different `number`, run `_refreshNumbers()` first;
  6. offline/online events as now.
- `_pushNow` (phones) passes the epoch; `PushStale` → refresh and push once more.

- [ ] **Step 1: Write failing tests**

```dart
test('offline entries get real numbers on reconnect, no gaps', ...)
// PC A online creates #1; goes offline, creates 2 (HOL-TEMP-1, -2); PC B online creates #2;
// A back online → A's rows #3, #4, previousRefIds ['HOL-TEMP-1'] / ['HOL-TEMP-2'];
// server next number 5; numbers on server == {1,2,3,4}
test('offline shared group plus added teeth get one number', ...)   // Review Focus 4
test('lost create response then offline fallback claims the same number', ...)  // Review Focus 2
// dropNextResponse on create → createProvisional with same ids → after sync the rows keep the
// server's number; server nextNumber did not move
test('compaction on one PC reaches the other without deleting rows', ...)       // Review Focus 1
// server rows #1 M1, #3 M1, #4 M1 (#2 deleted); B synced; A compacts; B syncs → B live rows
// #1, #2, #3, none deleted, previous IDs present
test('pending edit survives a renumber from another device', ...)               // Review Focus 3
// B edits #57 offline; A compacts (57→7); B syncs → B's row #7, edit uploaded, no conflicts
test('stale push refreshes numbers and retries', ...)
test('compactRefIds offline throws CloudOffline', ...)
```

- [ ] **Step 2:** `flutter test test/cloud/sync_engine_test.dart` → FAIL.
- [ ] **Step 3:** Implement.
- [ ] **Step 4:** `flutter test` (whole suite) → PASS.
- [ ] **Step 5: Commit** `feat: sync claims numbers for provisional entries and follows renumbering`

---

### Task 7: UI — provisional marker, previous IDs, Close Ref ID gaps

**Files:**
- Modify: `app/lib/ui/workspace_screen.dart` (table Ref ID cell; delete dialog copy), `app/lib/ui/entry_card.dart`, `app/lib/ui/entry_form_screen.dart` (preview + title), `app/lib/ui/structure_screen.dart`, `app/lib/ui/sync_status_chip.dart`, `app/lib/main.dart` (wire `onCloseGaps`)
- Test: `app/test/ui/workspace_test.dart`, `app/test/ui/entry_form_test.dart`, `app/test/ui/structure_test.dart`, `app/test/ui/sync_ui_test.dart`

**Interfaces:**
- `StructureScreen(..., Future<List<NumberChange>> Function()? onCloseGaps)`. In `main.dart`: backup first (`BackupService(Directory(settings.backupDir)).backup(store, exportedBy: settings.observerId ?? '')`), then `engine?.compactRefIds() ?? store.compactLocal()`, then `definitionChanged()`.
- Copy (exact):
  - Provisional chip next to the Ref ID: `Provisional`; tooltip `Gets its final Ref ID when this computer syncs.`
  - Under the Ref ID in the card / form title area: `Previously: HOL-TEMP-1, HOL0057`
  - Form preview offline: `will be saved as HOL-TEMP-4 (provisional)` — uses `store.nextProvisional` when the engine is offline.
  - Structure screen: replace `Existing Ref IDs never change.` with nothing; add section `Ref IDs` with a `Close Ref ID gaps` button.
  - Preview dialog title `Close Ref ID gaps?`; body `N entries will get a new Ref ID. Their old IDs are kept in Previous Ref IDs.` + scrollable list `HOL0057 → HOL0007` (one line per Ref ID, not per row); buttons `Cancel` / `Renumber`. No gaps: snackbar `No gaps — nothing to change.`
  - Offline/denied: `Closing gaps needs an internet connection.` / server message.
  - Delete dialog: `The entry is removed from lists and exports.` (drop "Its Ref ID is not reused.")
  - Offline toast: `You're offline. New entries get provisional IDs (HOL-TEMP-…) until this computer syncs. Changes will sync automatically when you're back online.` — with the database prefix instead of `HOL-`; `syncEventMessage` gains a `String prefix` parameter.
- Preview is computed from `compactionMap(live numbers)` over `store.allEntries()`; when the database is in the cloud and this device has pending rows, the button first runs `engine.syncNow()`.

- [ ] **Step 1: Write failing widget tests**: provisional chip shows for a negative-number entry and not for a positive one; `Previously:` line shows; structure screen dialog lists `HOL0057 → HOL0007` once for a shared group and `Renumber` calls `onCloseGaps`; no-gaps snackbar; offline toast text.
- [ ] **Step 2:** `flutter test test/ui` → FAIL.
- [ ] **Step 3:** Implement.
- [ ] **Step 4:** `flutter test` → PASS; `flutter analyze` → no issues.
- [ ] **Step 5: Commit** `feat: provisional Ref ID marker and Close Ref ID gaps button`

---

### Task 8: Docs and rollout note

**Files:**
- Modify: `docs/superpowers/specs/2026-10-23-bone-database-design.md` (§2 "Sense connexió" row → point to the new spec), `README.md` (if it mentions reserved blocks or updating the server: add "run `004_gapless_ref_ids.sql`")

- [ ] **Step 1:** `grep -rn "reserv\|block" README.md docs/superpowers/specs/2026-10-23-bone-database-design.md` and update each hit.
- [ ] **Step 2: Commit** `docs: gapless Ref IDs`

Rollout (for the user, not code): run 004 in Supabase → update the app on every PC and phone → let them sync → press Close Ref ID gaps.
