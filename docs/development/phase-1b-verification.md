# P1b.1 – Implementierung und Prüfnachweis

Datum: 2026-09-27. Umfang: [Mitarbeiteridentität und Eigenansicht](phase-1b-employee.md).
P1b insgesamt bleibt offen. Dieser Nachweis betrifft den lokalen Arbeitsstand;
ein Remote-CI-Lauf wurde nicht ausgelöst.

Dieser Nachweis dokumentiert den ursprünglichen Entwicklungsabschluss mit 84 Tests.
Die nachfolgenden Korrekturen und aktuellen 92 Testergebnisse stehen im
[Review des P1b.1-Entwicklungszyklus](phase-1b-review-2026-09-27.md).

## Ergebnis und Architektur

Employee-Profile lassen sich persistent anlegen, lesen, umbenennen und deaktivieren.
Eine feste Standortzuordnung gilt ab Anlage bis zur Deaktivierung. Identity
verwaltet separat eine explizite, historisierte Account-Verknüpfung. Die feste
Rolle `employee` liest nur das eigene aktive Profil und den eigenen Standort.
Admin verwaltet Profile; Viewer, Auditoren und Plugins erhalten keine Profilrechte.
Verknüpfen verändert keine Rolle.

Ein kleiner Application-Koordinator verbindet öffentliche People-, Identity- und
Organization-Ports innerhalb der bestehenden autorisierten PostgreSQL-Transaktion.
Fachregeln liegen außerhalb von Widgets und HTTP-Routen. Der Company-Lock,
Versionsprüfungen, partielle Unique-Indizes und zusammengesetzte Fremdschlüssel
schützen Verknüpfungen und Scopes. Deaktivierung, Verknüpfungsentzug,
Sitzungswiderruf und Audit werden gemeinsam bestätigt oder zurückgerollt.

Audit speichert für Mitarbeiteränderungen IDs, Versionen, Status und Feldnamen,
keine Kopien der Anzeigenamen oder Geheimnisse. Eine serverseitige UUID verbindet
HTTP-Antwort/Log, Audit und bestehende Organisationsevents eines Vorgangs.
Historische Audit-Korrelation bleibt `null`. Neue Mitarbeiter-Events sind ohne
konkreten Verbraucher nicht erforderlich. Keine neue Abhängigkeit oder Runtime.

Flutter bietet Mitarbeiterverwaltung und Eigenansicht mit einem separaten
Application-Controller. Antwortverlust bei Anlage/Verknüpfung wird über stabile
IDs und erneutes Lesen geklärt. Die sichtbare Eigenansicht wird alle 30 Sekunden
erneut geprüft; Ladefehler und Sitzungswechsel entfernen unbestätigte Daten.
Bei mehr als fünf verfügbaren Ansichten verwendet die schmale Oberfläche ein
Menü, damit die zusätzlichen Ansichten lesbar und erreichbar bleiben.

## Ausgeführte Prüfungen

| Prüfung | Ergebnis |
| --- | --- |
| `dart format` für alle vier Packages | erfolgreich; anschließend keine Formatdifferenzen |
| `dart analyze` Backend und API-Verträge | keine Befunde |
| `flutter analyze` Client und Designsystem | keine Befunde |
| Backend: `dart test` | 32 erfolgreich, einschließlich echter PostgreSQL-/HTTP-Integration |
| API-Verträge: `dart test` | 13 erfolgreich |
| Flutter-Client: `flutter test` | 37 erfolgreich |
| Designsystem: `flutter test` | 2 erfolgreich |
| `docker compose config --quiet` | erfolgreich |
| Flutter-Web-Release mit lokalen Webressourcen | erfolgreich |
| Setup-Regressionsprüfungen | erfolgreich |
| Backup-Kryptografie: Roundtrip, falscher Schlüssel, Manipulation, Kürzung, Umordnung | erfolgreich |
| Lokaler API-Smoke nach Migration und Neustart | erfolgreich |
| Browser-Smoke gegen isoliertes PostgreSQL-Schema unter Runtime-Rolle | erfolgreich |
| Verschlüsseltes Backup und isolierte Restoreprobe | erfolgreich |
| OpenAPI-JSON, interne Referenzen und `git diff --check` | erfolgreich |

Insgesamt **84 Tests** in den vier Dart-/Flutter-Packages. Die Datenbanktests
liefen mit gesetztem `STOREOS_TEST_DATABASE` und wurden nicht übersprungen.
Die Client-Suite wurde nach der im Browser gefundenen Navigationskorrektur
einschließlich eines neuen Tests bei 303 Pixel Breite erneut ausgeführt.

Die neuen Integrationsfälle prüfen insbesondere:

- gesamten HTTP-Ablauf einschließlich Serverneustart und persistiertem Profil;
- Rechte, Fremd-IDs, unzulässige Standortverknüpfung und Plugin-Abweisung;
- parallele Verknüpfungen, Verknüpfen gegen Deaktivieren, doppelte IDs und veraltete Versionen;
- gemeinsamen Rollback bei verweigertem Audit-INSERT, unveränderlichen Audit-Trail und Sitzungswiderruf;
- expliziten Rollenwechsel, Entzug und Accountdeaktivierung;
- gemeinsame Korrelations-ID in HTTP, Audit und Organisationsevent;
- Upgrade eines befüllten P1-Schemas unter Erhalt der IDs, Passwort-Hashes,
  Rollen und vorhandenen Auditwerte; wiederholte Migration bleibt ohne Änderung.

