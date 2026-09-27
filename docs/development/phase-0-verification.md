# Phase-0-Prüfnachweis

Lokal geprüft am 27.09.2026 unter Windows mit Flutter 3.47.5, Dart 3.13.4, PowerShell 7.6.5 und Docker Desktop/Linux-Containern. PostgreSQL 17 läuft im Compose-Service `db`. Dies ist ein technischer Entwicklungsnachweis, keine Freigabe späterer Fachmodule.

| Prüfung | Ergebnis |
| --- | --- |
| `dart format` über die vier Packages | angewendet; anschließender Check ohne Änderungen |
| `dart analyze` für Server und API-Verträge | ohne Befund |
| `dart test` für API-Verträge | 4 erfolgreich |
| `dart test` für Server mit `STOREOS_TEST_DATABASE` | 10 erfolgreich, davon 3 echte PostgreSQL-Integrationstests; keine übersprungen |
| `flutter analyze` für Client und Designsystem | ohne Befund |
| `flutter test` für Client / Designsystem | 15 / 2 erfolgreich |
| `docker compose config --quiet` | erfolgreich |
| Dart-Containerbuild, Migrationscontainer und HTTP-Start als Nicht-root | erfolgreich; `/ready` 200 mit eingeschränkter Runtime-Rolle |
| Caddy-Konfiguration und TLS-Proxy | validiert; HTTPS-Health/Readiness vom Windows-Host mit ausdrücklich geladener CA und aktiver Zertifikatsprüfung erfolgreich; Web-Auslieferung aus dem Proxy-Container geprüft |
| Flutter-Web-Releasebuild mit `--no-web-resources-cdn` | erfolgreich, CanvasKit und Roboto lokal gebündelt |
| Setup-Skript in isoliertem Testverzeichnis | frische Einrichtung, unveränderte Wiederholung und Schutz gegen neue Scope-IDs bei verlorener Konfiguration erfolgreich |
| Migration auf leerer Datenbank und Wiederholung | erste Migration angewendet; zweiter Lauf ohne Änderungen |
| Erneuter Bootstrap | erwartete Ablehnung; kein zweiter Erst-Account |
| API-Smoke im laufenden System | Health, Readiness, Login, Standortstatus, 401 ohne Sitzung, 403 für fremden Standort, Logout und Tokenwiderruf erfolgreich |
| PostgreSQL-Ausfall / Wiederanlauf | `/health` bleibt 200, `/ready` wird 503; nach Neustart Readiness und Anmeldung wieder erfolgreich |
| Flutter im Browser gegen echtes Backend | Login, sichtbarer Datenbankstatus, erneuter Abruf und Logout erfolgreich; temporärer Testaccount anschließend entfernt |
| Backup-Kryptografie | Roundtrip sowie Ablehnung falscher Schlüssel, Manipulation, Abschneiden und vertauschter Chunks erfolgreich |
| Verschlüsseltes PostgreSQL-Backup und isolierte Restoreprobe | 1 Account, 1 Bootstrapmarker, 0 aktive Sessions; Runtime-Verbindungsrecht zur Restore-DB verweigert; Original unverändert |

Die PostgreSQL-Tests prüfen außerdem Migrationsprüfsummen, atomaren Rollback fehlerhafter Migrationen, konkurrierende Ersteinrichtung sowie Account-Deaktivierung, Sitzungsablauf und eingeschränkte Datenbankrechte. Die Clienttests prüfen unter anderem fehlgeschlagene Aktualisierung ohne veraltete Erfolgsanzeige und verspätete Antworten nach Sitzungsablauf.

Die GitHub-Actions-Konfiguration führt die Package-Prüfungen, PostgreSQL-Integration, HTTP-Smoke, Compose-Konfiguration und Setup-/Backupformat-Tests aus. Ein Lauf auf GitHub wurde hier nicht ausgelöst. Der Browser-Smoke verwendet Loopback-HTTP. Für den ergänzenden Host-TLS-Test wurde die lokale Caddy-CA gezielt an einen Python-HTTPS-Client übergeben; der globale Trust Store blieb unverändert. Vertrauensstellung auf echten Geräten, native Runner, Last-/Langzeittests, vollständige Host-Wiederherstellung und externe Sicherheitsprüfung sind noch nicht abgenommen.
