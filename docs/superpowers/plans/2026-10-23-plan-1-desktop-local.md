# Bone Data Manager — Plan 1: Desktop app (local) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A working Windows desktop app that creates bone/teeth databases, records entries with automatic Ref IDs, exports Excel and makes local backups — no cloud yet.

**Architecture:** Flutter desktop app. Each database is one SQLite file (Drift) holding its definition, layers and entries. Pure-Dart domain modules (catalog, schema, ids, teeth, export cell formatting) are unit-tested; a `LocalStore` wraps the SQLite file; Riverpod providers connect stores to screens. Plan 2 adds Supabase (login, roles, sync, offline ID blocks, toasts); Plan 3 adds the mobile app.

**Tech Stack:** Flutter (latest stable) / Dart, `drift` + `sqlite3_flutter_libs` + `drift_dev`/`build_runner`, `flutter_riverpod`, `syncfusion_flutter_xlsio` (write .xlsx), `excel` (dev only, read .xlsx in tests), `path_provider`, `shared_preferences`, `file_picker`, `uuid`, `intl`.

**Spec:** `docs/superpowers/specs/2026-10-23-bone-database-design.md`

**Deviation from spec:** the spec names the `excel` package for export. It cannot set autofilter, which spec §12 requires, so writing uses `syncfusion_flutter_xlsio` (free Community License for individuals/small organisations). `excel` stays as a test-only reader.

**Plan 1 scope (from the spec):** §5 (local part), §6 online-equivalent counter, §7, §8, §9 screens 2–8 without Login/Members/storage choice, §12, §13, §14 unit + widget tests. **Deferred to Plan 2:** Login, roles/RLS, Members step, Supabase, sync, offline ID blocks, connection toasts, conflict dialog. **Plan 3:** mobile.

## Global Constraints

- All UI text in English.
- One entry = one bone or one tooth; each has its own Ref ID.
- Ref ID = `prefix` + number zero-padded to `digits` (default 4) → `MAS-0001`. Prefix optional. A Ref ID never changes and is never reused, even after deletion.
- Permanent teeth: `I1 I2 C P3 P4 M1 M2 M3`. Deciduous: `di1 di2 dc dm1 dm2`. No tooth numbering anywhere.
- Tooth expansion order: Upper before Lower, Right before Left, then tooth type in catalog order.
- Choice and Yes/No layers render as buttons, never dropdowns. Selected = solid primary fill + white text + ✓ icon.
- Dental layer templates are all off by default.
- Excel "Entries" columns, in order: `Ref ID · Element · Region · Dentition · Tooth type · Jaw · Side · [layers by order] · Created by · Created at · Modified by · Modified at`. Multi choice joined with `; `. Not-applicable cells empty. Header frozen + autofilter. "Info" sheet. File name `<database-name>_<YYYY-MM-DD>.xlsx`.
- Backup: every 15 min (configurable) and on close; each backup = `.sqlite` + `.xlsx`; keep 20 most recent per database.
- Entry form scrolls vertically; Save button pinned at bottom.

## Review Focus

1. Number larger than `digits` allows (entry 10 000 with 4 digits) → must widen, never truncate: `MAS-10000`. Test in Task 2.
2. Tooth selection with an empty dimension (no jaw, side or type) → 0 entries and Create blocked with "Select at least one jaw, side and tooth type". Tests in Tasks 3 and 9.
3. Layer options edited after data exists (option renamed/removed) → stored values kept and exported as-is, not blanked. Test in Task 6.
4. Database name with characters illegal in Windows file names (`Site/2026: A`) → export/backup file names sanitised, not a crash. Test in Task 6.
5. Delete the last entry then create a new one → number is not reused. Test in Task 5.

---

## File structure

