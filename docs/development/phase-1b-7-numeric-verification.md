# P1b.7: Prüfnachweis numerischer Guided-Work-Schritte

Abschluss der Verifikation: 2026-09-29. Grundlage: Commit `74e13d3` und die
uncommitteten Änderungen dieses Zyklus. Der [verbindliche Umfang](phase-1b-7-numeric-steps.md)
bleibt auf numerische Schritte mit festen inklusiven Grenzen beschränkt.

## Implementierung

Schema 2 ergänzt unveränderliche Vorlagenrevisionen und Instanz-Snapshots um
`number`-Schritte. Schema 1 bleibt ausführbar. Exakte Dezimalstrings werden ohne
Rundung als Tausendstel verarbeitet. Jeder akzeptierte Messversuch bleibt
unveränderlich: innerhalb der Grenzen bestätigt er den Schritt, außerhalb
blockiert er die Aufgabe. Nach Klärung ist ein neuer Versuch erforderlich.

Migration `0010_task_numeric_steps.sql` ergänzt Versuche und Referenzen in
Schrittresultaten und Blockierungen. Datenbankbedingungen verhindern fehlende,
falsch bewertete oder unpassend zugeordnete Nachweise. Versuch, Ergebnis,
Versionsfortschritt, Audit und Idempotenz-Receipt werden atomar geschrieben.

Bestehende Tasks-Rechte werden serverseitig geprüft; es gibt keine neuen Rollen,
Pluginrechte oder Domain Events. Der neue Audit-Typ `tasks.step.number_recorded`
enthält Referenzen und Bewertung, keine Rohmesswerte. Bestätigung und Blockierung
verwenden zusätzlich ihre bestehenden Audit-Typen. Es ist keine neue ADR nötig:
Domain, Application, Repository, HTTP-Adapter und Flutter-Controller behalten
ihre bisherigen Verantwortlichkeiten.

## Automatisierte Prüfung

Der abschließende vollständige Lauf ist in `.local/numeric-check-final.log`
festgehalten. Diese lokalen Prüfarbeitsdateien werden nicht eingecheckt.

| Prüfung | Ergebnis |
| --- | --- |
| Formatprüfung aller vier Dart-/Flutter-Pakete | Keine Formatänderungen erforderlich |
| Analyzer API-Contracts, Server, Design System, Flutter-Client | Alle ohne Befund |
| API-Contracts-Tests | 31 bestanden |
| Server-Tests einschließlich echter PostgreSQL-Integration | 92 bestanden |
| Design-System-Tests | 2 bestanden |
| Flutter-Client-Tests | 108 bestanden |
| Gesamt | 233 bestanden |
| Docker Compose-Konfiguration | Gültig |
| Flutter Web Release Build | Erfolgreich |

Geprüft wurden insbesondere:

- Inklusive Grenzen, negative Werte, exakte Präzision, ungültige Syntax,
  Schema 1/2 sowie Grenzen von 20 Schritten und 8 KiB.
- Aktueller Schritt und Status, eigene Mitarbeiteridentität, Standortgrenzen,
  Rechteentzug und erneut geprüfte Berechtigungen bei Command-Replays.
- Blockierung, Klärung, neuer gültiger Versuch, gemischte Bestätigungsschritte,
  Completion und Erhalt der Nachweise bei Stornierung.
- Normalisierte idempotente Wiederholungen, konkurrierende Commands,
  Versionskonflikte sowie Rollback bei Fehlern in Versuch, Resultat,
  Blockierung, Audit und Receipt.
- Direkte SQL-Versuche mit fehlendem Ergebnis, falscher Bewertung oder
  unerlaubter Änderung/Löschung; paginierte Historie mit 51 Versuchen.
- Upgrade einer befüllten Datenbank von 0009 auf 0010 mit unveränderten alten
  Revisionen, Snapshots, Resultaten und weiterhin wiederholbaren Receipts.
- Flutter-Eingaben mit Komma/Punkt, Vorlageneditor, verlorene Antwort,
  Konflikt mit erhaltenem Entwurf, Ladefehler der Historie und Logout.

## Smoke-Test, Neustart und Restore

Die isolierte Flutter-/API-/PostgreSQL-Umgebung wurde im Browser mit zwei
Benutzern bis zur Blockierung und anschließenden administrativen Klärung
geprüft. Der Wert `5` bei Grenzen `[-2.125, 4.5]` blockierte die Aufgabe ohne
Schrittresultat. Der fehlgeschlagene Versuch blieb nach Klärung sichtbar.

