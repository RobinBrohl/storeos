# P1b.2 – Standortgebundene Arbeitsvorlagen

Freigegebener Slice: Admin → Entwurf → Bearbeitung → Freigabe → unveränderliche
Revision → Audit. Tasks besitzt Vorlagen und Revisionen unter `apps/server/lib/src/tasks/`.
Organization bestätigt eingerichtete Locations über seinen öffentlichen Port.
Der vorhandene lokale Server ist alleiniger Schreiber; Company und Location einer
Vorlage sind unveränderlich. Keine Schichten, Instanzen, Durchführung, Offlinequeue,
Medien, Zahleneingaben, Zeitregeln, Archivierung, Löschung oder neuen Pluginrechte.

## Modell und API-Vertrag

Eine Vorlage besitzt UUID, Company, Location, eine Konkurrenzversion und Zeitstempel.
Revisionen besitzen eigene UUIDs, fortlaufende Nummern, Zustand `draft`/`published`,
Inhaltsschema 1 sowie Freigabezeit und Account. Es existiert höchstens ein Entwurf.
Ein neuer Entwurf kopiert die jüngste Freigabe; historische Revisionen bleiben erhalten.
Alle Änderungen eines Aggregats prüfen dessen `expectedVersion`. Ein unverändertes
Speichern erhöht die Version nicht. PostgreSQL schützt veröffentlichte Revisionen
auch vor direkten UPDATE-/DELETE-Versuchen der Runtime-Rolle.

Der Inhalt umfasst Titel (1–120 Unicode-Codepoints) und 0–20 geordnete Schritte.
Jeder Schritt besitzt UUID, `type: confirmation` und nichtleeren Anleitungstext
(maximal 1.000 Codepoints). IDs sind innerhalb der Revision eindeutig. Freigabe
erfordert mindestens einen Schritt. Das normalisierte kompakte UTF-8-JSON des
gesamten Inhalts darf 8.192 Bytes nicht überschreiten. Der vorhandene HTTP-Body-Limit
von 16.384 Bytes bleibt erhalten. Text ist gültiger Unicode-Klartext, kein HTML oder ausführbarer Code; isolierte UTF-16-Surrogate werden zurückgewiesen.
Bestätigungen werden hier nur definiert, nicht ausgeführt oder gespeichert.

Routen unter `/api/v1/platform/task-templates`:

| Methode / Pfad | Zweck |
| --- | --- |
| GET `/` | Metadatenliste, 50 Einträge, `after`/`nextCursor` |
| POST `/` | Vorlage und erster Entwurf: `id`, `revisionId`, `locationId`, `content` |
| GET `/{id}` | Vorlagenmetadaten einschließlich aktueller Revisionsreferenzen |
| GET `/{id}/revisions` | Revisionsmetadaten, 50 Einträge, `after`/`nextCursor` |
| GET `/{id}/revisions/{revisionId}` | Inhalt einer bestimmten Revision |
| POST `/{id}/revisions` | Nächster Entwurf: `id`, `expectedVersion` |
| POST `/{id}/revisions/{revisionId}/edit` | Entwurf ändern: `content`, `expectedVersion` |
| POST `/{id}/revisions/{revisionId}/publish` | Freigeben: `expectedVersion` |

Erzeugungs-UUIDs bleiben bei unklarem Ausgang stabil. Wiederholte Erstellungen
liefern 409 ohne zweite Wirkung; der Client gleicht den Datensatz unter derselben
ID ab. Freigaben sind an Revisions-ID und ursprüngliche Basisversion gebunden;
identische Wiederholungen liefern die bestätigte Revision ohne erneuten Audit.
Andere veraltete Kommandos liefern 409. Rechte werden auch bei Wiederholung geprüft.
Kein generischer Command- oder Idempotenzdienst.

## Rechte, Audit und Ereignisse

`tasks.templates.manage` wird ausschließlich `admin` gewährt, innerhalb der eigenen
Company an deren eingerichteten Standorten. Alle anderen Rollen und Plugin-Tokens
haben keinen Vorlagenzugriff. Bestehendes `audit.read` bleibt unverändert.

Auditaktionen: `tasks.template.created`, `tasks.template.draft_updated`,
`tasks.template.revision_created`, `tasks.template.published`. Sie speichern IDs,
Revision, Konkurrenzversion, geänderte Feldnamen und Status mit Akteur, Standort,
UTC-Zeit und HTTP-Korrelation. Keine vollständigen Anleitungstexte in Audit oder Log.
Fachänderung und Audit committen atomar. Keine neuen Domain-/Integrationsereignisse,
da kein konkreter Verbraucher existiert.

## Abnahme und Tests

Echte HTTP-/PostgreSQL-Tests unter Runtime-Rechten prüfen Revision 1 und 2,
Neustart, unveränderliche Historie, Scope-/Rollenmatrix, Grenzen, konkurrierende
Bearbeitung/Entwurfserstellung/Freigabe, Antwortverlust, No-op und Audit-Rollback.
Migration von befülltem 0004 erhält vorhandene Identitäten, Mitarbeiter und Audit.
Unit-/Vertragstests prüfen Schema, UTF-8-Limits, Schritte und Zustände. Flutter
prüft Editor, Reihenfolge, Freigabe, Historie, Paging, Fehler, Konflikte und
Sitzungswechsel. Echte UI-/API-Smoke- und Backup-/Restoreprobe ergänzen den
vollständigen Formatter-/Analyzer-/Testlauf.

Die UI unterscheidet ungespeicherte Änderungen, bestätigten Entwurf, Freigabe,
Laden, Fehler und Konflikt. Alte Sitzungen dürfen keine Fortsetzungen unter neuen
Rechten auslösen. Listen enthalten keine Schrittinhalte. Die Vorlagenpflege ist
eine vollständige Verwaltungsfunktion, noch kein ausführbarer Mitarbeiterworkflow.
