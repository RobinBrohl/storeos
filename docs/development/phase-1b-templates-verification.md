# P1b.2 – Prüfnachweis Arbeitsvorlagen

Stand: 2026-09-27. Ausgangsstand `3a8f710`; ausschließlich der freigegebene
[Vorlagen-Slice](phase-1b-templates.md). Keine Shift-, TaskInstance- oder Ausführungsfunktion.

Der anschließende [Review](phase-1b-templates-review-2026-09-27.md) korrigiert drei konkrete Befunde und bestätigt den aktuellen Stand mit **124 bestandenen Tests**. Die folgenden 119 Tests und Betriebsnachweise dokumentieren die ursprüngliche Implementierungsabnahme.

## Umsetzung und Architektur

Tasks besitzt Vorlagen und Revisionen im bestehenden modularen Dart-Monolithen.
Der Service prüft `tasks.templates.manage` serverseitig über die vorhandene
Company-Transaktion. Das Organization-Application-Interface prüft eingerichtete
Standorte. Fachänderung und Audit werden gemeinsam committet; Routen delegieren,
Flutter-Widgets zeigen Controllerzustände. Kein neues Package, keine Dependency,
kein Broker und keine generische Workflow- oder Idempotenzinfrastruktur.

Migration `0005_task_templates.sql` ergänzt `task_templates` und
`task_template_revisions`, Scope-Fremdschlüssel, Revisionsnummern, genau einen
möglichen Entwurf, Inhaltsgrenzen und den Trigger gegen Änderungen/Löschung
freigegebener Revisionen. Die Runtime erhält eingeschränkte Spaltenrechte;
DELETE/TRUNCATE bleiben gesperrt. Migrationen 0001–0004 wurden nicht verändert.

Nur `admin` erhält `tasks.templates.manage`; alle übrigen Rollen und gültige
Plugin-Tokens wurden als abgewiesen geprüft. Es entstehen keine neuen Domain
Events: Es gibt in diesem Scope keinen Verbraucher. Die vier Auditaktionen
`tasks.template.created`, `tasks.template.draft_updated`,
`tasks.template.revision_created`, `tasks.template.published` enthalten
Revision/Version/Änderungsfelder und Korrelation, keine vollständigen Anleitungen.

## Automatisierte Prüfung

Vollständiger Lauf von `scripts/dev.ps1 check` mit gesetztem
`STOREOS_TEST_DATABASE`, echter PostgreSQL-Datenbank und isolierten Testschemas.
Die Integrationstests wurden ausgeführt, nicht übersprungen.

| Paket | Ergebnis |
| --- | --- |
| API-Verträge | 16 Tests bestanden |
| Dart-Server | 42 Tests bestanden, einschließlich PostgreSQL-/HTTP-Integration |
| Flutter-Client | 59 Tests bestanden |
| Flutter-Design-System | 2 Tests bestanden |
| Gesamt | **119 Tests bestanden** |

`dart format` angewendet; abschließender Formatcheck ohne Änderungen.
`dart analyze` und `flutter analyze`: keine Befunde in allen vier Packages.
`docker compose config --quiet`: erfolgreich. Flutter-Web-Release mit lokalen
CanvasKit-Ressourcen gebaut. OpenAPI-JSON geparst und alle 70 internen Referenzen
aufgelöst. `git diff --check` ohne Whitespacefehler.

Neue Tests decken ab:

- Schema 1, Titel/Schrittgrenzen, Unicode, UTF-8-Größe, Steuerzeichen,
  eindeutige IDs, geordnete Inhalte und ungültige Freigaben.
- Vollständiger HTTP-Ablauf für Revisionen 1/2, No-op, Freigabewiederholung,
  unveränderliche Historie und neu gestartete Serverinstanz.
- Alle Rollen, anonyme/ungültige Sessions, gültige Plugin-Tokens,
  fremde Company und nicht eingerichtete/falsch referenzierte Objekte.