Nach einer Unterbrechung blieb dieser Zustand über einen Serverneustart erhalten.
Der weitere Browserzugriff wurde durch die Browser-Sicherheitsrichtlinie
blockiert. Die anschließende gültige Eingabe und Completion sind deshalb nur
über die reale HTTP-API nachgewiesen, nicht als vollständiger Browserdurchlauf.
Dies beschreibt den damaligen manuellen Smoke-Test; der automatisierte
Browsernachtrag unten prüft den Ablauf inzwischen zusätzlich über Flutter.

Der API-Smoke am 2026-09-29 bestätigte `4.500`, wiederholte denselben Command
normalisiert als `4.5` ohne zusätzlichen Versuch und schloss die Aufgabe ab.
Endzustand: `completed`, Version 6, zwei Versuche und ein Schrittresultat;
Health und Readiness waren erfolgreich. Lokaler Nachweis:
`.local/numeric-http-smoke.json`.

Das verschlüsselte Backup wurde in die getrennte Datenbank
`storeos_restore_numeric_20260929` wiederhergestellt. Anzahl und Inhalts-Hashes
stimmten für alle acht geprüften Tabellen mit der Quelle überein:

| Tabelle | Zeilen |
| --- | ---: |
| task_numeric_attempts | 2 |
| task_template_revisions | 1 |
| task_instances | 1 |
| task_step_results | 1 |
| task_blockings | 1 |
| task_execution_commands | 5 |
| shifts | 1 |
| audit_entries | 29 |

Der Restore enthielt keine aktiven Sessions; der Runtime-Zugang blieb gesperrt
und Plugin-Tokens wurden widerrufen. Der Vergleich ist lokal in
`.local/numeric-restore-verification.json` dokumentiert.

## Nachtrag: automatisierter Browserablauf (2026-09-29)

Der eingecheckte Test wird mit
`./scripts/e2e/Run-NumericGuidedWork.ps1 -ChromeDriverPath <chromedriver>`
aufgerufen. Ein lokaler Lauf ist vollständig mit Exitcode 0 abgeschlossen:
`Numeric Guided Work browser E2E passed; isolated fixture cleaned up.`
Zwei unmittelbar aufeinanderfolgende, unabhängig initialisierte lokale Läufe
bestanden mit Exitcode 0. Beide Fixture-Logs enthalten
`numeric_e2e_fixture_verified`; danach waren die beiden Testschemas, Manifeste
und Stop-Dateien entfernt und die Browserports 4444/8095 frei.
Der Wrapper startet ein zufällig benanntes Schema in einer ausdrücklich
konfigurierten `_test`-Datenbank, migriert und richtet die Testdaten über echte
APIs ein. Der HTTP-Server verwendet die eingeschränkte Runtime-Rolle.
ChromeDriver steuert den Flutter-Webclient mit produktiven HTTP-Adaptern;
API-Antworten werden nicht simuliert.

Der Browserlauf meldet den Mitarbeiter an, startet die Aufgabe, erfasst `5`
gegen `[-2.125, 4.5]`, prüft Blockierung und Versuchshistorie, meldet einen
Administrator für die begründete Wiederaufnahme an und erfasst danach als
Mitarbeiter `4,5`. Auf den Bestätigungsschritt folgen Completion, Neuaufbau
des Flutter-App-Baums und erneute Anmeldung. Anschließend ist der gespeicherte
Abschluss weiterhin sichtbar. Das Fixture prüft nach dem Browserlauf Aufgabe,
genau zwei Zahlenversuche, Schrittresultate und die zugehörigen Audits lesend
in PostgreSQL. Erst danach entfernt es Schema und temporäres Manifest.

Der CI-Job `numeric-guided-work-e2e` richtet eine eigene PostgreSQL-Service-
Datenbank und eine gepaarte Chrome-/ChromeDriver-Version ein und startet
denselben Wrapper. Der Job ist konfiguriert, aber in diesem lokalen Arbeitszyklus
noch nicht auf GitHub Actions ausgeführt worden.
Der oben dokumentierte vollständige Paketlauf mit 233 Tests fand vor diesem
Browser-Nachtrag statt; ein erneuter vollständiger Paketlauf steht noch aus.

Handover follow-up (2026-09-29): the subsequent [handover verification](handover-verification.md)
completed the full 233-test suite, all analyzers/format checks and two independent
browser E2E runs. The historical outstanding package-check item above is resolved;
the literal browser-reload limitation remains.

