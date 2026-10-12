# ADR 0027: Planned preparation with retained approved execution authority

Date: 2026-10-11. Decision: Accepted for the user-selected P4.13 implementation.
Local implementation does not close independent review, focused Security or remote CI.

## Context

Managers need to request a bounded amount of preparation from an eligible Employee.
Recipes own immutable approved instructions. PreparationBatch already owns attributable
execution, original completion/cancellation and append-only count corrections.
Publishing a replacement instruction must not silently change an assigned request.

## Decision

Production owns PreparationAssignment and its Company/operation command receipts.
Creation selects one currently eligible Employee, configured Location, exact current
published RecipeRevision and required whole declared batch count 1–9999. The saved
selection, creation identity and evidence are immutable. There is no reassignment.
Assigned version 1 terminates as withdrawn or started version 2. Started never changes
when its linked Batch completes, is cancelled or receives corrections.

Only the Employee derived from the currently active Account link may start. Identity
provides a narrow eligibility boolean; People provides current Employee eligibility.
Company, configured/route/current Account Location, current session and capabilities
are revalidated under the existing Company transaction lock before receipt disclosure.
Account replacement follows Employee-owned work, without inheriting another actor's replay.

A start re-reads the persisted assigned request in the caller's transaction. This
evidence authorizes opening its retained published R1 after R2 publication. Current
Recipe activity, Article activity, produced local Assortment and ingredient units
still gate fresh execution. Retirement blocks fresh starts; scoped historical context
and exact accepted replay remain available. Standalone Batch opening continues to
require the exact current published revision. HTTP never accepts a historical-open flag,
executing Employee, Batch identity, actor, snapshot or timestamp.

Batch opening, its distinct internally generated operation, opening receipt/audit,
assignment link, assignment receipt and audit commit atomically. Composite FKs and a
Batch tuple uniqueness anchor bind Company, Location, Employee, Recipe/revision and
requested count. A unique assignment Batch link and deferred checks bind opening
actor/time, canonical payload and original result to assignment start evidence.
Runtime receives only bounded lifecycle column updates; immutable receipt/content
edits, deletion and truncation remain forbidden. No SECURITY DEFINER is introduced.

Create/withdraw/start share a new Company/operation namespace with actor, kind,
resource, Location and canonical intent binding. Exact authorized replay returns the
original accepted result before current lifecycle/catalog checks, without effects.
The original opened Batch response remains separate from current Batch detail.
Failed transactions consume no operation identity.

Flutter retains frozen route/body/operation/session bindings in memory. Uncertain
commands allow exact retry only, including after later authorization denial. Opaque
same/different Account replacement clears resident fields, mounted forms/dialogs and
history, and fences delayed reads/writes. Confirmation survives a failed refresh;
stale actionable detail is cleared. Business and Recipe text render literally.

## Consequences

The site remains autonomous and the operator owns durable evidence. Manager planning
and Employee actual execution are distinct; zero corrected effective count preserves
the original completion. Audit records identifiers/transitions, without duplicating
counts, names, reasons or instructions. No event consumer exists, so no outbox event
is emitted. Stock/Counts, Purchasing, Tasks/Shifts, Knowledge and Planograms have no
assignment side effects or coupling.

Calendar scheduling, recurrence, multiple assignees, reassignment, attendance, HACCP,
yield/output-unit conversion, Goods Receipt, automatic Stock effects, device offline
writes and multi-site synchronization need separate contracts. P4.14 is UNSELECTED.
Supported-writer/raw-SQL, memory-only retry tracking, hardware/accessibility and operator
privacy/retention/export/recovery decisions retain their existing qualifications.
