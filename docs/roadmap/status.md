# Actual implementation status

Assessment baseline: `da2c9e8` (2026-09-29), clean before handover changes.
Use only `DONE`, `IN PROGRESS`, `TODO` and `BLOCKED` as status values.
`DONE` applies to the bounded scope below, not every ambition in architecture documents.
See [handover verification](../development/handover-verification.md) for evidence.

## Implemented

| Scope | Status | Evidence and boundary |
| --- | --- | --- |
| D0 documentation/repository foundation | DONE | Vision, principles, 12 ADRs, architecture, compliance and monorepo structure exist. |
| P0 single-site foundation | DONE | Flutter Web, Dart HTTP, PostgreSQL, configuration, migrations, local login, logs, design system, CI, optional TLS configuration and encrypted DB backup/isolated restore tooling. Native runners excluded. |
| P1 platform administration | DONE | Organization, accounts, fixed RBAC, runtime append-only audit, organization outbox and restricted external plugin clients; real PostgreSQL security/integrity tests. |
| P1b.1 employee identity | DONE | Profile, fixed site assignment, account link/revocation, own-profile UI and audit. |
| P1b.2 task templates | DONE | Drafts, immutable published revisions, history, scoped administration and audit. |
| P1b.3 shifts/Employee Home | DONE | Draft single shifts, atomic publication and bounded task snapshots; no editing/cancelling published shifts. |
| P1b.4 guided execution | DONE | Start, ordered confirmations, completion, persisted command receipts and retry/conflict handling. |
| P1b.5 blocking/resolution | DONE | Employee blocking, reason/history, administrative resume and audit. |
| P1b.6 blocked-task cancellation | DONE | Reasoned terminal cancellation, history and scoped cancelled-task lists. |
| P1b.7 numeric steps | DONE | Schema 2, exact thousandths, inclusive bounds, immutable attempts, automatic blocking, mixed-step completion, migration 0010 and regressions. |
| Numeric browser E2E | DONE | Real Flutter/HTTP/PostgreSQL journey and evidence/audit checks; app remount/re-login tested. CI job exists; remote execution not asserted. |

## Partially implemented / active

| Scope | Status | Remaining boundary |
| --- | --- | --- |
| P1b overall acceptance/pilot readiness | IN PROGRESS | Bounded online journey works. Literal browser reload/backend-process restart acceptance and broader pilot operating evidence remain separate checks; no recommendation engine or new shift lifecycle is implied. |
| P2 operational resilience | IN PROGRESS | Backup encryption, isolated restore and readiness exist. Controlled recovery/update exercises, capacity limits and device/offline policies are not a complete operating model. |

The highest completed foundation phase is **P1**. P1b.1–P1b.7 are delivered bounded
sub-slices; wider P1b/P2 gates are not blanket completion claims. No known code defect
currently blocks the verified single-site scope. Production use with real employee data
still needs operator-specific retention/access/recovery decisions and the security/
compliance review described in the architecture.

## Planned

| Scope | Status | Boundary |
| --- | --- | --- |
| P2 device cache/queue and conflict protocol | TODO | No durable client queue or offline write acceptance exists. |
| P3 workforce/knowledge extensions | TODO | Skills, recurrence, dependencies, priorities, handover and training are absent. |
| Native Android/desktop runner | TODO | Only Web runner is checked in; Flutter portability is not device acceptance. |
| Published-shift amendment/cancellation | TODO | Needs explicit task reconciliation/history rules before implementation. |

## Intentionally deferred

| Scope | Status | Reason |
| --- | --- | --- |
| Enterprise server/multi-location replication | TODO | Optional; needs authority transfer, conflict and restore contracts. Location rows are not replication. |
| Managed plugin runtime/marketplace/SDK package | TODO | Current plugins are external API clients; isolation and a concrete adapter case are prerequisites. |
| P4 inventory/purchasing, P5 HACCP/devices, P6 production | TODO | Separate domain/integrity/compliance scopes; numeric tasks are not certified HACCP controls. |
| P7 advanced planning/timekeeping, P8 reporting/forecasting | TODO | Planned shifts/task timestamps are not recorded working time or personnel scores. |
| P9 POS, P10 gastronomy, P11 finance/e-invoicing, P12 public channels/AI | TODO | Explicit later roadmap gates; none is a current feature. |

Proposed next cycles are in [HANDOVER](../HANDOVER.md#next-recommended-work).
They need their own scope authorization and are not implemented by this handover.
