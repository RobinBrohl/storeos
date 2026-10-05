# Module boundaries

P4.4 Local Planogram Execution, P4.5 Approved Operational Knowledge and P4.6
Task-to-Knowledge guidance are **DONE/CLOSED** at their documented baselines. P4.7 is **IMPLEMENTED LOCALLY / INDEPENDENT REVIEW APPROVE / SECURITY REMEDIATION COMPLETE / TARGETED SECURITY RE-REVIEW PENDING / REMOTE CHANGED-COMMIT CI PENDING** on `main` above baseline `a0ed6346`.
P4.6 has targeted review APPROVE, 64/64 PASS, focused Codex Security SECURITY APPROVE
and green changed-commit CI; future boundaries are
explicitly labeled below. [Status](../roadmap/status.md) owns delivery and
[vision](../vision.md) owns product scope. A logical boundary does not require
a separate process, Dart package or database schema.

## Current placement and dependency rule

`apps/server` is the composition root. Logical modules live in
`apps/server/lib/src/{organization,people,workforce,tasks,inventory,stock,merchandising,knowledge}/`;
platform/application/infrastructure components provide identity, authorization,
transactions, audit and events. The `modules/` directory is reserved, not where
today's business implementations are deployed.

Flutter UI calls controllers/Application, then API adapters. HTTP routes delegate
to Application/Domain services. Business decisions do not belong in widgets,
routes or plugins. `packages/api_contracts` is transport/validation shared by
client and server; `shared` is not a catch-all for domain models.

Cross-module reads/commands use narrow public ports and released projections.
Repositories/base tables are private to their owner. Company/session/location/
resource authorization is revalidated on the server. Relevant state and audit
share a transaction; events are added only when the use case needs them.

## Implemented ownership

| Owner | Writes / owns | Public boundary and limits |
| --- | --- | --- |
| Organization | Company, Location | Authorized scope/setup queries and configured-location port. Stable IDs; one configured Company per installation. Other named Locations can exist without distributed execution. |
| Identity / platform authorization | Accounts, sessions, fixed role capabilities, Account–Employee links, plugin approvals/tokens | Revalidated access context and minimal references. No employee HR file or scheduling rule; configurable Roles/direct grants are future. |
| People | Minimal Employee with current fixed Location and assignment interval | Authorized profile/eligibility information; no login sessions or task state. Future skills/HR need distinct privacy boundaries. |
| Workforce | Shift drafts, publication/cancellation and last interval-amendment evidence | Shift command/query ports. Planned work is not actual time recording. Employee/template reassignment and begun-work reconciliation are unsupported. |
| Tasks | TaskTemplate revisions/guidance selection, immutable TaskInstance snapshots/pins, execution state, step results, blockings, numeric attempts and command receipts | Task creation/execution/resolution/query ports. Does not update Workforce tables or own future HACCP records. |
| Inventory | Company-wide Article and ArticleLocationAssortment | `InventoryArticlePort` and released `inventory_article_location_projection`. Owns effective Article/Assortment information, not stock quantities or prices. |
| Stock | StockLevel projection and immutable StockMovement ledger | Authorized queries and manual opening/absolute correction. Exact thousandths; frozen unit; movement-ID replay. No valuation, receiving or unit conversion. |
| Merchandising | Local Fixture, independent Company Planogram, Revision/Zone/Placement and immutable Assignment | Organization scope, Inventory Article/Assortment and Stock referenced-level public ports; browser print; `PlanogramGuidancePort` validates exact fresh deployments and resolves retained instructions after authorized Task/Template context. No Stock writes or events. P4.4 DONE/CLOSED; P4.7 review/CI pending. |
| Knowledge | Company-wide WikiArticle and immutable published/discarded WikiRevision | Authorized instruction discovery/read and explicit management/publication. Knowledge-owned exact published-revision validation and exact contextual historical resolution through its public port; no foreign business tables, Task snapshot ownership, readership tracking or events. [ADRs 0019/0020](../adr/README.md); P4.5/P4.6 DONE/CLOSED. |
| Audit infrastructure | Append-only business audit | Shared transactional append and authorized reads. Does not decide business state; runtime grants do not protect against every privileged owner action. |
| Event/plugin infrastructure | Organization outbox, delivery receipts/inbox and registry | Bounded local dispatch/retry/dead-letter/replay and approved external read clients. No executed plugin code or business-module write API. |