- Gleichzeitiges Bearbeiten, Entwurfserstellen und Freigeben; CAS-Konflikte,
  genau eine Wirkung und keine doppelten Audit-Einträge.
- Rücknahme jeder der vier Schreibaktionen bei erzwungenem Auditfehler.
- Upgrade einer befüllten 0004-Datenbank: Accounts, Mitarbeiter,
  Account-Verknüpfungen und Audit bleiben erhalten; Migration wiederholbar.
- 51 Vorlagen und 51 Revisionen: Cursorseiten ohne Lücken/Dubletten und ohne
  Schrittinhalte in den Metadatenlisten.
- Flutter: Antwortverlust bei vier Schreibaktionen, Sitzungswechsel während
  laufender Requests, Konflikte einschließlich konkurrierender Freigabe,
  fehlgeschlagener Ergebnisabgleich, unbestätigte Zustände und Paging.
- Widget-Ablauf mit Erstellen, Schritten, Reihenfolge, Speichern, Freigabe,
  neuer Revision und historischer Anzeige; Eingabefehler und Logout.

## Browser, Betrieb und Wiederherstellung

Der echte Release-Client unter `http://127.0.0.1:8085/` verwendete die isolierte
Datenbank `storeos_templates_smoke_test`, Runtime-Rolle und HTTP-API. Getestet:
Anmeldung, Organisationseinrichtung, leere Vorlagenansicht, Anlage einer
Öffnungsroutine, Anleitungsschritt, Speichern, Freigabe Revision 1, Kopieren,
Ändern und Freigabe Revision 2. Die historische erste Revision zeigte weiterhin
ihren ursprünglichen Titel und Inhalt ohne Bearbeitungsaktionen. Das Audit-UI
zeigte alle sechs Vorlagenaktionen. Anschließend wurde die Sitzung beendet.

Die Testdaten wurden mit dem vorhandenen Backup-Crypto-Modul verschlüsselt
(`pg_dump` Custom-Format; für diesen Test nur die Quelldatenbank angepasst).
`infra/backup/Restore-StoreOS.ps1` stellte sie unverändert in der neuen isolierten
Datenbank `storeos_restore_templates_20260927` wieder her. Vergleich: eine Vorlage,
zwei veröffentlichte Revisionen und sechs Audit-Einträge stimmen feldgenau mit
der Quelle überein. UPDATE freigegebener Revisionen und DELETE unter Runtime-Rechten
bleiben gesperrt. Wiederhergestellte Sitzungen sind widerrufen; Runtime-CONNECT
ist gesperrt. Die Restore-Datenbank bleibt zur Kontrolle bestehen.

Vor dem lokalen Upgrade wurde auch die reguläre Entwicklungsdatenbank
verschlüsselt gesichert. Migration 0005 wurde dort erfolgreich angewendet,
der reguläre Server anschließend neu gestartet. Der bestehende vollständige
API-Smoke-Test sowie Adminrecht und GET der Vorlagenliste waren erfolgreich.
Die reguläre Datenbank enthält keine Smoke-Vorlagen. Die separate Smoke-Quelle
wurde nach erfolgreicher Wiederherstellung entfernt. Backup, Screenshot und
lokale Test-Runner liegen ausschließlich unter dem ignorierten `.local/`.

## Bekannte Grenzen

- P1b bleibt teilweise implementiert. Keine Aufgabenausführung, Schichten,
  Instanzen, Mitarbeiter-Startseite, Ergebnisdaten oder Offline-Schreibqueue.
- Nur Bestätigungsschritte; maximal 20 Schritte, 1.000 Codepoints je Anleitung,
  insgesamt 8 KiB normalisierter Inhalt. Listen sind auf 50 pro Seite begrenzt.
- Lokaler Server ist alleiniger Schreiber. Mehrere eingerichtete Locations sind
  Metadaten desselben Servers, keine Replikation unabhängiger Standortserver.
