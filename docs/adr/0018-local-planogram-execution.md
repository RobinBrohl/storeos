# ADR 0018: Local planogram execution

Status: Accepted product contract; P4.4 DONE/CLOSED, targeted independent review APPROVE and green changed-commit CI. See [final closure evidence](../development/phase-4-4-local-planograms.md#final-documentation-closure--2026-10-04); the architectural decision and supported-writer boundary are unchanged.
Date: 2026-10-04

## Context

P4.4 replaces simple local paper/spreadsheet merchandising instructions. The user explicitly selected the pasted P4.4 product contract as the complete architecture; no separate refined plan exists in the baseline repository. StoreOS remains a local-first, self-hosted modular monolith with a single configured execution Location.

## Decision

Merchandising owns six tables in migration 0016: Fixture, independent Company-scoped Planogram, PlanogramRevision, ordered Zone, ordered Placement and immutable Assignment. Fixture is a Location-scoped physical target, not a Planogram owner. Origin Fixture/authoring Location are provenance. A published revision can serve multiple Fixtures. Retirement is terminal and preserves evidence; Planogram retirement atomically discards its active draft.

One active draft and monotonically allocated revision numbers are guarded by Planogram.version, the existing Company transaction lock and database uniqueness. Published and discarded revision rows/content are frozen by database triggers. Assignments are append-only, published-only evidence; Fixture.currentAssignmentId identifies the current deployment. Publishing does not deploy. Fixture.version guards explicit deployment and retirement. Stale desired-state writes require reload and human review, with no automatic rebase.

Inventory owns the narrow typed Article/Assortment port; Organization validates the configured Location through its public application boundary; Stock owns the referenced-level read port. Merchandising repositories never query these modules' tables. Revision content stores Article IDs, order and optional positive facings, not mutable labels or Stock. Drafts allow inactive same-Company references and do not require Assortment. Publish requires active same-Company Articles. Assign additionally requires active target-Location Assortment. Live deactivation warnings preserve existing instructions; missing Stock, zero Stock and frozen-unit divergence are distinct read context.

The only capabilities are merchandising.layouts.manage, .publish and .read: admin all three, employee read, plugins none. Employee reads are limited to active local Fixtures, current assigned instructions and bounded referenced context/print. Manager-only draft/history/search data stays behind server checks. Mutations, evidence and minimized audit commit atomically. No event/outbox has a P4.4 consumer.

Assigned instruction is primary; live Stock is optional batch enrichment. LayoutView carries `stockContextStatus` (`available` or `unavailable`). Available with a null Article stock means no recorded level; a recorded zero remains explicit quantity plus frozen unit. A failed batch marks every referenced placement's Stock unavailable without changing instruction structure or evidence. The Stock-owned port isolates its SELECT with a savepoint and recovers only PostgreSQL permission unavailability (42501), lock timeout (55P03) and server query cancellation (57014), rolling back and releasing before the authorized transaction continues. Invalid SQL/schema, decoding bugs, failed savepoint recovery and loss of the shared mandatory database connection propagate. Authorization, configured Location and all instruction/Inventory reads remain mandatory. Print skips the Stock port entirely; its empty internal enrichment never enters the public print envelope or HTML.

There is no generic receipt table. Creation retains client UUIDs for authorized reconciliation. Save/edit/discard/retire use expected versions and authoritative reload after ambiguity. Publish replay identity is (operationId, Company, Planogram, revision, actor, expected Planogram version); the frozen revision binds content. Assignment identity is (operationId, Company, Location, Fixture, revision, actor, expected Fixture version). Current authentication, capability and local scope are revalidated before operation lookup. Exact committed replay precedes current lifecycle/version rejection and returns original applied evidence without changing newer state or emitting another audit. Command kind is part of identity: cross-kind Publish/Assign operation-ID reuse is also rejected. The Company transaction lock serializes the two evidence lookups without a seventh receipt table. Conflicting reuse returns operation_conflict. A matching-version already-current assignment is a no-op with no new receipt or audit.

Flutter retains uncertain Publish/Assign route/body/session identity in memory, guards submissions synchronously, and fences immediately on opaque SessionController identity replacement, including held replacement status. Dialog input is widget-owned and replacement closes old dialogs. Browser reload is outside this memory-only recovery contract.

Browser print uses authenticated JSON carrying escaped standalone HTML, opens about:blank synchronously, then invokes the Web adapter. Assignment/revision identity is pinned. A4 landscape contains live-as-of-generation identification, instructions and timestamps, with no Stock or external assets. Employee stale print returns assignment_changed; admin historical print is labeled. Print cancellation has no mutation or acknowledgment. The browser verification harness captures PDF only as a temporary inspection artifact; the product has no PDF generation feature or dependency.

## Alternatives

Fixture-owned Planograms would prohibit reusable revision deployment. Generic receipts would duplicate the durable evidence already owned by revisions/assignments. Article/Stock snapshots would misrepresent mutable live data. Canvas/CAD, HQ rollout, offline queues and generated PDF are outside this slice.

## Consequences

The supported application writer remains the authorization/version/audit boundary. Database triggers also protect immutable evidence against runtime SQL paths, and composite FKs preserve scope. The existing Company writer lock serializes relevant concurrent mutations; this slice introduces no distributed synchronization contract. Historical reconstruction preserves instruction identity/structure, not old mutable labels. Local acceptance and independent review/changed-commit CI are separate delivery facts.

The composite current-assignment FK enforces Assignment ownership by the same Fixture, Company and Location. It does not enforce “latest Assignment” or pointer/version advancement against arbitrary runtime SQL: that role can manually select one of its own Fixture's older Assignments without advancing Fixture.version. Supported Assign atomically appends evidence, advances pointer/version and audit, rolls back on audit failure, and exact late replay never restores older state. This accepted supported-writer limitation (P4.4 review F03) adds no deferred trigger and weakens no existing immutability/scope protection; revisit before another writer or a stronger raw-SQL threat model.

## Open questions

No unresolved decision blocks this bounded local slice. HQ distribution, future execution Locations, durable device recovery and physical geometry need separately approved contracts.
