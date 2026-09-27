# Review P1b.6 – Stornierung blockierter Aufgaben

Geprüft wurde ausschließlich der noch uncommittete Stornierungs-Slice seit `925ab52`
gegen AGENTS.md, ADR 0009/0010/0011/0012, Modulgrenzen und den
[verbindlichen Scope](phase-1b-cancellation.md). Keine neuen Fachfunktionen.

## Gefundene und behobene Probleme

1. **Falscher Leerzustand nach bestätigter Stornierung (P2).** Der Controller setzte
   die noch nicht geladene Stornierungsliste vor der Abfrage auf `[]`. Scheiterte das
   Nachladen, zeigte Flutter „Keine stornierten Aufgaben“, obwohl gerade eine Aufgabe
   storniert worden war. Die Liste bleibt jetzt bis zur erfolgreichen Abfrage unbekannt.
   Der bekannte terminale Ausführungsstatus löst das Nachladen aus, auch nach einem
   ausdrücklichen Serverabgleich bei Antwortverlust.
2. **Veraltete offene Blockierung im terminalen Detail (P2).** Nach bestätigter
   Stornierung konnte ein Fehler beim Laden der Listen oder Historie die bisherige
   Anzeige „Noch ungeklärt“ stehen lassen. Eine bestätigte Stornierung verwirft diese
   überholte Historie. Beim Abgleich wird die Historie vor den Listen aktualisiert;
   fehlgeschlagenes Nachladen zeigt weiterhin einen Fehler und keine alte offene
   Blockierung. Ein erneutes Laden stellt den bestätigten Grund wieder her.
3. **Unvollständig angepasster OpenAPI-Detailvertrag (P2).** Das im Slice erweiterte
   TaskInstanceDetail erlaubte cancelled, aber weiterhin nur Version 1. Außerdem
   fehlten die tatsächlich serialisierten confirmedSteps/totalSteps bei
   additionalProperties=false. Der Vertrag beschreibt jetzt die vorhandene Antwort
   einschließlich Version und Fortschritt korrekt. Die kopierten Antwortbeschreibungen
   der Stornierungslisten benennen jetzt cancelled statt blocked. Kein API-Verhaltenswechsel.

Die zwei neuen Flutter-Regressionstests schlugen vor der Korrektur mit `[] statt null`
bzw. einer veralteten TaskBlockingDto fehl. Ein zusätzlicher Contract-Test schlug mit
den fehlenden Antwortfeldern fehl. Alle drei prüfen zusätzlich den korrigierten Zustand.

## Weitere geprüfte Bereiche

- Tasks bleibt Eigentümer von Status, Historie und Invarianten. Application koordiniert
  Rechte und Modul-Ports; Widgets und Routen delegieren. Keine neuen Abstraktionen oder
  Dependencies. Keine Änderung an Workforce-/People-Daten durch Stornierung.
- Berechtigung, aktive Sitzung und Scope werden vor einem Replay erneut geprüft.
  Adminrecht wird nicht auf Mitarbeiter, Viewer, Auditor oder Plugins ausgedehnt.
- Statuswechsel, Abschlussgrund, Audit und Receipt liegen in derselben Transaktion.
  Versionsprüfung und Company-Sperre serialisieren cancel/resume und Wiederholungen.
  Die vorhandenen Integrationstests prüfen Rollback an allen vier Schreibgrenzen.
- Snapshot und bestätigte Schritte bleiben erhalten; cancelled ist terminal und kein
  completed. Mengen-/Rundungsberechnungen sind in diesem Slice nicht vorhanden.
- Pflichtgrund wird begrenzt und normalisiert. Freitext bleibt außerhalb des Audit-
  Payloads und der technischen Logs. Fachhistorie unterliegt bestehenden Leserechten.
- Listen sind auf 50 Einträge plus Cursor begrenzt. IDs und Metadaten werden gesammelt
  abgefragt; keine neue SQL-Abfrage pro Listeneintrag. Historie ist ebenfalls paginiert.
- Befülltes Upgrade, terminale SQL-Schutzregeln, Rechteentzug, Standort-/Mandantentrennung,
  Plugin-Abweisung, Schichtende und deaktivierte Mitarbeiter sind durch Integrationstests
  abgedeckt. Keine weitere belegte Korrektur im geprüften Scope erforderlich.

## Verbleibende Grenzen

Die bestehende Company-Sperre begrenzt Parallelität. Historien und Receipts besitzen
weiterhin keine automatische Aufbewahrungsbereinigung. Datenbank-Owner können
Schutzmaßnahmen administrativ umgehen; der Audit-Trail ist keine kryptografische
Manipulationsgarantie. Client und Server müssen gemeinsam aktualisiert werden.
Offline-Schreiben, Sync und Wiedereröffnung gehören nicht zu diesem Slice.
Native Gerätetests und ein neuer Browser-/Restore-Lauf sind nicht Teil dieses Reviews;
deren vorheriger Nachweis steht in der Implementierungsabnahme. Die Review-Korrekturen
betreffen Controller-Anzeige und API-Dokumentation; SQL und Backendverhalten bleiben gleich.

## Finale Prüfung

`scripts/dev.ps1 check` mit echtem PostgreSQL und isolierten Testschemas: Exit 0.
Nach der abschließenden OpenAPI-Korrektur wurden Formatter, Analyzer und sämtliche
Tests des Contracts-Pakets nochmals separat ausgeführt (Exit 0).

| Paket | Bestanden |
| --- | ---: |
| API Contracts | 28 |
| Dart-Server einschließlich PostgreSQL-/HTTP-Integration | 84 |
| Flutter-Client einschließlich Controller/Widgets | 102 |
| Design-System | 2 |
| Gesamt | **216** |

Keine übersprungenen PostgreSQL-Tests. Alle Formatter-Prüfungen ohne Änderungen,
alle Dart-/Flutter-Analyzer ohne Befund. Docker Compose config --quiet und
git diff --check erfolgreich. OpenAPI: 61 eindeutige Operationsnamen und 115 gültige
interne Referenzen; externe Error-Referenz vorhanden.
Lokale Protokolle: `.local/cancellation-review-final.log`,
`.local/cancellation-review-contract-final.log`. Reproduzierte Fehler:
`.local/cancellation-review-red.log`, `.local/cancellation-review-contract-red.log`.

Review-Änderungen: `shift_controller.dart`, `task_cancellation_test.dart`,
`platform.openapi.json`, `task_cancellation_contracts_test.dart`, dieser Bericht,
Dokumentationsindex und Verweis aus dem Implementierungsprüfnachweis.
Keine neue Migration, Berechtigung oder Domain Events; kein Commit angelegt.
