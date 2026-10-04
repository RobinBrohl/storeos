# StoreOS handover

Start after [AGENTS.md](../AGENTS.md). Current source baseline: `main`,
`cd7669ed7de2751d4dc97c2724a0d11d9f674f51`, verified 2026-10-04 with a clean
tree/index before CI remediation, matching cached `origin/main`, one worktree and no stash.
P4.3 Manual Stock Foundation is **DONE/CLOSED**: the committed acceptance correction
has independent targeted review **APPROVE**, **28/28 PASS**, and fully green
[changed-commit CI](https://github.com/RobinBrohl/storeos/actions/runs/37199144795).

P4.4 Local Planogram Execution is committed on `main` at `cd7669ed7de2751d4dc97c2724a0d11d9f674f51`.
Status is **IMPLEMENTED / REVIEW APPROVED / CHANGED-COMMIT CI NOT YET GREEN**.
Independent targeted review returned APPROVE. The first changed-commit
[CI run](https://github.com/RobinBrohl/storeos/actions/runs/37214855513) failed in
the Dart job: both real Flutter journeys used a Windows-only launcher on Ubuntu,
and the job provisioned only Dart. The portable launcher and pinned Flutter/client
CI setup correction are uncommitted; changed-commit CI for that correction is pending.
Independent review required F01 optional Stock failure isolation and F02 reachable
404 containment; both are remediated locally. F03 supported-writer integrity and
F04 historical migration-byte qualifications remain explicit in the evidence.
P4.4 is not DONE/CLOSED. The user selected
the pasted P4.4 contract as the complete architecture. See [ADR 0018](adr/0018-local-planogram-execution.md)
and [P4.4 development evidence](development/phase-4-4-local-planograms.md).

Use [actual status](roadmap/status.md) for delivery, [vision](vision.md) for the
product, [roadmap](roadmap/phases.md) for sequencing and [technical debt](development/technical-debt.md)
for live findings. The [2026-10-04 audit](development/project-health-audit-2026-10-04.md)
preserves the earlier audit baseline; the [P4.3 closure](development/phase-4-3-manual-stock.md#final-acceptance-closure--2026-10-04)
records the accepted correction and current-head CI.

## Done and active work

- P0/P1 single-site foundation and platform administration are delivered, including
  fixed roles, local authentication, account self-password change, atomic audit,
  organization outbox and restricted external plugin clients.
- P1b.1–P1b.9 deliver Employee identity, versioned task templates, Employee Home,
  guided confirmation/numeric execution, blocking/resolution, cancellation and
  pre-execution published-shift interval amendment. No general rescheduling or swaps.
- P4.1 Article and P4.2 location Assortment are committed; historical remote CI is
  recorded for these baselines. Article unit remains a label, not a conversion system.
- P4.3 manual Stock is **DONE/CLOSED**: foundation `e8ce8c3`, accepted retry/session/
  dialog/fake correction `f9c8b07`, migration chain ending at `0015_manual_stock.sql`
  ([ADR 0017](adr/0017-manual-stock-foundation.md)). Ledger and adjustment retry
  semantics are accepted; no active P4.3 remediation gate remains absent regression.
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
- IDs and immutable snapshots/evidence are preserved. Migrations 0001–0016 are
  append-only; no applied file edits, silent overwrite or evidence deletion.
- Personnel decisions remain human. Task activity is not attendance or employee scoring.

Details: [module boundaries](architecture/module-boundaries.md),
[ownership](architecture/data-ownership.md), [ADRs](adr/README.md),
[principles](product-principles.md).

## Active blockers and debt

F01/F06/F07 and targeted-review findings R1/R2/R3 are **CLOSED** by `f9c8b07`,
review APPROVE and changed-commit CI. The [P4.3 record](development/phase-4-3-manual-stock.md)
preserves the original defects, CHANGES REQUIRED review and final acceptance.
Pending recovery remains memory-only; session replacement ends local tracking
without cancelling or reversing a server operation and requires authoritative reload.

M1 remains active before a proxied real-user pilot: the current login limiter sees
the proxy socket address. Arbitrary forwarded headers are not a trusted fix.
M3/M4 global API/error debt remains; every new endpoint must contain it with
complete contracts, explicit errors and negative HTTP tests. External API/SDK work
requires broader review. **M2 is closed by migration 0012**, not deferred.

Other live items include scope consistency before multi-site execution, readiness's
early-schema-only check and maintenance couplings. P4.4 locally addresses the touched
harness diagnostic redaction and migration refusal coverage; independent review is pending. See [technical debt](development/technical-debt.md) for triggers and evidence;
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

1. Review the bounded uncommitted P4.4 CI correction and complete changed-commit
   CI after an explicitly authorized commit/push. Independent targeted review is
   already APPROVE; do not mark P4.4 DONE before changed-commit CI is green.
2. Resolve M1 when adopting a real-user proxy topology; apply M3 containment to
   every API-adding slice and the remaining debt only at its stated triggers.

No feature, commit, push or branch change is authorized by this handover.
The [workflow](development/workflow.md) defines the development process; new
technical material is English. Avoid unrelated refactors and speculative abstractions.