- Der vorhandene Company-Lock serialisiert Zugriffe; kein Lasttest für große
  Installationen und kein zusätzlicher Skalierungsmechanismus in diesem Slice.
- Ungespeicherte Eingaben leben im Speicher. Sitzungsende/Browserneuladen verwirft
  sie; bei Navigation zu anderen Revisionen wird vor Verwerfen gefragt.
- Datenbank-Owner bleiben außerhalb der Runtime-Schutzgrenze. Audit/Backup sind
  keine kryptografische oder regulatorische Unveränderlichkeitsgarantie.
- Browser-Abnahme erfolgte mit Flutter Web; native Runner wurden nicht abgenommen.

## Geänderte Dateien

- [README.md](../../README.md)
- [apps/client_flutter/lib/src/app/storeos_app.dart](../../apps/client_flutter/lib/src/app/storeos_app.dart)
- [apps/client_flutter/lib/src/application/task_template_controller.dart](../../apps/client_flutter/lib/src/application/task_template_controller.dart)
- [apps/client_flutter/lib/src/ui/platform_home_screen.dart](../../apps/client_flutter/lib/src/ui/platform_home_screen.dart)
- [apps/client_flutter/lib/src/ui/task_template_section.dart](../../apps/client_flutter/lib/src/ui/task_template_section.dart)
- [apps/client_flutter/test/task_template_test.dart](../../apps/client_flutter/test/task_template_test.dart)
- [apps/server/lib/src/http/platform_app.dart](../../apps/server/lib/src/http/platform_app.dart)
- [apps/server/lib/src/http/task_template_routes.dart](../../apps/server/lib/src/http/task_template_routes.dart)
- [apps/server/lib/src/infrastructure/migration_runner.dart](../../apps/server/lib/src/infrastructure/migration_runner.dart)
- [apps/server/lib/src/platform/audit_repository.dart](../../apps/server/lib/src/platform/audit_repository.dart)
- [apps/server/lib/src/platform/platform_database.dart](../../apps/server/lib/src/platform/platform_database.dart)
- [apps/server/lib/src/tasks/task_template.dart](../../apps/server/lib/src/tasks/task_template.dart)
- [apps/server/lib/src/tasks/task_template_repository.dart](../../apps/server/lib/src/tasks/task_template_repository.dart)
- [apps/server/lib/src/tasks/task_template_service.dart](../../apps/server/lib/src/tasks/task_template_service.dart)
- [apps/server/migrations/0005_task_templates.sql](../../apps/server/migrations/0005_task_templates.sql)
- [apps/server/test/postgres_integration_test.dart](../../apps/server/test/postgres_integration_test.dart)
- [apps/server/test/task_template_domain_test.dart](../../apps/server/test/task_template_domain_test.dart)
- [apps/server/test/task_template_integration_test.dart](../../apps/server/test/task_template_integration_test.dart)
- [docs/README.md](../../docs/README.md)
- [docs/architecture/module-boundaries.md](../../docs/architecture/module-boundaries.md)
- [docs/development/phase-1b-templates-verification.md](../../docs/development/phase-1b-templates-verification.md)
- [docs/development/phase-1b-templates.md](../../docs/development/phase-1b-templates.md)
- [docs/roadmap/phases.md](../../docs/roadmap/phases.md)
- [docs/vision.md](../../docs/vision.md)
- [packages/api_contracts/README.md](../../packages/api_contracts/README.md)
- [packages/api_contracts/lib/api_contracts.dart](../../packages/api_contracts/lib/api_contracts.dart)
- [packages/api_contracts/lib/src/task_templates.dart](../../packages/api_contracts/lib/src/task_templates.dart)
- [packages/api_contracts/platform.openapi.json](../../packages/api_contracts/platform.openapi.json)
- [packages/api_contracts/test/task_template_contracts_test.dart](../../packages/api_contracts/test/task_template_contracts_test.dart)

- [docs/development/phase-1b-templates-review-2026-09-27.md](phase-1b-templates-review-2026-09-27.md) – ergänzender Review
