# Phase 1 – Plattformverwaltung

Die aktuelle Freigabe umfasst Company, Location, User/Authentication, RBAC, Audit, Events und eine minimale externe Plugin-API. Workforce und der fachliche Aufgaben-Slice bleiben nachgelagert (ADR 0012). Ein User ist ein Login-Account, kein Employee.

## Modell und Grenzen

Eine Installation besitzt eine konfigurierte Company mit stabiler ID und einen lokalen Standort. Bestehende P0-IDs, Accounts und Passwort-Hashes bleiben erhalten. Namen für Company und ersten Standort werden durch den Administrator eingerichtet; ein noch nicht eingerichteter Datensatz wird ausdrücklich als solcher dargestellt. Weitere Standorte sind Stammdaten unter demselben lokalen Schreiber, keine synchronisierten Standortserver. Keine automatische Replikation oder Geräte-Offlineschreibvorgänge.

Organization besitzt Company und Location. Identity besitzt Accounts, feste Rollen und Sitzungen. Audit besitzt unveränderliche Einträge. Events besitzt Outbox und Zustellzustände. Plugins besitzt Manifeste, Freigaben und gehashte Zugangstokens. Sie teilen in dieser Phase eine PostgreSQL-Transaktion; Application Services koordinieren über explizite Repository-Schnittstellen. HTTP-Routen übernehmen nur Parsing, Service-Aufruf und Antwort. Flutter-Controller steuern Zustände und Aufrufe; Widgets präsentieren sie.

## Berechtigungen

Feste Rollen vermeiden vorerst einen allgemeinen Policy-Editor: `admin` verwaltet Company, Standorte, Benutzer und Plugins und liest Audit/Events; `auditor` liest Organization, Audit und Events; `viewer` liest Organization nur im eigenen Standortkontext. Alle Accounts gehören derselben Company und genau einem Heimatstandort. Nur der explizite Bootstrap-Account erhält beim Upgrade automatisch `admin`. Jede Anfrage prüft aktuelle Rechte; Benutzerdeaktivierung und sicherheitsrelevante Änderungen widerrufen Sitzungen. Der letzte aktive Administrator darf nicht entfernt werden. Plugin-Identitäten besitzen niemals eine Benutzerrolle.

## HTTP-Verträge

Alle folgenden Benutzerrouten liegen unter `/api/v1/platform`; Bearer-Sitzung erforderlich. Fehler verwenden bestehende `ApiError`-Verträge. Listen sind begrenzt; Audit/Event-Seiten verwenden einen Cursor. Änderungen bestehender Stammdatensätze verlangen `expectedVersion`, Konflikte antworten mit HTTP 409. Neue Locations und User nutzen clientseitig erzeugte UUIDs; Plugins verwenden ihre eindeutige Manifest-ID als Slug. Wiederholung derselben Erstellung erzeugt keine zweite Entität, sondern meldet einen Konflikt. Der Client lädt nach unklarem Ausgang den aktuellen Stand, bevor ein Nutzer erneut schreibt.

- `GET /context`: `{userId, companyId, locationId, role, permissions}`.
- `GET /organization`: `{company: {id,name,version}, locations: [{id,companyId,name,version}]}`; Namen können vor Einrichtung null sein.
- `POST /organization/setup`: `{companyName,locationName}`; einmalig, nur Admin, bestehende IDs.
- `POST /company`: `{name,expectedVersion}`; Company umbenennen.
- `POST /locations`: `{id,name}`; Standort anlegen.
- `POST /locations/{id}`: `{name,expectedVersion}`; Standort umbenennen.
- `GET /users`: `{users:[{id,username,companyId,locationId,role,isActive,version}]}`; Admin.
- `POST /users`: `{id,username,password,locationId,role}`; Admin.
- `POST /users/{id}`: `{role,isActive,expectedVersion}`; Admin; keine Passwortänderung über dieses Kommando.
- `POST /users/{id}/password`: `{password,expectedVersion}`; Admin setzt ein neues Passwort und widerruft alle Sitzungen des Accounts.
- `GET /audit?after=...`: `{items:[...],nextCursor}`; Admin/Auditor, Lesezugriff wird auditiert.
- `GET /events?after=...`: `{items:[...],nextCursor}`; Admin/Auditor, redigierte Ereignisse und Zustellstatus.
- `POST /events/{eventId}/replay`: ausschließlich Admin, ausschließlich `dead_letter`; erneuter Versuch mit derselben ID, auditiert.
- `GET /plugins`: `{plugins:[...]}`; Admin.
- `POST /plugins`: `{manifest: {...}}`; nur Registrierung, keine automatische Freigabe.
- `POST /plugins/{id}/approve`: `{expectedVersion,locationId,permissions:[...],subscriptions:[...]}`; explizite Teilmenge des Manifests, gibt Token einmalig zurück.
- `POST /plugins/{id}/disable`: `{expectedVersion}`; widerruft Token und ausstehende Zustellungen.