```
app/                                  Flutter project root
  pubspec.yaml
  lib/
    main.dart                         app entry, ProviderScope, theme
    common/enums.dart                 Region, Dentition, Jaw, Side + labels
    catalog/catalog.dart              BoneDef list, tooth type lists
    schema/layer.dart                 Layer, LayerType, validateLayer
    schema/dental_templates.dart      8 dental layer templates
    schema/database_def.dart          DatabaseDef, validatePrefix, validateName
    ids/ref_id.dart                   formatRefId
    teeth/tooth_selection.dart        ToothSpec, expandToothSelection
    entries/entry.dart                EntryDraft, Entry, validateDraft
    data/local_db.dart (+ .g.dart)    Drift tables
    data/local_store.dart             LocalStore (one database file)
    data/registry.dart                recent databases list
    export/cell_format.dart           cellText, exportFileName, sanitizeFileName
    export/excel_export.dart          buildWorkbookBytes
    backup/backup_service.dart        BackupService
    state/providers.dart              Riverpod providers
    ui/theme.dart
    ui/widgets/select_chips.dart
    ui/home_screen.dart
    ui/wizard/wizard_screen.dart      steps: Name, Reference ID, Bones, Layers, Review
    ui/wizard/layer_editor.dart
    ui/observer_dialog.dart
    ui/workspace_screen.dart
    ui/entry_form_screen.dart
    ui/structure_screen.dart
    ui/settings_screen.dart
  test/  (mirrors lib/)
```

---

### Task 0: Environment and project scaffold

**Files:** Create `app/` (via `flutter create`), `.gitignore`

- [ ] **Step 1:** Install the Flutter SDK (stable) from flutter.dev and Visual Studio 2022 with the "Desktop development with C++" workload (needed for Windows builds). **Ask the user before downloading.** Verify: `flutter doctor` shows Flutter ✓ and Visual Studio ✓.
- [ ] **Step 2:** In `C:\Users\alber\Desktop\datamanager`: `git init`, then `flutter create --platforms=windows --org com.bonedatamanager --project-name bone_data_manager app`.
- [ ] **Step 3:** In `app/`: `flutter pub add drift sqlite3_flutter_libs flutter_riverpod syncfusion_flutter_xlsio path_provider shared_preferences file_picker uuid intl path` and `flutter pub add --dev drift_dev build_runner excel`.
- [ ] **Step 4:** Run `flutter test` (default counter test) → PASS; `flutter run -d windows` opens a window. Delete the counter test and demo code in `main.dart`.
- [ ] **Step 5:** Commit `chore: scaffold Flutter desktop project`.

### Task 1: Enums and bone catalog

**Files:** Create `lib/common/enums.dart`, `lib/catalog/catalog.dart`; Test `test/catalog/catalog_test.dart`

**Interfaces — Produces:**
- `enum Region { skull, teeth, vertebralColumn, thorax, upperLimb, pelvis, lowerLimb }` with `String get label` → `Skull, Teeth, Vertebral column, Thorax, Upper limb, Pelvis, Lower limb`.
- `enum Dentition { permanent, deciduous }`, `enum Jaw { upper, lower }`, `enum Side { right, left }`, each with `label` (`Permanent`, `Upper`, `Right`…).
- `class BoneDef { final String id; final String name; final Region region; final bool paired; }`
- `const List<BoneDef> kBones;` `List<BoneDef> bonesIn(Region r)`; `BoneDef boneById(String id)` (throws on unknown).
- `const String kTeethId = 'teeth';` `const List<String> kPermanentTeeth = ['I1','I2','C','P3','P4','M1','M2','M3'];` `const List<String> kDeciduousTeeth = ['di1','di2','dc','dm1','dm2'];` `List<String> toothTypesFor(Dentition d)`.

Catalog content is spec §7 verbatim. Ids are snake_case (`femur`, `rib_1`, `c1`, `t12`, `metacarpal_3`, `hand_proximal_phalanx_1`, `foot_distal_phalanx_5`, `medial_cuneiform`, `os_coxae`). Names use spec spelling (`Rib 1`, `C1`, `Hand proximal phalanx 1`). Intermediate phalanges exist only for rays 2–5.

- [ ] **Step 1: Write the failing tests**

