# P1b.3 – Schichtveröffentlichung und lesendes Employee Home

Freigegebener Teilslice vom 2026-09-27. Ziel ist ausschließlich:
Administrator erstellt eine Einzelschicht, wählt veröffentlichte Revisionen,
veröffentlicht atomar und der zugeordnete Mitarbeiter liest seinen Arbeitsplan.
Guided Work und Completion bleiben eine spätere Freigabe.

## Modell und Regeln

Workforce besitzt `shifts` und `shift_template_selections`. Ein Entwurf hat genau
einen Mitarbeiter, einen unveränderlichen Standort und Mandanten, ein UTC-Intervall
und null bis zehn geordnete, explizite Revisionsreferenzen. Jede Vorlage kommt
höchstens einmal vor. Beginn muss vor Ende liegen; Eingaben ohne Zeitzone und
ungültige Kalenderwerte werden abgewiesen. Die UI zeigt ausdrücklich UTC; die
konzeptionelle IANA-Standortzeitzone ist noch kein implementiertes Feld.

Der Mitarbeiter muss aktiv und seine Standortzuordnung für das ganze Intervall
gültig sein. Alle Revisionen sind veröffentlicht und am selben Standort.
Veröffentlichung braucht mindestens eine Auswahl und eine noch nicht beendete
Schicht. Veröffentlichte Intervalle desselben Mitarbeiters dürfen sich nicht
überschneiden; angrenzende Intervalle sind erlaubt. Dies ist eine Datenintegritäts-
regel, keine vollständige arbeitsrechtliche Dienstplanprüfung.

Tasks besitzt `task_instances`: pro Schicht/Vorlage genau eine Instanz mit
expliziter Mitarbeiterzuordnung, Revisionsreferenz, Reihenfolge und unveränderlichem
Schema-1-Inhaltssnapshot. Instanzen sind `open`, Version 1 und in diesem Slice
ausschließlich lesbar. Eine spätere Migration muss Zustandswechsel ausdrücklich
freigeben; es gibt keine vorbereiteten Ausführungsbefehle.

`ShiftApplication` koordiniert `WorkforceService`, `TaskInstanceService`, People,
Identity und Organization über öffentliche Ports mit derselben `TxSession`.
Kein Modul liest oder schreibt Repositorytabellen eines anderen Moduls. Der
bestehende Company-Lock serialisiert Veröffentlichungen, Bearbeitungen und
Mitarbeiterdeaktivierungen. Es gibt keine verschachtelten Autorisierungstransaktionen.

## Idempotenz, Konkurrenz und Audit

Der Client erzeugt eine stabile Entwurfs-ID. `creation_input` bindet diese ID an
den normalisierten ursprünglichen Inhalt, `created_by` an den Akteur. Identische
Wiederholung liefert den aktuellen Datensatz; anderer Inhalt/Akteur/Standort wird
abgewiesen. Bearbeitung braucht die erwartete Version; No-op verändert weder
Version noch Audit. Veröffentlichte Schichten, Auswahlen und Snapshots sind gegen
Runtime-Änderung geschützt. Kein Löschen, Stornieren oder Neuzuordnen.

Schichtveröffentlichung, alle Instanzen und Audit committen gemeinsam gemäß
ADR 0011. Wiederholung mit ursprünglicher `expectedVersion` liefert dieselben
Instanz-IDs, ohne neue Vorlagenauswahl oder zusätzliche Auditwirkung. Rechte und
Session werden bei jeder Wiederholung erneut geprüft. Nachträgliche Deaktivierung
verändert den historischen Plan nicht, sperrt aber den Eigenzugriff.

Auditaktionen:

- `workforce.shift.created`
- `workforce.shift.draft_updated`
- `workforce.shift.published`
- `tasks.instance.created`

Enthalten sind Akteur, Company, Location, Objekt, Version, Status, relevante
Mitarbeiter-/Revisionsreferenzen und Schichtzeiten; Entwurfsänderungen benennen die
geänderten Felder. Alle Einträge einer Veröffentlichung teilen die Korrelations-ID.
Keine Anleitungen oder vollständigen Personaldaten in Audit/Logs.

