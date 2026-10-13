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
| [0018](0018-local-planogram-execution.md) | Local planogram execution: independent layouts and explicit immutable deployment |
| [0019](0019-approved-operational-knowledge.md) | Approved operational Knowledge: stable Article, immutable revisions and strict publication replay |
| [0020](0020-task-knowledge-guidance.md) | Exact approved Knowledge revision pins and contextual historical Task guidance |
| [0021](0021-task-planogram-assignment-guidance.md) | Exact Fixture/Assignment/Revision pins, current fresh-work validation and contextual retained layout |
| [0022](0022-selected-article-stock-counts.md) | Selected Stock counts, immutable blind observations, whole approval and typed movement provenance |
| [0023](0023-approved-article-recipe-composition.md) | Approved Article composition, declared batch, frozen references and exact publication replay |
| [0024](0024-preparation-batch-evidence.md) | Location-scoped preparation declarations, retained Recipe revision, immutable terminal evidence and append-only count corrections; P4.10 DONE/CLOSED, F01–F03 CLOSED, targeted APPROVE, SECURITY APPROVE and green exact-commit CI 37632074236 |
| [0025](0025-one-way-shift-transfer-before-execution.md) | One-way future Shift transfer with exact recipient consent, independent approval and immutable lineage; P4.11 DONE/CLOSED |
| [0026](0026-bounded-purchase-order-intent.md) | Minimal Company Supplier identity, local PurchaseOrder intent, frozen selections and eight durable commands; P4.12 DONE/CLOSED, F01 CLOSED, targeted APPROVE, SECURITY APPROVE, implementation CI 38152045998 and closure CI 38156014870 successful |
| [0027](0027-planned-preparation-assignment.md) | Production-owned immutable preparation requests with retained approved revision authority and atomic Batch linkage; P4.13 DONE/CLOSED — accepted implementation, F01 CLOSED, targeted APPROVE, SECURITY APPROVE and exact implementation CI 38224661628 successful; docs publication/closure-commit CI pending |
| [0029](0029-explicit-article-quantity-semantics.md) | Accepted P4.15 immutable Article quantity anchors, versioned direct packaging, prospective Stock bindings and exact reviewed manual targets; DONE/CLOSED — accepted implementation, targeted APPROVE, F01–F03 CLOSED, SECURITY APPROVE and successful main CI 38323585842; separate documentation-closure publication and its own exact-commit CI PENDING; P4.16 UNSELECTED |

Write new ADRs in English with Context, Decision, Alternatives, Consequences and Open Questions, plus a status such as Proposed, Accepted or Superseded by ADR …. Preserve existing filenames and historical German records. See the [language policy](../development/workflow.md).

## Decision status versus delivery

An Accepted ADR records a chosen architectural direction, not proof that every
consequence has been implemented, independently reviewed or verified by CI. Use
[actual status](../roadmap/status.md) for those facts and [live debt](../development/technical-debt.md)
for remaining findings. Records 0001–0017 are retained. ADR 0018 records the user-selected P4.4 contract; delivery is DONE/CLOSED with targeted review APPROVE and green changed-commit CI per the [final closure](../development/phase-4-4-local-planograms.md#final-documentation-closure--2026-10-04). Its supported-writer decision remains intact.

Follow-up context: ADR 0015's location-availability boundary is implemented by
ADR 0016; ADR 0016's first Stock consumer is implemented by ADR 0017. Manual Stock
foundation is committed at `e8ce8c3`, with acceptance correction `f9c8b07`;
P4.3 is DONE/CLOSED per the [closure evidence](../development/phase-4-3-manual-stock.md#final-acceptance-closure--2026-10-04).
The broader unit catalog/conversion and costing questions remain open. Do not rewrite the
original alternatives, decisions or dated verification to reflect later delivery.

ADR 0029's exact alternate-unit manual targets are now P4.15 **DONE/CLOSED — accepted
implementation**, with targeted functional APPROVE, F01–F03 CLOSED, SECURITY APPROVE
and successful [main CI 38323585842](https://github.com/RobinBrohl/storeos/actions/runs/38323585842).
Separate documentation-closure publication and its own exact-commit CI remain
PENDING. P4.16 is UNSELECTED. See the [complete chronology and six qualifications](../development/phase-4-15-article-quantities.md#final-documentation-closure--2026-10-13).

## Historical delivery snapshots

The following pending/unselected statements retain their earlier drafting context;
current P4.15 status is recorded above and does not rewrite those historical results.

[ADR 0025: One-way Shift transfer before execution](0025-one-way-shift-transfer-before-execution.md) records the delivered P4.11 contract: **DONE/CLOSED**, F01/F02/F03 CLOSED, targeted APPROVE, 177 PASS / 0 QUALIFIED / 0 FAIL, SECURITY APPROVE and green exact-commit CI 38125193187. [ADR 0026](0026-bounded-purchase-order-intent.md) records accepted P4.12, DONE/CLOSED with all three implementation review/CI gates complete; documentation closure CI 38156014870 successful. P4.13 is DONE/CLOSED — accepted implementation; F01 CLOSED, targeted APPROVE, SECURITY APPROVE and exact implementation CI 38224661628 successful. P4.13 docs publication/closure-commit CI pending. P4.14 UNSELECTED.

[ADR 0027: Planned preparation with retained approved execution authority](0027-planned-preparation-assignment.md)
records accepted P4.13, DONE/CLOSED: F01 CLOSED, targeted APPROVE, SECURITY APPROVE
and successful exact implementation CI 38224661628. Final documentation publication
and its own closure-commit CI remain PENDING. P4.14 is UNSELECTED.

[ADR 0028: Purchase Order delivery evidence and immutable terminal reconciliation](0028-purchase-order-delivery-evidence.md)
records selected P4.14. Delivery is IMPLEMENTED LOCALLY; independent review, focused
Codex Security and implementation-commit CI remain PENDING. P4.15 is UNSELECTED.
