# Review des P1b.5-Entwicklungszyklus

Stand: 2026-09-27. Ausschließlich die uncommitteten Änderungen seit `744cae3`
für [Blockierung und Klärung](phase-1b-blocking.md). Kein neuer Feature-Scope.

## Bestätigte und behobene Befunde

1. **P2 – Sichtbarer Begründungsentwurf überlebt ausdrückliches Verwerfen.**
   Beim Neuladen derselben Ausführungsversion leerte der Controller `reason`,
   während `TextFormField.initialValue` wegen identischem Widget-Key den alten
   Text behielt. Die Oberfläche zeigte somit Text, den der nächste Befehl nicht
   verwendete. Eine eigene Ausführungsgeneration erneuert nun das Feld beim
   bewussten Zurücksetzen, unabhängig von einer serverseitigen Versionsänderung.
   Der Widget-Regressionstest scheiterte vorher mit dem alten sichtbaren Text
   trotz leerem Controllerwert.
2. **P2 – Veralteter Klärungskontext nach Wechsel zu einem Schichtentwurf.**
   `newDraft()` entfernte die ausgewählte Aufgabe, ließ aber Begründung,
   Ausführung und Blockierungshistorie im Controller zurück. Dadurch entstanden
   erneut Verwerfen-Rückfragen und eine intern weiterhin freigegebene
   Wiederaufnahmeaktion ohne ausgewählte Aufgabe. Der bestätigte Kontextwechsel
   setzt jetzt auch die Ausführung zurück. Der Controller-Regressionstest
   scheiterte vorher an der nicht verworfenen Klärung.

Änderungen dieses Reviews: `shift_controller.dart`, `shift_section.dart`,
`task_blocking_test.dart` sowie dieser Bericht und Dokumentationsverweise.
Keine Backend-, API-, Rechte- oder Schemaänderung erforderlich. Migration 0008
bleibt unverändert; keine neue Migration.

## Weitere geprüfte Bereiche

- AGENTS.md, ADR 0001/0009/0010/0011/0012 und Modulgrenzen: Fachentscheidungen
  bleiben in Domain/Application; SQL und Blockierungshistorie gehören Tasks.
  Keine neue Kopplung zwischen privaten Tabellen verschiedener Fachmodule.
- Rechte/Scope: aktuelle Rolle und Sitzung vor jedem Befehl und Receipt-Replay;
  eigene Mitarbeiteridentität, Company und eingerichteter Standort. Plugins
  erhalten keine der neuen Fähigkeiten. Parameter werden gebunden, Gründe
  begrenzt und als Text gerendert; keine Freitexte im Audit-Payload.
- Integrität: Company-Sperre, erwartete Version, stabile Operations-ID,
  unveränderliche Snapshots/Resultate, genau eine offene Blockierung,
  explizite Freigabe und weiterhin separater Abschluss. Mutation, Audit und
  Receipt sind atomar. Mengen-/Rundungslogik ist nicht Teil dieses Slice.
- Migration: befülltes Upgrade 0007 → 0008 einschließlich Backfill und
  unverändertem Replay alter Receipts; SQL-Rechte und Historien-Schutz.
- Fehlerfälle: Konkurrenz, Antwortverlust, Wiederholung, Rechtewiderruf,
  ungültige Gründe, fehlende Mitarbeiterzuordnung und Rollback bei Fehlern an
  jeder Persistenzgrenze. Ladefehler sperren weitere Ausführungsaktionen bis
  zum erfolgreichen Abgleich; leere Listen sind von ungeladenen unterscheidbar.
- Performance: 50er-Pagination mit einem zusätzlichen Cursor-Datensatz,
  gemeinsame Instanzabfrage statt N+1-Roundtrips, keine Anleitungssnapshots in
  Listen. Keine neuen Integrationsereignisse ohne freigegebenen Verbraucher.

Keine weiteren bestätigten Fehler innerhalb des freigegebenen Scope gefunden.
Das ist keine formale Sicherheitszertifizierung oder Lasttest-Abnahme.

## Verbleibende bekannte Grenzen

Die bestehende Company-Sperre serialisiert auch Lesezugriffe. Historie und Receipts
haben weiterhin keine begrenzte Aufbewahrungsdauer; Gründe können trotz Hinweis
personenbezogene Angaben enthalten. Client/Server müssen gemeinsam aktualisiert
werden. Offlinequeue, Multi-Location-Synchronisation, Stornierung und Neuzuordnung
bleiben ausdrücklich außerhalb dieses Zyklus. Browser- und Restore-Nachweise der
Implementierung stehen im [Prüfnachweis](phase-1b-blocking-verification.md).

## Finale Prüfung

`scripts/dev.ps1 check` mit gesetztem STOREOS_TEST_DATABASE und echter PostgreSQL-
Integration erfolgreich (Exit 0), keine übersprungenen Datenbanktests:

| Paket | Bestanden |
| --- | ---: |
| API Contracts | 25 |
| Dart-Server inklusive PostgreSQL/HTTP | 77 |
| Flutter-Client inklusive Controller/Widgets | 97 |
| Design-System | 2 |
| Gesamt | **201** |

Alle vier Formatprüfungen ohne Änderungen, alle Analyzer ohne Befund.
Docker Compose config --quiet und git diff --check erfolgreich.
OpenAPI erneut geprüft: 58 eindeutige Operationen, 110 gültige interne
Referenzen und vorhandene externe Error-Response. Die beiden neuen
Regressionstests wurden vor der Korrektur jeweils rot nachgewiesen.
Protokolle: `.local/blocking-review-check.log`,
`.local/blocking-review-repro.log`, `.local/blocking-review-draft-repro.log`.
Für die ausschließlich im Client behobenen Zustandsfehler wurden gezielte
Controller-/Widgettests verwendet; Browser-Smoke und Backup/Restore wurden
in diesem Review nicht erneut ausgeführt.
