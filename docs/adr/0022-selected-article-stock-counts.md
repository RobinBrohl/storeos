# ADR 0022: Selected-article Stock counts and immutable physical observations

Status: Accepted product/architecture decision; P4.8 DONE/CLOSED, targeted independent
APPROVE, 124/124 PASS, focused SECURITY APPROVE and green changed-commit CI.
Date: 2026-10-06

## Context

ADR 0017 establishes exact thousandths, an immutable unit snapshot, a movement
ledger and an authoritative balance/version projection. Operators need a bounded
physical count of selected existing StockLevels while ordinary Stock remains
writable. Guided Work supplies useful interaction/replay patterns, but physical
Stock evidence belongs to Stock. P4.7's configured execution-Location equality
must also apply to every historical count read and receipt replay.

## Decision

Stock owns StockCount, StockCountLine, StockCountRound, StockCountObservation and
StockCountCommand. Migration 0020 introduces exactly those five tables and typed
`count_correction` movement provenance. Counts select 1–100 distinct existing
levels at one configured Company/Location, assigned to one eligible Employee.
The sole lifecycle is open → approved or cancelled; scope and assignment never
change. A terminal count may be linked by a new count with fresh baselines.

Each line freezes Article/StockLevel identity, position, Stock unit and the minimal
count-time identification labels SKU, name and optional opaque barcode. Article ID
is authoritative; labels make historical evidence interpretable after metadata
changes. No description, price or unrelated Article fields are copied. A round
captures exact baseline quantity/version/unit at database time. Observations are
immutable, one per round, and retain assigned Employee separately from recording
Account. Recount appends a round for only selected lines and captures fresh Stock.

Separate employee DTOs expose identification, unit, current round and permitted
observations/history. They exclude baseline, discrepancy, Stock quantity/version,
recording Account and manager review/terminal outcome details. The wire boundary
enforces blindness; Flutter cannot recover those fields. Public People and Identity
ports validate current eligibility and Account links. Stock repositories never read
foreign People, Identity, Task or Inventory-owned tables; Article information comes
through the existing released Stock/Inventory read contract.

The current approving Account must differ from every CURRENT observation's
recording Account. Historical superseded self-recorded observations remain evidence
and do not independently block approval. This is a product integrity rule, with
no legal or statutory inventory certification claim.

Whole approval occurs in the existing authorized Company advisory transaction.
Every current round must be observed, its unit compatible, and its baseline version
equal to current Stock version. Quantity equality cannot repair staleness, including
ABA changes. All lines are validated before effects. Each nonzero discrepancy yields
exactly one correction to observed quantity, with scoped count/line/observation
provenance and immutable ledger evidence. A zero line retains approved observation,
discrepancy zero and checked version with null movement; it never writes Stock,
advances its version or changes its balance timestamp. Any failure rolls back the
entire approval, audit and receipt. No Stock lock lives across user interactions.

Every command has a Stock-specific receipt binding operation UUID, Company,
Location, actor, Count, kind, canonical payload and original committed result.
Current session, capability, execution Location and own-resource scope precede
receipt lookup. Exact replay returns original evidence before fresh lifecycle/version
checks and performs no additional Stock/audit write. No generic command engine,
Task schema 5 or event/outbox consumer is introduced.

Fixed capabilities are `stock.counts.manage`, `.approve`, `.self.read`, `.self.record`.
Admin receives all four under the existing fixed-role architecture; own access
also requires a current eligible Employee link. Employee receives own read/record.
Manager operations additionally require `stock.levels.manage`. Viewer, Auditor and
Plugin receive no count business capabilities. Explicit execution-Location equality
precedes every resource read/replay, including other registered Company Locations.

Database composite identities, unique constraints, checks, immediate append-only
guards and deferred final-state checks protect evidence and typed movement outcomes.
Runtime grants permit only supported append and lifecycle/pointer/outcome columns;
there is no broad evidence UPDATE/DELETE/TRUNCATE or SECURITY DEFINER. This retains
the supported-writer boundary, not protection against a privileged owner disabling
triggers. Audit stores bounded identifiers, versions and transitions, never duplicated
quantity/discrepancy/note/reason/purpose values. Business records own those facts.

## Alternatives

Task-based counts would mix task execution evidence with physical Stock approval
and are rejected. A generic workflow/receipt engine is speculative at this scope.
Long-lived Stock locks would inhibit autonomous operation. Partial approval would
make the selected whole-count contract ambiguous. Editing observations would destroy
attribution; another physical count requires a new round. Automatic inverse movements
would rewrite the meaning of later Stock activity; corrections use new linked counts.

## Consequences

Manager UI distinguishes captured baseline from explicitly current Stock. Employee
UI is blind and accepted observations are read-only. Lists/history use scoped keyset
pages of 50; detail contains at most 100 current lines. Flutter pending commands are
canonical, deeply immutable and memory-only, bound to opaque session identity/epoch.
Uncertain outcomes permit only exact retry; confirmed refresh failure does not invite
duplicate approval. Replacement sessions clear reads, choices, inputs and pending
tracking immediately. Reload/session replacement can lose local uncertain tracking;
operators must reload server state and inspect durable evidence.

Backup acceptance hashes all five count tables and movements, then checks restored
blind reads, exact receipt replay and Location denial after existing revocation/fencing.
Update/recovery remains forward-only; it runs through 0020 and preserves pre-update
restore-point independence. Dedicated 0019→0020 tests preserve Task schemas 1–4,
Knowledge, Planogram and legacy Stock and prove failed migration rollback.

## Open questions

Statutory inventory certification, valuation, recurring/whole-Location counts,
offline writes, multi-site sync and device/scanner workflows need separate contracts.
Independent review, focused security review and remote changed-commit CI remain gates
before canonical DONE/CLOSED. See the [slice](../development/phase-4-8-stock-counts.md).
