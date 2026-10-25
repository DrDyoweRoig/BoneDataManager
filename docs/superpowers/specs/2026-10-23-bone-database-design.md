# Bone Data Manager — Especificació de disseny

**Data:** 2026-10-23
**Estat:** Pendent de revisió

## 1. Objectiu

Aplicació per crear i omplir bases de dades d'observacions d'ossos humans, amb èmfasi en les dents. Interfície moderna i intuïtiva, **tota en anglès**. Hi ha una app d'escriptori i una app mòbil que comparteixen les dades al núvol en temps real. L'exportació es fa a Excel.

**Criteris d'èxit**
- Crear una base de dades nova (ossos, layers, prefix) en pocs minuts sense manual.
- Cada entrada rep un Ref ID únic i automàtic amb prefix.
- Diversos ordinadors i mòbils treballen sobre la mateixa base de dades i veuen els canvis a l'instant.
- L'escriptori pot seguir treballant sense connexió i sincronitzar després.
- L'Excel exportat és net i directament analitzable.

## 2. Decisions preses

| Tema | Decisió |
|---|---|
| Unitat d'entrada | **1 entrada = 1 os o 1 dent**, amb Ref ID propi. L'individu és un layer opcional. |
| Excel | Font de veritat = núvol. Excel = **exportació** sota demanda. |
| Sense connexió | Escriptori: pot **crear i editar** entrades offline; IDs de blocs reservats; avís efímer. Mòbil: sempre en línia. |
| Usuaris | Comptes amb correu + rols **Owner / Editor / Viewer** + **Observer ID** en començar a editar. |
| App mòbil | Introduir i consultar dades + exportar. **No** crea ni modifica l'estructura. |
| Catàleg d'ossos | **Os sencer** (sense porcions). |
| Selecció de dents | **Multiple choice** (Jaw × Side × Tooth type), sense odontograma. |
| Nomenclatura dental | Permanents `I1 I2 C P3 P4 M1 M2 M3`; deciduals `di1 di2 dc dm1 dm2`. Sense numeració (ni FDI ni Universal). |
| Layers d'opcions | Es mostren com a **botons per marcar**, mai com a desplegables. |
| Estat marcat | Fons de color sòlid + text blanc + icona ✓. Clarament diferent del no marcat. |

## 3. Tecnologia

| Peça | Tecnologia |
|---|---|
| App escriptori (Windows; macOS possible) i mòbil (Android, iOS) | **Flutter (Dart)**, un sol codi |
| Núvol | **Supabase**: PostgreSQL + Auth + Realtime |
| Base de dades local (escriptori) | **SQLite** via Drift |
| Generació Excel | Paquet Dart `excel` |
| Gestió d'estat | Riverpod |

## 4. Arquitectura

```
 Desktop app (Flutter)          Mobile app (Flutter)
 ├─ UI                          ├─ UI
 ├─ Repository ─┬─ SQLite       └─ Repository ── Supabase
 │              └─ Sync engine ──────────┐
 └─ Backup service                       ▼
                                 Supabase (Postgres, Auth, Realtime)
```

Mòduls del codi (cada un amb una responsabilitat clara):

| Mòdul | Responsabilitat |
|---|---|
| `catalog` | Llista fixa de regions, ossos (amb indicador de parell) i dents. Dades estàtiques. |
| `schema` | Definició d'una base de dades: ossos seleccionats, layers, prefix. Validació. |
| `ids` | Formatar Ref IDs, gestionar comptador i blocs reservats. |
| `teeth` | Expandir una selecció Jaw × Side × Type en llista d'entrades. |
| `entries` | CRUD d'entrades, a través del repository. |
| `sync` | Cua de canvis offline, pujada, descàrrega, detecció de conflictes. |
| `export` | Generar `.xlsx` a partir de schema + entrades. |
| `backup` | Còpies periòdiques i restauració. |
| `auth` | Login, membres, rols, Observer ID. |
| `ui` | Pantalles i components (botons de selecció, toasts…). |

## 5. Model de dades

