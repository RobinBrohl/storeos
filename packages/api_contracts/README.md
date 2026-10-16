# API-Verträge

Reines Dart-Package `storeos_api_contracts` für die HTTP-Verträge von P0, P1 und P1b.1 bis P1b.9 sowie Article, Assortment und Stock. Keine Flutter-, Datenbank- oder Domain-Abhängigkeit. [Basis-OpenAPI](openapi.yaml) und [Plattform-OpenAPI](platform.openapi.json) beschreiben die API maschinenlesbar. Mitarbeiterprofile, Account-Verknüpfungen, Vorlagen, Schichten, stornierte/geänderte Schichtintervalle, Aufgabenausführung, Article, Assortment und Stock werden als öffentliche DTOs transportiert; interne Domainmodelle bleiben im jeweiligen Servermodul.

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

Selbstbedienung (P1) ergänzt unter `/api/v1/platform`:

- `POST /profile/password`: `{currentPassword,newPassword}` für den eigenen Account
  jeder angemeldeten Rolle (`identity.self.password`); es wird kein Account-, Benutzer-
  oder Mitarbeiterbezeichner akzeptiert. `currentPassword` umfasst 1–1024, `newPassword`
  12–1024 UTF-8-Bytes und muss sich vom aktuellen Passwort unterscheiden. Da die Regel
  bytebasiert ist, werden `minLength`/`maxLength` im OpenAPI bewusst nicht verwendet;
  `x-storeos-min-utf8-bytes`/`x-storeos-max-utf8-bytes` dokumentieren die exakten Grenzen.
  Erfolg ist `204`; Hash-Aktualisierung, Audit `identity.user.password_changed` und der
  Widerruf aller Sitzungen einschließlich der aufrufenden sind atomar. Falsches aktuelles
  Passwort: `422 invalid_current_password`; mehr als fünf Fehlversuche pro Account in
  15 Minuten: `429 rate_limited`. [Slice-Vertrag](../../docs/development/phase-1-self-service-password-change.md).

## Current documentation boundaries

P4.11 adds strict `ShiftTransferCommandInput` and bounded immutable evidence DTOs,
eleven concrete operations in `platform.openapi.json` referenced by canonical
`openapi.yaml`, and operation-specific errors. Regenerate only these additions with
`dart run tool/shift_transfer_openapi.dart` from this package. Contract tests validate
exact lifecycle/pin/lineage evidence, privacy and OpenAPI references. The
[P4.11 record](../../docs/development/phase-4-11-one-way-shift-transfers.md) describes
participant authorization and Company+operation replay; broader M3/M4 debt remains.

OpenAPI route/error drift prevention remains M3; broad error-taxonomy cleanup remains
M4. Shared Dart contracts and bounded endpoint tests do not constitute a global
router/OpenAPI consistency gate. Every API-adding slice must document and test
its request/response/errors and negative cases. Before external API/SDK consumers,
review the broader surface. Stock's required-nullable note is described as optional
in OpenAPI (F10); that contract file is intentionally unchanged in this documentation
pass and the correction remains open. See [technical debt](../../docs/development/technical-debt.md).

Package README text is guidance; dated phase contracts and actual DTO/HTTP tests
establish implementation. Use [status](../../docs/roadmap/status.md) for delivery
and [module boundaries](../../docs/architecture/module-boundaries.md) for ownership.

P4.15 adds strict decimal-string Article quantity and Stock conversion contracts
in `article_quantities.dart`, with immutable bounded packaging, explicit binding,
complete reviewed targets and original receipt evidence. `Article.unit` and old
Stock contracts remain unchanged. New routes are in `platform.openapi.json` and
referenced by `openapi.yaml`; `tool/article_quantity_openapi.dart` supplies the
bounded additions and `article_quantity_openapi_test.dart` verifies the artifact.
See the [P4.15 contract](../../docs/development/phase-4-15-article-quantities.md).

## P4.16 bilateral Shift Swap contracts

The independently approved B2a backend implements sixteen authenticated swap
operations. Stage B2b adds their OpenAPI parity locally under implementation-plan
Step 7; independent B2b review remains pending. P4.16 remains **IN PROGRESS**.
The roots are `/api/v1/platform/me/shift-swaps` and
`/api/v1/platform/locations/{locationId}/shift-swaps`, plus own-Shift
`swap-colleagues` discovery. Captured recipient B alone discovers own counterparts;
these operations grant no general colleague roster. Server-side session,
Company/Location, capability and participant authorization precedes receipt replay.

`shift_swaps.dart` supplies strict command and immutable evidence DTOs.
`platform.openapi.json` contains 22 separate `ShiftSwap*` schemas and the sixteen
operations, referenced by canonical `openapi.yaml`. Regenerate with
`dart run tool/shift_swap_openapi.dart`. The bounded generator preserves all
historical members, is deterministic/idempotent and refuses conflicting or partial
definitions. Tests independently read actual route registrations, validate DTO
shapes and per-operation errors, resolve references and check raw preservation of
P4.11 and unrelated APIs. Historical P4.11 definitions are unchanged.

Commands have an 8192 UTF-8 byte wire limit, independent of reason normalization:
trim first, then 1–500 Unicode scalar values, excluding controls and unpaired
surrogates. `x-storeos-*` annotations describe normalization, strict JSON integer
tokens, UTF-16 cursor length and cross-field identity/temporal constraints that
standard JSON Schema cannot fully express. Responses retain original accepted
status/version/kind and explicit replay metadata; current actionability is a
separate detail read. Lists contain at most fifty items; history pages contain two
receipts. Native expiry may terminate a connection without an HTTP error response;
there is no pre-EOF 413 promise. The approved shared body-completion gates and
transport qualifications remain intact.

See the [B2b handoff](../../docs/development/phase-4-16-stage-b2b.md) for all paths,
schemas, error sets, preservation hashes and verification. Flutter swap controllers,
UI/Chrome acceptance, expanded recovery and full A01–A16 acceptance remain later
gates; a release Web compatibility build does not deliver those features.
