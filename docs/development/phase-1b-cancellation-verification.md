# P1b.6 – Prüfnachweis Stornierung

Stand: 2026-09-27. Basiscommit `925ab52`. Ausschließlich der freigegebene
[Stornierungs-Slice](phase-1b-cancellation.md), ohne automatischen Commit.

Die Zahlen unten dokumentieren die Implementierungsabnahme. Der
[anschließende Review](phase-1b-cancellation-review-2026-09-27.md) ergänzt drei
Regressionstests und enthält die abschließenden Prüfergebnisse.

## Ergebnis und Architektur

Admin kann ausschließlich blockierte Aufgaben begründet und ausdrücklich bestätigt
stornieren. Der terminale Zustand erhält Snapshot, Zuordnung und bestätigte Schritte.
Tasks besitzt Status, Blockierungshistorie und SQL-Invarianten. ShiftApplication prüft
aktuelle Rechte und den eingerichteten Standort; HTTP-Routen und Widgets delegieren.
Keine neue Dependency oder allgemeine Abstraktion. Mutation, Abschluss der Blockierung,
Audit und Receipt sind atomar. Die bestehende Company-Sperre serialisiert Befehle.

Migration `0009_task_cancellation.sql` ergänzt cancelled und resolution_kind. Bereits
geschlossene Blockierungen erhalten resumed. Grund, Zeit, Akteur und Version verwenden
die vorhandenen Abschlussfelder; die API leitet ihre Stornierungsmetadaten daraus ab.
Neue Berechtigung ausschließlich für Admin: `tasks.instances.cancel`.
Audit: `tasks.instance.cancelled` mit Referenzen und Versionen ohne Freitext.
Keine neuen Domain Events, da kein Verbraucher erforderlich ist.

## Automatisierte Prüfung

`scripts/dev.ps1 check` mit STOREOS_TEST_DATABASE gegen echtes PostgreSQL und isolierte
Testschemas erfolgreich (Exit 0), keine übersprungenen Datenbanktests.

| Paket | Bestanden |
| --- | ---: |
| API Contracts | 27 |
| Dart-Server einschließlich PostgreSQL-/HTTP-Integration | 84 |
| Flutter-Client einschließlich Controller/Widgets | 100 |
| Design-System | 2 |
| Gesamt | **213** |

Dart-Formatprüfungen ohne Änderungen, Dart-/Flutter-Analyzer ohne Befund.
Docker Compose config --quiet und Flutter-Web-Release-Build erfolgreich.
OpenAPI-Operationsnamen eindeutig, interne Referenzen auflösbar; vorhandene externe
Error-Referenz geprüft. git diff --check erfolgreich.
Protokolle: `.local/cancellation-check-final.log`, `.local/cancellation-build.log`.

Abgedeckt: Pflichtgrund und Unicode-Grenzen, Rechte-/Company-/Standort-/Plugin-Abgrenzung,
Rechteentzug vor Replay, deaktivierter Mitarbeiter und widerrufener Account-Link,
Schichtende, alle Schritte bereits bestätigt, mehrere Blockierungszyklen, unveränderte
Snapshots und Resultate, terminale SQL-Unveränderlichkeit, konkurrierendes cancel/resume,
gleiche Operation parallel, geänderter Replay-Input, Neustart und 51 Einträge mit Cursor.
Injizierte Fehler an Blockierungsabschluss, Task-Status, Audit und Receipt rollen alles
zurück. Das befüllte Upgrade 0008 → 0009 prüft offene und geschlossene Blockierungen,
vorhandene Resultate sowie unveränderte alte Receipts einschließlich API-Replay.
Flutter prüft Konflikte, Antwortverlust mit identischer Wiederholung, Ladefehler nach
Mutation, Logout während einer Anfrage, Bestätigungsdialog und terminale Rollenansicht.

## Browser-Smoke und Wiederherstellung

Isolierter Server 8088 und Release-Webclient 8089, eigene Testdatenbank
`storeos_execution_20260927_test`; die Entwicklungsinstanz 8085 blieb unverändert.
Mitarbeiter startet eine Aufgabe, bestätigt einen Schritt und meldet ein Hindernis.
Admin storniert mit Grund und Bestätigungsdialog. Nach erneuter Mitarbeiter-Anmeldung
ist die Aufgabe über die Stornierungsliste lesbar: 1/1 bestätigt, ausdrücklich nicht
erfolgreich abgeschlossen, beide Gründe in der Historie und keine Schreibaktionen.
Nachweis: `.local/cancellation-browser-smoke.png`.