```dart
test('catalog has 120 unique bones', () {
  expect(kBones.length, 120);
  expect(kBones.map((b) => b.id).toSet().length, 120);
});
test('region counts', () {
  expect(bonesIn(Region.skull).length, 18);
  expect(bonesIn(Region.vertebralColumn).length, 26);
  expect(bonesIn(Region.thorax).length, 13);
  expect(bonesIn(Region.upperLimb).length, 32);
  expect(bonesIn(Region.pelvis).length, 1);
  expect(bonesIn(Region.lowerLimb).length, 30);
});
test('pairing', () {
  expect(boneById('femur').paired, isTrue);
  expect(boneById('rib_7').paired, isTrue);
  expect(boneById('mandible').paired, isFalse);
  expect(boneById('sacrum').paired, isFalse);
  expect(boneById('sternum').paired, isFalse);
});
test('tooth types', () {
  expect(toothTypesFor(Dentition.permanent), ['I1','I2','C','P3','P4','M1','M2','M3']);
  expect(toothTypesFor(Dentition.deciduous), ['di1','di2','dc','dm1','dm2']);
});
```

- [ ] **Step 2:** `flutter test test/catalog` → FAIL (undefined).
- [ ] **Step 3:** Implement the two files.
- [ ] **Step 4:** `flutter test test/catalog` → PASS.
- [ ] **Step 5:** Commit `feat: bone catalog and shared enums`.

### Task 2: Ref ID formatting

**Files:** Create `lib/ids/ref_id.dart`; Test `test/ids/ref_id_test.dart`

**Interfaces — Produces:** `String formatRefId(String prefix, int digits, int number)`.

- [ ] **Step 1: Failing tests**

```dart
expect(formatRefId('MAS-', 4, 1), 'MAS-0001');
expect(formatRefId('', 4, 37), '0037');
expect(formatRefId('X', 2, 5), 'X05');
expect(formatRefId('MAS-', 4, 10000), 'MAS-10000'); // Review Focus 1
```

- [ ] **Step 2:** run → FAIL. **Step 3:** implement with `padLeft`. **Step 4:** run → PASS. **Step 5:** commit `feat: ref id formatting`.

### Task 3: Tooth selection expansion

**Files:** Create `lib/teeth/tooth_selection.dart`; Test `test/teeth/tooth_selection_test.dart`

**Interfaces — Consumes:** Task 1 enums, `toothTypesFor`. **Produces:**
- `class ToothSpec { final Dentition dentition; final Jaw jaw; final Side side; final String type; }` (value equality)
- `List<ToothSpec> expandToothSelection({required Dentition dentition, required Set<Jaw> jaws, required Set<Side> sides, required Set<String> types})` — order: Jaw (upper, lower) → Side (right, left) → type in `toothTypesFor(dentition)` order. Types not valid for the dentition are ignored.

- [ ] **Step 1: Failing tests**

```dart
test('2 jaws x 1 side x 2 types = 4 in order', () {
  final r = expandToothSelection(dentition: Dentition.permanent,
      jaws: {Jaw.lower, Jaw.upper}, sides: {Side.left}, types: {'P4', 'M1'});
  expect(r.map((t) => '${t.jaw.label} ${t.side.label} ${t.type}'),
      ['Upper Left P4', 'Upper Left M1', 'Lower Left P4', 'Lower Left M1']);
});
test('empty dimension gives zero', () { // Review Focus 2
  expect(expandToothSelection(dentition: Dentition.permanent,
      jaws: {}, sides: {Side.left}, types: {'M1'}), isEmpty);
});
test('deciduous ignores permanent types', () {
  expect(expandToothSelection(dentition: Dentition.deciduous,
      jaws: {Jaw.upper}, sides: {Side.right}, types: {'M1', 'dm1'}).single.type, 'dm1');
});
```

- [ ] **Steps 2–5:** FAIL → implement → PASS → commit `feat: tooth selection expansion`.

### Task 4: Schema — layers, templates, database definition, entries

**Files:** Create `lib/schema/layer.dart`, `lib/schema/dental_templates.dart`, `lib/schema/database_def.dart`, `lib/entries/entry.dart`; Tests `test/schema/layer_test.dart`, `test/schema/database_def_test.dart`, `test/entries/entry_test.dart`

