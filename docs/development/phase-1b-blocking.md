# P1b.5 – Aufgaben blockieren und Wiederaufnahme freigeben

Freigegebener Scope: eigene laufende Bestätigungsaufgaben mit 1–500 Unicode-Zeichen
Begründung blockieren; Administratoren geben nach dokumentierter Klärung die
Wiederaufnahme frei. Keine automatische Bestätigung, Stornierung, Neuzuordnung,
Messwerte, Offlinequeue oder neuen Events. P1b bleibt teilweise implementiert.

Tasks besitzt Blockierungen und Historie in der Instanz-Transaktion. Jede Mutation
verwendet operationId und expectedVersion; Rechte werden auch vor Replay geprüft.
Status, Blockierung, Audit und Annahmeergebnis werden atomar gespeichert. Snapshot,
Zuordnung und bestehende Schrittresultate bleiben erhalten. Nur eine offene
Blockierung pro Instanz; abgeschlossene Meldungen bleiben unveränderlich.

Employee/Admin dürfen eigene Arbeit mit tasks.instances.self.execute blockieren.
Nur Admin erhält tasks.instances.resolve; Freigabe verlangt denselben eingerichteten
Standort und eine aktuell gültige Mitarbeiterzuordnung. Administrative Leserechte
bleiben tasks.instances.read. Keine neuen Rechte für Viewer, Auditor oder Plugins.
Audit: tasks.instance.blocked und tasks.instance.resumed mit Blockierungsreferenz,
Operation, Akteur, Scope und vorheriger/neuer Version/Status, ohne Begründungstext.

Migration 0008 erweitert Status und SQL-Schutz, ergänzt task_blockings sowie
accepted_version an Schrittresultaten (Bestand: position+3). Aggregate-Versionen
zählen alle Mutationen, nicht nur Bestätigungen. Alte Migrationsdateien bleiben
unverändert; alte Annahmeergebnisse bleiben lesbar. Client und Server gemeinsam
aktualisieren, weil alte Clients blocked nicht verstehen.

API unter /api/v1/platform:
- POST /employee-home/shifts/{shift}/tasks/{task}/block
- POST /shifts/{shift}/tasks/{task}/resume
- GET /employee-home/blocked-tasks und /blocked-tasks
- GET /employee-home/shifts/{shift}/tasks/{task}/blockings und
  /shifts/{shift}/tasks/{task}/blockings
Befehle enthalten ausschließlich operationId, expectedVersion, reason. CRLF wird
normalisiert, Rand-Leerraum entfernt; nur Zeilenumbrüche/Tab als Steuerzeichen.
Listen enthalten 50 Einträge und nextCursor, Fortsetzung über after. Blockierte
Aufgaben bleiben unabhängig vom Schichtende sichtbar. running-tasks bleibt unverändert.
Historie ist nach Meldeversion absteigend paginiert; Listen nach Instanz-ID.

Abnahme: Mitarbeiter blockiert → Admin klärt → Mitarbeiter setzt am unveränderten
Pflichtschritt fort → separater Abschluss → Audit. Zu prüfen: Unicode/Grenzen,
mehrfache Blockierungen, Rollen/Scope/Widerruf, konkurrierende Befehle, Replay,
Rollback an jeder Persistenzgrenze, mehr als 50 Listeneinträge, befülltes Upgrade,
Neustart, Backup/Restore, Flutter-Fehlerzustände und Zwei-Benutzer-Smoke.
Company-Sperre, unbegrenzte Nachweisaufbewahrung und fehlende Stornierung bleiben
bekannte Grenzen. Freigabe ist eine menschliche Entscheidung, kein physischer Nachweis.

[Prüfnachweis und geänderte Dateien](phase-1b-blocking-verification.md).
