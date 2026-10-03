# StoreOS

**Developer handover:** Start with [HANDOVER](docs/HANDOVER.md), [actual implementation status](docs/roadmap/status.md), [workflow/language policy](docs/development/workflow.md) and [current verification](docs/development/handover-verification.md). New technical material is written in English; existing German product and historical documentation is retained.

StoreOS ist ein langfristig angelegtes, quelloffenes Betriebssystem für standortgebundene Unternehmen. Es soll tägliche Arbeit, Wissen und betriebliche Daten in einer selbst betriebenen Plattform verbinden. Der erste fachliche Schwerpunkt ist die geführte Arbeit von Mitarbeitenden.

**Projektstand:** P1-Plattform und die Teilslices P1b.1 bis [P1b.8 – Stornierung veröffentlichter Schichten](docs/development/phase-1b-8-shift-cancellation.md) sind implementiert. Administratoren planen Einzelschichten und veröffentlichen Vorlagenrevisionen atomar als Aufgaben-Snapshots. Verknüpfte Mitarbeiter starten eigene Aufgaben, bestätigen geordnete Schritte, schließen sie ab oder melden ein Hindernis. Administratoren können blockierte Aufgaben zur Wiederaufnahme freigeben oder begründet stornieren und eine veröffentlichte Schicht vor Ausführungsbeginn stornieren. [P1b.9](docs/development/phase-1b-9-shift-amendment.md) ergänzt die Änderung von Beginn und Ende einer veröffentlichten Schicht, solange keine Aufgabe begonnen wurde, sowie die datenbankseitige Überschneidungssicherung; der Slice ist committet (`f37dd6b`), unabhängig geprüft und remote CI-verifiziert. Zahlenschritte prüfen feste inklusive Grenzen; Werte außerhalb der Grenzen bleiben gespeichert und blockieren die Aufgabe bis zur Klärung. P1b bleibt teilweise implementiert: Mitarbeiter-/Vorlagenänderungen veröffentlichter Schichten, der Umgang mit begonnener Arbeit und Offline-Schreiben fehlen weiterhin. Committet als `a4aeecd`, korrigiert durch `d0fcf43` (web-sichere Versionsgrenzen) und `d90dd7e` (Stabilisierung der numerischen E2E-Synchronisation) und remote CI-verifiziert (Lauf 31), ergänzt [P4.1 – Artikelstamm](docs/development/phase-4-1-article-master.md) einen unternehmensweiten Produktstamm mit SKU, optionalem Barcode, Einheit, aktiv/inaktiv-Lebenszyklus, Audit und Flutter-Verwaltung; Bestandsführung, Lieferanten, Bestellungen, Preise, HACCP, POS und Accounting bleiben weiterhin außerhalb des aktuellen Umfangs. `unit` ist dabei eine Bezeichnung ohne Umrechnung. Im Arbeitsbaum (uncommittet, Review und remote CI ausstehend) ergänzt [P4.2 – Standort-Sortiment](docs/development/phase-4-2-location-assortment.md) eine standortbezogene Freigabe, welche Unternehmensartikel ein Standort führt; Sortiments- und Artikelstatus sind unabhängig, wirksam ist nur die Konjunktion. Weiterhin kein Bestand und keine Mengen.

**Upgrade auf P1b.7:** Datenbank sichern, Server stoppen, `./scripts/dev.ps1 migrate` ausführen und Server/Client gemeinsam aktualisieren und neu starten. Ausstehende Migrationen werden der Reihe nach angewendet; `0010` ergänzt Inhaltsschema 2 und unveränderliche Zahlenversuche; Schema-1-Snapshots und alte Receipts bleiben erhalten. Server und Client gemeinsam aktualisieren: alte Clients verstehen numerische Schritte nicht. Unter **Schichten** einen aktiven Mitarbeiter und UTC-Zeiten wählen, veröffentlichte Revisionen zuordnen, speichern und veröffentlichen. Mitarbeiter öffnen anschließend **Meine Arbeit**. Eine veröffentlichte Schicht kann weiterhin nicht bearbeitet werden; P1b.8 ergänzt die begründete Stornierung vor Ausführungsbeginn, getrennt von der Stornierung blockierter Aufgaben.

## Lokal starten

Voraussetzungen: Flutter **3.47.5** mit Dart **3.13.4**, Docker mit Compose und laufendem Linux-Container-Daemon, PowerShell **7.4 oder neuer** (`pwsh`). Die Toolchain-Versionen entsprechen der CI. Ports 5432 (PostgreSQL), 8080 (API) und 8085 (Flutter) müssen frei sein; Datenbank und API sind im Entwicklungsbetrieb nur an Loopback gebunden.

