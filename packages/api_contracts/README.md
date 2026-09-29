# API-Verträge

Reines Dart-Package `storeos_api_contracts` für die HTTP-Verträge von P0, P1 und P1b.1 bis P1b.7. Keine Flutter-, Datenbank- oder Domain-Abhängigkeit. [Basis-OpenAPI](openapi.yaml) und [Plattform-OpenAPI](platform.openapi.json) beschreiben die API maschinenlesbar. Mitarbeiterprofile, Account-Verknüpfungen, Vorlagen, Schichten und Aufgabenausführung werden als öffentliche DTOs transportiert; interne Domainmodelle bleiben im jeweiligen Servermodul.

`/api/v1/` ist die erste Vertragsversion. Zusätzliche optionale Antwortfelder sind kompatibel; vorhandene Pflichtfelder, Typen und Semantik bleiben stabil. Breaking Changes erhalten eine neue API-Version. IDs sind opake Referenzen und verleihen keine Berechtigung. Login- und Session-Payloads dürfen nicht geloggt werden.

`dart pub get`, `dart analyze` und `dart test` in diesem Verzeichnis prüfen das Package unabhängig von Flutter. Die Anwendungen binden es lokal über eine Pfadabhängigkeit ein; Lockfiles werden eingecheckt.

Arbeitsvorlagen unterstützen Schema 1 mit Bestätigungsschritten und Schema 2 mit gemischten Bestätigungs-/Zahlenschritten. DTOs trennen paginierte Metadaten und Revisionsinhalt; validierte Inhalte sind auf 8 KiB begrenzt. [P1b.2-Vertrag](../../docs/development/phase-1b-templates.md).

P1b.6 ergänzt unter `/api/v1/platform`:

- `POST /shifts/{id}/tasks/{taskId}/cancel`: ausschließlich `blocked → cancelled`, mit `operationId`, `expectedVersion` und Pflichtgrund `reason` (1–500 Unicode-Zeichen nach Normalisierung). Benötigt `tasks.instances.cancel` (Admin) im aktuellen Mandanten-/Standortkontext. Stornierung bleibt nach Schichtende und bei deaktiviertem Mitarbeiter oder widerrufener Account-Verknüpfung möglich.
- `GET /cancelled-tasks` und `GET /employee-home/cancelled-tasks`: höchstens 50 Metadatensätze mit `after`-ID-Cursor. Administrative Abfragen benötigen `tasks.instances.read`; eigene Abfragen `tasks.instances.self.read` sowie die weiterhin gültige eigene Mitarbeiterverknüpfung und Standortzuordnung.
- Bestehende Detailantworten enthalten Status, Version, `confirmedSteps` und `totalSteps`. Die Ausführungsantwort ergänzt für `cancelled` die Felder `cancelledAt`, `cancelledBy` und `cancelledBlockingId`. Die Historie unterscheidet `resolutionKind: resumed` und `cancelled`; offene Blockierungen haben keine Abschlussart.

Stornierung ist terminal und keine Completion. Fachänderung, Blockierungsabschluss,
Auditaktion `tasks.instance.cancelled` und Receipt sind atomar. Gleiche Wiederholungen
liefern nach erneuter Rechteprüfung das gespeicherte Ergebnis; abweichender Input oder
Versionskonflikt führt zu 409. Es entstehen keine neuen Domain Events oder Plugin-Rechte.
Server und Client gemeinsam aktualisieren; ältere Clients kennen `cancelled` nicht.
[Vollständiger P1b.6-Vertrag](../../docs/development/phase-1b-cancellation.md).

P1b.7 ergänzt den eigenen POST-Befehl
`/employee-home/shifts/{id}/tasks/{taskId}/steps/{stepId}/record-number`
mit `operationId`, `expectedVersion`, `value` (Dezimalstring). Ein darstellbarer Wert
außerhalb der Grenzen wird mit HTTP 200 und Zustand `blocked` angenommen; ungültiges
Format mit 400, falscher Schritt/Typ mit 422, Versions-/Zustandskonflikt mit 409.
Wiederholungen vergleichen den normalisierten Wert und prüfen erneut die Berechtigung.

GET `.../tasks/{taskId}/number-attempts` ist unter `employee-home/shifts` und `shifts`
verfügbar. Seiten enthalten maximal 50 Einträge, absteigend nach `acceptedVersion`;
`after` ist der exklusive Versionscursor. Einheit und Regel sind im Snapshot enthalten.
`numericAttemptId` verbindet Bestätigungen/Blockierungen mit ihrem Nachweis.
Schema 2 ist nicht für ältere Clients lesbar; Schema 1 bleibt unverändert unterstützt.
[Präzisions-, Rechte- und Auditvertrag](../../docs/development/phase-1b-7-numeric-steps.md).
