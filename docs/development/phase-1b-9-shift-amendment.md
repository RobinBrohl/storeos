# P1b.9: Pre-execution published-shift interval amendment

Status (2026-10-02): implemented and verified locally (contracts, real
PostgreSQL, real HTTP and Flutter suites); independent review and remote CI
pending. Baseline at implementation start: `9aef373`. Decision record:
[ADR 0014](../adr/0014-pre-execution-shift-interval-amendment.md).

## Goal

An authorized administrator can change only the `startsAt`/`endsAt` interval of
an already published shift while every materialized task instance is still
pristine `open`. The shift keeps its identity, employee, template selections,
publication evidence and open task instances; the change, its last-amendment
evidence and its audit entry commit atomically. The same migration adds the
database exclusion constraint for published-shift overlap that the 2026-10-02
health check required as finding M2.

## Exact scope

- New route `POST /api/v1/platform/shifts/<id>/amend` with exactly
  `expectedVersion`, `startsAt`, `endsAt`.
- New migration `0012_published_shift_amendment.sql`: amendment evidence
  columns, extended shift state CHECK, extended published-shift protection
  trigger, `btree_gist` requirement and the published-interval exclusion
  constraint.
- Minimal runtime grant for the three new evidence columns.
- Strict current-window no-op and last-amendment retry semantics.
- Audit `workforce.shift.amended`, Flutter dialog and tests.

Out of scope: employee/location/selection changes, task-instance or snapshot
rewrites, started/blocked/completed reconciliation, series/recurrence, M1,
global M3/M4 cleanup, other findings, company-lock narrowing, offline support,
new acceptance harnesses and browser E2E.

## Authorization

The route requires `workforce.shifts.manage` and `tasks.instances.read`, the
same pair as publish/cancel. Authorization is re-checked server-side under the
company advisory lock; the configured location must match the shift's location.
Plugin tokens remain rejected by session authentication. The route accepts no
employee, selection or task identifier.

## API contract

`POST /api/v1/platform/shifts/<id>/amend`, `application/json`, Bearer session:

| Status | Code | Semantics |
| --- | --- | --- |
| 200 | – | Amended (or current-window no-op / exact retry) returning `ShiftDetail` |
| 400 | `invalid_request`, `invalid_shift`, `invalid_json` | Field/version/type errors and invalid windows |
| 401 | `unauthorized` | Missing, revoked or expired session |
| 403 | `forbidden` | Company mismatch or missing capability |
| 404 | `not_found` | Unknown or foreign shift, unconfigured location |
| 409 | `shift_conflict`, `shift_overlap` | Stale/draft/cancelled/mismatching retry; overlapping published interval |
| 413/415 | `body_too_large`, `unsupported_media_type` | Shared body preconditions |
| 422 | `shift_in_progress`, `shift_not_amendable`, `employee_unavailable` | Not all instances pristine; end not after the DB clock; employee not eligible for the new interval |
| 500 | `internal_error` | Unexpected server error |
| 503 | `database_unavailable` | Infrastructure failure, zero writes |

## Transaction and gate order

One `runAuthorized` transaction under the company advisory lock:

1. parse/validate the request;
2. company/location-scoped shift read (404);
3. exact last-amendment retry short-circuit;
4. `requireAmendable` (published + `expectedVersion`);
5. current-version identical-interval no-op;
6. pristine `open` v1 gate for every instance (`422 shift_in_progress`);
7. one `clock_timestamp()` read; `endsAt > now` (`422 shift_not_amendable`);
8. employee eligibility for the new interval (`422 employee_unavailable`);
9. application overlap check excluding self (`409 shift_overlap`);
10. version-guarded published-only UPDATE with `amendment_version =
    expectedVersion`;
11. audit;
12. commit.

No second transaction, no check-then-write gap, no task-instance mutation.

## Idempotency semantics

- `amendment_version` stores the pre-amendment `expectedVersion`; the three
  evidence columns are all NULL or all set and are overwritten together.
