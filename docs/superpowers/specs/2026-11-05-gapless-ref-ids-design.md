# Ref IDs sense salts — Especificació de disseny

**Data:** 2026-11-05
**Estat:** Pendent de revisió
**Substitueix:** la decisió "IDs de blocs reservats" (spec principal §2) i els blocs de 50 números del Pla 2.

## 1. Objectiu

Els Ref IDs d'una base de dades han de ser correlatius (1, 2, 3…) i sense salts.

**Criteris d'èxit**
- Amb connexió, crear entrades mai deixa salts.
- Sense connexió, l'entrada rep un ID **provisional** clarament visible (`HOL-TEMP-1`). En sincronitzar rep el següent número real.
- Un botó tanca els salts que ja existeixen (blocs antics, entrades esborrades).
- Cap canvi d'ID es perd: l'ID anterior queda guardat a l'entrada i a l'Excel, per poder seguir la pista de les etiquetes físiques.

**Context:** el Ref ID s'escriu a bosses i etiquetes. Per això un ID provisional ha de semblar provisional, i tot canvi d'ID ha de deixar rastre.

## 2. Decisions preses

| Tema | Decisió |
|---|---|
| Blocs reservats | **S'eliminen.** L'escriptori ja no reserva números. |
| Sense connexió | ID provisional `<prefix>TEMP-<n>` (p. ex. `HOL-TEMP-1`, `MAS-TEMP-3`). Si el prefix acaba en lletra o xifra s'hi afegeix un guió: `HOL` → `HOL-TEMP-1`. |
| Grup de dents offline | Totes les dents del grup comparteixen el mateix TEMP i reben **un sol** número real. |
| "Add teeth to…" offline sobre un TEMP | Permès; les dents noves segueixen el TEMP del grup. |
| Rastre | Camp nou **Previous Ref IDs** (llista, el més antic primer). Visible a la fitxa de l'entrada i com a columna a l'Excel. |
| Compactar | Botó **Close Ref ID gaps** a l'estructura de la base de dades. Només l'Owner. En una base de dades al núvol, només amb connexió. |
| Ordre en compactar | Es manté l'ordre actual dels números. Els grups compartits continuen compartint número. |
| Entrades esborrades | No es renumeren. El seu número pot tornar a aparèixer en una entrada viva (no hi ha conflicte: l'índex únic només mira les vives). |
| Mòbil | Cap canvi de flux: ja desa només amb connexió. Rep els números nous en sincronitzar. |
| Bases de dades locals (sense núvol) | El botó també hi és i compacta en local. No tenen IDs provisionals: sempre tenen número. |

## 3. IDs provisionals (escriptori sense connexió)

**Local**
- Les entrades provisionals es guarden amb `number` **negatiu** (-1, -2, …). `refId` = `<prefix>TEMP-<n>`. El comptador és una columna nova `meta.tempNext`, que comença a 1 i no es reinicia mai en aquell fitxer, per evitar repetir TEMP en etiquetes.
- `createEntriesFromBlock` es substitueix per `createProvisional`. Mai falla per falta de números, així que `NoNumbersLeft` desapareix.
- El formulari mostra "will be saved as HOL-TEMP-4 (provisional)" quan no hi ha connexió.
- A la taula i a la fitxa, un ID provisional es veu en cursiva amb una etiqueta "Provisional".

**En sincronitzar** (dins de `_round`, abans del push):
1. Per a cada número negatiu diferent entre les entrades pendents, es crida la RPC `claim_number(db, device, temp, ids)` amb els ids de les entrades del grup. Retorna el número real.
2. En una sola transacció local, totes les entrades amb aquell número negatiu passen al número real, el `refId` es recalcula i s'afegeix `HOL-TEMP-n` a Previous Ref IDs.
3. Després, el push de sempre (`push_entry`) puja les entrades ja amb número real.

**Servidor**
- Taula nova `temp_claims(database_id, device_id, temp_number, number)` amb clau primària `(database_id, device_id, temp_number)`.
- `claim_number`: si la reclamació ja existeix, retorna el mateix número. Si algun dels `ids` ja és al servidor (un intent en línia que va arribar però la resposta es va perdre), retorna el número d'aquella fila i no en gasta cap de nou. Així, si la resposta es perd, no es gasta cap altre número. Si no existeix, pren `next_number` i l'incrementa en 1.
- `push_entry` passa a tenir un paràmetre més, `epoch` (el `numbering_epoch` que coneix el dispositiu). Canviar la signatura és intencionat: les apps antigues, que la criden sense `epoch`, reben un error i no poden pujar números que podrien estar desfasats. L'error es mostra com a problema de sincronització ("Update the app to keep syncing"). Les seves entrades queden pendents al PC, no es perden.
- Una fila nova és vàlida si el seu número és a `temp_claims`, o si ja existeix a `entries` (s'afegeix a un grup compartit) **i** `epoch` és l'actual. Si `epoch` és antic, retorna `stale`: el dispositiu actualitza els números (§4) i torna a provar.
- `push_entry` accepta `previous_ref_ids` en inserir una fila. En actualitzar-la no el toca, perquè només el servidor (compactar) o el claim el modifiquen.
- `reserve_block` i `id_blocks` deixen de fer-se servir. La migració 004 esborra `reserve_block`; la taula `id_blocks` es buida i s'esborra.

## 4. Compactar (botó "Close Ref ID gaps")

**Previsualització:** abans d'aplicar, un diàleg mostra quantes entrades canviaran i una llista `HOL0057 → HOL0007`. Si no hi ha salts: "No gaps — nothing to change."

**Servidor:** nova RPC `compact_ref_ids(db)`, només per a l'Owner:
1. Bloqueja la fila de `databases` (`for update`). Mentrestant, qualsevol `create_entries`/`claim_number` espera.
2. Calcula el número nou de cada número viu diferent, en ordre: 1, 2, 3…
3. Aplica els canvis en dues fases (primer a negatiu, després al definitiu) per no xocar amb l'índex únic. A cada fila que canvia, l'ID antic s'afegeix a `previous_ref_ids` i s'actualitza `updated_at`. **No** s'incrementa `version`, perquè renumerar no ha de crear conflictes amb edicions pendents.
4. `next_number` = màxim viu + 1. `temp_claims.number` es renumera amb el mateix mapa, perquè un claim repetit retorni el número **actual** del grup. Un claim que encara no té cap fila pujada també compta com a número viu, perquè no es perdi.
5. Incrementa `databases.numbering_epoch`.
6. Retorna la llista de canvis.

**Altres dispositius:** quan detecten que `numbering_epoch` ha canviat, descarreguen `(id, number, ref_id, previous_ref_ids)` de totes les files i les reescriuen en una sola transacció local en dues fases. Ho fan també en les files amb edicions pendents, perquè el número és del servidor i les edicions (valors) es conserven.

**Local (sense núvol):** el mateix algorisme en una transacció de drift. `meta.nextNumber` = màxim + 1.

**Seguretat:** abans de compactar es fa un backup local automàtic (el servei de backup existent).

## 5. Canvis d'esquema

**Servidor:** migració `004_gapless_ref_ids.sql`. També s'actualitza `app/assets/supabase_setup.sql` per a l'edició de servidor propi.
- `entries.previous_ref_ids jsonb not null default '[]'`
- `databases.numbering_epoch int not null default 0`
- taula `temp_claims` (+ RLS: lectura per a membres; escriptura només via funcions)
- funcions `claim_number`, `compact_ref_ids`; `push_entry` amb el paràmetre `epoch`; s'esborren `reserve_block` i `id_blocks`
- `app_schema_version()` → 4; `kSchemaVersion = 4` a l'app. Un servidor amb versió 3 mostra el missatge "server needs update" que ja existeix.

**Local (drift):** `schemaVersion` 4.
- `entries.previousRefIds` (text JSON, default `'[]'`)
- `meta.tempNext` (int, default 1), `meta.numberingEpoch` (int, nullable)
- En migrar: s'esborra el bloc reservat (`blockNext/blockEnd` = null). Les entrades pendents que encara no s'havien pujat mai (`baseVersion = 0`) i tenien un número del bloc passen a ser provisionals: número negatiu, `HOL-TEMP-n`, i l'ID del bloc va a Previous Ref IDs (encara que no s'hagi pujat mai, pot estar escrit en una etiqueta). Les entrades d'un mateix grup reben el mateix TEMP.

## 6. Excel i fitxa

- Columna nova **Previous Ref IDs** just després de Ref ID, amb els valors separats per `; `. Si cap entrada en té, la columna es manté igualment, perquè l'Excel en viu tingui sempre les mateixes columnes.
- La fitxa de l'entrada mostra "Previously: HOL-TEMP-1, HOL0057" sota el Ref ID.

## 7. Errors i casos límit

- **Compactar mentre un altre PC és offline amb TEMPs:** cap problema. Els seus TEMPs reclamaran números després de `next_number`.
- **Un PC amb l'app antiga i entrades offline d'un bloc sense pujar:** no pot pujar-les (signatura nova de `push_entry`). En actualitzar l'app, la migració local les converteix en TEMP (§5) i reben un número nou sense xocar amb ningú.
- **Ordre recomanat per al primer ús:** actualitzar l'app a tots els PCs i mòbils, deixar que sincronitzin, i després prémer Close Ref ID gaps.
- **Afegir dents a un grup mentre un altre PC compacta:** el push arriba amb `epoch` antic → `stale` → el dispositiu actualitza els números i torna a provar amb el número nou del grup.
- **Resposta del claim perduda:** el següent intent retorna el mateix número (clau a `temp_claims`).
- **Viewer:** no pot compactar ni reclamar números (com ara).
- **Dues compactacions alhora:** el bloqueig de la fila les serialitza; la segona no troba salts.

## 8. Proves

- `local_store`: provisional (negatiu, TEMP, comptador no es reinicia), grup TEMP, add-to-group sobre TEMP, compactar local (ordre, grups, Previous Ref IDs, esborrades intactes).
- `sync_engine` amb `FakeCloudApi`: claim → renumera → push; claim repetit idempotent; epoch canviat → reescriptura amb edició pendent conservada.
- SQL (`supabase/checks`): `claim_number` idempotent, `compact_ref_ids` (dues fases, epoch, només Owner), `push_entry` amb `epoch` antic → `stale`; fila nova amb número no reclamat → error; `reserve_block` ja no existeix.
- Migració local v3 → v4: entrades pendents d'un bloc passen a TEMP (grups junts) i guarden l'ID del bloc.
- Excel: columna Previous Ref IDs.
- UI: etiqueta Provisional, previsualització del diàleg de compactar.

## 9. Fora d'abast

- Desfer una compactació (hi ha el backup automàtic).
- Reutilitzar els números de les entrades esborrades sense prémer el botó.