Im Repository-Hauptverzeichnis:

```powershell
./scripts/dev.ps1 setup
./scripts/dev.ps1 get
./scripts/dev.ps1 db
./scripts/dev.ps1 migrate
./scripts/dev.ps1 bootstrap
./scripts/dev.ps1 server
```

`setup` erzeugt einmalig `.env`, stabile Company-/Location-IDs und zufällige Secrets in `.local/secrets/`. Es verändert eine vorhandene Installation nicht. `migrate` ist wiederholbar; `bootstrap` legt genau einen lokalen Administrator und die noch nicht benannten Company-/Location-Datensätze an. Nach Anmeldung werden die tatsächlichen Organisationsnamen eingerichtet. Der Bootstrap-Vorgang lässt sich nach erfolgreicher Anlage nicht wiederholen.

**Upgrade von P0:** Server stoppen, `.env`, Secrets und Datenbank sichern, `./scripts/dev.ps1 migrate` ausführen und Server/Client neu starten. `bootstrap` nicht erneut aufrufen. Bestehende IDs und Passwort-Hashes bleiben erhalten; ausschließlich der ursprüngliche Bootstrap-Account erhält beim Upgrade die Administratorrolle. Angewendete Migrationsdateien niemals ändern.

**Upgrade von P1 auf P1b.1:** Ebenso sichern, Server stoppen, migrieren und Server/Client neu starten. Migration `0004` ergänzt Mitarbeiter, Account-Verknüpfungen, die Rolle `employee` und Audit-Korrelation. Bestehende Accounts werden nicht automatisch verknüpft; Rollen bleiben erhalten. Historische Audit-Korrelation bleibt unbekannt (`null`). Bei einem statisch ausgelieferten Flutter-Build den Client neu bauen und den Browser neu laden.

**Upgrade auf P1b.2:** Datenbank sichern, Server stoppen, `./scripts/dev.ps1 migrate` ausführen und Server/Client neu starten beziehungsweise den statischen Flutter-Build erneuern. Migration `0005` ergänzt ausschließlich Vorlagen und Revisionen mit Datenbankrechten und Schutz freigegebener Inhalte. Bestehende Daten und Rollen bleiben erhalten.

**Task templates:** As an administrator, choose a title and configured location under "Arbeitsvorlagen", add steps, save the draft and publish its revision. Publication requires at least one fully defined supported step: confirmation or numeric. Numeric steps require a unit and inclusive bounds. For changes, create a new revision; published history remains immutable. Compare conflicts with the current server state before explicitly adopting it. Saving and publishing require the site server. [Template scope](docs/development/phase-1b-templates.md), [numeric extension](docs/development/phase-1b-7-numeric-steps.md).

**Mitarbeiterprofil verwenden:** Als Administrator zuerst Organisation und Standort einrichten, unter „Mitarbeiter“ ein Profil anlegen und einen vorhandenen aktiven Account desselben Standorts verknüpfen. Die Account-Rolle wird separat in der Benutzerverwaltung vergeben; `employee` darf nur die eigene Organisation und das eigene verknüpfte Profil lesen. Verknüpfen, Entziehen und Profildeaktivierung widerrufen betroffene Sitzungen. Nach erneuter Anmeldung erscheint „Mein Mitarbeiterprofil“. Das ist eine Profilansicht ohne Schichten oder Aufgaben. [Rechte, Grenzen und API](docs/development/phase-1b-employee.md).

In einem zweiten Terminal:

```powershell
./scripts/dev.ps1 client
```