Inventory's released projection is an explicit read contract: Stock may join that
view and use its typed port, not the underlying Article/Assortment tables.
Stock identity is Article + Location, not the Assortment UUID. Opening requires
effective availability; existing Stock remains readable/correctable after either
Article or membership deactivation. Stock owns movement/version/replay logic.

Current PluginService and IdentityService still read OrganizationRepository.
These are recorded boundary exceptions (L1), not permission to copy the pattern.
See [technical debt](../development/technical-debt.md).

## Coordinated local operations

`ShiftApplication` composes public Workforce, Tasks and People ports in the same
authorized transaction. It owns orchestration, not another copy of their data.

- Publication writes Shift, immutable selected task snapshots and relevant audit
  atomically ([ADR 0011](../adr/0011-atomare-schichtveroeffentlichung.md)).
- Employee Home combines authorized queries without a separate persistent aggregate.
- Execution checks current own-employee/shift context; Tasks controls order, evidence,
  completion, blocking and resolution. Cancellation of blocked work has its explicit
  administrative eligibility exception; it is not an employee completion.
- Pristine published-shift cancellation first asks Tasks to cancel every eligible
  open instance, then cancels Workforce state in one transaction. Any ineligible task
  or audit failure rolls back everything ([ADR 0013](../adr/0013-published-shift-cancellation.md)).
- Pristine interval amendment changes only Workforce starts/ends and retry evidence;
  it neither regenerates tasks nor changes their snapshots. The database overlap
  invariant is enforced by migration 0012 ([ADR 0014](../adr/0014-pre-execution-shift-interval-amendment.md)).

**No shift/task integration events currently exist.** Names such as
`shift.published.v1` in target examples are future contracts, not emitted facts.
There is no asynchronous task generator. Add an event only for a concrete consumer;
it must not repeat the synchronous publication effects.

## P4.4 local Merchandising boundary