**Interfaces — Produces:**
- `enum LayerType { singleChoice, multiChoice, yesNo, shortText, number, date }` with `label` (`Single choice`, `Multiple choice`, `Yes/No`, `Short text`, `Number`, `Date`).
- `class Layer { String id; String name; LayerType type; List<String> options; List<String> appliesTo; int order; Map<String,Object?> toJson(); factory Layer.fromJson(Map); bool appliesToElement(String elementId); }` — `appliesTo` empty = all elements; otherwise bone ids and/or `kTeethId`.
- Value shapes in `Entry.values[layer.id]`: singleChoice `String`, multiChoice `List<String>`, yesNo `bool`, shortText `String`, number `num`, date `String` `YYYY-MM-DD`.
- `const kFixedColumns = ['Ref ID','Element','Region','Dentition','Tooth type','Jaw','Side','Created by','Created at','Modified by','Modified at'];`
- `String? validateLayer(Layer layer, List<Layer> others)` — errors: `Enter a name`; `A layer with this name already exists` (case-insensitive); `This name is reserved` (in `kFixedColumns`, case-insensitive); `Add at least one option` (choice types); `Options must be unique`.
- `List<Layer> dentalTemplates()` — the 8 layers of spec §8 with fresh ids, `appliesTo: [kTeethId]`. Wear options `'1'..'8'`; Calculus `'0'..'3'`; Development stage options = Moorrees crown/root stages `Ci, Cco, Coc, Cr½, Cr¾, Crc, Ri, Rcl, R¼, R½, R¾, Rc, A½, Ac`.
- `class DatabaseDef { String id; String name; String prefix; int digits; Set<String> selectedElements; List<Layer> layers; }` + `copyWith`.
- `String? validateName(String)` → `Enter a name` if blank. `String? validatePrefix(String)` → allowed `[A-Za-z0-9_-]{0,10}`, else `Use up to 10 letters, numbers, - or _`.
- `class EntryDraft { String elementId; Dentition? dentition; String? toothType; Jaw? jaw; Side? side; Map<String,Object?> values; }` — `elementId` is a bone id or `kTeethId`.
- `class Entry { String id; String refId; EntryDraft data; String createdBy; DateTime createdAt; String modifiedBy; DateTime modifiedAt; int version; bool deleted; }`
- `String elementName(EntryDraft d)` → bone name or `Tooth`; `Region elementRegion(EntryDraft d)`.
- `String? validateDraft(EntryDraft d, DatabaseDef db)` — errors: `This element is not part of the database`; `Choose Left or Right` (paired bone without side).

- [ ] **Step 1: Failing tests** — one per validation message above, plus: `Layer.fromJson(l.toJson())` round-trips; `dentalTemplates()` has 8 layers named `Status, Wear, Caries, Calculus, Enamel hypoplasia, Periapical lesion, Development stage, Notes`; `validatePrefix('MAS-')` null, `validatePrefix('MA S')` error; `validateDraft(femur without side)` == `Choose Left or Right`; `validateDraft(mandible without side)` == null.
- [ ] **Steps 2–5:** FAIL → implement → PASS → commit `feat: layers, database definition and entry models`.

### Task 5: Local storage (Drift) and registry

**Files:** Create `lib/data/local_db.dart`, `lib/data/local_store.dart`, `lib/data/registry.dart`; Test `test/data/local_store_test.dart`

**Tables (one SQLite file per database):** `meta` (single row: id, name, prefix, digits, next_number, selected_elements JSON), `layers` (id, json, sort_order), `entries` (id, ref_id UNIQUE, element_id, dentition, tooth_type, jaw, side, values JSON, created_by, created_at, modified_by, modified_at, version, deleted).

