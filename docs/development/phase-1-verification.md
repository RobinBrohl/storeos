# Phase 1 – Prüfnachweis

Datum: 2026-09-27. Geprüft auf Windows mit PowerShell 7.6.5, Flutter 3.47.5, Dart 3.13.4 und PostgreSQL 17 in lokalem Docker Compose. Umfang: [Plattformphase](phase-1.md), keine Fachmodule.

Dieser Nachweis beschreibt die Erstabnahme. Der anschließende [Implementierungsreview](implementation-review-2026-09-27.md) dokumentiert weitere Korrekturen und den erweiterten erfolgreichen Prüflauf mit 63 Tests.

## Automatisierte Prüfungen

Der abschließende Aufruf von `scripts/dev.ps1 check` bestand mit gesetztem `STOREOS_TEST_DATABASE` und den Runtime-Zugangsdaten aus der lokalen `.env`. Kein PostgreSQL-Test wurde übersprungen. Formatierung wurde zuvor mit `dart format` angewendet.

| Bereich | Ergebnis |
| --- | --- |
| `dart format --output=none --set-exit-if-changed` in allen vier Packages | bestanden, keine Änderungen erforderlich |
| `dart analyze` in API-Contracts und Server | keine Befunde |
| `dart test` API-Contracts | 9 Tests bestanden |
| `dart test` Server | 17 Tests bestanden, einschließlich echter PostgreSQL- und HTTP-Integration |
| `flutter analyze` in Design-System und Client | keine Befunde |
| `flutter test` Design-System | 2 Tests bestanden |
| `flutter test` Client | 26 Tests bestanden |
| `docker compose config --quiet` | bestanden |
| Flutter-Web-Release mit `--no-web-resources-cdn` und API-Port 8080 | erstellt und im Browser geprüft |
| Setup- und Backup-Kryptografietests | bestanden |
| `git diff --check` | keine Diff-Fehler |

Damit bestehen insgesamt 54 Dart-/Flutter-Tests. Die CI-Konfiguration verwendet dieselben Toolchain-Versionen; ein entfernter CI-Lauf ist kein Bestandteil dieses lokalen Nachweises.

Die Integration prüft insbesondere P0-Upgrade mit unveränderten IDs und Passwort-Hashes, konkurrierenden Bootstrap, letzten aktiven Administrator, aktuelle serverseitige Rechte, Standortgrenzen, Versionskonflikte und Sitzungswiderruf bei Passwortänderung. Ein erzwungener Auditfehler rollt Zustand und Outbox gemeinsam zurück. Die eingeschränkte Datenbankrolle kann Audit ergänzen, aber weder ändern noch löschen.

Eventtests prüfen begrenzte Wiederholungen, Dead-Letter und manuelles Replay mit derselben Event-ID sowie atomare Empfangsmarker und deduplizierte Plugin-Inboxen. Plugin-Tests prüfen Manifest-Whitelist, explizite Teilfreigaben, Standortgrenzen, Trennung von Benutzer- und Plugin-Tokens und konkurrierenden Widerruf mit erneuter Freigabe. Ein altes Token wird durch erneute Freigabe nicht wieder gültig.

## Laufende Installation und Browser

Die vorhandene lokale P0-Datenbank wurde nach einem verschlüsselten Backup mit `0002_platform_organization` und `0003_platform_events_plugins` aktualisiert. Ein zweiter Migrationsaufruf wendete keine Migration erneut an. Der ursprüngliche Bootstrap-Account erhielt die Administratorrolle; bestehende IDs und Secrets wurden beibehalten. Tatsächliche Organisationsnamen werden durch den Betreiber in der Ersteinrichtung vergeben.

`scripts/dev.ps1 smoke` bestand gegen diese Installation: Health/Readiness, Anmeldung, vorhandene Organisations-IDs, Plattformrechte, Audit-/Event-/Plugin-Abfragen, Ablehnung anonymer und fremder Standortzugriffe sowie Abweisung einer abgemeldeten Sitzung. API-Port 8080 und der lokal bereitgestellte Flutter-Release auf 8085 sind erreichbar.

Der separate Browserdurchlauf verwendete `tool/serve_smoke.dart`, eine ausdrücklich isolierte Testdatenbank und ein zufälliges Schema. Der HTTP-Prozess verband sich als eingeschränkte Runtime-Rolle. Geprüft wurden Anmeldung, Ersteinrichtung, erneut geladene persistente Organisationsdaten, Standortänderung mit steigender Version, Benutzeransicht, Audit, Eventverarbeitung sowie Plugin-Registrierung, ausdrückliche Freigabe, einmalige verdeckte Token-Anzeige und Deaktivierung. Nach Abmeldung und regulärem Stop wurde das Testschema entfernt. In der normalen Installation wurden keine Demo-Organisation oder Test-Plugins hinterlassen.

## Backup und Restore

Nach dem Upgrade wurde ein weiteres verschlüsseltes Backup erstellt und in die neue Datenbank `storeos_restore_p1_202609271508` wiederhergestellt. Ergebnis: ein Account, genau ein Bootstrap-Datensatz, keine aktiven Sitzungen und kein Runtime-CONNECT-Recht. Die P1-Token-Tabelle wurde bei der Restore-Prüfung berücksichtigt; diese Installation enthielt noch keine Plugin-Tokens. Der Token-Widerruf mit vorhandenen Tokens ist separat in den PostgreSQL-Integrationstests geprüft.

Die Quelldatenbank blieb beim Restore unverändert. Die gesperrte Restore-Kopie und verschlüsselte Backups unter `.local/backups/` bleiben lokal zur Kontrolle erhalten. `.env` und Secrets sind nicht Teil des Git-Index.

## Grenzen dieser Abnahme

Geprüft wurde Flutter Web mit einem lokalen Schreiber. Native Runner, LAN-TLS-Gerätefreigabe, Lastverhalten großer Installationen, getrennte Standortserver, Unternehmenssynchronisation und Geräte-Offlineschreiben sind nicht abgenommen. Plugins bleiben externe API-Clients ohne Fremdcodeausführung. Audit schützt gegen Änderungen durch die Runtime-Rolle, nicht gegen einen Datenbankadministrator. Es bestehen keine Aussagen zur regulatorischen Zertifizierung oder zu noch nicht implementierten Fachmodulen.
