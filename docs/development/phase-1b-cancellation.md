# P1b.6 – Blockierte Aufgaben begründet stornieren

Freigegeben ist ausschließlich blocked → cancelled durch Admin mit
`tasks.instances.cancel`, erwarteter Version, stabiler operationId und Pflichtgrund
(1–500 Unicode-Zeichen nach bestehender Normalisierung). Cancelled ist terminal,
kein erfolgreicher Abschluss und keine Behauptung einer Hindernisbeseitigung.
Snapshot, Zuordnung, frühere Meldungen und Schrittresultate bleiben unverändert.

Tasks besitzt die Änderung; ShiftApplication prüft aktuelle Sitzung, Rolle, Company
und eingerichteten Standort. Anders als eine Freigabe setzt Stornierung weder eine
aktive Mitarbeiterzuordnung noch einen Account-Link voraus und funktioniert nach
Schichtende. Eigene Leserechte bleiben an die bestehende gültige Zuordnung gebunden.
Plugins, Viewer und Auditor erhalten keine neuen Fachrechte.

Mutation, Abschluss der Blockierung mit resolution_kind=cancelled, Audit
`tasks.instance.cancelled` und Receipt sind atomar. Freitext bleibt in der
Fachhistorie und im bestehenden privaten Receipt, nicht im Audit oder Log.
Keine neuen Domain Events ohne Verbraucher. Gleicher Replay liefert das gespeicherte
Ergebnis nach erneuter Rechteprüfung; geänderter Input oder Konkurrenz ist ein Konflikt.

Migration 0009 ergänzt cancelled, resolution_kind (resumed/cancelled) und einen
Listenindex. Bisherige abgeschlossene Meldungen erhalten resumed, offene bleiben null.
Abschlussgrund/-zeit/-akteur/-version verwenden die vorhandenen resolution/resolved_*
Felder. Ausführungsantworten leiten cancelledAt/By/BlockingId daraus ab. Historie,
Zustandsübergänge und terminale Unveränderlichkeit bleiben SQL-geschützt. Vorhandene
Migrationen und Receipts werden nicht geändert. Client und Server gemeinsam aktualisieren.

API unter /api/v1/platform:
- POST /shifts/{shiftId}/tasks/{taskId}/cancel mit operationId, expectedVersion, reason.
- GET /cancelled-tasks und /employee-home/cancelled-tasks: 50 Einträge, after-ID-Cursor.
- Bestehende Detail-/Ausführungs-/Historienabfragen zeigen den terminalen Zustand.

Flutter ergänzt einen ausdrücklich bestätigten Stornobefehl und gezielt aufrufbare
Stornierungslisten einschließlich beendeter Schichten. Keine Ausführungsaktionen nach
Stornierung; Ladefehler, Konflikte und Antwortverlust bleiben explizit.

Abnahme: Mitarbeiter blockiert → Admin storniert → Mitarbeiter liest Grund und Historie,
auch nach Neustart. Rechte-/Scope-/Plugin-Tests, Replay, cancel-vs-resume, Rollback an
allen Schreibgrenzen, deaktivierte Profile/fehlender Link, letzte bereits bestätigte
Schritte, >50 Einträge, befülltes Upgrade und Backup/Restore sind erforderlich.

Nicht enthalten: andere Storno-Ausgangszustände, Schichtänderungen, Neuzuordnung,
Ersatzaufgaben, Wiedereröffnung, Zahlenschritte, HACCP, Offlinequeue, Sync, allgemeines
Archiv/Reporting, neue Plugins oder ein Umbau der Company-Sperre.