**`databases`**: `id`, `name`, `prefix` (p. ex. `MAS-`), `digits` (per defecte 4), `next_number`, `selected_elements` (llista d'ossos/regions), `created_by`, `created_at`.

**`members`**: `database_id`, `user_id`, `role` (`owner` | `editor` | `viewer`).

**`layers`**: `id`, `database_id`, `name`, `type` (`single_choice` | `multi_choice` | `yes_no` | `short_text` | `number` | `date`), `options` (llista, per als de tipus choice), `applies_to` (`all` | llista d'ossos | `teeth`), `order`.

**`entries`**:
`id` (UUID intern), `database_id`, `ref_id` (únic per base de dades), `element` (nom de l'os o `Tooth`), `region`, `dentition` (`Permanent` | `Deciduous` | null), `tooth_type` (null si no és dent), `jaw` (`Upper` | `Lower` | null), `side` (`Left` | `Right` | null), `values` (JSON: `layer_id → valor`), `created_by` (Observer ID), `created_at`, `modified_by`, `modified_at`, `version` (enter, per detectar conflictes), `deleted` (bool, esborrat lògic per sincronitzar).

**`id_blocks`**: `database_id`, `device_id`, `start`, `end`, `next`. Cada escriptori té sempre un bloc reservat de **50** números per treballar offline.

## 6. Ref IDs

- Format: `prefix` + número amb zeros a l'esquerra fins a `digits` → `MAS-0001`. El prefix és opcional.
- **En línia:** el número l'assigna una funció de Postgres amb bloqueig de fila → mai es repeteix.
- **Fora de línia (escriptori):** s'agafa el següent número del bloc reservat del dispositiu. Quan torna la connexió, si el bloc s'ha gastat més de la meitat, se'n reserva un de nou.
- Conseqüència acceptada: la numeració pot tenir salts.
- Un Ref ID mai canvia un cop assignat i mai es reutilitza (ni després d'esborrar).

## 7. Catàleg d'ossos

Regions i ossos (P = parell, demana Side). Opció **All body** marca-ho tot.

- **Skull:** Frontal, Parietal (P), Occipital, Temporal (P), Sphenoid, Ethmoid, Zygomatic (P), Maxilla (P), Nasal (P), Lacrimal (P), Palatine (P), Vomer, Inferior nasal concha (P), Malleus (P), Incus (P), Stapes (P), Mandible, Hyoid
- **Teeth:** vegeu secció 8
- **Vertebral column:** C1–C7, T1–T12, L1–L5, Sacrum, Coccyx
- **Thorax:** Sternum, Ribs 1–12 (P)
- **Upper limb:** Clavicle (P), Scapula (P), Humerus (P), Radius (P), Ulna (P), Scaphoid, Lunate, Triquetral, Pisiform, Trapezium, Trapezoid, Capitate, Hamate (tots P), Metacarpals 1–5 (P), Hand phalanges proximal 1–5 / intermediate 2–5 / distal 1–5 (P)
- **Pelvis:** Os coxae (P)
- **Lower limb:** Femur (P), Patella (P), Tibia (P), Fibula (P), Talus, Calcaneus, Navicular, Cuboid, Medial / Intermediate / Lateral cuneiform (tots P), Metatarsals 1–5 (P), Foot phalanges proximal 1–5 / intermediate 2–5 / distal 1–5 (P)

Cada regió es pot marcar sencera o desplegar-se per marcar ossos concrets.

## 8. Mòdul de dents

Pantalla de selecció (dins *New entry*, si Teeth està a la base de dades):

1. **Dentition:** Permanent / Deciduous (un de dos)
2. **Jaw:** Upper, Lower (multi)
3. **Side:** Right, Left (multi)
4. **Tooth type:** `I1 I2 C P3 P4 M1 M2 M3` o `di1 di2 dc dm1 dm2` (multi)
5. **Vista prèvia:** "N entries will be created" + llista amb el Ref ID provisional de cada una
6. Layers comuns (s'omplen una vegada i s'apliquen a totes)
7. **Create** → N entrades amb IDs consecutius

**Plantilles de layers dentals** (al wizard, **totes desactivades per defecte**):

| Layer | Tipus | Opcions |
|---|---|---|
| Status | Single choice | In socket · Loose · Lost antemortem · Lost postmortem · Unerupted · Congenitally absent |
| Wear | Single choice | Smith 1–8 |
| Caries | Multi choice | Occlusal · Interproximal · Buccal · Lingual · Root · None |
| Calculus | Single choice | Brothwell 0–3 |
| Enamel hypoplasia | Yes/No | — |
| Periapical lesion | Yes/No | — |
| Development stage | Single choice | Moorrees stages |
| Notes | Short text | — |

Un cop activades, s'editen com qualsevol altre layer.

## 9. Pantalles

1. **Login** — correu + contrasenya.
2. **Home** — *Create a new database* (només escriptori), *Open an existing database*, llista de recents amb icona local/núvol.
3. **Create wizard** (escriptori), barra de passos:
   1. Name
   2. Reference ID — prefix + dígits, vista prèvia `MAS-0001`
   3. Bones — regions + *All body*, desplegables
   4. Layers — afegir/editar/ordenar; plantilles dentals si Teeth
   5. Members — convidar per correu i rol
   6. Review → Create
4. **Observer ID** — diàleg en obrir per editar; recorda l'últim valor.
5. **Workspace** — taula d'entrades, cerca, filtres (Element, Side, Jaw, Tooth type, layers), indicador de sincronització, Observer actual. Botons: *New entry*, *Export Excel*, *Structure* (només Owner, només escriptori).
6. **New / Edit entry**
   - Os: llista amb cerca (només ossos seleccionats). Si és parell → botons Left / Right.
   - Dent: mòdul de la secció 8.
   - Layers: formulari amb scroll vertical; botó **Save** fix a baix.
7. **Structure** — editar layers, ossos i membres després de crear.
8. **Settings** — carpeta i freqüència de backup, Restore, tancar sessió.

**Components de selecció:** tots els layers de tipus choice i Yes/No són botons. Estat marcat = fons color principal sòlid + text blanc + ✓. Els botons fan salt de línia quan no caben.

## 10. Sincronització i offline

- **Mòbil:** llegeix i escriu directament a Supabase; subscripció Realtime per veure canvis d'altres. Si perd connexió, mostra avís i no deixa desar fins que torni.
- **Escriptori:** escriu sempre a SQLite; el *sync engine* puja la cua de canvis i aplica els canvis remots (Realtime quan hi ha connexió).
- **Toasts:**
  - En perdre connexió: *"You're offline. New entries will use this device's reserved IDs, so numbering may have gaps. Changes will sync automatically when you're back online."*
  - En recuperar-la: *"Back online — N entries synced."*
- **Conflictes:** cada entrada té `version`. Si en pujar la versió remota és més nova que la que s'havia editat, es mostra un diàleg amb les dues versions camp a camp i l'usuari tria quina es queda.

## 11. Rols i traçabilitat

| Rol | Pot |
|---|---|
| Owner | Tot: estructura, membres, entrades, esborrar base de dades |
| Editor | Crear, editar i esborrar entrades; exportar |
| Viewer | Consultar i exportar |

Els permisos s'apliquen al servidor (Row Level Security de Supabase), no només a la interfície. Cada entrada guarda `created_by/at` i `modified_by/at` amb l'Observer ID.

## 12. Export Excel

- **Full "Entries":** una fila per entrada. Columnes: `Ref ID · Element · Region · Dentition · Tooth type · Jaw · Side · [layers en ordre] · Created by · Created at · Modified by · Modified at`.
  - Multi choice: valors separats per `; `.
  - Camps no aplicables: cel·la buida.
  - Capçalera fixada i autofiltre activat.
- **Full "Info":** nom de la base de dades, prefix, data i autor de l'exportació, llista de layers amb tipus i opcions.
- Nom del fitxer: `<nom-base-de-dades>_<AAAA-MM-DD>.xlsx`.

## 13. Backup (escriptori)

- Carpeta configurable. Còpia cada **15 minuts** (configurable) i en tancar l'app.
- Cada còpia: `.sqlite` (restaurable) + `.xlsx` (llegible).
- Es conserven les **20** més recents.
- *Restore from backup*: tria una còpia i la recupera com a base de dades local; si la base de dades és del núvol, es pujaran les entrades que faltin.

## 14. Proves

- **Unitàries:** format de Ref ID; assignació amb blocs offline; expansió Jaw × Side × Type; validació de layers; generació d'Excel (columnes i valors).
- **Integració:** sync escriptori ↔ Supabase (offline → online, conflicte), permisos per rol.
- **Manuals:** escriptori i mòbil alhora sobre la mateixa base de dades.

## 15. Fora d'abast (possibles extres futurs)

- Historial de canvis camp a camp per entrada.
- Full de càlcul en línia (Google Sheets / OneDrive) actualitzat automàticament.
- Porcions d'os (epífisi, diàfisi…).
- Odontograma visual.
- Crear o modificar l'estructura des del mòbil.

## 16. Canvis acordats després del Pla 1 (2026-10-23 → 2026-10-25)

**Ja implementats al Pla 1:**
- Side i Jaw tenen l'opció **Unknown** (no marcada per defecte; cal triar sempre).
- Backups: una carpeta per base de dades, `Backups/<nom>/<nom> AAAA-MM-DD HH-mm.sqlite|.xlsx`.
- En crear una base de dades es tria la **carpeta**. Al costat de `<nom>.sqlite` hi ha sempre `<nom>.xlsx`, reescrit automàticament després de cada canvi, amb botó **Update Excel** i avís si el fitxer està obert a Excel.
- Una entrada d'un element que s'ha tret de la base de dades continua sent editable; en editar, es conserven els valors de layers que ja no s'apliquen.

**Decisions per al Pla 2 (núvol):**
- Backend: **Supabase**, projecte a una regió **europea**. L'app només coneix la URL i la clau *anon/publishable*; mai la clau *service_role*.
- Les bases de dades locals es poden pujar amb **Move to cloud** (a Structure): es pugen definició i entrades amb els mateixos Ref IDs i el comptador; el fitxer local queda enllaçat al núvol.
- El wizard permet triar **Local** o **Cloud** (Cloud només amb sessió iniciada) i, per a Cloud, afegir membres.
- **Membres per correu:** l'Owner escriu correu + rol. Si la persona no té compte, la base de dades li apareix quan es registra amb aquest correu. L'app no envia correus propis.
- A l'escriptori, una base de dades del núvol té sempre una **còpia local** (SQLite a la carpeta triada) que és la que fa servir la interfície; l'Excel automàtic i els backups funcionen igual que en local.
- Les bases de dades locals continuen funcionant sense compte.
