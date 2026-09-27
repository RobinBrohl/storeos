# Review des P1b.4-Entwicklungszyklus

Basis: `8be17f9`; geprüft wurden ausschließlich die danach implementierten
Änderungen für Guided Work und Completion samt Migration 0007, Verträgen und Tests.
Keine zusätzlichen Fachfunktionen, Berechtigungen, Events oder Migrationen.

## Gefundene und behobene Probleme

1. **Veraltete Fortschrittslisten nach Antwortverlust.** Der explizite Abruf des
   Aufgabenstands ersetzte nur die Ausführung im Detail. Nach serverseitig
   erfolgreichem Abschluss mit verlorener Antwort blieb die Aufgabe in der
   Schichtliste als laufend und unter „Laufende Aufgaben“ sichtbar. Der Controller
   aktualisiert nun auch Schichtmetadaten und laufende Aufgaben; derselbe Ablauf
   wird nach bestätigten Befehlen verwendet. Er sendet dabei keinen Befehl erneut.
2. **Vorzeitige Freigabe nach fehlgeschlagener Nachladung.** Nach erfolgreichem
   Ausführungs-GET wurden Folgeaktionen bereits freigegeben, obwohl eine danach
   fehlgeschlagene Listenabfrage die dokumentierte Nachladung unvollständig ließ.
   Die Sperre endet jetzt erst nach erfolgreicher Nachladung aller betroffenen
   Ansichten. Eine bestätigte Mutation bleibt bestätigt und wird nicht erneut
   gesendet. Explizites Neuladen stellt die Bedienbarkeit wieder her.

Beide Fälle wurden zuerst mit fehlschlagenden Controller-Regressionstests
reproduziert und anschließend mit der Korrektur erfolgreich geprüft. Die
Änderung bleibt im bestehenden ShiftController; Widgets und HTTP-Routen erhalten
keine Fachlogik. Zusätzliche Abfragen sind begrenzt und erfolgen nur beim
expliziten Abgleich beziehungsweise nach einem bestätigten Befehl.

## Weitere Review-Ergebnisse

- Tasks besitzt Ausführung und Schrittresultate. Der Application-Koordinator
  verwendet die bestehenden Ports; kein neuer Zugriff auf fremde Modultabellen.
- Die autorisierte Transaktion prüft aktuelle Accountrechte, eigene Zuordnung und
  Standort auch vor einer Wiederholung. Plugins erhalten keine Ausführungsrechte.
- Version, Schrittfolge, Startfenster und terminaler Zustand werden serverseitig
  geprüft. Fachänderung, Audit und Operationsnachweis werden gemeinsam committed.
  Die bestehende Company-Sperre serialisiert konkurrierende Befehle.
- Schrittresultate und gespeicherte Wiederholungsergebnisse sind für das
  Runtime-Konto nicht änder- oder löschbar. Die Migration erhält die Snapshots.
- Alle drei relevanten Mutationen erzeugen Audit; Wiederholungen erzeugen keinen
  zweiten Änderungsnachweis. Ohne Verbraucher ist kein neues Event erforderlich.
- Keine Mengen-/Rundungsregeln in diesem Slice. Listen sind paginiert, Inhalte
  auf Detailabfragen begrenzt. Kein zusätzlicher HTTP-/DB-Aufruf pro Listenobjekt;
  Resultatzählung erfolgt in der begrenzten Metadatenabfrage.

## Finale Prüfung

`scripts/dev.ps1 check` mit echter PostgreSQL-Testdatenbank erfolgreich:

| Paket | Tests bestanden |
| --- | ---: |
| API Contracts | 22 |
| Server einschließlich PostgreSQL-/HTTP-Integration | 69 |
| Flutter-Client | 90 |
| Design-System | 2 |
| Gesamt | **183** |

Alle Formatter und Analyzer ohne Befund; keine übersprungenen Datenbanktests.
Docker Compose config erfolgreich. Die Integrationstests prüfen unter anderem
Konkurrenz, Rechteentzug, atomaren Rollback, Neustart und befülltes Upgrade.
100 interne OpenAPI-Referenzen aufgelöst; 52 eindeutige Operationsnamen.
Protokoll: `.local/execution-review-check.log`.
Flutter-Web-Release erneut erfolgreich gebaut
(`.local/execution-review-build.log`); `git diff --check` ohne Fehler.

Der Browser-/Backup-/Restore-Nachweis des Entwicklungszyklus steht im
[ursprünglichen Prüfnachweis](phase-1b-execution-verification.md). Browser und
Restore wurden im Review nicht wiederholt; Backend und Datenmodell blieben
unverändert. Die Controller-Korrekturen sind durch Regressionstests und den
erneut ausgeführten Widget-Ablauf Start → Bestätigung → Abschluss abgedeckt.

## Verbleibende bekannte Grenzen

Die Company-Sperre begrenzt späteren Durchsatz; es wurde keine Lastabnahme
durchgeführt. Zwischen getrennten GET-Anfragen kann sich der Serverstand ändern;
die Basisversion verhindert weiterhin stilles Überschreiben. Operationsnachweise
wachsen ohne automatische Bereinigung. Aufbewahrung und DB-Owner-Zugriff benötigen
das bereits dokumentierte Betriebskonzept. Kein Geräte-Offlinepuffer, keine
blocked-/Korrekturabläufe, keine native Geräteabnahme. Diese Grenzen wurden nicht
durch neue Features oder einen horizontalen Umbau ausgeweitet.
