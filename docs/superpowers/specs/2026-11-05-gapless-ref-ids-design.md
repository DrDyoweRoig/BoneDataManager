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
| Entrades esborrades | No es renumeren. El seu número pot tornar a aparèixer en una entrada viva (no hi ha conflicte: l'índex únic només mira les vives). Si una entrada esborrada es recupera després d'una compactació, rep un número nou (§4). |
| Mòbil | Cap canvi de flux: ja desa només amb connexió. Rep els números nous en sincronitzar. |
| Bases de dades locals (sense núvol) | El botó també hi és i compacta en local. No tenen IDs provisionals: sempre tenen número. |

## 3. IDs provisionals (escriptori sense connexió)

**Local**
- Les entrades provisionals es guarden amb `number` **negatiu** (-1, -2, …). `refId` = `<prefix>TEMP-<n>`. El comptador és una columna nova `meta.tempNext`, que comença a 1 i no es reinicia mai en aquell fitxer, per evitar repetir TEMP en etiquetes.
- `createEntriesFromBlock` es substitueix per `createProvisional`. Mai falla per falta de números, així que `NoNumbersLeft` desapareix.
- El formulari mostra "will be saved as HOL-TEMP-4 (provisional)" quan no hi ha connexió.
- A la taula i a la fitxa, un ID provisional es veu en cursiva amb una etiqueta "Provisional".

**En sincronitzar** (dins de `_round`, abans del push), per a cada grup TEMP pendent, del més antic al més nou:
1. Si totes les entrades del grup estan esborrades i cap no s'ha pujat mai (`baseVersion = 0`), s'eliminen del fitxer local i no es reclama cap número (crear i esborrar sense connexió no deixa salts).
2. Es crida la RPC `claim_number(db, device, temp, ids)` amb els ids de **totes** les entrades del grup (també les esborrades). Es reclama a **cada** ronda mentre el grup sigui provisional: tornar a demanar retorna el número actual del grup, també després d'una compactació.
3. Cada entrada del grup es puja (`push_entry`) com a **còpia** amb el número real, `refId` recalculat i el TEMP afegit a Previous Ref IDs. Al fitxer local l'entrada continua sent provisional.
4. Només quan el servidor ha acceptat **tot** el grup, una transacció local passa totes les entrades amb aquell número negatiu (també les esborrades) al número real i guarda `HOL-TEMP-n` a Previous Ref IDs. Si alguna entrada queda pendent (conflicte, refús), el grup continua provisional i es torna a provar a la ronda següent.
5. Després es pugen les altres entrades pendents (números reals).
- Si un push respon `stale` (els números han canviat mentrestant), el dispositiu pren la numeració del servidor (§4) i s'acaben els pujaments d'aquella ronda; la ronda següent ho torna a provar.
- Mòbil: desa només amb connexió. Si el push respon `stale`, pren la numeració nova i ho torna a provar **una** vegada; si torna a ser `stale`, l'acció es refusa ("Please try again") i el canvi es desfà.

**Identificador de dispositiu:** cada vegada que un fitxer s'enllaça al núvol (obrir una base de dades del núvol, crear-la, "Move to cloud") rep un `device_id` propi: `<id de la instal·lació>:<uuid nou>`. La migració local a v4 també en dona un de nou als fitxers enllaçats. Així dues còpies de la mateixa base de dades en un mateix PC (o un fitxer copiat i tornat a obrir) no comparteixen reclamacions.

**Servidor**
- Taula nova `temp_claims(database_id, device_id, temp_number, number, ids)` amb clau primària `(database_id, device_id, temp_number)`. `ids` són els ids de les entrades del grup.
- `claim_number(db, device, temp, ids)`:
  - Si la reclamació ja existeix, retorna el mateix número. Però si la reclamació guardada i la nova tenen `ids` i no en comparteixen cap, és una altra còpia del fitxer amb el mateix TEMP (un altre espècimen): error `Claim key reused by a different copy`, mai el número de l'altra.
  - Si algun dels `ids` ja és al servidor **i és viu** (un intent en línia que va arribar però la resposta es va perdre), retorna el número d'aquella fila i no en gasta cap de nou. El número d'una fila esborrada no es reutilitza, perquè després d'una compactació pot ser d'un altre espècimen.
  - Si no, pren `next_number` i l'incrementa en 1.
  - El TEMP que l'usuari va veure el calcula el servidor a partir del prefix (`HOL` → `HOL-TEMP-3`, `MAS-` → `MAS-TEMP-3`, sense prefix → `TEMP-3`) i l'afegeix a `previous_ref_ids` de les files del grup que ja hi són (actualitza `updated_at`, no `version`).
- `push_entry` passa a tenir un paràmetre més, `epoch` (el `numbering_epoch` que coneix el dispositiu). Canviar la signatura és intencionat: les apps antigues, que la criden sense `epoch`, reben un error del servidor i no poden pujar números que podrien estar desfasats (§7).
- Una fila nova és vàlida si el seu número és a `temp_claims`, o si s'afegeix a un Ref ID que té alguna fila **viva** (un número que només tenen files esborrades no és un Ref ID al qual afegir dents), **i** `epoch` és l'actual. Si `epoch` és antic, retorna `stale`.
- En inserir una fila, el servidor calcula el `ref_id` a partir del número (no es fia del dispositiu) i accepta `previous_ref_ids` del dispositiu (porta el TEMP), si és una llista. En actualitzar-la no toca número, `ref_id` ni `previous_ref_ids`, excepte en recuperar una fila esborrada (§4).
- `create_database` ("Move to cloud") també puja `previous_ref_ids`.
- `reserve_block` i `id_blocks` deixen de fer-se servir. La migració 004 esborra `reserve_block`; la taula `id_blocks` es buida i s'esborra.

## 4. Compactar (botó "Close Ref ID gaps")

**Previsualització:** abans d'aplicar, un diàleg mostra quantes entrades canviaran i una llista `HOL0057 → HOL0007`. Si no hi ha salts: "No gaps — nothing to change."

**Servidor:** nova RPC `compact_ref_ids(db)`, només per a l'Owner:
1. Bloqueja la fila de `databases` (`for update`). Mentrestant, qualsevol `create_entries`/`claim_number` espera.
2. Calcula el número nou de cada número viu diferent, en ordre: 1, 2, 3…
3. Aplica els canvis en dues fases (primer a negatiu, després al definitiu) per no xocar amb l'índex únic. A cada fila que canvia, l'ID antic s'afegeix a `previous_ref_ids` i s'actualitza `updated_at`. **No** s'incrementa `version`, perquè renumerar no ha de crear conflictes amb edicions pendents.
4. Números vius = els de les files vives + els dels claims **pendents**. Un claim és pendent mentre cap de les seves entrades no és al servidor amb el número del claim (sense `ids`: mentre cap fila no té el seu número). Així un grup reclamat però encara no pujat no perd el seu número, encara que una fila esborrada tingui aquell número.
5. Els claims que no són pendents ni tenen un número viu (les seves files pujades s'han esborrat) s'**esborren**: si la resta del grup torna a reclamar, rep un número nou i no el que la compactació pot haver donat a un altre espècimen. Tots els altres claims es renumeren amb el mateix mapa, perquè un claim repetit retorni el número **actual** del grup.
6. `next_number` = nombre de números vius + 1. Incrementa `databases.numbering_epoch` (només si hi ha canvis).
7. Retorna la llista de canvis.

**Entrades esborrades i recuperades:** `entries.deleted_epoch` guarda el `numbering_epoch` en què es va esborrar la fila (null mentre és viva). Si un `push_entry` recupera una fila esborrada (p. ex. "keep mine" en un conflicte amb una fila esborrada en un altre lloc) i `deleted_epoch` no és l'epoch actual, és que hi ha hagut una compactació des de l'esborrat i el seu número pot ser d'un altre espècimen: rep un número nou de `next_number`, l'ID antic va a Previous Ref IDs i `updated_at` s'actualitza. Els dispositius ho reben en sincronitzar (el número de la fila canvia). Les files esborrades abans de la migració 004 compten com esborrades a l'epoch 0.

**Altres dispositius:** quan detecten que `numbering_epoch` ha canviat (o una fila descarregada té un número diferent del local, o la ronda anterior va deixar files enrere), prenen la numeració del servidor en una sola transacció local:
1. Primer, els esborrats fets en altres llocs: una fila esborrada al servidor i sense canvis aquí es marca esborrada (el seu número pot passar a una altra fila). Si té una edició pendent, es converteix en conflicte.
2. Les files que el servidor coneix reben el seu número, `ref_id` i `previous_ref_ids`, també les que tenen edicions pendents (les edicions es conserven). Les files provisionals (número negatiu) no es toquen mai: només el seu claim els dona número.
3. Les files que encara no s'han pujat mai segueixen el número nou del seu grup. Si el grup ja no té cap fila viva al servidor, o les files que compartien el seu número ara són en llocs diferents (no se sap quin és el seu espècimen), passen a ser provisionals (un TEMP nou, amb l'ID anterior a Previous Ref IDs) i reclamen un número propi. Mai es deixen en un número que pot ser d'un altre espècimen.
4. Una fila coneguda pel servidor que xocaria (mateix número i mateixa dent) amb una altra fila viva local es queda on és; es torna a provar a la ronda següent (el conflicte pendent es resol primer).
La reescriptura és en dues fases per no xocar amb l'índex únic, i no canvia `version` ni l'estat de sincronització.

**Local (sense núvol):** el mateix algorisme en una transacció de drift. `meta.nextNumber` = màxim + 1.

**Seguretat:** abans de compactar es fa un backup local automàtic (el servei de backup existent). Si el backup falla, no es renumera res i es diu ("Couldn't make a backup, so nothing was renumbered"). Després de compactar, un missatge diu quants Ref IDs han canviat ("Renumbered N Ref IDs.").

**Desenllaçar i restaurar:** una còpia restaurada d'un backup d'una base de dades del núvol queda local (sense enllaç, sense pendents ni conflictes). Els grups TEMP que tenia reben números reals locals a partir del més gran que hi hagi + 1 (ningú més els numerarà), i l'ID TEMP queda a Previous Ref IDs.

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
- Un número es converteix només si **cap** fila amb aquell número està sincronitzada o s'ha pujat abans (`baseVersion > 0`). Si n'hi ha alguna, el número és un Ref ID del servidor i les dents afegides sense connexió ("Add teeth to HOL0042") s'hi queden.
- Els fitxers enllaçats al núvol reben un `device_id` nou (§3), dins de la mateixa transacció.
- Servidor: `entries.deleted_epoch int` (null mentre la fila és viva); les files ja esborrades reben 0.

## 6. Excel i fitxa

- Columna nova **Previous Ref IDs** just després de Ref ID, amb els valors separats per `; `. Si cap entrada en té, la columna es manté igualment, perquè l'Excel en viu tingui sempre les mateixes columnes.
- La fitxa de l'entrada mostra "Previously: HOL-TEMP-1, HOL0057" sota el Ref ID.

## 7. Errors i casos límit

- **Compactar mentre un altre PC és offline amb TEMPs:** cap problema. Els seus TEMPs reclamaran números després de `next_number`.
- **Apps antigues:** després d'executar la migració 004, una app sense actualitzar no pot pujar res (signatura nova de `push_entry`, `reserve_block` ja no existeix). Mostra un error del servidor, no un missatge amable; els seus canvis queden pendents en aquell dispositiu i no es perden. En actualitzar l'app, la migració local converteix les entrades offline del bloc en TEMP (§5) i reben un número nou sense xocar amb ningú.
- **Una app antiga després d'una compactació:** no s'ha de fer servir. Continua descarregant canvis, però no sap renumerar: mostra Ref IDs antics i, quan una fila renumerada xoca amb una de local, pot marcar com a esborrades files que són vives (només en aquell dispositiu). S'ha d'actualitzar abans de tornar-la a fer servir.
- **Ordre recomanat:** executar 004 i actualitzar l'app a tots els PCs i mòbils alhora, deixar que sincronitzin, i després prémer Close Ref ID gaps.
- **Una còpia del fitxer obert en un altre PC o carpeta:** si encara té el `device_id` de l'original i fa servir el mateix TEMP per a un altre espècimen, `claim_number` ho refusa (§3); aquell grup no es puja fins que es resol a mà.
- **Afegir dents a un grup mentre un altre PC compacta:** el push arriba amb `epoch` antic → `stale` → el dispositiu actualitza els números i torna a provar amb el número nou del grup.
- **Resposta del claim perduda:** el següent intent retorna el mateix número (clau a `temp_claims`).
- **Un grup TEMP pujat a mitges i la part pujada esborrada en un altre lloc:** la compactació esborra aquell claim (§4) i la resta del grup rep un número nou.
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
