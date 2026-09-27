# P1b.4 – Prüfnachweis Guided Work und Completion

Stand: 2026-09-27, Basiscommit `8be17f9`. Ausschließlich der freigegebene
[Bestätigungsschritt-Slice](phase-1b-execution.md). Kein automatischer Commit.

Die folgenden Zahlen dokumentieren die Implementierungsabnahme vor dem Review.
Der [anschließende Review](phase-1b-execution-review-2026-09-27.md) ergänzt zwei
Regressionstests und enthält die finalen Prüfergebnisse.

## Ergebnis

Eigene Aufgabe starten, persistierte Schritte in Snapshot-Reihenfolge bestätigen,
separat abschließen. Start innerhalb der Schicht; laufende Aufgaben nach Schichtende
weiter erreichbar. Admin liest den Fortschritt und Audit. Kein neuer Event,
Pluginzugriff, Messwert, Ausnahmeprozess oder Offline-Schreibpuffer.

## Automatisierte Prüfung

`scripts/dev.ps1 check` mit gesetztem STOREOS_TEST_DATABASE, echten PostgreSQL-
Transaktionen und isolierten Schemas. Keine übersprungenen Datenbanktests.

| Paket | Bestanden |
| --- | ---: |
| API Contracts | 22 |
| Dart-Server inklusive PostgreSQL/HTTP | 69 |
| Flutter-Client inklusive Controller/Widgets | 88 |
| Design-System | 2 |
| Gesamt | **181** |

Dart-Formatter und Dart-/Flutter-Analyzer ohne Befund. Docker Compose config quiet,
Flutter-Web-Release mit lokalen CanvasKit-Ressourcen und git diff --check erfolgreich.
OpenAPI-interne Referenzen aufgelöst und Operationsnamen eindeutig geprüft.
Protokolle: `.local/execution-check-final.log`, `.local/execution-build.log`.

Zusätzliche Fälle: Start-/Endgrenze, nächster Pflichtschritt, terminaler Abschluss,
parallel gleiche und verschiedene Operations-IDs, Antwortverlust, Wiederholung nach
weiterem Fortschritt, Kontext-/Berechtigungsprüfung vor Wiederholung, Linkwiderruf,
Plugin-Token-Abweisung, fremde Company/Objekte und ungültige Bodies. Fachänderung,
Schrittresultat, Audit und Befehlsnachweis rollen bei injizierten Fehlern gemeinsam
zurück. Neue Vorlagenrevisionen ändern laufende Aufgaben nicht. Serverneustart
und Clientneuladen erhalten den bestätigten Fortschritt.

Das befüllte Upgrade 0006 → 0007 bewahrt bestehende Instanzdaten und Snapshots;
wiederholte Migration ist wirkungslos. Runtime-Schreibrechte erlauben ausschließlich
Ausführungsänderungen; Snapshot, Schrittresultate, Befehlsnachweise und terminale
Ausführungen bleiben geschützt. Frühere Plattform-/Employee-/Vorlagentests bestehen.

Während der Prüfung behoben: PostgreSQL generierte Titel sind in BEFORE-Triggern
noch nicht befüllt und werden deshalb nicht mit OLD verglichen; ihre unveränderliche
Quelle content bleibt geprüft. Neue Test-Doubles und Timer-Cleanup wurden korrigiert.

## Browser- und Betriebsnachweis

Isolierter Server 8088, Flutter-Web-Release 8089, Datenbank
`storeos_execution_20260927_test`. Die normale Entwicklungsinstanz wurde nicht
migriert oder neu gestartet.

1. Administrator bereitet über HTTP Employee/Account-Link, veröffentlichte Vorlage
   und aktuelle Schicht mit Aufgabeninstanz vor.
2. Testmitarbeiter meldet sich im Browser an, öffnet Meine Arbeit, startet und
   bestätigt den Schritt. Status: in_progress, Version 3, ein Schrittresultat.
3. Verschlüsseltes Backup dieses laufenden Zustands; Restore in die neue isolierte
   `storeos_restore_execution_20260927`. Restoreprüfung widerruft Sitzungen/Plugin-
   Tokens und sperrt Runtime-CONNECT wie vorgesehen.
4. Vollständige kanonische Datensatzprüfsummen stimmen für task_instances,
   task_step_results, task_execution_commands, shifts und audit_entries überein.
   Erhalten: eine laufende Instanz, ein Schrittresultat, zwei Befehlsnachweise.
   Protokoll: `.local/execution-restore-verification.json`.
5. Browser neu laden und erneut anmelden; unter Laufende Aufgaben den erhaltenen
   Fortschritt öffnen und separat abschließen. Ergebnis completed, Version 4.
6. Administrative HTTP-Abfragen zeigen completed, 1/1 Schritte und genau drei
   Ausführungs-Auditaktionen. Screenshot: `.local/execution-browser-smoke.png`.

Backup: `.local/execution-backup/storeos-20260927-193038-55769562.sodb` samt Manifest.
Die Restore-Datenbank bleibt isoliert zur Inspektion bestehen. Keine privaten
Schlüssel oder Testzugangsdaten wurden in Repositorydateien aufgenommen.

## Verbleibende Grenzen

Nur Bestätigungsschritte; keine blocked-Auflösung, Korrektur oder Stellvertretung.
Kein vollständiger P1b-Abschluss. Company-Lock und UTC-Oberfläche bleiben; keine
Lastabnahme großer Installationen und keine native Geräteabnahme. Nicht bestätigte
Clientbefehle sind nur im Arbeitsspeicher. Ohne Standortserver kein verbindlicher
Abschluss. DB-Owner sind keine vom Runtime-Schutz kontrollierte Rolle. Migration
und aktueller Client/Server müssen gemeinsam ausgerollt werden; bestehende
Entwicklungsinstanzen sind gemäß README neu zu starten.

## Geänderte Dateien

- `README.md`
- `apps/client_flutter/lib/src/application/shift_controller.dart`
- `apps/client_flutter/lib/src/ui/shift_section.dart`
- `apps/client_flutter/test/shift_test.dart`
- `apps/client_flutter/test/task_execution_test.dart`
- `apps/server/lib/src/application/shift_application.dart`
- `apps/server/lib/src/http/shift_routes.dart`
- `apps/server/lib/src/infrastructure/migration_runner.dart`
- `apps/server/lib/src/platform/audit_repository.dart`
- `apps/server/lib/src/platform/platform_database.dart`
- `apps/server/lib/src/tasks/task_execution.dart`
- `apps/server/lib/src/tasks/task_execution_repository.dart`
- `apps/server/lib/src/tasks/task_execution_service.dart`
- `apps/server/lib/src/tasks/task_instance_repository.dart`
- `apps/server/migrations/0007_task_execution.sql`
- `apps/server/test/postgres_integration_test.dart`
- `apps/server/test/shift_integration_test.dart`
- `apps/server/test/task_execution_integration_cases.dart`
- `apps/server/test/task_execution_test.dart`
- `apps/server/test/task_template_integration_test.dart`
- `docs/README.md`
- `docs/architecture/domain-model.md`
- `docs/architecture/guided-work.md`
- `docs/architecture/module-boundaries.md`
- `docs/development/phase-1b-execution-verification.md`
- `docs/development/phase-1b-execution.md`
- `docs/roadmap/phases.md`
- `docs/vision.md`
- `packages/api_contracts/lib/api_contracts.dart`
- `packages/api_contracts/lib/src/shifts.dart`
- `packages/api_contracts/lib/src/task_execution.dart`
- `packages/api_contracts/platform.openapi.json`
- `packages/api_contracts/test/task_execution_contracts_test.dart`
