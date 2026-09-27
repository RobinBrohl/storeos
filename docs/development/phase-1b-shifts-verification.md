# P1b.3 – Prüfnachweis Schichten und Employee Home

Stand: 2026-09-27. Ausgangspunkt `922a45f`, ausschließlich der freigegebene
[Schicht-Slice](phase-1b-shifts.md). Keine Guided-Work-, Completion-, Offline- oder
Plugin-Erweiterung. Kein Commit automatisch erstellt.

Dieser Nachweis beschreibt den Stand vor dem anschließenden Review. Dessen
Korrekturen und finale Testergebnisse stehen im [Reviewbericht](phase-1b-shifts-review-2026-09-27.md).

## Finale automatisierte Prüfung

Vollständiger Lauf von `scripts/dev.ps1 check` mit gesetztem
`STOREOS_TEST_DATABASE`, echter PostgreSQL-Datenbank und getrennten Testschemas.
Alle Formatter und Dart-/Flutter-Analyzer ohne Befund; keine übersprungenen DB-Tests.

| Paket | Bestanden |
| --- | ---: |
| API-Verträge | 20 |
| Server einschließlich PostgreSQL/HTTP | 56 |
| Flutter-Client | 77 |
| Design-System | 2 |
| Gesamt | **155** |

`docker compose config --quiet`, Flutter-Web-Release mit lokalen CanvasKit-
Ressourcen und `git diff --check` erfolgreich. Alle 89 internen OpenAPI-Referenzen
aufgelöst; bestehende Routen und Schemaobjekte semantisch unverändert.
Lokales vollständiges Laufprotokoll: `.local/shifts-check-final.log`.

Zusätzliche Prüffälle umfassen:

- Zeitpunkte mit Offset/UTC, ungültige Kalenderwerte, Mitternacht und Zeitumstellung,
  unterstützte UTC-Jahresgrenzen, eindeutige Auswahl und zehn Vorlagen als Grenze.
- Entwurf, Versionskonflikt, explizite Revision, Veröffentlichung und unveränderlicher
  Snapshot auch nach Freigabe einer neueren Vorlage und nach Serverneustart.
- Stabile Anlage-ID, parallele Bearbeitungen/Veröffentlichungen, gemeinsame Audit-
  Korrelation und keine doppelte Instanz oder Auditwirkung bei Wiederholung.
- Rollback bei Erzeugungsfehler nach bereits angelegter erster Instanz sowie bei
  beiden Auditpunkten der Veröffentlichung; Anlage-/Bearbeitungs-Auditfehler.
- Überschneidung einschließlich konkurrierender Veröffentlichungen, angrenzende
  Schichten, inaktive Mitarbeiter, falscher Standort und unveröffentlichte Revision.
- Rollen, gültige Plugin-Tokens, fremde Company, andere Mitarbeiter, direkte
  Aufgaben-IDs, Linkwiderruf und konkurrierende Mitarbeiterdeaktivierung.
- 51 Schichten über zwei begrenzte Seiten ohne Lücken/Dubletten; keine
  Anleitungsinhalte in den Listen.
- Populiertes Upgrade 0005 → 0006 mit unveränderten Accounts, Mitarbeitern,
  Vorlagenrevisionen und Audit; wiederholte Migration ohne weitere Änderungen.
- Flutter: Antwortverlust bei Anlage/Bearbeitung/Veröffentlichung und unverändertem
  Speichern, unbekannte Ergebnisse mit stabiler ID, Konflikte ohne automatisches
  Überschreiben, Sitzungswechsel, fehlendes Eigenprofil und fehlgeschlagene
  Listenaktualisierung nach bereits bestätigter Anlage.
- Widgets: UTC-Formular, Veröffentlichungswarnung, eigene Anleitung und bewusst
  fehlende Ausführungs-/Abschlussaktionen.

## Browser-Smoke und Betriebsnachweis

Der Flutter-Web-Release wurde gegen einen isolierten Server auf Port 8086 und
Client auf Port 8087 geprüft. Die reguläre Entwicklungsdatenbank wurde nicht mit
Smoke-Datensätzen befüllt.

