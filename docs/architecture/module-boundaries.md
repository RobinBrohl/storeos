# Module boundaries

Current design selection, 2026-10-13: **P4.16 bilateral pristine-future Shift swaps
are SELECTED / DESIGN IN PROGRESS; implementation NOT AUTHORIZED**. The selected
ownership extension is described below and in
[ADR 0030](../adr/0030-bilateral-shift-consent-and-shared-handoff-claims.md).
Earlier P4.15 pending/unselected wording retains its closure context; it does not
describe the current P4.16 selection. Implemented ownership below remains actual
code, not an assertion that the new ports/tables already exist.

P4.15 implementation adds Inventory-owned immutable Article quantity anchors,
packaging revisions and quantity command receipts. Stock owns prospective
immutable bindings and alternate-unit manual correction evidence/receipts.
`ArticleQuantityPort` releases only current profile facts and exact unit
resolution inside the caller's authorized transaction; Stock repositories never
read Inventory quantity tables. Inventory's `inventory_quantity_factor` SQL
port supplies retained factors solely to database integrity guards. Legacy Stock
units, quantities, snapshots, counts and contracts remain intact. See
[ADR 0029](../adr/0029-explicit-article-quantity-semantics.md) and the
[P4.15 slice](../development/phase-4-15-article-quantities.md). P4.15 is
**DONE/CLOSED — accepted implementation** at `f4ffffaae235307424133c4ed280328df3e33f01`,
with test-only correction `c132a88feb619268c65fae69d3eeff64d5363218`. Targeted functional
APPROVE, F01–F03 CLOSED, SECURITY APPROVE and [successful main CI](https://github.com/RobinBrohl/storeos/actions/runs/38323585842)
(attempt 1, all five jobs) establish the gates. Separate documentation-closure
commit publication and its own exact-commit CI remain PENDING. P4.16 was UNSELECTED
at that closure; current owner-authorized design selection is recorded above.
All six qualifications in the [closure](../development/phase-4-15-article-quantities.md#final-documentation-closure--2026-10-13)
remain. No automatic Goods Receipt/Stock posting, Recipe/Purchasing conversion,
production consumption, POS ingestion or costing is introduced. Historical
non-conversion statements below describe the earlier accepted baselines.

P4.4 Local Planogram Execution, P4.5 Approved Operational Knowledge and P4.6
Task-to-Knowledge guidance are **DONE/CLOSED** at their documented baselines. P4.7 is **DONE/CLOSED** at implementation `ccfa3df`, with 80/80 PASS, targeted independent APPROVE, targeted SECURITY APPROVE and green [changed-commit CI 37377829784](https://github.com/RobinBrohl/storeos/actions/runs/37377829784). No active P4.7 remediation remains.
P4.6 has targeted review APPROVE, 64/64 PASS, focused Codex Security SECURITY APPROVE
and green changed-commit CI; future boundaries are
explicitly labeled below. [Status](../roadmap/status.md) owns delivery and
[vision](../vision.md) owns product scope. A logical boundary does not require
a separate process, Dart package or database schema.

## Current placement and dependency rule

`apps/server` is the composition root. Logical modules live in
`apps/server/lib/src/{organization,people,workforce,tasks,inventory,stock,merchandising,knowledge,production,purchasing}/`;
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
| Workforce | Shift drafts, publication/cancellation, last interval-amendment evidence, one-way transfer requests/consent/decisions/Shift lineage and receipts | Shift and transfer command/query ports. Planned work is not actual time recording. Published ownership is never reassigned in place; P4.11 creates exact replacement work. Begun-work reconciliation remains unsupported. |
| Purchasing | Minimal Company Supplier identities; local PurchaseOrder intent, ordered immutable snapshots, lifecycle/history and eight durable receipts; delivery declarations/revisions, reconciliation and terminal snapshots | Inventory-owned `PurchasingArticlePort` validates active Article/version/unit and effective local Assortment. Current Admin and configured execution Location govern Order ports. P4.12 is DONE/CLOSED under ADR 0026, with F01 CLOSED, targeted APPROVE, SECURITY APPROVE and successful implementation CI 38152045998; documentation closure CI 38156014870 successful. Issue is internal approval; closure is administrative. No receiving, prices, conversions, Stock/Task effects, transmission or events. |
| Tasks | TaskTemplate revisions/guidance selection, immutable TaskInstance snapshots/pins, execution state, step results, blockings, numeric attempts, command receipts and source/replacement transfer links | Task creation/execution/resolution/query and exact transfer validation/lineage ports. Does not update Workforce tables or own future HACCP records. |
| Inventory | Company-wide Article and ArticleLocationAssortment; immutable Article quantity anchors, profile revisions, direct packaging and quantity command receipts | `InventoryArticlePort` and released `inventory_article_location_projection`; narrow transaction-scoped `ArticleQuantityPort` and retained-factor SQL integrity port. Owns effective Article/Assortment and quantity semantics, not Stock balances or prices. P4.15 DONE/CLOSED under ADR 0029. |
| Stock | StockLevel projection, immutable StockMovement ledger, StockCount/Line/Round/Observation/Command; prospective immutable quantity bindings and conversion evidence/receipts | Authorized manual opening/correction, exact reviewed alternate-unit targets and selected 1–100-level physical counts, blind own observation, recount and whole atomic approval. Exact thousandths, immutable unit/baselines/bindings and typed correction provenance. Inventory supplies quantity facts through its public port; People/Identity ports supply eligibility. No foreign repositories, Tasks, events, valuation, automatic receiving/posting or cross-dimensional conversion. P4.15 DONE/CLOSED under ADR 0029; historical P4.8 closure: targeted APPROVE, 124/124 PASS, SECURITY APPROVE and green exact-commit CI; ADR 0022. |
| Merchandising | Local Fixture, independent Company Planogram, Revision/Zone/Placement and immutable Assignment | Organization scope, Inventory Article/Assortment and Stock referenced-level public ports; browser print; `PlanogramGuidancePort` validates exact fresh deployments and resolves retained instructions after authorized Task/Template context. No Stock writes or events. P4.4 DONE/CLOSED; P4.7 DONE/CLOSED. |
| Knowledge | Company-wide WikiArticle and immutable published/discarded WikiRevision | Authorized instruction discovery/read and explicit management/publication. Knowledge-owned exact published-revision validation and exact contextual historical resolution through its public port; no foreign business tables, Task snapshot ownership, readership tracking or events. [ADRs 0019/0020](../adr/README.md); P4.5/P4.6 DONE/CLOSED. |
| Production | Company-wide Article-linked Recipe, immutable revisions and ordered frozen ingredient composition; Location-scoped PreparationAssignment and PreparationBatch, immutable command receipts and append-only count corrections | Inventory-owned `RecipeArticlePort` / `inventory_recipe_article_projection` and released effective local Assortment; current employee composition, exact batch context and manager history. P4.13 immutable requests/atomic Batch linkage are DONE/CLOSED — accepted implementation under ADR 0027; F01 CLOSED, targeted APPROVE, SECURITY APPROVE, exact implementation CI 38224661628 successful; docs publication/closure-commit CI pending. P4.10 declarations are DONE/CLOSED under ADR 0024: F01–F03 CLOSED, targeted APPROVE, 156 PASS / 0 QUALIFIED / 0 FAIL, SECURITY APPROVE and green exact-commit CI 37632074236. Declared batch only; no yield, conversions, Stock/Task effects, readership or events. [ADR 0023](../adr/0023-approved-article-recipe-composition.md); P4.9 DONE/CLOSED, F01–F05 closed, targeted APPROVE, 151 PASS / 1 QUALIFIED / 0 FAIL, SECURITY APPROVE and green exact-commit CI. Criterion 152 is historical evidence qualification only. |
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

Selection and fresh publication require the exact current eligible deployment in the Company transaction. Historical contextual resolution validates durable identity after scoped Task/Template authorization without requiring current/active lifecycle. Migration 0019 binds the complete tuple to append-only Assignment evidence; no transient lifecycle belongs in the FK. Frozen instruction and explicitly current Inventory/Stock enrichment are separate. Reads create no execution, acknowledgment, audit or event. See [ADR 0021](../adr/0021-task-planogram-assignment-guidance.md) and [closure evidence](../development/phase-4-7-task-planogram-guidance.md).

## Intentional future ownership

These are **planned boundaries**, not existing modules or final schema decisions.
Public ports should express product dependencies without circular Domain ownership.

| Future owner | Intended data/responsibility | Dependencies through contracts; excluded ownership |
| --- | --- | --- |
| Knowledge extensions | Suggestions and separate review beyond delivered P4.5/P4.6 | Concrete Task guidance is delivered through [ADR 0020](../adr/0020-task-knowledge-guidance.md); further consumers/lifecycle changes need separate contracts. Reads never change execution history. |
| Merchandising extensions | Future HQ rollout, acknowledgment and deviations beyond P4.4 | Separately approved contracts; Tasks would own rollout work. No foreign Stock writes or general CAD. |
| Production extensions | Future yield, production orders, consumption and costing beyond delivered composition and preparation evidence | Require separately selected contracts; Inventory retains Article identity and Stock retains physical evidence. P4.12 Purchasing intent is DONE/CLOSED; documentation closure CI 38156014870 successful; P4.13 is DONE/CLOSED — accepted implementation; F01 CLOSED, targeted APPROVE, SECURITY APPROVE and exact implementation CI 38224661628 successful. P4.13 closure publication/CI 38229127545 verified successful. P4.14 DONE/CLOSED — accepted implementation at 0c62bdf977727c8fa9ddf645e09cc1b34c0ab4df; functional and targeted APPROVE, F01/F02 CLOSED, SECURITY APPROVE, verification PASS, implementation CI 38277299556 SUCCESS; documentation-closure publication and its own CI PENDING. P4.15 DONE/CLOSED — accepted implementation; implementation/correction/main CI are recorded above; separate documentation-closure publication and its own CI PENDING. P4.16 SELECTED / DESIGN IN PROGRESS (design only; implementation NOT AUTHORIZED). |
| Purchasing / Receiving extensions | Receipt/source cost evidence beyond bounded P4.12 order intent | Article/unit references; future authorized Stock commands for accepted physical receipts require separate selection. Not Stock ledger owner or invented valuation. |
| Sales integration | Canonical SalesSource/import/checkpoint, Sale/Line source references, mapping and import health | Core validates authority/identity and coordinates explicit Stock/report effects. Vendor adapter acquires/converts; checkout/payment/fiscal archive ownership separate. |
| Pricing | Effective prices/currency and approval rules | Article references; Menu consumes approved price contract. No implicit price column in Article. |
| Menu / public publishing | Structured Menu revisions, themes/print artifacts and explicit public publication | Optional Article/Recipe/price references. Publisher owns artifact deployment/status, not public operational DB access. |
| Communications | Boards, announcements and Chat content/membership lifecycle | Identity/scope and operator privacy policy; Notifications owns delivery, not message content. No generic Slack system or employee scoring. |
| Notifications | Durable event-based delivery/retry/failure/preferences/contact use | Domain facts with minimal authorized payloads; not business approval or proof of readership. |
| Workforce extension | P4.16 selected design: bilateral requests, immutable legs/consents/decisions, paired Shift lineage, receipts and shared handoff claims | Protocol B and one authorized coordinator use existing owners' public ports. Tasks owns paired Task lineage. Design only; broader comments, scheduling and begun-work reconciliation remain future. |
| HACCP | ControlPlan/Execution, measurements, deviations and corrective actions | Tasks presents control work; HACCP retains authoritative safety evidence. Generic task numbers are not certified records. |
| Reporting / Finance | Defined metrics, provenance, scoped exports and later finance records | Authorized projections; no business-table ownership, fabricated margins or assumed valuation. |
| Remote access boundary | Authenticated workplace/remote context and capability allowlist, optional gateway | Identity/grants/resource authorization remains in Core. No mandatory private device/cloud and no automatic remote full-admin exposure. |

## Evolution rules

### Selected P4.16 ownership extension (not implemented)

Workforce will own one active handoff-claim authority for both P4.11 source Shifts
and P4.16 legs, alongside bilateral request/leg/lifecycle/receipt/Shift lineage
evidence. Claims are a current projection; guarded terminal deletion retains all
business evidence. P4.11's local index and accepted receipts/lineage remain intact.
One Application coordinator validates both consents and creates both replacements
in the same authorized Company transaction. It does not own another Shift model.

Tasks will capture exact ordered work references, validate pristine source sets,
materialize exact replacement work and own immutable task_swap_links. A narrow
Tasks-owned SQL integrity port supports deferred approval/reference checks; no
Application/Workforce repository gains foreign Task-table access. People/Identity
retain eligibility/link/account-version facts; Knowledge/Merchandising retain pin
validation and content. Existing P4.11-specific Task lineage is not reused for swap
request IDs. There is no consumer requiring events or notifications.

See the [complete contract](../development/phase-4-16-bilateral-shift-swaps.md) and
[file-level plan](../development/phase-4-16-implementation-plan.md). No new application
port, table or migration is delivered by this documentation selection.

P4.11 is **DONE/CLOSED** and implements the one-way, future/pristine Shift transfer described in
[ADR 0025](../adr/0025-one-way-shift-transfer-before-execution.md). Workforce owns
requests, consent, decisions, Shift lineage and Company-scoped receipts. Tasks owns
complete source/replacement Task links and exact snapshot verification. The
application coordinator uses public owner ports for Identity/People, Workforce,
Tasks and guidance validation; it never accesses their foreign repositories.
F01/F02/F03 are CLOSED; targeted APPROVE, 177 PASS / 0 QUALIFIED / 0 FAIL, SECURITY APPROVE and green exact-commit CI 38125193187 establish closure.
Broader Workforce capabilities remain unselected; P4.16 bilateral swaps are selected for design only. P4.12 delivers accepted bounded Purchasing intent under ADR 0026, with documentation closure CI 38156014870 successful; P4.13 is DONE/CLOSED — accepted implementation; F01 CLOSED, targeted APPROVE, SECURITY APPROVE and exact implementation CI 38224661628 successful. P4.13 closure publication/CI 38229127545 verified successful. P4.14 DONE/CLOSED — accepted implementation at 0c62bdf977727c8fa9ddf645e09cc1b34c0ab4df; functional and targeted APPROVE, F01/F02 CLOSED, SECURITY APPROVE, verification PASS, implementation CI 38277299556 SUCCESS; documentation-closure publication and its own CI PENDING. P4.15 DONE/CLOSED — accepted implementation; implementation/correction/main CI are recorded above; separate documentation-closure publication and its own CI PENDING. P4.16 SELECTED / DESIGN IN PROGRESS (design only; implementation NOT AUTHORIZED).

Own each schema change through a new tested migration; retain IDs, snapshots and
supported contracts. Do not let a future integration write Core tables directly.
Events represent committed facts, not a substitute for synchronous consistency.

A new module needs one bounded use case, owner, permissions, audit/events decision,
error handling and tests before code. See [ADRs](../adr/README.md),
[guided work](guided-work.md), [workforce orchestration](workforce-orchestration.md)
and [data ownership](data-ownership.md). Larger entity names above are conceptual;
choose concrete persistence/API contracts only when a slice is approved.

## P4.13 preparation ownership

Production owns PreparationAssignment, command receipts and atomic Batch linkage under
[ADR 0027](../adr/0027-planned-preparation-assignment.md). People supplies current Employee
eligibility through its public service; Identity supplies a narrow current link/Account
eligibility boolean; Organization and Inventory ports retain their existing scope/catalog
ownership. Assignment application code never reads their foreign repositories/tables.
Only persisted assigned evidence authorizes retained R1 execution after R2. Existing
standalone Batch opening remains current-revision-only. Planning and execution outcomes
remain separate. No Stock/Purchasing/Task/Shift/events/attendance/HACCP coupling is added.

Delivery is DONE/CLOSED — accepted implementation: F01 CLOSED, targeted APPROVE,
SECURITY APPROVE and exact implementation CI 38224661628 success. Documentation
publication/closure-commit CI remains PENDING; P4.14 UNSELECTED. Platform supplies one
authorized transaction for locked Assignment, server-generated Batch/opening operation,
both receipt families, linkage, minimized audit and deferred final-state validation.
There is no independently committed nested operation. See [dated closure](../development/phase-4-13-planned-preparation-assignments.md#final-documentation-closure--2026-10-12).

## P4.14 Purchasing delivery boundary

Purchasing owns append-only delivery revisions/lines/receipts and immutable terminal
reconciliation under [ADR 0028](../adr/0028-purchase-order-delivery-evidence.md).
The existing authorized Company transaction coordinates Order locking, delivery
ledger revisions, old/new Purchasing operation namespace protection, terminal capture
and minimized audit. Order versions and old receipt meanings remain unchanged.
Organization/Platform retain scope/authorization; frozen Order lines define units.
No foreign repositories, Stock writer, physical inventory effects or events are added.
Recorded delivery evidence does not mutate or establish Stock. P4.14 is DONE/CLOSED
as an accepted implementation at `0c62bdf977727c8fa9ddf645e09cc1b34c0ab4df`;
both independent reviews APPROVE, F01/F02 CLOSED, SECURITY APPROVE and verification PASS.
All five [implementation CI 38277299556](https://github.com/RobinBrohl/storeos/actions/runs/38277299556)
jobs succeeded. Documentation-closure publication and its own CI remain PENDING.
P4.15 was UNSELECTED at the P4.14 closure; its current accepted status is recorded above. Earlier unselected mentions describe their historical baselines.
