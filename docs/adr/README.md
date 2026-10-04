# Architecture Decision Records

ADRs halten langlebige Entscheidungen samt Alternativen und Folgen fest. Die Nummern sind stabil; eine Änderung der Grundentscheidung bekommt eine neue ADR und verlinkt die abgelöste. Details, die vor der Implementierung noch geprüft werden müssen, stehen im Abschnitt „Offene Prüfungen“ und sind keine stillschweigend freigegebenen Features.

| Nr. | Entscheidung |
| --- | --- |
| [0001](0001-modularer-monolith.md) | Modularer Monolith |
| [0002](0002-flutter-client.md) | Flutter als gemeinsamer Client |
| [0003](0003-dart-backend.md) | Dart als Backend |
| [0004](0004-postgresql.md) | PostgreSQL |
| [0005](0005-local-first-self-hosted.md) | Local-first und Self-hosted |
| [0006](0006-standort-und-unternehmensserver.md) | Standortserver und optionaler Unternehmensserver |
| [0007](0007-plugin-architektur.md) | Plugin-Architektur |
| [0008](0008-event-system.md) | Event-System |
| [0009](0009-audit-trail.md) | Audit Trail |
| [0010](0010-offline-und-sync-strategie.md) | Offline- und Synchronisationsstrategie |
| [0011](0011-atomare-schichtveroeffentlichung.md) | Atomare Schichtveröffentlichung im ersten Slice |
| [0012](0012-phase-1-plattform-und-plugin-api.md) | Vorgezogene Plattformverwaltung und minimale Plugin-API |
| [0013](0013-published-shift-cancellation.md) | Published-shift cancellation before execution starts |
| [0014](0014-pre-execution-shift-interval-amendment.md) | Pre-execution published-shift interval amendment |
| [0015](0015-company-wide-article-master.md) | Company-wide article master foundation |
| [0016](0016-article-location-assortment.md) | Article–location assortment membership |
| [0017](0017-manual-stock-foundation.md) | Manual stock foundation (ledger, projection, immutable unit snapshot) |

Write new ADRs in English with Context, Decision, Alternatives, Consequences and Open Questions, plus a status such as Proposed, Accepted or Superseded by ADR …. Preserve existing filenames and historical German records. See the [language policy](../development/workflow.md).

## Decision status versus delivery

An Accepted ADR records a chosen architectural direction, not proof that every
consequence has been implemented, independently reviewed or verified by CI. Use
[actual status](../roadmap/status.md) for those facts and [live debt](../development/technical-debt.md)
for remaining findings. All 17 stable records above are retained; this documentation
pass adds no irreversible decision or new speculative ADR.

Follow-up context: ADR 0015's location-availability boundary is implemented by
ADR 0016; ADR 0016's first Stock consumer is implemented by ADR 0017. Manual Stock
is committed at `e8ce8c3` with active client acceptance corrections. The broader
unit catalog/conversion and costing questions remain open. Do not rewrite the
original alternatives, decisions or dated verification to reflect later delivery.
