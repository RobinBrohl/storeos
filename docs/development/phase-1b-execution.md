# P1b.4 – Bestätigungsaufgaben ausführen

Freigegebener Scope: eigene Schema-1-Aufgaben starten, Schritte der Reihe nach
bestätigen, separat abschließen. `open → in_progress → completed`. Start nur
innerhalb `startsAt ≤ Serverzeit < endsAt`; Fortsetzung nach Schichtende bei
weiterhin gültiger Zuordnung erlaubt. Laufende eigene Aufgaben bleiben paginiert
in Employee Home erreichbar. Keine Messwerte, blocked-/Korrekturabläufe,
Stellvertretung, Offline-Schreibqueue, Events oder Plugin-Erweiterungen.

Tasks besitzt Ausführungskopf an TaskInstance, unveränderliche Schrittresultate
und Befehlsnachweise. Application koordiniert Identity, People und Workforce über
Ports in derselben autorisierten Transaktion. Snapshot und Zuordnung bleiben
unveränderlich. Jeder Befehl enthält operationId und expectedVersion; Bestätigung
zusätzlich die Snapshot-Schritt-ID im Pfad. Nur explizite positive Bestätigungen
werden gespeichert. Neue Befehle erhöhen die Instanzversion genau einmal.

`tasks.instances.self.execute` gilt für Employee und Admin nur für eigene Aufgaben
mit aktiver Verknüpfung und aktuell gültiger Mitarbeiter-Standortzuordnung. Rechte
werden vor jedem Zugriff einschließlich Wiederholung geprüft. Admin liest fremden
Fortschritt mit bisherigen Leserechten und kann ihn nicht stellvertretend ändern.

Befehlsnachweise binden operationId an Company, Account, Instanz, Befehlsart,
Schritt und Basisversion. Identische Wiederholung liefert das gespeicherte
Annahmeergebnis; abweichende Verwendung ergibt 409. Nachweise werden in diesem
Slice nicht automatisch gelöscht und enthalten keine vollständigen Anleitungen.
Ein zusätzlicher GET liefert den aktuellen Ausführungsstand. Es gibt keinen
geräteübergreifenden Offlinevertrag und keine generische Idempotenzplattform.

Audit: tasks.instance.started, tasks.step.confirmed, tasks.instance.completed.
Objekt, Schritt, Operations-ID, vorherige/neue Version und Zustand werden ohne
Anleitungstext gemeinsam mit Mutation und Befehlsnachweis gespeichert. Ein Fehler
rollt alles zurück. Ohne Folgeverbraucher entstehen keine Outbox-Ereignisse.

Migration 0007 erhält vorhandene Instanzen als open/Version 1 und ersetzt nur den
pauschalen Instanz-Updateschutz durch Ausführungsschutz. Alle alten Migrationen
bleiben unverändert. Server und Webclient gemeinsam aktualisieren; alte Clients
kennen ausführbare Instanzzustände nicht zuverlässig.

Abnahme: echter Zwei-Benutzer-Ablauf, Pflichtfolge, Zeitgrenzen, Fortsetzung nach
Schichtende, parallele/retry Befehle, Snapshotstabilität, Rechteentzug, atomarer
Rollback, Neustart, befülltes Upgrade und Backup/Restore. Formatter, Analyzer,
Unit-/PostgreSQL-/Fluttertests und Browser-Smoke müssen bestehen. P1b bleibt wegen
fehlender Abweichungsbehandlung teilweise implementiert. Bestätigungen sind keine
HACCP-, Arbeitszeit- oder Leistungsnachweise.

## API

Alle Pfade beginnen mit `/api/v1/platform`:

| Methode / Pfad | Vertrag |
| --- | --- |
| GET /employee-home/running-tasks?after={taskId} | Eigene laufende Aufgaben, 50 Metadatensätze je Seite, nach ID sortiert; nextCursor für die Fortsetzung |
| GET /employee-home/shifts/{id}/tasks/{taskId}/execution | Eigener gespeicherter Ausführungsstand |
| GET /shifts/{id}/tasks/{taskId}/execution | Administrative lesende Fortschrittsansicht |
| POST /employee-home/shifts/{id}/tasks/{taskId}/start | Start während des Schichtintervalls |
| POST /employee-home/shifts/{id}/tasks/{taskId}/steps/{stepId}/confirm | Genau den nächsten Snapshot-Schritt bestätigen |
| POST /employee-home/shifts/{id}/tasks/{taskId}/complete | Separater Abschluss nach allen Bestätigungen |

POST-Bodies enthalten ausschließlich `operationId` (UUID) und `expectedVersion`
(positive Ganzzahl). Akteur, Standort und Mitarbeiter werden nicht vom Body
übernommen. 400: ungültiger Vertrag; 401: Sitzung ungültig; 403: fehlendes Recht;
404: kein sichtbares eigenes Objekt/Profil; 409: Version, Zustand oder
Operationsidentität widersprechen; 422: Schrittfolge/Abschlussbedingung oder
Startfenster ungültig; 503: Datenbank nicht verfügbar. Bei 5xx/Netzwerkfehler ist
der Erfolg zunächst unbestätigt, ein Fehler beweist keinen Rollback beim Server.

Jeder akzeptierte Befehl erhöht die Instanzversion; eine identische Wiederholung
liefert ihr ursprüngliches Ergebnis, auch wenn die Instanz inzwischen weiter ist.
Der Client lädt anschließend den aktuellen Stand. Bei fehlgeschlagener Nachladung
bleiben weitere Aktionen bis zum expliziten Neuladen gesperrt. Bei Benutzerwechsel
werden ausstehende Befehle und geladene Daten verworfen. Es gibt keinen
persistenten lokalen Schreibpuffer; nach Clientneustart wird der Serverstand geladen.
Die bestehende Company-Sperre bleibt die gemeinsame Konkurrenzgrenze.

Die administrative und eigene Aufgabenmetadaten-API liefern tatsächlichen Status,
Version und bestätigte/gesamte Schrittanzahl. Inhalte bleiben auf Detailabfragen
begrenzt. Der ursprüngliche Schema-1-Anleitungssnapshot wird nicht erweitert.

[Prüfnachweis und vollständige Dateiliste](phase-1b-execution-verification.md).
