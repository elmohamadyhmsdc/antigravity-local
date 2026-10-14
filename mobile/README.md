# Antigravity Mobile

Flutter (Android) phone client for the Antigravity Local GPU server. **All user data lives on the phone**
(encrypted SQLite - SQLCipher - with the key in the Android Keystore); the Windows PC only computes.

Plan: [`docs/plans/2026-10-11-mobile-app-plan.md`](../docs/plans/2026-10-11-mobile-app-plan.md).
Contract with the PC: [`the app/mobile_api/contract/openapi.yaml`](../the%20app/mobile_api/contract/openapi.yaml)
(golden fixtures in `contract/fixtures/` are parsed by both the server tests and `test/data/dto_test.dart`).

## Status

| Phase | State |
|---|---|
| P0 Foundations | done |
| P1 Server core + pairing | done - S01 Welcome/Pair (QR, tapped link, typed address + fingerprint check), S02 Permissions, S03 Home (PC status chip, library stats from the local DB), "Detect faces in a photo" (the end-to-end check against the PC) |
| P2 Library & People | built - photo scan with foreground service, People / Person / Face picker / Review / Merge, photo viewer with boxes, Settings (grouping strictness, quality gate), backup & restore; awaiting verification on the phone |

## Layout

```
lib/
  app.dart main.dart providers.dart      router/session wiring, start-up (opens the encrypted DB or shows an error screen)
  core/                                  router (with the agmobile:// deep link), theme
  data/db/                               Drift schema (tables.dart), migrations (app_database.dart), SQLCipher opening
  data/api/                              pinned Dio client, DTOs parsed from the contract, pairing payload, LAN-only host check
  data/secrets/ data/repositories/       Keystore wrapper, which PC we are paired with (token in Keystore, rest in the DB)
  data/platform/                         permissions / photo picker / device name behind small interfaces
  data/{files,index,media}/              FileStore (relative crop paths), EmbeddingIndex (isolate), MediaStore access (photo_manager)
  data/repositories/                     library queue, people + manual corrections, review plan, media queries, typed settings
  domain/{scan,grouping,backup}/         ScanEngine + PhotoResultStore, grouping rounds + PlanApplier, .agbackup export/restore
  features/{onboarding,home,analyze}/    screens S01-S03 and the detection check
  features/{library,media,people,review,merge,scan,settings,backup}/   S04-S11, S24, S26
  l10n/app_en.arb                        all user-visible strings
```

## Commands

```
flutter pub get
flutter analyze
flutter test                              # DB (SQLCipher on the host), pinned HTTPS against a local server, DTOs vs fixtures, widgets
dart run build_runner build               # after editing lib/data/db/tables.dart (app_database.g.dart is committed)
flutter gen-l10n                          # after editing lib/l10n/app_en.arb
flutter build apk --debug                 # needs the Android SDK licences accepted
```

## Trying it against the PC

1. PC: `the app/run_mobile_api.bat` (opens `http://127.0.0.1:8444/pair`, which shows the QR, code and certificate fingerprint).
2. Phone on the same Wi-Fi: Scan QR code (or Enter address manually and compare the fingerprint shown with the PC's page).
3. Home shows the PC as connected; "Detect faces in a photo" sends one downscaled photo and draws what the PC found.

USB alternative without any firewall rule: `adb reverse tcp:8443 tcp:8443`, start the server with `--bind 127.0.0.1`,
pair with address `127.0.0.1`. The Android emulator reaches the PC at `10.0.2.2`.

## Security notes

- Certificate pinning: the client trusts exactly one certificate (SHA-256 from the QR / confirmed by the user); a wrong pin aborts the TLS handshake before the bearer token is sent.
- Pairing only accepts private-network addresses (192.168.x.x, 10.x, 172.16-31.x, link-local, `.local`, loopback).
- A tapped `agmobile://pair` link never pairs silently; it shows the address and asks.
- `allowBackup=false` plus data-extraction rules exclude everything from Android backups. Cleartext traffic is disabled.