Durable boundary automation (2026-09-30): the isolated journey now runs in three
browser phases. Phase A leaves the task blocked; the API process is then replaced
and phase B verifies the blocked state and the rejected attempt in a fresh page
before the admin resumes and the worker completes; a further fresh page (phase C)
verifies the completed state and both attempts. The fixture verifies task,
attempts, step results, audit actions and `task_execution_commands` receipts, then
replays every recorded operation ID over the real HTTP API with its stored body,
rejects a mismatched reuse with 409 and confirms no additional effects. Locally the
full runner passed three consecutive times with no leftover schema, listeners or
driver processes; an injected phase-A browser failure dropped the isolated schema
through the cleanup fallback. Remote CI execution remains unverified until a push.

## Verbleibende Grenzen

- Der automatisierte Ablauf umfasst inzwischen einen ersetzten HTTP-Prozess, zwei
  reine Seiten-/Browser-Grenzen, Receipt-Replay und einen Cleanup-Fallback nach
  injiziertem Fehler; lokal sind drei aufeinanderfolgende Läufe bestanden. Ein
  Remote-CI-Lauf steht bis zum Push weiterhin aus.
- Schema 2 erfordert passende Client- und Serverversionen; alte Clients werden
  dadurch nicht nachträglich numerikfähig.
- Kein Offline-Schreiben, Sync, Sensorzugriff, Einheitenumrechnung, Override
  oder fachliche HACCP-Freigabe. Die Einheit ist ein Anzeigetext.
- Bestehende Company-Sperrgranularität und Retention-Regeln wurden nicht erweitert.

## Geänderte Dateien

Die folgende Liste umfasst diesen Arbeitsstand einschließlich der bereits zu
Zyklusbeginn vorhandenen, erhaltenen und ergänzten Dokumentationsänderungen.

- `README.md`
- `apps/client_flutter/lib/src/application/shift_controller.dart`
- `apps/client_flutter/lib/src/application/task_template_controller.dart`
- `apps/client_flutter/lib/src/ui/shift_section.dart`
- `apps/client_flutter/lib/src/ui/task_template_section.dart`
- `apps/client_flutter/test/task_numeric_test.dart`
- `apps/client_flutter/test/task_template_test.dart`
- `apps/server/lib/src/application/shift_application.dart`
- `apps/server/lib/src/http/shift_routes.dart`
- `apps/server/lib/src/infrastructure/migration_runner.dart`
- `apps/server/lib/src/platform/audit_repository.dart`
- `apps/server/lib/src/tasks/task_execution.dart`
- `apps/server/lib/src/tasks/task_execution_repository.dart`
- `apps/server/lib/src/tasks/task_execution_service.dart`
- `apps/server/migrations/0010_task_numeric_steps.sql`
- `apps/server/test/postgres_integration_test.dart`
- `apps/server/test/shift_integration_test.dart`
- `apps/server/test/task_blocking_integration_cases.dart`
- `apps/server/test/task_cancellation_integration_cases.dart`
- `apps/server/test/task_execution_integration_cases.dart`
- `apps/server/test/task_execution_test.dart`
- `apps/server/test/task_numeric_integration_cases.dart`
- `apps/server/test/task_template_integration_test.dart`
- `docs/README.md`
- `docs/architecture/domain-model.md`
- `docs/architecture/guided-work.md`
- `docs/development/phase-1b-7-numeric-steps.md`
- `docs/development/phase-1b-7-numeric-verification.md`
- `docs/roadmap/phases.md`
- `packages/api_contracts/README.md`
- `packages/api_contracts/lib/api_contracts.dart`
- `packages/api_contracts/lib/src/task_execution.dart`
- `packages/api_contracts/lib/src/task_numbers.dart`
- `packages/api_contracts/lib/src/task_templates.dart`
- `packages/api_contracts/platform.openapi.json`
- `packages/api_contracts/test/task_numbers_test.dart`
- `packages/api_contracts/test/task_template_contracts_test.dart`

Der Browsernachtrag ergänzt darüber hinaus `apps/server/tool/numeric_e2e_fixture.dart`,
`apps/client_flutter/integration_test/numeric_guided_work_test.dart`,
`apps/client_flutter/test_driver/integration_test.dart`, die Flutter-
`pubspec.yaml`/`pubspec.lock`, UI-Testkennungen in `shift_section.dart`,
`scripts/e2e/Run-NumericGuidedWork.ps1` und `.github/workflows/ci.yml`.