Merchandising now owns local Fixtures, independent Company Planograms, immutable
published revisions with ordered Zones/Placements, and explicit append-only
Assignments. The bounded implementation is recorded in [ADR 0018](../adr/0018-local-planogram-execution.md).
Its repository touches only its six tables. Organization supplies configured-Location
validation; Inventory supplies typed bounded Article/Assortment context and candidates;
Stock supplies typed referenced current levels, missing versus zero and frozen units.
At P4.4 closure no Tasks integration existed. P4.7 adds the narrow port described below; no Stock writes or outbox consumer exists. P4.4 is DONE/CLOSED
with independent review APPROVE and green changed-commit CI; see [closure evidence](../development/phase-4-4-local-planograms.md#final-documentation-closure--2026-10-04).
Database constraints/triggers protect ownership/scope, append-only Assignments and
immutable published content. Current/latest pointer and Fixture version advancement,
Assignment insert and audit are one supported-writer atomic transition. Arbitrary
direct runtime SQL can repoint to the same Fixture's older Assignment without
advancing version; this accepted F03 boundary is retained in ADR 0018.

## P4.6 Task / Knowledge boundary

Tasks owns guidance selection and immutable Task snapshot inclusion. Knowledge
owns approved content, revision lifecycle, exact published-revision validation and
exact contextual historical resolution through `KnowledgeGuidancePort`. Workforce
continues to own Shift publication context. Tasks/Workforce establish authorized
context before passing the stored pin; Knowledge never queries Tasks tables and
Task repositories never query Knowledge tables. There is no generic polymorphic
InstructionReference abstraction, acknowledgment or read event. P4.6 introduced Knowledge alone; P4.7 adds a separate concrete Planogram field.
See [ADR 0020](../adr/0020-task-knowledge-guidance.md).

## P4.7 Task / Planogram Assignment boundary

Current authorization requires the work Location to equal the actor's and the configured execution Location, as well as Company and action scope. `PlanogramGuidancePort.requireWorkLocation` enforces this before layout and live enrichment reads, fresh validation, retained edit/clone and publication replay. Same-Company registered Locations are not interchangeable. Local historical lifecycle exceptions never waive current Location scope.

Tasks owns schema-4 selection and the immutable exact Fixture/Assignment/Revision snapshot. Merchandising owns `PlanogramGuidancePort`, Assignment identity, lifecycle eligibility, immutable layout structure and retained-layout resolution. Workforce authorizes Shift/Task context and coordinates publication through Tasks. Task repositories never read Merchandising tables; the Merchandising port never reads Tasks tables. Knowledge remains independently owned by `KnowledgeGuidancePort`.

Selection and fresh publication require the exact current eligible deployment in the Company transaction. Historical contextual resolution validates durable identity after scoped Task/Template authorization without requiring current/active lifecycle. Migration 0019 binds the complete tuple to append-only Assignment evidence; no transient lifecycle belongs in the FK. Frozen instruction and explicitly current Inventory/Stock enrichment are separate. Reads create no execution, acknowledgment, audit or event. See [ADR 0021](../adr/0021-task-planogram-assignment-guidance.md) and [local evidence](../development/phase-4-7-task-planogram-guidance.md).

## Intentional future ownership

These are **planned boundaries**, not existing modules or final schema decisions.
Public ports should express product dependencies without circular Domain ownership.

| Future owner | Intended data/responsibility | Dependencies through contracts; excluded ownership |
| --- | --- | --- |
| Knowledge extensions | Suggestions and separate review beyond delivered P4.5/P4.6 | Concrete Task guidance is delivered through [ADR 0020](../adr/0020-task-knowledge-guidance.md); further consumers/lifecycle changes need separate contracts. Reads never change execution history. |
| Merchandising extensions | Future HQ rollout, acknowledgment and deviations beyond P4.4 | Separately approved contracts; Tasks would own rollout work. No foreign Stock writes or general CAD. |
| Production / Recipes | Optional Article-linked Recipe revisions, ingredients/yield/instructions, production/batch evidence | Inventory owns Article identity; Stock applies physical effects; cost source and consumption model undecided. No duplicate manufactured product identity. |
| Purchasing / Receiving | Suppliers, orders, receipt/source cost evidence | Article/unit references; authorized Stock commands for accepted physical receipts. Not Stock ledger owner or invented valuation. |
| Sales integration | Canonical SalesSource/import/checkpoint, Sale/Line source references, mapping and import health | Core validates authority/identity and coordinates explicit Stock/report effects. Vendor adapter acquires/converts; checkout/payment/fiscal archive ownership separate. |
| Pricing | Effective prices/currency and approval rules | Article references; Menu consumes approved price contract. No implicit price column in Article. |
| Menu / public publishing | Structured Menu revisions, themes/print artifacts and explicit public publication | Optional Article/Recipe/price references. Publisher owns artifact deployment/status, not public operational DB access. |
| Communications | Boards, announcements and Chat content/membership lifecycle | Identity/scope and operator privacy policy; Notifications owns delivery, not message content. No generic Slack system or employee scoring. |
| Notifications | Durable event-based delivery/retry/failure/preferences/contact use | Domain facts with minimal authorized payloads; not business approval or proof of readership. |
| Workforce extension | ShiftSwapRequest proposals/comments/responses and responsible approval | Final current-state checks and schedule mutation coordinated via Workforce/Tasks ports; no recipient-only schedule change. |
| HACCP | ControlPlan/Execution, measurements, deviations and corrective actions | Tasks presents control work; HACCP retains authoritative safety evidence. Generic task numbers are not certified records. |
| Reporting / Finance | Defined metrics, provenance, scoped exports and later finance records | Authorized projections; no business-table ownership, fabricated margins or assumed valuation. |
| Remote access boundary | Authenticated workplace/remote context and capability allowlist, optional gateway | Identity/grants/resource authorization remains in Core. No mandatory private device/cloud and no automatic remote full-admin exposure. |

## Evolution rules

Own each schema change through a new tested migration; retain IDs, snapshots and
supported contracts. Do not let a future integration write Core tables directly.
Events represent committed facts, not a substitute for synchronous consistency.

A new module needs one bounded use case, owner, permissions, audit/events decision,
error handling and tests before code. See [ADRs](../adr/README.md),
[guided work](guided-work.md), [workforce orchestration](workforce-orchestration.md)
and [data ownership](data-ownership.md). Larger entity names above are conceptual;
choose concrete persistence/API contracts only when a slice is approved.