**Interfaces — Consumes:** Task 2 `formatRefId`, Task 4 models. **Produces:**
- `class LocalStore { static Future<LocalStore> create(File file, DatabaseDef def); static Future<LocalStore> open(File file); factory LocalStore.inMemory(DatabaseDef def); }`
- `DatabaseDef get def;` `Future<void> updateDefinition(DatabaseDef def)` (name, prefix, digits, elements, layers — never touches `next_number`).
- `Future<List<Entry>> createEntries(List<EntryDraft> drafts, String observer)` — one transaction; consecutive numbers from `next_number`; increments it by `drafts.length`.
- `Future<Entry> updateEntry(String id, EntryDraft data, String observer)` — bumps `version`, sets modified fields.
- `Future<void> deleteEntry(String id, String observer)` — soft delete.
- `Stream<List<Entry>> watchEntries()` — non-deleted, ordered by `ref_id`. `Future<List<Entry>> allEntries()`.
- `Future<void> vacuumInto(File target)` (for backups). `File? get file;` `Future<void> close()`.
- `class Registry { Future<List<RecentDb>> recents(); Future<void> remember(String path, String name); Future<void> forget(String path); }` (shared_preferences, max 10, most recent first). `class RecentDb { String path; String name; DateTime openedAt; }`

- [ ] **Step 1: Failing tests** (in-memory store, prefix `MAS-`, digits 4)

```dart
test('bulk create gives consecutive ids and audit fields', () async {
  final e = await store.createEntries([draftA, draftB, draftC], 'AP');
  expect(e.map((x) => x.refId), ['MAS-0001', 'MAS-0002', 'MAS-0003']);
  expect(e.first.createdBy, 'AP');
});
test('deleted numbers are never reused', () async { // Review Focus 5
  final e = await store.createEntries([draftA], 'AP');
  await store.deleteEntry(e.single.id, 'AP');
  expect((await store.createEntries([draftA], 'AP')).single.refId, 'MAS-0002');
});
test('update bumps version and modified fields', ...);
test('changing prefix keeps old ref ids and continues numbering', ...);
test('create then open from file round-trips definition and entries', ...); // temp dir
```

- [ ] **Step 2:** FAIL. **Step 3:** implement; run `dart run build_runner build --delete-conflicting-outputs`. **Step 4:** PASS. **Step 5:** commit `feat: local SQLite store with ref id counter`.

### Task 6: Excel export

**Files:** Create `lib/export/cell_format.dart`, `lib/export/excel_export.dart`; Tests `test/export/cell_format_test.dart`, `test/export/excel_export_test.dart`

**Interfaces — Consumes:** Tasks 1, 4. **Produces:**
- `String cellText(Layer layer, Object? value)` — null → `''`; multi → `join('; ')`; yesNo → `Yes`/`No`; number → no trailing `.0`; others `toString()`.
- `String sanitizeFileName(String s)` — replaces each of `<>:"/\|?*` with `-`, trims.
- `String exportFileName(String dbName, DateTime date)` → `'${sanitizeFileName(dbName)}_${yyyy-MM-dd}.xlsx'`.
- `List<int> buildWorkbookBytes(DatabaseDef db, List<Entry> entries, {required String exportedBy, required DateTime exportedAt})` — sheet `Entries` (columns per Global Constraints; layers by `order`; dates `yyyy-MM-dd HH:mm`), frozen row 1, autofilter over used range; sheet `Info` with rows `Database`, `Prefix`, `Exported at`, `Exported by`, then a blank row and one row per layer: name, type label, options joined `; `.

- [ ] **Step 1: Failing tests** — decode the bytes with `excel` (dev dep) and assert:
  - header row equals `['Ref ID','Element','Region','Dentition','Tooth type','Jaw','Side','Wear','Caries','Created by','Created at','Modified by','Modified at']` for a db with layers Wear, Caries;
  - tooth row: `MAS-0001, Tooth, Teeth, Permanent, M1, Lower, Left, 3, Occlusal; Root, AP, …`;
  - femur row: Dentition/Tooth type/Jaw empty, Side `Right`;
  - value `'Grade X'` not in options still exported as `Grade X` (Review Focus 3);
  - `exportFileName('Site/2026: A', DateTime(2026,10,23))` == `Site-2026- A_2026-10-23.xlsx` (Review Focus 4);
  - sheet `Info` exists with `Database` row.
- [ ] **Steps 2–5:** FAIL → implement → PASS → commit `feat: excel export`.

### Task 7: Backup service

