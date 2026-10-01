# ADR 0013: Published-shift cancellation before execution starts

Status: Accepted. Scope decided 2026-10-01 as part of the published-shift
cancellation slice (P1b.8).

## Context

P1b.3 published single shifts atomically and made published shifts and their task
snapshots immutable. Publication mistakes (wrong employee, wrong interval, wrong
template selection) could not be corrected afterwards: the shift and its generated
task instances remained visible and actionable, and no supported operation removed
them from Employee Home. Operators named this as the first acute pilot gap.

The open decision "which shift change creates, modifies or cancels TaskInstances and
how is a running task handled" (`docs/risks-and-open-questions.md`) was deliberately
left unresolved. Full amendment and in-flight reconciliation need explicit product
rules for started, blocked and completed work; those rules do not exist yet.

## Decision

A published shift may be terminally cancelled **only while every materialized task
instance is still in the pristine `open` state**. The moment any instance has left
`open` (started, blocked, completed or already cancelled), the whole cancellation is
refused with `422 shift_in_progress` and no state changes.

The cancellation is one authorized local transaction under the existing company
advisory lock:

- the shift transitions `published -> cancelled` and records `cancelled_at`,
  `cancelled_by`, `cancellation_reason` and `cancellation_version`;
- every still-open instance transitions `open -> cancelled` (version `1 -> 2`)
  with its own cancellation timestamp and actor;
- `workforce.shift.cancelled` and one `tasks.instance.cancelled` audit entry per
  instance commit with the state change;
- published snapshots, selections and instruction content remain unchanged.

`cancellation_version` stores the request's original `expectedVersion`. An exact
retry (same `expectedVersion`, same actor, same normalized reason) returns the
existing cancelled state without a second version increment, task mutation or audit
entry. A mismatching retry identity, stale version or non-published state returns
`409 shift_conflict`.

Amendment of a published shift (employee, interval, selections) remains out of
scope; this is cancellation only.

## Alternatives considered

- **Full published-shift amendment with task reconciliation.** Rejected for now:
  needs product rules for partially executed work, receipt and snapshot handling and
  is materially larger than a bounded slice.
- **Refusing all published-shift corrections until reconciliation exists.**
  Rejected: leaves the documented pilot defect in place.
- **Soft-deleting or hiding the shift without cancelling instances.** Rejected:
  would leave dangling `open` instances that can never reach a terminal state.
- **Cancelling started tasks silently.** Rejected: would overwrite evidence and
  contradict the integrity principles.

## Consequences

- Operators can correct a wrongly published shift before work begins; the interval
  is freed because overlap protection only considers `published` shifts.
- Employee Home and employee self-read paths no longer expose the cancelled shift;
  admin reads retain it as historical evidence.
- `TaskExecutionDto` gains a second, strictly validated cancellation shape
  (unstarted); the existing blocked-origin shape is unchanged.
- In-flight work still cannot be cancelled at shift level; a broader reconciliation
  contract is required before that changes.
- The generic audit per-string value bound rises from 256 to 512 code points so the
  bounded 1-500-code-point cancellation reason can be audited. The overall audit
  metadata bound (4096 bytes) is unchanged, the widened bound is still hard, and
  other producers remain below their own smaller field limits.
- No integration event is emitted; no consumer exists.

## Open questions

- Which shift changes (employee, interval, selections) should be allowed once
  instances have started, and who may authorize them?
- How should a corrected republish reference the cancelled shift for traceability?
- Which retention rule applies to cancelled shifts and their audit evidence?
