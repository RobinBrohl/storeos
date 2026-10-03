# ADR 0014: Pre-execution published-shift interval amendment

Status: Accepted. Scope decided 2026-10-02 as part of the P1b.9 interval
amendment slice.

## Context

P1b.8 added terminal published-shift cancellation while every task instance is
still pristine `open` (`docs/adr/0013-published-shift-cancellation.md`). It
frees the interval, but correcting a wrong shift replaces the shift identity
and produces cancellation evidence even though nothing had been executed. The
remaining documented product gap is amendment of a published shift
(`docs/roadmap/status.md`, "Published-shift amendment").

The health check of 2026-10-02 recorded finding M2: published-shift overlap was
enforced only by an application SELECT under the company advisory lock, without
an equivalent database invariant, and required a DDL exclusion constraint
before any overlap-dependent amendment.

Two constraints limit the amendment shape:

- `task_instances` has a composite foreign key to
  `shifts(id, company_id, location_id, employee_id)`, and instances are
  immutable apart from controlled execution transitions. Changing a published
  shift's employee cannot keep historical instances valid without a schema-level
  redesign.
- `shift_template_selections` is frozen for published and cancelled shifts by a
  protection trigger; replacing selections would need an insert-time-only
  evidence coupling and task reconciliation rules.

## Decision

A published shift's `starts_at`/`ends_at` interval may be amended only while
every materialized task instance is still pristine `open` at version 1. The
whole request is refused with `422 shift_in_progress` and zero writes as soon
as any instance has started, blocked, completed or been cancelled. Employee,
location and template selections cannot be changed by this operation; those
corrections keep using cancellation plus a corrected publication.

The amendment is one authorized local transaction under the existing company
advisory lock:

- the shift keeps its identity, employee, selections and publication evidence;
- `starts_at`/`ends_at` change, `version` increments by one and
  `amended_at`/`amended_by`/`amendment_version` record the most recent
  amendment (`amendment_version` is the request's original `expectedVersion`);
- `workforce.shift.amended` is audited in the same transaction; earlier
  amendments remain only in the append-only audit;
- the shift must still end after the database clock, the employee must remain
  active and assigned for the new interval, and the new interval must not
  overlap another published shift of that employee.

Retry semantics mirror P1b.8. A current-version request with the identical
interval is a no-op. A retry with the original `expectedVersion`, the same
actor and the identical interval returns the current state without a second
version increment or audit entry; any other mismatch returns
`409 shift_conflict`. Only the latest amendment identity is retained.

Migration `0012_published_shift_amendment.sql` additionally closes M2 with a
PostgreSQL exclusion constraint on `(company_id, employee_id,
tstzrange(starts_at, ends_at, '[)'))` for `status='published'`, built on the
trusted `btree_gist` extension. Drafts and cancelled shifts stay outside the
constraint, and back-to-back intervals remain allowed. The application overlap
check remains for a friendly deterministic `409 shift_overlap`; SQLSTATE
`23P01` is mapped to that code only when the violated constraint is
`shifts_published_no_overlap`.

## Alternatives considered

- **Full amendment including employee and selections.** Rejected: the composite
  instance foreign key and the frozen selection trigger make it a task
  reconciliation project, not a bounded slice; the product rules for changed
  snapshots and reconciliation still do not exist.
- **Mutating `task_instances` or snapshots during amendment.** Rejected:
  rewrites supposedly immutable evidence and bypasses the execution state
  machine.
- **Deferring M2 until a later slice.** Rejected: the health check makes the
  database exclusion invariant a prerequisite of overlap-dependent amendment,
  and the amendment is exactly that.
- **Global SQLSTATE `23P01` mapping.** Rejected: a generic mapping would hide
  unrelated exclusion violations; the mapping is constraint-name specific.

## Consequences

- A wrong time window can be corrected in place before work starts; the shift
  identity, employee, selections and open instances remain.
- Task execution always reads the effective interval from the current shift
  row inside the same locked transaction; no interval is denormalized into
  instances, snapshots or receipts. A start that loses the race validates
  against the amended window.
- `btree_gist` becomes a database requirement of migration `0012`. It is a
  trusted extension available in the supported PostgreSQL 17 image and is
  installed by the migration with `CREATE EXTENSION IF NOT EXISTS` (the
  concurrency race of that statement across schema migrations is handled
  narrowly, and every other extension failure still fails the migration
  loudly).
- Existing published-shift overlap rows would make migration `0012` fail
  closed and roll back the whole run; the application has always prevented
  them.
- Cancelled shifts retain prior amendment evidence unchanged.
- No integration event is emitted; no consumer exists.
- Employee and selection amendment plus started-work reconciliation remain
  open product questions.

## Open questions

- Which shift changes (employee, selections) should be allowed once instances
  have started, and who may authorize them?
- How should a corrected republish reference a corrected shift for
  traceability?
- Which retention rule applies to amendment, cancellation and their audit
  evidence?