**Files:** Create `lib/backup/backup_service.dart`; Test `test/backup/backup_service_test.dart`

**Interfaces — Consumes:** Task 5 `LocalStore.vacuumInto`, `allEntries`; Task 6 `buildWorkbookBytes`, `sanitizeFileName`. **Produces:**
- `class BackupService { BackupService(Directory dir, {int keep = 20}); Future<BackupInfo> backup(LocalStore store, {required String exportedBy}); Future<List<BackupInfo>> list(String databaseId); Future<File> restore(BackupInfo b, Directory databasesDir); }`
- `class BackupInfo { String databaseId; String databaseName; DateTime at; File sqlite; File xlsx; }`
- Files: `<sanitized-name>_<databaseId8>_<yyyyMMdd-HHmmss>.sqlite|.xlsx` (first 8 chars of id keep databases with the same name apart). `restore` copies the `.sqlite` to `databasesDir/<sanitized-name> (restored <yyyy-MM-dd HH-mm>).sqlite` and returns it.

- [ ] **Step 1: Failing tests** (temp dirs, injectable clock `DateTime Function() now`): backup writes both files; 22 backups → `list` returns 20, newest first; restore produces a file that `LocalStore.open` reads with the same entries.
- [ ] **Steps 2–5:** FAIL → implement → PASS → commit `feat: local backups with retention and restore`.

### Task 8: Theme, selection buttons, app shell and Home

**Files:** Create `lib/ui/theme.dart`, `lib/ui/widgets/select_chips.dart`, `lib/state/providers.dart`, `lib/ui/home_screen.dart`, modify `lib/main.dart`; Test `test/ui/select_chips_test.dart`

**Interfaces — Produces:**
- `class SelectChips<T> extends StatelessWidget { SelectChips({required List<T> values, required String Function(T) label, required Set<T> selected, required ValueChanged<Set<T>> onChanged, bool multi = true}); }` — `Wrap` of buttons; selected: `colorScheme.primary` fill, `onPrimary` text, leading `Icons.check`; unselected: outlined. Single mode replaces the set; tapping the selected one in single mode deselects.
- Providers: `registryProvider`, `openStoreProvider` (`StateProvider<LocalStore?>`), `observerIdProvider` (persisted in shared_preferences), `settingsProvider` (backup dir, interval minutes default 15).
- Theme: Material 3, one seed colour, light + dark, `useMaterial3: true`.
- Home: buttons `Create a new database`, `Open an existing database` (file picker for `.sqlite`), list of recents (click opens). Opening = `LocalStore.open` → `Registry.remember` → Observer dialog (Task 10) → Workspace.

- [ ] **Step 1: Failing widget tests:** tapping `M1` in multi mode calls `onChanged({'M1'})`; a selected chip shows `Icons.check` and its `Material` colour equals `colorScheme.primary`; single mode tapping `B` with `{'A'}` selected gives `{'B'}`.
- [ ] **Steps 2–4:** FAIL → implement → PASS. Manual: `flutter run -d windows` shows Home in light and dark.
- [ ] **Step 5:** commit `feat: theme, selection buttons and home screen`.

### Task 9: Create wizard

**Files:** Create `lib/ui/wizard/wizard_screen.dart`, `lib/ui/wizard/layer_editor.dart`; Test `test/ui/wizard_test.dart`

Steps (stepper at top, Back/Next at bottom): **Name** (`validateName`) → **Reference ID** (prefix with `validatePrefix`, digits 3–6 default 4, live preview `formatRefId(prefix, digits, 1)`) → **Bones** ("Which bones are you planning to observe?": `All body` toggle, one expandable card per `Region` with a region checkbox and per-bone checkboxes; Teeth is a single checkbox) → **Layers** (list + `Add layer` dialog: name, type as `SelectChips` single, options editor for choice types, "Applies to": All / Teeth / chosen bones; reorder by drag; if Teeth selected, a "Dental templates" section with one switch per template, all off) → **Review** (summary) → `Create` → save dialog for file location (default `Documents/Bone Data Manager/`) → `LocalStore.create` → open Workspace.

