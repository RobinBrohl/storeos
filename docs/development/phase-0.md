# Phase 0: technische Grundlage

Diese Umsetzung konkretisiert [P0](../roadmap/phases.md). Die Zielarchitektur in `docs/architecture/` enthält weiterhin spätere Fähigkeiten; allein daraus folgt keine Implementierungszusage.

## Umfang und Grenzen

Vier Packages reichen: reines Dart-Backend, Flutter-App, transportneutrale API-Verträge und ein kleines Flutter-Designsystem. Lokale Pfadabhängigkeiten und getrennte Lockfiles erlauben einen Backend-Build ohne Flutter. Eine zusätzliche Monorepo-Frameworkschicht, ORM, generische Repository-Basisklassen, Event-Broker oder Plugin-Runtime sind für P0 nicht erforderlich.

Der einzige Benutzerablauf ist lokale Anmeldung → berechtigter Standort-Systemstatus → Abmeldung. Er verarbeitet echte persistierte Accounts und Sessions. Company-/Location-IDs sind dabei stabile technische Autorisierungsscopes einer Installation; es werden keine Organisationseinträge oder Mitarbeiter simuliert. P1 muss diese IDs kontrolliert an seine echten Organisationseinträge binden. Ein Claim allein ist keine Standortfreigabe: Account, gültige Sitzung und konfigurierter Standort müssen serverseitig zusammenpassen.

Products, Inventory, HACCP, Workforce, Tasks, POS, Accounting, Forecasting und AI werden nicht implementiert. Es gibt weder Hintergrund-Synchronisation noch vorgetäuschte Offlinefähigkeit. Der erste geprüfte Flutter-Runner ist Web; Android, Windows und Linux bleiben Ziele der gemeinsamen Codebasis, erhalten aber eigene spätere Abnahmetests.

## Implementierungsgrenzen

- `apps/server/bin`: Composition Root und eigenständige Start-, Migrations- und Bootstrap-Kommandos.
- `apps/server/lib/src/application`: Authentifizierung, Sessionverwaltung und Autorisierung des technischen Statusabrufs.
- `apps/server/lib/src/http`: Transport, Eingabegrenzen, sichere Fehlerübersetzung, CORS und strukturierte Logs; keine fachlichen Regeln.
- `apps/server/lib/src/infrastructure`: parametrisierte PostgreSQL-Abfragen und versionierte SQL-Migrationen.
- Flutter: Widgets stellen dar und sammeln Eingaben; Controller steuern Anfragen und Sitzungszustand, ein HTTP-Adapter verarbeitet Verträge.
- `packages/api_contracts`: JSON-DTOs und OpenAPI v1, ohne Datenbank- und Flutter-Abhängigkeiten.
- `packages/design_system`: Theme, Abstände und zugängliche Statusdarstellung, ohne Geschäftsentscheidungen.

Shelf hält den HTTP-Transport klein; der PostgreSQL-Treiber stellt Transaktionen und Pooling bereit. SQL-Migrationen besitzen Prüfsummen und eine Datenbanksperre gegen parallele Ausführung. Veränderte bereits angewendete Migrationen werden nicht still akzeptiert. Der normale HTTP-Start führt keine DDL aus. Separate Datenbankrollen begrenzen die Runtime auf erforderliche Lese- und Sessionrechte.

## Sicherheit und Betriebsannahmen

Der erste Account wird ausschließlich per lokalem CLI mit zufälligem Secret aus einer privaten Datei eingerichtet. Ein persistierter Bootstrap-Marker verhindert eine zweite Ersteinrichtung. Es gibt keine öffentliche Setup-Route und keine Standardpasswörter. Die spätere Anlage der ersten Company und ein vollständiges Rollenmodell bleiben P1; P0 eröffnet keine Verwaltungsoberfläche für Fachrechte.

Passwörter werden langsam und gesalzen gehasht. Tokens sind zufällig, in der Datenbank nur gehasht gespeichert, zeitlich begrenzt und widerrufbar. Der Webclient speichert sie nicht dauerhaft. Begrenzte Loginversuche und Requestgrößen reduzieren triviale Überlastung; dies ersetzt keine spätere Betriebsdimensionierung. Logs enthalten Status, Zeit und technische Korrelation, keine Passwörter, Sessiontokens oder vollständigen Anfragen.

HTTP ist für lokale Entwicklung an Loopback gedacht. LAN-Zugriff benötigt den dokumentierten TLS-Proxy und eine auf Geräten vertrauenswürdige lokale CA. Secrets, private Schlüssel und Backups liegen außerhalb von Git. Die Referenz ist eine technische Basis, keine Freigabe für sensiblen Produktivbetrieb. Insbesondere Kontoverwaltung, Passwortwechsel/-Recovery, MFA, granulare Fachrechte und ein fachlicher Audit-Trail sind noch nicht vorhanden.

## Abnahme

Die Abnahme umfasst Formatter, statische Analyse, Unit-/Widgettests, echte PostgreSQL-Integrationstests, Compose-Validierung und laufenden HTTP-/Client-Smoke-Test. Negative Fälle müssen fehlende Anmeldung, fremden Standort, abgelaufene/widerrufene Sitzung, falsches Passwort und nicht erreichbare Datenbank sichtbar abweisen. Eine zweite Migration und Ersteinrichtung dürfen weder Schema noch ersten Account verdoppeln.

Die verschlüsselte Restoreprobe schreibt ausschließlich in eine neue isolierte Datenbank, prüft migrierte Tabellen und verwirft wiederhergestellte Sessions. Vor einer echten produktiven Wiederöffnung müssen aktuelle Sperr-/Löschentscheidungen nach [Deployment](../architecture/deployment.md) geprüft werden. P0 besitzt noch keine automatisierte Wiederherstellung eines späteren verteilten Sicherheitszustands.
