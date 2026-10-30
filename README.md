# Bone Data Manager

Desktop and Android app for recording osteological and dental observations — one row per bone or
tooth, each with its own reference ID — and exporting them to Excel. Built for bioarchaeology and
human osteology teams.

- **Bones and teeth.** 120 bones grouped by region, with Left / Right / Unknown for paired
  elements. Teeth by dentition, jaw, side and type (`I1 I2 C P3 P4 M1 M2 M3`, deciduous
  `di1 di2 dc dm1 dm2`), entered several at a time.
- **Reference IDs.** Automatic, with an optional prefix (`MAS-0001`). Teeth of one specimen can
  share a single ID ("Give all selected teeth the same Ref ID?").
- **Your own fields.** Single / multiple choice, yes/no, text, number and date layers, plus
  ready-made dental layers (wear, caries, calculus, enamel hypoplasia…).
- **Excel.** A live `.xlsx` next to each database, updated as you work, plus export and
  automatic backups.
- **Teams (optional).** Each team connects **its own** free Supabase server: shared databases,
  owner / editor / viewer roles, real-time sync between computers and phones, offline work on
  desktop with conflict resolution. Your data stays on your server.

The interface is in English.

## Download

Get the latest version from **[Releases](../../releases)**:

| File | For |
|---|---|
| `BoneDataManager-windows.zip` | Windows 10/11 — unzip and run `bone_data_manager.exe` |
| `BoneDataManager.apk` | Android 7.0+ — open on the phone and allow installing it |

Windows and Android show a warning for apps that are not code-signed or not from Google Play;
choose *More info → Run anyway* / *Install anyway*.

On its own the app works **locally** on one computer. To share databases with a team, follow
**[docs/SETUP.md](docs/SETUP.md)** (about 15 minutes, no programming).

## Build from source

Requirements: [Flutter](https://flutter.dev) (stable), Visual Studio Build Tools with the C++
workload (Windows), Android SDK (Android).

```bash
cd app
flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter test
flutter build windows        # or: flutter build apk --release
```

A build made without `--dart-define-from-file=cloud_config.json` is the public edition: no
built-in server, each team connects its own. `tools/build_all.ps1` builds both editions.

Server setup lives in `supabase/migrations/`; `python supabase/build_setup.py` regenerates the
single setup script bundled in the app (`app/assets/supabase_setup.sql`).

## Cite

If you use Bone Data Manager in research, please cite it — see [`CITATION.cff`](CITATION.cff)
(GitHub's *Cite this repository* button gives APA and BibTeX).

## License

[MIT](LICENSE) © 2026 Albert Epitíe Dyowe Roig