Der Browser-Smoke verwendete ausschließlich ein isoliertes Testschema:
Organisation einrichten → Mitarbeiter anlegen → bestehenden Testaccount
verknüpfen → erwarteter Sitzungswiderruf → erneut anmelden → eigenes Profil.
Der finale Build wurde mit der korrigierten mobilen Navigation erneut geprüft.
Das Testschema wurde beim Beenden entfernt. Anschließend wurde die normale
lokale Installation gestartet; `/health`, `/ready`, Anmeldung, Organisations-IDs,
Rechte, Audit/Events/Plugins, verweigerter Fremdzugriff und Logout bestanden den
bestehenden API-Smoke. Der Browser wurde auf die normale Installation zurückgesetzt.

Die lokale Datenbank wurde vor Migration gesichert und mit `0004` aktualisiert.
Eine weitere verschlüsselte Sicherung des migrierten Schemas wurde nach
`storeos_restore_p1b_20260927_1615` zurückgespielt. Dort sind vier Migrationen,
Employee-/Verknüpfungstabellen und Audit-Korrelation vorhanden. Aktive Sitzungen:
0; Plugin-Tokens widerrufen; Runtime-`CONNECT`: verweigert. Die Restore-Datenbank
bleibt isoliert zur Prüfung erhalten; sie wurde nicht produktiv aktiviert.
Diese Restoreprobe prüft das migrierte lokale Schema, nicht einen großen
Mitarbeiterbestand oder die Wiederanwendung späterer Sperr-/Löschentscheidungen.

## Verbleibende Grenzen

- Höchstens 200 Profile pro Installation; Deaktivierte zählen mit. Ein
  unveränderlicher Standort je Profil, kein Standortwechsel und keine Reaktivierung.
- Eine Company und ein lokaler Schreiber; vorhandene Company-Sperre bleibt eine
  Durchsatzgrenze. Keine neue Multi-Location-Replikation oder Handheld-Offlineschreibfähigkeit.
- Account-Rolle und Mitarbeiterverknüpfung sind getrennt zu verwalten. Eine
  Deaktivierung des Profils sperrt dessen Eigenansicht, deaktiviert aber nicht
  automatisch den Account oder dessen unabhängig zugewiesene Administratorrechte.
- Ein bereits angezeigtes Profil kann vor der nächsten Serverprüfung sichtbar
  bleiben. Es wird nicht dauerhaft im Browser gespeichert.
- Aufbewahrung, Löschung und Wiederanwendung neuerer Sperren nach Restore sind
  vor einem Einsatz mit echten Beschäftigtendaten festzulegen. Deaktivierung
  ersetzt keine Löschung; Datenbank-Owner bleiben außerhalb des Runtime-Schutzes.
- Keine Shift-, Task-, Employee-Home-, Guided-Work-, Completion-, Workforce-,
  Warenwirtschafts-, HACCP-, POS- oder Accounting-Funktionen. Native Geräteabnahme
  und Lasttests sind nicht Teil dieses Teilslice.

## Geänderte Dateien

Die folgende Liste enthält neue und geänderte Repository-Dateien gegenüber dem
vorherigen Stand. Lokale Buildprodukte, Logs, Testhelfer, Backups und Secrets
unter `.local/` sind absichtlich nicht Teil der Repository-Änderung.

- `README.md`
- `apps/client_flutter/lib/src/app/storeos_app.dart`
- `apps/client_flutter/lib/src/application/employee_controller.dart`
- `apps/client_flutter/lib/src/application/platform_controller.dart`
- `apps/client_flutter/lib/src/ui/employee_section.dart`
- `apps/client_flutter/lib/src/ui/platform_home_screen.dart`
- `apps/client_flutter/lib/src/ui/platform_sections.dart`
- `apps/client_flutter/test/employee_test.dart`
- `apps/client_flutter/test/platform_app_test.dart`
- `apps/server/lib/src/application/correlation.dart`
- `apps/server/lib/src/application/employee_application.dart`
- `apps/server/lib/src/http/employee_routes.dart`
- `apps/server/lib/src/http/platform_app.dart`
- `apps/server/lib/src/http/server_app.dart`
- `apps/server/lib/src/identity/employee_link_repository.dart`
- `apps/server/lib/src/identity/employee_links.dart`
- `apps/server/lib/src/infrastructure/auth_store.dart`
- `apps/server/lib/src/infrastructure/migration_runner.dart`
- `apps/server/lib/src/people/employee.dart`
- `apps/server/lib/src/people/employee_repository.dart`
- `apps/server/lib/src/people/people_service.dart`
- `apps/server/lib/src/platform/audit_repository.dart`
- `apps/server/lib/src/platform/organization_service.dart`
- `apps/server/lib/src/platform/platform_database.dart`
- `apps/server/lib/src/platform/platform_input.dart`
- `apps/server/lib/src/platform/platform_models.dart`
- `apps/server/migrations/0004_employee_identity_and_audit.sql`
- `apps/server/test/employee_domain_test.dart`
- `apps/server/test/employee_integration_test.dart`
- `apps/server/test/postgres_integration_test.dart`
- `docs/README.md`
- `docs/adr/README.md`
- `docs/architecture/module-boundaries.md`
- `docs/development/phase-1.md`
- `docs/development/phase-1b-employee.md`
- `docs/development/phase-1b-verification.md`
- `docs/roadmap/phases.md`
- `docs/vision.md`
- `packages/api_contracts/README.md`
- `packages/api_contracts/lib/api_contracts.dart`
- `packages/api_contracts/lib/src/employees.dart`
- `packages/api_contracts/platform.openapi.json`
- `packages/api_contracts/test/employee_contracts_test.dart`
