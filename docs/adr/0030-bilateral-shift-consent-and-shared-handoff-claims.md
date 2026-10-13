# ADR 0030 — Bilateral Shift consent, shared handoff claims and atomic exchange

Date: 2026-10-13. Status: **Accepted for the owner-selected P4.16 design**.
Delivery: **SELECTED / DESIGN IN PROGRESS**; implementation **NOT AUTHORIZED**.
Baseline: `8a0198f3430cb7ec636e952522dda7cf930b7fca`, migrations 0001–0027.
This adds a selected extension to [ADR 0025](0025-one-way-shift-transfer-before-execution.md)
without rewriting its accepted P4.11 evidence or delivered contract.

Independent architecture verdict supplied by the owner: **ARCHITECTURE APPROVE**.
LOW/nonblocking F01 is resolved by the bounded implementation-plan Step 3
documentation correction identifying the private Workforce overlap repository and
its public-port boundary. No fresh independent re-review is claimed. Design
approval does **not** establish verified database enforcement, implementation
acceptance or CI success, and does not authorize implementation.

## Context

P4.11 already supports one named, consented transfer of a complete future pristine
Shift through exact cancellation/replacement and immutable Task/Shift lineage.
Employee Home authorizes own work; transfer discovery exposes colleague ID/name,
not colleague rosters. A bilateral exchange needs two exact consents, two departing
Shifts and one indivisible schedule change. Migration 0023's transfer_active_source
index protects only one-way source requests and cannot arbitrate a swap's two legs.

The owner selects protocol B and authorizes formal specification only. See the
[complete contract](../development/phase-4-16-bilateral-shift-swaps.md) and
[file-level plan](../development/phase-4-16-implementation-plan.md).

## Decision

### Employee-controlled disclosure and exact consent

A requests exchange of an own Shift with named B. B alone discovers own candidate
Shifts and explicitly offers one counterpart. A then confirms the immutable pair.
Independent authorized managerial approval follows. REQUESTED/1 -> OFFERED/2 ->
CONFIRMED/3 -> APPROVED/4, with explicit terminal decline/withdrawal/rejection.
Every terminal transition advances the preceding version once and retains consent.
No schedule effect precedes approval. Changes to either selected leg require closure
and a fresh request, rather than editing consented work.

Both consents bind Company/request/offer-version identity and exact Shift IDs,
versions, intervals, incoming owners and ordered work references. Capture and
revalidate current Account/link/version bases; replacement Accounts do not inherit
consent or replay another actor's command. Approver Account differs from both
consenting Accounts, retaining P4.11's independence policy.

Only request-specific summaries deliberately disclosed by participants are visible:
interval, work titles and identity/revision/pin references. No general colleague
roster, execution values, personnel records or arbitrary historical instruction
access. Use a swap-specific identity finder, not the one-way overlap filter.

### One Workforce claim authority

A single Workforce-owned current claim projection uses primary key
`(company_id,shift_id)` and scoped, typed transfer-source or swap-leg FKs. Active
P4.11 holds its source; REQUESTED swaps hold A; OFFERED/CONFIRMED swaps hold A and
B; terminal workflows hold none. Immediate uniqueness plus deferred parent/leg/
claim consistency guards protect exact occupancy. Both workflows maintain it in
their existing authorized Company transaction; no separate swap reservation system.

Claims may be inserted and deleted only with the corresponding parent lifecycle;
ownership cannot be edited. Terminal deletion removes current occupancy, while
immutable business requests, receipts and lineage retain evidence. Stale eligibility
never expires a claim silently. Existing execution/amendment/cancellation may make
a request non-actionable; explicit participant closure or manager rejection releases
it. Claims are not Employee/time-slot reservations and do not freeze ordinary work.

Use one new forward-only migration after 0027, with stopped/drained application
writers. Add only required scoped anchors and backfill every active P4.11 request,
including stale ones. Retain transfer_active_source, old payloads/receipts/lineage
and historical migrations. P4.11 adds shared pending/conflict handling and lifecycle
hooks; no old consent/state/replay contract is replaced. Swaps keep their own
Company/operation receipt namespace; claim sharing is independent of UUID namespaces.

### One exact atomic approval

One Application coordinator revalidates both originals, full pristine Task sets,
captured consent bases, incoming assignment eligibility and exact guidance through
public owner ports in one runAuthorized transaction. Workforce owns requests/legs/
claims/Shift lineage; Tasks owns snapshots and paired Task links; other modules
retain their own truth. Narrow Tasks-owned SQL integrity ports support deferred
database checks without new application foreign-table access.

Evaluate the final roster excluding exactly both persisted originals. Cancel both
originals before publishing either replacement, preserving the immediate overlap
exclusion. Create both exact replacements and complete ordered correspondence;
record decision, receipts, audit and claim release atomically. Existing P4.11 Task
lineage is not repurposed for swap request IDs.

An initially deferred fresh-approval guard proves both complete effects and checks
fresh database clock_timestamp() last before both captured starts. Historical replay
and later replacement execution do not reapply fresh lifecycle/time constraints.
Any second-leg, receipt, audit or final-guard failure rolls back all attempted effects.
The guarantee is the final deferred validation boundary, not exact client delivery
or WAL-durability timing. No labor-law, absence, qualification or attendance claim.

## Alternatives

- Bounded peer-Shift discovery saves one interaction but discloses schedules before
  B consents; reject it in favor of employee-controlled counterpart disclosure.
- Recipient selection without A confirmation lacks A's consent to the final pair.
- Two independent transfers can partially commit and mis-evaluate departing overlaps.
- Separate transfer/swap reservations cannot supply one cross-workflow invariant.
- General workflow engines, distributed reservations and configurable RBAC add
  unneeded scope to a single-site paired operation.
- Silent expiry or stale claim theft would erase the explicit P4.11 closure boundary.
- In-place assignment or guidance repinning would change historical ownership/work.

## Consequences

The consent interaction has an additional stage. Shared claims require a bounded
P4.11 migration/service integration and its regression proof; this is not a trivial
reuse of its endpoint. Proposed persistence is five new tables plus narrow anchors,
guards and runtime grants. Claims are the only deletable new current projection;
receipts, source facts, accepted consents and Task lineage remain protected evidence.

Flutter pending state stays memory-only, immutable and session fenced. Current
actionability and original accepted receipt results remain distinct. Audit is
atomic/minimized; no event consumer or notification is introduced. Backup/restore
preserves claims as well as evidence and respects existing recovery fencing.

P4.15 immutable anchors/bindings, permanent suspension, historical compatibility,
six qualifications and nonblocking debt remain unchanged. Broader Workforce,
remote, offline and multi-site capabilities remain outside this decision.

## Open Questions and implementation gate

No unresolved owner policy choice or architectural contradiction is known inside
the selected scope. Exact database constraints/grants, populated backfill, paired
lineage and time boundaries must be demonstrated by the contract's acceptance
cases, independent functional/Security review and exact-commit CI after separate
implementation authorization. These are future gates, not current evidence.
If a proof reveals a contradiction, report it before changing the selected contract.