**Keine neuen Integrationsereignisse.** Employee Home liest synchron; ein konkreter
Folgeverbraucher fehlt. `shift.published.v1` bleibt für spätere Folgereaktionen
vorgesehen. Es gibt keine zweite Aufgabenerzeugung über den Event Bus und keine
Erweiterung der Plugin-Freigaben. Audit gilt unabhängig davon.

## Rechte und API

Nur Admin: `workforce.shifts.manage`, `tasks.instances.read`.
Admin und Employee: `workforce.shifts.self.read`, `tasks.instances.self.read`,
jeweils zusätzlich mit aktiver Account-Mitarbeiter-Verknüpfung und passendem
Company-/Location-Kontext. Auditor/Viewer erhalten keine Schichtdaten;
bestehender, separat berechtigter Auditzugriff bleibt bestehen. Plugin-Tokens sind
keine Benutzer-Sessions und werden abgewiesen.

Alle Routen beginnen mit `/api/v1/platform`:

| Methode / Route | Zweck |
| --- | --- |
| GET /shifts | Admin-Liste, 50 Datensätze pro Seite |
| POST /shifts | Entwurf anlegen bzw. identische Anlage wiederholen |
| GET /shifts/{id} | Schicht und Aufgabenmetadaten |
| POST /shifts/{id}/edit | Entwurf mit erwarteter Version bearbeiten |
| POST /shifts/{id}/publish | Atomare Veröffentlichung |
| GET /shifts/{id}/tasks/{taskId} | Aufgaben-Snapshot lesen |
| GET /employee-home/shifts | Eigene veröffentlichte Schichten mit Ende nach Serverzeit |
| GET /employee-home/shifts/{id} | Eigene veröffentlichte Schicht; direkter historischer Zugriff bleibt erlaubt |
| GET /employee-home/shifts/{id}/tasks/{taskId} | Eigene Anleitung |

Listen sortieren nach Beginn/ID und verwenden einen opaken `after`-Cursor.
Aufgabenmetadaten werden für eine Seite gemeinsam geladen; Inhalte nur im Detail.
Employee Home ist eine berechtigte Application-Abfrage ohne persistierte Projektion.
Es gibt keine vom Client frei wählbare Mitarbeiter-ID für Eigenabfragen.

400: ungültiger Vertrag/Cursor; 401: ungültige Sitzung oder Plugin-Token;
403: fehlendes Recht; 404: nicht sichtbares Objekt/fehlendes eigenes Profil;
409: Versions-/Identitätskonflikt oder Überschneidung;
422: ungültige Zuordnung, Auswahl oder Veröffentlichungsbedingung;
503: Datenbankfehler ohne bestätigte Fachänderung.

## Bedienung und Betrieb

Unter **Schichten** Mitarbeiter und explizite UTC-Zeiten eintragen, Revisionen
wählen, Entwurf speichern und Veröffentlichung bestätigen. Der Warnhinweis nennt
die fehlende spätere Korrektur/Stornierung. **Meine Arbeit** zeigt geplante Arbeit,
keine tatsächliche Anwesenheit und keine ausführbaren Abschluss-Schaltflächen.

Controller halten Eingaben und Sitzungsgrenzen; Widgets zeigen deren Zustand.
Antwortverlust wird gegen Inhalt und Version abgeglichen. Unbestätigte Befehle
bleiben gesperrt und behalten ihren ursprünglichen Inhalt zur bewussten Wiederholung.
Konflikte erfordern ausdrückliches Laden des Serverstands. Sitzungsende verwirft
lokale Daten; Eingaben sind nicht dauerhaft gespeichert.

Migration `0006_shifts_and_task_instances.sql` ist additiv. Vor Upgrade sichern,
Server stoppen, migrieren, neu starten. Bestehende Migrationen bleiben unverändert.
Neue Tabellen sind im regulären PostgreSQL-Backup enthalten; Restore widerruft
Sitzungen wie bisher. [Prüfnachweis](phase-1b-shifts-verification.md).

## Ausdrücklich ausgeschlossen

Guided Work, TaskExecution/StepResult, Completion, Änderungen veröffentlichter
Schichten, Serienplanung, Kalender, Anwesenheit, Zeiterfassung, Skills, Optimierung,
Standortzeitzonenverwaltung, Offline-Schreibqueue, Zentralsync, neue Plugins sowie
Warenwirtschaft, HACCP, POS und Accounting. Keine allgemeine Scheduling-Engine.
