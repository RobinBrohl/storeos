# P1b.5 – Prüfnachweis Blockierung und Wiederaufnahme

Stand: 2026-09-27. Basiscommit `744cae3`. Ausschließlich der freigegebene
[Blockierungs-Slice](phase-1b-blocking.md), ohne automatischen Commit.

Die Zahlen unten dokumentieren die Implementierungsabnahme. Der
[anschließende Review](phase-1b-blocking-review-2026-09-27.md) ergänzt zwei
Regressionstests und enthält die finalen Prüfergebnisse.

## Ergebnis und Architektur

Mitarbeiter blockieren eigene laufende Aufgaben mit Pflichtbegründung. Administratoren
geben nach dokumentierter Klärung die Wiederaufnahme frei. Der Mitarbeiter bestätigt
den unveränderten nächsten Schritt und schließt anschließend separat ab. Beliebig viele
Blockierungszyklen sind möglich; pro Aufgabe besteht höchstens eine offene Blockierung.

Tasks besitzt Status, Historie und SQL-Invarianten. Die Application koordiniert die
bestehenden People-/Workforce-Schnittstellen und prüft aktuelle Rechte sowie den
konfigurierten Standort. Flutter-Controller halten Entwürfe, Versionskonflikte und
Wiederholungen; Widgets und HTTP-Routen enthalten keine Fachentscheidungen.
Mutation, Audit und Befehlsnachweis liegen in derselben Transaktion. Der bestehende
Company-Lock serialisiert konkurrierende Befehle. Keine neue Architekturabstraktion.

Migration `0008_task_blocking.sql` ergänzt task_blockings, blocked und accepted_version
für Schrittresultate. Befüllte Bestände werden mit position+3 migriert. Alte Receipts
bleiben unverändert lesbar. Nur Admin erhält tasks.instances.resolve. Bestehende
Eigenrechte erlauben das Blockieren; Plugins erhalten keine zusätzlichen Rechte.
Auditaktionen: tasks.instance.blocked und tasks.instance.resumed mit Referenzen und
Versionen, ohne Freitext. Keine neuen Domain Events in diesem Slice.

## Automatisierte Prüfung

`scripts/dev.ps1 check` mit STOREOS_TEST_DATABASE gegen echtes PostgreSQL und isolierte
Testschemas, keine übersprungenen Datenbanktests. Finaler Lauf erfolgreich (Exit 0).

| Paket | Bestanden |
| --- | ---: |
| API Contracts | 25 |
| Dart-Server einschließlich PostgreSQL-/HTTP-Integration | 77 |
| Flutter-Client einschließlich Controller/Widgets | 95 |
| Design-System | 2 |
| Gesamt | **199** |

Alle Dart-Formatprüfungen ohne Änderungen, alle Dart-/Flutter-Analyzer ohne Befund.
Docker Compose config --quiet und Flutter-Web-Release-Build erfolgreich.
OpenAPI: 58 eindeutige Operationsnamen, 110 gültige interne Referenzen; die bestehende
externe Error-Referenz ist in openapi.yaml vorhanden. git diff --check erfolgreich.
Protokolle: `.local/blocking-check-final.log`, `.local/blocking-build.log`.

Abgedeckt: mehrere Blockierungszyklen, Blockieren nach letzter Bestätigung, Reihenfolge
und unveränderte Resultate, Rechteentzug, Account-Link-Widerruf, fremde Company und
Standort, Plugin-Abweisung, Unicode-Grenzen und ungültige Eingaben, Ende der Schicht,
aktuelle Mitarbeiterzuordnung bei Freigabe, parallele gleiche/verschiedene Operationen,
Blockieren gegen Bestätigung, Replay nach weiterem Fortschritt und Neustart.
Injizierte Fehler an Blockierungs-, Audit- und Receipt-Persistenz rollen gemeinsam zurück.
51 Blockierungen bzw. blockierte Aufgaben prüfen Pagination und Eigenabgrenzung.
Das befüllte Upgrade 0007 → 0008 erhält offene, laufende und abgeschlossene Aufgaben,
Snapshots und alte Receipts; frühere Bestätigungen erhalten accepted_version.
Flutter prüft Pflichtbegründung, Konflikte, Antwortverlust, unveränderte Wiederholung,
Historien-Ladefehler, Logout mit ausstehender Antwort und die Rollenoberflächen.

Während der Prüfung korrigiert: Testfixture-Scrollziele nach Einführung des mehrzeiligen
Felds, versehentlich erweiterte Routenliste eines älteren Paginationstests und
Analyzer-Befunde in Test-Doubles. Ein anfänglicher Timeout eines bestehenden
Migrationstests trat im finalen vollständigen Lauf nicht erneut auf.

