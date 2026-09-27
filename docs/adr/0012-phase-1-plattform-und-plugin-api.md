# ADR 0012 – Plattformphase vor fachlichem Slice

Status: angenommen. Datum: 2026-09-27.

## Kontext

Der ursprüngliche P1-Fahrplan bündelte Plattform und Workforce-/Aufgaben-Slice. Die aktuelle ausdrückliche Projektfreigabe verlangt ausschließlich Company, Location, User, Authentication, RBAC, Audit, Events und eine minimale Plugin-API; Fachmodule sind ausgenommen.

## Entscheidung

P1 liefert diese Plattform. Der erste fachliche Vertical Slice bleibt unverändert als P1b nachgelagert. ADR 0011 bleibt für dessen spätere Implementierung gültig. P1 führt weder Mitarbeiter, Schichten noch Aufgaben ein.

Die minimale Plugin-API registriert externe Clients mit validiertem Manifest, expliziten eng begrenzten Leserechten und widerrufbaren Zugangstokens. Der Event Bus besteht aus transaktionaler Outbox und lokalem Consumer für freigegebene Plugin-Inboxen. Es gibt keine Fremdcodeausführung, keinen Broker und keine allgemeine Workflow-Engine. Dies konkretisiert ADR 0007/0008, ohne die Sicherheitsvoraussetzungen einer künftigen verwalteten Plugin-Runtime zu umgehen.

## Folgen

Die Plattform lässt sich eigenständig testen, ohne den fachlichen Slice vorzutäuschen. Company-/Location-IDs aus P0 bleiben stabil; neue additive Migrationen ersetzen keine angewendeten Migrationen. Feste Rollen, ein lokaler Schreiber und begrenzte API-Verträge reduzieren vorzeitige Abstraktion. Eine spätere Unternehmenssynchronisation benötigt weiterhin separate Ownership-, Konflikt- und Restore-Abnahmen. Details und Abnahmetests stehen in [Phase 1](../development/phase-1.md).