**Interfaces — Consumes:** Tasks 1, 2, 4, 5, 8.

- [ ] **Step 1: Failing widget tests:** Next on Name with empty field shows `Enter a name`; typing prefix `MAS-` shows preview `MAS-0001`; `All body` checks every region including Teeth; Dental templates section hidden when Teeth unchecked and all switches off when shown; adding a layer named `Side` shows `This name is reserved`.
- [ ] **Steps 2–5:** FAIL → implement → PASS → commit `feat: create database wizard`.

### Task 10: Observer dialog, Workspace and entry form

**Files:** Create `lib/ui/observer_dialog.dart`, `lib/ui/workspace_screen.dart`, `lib/ui/entry_form_screen.dart`; Test `test/ui/entry_form_test.dart`, `test/ui/workspace_test.dart`

- **Observer dialog:** text field prefilled from `observerIdProvider`, required (`Enter your observer ID`), saved on confirm. Workspace header shows `Observer: AP` (click to change).
- **Workspace:** `DataTable`/paginated table of `watchEntries()` with the export columns minus audit times; search box (matches Ref ID, element, any layer text); filter chips for Element, Side, Jaw, Tooth type; buttons `New entry`, `Export Excel` (save dialog with `exportFileName`), `Structure`; row click opens edit; row menu `Delete` with confirm.
- **Entry form:** first `SelectChips` single: `Bone` / `Teeth` (Teeth only if selected in the db).
  - Bone: searchable list limited to selected bones; if paired, `Left`/`Right` chips.
  - Teeth: Dentition (single), Jaw, Side, Tooth type (multi) chips; preview text `N entries will be created` + list of provisional Ref IDs; with N = 0 the Save button shows message `Select at least one jaw, side and tooth type` and does nothing.
  - Layers applicable to the element, as: choice/yes-no → `SelectChips`; short text/number → `TextField`; date → date picker.
  - `SingleChildScrollView` body, Save pinned in `bottomNavigationBar`. Save → `validateDraft` → `createEntries` / `updateEntry`.

**Interfaces — Consumes:** Tasks 3, 4, 5, 6, 8.

- [ ] **Step 1: Failing widget tests:** teeth with Lower + Left + P4, M1 shows `2 entries will be created`; with no jaw, Save shows `Select at least one jaw, side and tooth type` and the store has 0 entries (Review Focus 2); femur without side → `Choose Left or Right`; saving 2 teeth creates `MAS-0001`, `MAS-0002` with `createdBy` = observer; Save button stays visible after scrolling a form with 15 layers.
- [ ] **Steps 2–5:** FAIL → implement → PASS → commit `feat: workspace and entry form`.

### Task 11: Structure and Settings screens, scheduled backups

**Files:** Create `lib/ui/structure_screen.dart`, `lib/ui/settings_screen.dart`; modify `lib/main.dart`, `lib/state/providers.dart`; Test `test/ui/structure_test.dart`

- **Structure:** reuses wizard's Bones and Layers steps plus name/prefix/digits on one page; Save → `updateDefinition`. Removing a layer asks for confirmation: `Existing values stay stored but won't be exported`.
- **Settings:** backup folder (folder picker; default `Documents/Bone Data Manager/Backups`), interval minutes (default 15), `Back up now`, `Restore from backup` (list from `BackupService.list`, restore → open restored file).
- **Scheduling:** while a store is open, a `Timer.periodic(interval)` calls `backup`; on window close (`AppLifecycleListener.onExitRequested`) run one backup before exiting.

- [ ] **Step 1: Failing tests:** changing prefix in Structure then creating an entry gives new prefix with continued number; removing a layer shows the warning text.
- [ ] **Steps 2–4:** FAIL → implement → PASS.
- [ ] **Step 5: Manual end-to-end check** (`flutter run -d windows`): create db `Test` prefix `MAS-` with All body + Wear template → add femur Right and 4 teeth → export → open the xlsx in Excel: frozen header, filters, columns as specified → `Back up now` → restore → same entries.
- [ ] **Step 6:** `flutter build windows` succeeds. Commit `feat: structure editing, settings and scheduled backups`.
