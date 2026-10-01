# P2: Single-site concurrent-work capacity measurement

Status: implemented, independently reviewed, committed to `main` (`8a58226`) and
verified by the remote CI run.

This slice adds an opt-in, run-scoped harness that measures the existing
single-site StoreOS stack under declared concurrent read and write workloads.
It is defined by [HANDOVER next recommended work item 3](../HANDOVER.md#next-recommended-work).
It measures the system; it does not optimize it.

## Purpose

Provide repeatable pilot-sizing evidence for one configured company/location:
how many concurrent employee sessions one Dart server and PostgreSQL instance
sustain for the bounded employee journey, with observed latency, throughput,
error counts, lock-contention samples and a full end-state integrity proof.
Results are environment-specific observations, never product requirements.

No performance number determines success or failure. A run fails only for
correctness, integrity, safety or cleanup reasons.

## Measurement contract (profiles)

`Workers` must equal `Employees`: every worker owns exactly one employee
account and that employee's tasks. `TasksPerEmployee` is bounded by the
existing shift selection limit (10).

| Parameter | Smoke | Full | Bounds |
| --- | ---: | ---: | --- |
| `Employees` | 2 | 8 | 1–16 |
| `Workers` | 2 | 8 | 1–16, equal to `Employees` |
| `TasksPerEmployee` | 2 | 3 | 1–10 |
| `ReadIterations` | 2 | 5 | 1–50 |

Per employee and run the fixture seeds exactly one published shift with
`TasksPerEmployee` tasks. Every task uses one template revision with exactly
two steps in this order:

1. `number` step: unit `C`, minimum `-2.125`, maximum `4.5`;
2. `confirmation` step.

The accepted numeric value is always the exact decimal string `1.5`
(`value_scaled = 1500`). Rejected/out-of-range attempts, blocking, resume and
cancellation are deliberately excluded from the timed workload; they are
covered by the existing unit, integration and browser tests and would require
administrative coordination inside the write path.

### Expected workload and counts

| Count | Formula | Smoke | Full |
| --- | --- | ---: | ---: |
| Shift / employee | `Employees` | 2 | 8 |
| Templates / revisions | `TasksPerEmployee` | 2 | 3 |
| Task instances | `Employees × TasksPerEmployee` | 4 | 24 |
| Completed task instances (final version 5) | same | 4 | 24 |
| Step results | `2 × task instances` | 8 | 48 |
| Numeric attempts (all in range, accepted version 3) | `task instances` | 4 | 24 |
| Command receipts | `4 × task instances` | 16 | 96 |
| `tasks.instance.started` audit entries | `task instances` | 4 | 24 |
| `tasks.step.number_recorded` audit entries | `task instances` | 4 | 24 |
| `tasks.step.confirmed` audit entries | `2 × task instances` | 8 | 48 |
| `tasks.instance.completed` audit entries | `task instances` | 4 | 24 |
| `audit.read` entries (admin audit reads) | `ReadIterations` | 2 | 5 |

Write lifecycle per task (each command with its own operation ID and expected
version): `start` (1 → 2), `record-number` (2 → 3), `confirm` (3 → 4),
`complete` (4 → 5). Every command response must report the expected status
(`in_progress` until `complete`, then `completed`), the expected version and the
own task ID.

### Read scenario mix

| Request type | Endpoint | Count per worker/admin per iteration |
| --- | --- | --- |
| `employee-home-shifts` | `GET /api/v1/platform/employee-home/shifts` | employee: 1 |
| `employee-home-running-tasks` | `GET /api/v1/platform/employee-home/running-tasks` | employee: 1 |
| `admin-shifts` | `GET /api/v1/platform/shifts` | admin: 1 |
| `admin-blocked-tasks` | `GET /api/v1/platform/blocked-tasks` | admin: 1 |
| `admin-audit` | `GET /api/v1/platform/audit` | admin: 1 |

Total read requests: `Workers × ReadIterations × 2 + ReadIterations × 3`
(smoke 14, full 95). Total write requests: `4 × task instances` (smoke 16,
full 96).

## Measurement semantics

- Timing starts after seeding and all logins. Argon2id password hashing and
  session setup are excluded from measured request latency.
- Request duration is client wall-clock time from opening the request until the
  full response body is read. It includes server queueing, authorization, the
  company advisory lock, PostgreSQL work and transfer.
- Scenario duration is wall-clock from the first worker start until all bounded
  workers have joined. Workers are joined before verification.
- Latency percentiles use the nearest-rank method over ascending sorted
  successful request durations: `rank = ceil(percent/100 × n)`, clamped to
  `[1, n]`; the `rank`-th value in milliseconds is reported. For `n = 0` the
  percentile is `null`. With an even count, `p50` is the lower middle value.
- Throughput is `successes / scenario seconds`, reported with three decimals,
  `null` for a zero-length scenario.
- Failed requests are counted by class (`http_<status>`, `malformed`,
  `transport_<type>`) and excluded from latency percentiles. Any unexpected
  status, malformed response or transport failure fails the run as a
  correctness error.
- Observed timings are reported verbatim. High latency, low throughput or lock
  contention never fail a run.

## Contention observation

A sampler using an owner connection polls every 200 ms during both scenarios:

- `pg_stat_activity` for the run database: total backends, runtime-role
  backends and runtime backends with a visible `state`. PostgreSQL may hide
  `state`/`wait_event*` for other roles; the report records whether any runtime
  state was observable.
- `pg_locks` joined with `pg_stat_activity` for the run database: granted and
  ungranted locks grouped by mode. Ungranted locks are direct evidence of lock
  waiting (including the company advisory lock).

The sampler is observational only: no new privileges, no role changes, no
`pg_monitor`, no session termination, no PostgreSQL setting changes and no
query text retention. Sampling errors are counted, never fatal.

## Report

`.local/capacity/<run-id>/report.json` (sanitized, retained) contains:
run ID, start/finish timestamps, result, failed step, declared profile,
environment metadata (OS, OS version, Dart version, PostgreSQL version,
logical processors), per-scenario request counts, successes, errors,
errors-by-class, per-request-type counts and latencies, duration, throughput,
p50/p95, contention aggregates, expected/observed integrity counts and the
integrity/cleanup verdicts plus an explicit note that timings are
environment-specific observations.

The report never contains database URLs, passwords, bearer/session/plugin
tokens, secret values, raw rows, request bodies, audit rows or SQL text.

## Safety boundaries

- The harness creates, uses and drops exactly one database named
  `storeos_capacity_<16 hex run id>`.
- Every destructive database operation requires both the strict name pattern
  and membership in the current run's owned-name set. Cleanup fails closed.
- The normal StoreOS database is only checked for existence; it is never
  migrated, seeded, read, written, restored into or dropped.
- The fixture connects only to the run-scoped database. The owner role
  migrates/bootstraps/verifies; the restricted runtime role serves the API.
- The API binds to `127.0.0.1` only.

## Local command

```powershell
# Requires the healthy Compose database and the configured .env/secrets.
./scripts/capacity/Run-CapacityMeasurement.ps1 -Profile smoke
./scripts/capacity/Run-CapacityMeasurement.ps1 -Profile full
./scripts/capacity/Run-CapacityMeasurement.ps1 -Profile full -InjectFailureAfter integrity
./scripts/capacity/Run-CapacityMeasurement.ps1 -Profile smoke -InjectFailureAfter read
./scripts/capacity/Test-CapacityReportRedaction.ps1
```

Parameters: `-Profile smoke|full` (defaults for the four profile values),
`-Workers`, `-Employees`, `-TasksPerEmployee`, `-ReadIterations` (explicit
bounded overrides), `-ApiPort` (default 8098), `-InjectFailureAfter
none|prepare|read|write|integrity`, `-DartPath`, `-DockerPath`.

`-InjectFailureAfter integrity` makes the verifier use a deliberately corrupted
expectation against the real database, so the run fails a genuine integrity
comparison. `prepare|read|write` abort the fixture after that phase to prove
failure-path cleanup.

## Cleanup and recovery

Cleanup always runs, including after injected failures: the run's capacity
database is dropped, the normal StoreOS database must still exist, the API port
must be free and fixture logs plus the private measurement file are removed.
Only `report.json` remains. If cleanup fails, the wrapper exits non-zero,
names the resource and does not escalate to broader destructive cleanup.

## Interpretation limits

- Measurements describe one local machine, OS, Docker/PostgreSQL Compose
  deployment and process-local server. They are not universal requirements,
  capacity guarantees or performance gates.
- `runAuthorized` serializes company operations behind an advisory lock,
  including reads; measured concurrency largely reflects that design. A lock or
  pool change needs its own scope, ADR and re-measurement.
- Shared CI runners are used only to prove the smoke path and integrity, never
  as representative timing evidence; CI asserts no latency or throughput
  threshold.
- The in-process Dart API (not the container image or reverse proxy) is
  measured.

## Lokaler Prüfnachweis (2026-09-30)

Environment: Windows 11 Pro (build 26200), 24 logical processors, Dart 3.13.4,
Docker 29.8.0 with the PostgreSQL 17.11 Compose service, repository `.env` and
`.local/secrets` preserved. Sanitized reports remain under
`.local/capacity/<run-id>/` and contain only aggregate measurements.

| Check | Result |
| --- | --- |
| Smoke profile (`bce3eebb0c8548cc`) | PASS |
| Full profile run 1 (`eb17283a3fcd4d93`) | PASS |
| Full profile run 2 (`0fb83227327047b5`) | PASS |
| Injected integrity mismatch (`94f19bc55c1a4ed4`) | expected exit 1; integrity fail (`task_instances: observed 4, expected 5`); cleanup PASS |
| Injected operational failure after `prepare` (`864a2febe4524a6d`) | expected exit 1; cleanup PASS |
| Real-PostgreSQL smoke integration test | PASS |
| `scripts/capacity/Test-CapacityReportRedaction.ps1` | PASS |

Both full runs used the identical declared profile (8 employees/workers,
3 tasks per employee, 5 read iterations) and passed all integrity checks
(24 tasks completed at version 5, 48 step results, 24 accepted numeric
attempts, 96 receipts, matching audit deltas). Timings are recorded verbatim
and differ between runs as expected:

| Measurement | Full run 1 | Full run 2 |
| --- | ---: | ---: |
| Read requests / errors | 95 / 0 | 95 / 0 |
| Read duration / throughput | 2078 ms / 45.696 rps | 2093 ms / 45.375 rps |
| Read p50 / p95 | 170.891 / 347.974 ms | 179.994 / 325.213 ms |
| Write requests / errors | 96 / 0 | 96 / 0 |
| Write duration / throughput | 4608 ms / 20.830 rps | 4643 ms / 20.676 rps |
| Write p50 / p95 | 376.583 / 464.891 ms | 364.028 / 484.202 ms |
| Contention samples / max ungranted locks | 33 / 7 (`ExclusiveLock`) | 33 / 7 (`ExclusiveLock`) |

All runs removed their capacity database, kept the normal `storeos` database
present, freed the API port and retained only `report.json`. No
`storeos_capacity_*` database and no fixture process or listener remained
afterwards.

Remote CI status: the remote run on `8a58226` passed, including the capacity
report redaction check. Independent review completed before the commit.
