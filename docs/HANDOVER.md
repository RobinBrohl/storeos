# StoreOS handover

Start after [AGENTS.md](../AGENTS.md). Current source baseline: `main`,
`e8ce8c319e2dd3051b402d252a0666f33b170fa3`, reconciled 2026-10-04.
The tree was clean before this documentation pass; `origin/main` matched locally
without fetching. These edits are uncommitted documentation only.

Use [actual status](roadmap/status.md) for delivery, [vision](vision.md) for the
product, [roadmap](roadmap/phases.md) for sequencing and [technical debt](development/technical-debt.md)
for live findings. The [2026-10-04 audit](development/project-health-audit-2026-10-04.md)
records earlier checks in this session; current-head remote CI was not verified.

## Done and active work

- P0/P1 single-site foundation and platform administration are delivered, including
  fixed roles, local authentication, account self-password change, atomic audit,
  organization outbox and restricted external plugin clients.
- P1b.1–P1b.9 deliver Employee identity, versioned task templates, Employee Home,
  guided confirmation/numeric execution, blocking/resolution, cancellation and
  pre-execution published-shift interval amendment. No general rescheduling or swaps.
- P4.1 Article and P4.2 location Assortment are committed; historical remote CI is
  recorded for these baselines. Article unit remains a label, not a conversion system.
- P4.3 manual Stock is implemented and committed at `e8ce8c3` (migration 0015,
  [ADR 0017](adr/0017-manual-stock-foundation.md)). **ACTIVE: acceptance corrections
  remain.** Stock retry identity, dialog error handling and a misleading mock test
  need a focused code cycle; this documentation task does not fix them.
- Highest broadly completed foundation remains P1; later slices do not mean all
  intervening roadmap domains are complete. P2 has bounded recovery/capacity tooling,
  not device queues, distributed sync, HA or automatic restore activation.

## Architectural invariants

- Local-first, self-hosted Dart modular monolith, PostgreSQL and Flutter.
  Logical modules live under `apps/server/lib/src/`; `modules/` is reserved.
- One configured Company per installation; other named Locations can be registered.
  That does not implement multi-site execution or replication.
- Domain/Application owns business rules; routes and widgets delegate.
  Cross-module work uses public ports and a shared local transaction.
- `runAuthorized` revalidates session, rights and scope under a Company advisory lock.
  State, relevant audit and required events commit together.
- Workforce owns shifts; Tasks owns snapshots/execution/evidence. Publication is
  atomic; no shift/task integration events currently exist without a consumer.
- Inventory owns Article/Assortment. Stock owns immutable movements and level
  projections; it reads the released inventory projection/port, not foreign tables.
  Existing stock survives Article/Assortment deactivation.
- IDs and immutable snapshots/evidence are preserved. Migrations 0001–0015 are
  append-only; no applied file edits, silent overwrite or evidence deletion.
- Personnel decisions remain human. Task activity is not attendance or employee scoring.

Details: [module boundaries](architecture/module-boundaries.md),
[ownership](architecture/data-ownership.md), [ADRs](adr/README.md),
[principles](product-principles.md).

## Active blockers and debt

F01/F06/F07 gate P4.3 acceptance: guard stock commands before mutating pending identity,
disable duplicate dialog submissions, retain invalid input/errors and correct the
mock's version behavior with meaningful regression coverage in a later authorized code task.
Server version checks protect against silent ledger overwrite; this is a client
retry/UX defect, not demonstrated ledger corruption.

M1 remains active before a proxied real-user pilot: the current login limiter sees
the proxy socket address. Arbitrary forwarded headers are not a trusted fix.
M3/M4 global API/error debt remains; every new endpoint must contain it with
complete contracts, explicit errors and negative HTTP tests. External API/SDK work
requires broader review. **M2 is closed by migration 0012**, not deferred.

Other live items include scope consistency before multi-site execution, readiness's
early-schema-only check, harness diagnostic redaction/refusal coverage and maintenance
couplings. See [technical debt](development/technical-debt.md) for triggers and evidence;
[risks](risks-and-open-questions.md) separates product/operator decisions.

## How to Run StoreOS

Use [local development](development/local-development.md) for SDK versions, setup,
bootstrap, server/client commands, checks, E2E prerequisites and upgrade conventions.
Use [deployment](architecture/deployment.md), [Docker](../infra/docker/README.md),
[TLS](../infra/reverse_proxy/README.md) and [backup/restore](../infra/backup/README.md)
for operation. The old long handover is preserved as a [historical snapshot](development/handover-snapshot-2026-10-03.md).

Apply all migrations before starting a new binary; `/ready` currently checks only
0001–0004 and is not proof of full schema compatibility. Client sessions and pending
commands are memory-only. Disconnected devices cannot persist offline commands.

A restored database is fenced. Recovery acceptance does not prove automatic
replacement activation, downgrade, target-hardware capacity or all physical devices.
Before real employee data: decide retention/access/export/deletion/offboarding,
RPO/RTO, key custody/off-host restore and supported devices. No compliance certification.

## Next Recommended Work

1. Complete one focused P4.3 retry/dialog/test correction cycle, then relevant
   analyzer/tests and review/CI verification before marking it DONE.
2. Choose one next product slice against real operator data. Canonical external-POS
   ingestion is a candidate with a concrete source; recurring/guided work is an
   alternative if no usable source exists. Neither is an active implementation.
3. Resolve M1 when adopting a real-user proxy topology; apply M3 containment to
   every API-adding slice and the remaining debt only at its stated triggers.

No feature, commit, push or branch change is authorized by this handover.
The [workflow](development/workflow.md) defines the development process; new
technical material is English. Avoid unrelated refactors and speculative abstractions.