## Browser- und Betriebsnachweis

Isolierter Server 8088, Flutter-Web-Release 8089, Datenbank
storeos_execution_20260927_test. Normale Entwicklungsinstanz und Benutzer-Tab bleiben
unverändert; ihre Datenbank wurde für diesen Nachweis nicht migriert.

1. Testmitarbeiter startet im Browser die Aufgabe und blockiert mit Begründung.
   Status blocked, 0/1 bestätigt; Bestätigung/Abschluss sind gesperrt.
2. Separates Administratorkonto öffnet die Standortliste, liest die Meldung und
   dokumentiert die Klärung. Danach in_progress, weiterhin 0/1 bestätigt.
3. Mitarbeiter meldet sich erneut an, sieht die fortsetzbare Aufgabe und Historie,
   bestätigt den Pflichtschritt und schließt separat ab. Erneutes Laden zeigt
   completed mit 1/1 und erhaltener Meldung/Klärung.
4. Screenshot: `.local/blocking-browser-smoke.png`.

Verschlüsselte Backups wurden sowohl für den offenen Blockierungszustand als auch
für den abgeschlossenen Ablauf in neue isolierte Datenbanken zurückgespielt:
storeos_restore_blocking_20260927 und storeos_restore_blocking_completed_20260927.
Die unveränderten Restore-Werkzeuge widerrufen Sitzungen/Plugin-Tokens und entziehen
Runtime-CONNECT. Vollständige kanonische Datensatzprüfsummen stimmen für task_instances,
task_step_results, task_blockings, task_execution_commands, shifts und audit_entries
jeweils zwischen Quelle und Restore überein. Der zweite Nachweis umfasst ein Resultat,
eine geklärte Blockierung, fünf Receipts und 25 Audit-Einträge.
Artefakte liegen unter `.local/blocking-backup`, `.local/blocking-completed-backup`,
`.local/blocking-restore-verification.json` und
`.local/blocking-completed-restore-verification.json` (nicht eingecheckt).

## Bekannte Grenzen

P1b insgesamt bleibt teilweise implementiert. Keine Stornierung, Neuzuordnung,
Messwerte, Offlinequeue oder Multi-Location-Synchronisation. Client und Server gemeinsam
aktualisieren: alte Clients verstehen blocked nicht. Der Company-Lock bleibt eine
bekannte Skalierungsgrenze; Nachweise werden weiterhin unbefristet aufbewahrt.
Begründungen sind fachlicher Freitext und müssen auf sachlich nötige Angaben begrenzt
bleiben. Menschliche Freigabe ist kein physischer Nachweis der Problembeseitigung.

## Geänderte Dateien

- `README.md`
- `apps/client_flutter/lib/src/application/shift_controller.dart`
- `apps/client_flutter/lib/src/ui/shift_section.dart`
- `apps/client_flutter/test/shift_test.dart`
- `apps/client_flutter/test/task_blocking_test.dart`
- `apps/client_flutter/test/task_execution_test.dart`
- `apps/server/lib/src/application/shift_application.dart`
- `apps/server/lib/src/http/shift_routes.dart`
- `apps/server/lib/src/infrastructure/migration_runner.dart`
- `apps/server/lib/src/platform/audit_repository.dart`
- `apps/server/lib/src/platform/platform_database.dart`
- `apps/server/lib/src/tasks/task_execution.dart`
- `apps/server/lib/src/tasks/task_execution_repository.dart`
- `apps/server/lib/src/tasks/task_execution_service.dart`
- `apps/server/migrations/0008_task_blocking.sql`
- `apps/server/test/postgres_integration_test.dart`
- `apps/server/test/shift_integration_test.dart`
- `apps/server/test/task_blocking_integration_cases.dart`
- `apps/server/test/task_execution_integration_cases.dart`
- `apps/server/test/task_execution_test.dart`
- `apps/server/test/task_template_integration_test.dart`
- `docs/README.md`
- `docs/architecture/domain-model.md`
- `docs/architecture/guided-work.md`
- `docs/architecture/module-boundaries.md`
- `docs/development/phase-1b-blocking-verification.md`
- `docs/development/phase-1b-blocking.md`
- `docs/roadmap/phases.md`
- `packages/api_contracts/lib/src/task_execution.dart`
- `packages/api_contracts/platform.openapi.json`
- `packages/api_contracts/test/task_blocking_contracts_test.dart`
