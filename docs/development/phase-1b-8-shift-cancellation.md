# P1b.8: Published-shift cancellation before execution starts

Status: implemented and locally verified; independent review and remote CI pending.
Baseline: `8a58226`. Decision record: [ADR 0013](../adr/0013-published-shift-cancellation.md).

## Purpose

Close the documented P1b gap that a wrongly published shift could never be corrected.
An authorized administrator can terminally cancel a published shift while every
materialized task instance is still in the pristine `open` state. Cancellation removes
the shift and its tasks from employee-facing active views and frees the employee/time
interval for a corrected republish. Work that has already started is never reconciled
or overwritten; the cancellation is refused instead.

## Exact scope

- `published -> cancelled` shift transition with cancellation evidence.
- `open -> cancelled` instance transition for every instance of the shift.
- One authorized local transaction under the existing company advisory lock.
- Cancellation reason (1-500 characters after normalization).
- `workforce.shift.cancelled` and one `tasks.instance.cancelled` audit entry per
  instance, sharing the request correlation ID.
- Strict version-based lost-response retry.
- Employee Home exclusion; admin cancelled-state display and cancellation evidence.
- Contract, OpenAPI, migration, UI and tests.

Out of scope: editing a published shift, changing employee/interval/selections,
partial or per-task cancellation, in-flight reconciliation, draft deletion, series,
notifications, offline behavior, new RBAC capabilities, new domain events, new
modules.

## Rules

- Cancellation requires `workforce.shifts.manage` and `tasks.instances.read` and the
  configured company/location context; plugin tokens remain rejected.
- The shift must be `published` and the request `expectedVersion` must equal the
  current shift version.
- Every instance of the shift must still be `open` with no step results, no numeric
  attempts, no blocking and version 1. Otherwise the whole request fails
  `422 shift_in_progress` with zero writes.
- Cancelled shifts and task instances are terminal and immutable.
- Published instruction snapshots and template selections are never modified.
- Overlap protection still applies to `published` shifts only; a cancelled shift does
  not block a corrected republish.

The generic audit per-string value bound increased from 256 to 512 code points so the
bounded 1-500-code-point cancellation reason can be audited. The overall audit metadata
bound is unchanged, the widened bound is still hard, and other producers remain below
their own smaller field limits.

## Version and idempotency semantics

- Successful cancellation increments `shifts.version` by one and stores
  `cancellation_version = expectedVersion` (the request's original version).
- Each cancelled instance moves from version 1 to version 2.
- A retry is treated as the same committed command only when the shift is already
  `cancelled`, the request `expectedVersion` equals `cancellation_version`, the actor
  equals `cancelled_by` and the normalized reason equals `cancellation_reason`. It
  returns the current state without a version increment, task mutation or audit entry.
- A mismatching retry identity (different reason or actor with the same version), a
  stale version or a non-published state returns `409 shift_conflict`.

## API

`POST /api/v1/platform/shifts/{id}/cancel`

Request: `{"expectedVersion": <int>, "reason": <string>}`.

Response: the existing shift detail shape `{"shift": ..., "tasks": [...]}`.

Errors: `400 invalid_request`/`invalid_reason`, `401 unauthorized`, `403 forbidden`,
`404 not_found`, `409 shift_conflict`, `422 shift_in_progress` (message names the
first non-open task), `503 database_unavailable`.

## Read behavior

- Employee Home (`GET /employee-home/shifts`) filters `published` shifts only, so
  cancelled shifts disappear; direct employee reads and execution paths reject them.
- Admin list/detail keep cancelled shifts and expose status, reason, timestamp and
  actor; the existing cancelled-task list includes unstarted-cancelled instances.
- Existing blocked-origin cancellation evidence and audit shape remain unchanged.

## Local verification (2026-10-01)

Environment: Windows 11 Pro, Flutter 3.47.5 / Dart 3.13.4, PostgreSQL 17 via the
repository Compose service, isolated `*_test` database, Chrome 154 with the matching
ChromeDriver.

| Check | Result |
| --- | --- |
| `packages/api_contracts`: format, analyze, 34 contract tests | PASS |
| `apps/server`: format, analyze, 114 tests with real PostgreSQL/HTTP (includes cancellation success/refusal matrix, strict retry, authorization, overlap, concurrency and rollback injection) | PASS |
| Migration upgrade 0010 -> 0011 on populated data (published shift, pristine open task, blocked-origin cancelled task) with byte-level preservation and rejected mixed shapes | PASS |
| `packages/design_system`: format, analyze, 2 tests | PASS |
| `apps/client_flutter`: format, analyze, 115 tests, web build | PASS |
| `scripts/dev.ps1 check` with isolated `STOREOS_TEST_DATABASE` | PASS |
| `scripts/Test-DevSetup.ps1` | PASS |
| Existing numeric guided-work browser E2E unchanged | PASS |

Independent review and remote CI remain pending; no behavior or contract was verified
remotely for this slice yet.