1. Testadministrator meldet sich an und öffnet Schichten.
2. Aktiven Mitarbeiter und UTC-Zeiten auswählen, konkrete veröffentlichte Revision
   hinzufügen, Entwurf speichern. Bestätigter Entwurf erscheint in der Liste.
3. Warnhinweis bestätigen und veröffentlichen: Version 2, eine Aufgabeninstanz.
4. Abmelden, als verknüpfter Employee anmelden, unter Meine Arbeit die Schicht
   öffnen und den gespeicherten Anleitungstext lesen.
5. Finalen Build nach den UI-/Randfallkorrekturen neu laden und Mitarbeiteransicht
   erneut prüfen. Screenshot: `.local/shifts-browser-smoke.png`.

Verschlüsseltes Backup der isolierten `storeos_shifts_smoke_test`-Datenbank mit
bestehendem Backup-Verfahren erstellt. Restore in die neue, isolierte Datenbank
`storeos_restore_shifts_20260927`: bestehende Restoreprüfung erfolgreich,
Sitzungen widerrufen, Runtime-CONNECT gesperrt. Vollständige kanonische Datensatz-
Checksummen von `shifts`, `shift_template_selections`, `task_instances`,
`task_template_revisions`, `employees`, `account_employee_links` und `audit_entries`
stimmen zwischen Quelle und Restore überein. Das Restore bleibt zur Inspektion
isoliert bestehen; das verschlüsselte Testbackup liegt unter `.local/shifts-backup/`.

## Grenzen

Nur lesende Aufgabeninstanzen, maximal zehn pro Veröffentlichung; keine Änderung
oder Stornierung veröffentlichter Schichten. UTC statt Standortkalender. Keine
Offline-Schreibqueue oder Zentralsynchronisation. Company-Lock bleibt erhalten;
kein Lasttest großer Installationen. Vorhandene Mitarbeiterauswahl übernimmt die
bestehende Listenbegrenzung. DB-Owner liegen außerhalb des Runtime-/Auditschutzes.
Native Clients wurden nicht abgenommen. Ungespeicherte Eingaben leben nur im
Arbeitsspeicher. Die reguläre laufende Entwicklungsinstanz wurde für diese Tests
nicht umgestellt; Upgrade/Neustart erfolgt gemäß README.

## Geänderte Dateien

- `README.md`
- `apps/client_flutter/lib/src/app/storeos_app.dart`
- `apps/client_flutter/lib/src/application/shift_controller.dart`
- `apps/client_flutter/lib/src/ui/platform_home_screen.dart`
- `apps/client_flutter/lib/src/ui/shift_section.dart`
- `apps/client_flutter/test/shift_test.dart`
- `apps/server/lib/src/application/shift_application.dart`
- `apps/server/lib/src/http/platform_app.dart`
- `apps/server/lib/src/http/shift_routes.dart`
- `apps/server/lib/src/infrastructure/migration_runner.dart`
- `apps/server/lib/src/platform/audit_repository.dart`
- `apps/server/lib/src/platform/platform_database.dart`
- `apps/server/lib/src/tasks/task_instance_repository.dart`
- `apps/server/lib/src/tasks/task_instance_service.dart`
- `apps/server/lib/src/workforce/shift.dart`
- `apps/server/lib/src/workforce/shift_repository.dart`
- `apps/server/lib/src/workforce/workforce_service.dart`
- `apps/server/migrations/0006_shifts_and_task_instances.sql`
- `apps/server/test/postgres_integration_test.dart`
- `apps/server/test/shift_integration_test.dart`
- `apps/server/test/shift_test.dart`
- `apps/server/test/task_template_integration_test.dart`
- `docs/README.md`
- `docs/architecture/domain-model.md`
- `docs/architecture/module-boundaries.md`
- `docs/development/phase-1b-shifts-verification.md`
- `docs/development/phase-1b-shifts.md`
- `docs/roadmap/phases.md`
- `packages/api_contracts/lib/api_contracts.dart`
- `packages/api_contracts/lib/src/shifts.dart`
- `packages/api_contracts/platform.openapi.json`
- `packages/api_contracts/test/shift_contracts_test.dart`
