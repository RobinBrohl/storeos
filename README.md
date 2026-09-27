# StoreOS

StoreOS ist ein langfristig angelegtes, quelloffenes Betriebssystem für standortgebundene Unternehmen. Es soll tägliche Arbeit, Wissen und betriebliche Daten in einer selbst betriebenen Plattform verbinden. Der erste fachliche Schwerpunkt ist die geführte Arbeit von Mitarbeitenden.

**Projektstand:** P1-Plattform, P1b.1 Mitarbeiteridentität, P1b.2 Arbeitsvorlagen und [P1b.3 Schichten mit lesendem Employee Home](docs/development/phase-1b-shifts.md). Administratoren planen Einzelschichten und veröffentlichen ausgewählte Vorlagenrevisionen atomar als Aufgaben-Snapshots. Verknüpfte Mitarbeiter lesen ihre geplante Arbeit und Anleitungen. Guided Work, Completion, Änderungen veröffentlichter Schichten und Offline-Schreiben sind noch nicht implementiert. Warenwirtschaft, HACCP, POS und Accounting bleiben außerhalb des aktuellen Umfangs.

**Upgrade auf P1b.3:** Datenbank sichern, Server stoppen, `./scripts/dev.ps1 migrate` ausführen und Server/Client neu starten. Migration `0006` ergänzt Schichten, Revisionszuordnungen und Aufgabeninstanzen; bestehende Daten bleiben erhalten. Unter **Schichten** einen aktiven Mitarbeiter und UTC-Zeiten wählen, veröffentlichte Revisionen zuordnen, speichern und veröffentlichen. Mitarbeiter öffnen anschließend **Meine Arbeit**. Eine Veröffentlichung kann derzeit nicht korrigiert oder storniert werden.

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

**Arbeitsvorlagen verwenden:** Als Administrator unter „Arbeitsvorlagen“ einen Titel und eingerichteten Standort wählen. Anleitungsschritte ergänzen, Entwurf speichern und Revision freigeben. Für Änderungen eine neue Revision aus der letzten Freigabe anlegen; alte Revisionen bleiben lesbar. Freigabe benötigt mindestens einen vollständigen Bestätigungsschritt. Die Eingaben definieren Anleitungen, keine Aufgabenausführung. Bei Konflikten lokale Eingaben mit dem angezeigten Serverstand vergleichen und diesen ausdrücklich übernehmen. Ohne Verbindung zum lokalen Server sind Speichern und Freigabe nicht möglich. [Umfang und Grenzen](docs/development/phase-1b-templates.md).

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
und neu starten; alte Clients verstehen blocked nicht. Keine Messwerte, Stornierung,
Stellvertretung oder Offline-Schreibqueue. [Scope und Rechte](docs/development/phase-1b-blocking.md).