Die gesonderte Plugin-API `/api/plugin/v1` akzeptiert ausschließlich Plugin-Bearer-Tokens: `GET /organization` liefert freigegebene Company/Location-Felder; `GET /events` liefert nur freigegebene Organisationsevents; `POST /events/{eventId}/ack` bestätigt eine Zustellung. Ein nicht bestätigtes Event darf erneut geliefert werden. Plugins deduplizieren anhand eventId; Rechte werden bei Abruf und Bestätigung erneut geprüft.

## Audit, Events und Plugins

Audit, State und ein benötigtes Organisationsevent werden atomar gespeichert. Audit enthält Akteur-ID, Aktion, Ziel, Scope, Zeitpunkt und begrenzte Änderungsdaten; niemals Passwörter, Tokens oder Hashes. Das Runtime-Datenbankkonto erhält keine UPDATE-/DELETE-Rechte auf Audit. Ein Datenbankadministrator kann weiterhin Daten ändern; keine Behauptung manipulationssicherer Archivierung.

Die lokale Outbox stellt Organisationsevents nach Commit an einen konkreten internen Consumer zu: die Inbox freigegebener Plugin-Registrierungen. Consumer-Effekt und Empfangsmarker sind atomar; Wiederholungen erzeugen keine zweite Zustellung. Fehlversuche sind begrenzt und sichtbar. Kein externer Broker, kein Event Sourcing, keine Sortiergarantie über Aggregate hinweg. Payloads enthalten ausschließlich freigegebene Organisationsfelder, keine Benutzer- oder Auditdaten. Neue Freigaben erhalten keine stillschweigende historische Datenausleitung.

Das Manifest beschreibt Identität, Version, Anbieter, Core/API-Version, Capabilities, Permissions, Subscriptions und ein Konfigurationsschema. P1 akzeptiert nur den kleinen tatsächlich unterstützten Vertrag. Freigaben gelten für genau einen Standort. Tokens laufen ab und werden nur gehasht gespeichert; erneute Freigabe rotiert das Token. Deaktivierung stoppt ausstehende Zustellungen. StoreOS lädt, installiert oder startet keinen Fremdcode und ruft keine Plugin-URLs auf. Der Betreiber betreibt einen externen API-Client selbst. Eine verwaltete Plugin-Runtime bleibt gesperrt, bis Isolation und Lieferkette abgenommen sind.

## Bewusste Betriebsgrenzen

P1 begrenzt eine Installation auf eine Company, 200 Standorte, 200 Accounts und 100 Plugin-Registrierungen. Audit-/Event-Abfragen liefern höchstens 50 Einträge je Seite. Ein Company-Lock serialisiert administrative Transaktionen einschließlich Rechteprüfung; er schützt derzeit Integrität vor maximalem Durchsatz. Größere Installationen benötigen eine gemessene Lastabnahme, granulare Locks und paginierte Stammabfragen. Es gibt keine automatische Audit-/Outbox-Bereinigung; Speicherbedarf und verschlüsselte Backups sind zu überwachen. Ein Aufbewahrungsjob benötigt eine eigene Regel und Datenbankrolle.