- A request with the current version and the identical interval is a no-op
  (200, no version increment, no audit).
- A retry with the original version, same actor and identical interval returns
  the current state without new effects.
- Any other stale or mismatching request returns `409 shift_conflict`; earlier
  amendment identities remain only in the append-only audit.

## Database invariant (M2)

Migration `0012` adds:

```
EXCLUDE USING gist (
  company_id WITH =, employee_id WITH =,
  tstzrange(starts_at, ends_at, '[)') WITH &&
) WHERE (status='published')
```

using the trusted `btree_gist` extension. Back-to-back intervals are allowed,
drafts and cancelled shifts are outside the invariant, and pre-existing
overlapping published rows make the migration fail closed with the ledger and
schema unchanged. SQLSTATE `23P01` is mapped to `409 shift_overlap` only when
the violated constraint is `shifts_published_no_overlap`; every other
exclusion or integrity failure keeps its normal error behavior.

The replaced `protect_published_shift` trigger preserves every 0011 rule:
published→cancelled keeps the exact cancellation whitelist, cancelled stays
terminal, deletes stay refused, drafts keep their paths, and a
published→published update is allowed only when at least one bound changes,
`version = old version + 1`, `amendment_version = old version`, actor and
timestamp are set, and every other column - including employee, location,
publication and cancellation evidence - is unchanged.

## Audit, events and secret safety

- `workforce.shift.amended` records the old/new interval, employee context,
  version, `amendmentVersion` and `changedFields`; no snapshots, no secrets.
- No audit for no-op, retry, validation, overlap, started-work or failed
  transactions; an injected audit failure rolls back the whole amendment.
- No domain/outbox event is emitted; workforce remains a documented
  non-emitter.

## Flutter behavior

The published-shift card offers "Zeiten ändern" only while the client-visible
state indicates an attempt is possible (`workforce.shifts.manage`, published,
all tasks open). The dialog asks for UTC start/end, validates ordering, instants
and at least one changed bound locally; an unchanged window never reaches the
API. It disables submission while busy and keeps static validation inline.
Success refreshes the detail and shows the amended interval. A `409` keeps the
recoverable conflict state with explicit reload; `422 shift_in_progress`
explains that work has started and requires the server state to be reloaded
explicitly; `422 shift_not_amendable`/`employee_unavailable` show static
messages. The client gate is UX only; the server remains authoritative.

## Verification (local, 2026-10-02)

- `packages/api_contracts`: 49 tests passed, including amendment input,
  `ShiftDto` all-or-none evidence and OpenAPI containment.
- `apps/server`: 146 tests passed against an isolated PostgreSQL test database,
  including the amendment success/refusal matrix, no-op/retry, overlaps,
  raw-writer constraint and trigger refusal, runtime grants, races, audit
  rollback, populated 0011→0012 upgrade, fail-closed pre-existing overlap and
  the HTTP smoke matrix.
- `apps/client_flutter`: 136 tests passed, including controller, dialog and
  widget coverage for the amendment flows.
- The existing controlled update/recovery acceptance passed on the extended
  `0010→0012` chain: exactly `0011` and `0012` applied once, amendment columns
  and `shifts_published_no_overlap` present, raw overlapping published interval
  rejected, real HTTP interval amendment on the upgraded server and isolated
  recovery fencing intact (`scripts/update/Run-UpdateRecoveryAcceptance.ps1`,
  sanitized report under `.local/update-recovery/`).
- `dart format --set-exit-if-changed`, `dart analyze`/`flutter analyze` clean in
  the touched packages.
- Independent review and remote CI are not yet performed.

## Boundaries and debt

M1, the global M3/M4 cleanup, L1-L9 and L11/L12, fixture duplication,
company-lock granularity, offline behavior and retention/export remain
deferred. M2 is now also enforced at the database level. Employee and selection
amendment plus started-work reconciliation remain open product questions, and
`btree_gist` is a new operational prerequisite of migration `0012`.
