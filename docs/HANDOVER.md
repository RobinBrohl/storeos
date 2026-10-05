# StoreOS handover

P4.7 Task + exact Planogram Assignment execution pinning is **IMPLEMENTED LOCALLY / INDEPENDENT REVIEW APPROVE / SECURITY REMEDIATION COMPLETE / TARGETED SECURITY RE-REVIEW PENDING / REMOTE CHANGED-COMMIT CI PENDING** on `main`, uncommitted and unstaged. The verified starting HEAD was `a0ed6346f7453c8f4e170aee43af8d775677f97b`, matching cached/live origin; all five exact-HEAD jobs succeeded in [baseline CI 37290533013](https://github.com/RobinBrohl/storeos/actions/runs/37290533013). New migration 0019 adds schema 4 and durable Fixture/Assignment/Revision integrity; migrations 0001–0018 and dependencies/lockfiles are unchanged. Existing P4.1–P4.6 closure remains intact. No P4.8 capability is selected.

See [P4.7 evidence](development/phase-4-7-task-planogram-guidance.md) and [ADR 0021](adr/0021-task-planogram-assignment-guidance.md). Fresh selection/publication requires the exact current eligible Assignment. Historical Task reads keep the stored tuple after reassignment and terminal retirement; opening either guidance panel is read-only. All business acceptance writes used isolated databases; the normal StoreOS database was untouched.

P4.6 closure context:

Start after [AGENTS.md](../AGENTS.md). P4.6 Guided Operation — Task + approved
Knowledge revision pinning is **DONE/CLOSED** at implementation commit
`15679bf3c81f50ca31e4995d5b958d7c27e5284d`. The first independent review returned
**CHANGES REQUIRED** with exactly one LOW commit blocker, F01. Bounded remediation
separates draft selection `guidance_selection_unavailable` from fresh-publication
`guidance_unavailable`; committed replay returns original evidence after current
authorization. Targeted independent review **APPROVE**, **64/64 PASS**, focused
Codex Security **SECURITY APPROVE** and all five jobs green in
[changed-commit CI 37287951549](https://github.com/RobinBrohl/storeos/actions/runs/37287951549)
establish closure. Real Flutter/HTTP/PostgreSQL and Chrome journeys, backup/restore,
update/recovery and full regression are recorded. Before closure edits, `main`
was clean and matched cached/live origin, with one worktree and no stash.
At P4.6 closure the migration chain ended at 0018; 0001–0017 were unchanged. See
[P4.6 evidence](development/phase-4-6-task-knowledge-guidance.md#final-documentation-closure--2026-10-05)
and [ADR 0020](adr/0020-task-knowledge-guidance.md). No active P4.6 remediation remains.
That P4.6 closure changed documentation only; no commit, push, branch/dependency change
or database operation occurred in that closure pass. P4.7 was not selected at that time.

P4.5 Approved Operational Knowledge is **DONE/CLOSED**:
independent adversarial review **APPROVE**, **60/60 PASS**, and all five jobs green
in [changed-commit CI run 37229964360](https://github.com/RobinBrohl/storeos/actions/runs/37229964360)
for that exact implementation commit. Its closure migration chain ended at
`0017_approved_operational_knowledge.sql`; 0001–0016 were unchanged at that closure.
No active P4.5 remediation remains. F01/F02 are LOW, non-blocking follow-ups retained
in [technical debt](development/technical-debt.md#p45-low-non-blocking-follow-ups).
See [P4.5 evidence](development/phase-4-5-approved-operational-knowledge.md#final-documentation-closure--2026-10-04)
and [ADR 0019](adr/0019-approved-operational-knowledge.md). Browser acceptance does
not establish native-device or accessibility acceptance. That P4.5 closure pass made
no implementation change, commit, push or branch change.

P4.3 Manual Stock Foundation is **DONE/CLOSED**: the committed acceptance correction
has independent targeted review **APPROVE**, **28/28 PASS**, and fully green
[changed-commit CI](https://github.com/RobinBrohl/storeos/actions/runs/37199144795).

P4.4 Local Planogram Execution is **DONE/CLOSED**. Implementation `cd7669ed`
and bounded CI portability fix `73dca5a4` are committed on `main`. Closure combines
the independent full CHANGES REQUIRED review, F01/F02 remediation, targeted
**APPROVE**, acceptance 1–49 PASS / 50A PASS / 50B QUALIFIED / 51–68 PASS,
and fully green [changed-commit CI run 37217071802](https://github.com/RobinBrohl/storeos/actions/runs/37217071802)
for portability-fix commit `73dca5a4`. All five jobs succeeded. Migration/update/
recovery, backup/restore, real Flutter/HTTP/PostgreSQL journeys and browser print
acceptance are recorded in the [final closure](development/phase-4-4-local-planograms.md#final-documentation-closure--2026-10-04).
Browser evidence does not establish physical printer/device or accessibility acceptance.
F01/F02 are **CLOSED**; F03 is an **ACCEPTED LIMITATION / NON-BLOCKER** and F04 is
**QUALIFIED BASELINE EVIDENCE / NON-BLOCKER**. No P4.4 remediation remains active
absent regression. The first failed [CI run 37214855513](https://github.com/RobinBrohl/storeos/actions/runs/37214855513)
is retained as historical CI configuration evidence. No production code change
was required for that fix. [ADR 0018](adr/0018-local-planogram-execution.md) remains unchanged in decision.

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
- P4.4 Local Planogram Execution is **DONE/CLOSED**: independent Company Planograms,
  local Fixtures, immutable published revisions, explicit append-only Assignments,
  target-Location Assortment validation and browser HTML/CSS print. The migration
  chain at closure ended at `0016_local_planograms.sql`; 0001–0015 retain identical Git content,
  with historical raw checkout-byte evidence qualified rather than asserted.
- P4.5 Approved Operational Knowledge is **DONE/CLOSED**: Company-wide
  instructions, one draft, immutable published/discarded revisions, terminal
  retirement and strict publication replay. Migration 0017 adds two tables;
  0001–0016 retain identical Git content. Independent review APPROVE, 60/60 PASS,
  real Flutter/HTTP/PostgreSQL and Chrome journeys, backup/update/recovery, full
  regression and green changed-commit CI establish closure. At P4.5 closure, no Task
  evidence integration existed; P4.6 adds exact pins. No Knowledge events exist.
  F01/F02 remain LOW, non-blocking follow-ups.
- P4.6 Guided Operation is **DONE/CLOSED**: optional concrete KnowledgeGuidance in
  schema-3 Templates and immutable Task snapshots, exact contextual historical read,
  scoped authorization and literal text rendering. No acknowledgment or execution
  mutation on read. Migration 0018; targeted APPROVE, 64/64 PASS, SECURITY APPROVE
  and green changed-commit CI. Native-device/accessibility acceptance is not claimed.
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
- IDs and immutable snapshots/evidence are preserved. Migrations 0001–0018 are
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
early-schema-only check and maintenance couplings. P4.4 closes the touched
harness diagnostic redaction and migration refusal findings with review and CI
evidence. See [technical debt](development/technical-debt.md) for triggers and evidence;
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

1. Obtain targeted security re-review of the bounded P4.7 Security F01 remediation. Independent normal review APPROVE is preserved; remote changed-commit CI remains pending until a user-authorized commit/push. No P4.8 capability is preselected. No active P4.6 remediation remains.
2. Resolve M1 when adopting a real-user proxy topology; apply M3 containment to
   every API-adding slice and the remaining debt only at its stated triggers.

No feature, commit, push or branch change is authorized by this handover.
The [workflow](development/workflow.md) defines the development process; new
technical material is English. Avoid unrelated refactors and speculative abstractions.