Plugin-Tokens gelten 24 Stunden. Zur erneuten Freigabe muss eine aktive Registrierung zuerst deaktiviert werden. Unterstützte Rechte und Capabilities sind `organization.read` und `events.read`; Abonnements sind `organization.company.updated`, `organization.location.created`, `organization.location.updated`. `coreApiVersion` muss 1 sein, das Konfigurationsschema ein geschlossenes leeres Objekt. Ein [Beispielmanifest](examples/organization-reader.manifest.json) lässt sich in der Plugin-Verwaltung einfügen. Das Manifest bleibt nach Registrierung unverändert; Manifest-Updates mit erneuter Freigabe sind eine spätere API-Version.

Der Worker prüft alle zwei Sekunden bis zu 25 Events, versucht eine fehlgeschlagene interne Zustellung höchstens fünfmal mit wachsender Wartezeit und legt sie dann als `dead_letter` ab. Replay bleibt manuell. Die eigene Node-ID wird mit der Datenbank gesichert; eine Restorekopie darf nicht parallel als aktiver zweiter Schreiber betrieben werden.

Auditoren dürfen Audit inklusive Benutzerkennungen firmenweit lesen; Viewer erhalten nur ihre Standortdaten. Abteilungen, delegierte Administration, MFA, Personalakten, Manifest-Updates und automatisierte Token-Erneuerung gehören nicht zu P1. Passwortänderungen durch Administratoren widerrufen alle Sitzungen des betroffenen Accounts; bei eigener Änderung folgt eine neue Anmeldung.

## Abnahme und Testwerkzeuge

Tests prüfen Upgrade mit bestehenden P0-IDs, frische Installation, Rechte/IDOR, konkurrierenden Schutz des letzten Admins, Versionskonflikte, widerrufene Sitzungen, Transaktionsrollback bei Auditfehler, Audit-Datenbankrechte, wiederholte Eventzustellung, Plugin-Scope/Deaktivierung und Geheimnisfreiheit der Antworten. Flutter prüft Controller-Fehlerpfade und bedienbare Verwaltungsansichten. Ein echter PostgreSQL-/HTTP-/Flutter-Smoke-Test ergänzt Analyzer und Tests. Backup/Restore widerruft sowohl Benutzer- als auch Plugin-Tokens.

Der [Implementierungsreview](implementation-review-2026-09-27.md) ergänzt unter anderem Ablauf während Sperrwartezeit, konkurrierende Dispatcher, Cursor-Grenzen und verlorene Erstellungsantworten. Ablaufprüfungen verwenden die aktuelle Datenbankzeit nach Sperrerwerb, nicht den Zeitpunkt des Transaktionsbeginns. Manifest-Namen und Anbieter erlauben keine Steuerzeichen.

`dart test test/platform_http_smoke_test.dart` in `apps/server` startet einen echten HTTP-Server auf einem freien Port und entfernt sein zufälliges Testschema im Anschluss. Voraussetzung ist `STOREOS_TEST_DATABASE`.

Für einen manuellen Browserdurchlauf gibt es `dart run tool/serve_smoke.dart`. Er verlangt eine Datenbank mit Suffix `_test` in `STOREOS_TEST_DATABASE`, das Runtime-Passwort in `STOREOS_TEST_RUNTIME_PASSWORD` und ein nur für diesen Lauf gewähltes Passwort (mindestens 24 Bytes) in `STOREOS_SMOKE_PASSWORD`. Optional setzt `STOREOS_TEST_RUNTIME_USER` den Datenbankbenutzer (sonst `storeos`). Port 8080 muss frei sein. Das Tool migriert ein zufälliges Schema, bootstrapt `smoke_admin`, bedient HTTP ausschließlich über die eingeschränkte Runtime-Rolle und entfernt das Schema bei regulärem `Ctrl+C`. Dazu den lokalen Flutter-Build auf 8085 öffnen. Bei hartem Prozessabbruch kann das ausdrücklich mit `storeos_browser_` benannte Testschema zur manuellen Prüfung verbleiben; keine Produktivdatenbank verwenden.