Öffne [StoreOS lokal](http://127.0.0.1:8085). Benutzername: Wert `STOREOS_BOOTSTRAP_USERNAME` aus `.env` (standardmäßig `operator`). Das lokal erzeugte Anfangspasswort liegt in `.local/secrets/bootstrap_password.txt`; nur lokal lesen und nicht in Chats, Logs oder Git übernehmen. Der Client hält die Sitzung ausschließlich im Arbeitsspeicher. Nach Neuladen ist eine erneute Anmeldung erforderlich. Er zeigt den echten Verbindungs- und Datenbankstatus; bei Fehlern erscheint keine vermeintlich aktuelle Erfolgsanzeige.

Server und Flutter lassen sich mit `Ctrl+C` stoppen; `docker compose stop db` stoppt die Datenbank ohne Datenverlust. `docker compose down --volumes` würde die Datenbank löschen und gehört **nicht** zum normalen Stoppen. Bestehende IDs, Datenvolumes und Secrets für weitere Starts beibehalten.

## Konfiguration und Betrieb

`.env.example` dokumentiert lokale Einstellungen. Die Entwicklungsskripte laden `.env` ohne Shell-Auswertung und lösen relative Secret-Pfade gegen das Repository auf. Bereits gesetzte Umgebungsvariablen haben Vorrang. Direkte Dart-Aufrufe laden keine `.env` automatisch. Der Server validiert Ports, Scopes, Origins und Secrets beim Start und bricht bei ungültiger Konfiguration ab.

- API: `GET /health` prüft den HTTP-Prozess; `GET /ready` prüft zusätzlich Datenbank und Schema. Nur `/ready` ist ein Bereitschaftsnachweis.
- [API-Verträge / OpenAPI](packages/api_contracts/openapi.yaml) und [Plattformverträge](docs/development/phase-1.md) beschreiben Anmeldung, Standort-Systemstatus und Verwaltung.
- [Docker-Betrieb](infra/docker/README.md) beschreibt Backend-Container sowie getrennte Migrations- und Bootstrap-Kommandos.
- [Lokales TLS](infra/reverse_proxy/README.md) beschreibt den optionalen HTTPS-Zugang. HTTP ist ausschließlich für Loopback-Entwicklung vorgesehen; LAN-Betrieb benötigt vertrauenswürdig eingerichtete Zertifikate.
- [Backup und Restoreprobe](infra/backup/README.md) sichern die Datenbank verschlüsselt und prüfen eine isolierte Wiederherstellung. Den Wiederherstellungsschlüssel separat vom Server und Backup aufbewahren.

Die Compose-Referenz verwendet `storeos` als eingeschränkten Runtime-Datenbanknutzer und `storeos_owner` für Migrationen/Bootstrap. Der HTTP-Prozess erhält das Owner-Secret nicht. Initialisierungsskripte laufen nur beim ersten Start eines **leeren** PostgreSQL-Volumes; geänderte Secret-Dateien rotieren bestehende Datenbankpasswörter nicht automatisch.

## Prüfungen

```powershell
./scripts/dev.ps1 check
# Bei laufendem Server und eingerichteter Datenbank:
./scripts/dev.ps1 smoke
```

`check` führt `dart format --output=none --set-exit-if-changed`, `dart analyze`, `dart test`, `flutter analyze`, `flutter test` in den passenden Packages und `docker compose config --quiet` aus. Zum Anwenden der Formatierung: `dart format apps/server packages/api_contracts apps/client_flutter/lib apps/client_flutter/test packages/design_system`.

Die PostgreSQL-Integrationstests benötigen zusätzlich `STOREOS_TEST_DATABASE` als PostgreSQL-Verbindungs-URI zu einer ausdrücklich dafür vorgesehenen Testdatenbank (Details im [Server-README](apps/server/README.md)). Sie verwenden isolierte Schemas und prüfen echte Transaktionen. Ohne diese Variable werden sie sichtbar übersprungen; das ersetzt keine vollständige Abnahme. Die CI richtet eine eigene PostgreSQL-Testdatenbank ein. Der Smoke-Test prüft Liveness, Readiness, Anmeldung, stabile Organisations-IDs, Rechte, Audit-/Event-/Plugin-Abfragen, Standortgrenzen und Sitzungswiderruf ohne Ausgabe von Zugangsdaten. Er verwendet den ursprünglichen Bootstrap-Zugang; nach dessen Passwortänderung sind eigene aktuelle Testzugänge zu verwenden.

### Numerischen Mitarbeiterablauf im Browser prüfen

Für den automatisierten P1b.7-Ende-zu-Ende-Test werden ein laufender PostgreSQL-Server,
Flutter 3.47.5, Chrome und ein zu Chrome passender ChromeDriver aus
[Chrome for Testing](https://googlechromelabs.github.io/chrome-for-testing/) benötigt.
`STOREOS_TEST_DATABASE` muss auf eine **eigene** PostgreSQL-Datenbank mit dem
Namenssuffix `_test` zeigen. Der Datenbank-Owner braucht Rechte für Schemas und
Migrationen. `STOREOS_DB_USER` und `STOREOS_DB_PASSWORD_FILE` bezeichnen einen
eingeschränkten Runtime-Account mit Zugang zu dieser Testdatenbank. Diese
drei Variablen müssen ausdrücklich gesetzt sein; das Testskript lädt die lokale
`.env` nicht und verwendet keine Daten des regulären Standorts.

Mit diesen Voraussetzungen genügt aus dem Repository-Hauptverzeichnis ein Aufruf:

```powershell
./scripts/e2e/Run-NumericGuidedWork.ps1 -ChromeDriverPath '<Pfad zum passenden chromedriver>'
```

Das Skript erstellt ein neues isoliertes Schema, migriert und richtet nur darin
Testdaten ein. Es startet den echten Dart-Server, ChromeDriver und den
Flutter-Webclient, führt den Mitarbeiter-/Administratorablauf aus und prüft
nach dem Browserlauf die persistierten Ergebnisse. Ein fehlendes Werkzeug,
ein Timeout, ein fehlgeschlagener Test oder fehlgeschlagenes Aufräumen führt zu
einem Fehlerstatus. Nur selbst gestartete Prozesse und das selbst erzeugte
Schema werden beendet. Das temporäre Manifest mit Testzugängen wird nach dem
Lauf gelöscht; Prozesslogs liegen im ignorierten `.local/`. Der CI-Job
`numeric-guided-work-e2e` führt denselben Aufruf
mit einer eigenen Testdatenbank und fest gepaartem Chrome/ChromeDriver aus.
[Prüfnachweis und verbleibende Grenzen](docs/development/phase-1b-7-numeric-verification.md).

### Kontrolliertes Update/Recovery abnehmen (P2)

`./scripts/update/Run-UpdateRecoveryAcceptance.ps1` proves the supported
single-site update contract on a run-scoped database: a real 0010 schema built
from byte-identical migration copies, an encrypted pre-update restore point, the
real pending migrations through the production runner, preservation of
pre-update evidence, the published-interval exclusion constraint, a
current-server HTTP smoke including a bounded interval amendment and isolated
recovery into a fenced `storeos_restore_upd_*` target. It never touches the
normal StoreOS database and always cleans up its own databases; only a sanitized
report remains under `.local/update-recovery/<run-id>/`. "Recovery" is
restore-point recovery, not a database or application downgrade; replacement
activation and down migrations are not supported. Failure-path modes:
`-InjectFailureAfter prepare|upgrade|recovery`.
[Contract and evidence](docs/development/phase-2-update-recovery-acceptance.md).

Weitere Implementierungsgrenzen und Abnahmekriterien: [Phase-0-Grundlage](docs/development/phase-0.md), [Phase-1-Plattform](docs/development/phase-1.md) und [Phase-1-Prüfnachweis](docs/development/phase-1-verification.md). Plugin-Registrierungen sind externe API-Clients mit ausdrücklicher Freigabe; StoreOS installiert oder startet keinen fremden Code. Der Client hält auch Plugin-Tokens nur zur einmaligen Anzeige im Arbeitsspeicher. Separate Standortserver und Unternehmenssynchronisation sind noch nicht implementiert.

## Einstieg

Der [P1b.1-Prüfnachweis](docs/development/phase-1b-verification.md) dokumentiert Tests, Upgrade, Browser-Smoke und Restore der Mitarbeiteridentität.

Der [P1b.2-Prüfnachweis](docs/development/phase-1b-templates-verification.md) dokumentiert die Arbeitsvorlagen-Abnahme.

- [Vision](docs/vision.md) und [Produktprinzipien](docs/product-principles.md)
- [Architektur](docs/architecture/overview.md), [kritische Prüfung](docs/risks-and-open-questions.md) und [ADRs](docs/adr/)
- [Entwicklungsphasen](docs/roadmap/phases.md) und [Compliance-Überblick](docs/compliance/overview.md)
- [Regeln für Mitwirkende und Agenten](AGENTS.md)

## Repository

```text
apps/       Auslieferbare Server- und Flutter-Anwendungen
packages/   Technische, fachlich neutrale Verträge und UI-Bausteine
modules/    Fachliche Module des modularen Monolithen (noch nicht angelegt)
plugins/    Spätere externe Erweiterungen und Beispiele
infra/      Docker, lokaler TLS-Proxy, verschlüsselte Backups und Restoreprobe
scripts/    Lokales Setup, Start, Prüfungen und API-Smoke-Test
docs/       Verbindliche Produkt- und Architekturgrundlagen
```

Vier unabhängige Packages bilden das Monorepo: `apps/server`, `apps/client_flutter`, `packages/api_contracts` und `packages/design_system`. Lokale Pfadabhängigkeiten und eingecheckte Lockfiles genügen zunächst; der Server benötigt keine Flutter-Laufzeit. `modules/`, `packages/shared`, `packages/plugin_sdk` und `plugins/` bleiben dokumentierte Platzhalter. Der erste ausführbare Client ist Web; native Runner und deren gerätespezifische Freigabe folgen gesondert.

## Lizenz

Der Repository-Quelltext steht unter der [GNU AGPLv3](LICENSE). Vor dem Einbringen fremder Komponenten oder proprietärer Integrationen sind deren Lizenzbedingungen gesondert zu prüfen.

## P1b.4: Bestätigungsaufgaben ausführen

[Scope und API](docs/development/phase-1b-execution.md), [Prüfnachweis](docs/development/phase-1b-execution-verification.md).
Vor Upgrade Backup erstellen, Server stoppen, `./scripts/dev.ps1 migrate` ausführen
und Server sowie Webclient gemeinsam aktualisieren. Migration 0007 erhält vorhandene
Aufgaben und ergänzt die Ausführung; alte Clients stellen deren Status nicht zuverlässig dar.

Ein verknüpfter Mitarbeiter öffnet **Meine Arbeit**, startet eine eigene Aufgabe
während ihrer Schicht, bestätigt die Schritte und schließt separat ab. **Laufende
Aufgaben** bleiben nach Schichtende erreichbar. Bestätigter Fortschritt überlebt
Neuladen und erneute Anmeldung. Admins sehen den Fortschritt in **Schichten** und
Änderungen im Audit. Bei Antwortverlust den unbestätigten Befehl ausdrücklich erneut
senden oder den Serverstand laden; ohne Standortserver gibt es keinen bestätigten
Abschluss. Keine Messwerte, Ausnahmen, stellvertretenden Abschlüsse oder Offlinequeue.

## P1b.5: Blockierungen und Wiederaufnahme

Mitarbeitende können eigene laufende Aufgaben mit Begründung blockieren. Unter
„Blockierte Aufgaben am Standort“ kann ein Administrator die Klärung dokumentieren
und die Wiederaufnahme freigeben. Der Mitarbeiter bestätigt anschließend selbst
alle verbleibenden Schritte und den Abschluss. Blockierungen bleiben nach
Schichtende sichtbar; die Historie wird nicht überschrieben.

Vor dem Start `./scripts/dev.ps1 migrate` ausführen: Migration 0008 erhält bestehende
Aufgaben und Befehlsnachweise. Backend und Flutter-Webclient gemeinsam aktualisieren
und neu starten; alte Clients verstehen blocked nicht. Keine Messwerte,
Stellvertretung oder Offline-Schreibqueue. [Scope und Rechte](docs/development/phase-1b-blocking.md).

### Blockierte Aufgaben stornieren (P1b.6)

Administratoren können blockierte Aufgaben mit Pflichtgrund und ausdrücklicher Bestätigung endgültig stornieren. Stornierte Aufgaben bleiben über die gezielt ladbaren Listen für berechtigte Mitarbeiter und Administratoren erreichbar, auch nach Schichtende. Vorherige Nachweise bleiben erhalten; eine Stornierung ist kein erfolgreicher Abschluss. Migration 0009 und Client zusammen ausrollen; ältere Clients verstehen `cancelled` nicht. [Scope und Grenzen](docs/development/phase-1b-cancellation.md), [Abnahme](docs/development/phase-1b-cancellation-verification.md) und [Review mit finalen Testergebnissen](docs/development/phase-1b-cancellation-review-2026-09-27.md).

### Zahlenwerte erfassen (P1b.7)

Unter **Arbeitsvorlagen** einen Zahlenschritt mit Anleitung, Einheit und inklusiven
Unter-/Obergrenzen hinzufügen, speichern und freigeben. Bestätigungs- und Zahlenschritte
können kombiniert werden. Werte verwenden maximal drei Nachkommastellen im Bereich
-999999.999 bis 999999.999; der Client erlaubt Komma oder Punkt, keine Tausendertrennung.
Es wird nicht gerundet und nicht zwischen Einheiten umgerechnet.

Ein Mitarbeiter erfasst im aktuellen Schritt einen Wert. Werte außerhalb der Grenzen
werden als Versuch gespeichert und blockieren die Aufgabe ohne Schrittbestätigung.
Nach administrativer Wiederaufnahme ist eine neue Eingabe erforderlich. Stornierung
bewahrt sämtliche Versuche. **Zahlenversuche** zeigt die paginierte Historie; Messwerte
stehen nicht im allgemeinen Audit-Log. Keine Sensorintegration oder HACCP-Zertifizierung.
[Vertrag und Abnahme](docs/development/phase-1b-7-numeric-steps.md).