Verschlüsseltes Backup nach Abschluss der Anmeldungen in neue isolierte Datenbank
`storeos_restore_cancellation_20260927_final` wiederhergestellt. Zeilenzahl und Prüfsumme
des kanonisch sortierten vollständigen Inhalts stimmen in allen sechs Tabellen überein:
task_instances (1), task_step_results (1), task_blockings (1), task_execution_commands (4),
shifts (1), audit_entries (22). Wiederherstellung bestätigt null aktive Sitzungen,
gesperrten Runtime-CONNECT und widerrufene Plugin-Tokens. Ein erster Vergleich während
der erneuten Anmeldung zeigte erwartete zusätzliche Auditzeilen; der abschließende
Vergleich verwendet einen unveränderten Quellbestand.
Protokolle: `.local/cancellation-backup.log`, `.local/cancellation-restore.log`,
`.local/cancellation-restore-verification.json`.

## Grenzen

Client und Server gemeinsam aktualisieren; alte Clients kennen cancelled nicht.
Kein Offline-Schreibbetrieb, kein Sync, keine Wiedereröffnung oder Stornierung anderer
Zustände. Eigene Leserechte bleiben an die aktuelle Mitarbeiterverknüpfung gebunden.
Bestehende Company-Serialisierung und unbegrenzte Historien-/Receipt-Aufbewahrung bleiben
unverändert. Native Plattformen wurden nicht separat im Gerätetest ausgeführt.
P1b bleibt insgesamt teilweise umgesetzt; insbesondere Zahlenschritte fehlen weiterhin.

## Geänderte Dateien

Die folgende Liste enthält alle versionierbaren Änderungen dieses Zyklus; lokale
Prüfskripte und Protokolle unter `.local/` sind ignorierte Testartefakte.

- [README.md](../../README.md)
- [apps/client_flutter/lib/src/application/shift_controller.dart](../../apps/client_flutter/lib/src/application/shift_controller.dart)
- [apps/client_flutter/lib/src/ui/shift_section.dart](../../apps/client_flutter/lib/src/ui/shift_section.dart)
- [apps/client_flutter/test/task_cancellation_test.dart](../../apps/client_flutter/test/task_cancellation_test.dart)
- [apps/server/lib/src/application/shift_application.dart](../../apps/server/lib/src/application/shift_application.dart)
- [apps/server/lib/src/http/shift_routes.dart](../../apps/server/lib/src/http/shift_routes.dart)
- [apps/server/lib/src/infrastructure/migration_runner.dart](../../apps/server/lib/src/infrastructure/migration_runner.dart)
- [apps/server/lib/src/platform/platform_database.dart](../../apps/server/lib/src/platform/platform_database.dart)
- [apps/server/lib/src/tasks/task_execution.dart](../../apps/server/lib/src/tasks/task_execution.dart)
- [apps/server/lib/src/tasks/task_execution_repository.dart](../../apps/server/lib/src/tasks/task_execution_repository.dart)
- [apps/server/lib/src/tasks/task_execution_service.dart](../../apps/server/lib/src/tasks/task_execution_service.dart)
- [apps/server/migrations/0009_task_cancellation.sql](../../apps/server/migrations/0009_task_cancellation.sql)
- [apps/server/test/postgres_integration_test.dart](../../apps/server/test/postgres_integration_test.dart)
- [apps/server/test/shift_integration_test.dart](../../apps/server/test/shift_integration_test.dart)
- [apps/server/test/task_blocking_integration_cases.dart](../../apps/server/test/task_blocking_integration_cases.dart)
- [apps/server/test/task_cancellation_integration_cases.dart](../../apps/server/test/task_cancellation_integration_cases.dart)
- [apps/server/test/task_execution_integration_cases.dart](../../apps/server/test/task_execution_integration_cases.dart)
- [apps/server/test/task_execution_test.dart](../../apps/server/test/task_execution_test.dart)
- [apps/server/test/task_template_integration_test.dart](../../apps/server/test/task_template_integration_test.dart)
- [docs/README.md](../../docs/README.md)
- [docs/architecture/domain-model.md](../../docs/architecture/domain-model.md)
- [docs/architecture/guided-work.md](../../docs/architecture/guided-work.md)
- [docs/architecture/module-boundaries.md](../../docs/architecture/module-boundaries.md)
- [docs/development/phase-1b-cancellation-verification.md](../../docs/development/phase-1b-cancellation-verification.md)
- [docs/development/phase-1b-cancellation.md](../../docs/development/phase-1b-cancellation.md)
- [docs/roadmap/phases.md](../../docs/roadmap/phases.md)
- [packages/api_contracts/lib/src/task_execution.dart](../../packages/api_contracts/lib/src/task_execution.dart)
- [packages/api_contracts/platform.openapi.json](../../packages/api_contracts/platform.openapi.json)
- [packages/api_contracts/test/task_cancellation_contracts_test.dart](../../packages/api_contracts/test/task_cancellation_contracts_test.dart)
