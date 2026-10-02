# Milestone health check 2026-10-02

Status: milestone health check completed locally; independent review performed
(returned CHANGES REQUIRED for report-text precision), corrections applied, and a
targeted confirmation review performed which found two remaining report-text
defects (a duplicated M3/M4 debt row and an uncorrected L4 sentence in section
14). Both were corrected in this revision; final confirmation is pending. This
report claims no APPROVE and no remote CI verification for itself.

This is a cross-cutting architecture, correctness, security and pilot-readiness
review. It is not a feature implementation cycle and it fixed no finding.
Production code, tests, scripts, CI, migrations, configuration, dependencies and
lockfiles were not modified during the review.

## 1. Baseline

| Item | Value |
| --- | --- |
| Branch | `main` (StoreOS develops on main only) |
| HEAD | `512ac64544daa4e12bb5dae54ffc996b9c705537` "Add update recovery acceptance" (2026-10-01 22:46:02 +0200) |
| origin/main | identical to HEAD at review start |
| Working tree | clean at review start and throughout evidence collection; no stash; single worktree |
| Migrations | append-only chain ends at `apps/server/migrations/0011_published_shift_cancellation.sql` |
| Reviewed slice chain | `898c2a1` durable E2E/receipt replay, `b94c8e0` task-aware backup/restore, `8a58226` capacity measurement, `19151f6` P1b.8 published-shift cancellation, `512ac64` update/recovery acceptance |
| CI jobs present | `dart`, `flutter`, `numeric-guided-work-e2e`, `backup-restore-acceptance`, `update-recovery-acceptance` (`.github/workflows/ci.yml:11-246`) |
| Review date | 2026-10-02 |

Operator-provided evidence accepted for this cycle (not independently
re-verifiable locally because `gh` is not installed on the review machine):
independent Kimi K3 review of the update/recovery slice with APPROVE, commit
`512ac64`, remote CI green for `512ac64`.

## 2. Review method

1. Baseline verification and freeze (`git status`, `rev-parse`, `stash list`,
   `worktree list`, migration chain, CI job existence) before any read.
2. Source-of-truth documents read first: `AGENTS.md`, `docs/HANDOVER.md`,
   `docs/roadmap/status.md`, `docs/roadmap/phases.md`,
   `docs/risks-and-open-questions.md`, `docs/architecture/module-boundaries.md`,
   `docs/architecture/deployment.md`, `docs/architecture/event-system.md`,
   `docs/development/workflow.md`, `docs/development/phase-2-*-acceptance` and
   capacity documents, ADRs 0011-0013.
3. Repository code, migrations and tests treated as authoritative where they
   conflict with prose. Evidence gathered by exhaustive greps and full reads of
   the server library (`apps/server/lib/src`, 51 files), migrations 0001-0011,
   the migration runner, HTTP layer, contracts package, Flutter client, test
   suites, tool fixtures, acceptance scripts and the CI workflow. Every claim
   below carries exact `file:line` evidence from the frozen baseline.
4. Documentation drift captured as committed evidence before any edit
   (section 3); corrections applied only after evidence collection completed.
5. Absence claims state the search method (grep pattern plus scope).

## 3. Documentation drift captured (committed state at 512ac64)

The following stale statements existed in the committed baseline and are
corrected by this cycle (section 30). They are recorded here as review evidence.

| File:line (at 512ac64) | Stale statement | Reality per operator evidence |
| --- | --- | --- |
| `docs/HANDOVER.md:3` | "Baseline: `19151f6`, status updated 2026-10-01." | Baseline is `512ac64` |
| `docs/HANDOVER.md:69-72` | "a locally verified controlled update/recovery acceptance" | Independently reviewed (APPROVE), committed as `512ac64`, remote CI verified |
| `docs/roadmap/status.md:3` | "Assessment baseline: `19151f6` (2026-10-01; includes P1b.8)." | Baseline is `512ac64` |
| `docs/roadmap/status.md:31` | "a locally verified controlled update/recovery acceptance" | Remotely verified |
| `docs/roadmap/status.md:32` | Update/recovery row under "Partially implemented / active": "independent review and remote CI pending" | Independently reviewed APPROVE; remote CI passed; belongs in the DONE table |
| `docs/development/phase-2-update-recovery-acceptance.md:3-5` | "independent review and remote CI pending" | Independently reviewed (APPROVE), committed as `512ac64`, remote CI verified |
| `docs/development/phase-2-update-recovery-acceptance.md:245` | Criterion 23: "the CI job exists; remote CI is unverified until pushed." | Remote CI job `update-recovery-acceptance` passed |
| `docs/development/phase-2-update-recovery-acceptance.md:257` | "Local Windows evidence plus a CI job; remote CI is unverified until pushed." | Remote CI verified |

Checked and not stale: `docs/README.md`, `docs/architecture/deployment.md`
(line 16 already describes the accepted 0010->0011 update/recovery contract),
`docs/roadmap/phases.md`. These were left unmodified.

## 4. Module ownership map and dependency direction

Implemented logical modules under `apps/server/lib/src/` (composition root
`apps/server`):

| Module | Directory | Owns (writes) | Public surface used by others |
| --- | --- | --- | --- |
| Platform | `platform/` | Transaction boundary + RBAC (`platform_database.dart`), audit (`audit_repository.dart`, `audit_service.dart`), events/outbox (`event_repository.dart`, `event_service.dart`, `event_bus.dart`), plugins (`plugin_repository.dart`, `plugin_service.dart`), identity/org application services | `runAuthorized`, `audit(tx,...)`, `publishOrganizationEvent(tx,...)` |
| Organization | `organization/` | companies, locations | `OrganizationService` (incl. `requireConfiguredLocation`), `OrganizationRepository` (intended private) |
| Identity | `identity/` | accounts, sessions data, employee-account links | `IdentityRepository`, `EmployeeLinks` port |
| People | `people/` | employee profiles, site validity | `PeopleService`, `EmployeeRepository` (intended private) |
| Workforce | `workforce/` | shifts, selections | `WorkforceService` port; `ShiftRepository` (intended private) |
| Tasks | `tasks/` | templates/revisions, instances, execution, receipts, attempts | `TaskTemplateService`, `TaskInstanceService`, `TaskExecutionService` ports |
| Application coordinators | `application/` | none (coordination only) | `ShiftApplication`, `EmployeeApplication`, correlation zone |
| Infrastructure | `infrastructure/` | auth store, bootstrap, migrations | `PostgresAuthStore`, `BootstrapService`, `MigrationRunner` |
| HTTP | `http/` | none | routes delegating to services/coordinators |
| Contracts | `packages/api_contracts` | none | shared DTOs/validation used by server and Flutter client |
| Flutter client | `apps/client_flutter/lib/src/{ui,application,data}` | none | controllers call data-layer APIs only |

Dependency-direction result: coordination flows exclusively through module ports
inside one `runAuthorized` transaction (e.g. `shift_application.dart:36` wrapper;
`task_instance_service.dart:7` "Tasks owns selection validation and snapshots; no
workforce table access"; `workforce_service.dart:9`). Routes contain no business
decisions; widgets contain no server-owned rules (section 22). Two documented
exceptions bypass a public port (finding L1):

- `PluginService` constructs and uses the foreign `OrganizationRepository`
  directly: `apps/server/lib/src/platform/plugin_service.dart:9` (import),
  `:24-25` (construction), `:144` (location validation in `approve`),
  `:240-244` (plugin projection). Documented as known debt in
  `docs/HANDOVER.md:229-230`; permitted as an accepted P1 shortcut, must not be
  extended to business modules.
- `IdentityService` uses the same pattern: `identity_service.dart:4` (import),
  `:11` (`organization = OrganizationRepository(database)`), `:61`
  (`organization.location(tx, locationId)` in `createUser`). This instance is
  not listed in the HANDOVER debt entry (part of finding L1).

No module writes a foreign table; no cycles; no HTTP/Flutter dependency inside
domain code. The intentional coordinator dependencies described in
`docs/architecture/module-boundaries.md:5,71-81` are not defects.

## 5. Direct SQL inventory

Method: grep for `Sql.named`, `tx.execute`, `pool.execute`, SQL keywords,
`clock_timestamp`, `pg_*`, `information_schema` across all 51 files in
`apps/server/lib`. Files containing SQL: the 12 `*_repository.dart` files, the
3 `infrastructure/` files, `platform_database.dart`, `shift_application.dart`,
`workforce_service.dart`. No SQL in `http/`, `config.dart`, models or `bin/`.

| # | Location | Statement | Classification |
| --- | --- | --- | --- |
| S1 | `platform_database.dart:105-108` | `SELECT pg_advisory_xact_lock(hashtext(@key))` | JUSTIFIED EXCEPTION - the lock is the transaction-boundary mechanism itself |
| S2 | `platform_database.dart:109-116` | account re-read (`SELECT id::text, role, is_active ... FROM accounts`) | JUSTIFIED EXCEPTION (mild debt: overlaps `IdentityRepository.user`) |
| S3 | `platform_database.dart:137-144` | session liveness re-check (`expires_at > clock_timestamp()`) | JUSTIFIED EXCEPTION (mild debt: overlaps `PostgresAuthStore.findSession`) |
| S4 | `shift_application.dart:98` | `(await tx.execute('SELECT clock_timestamp()')).single.first as DateTime` (self employee-window check) | BOUNDARY DEBT (finding L2) |
| S5 | `shift_application.dart:236` | same pattern (cancellation timestamp) | BOUNDARY DEBT (L2) |
| S6 | `shift_application.dart:482` | same pattern (execution timestamps/validation) | BOUNDARY DEBT (L2) |
| S7 | `shift_application.dart:499` | same pattern (resume eligibility re-check) | BOUNDARY DEBT (L2) |
| S8 | `workforce_service.dart:89` | same pattern (publishability `now`) | BOUNDARY DEBT (L2) |

Verdict on the planned question: the raw `SELECT clock_timestamp()` occurrences
are real (5 sites). They are **not** persistence leakage of business queries -
each obtains the transaction-consistent PostgreSQL clock so boundary decisions
and stored timestamps share one time source, immune to app-host clock skew.
They are nonetheless raw SQL strings in the application/port layer; a
`txNow(tx)`-style port would remove them. Functionally correct; classified
LOW boundary debt (L2), not a bug. All repositories use parameterized
`Sql.named` with company scoping (EXPECTED). `event_repository.dart:222`
(`recordFailure`) deliberately runs outside the failed dispatch transaction
(EXPECTED for a repository; keeps failure bookkeeping after rollback).

## 6. Transaction model

All production transactions use `pool.runTx`/`connection.runTx` from package
`postgres`; no manual `BEGIN`/`COMMIT` anywhere in `lib` (grep). Nine entry
points exist:

| # | Entry point | file:line | Lock inside | Purpose |
| --- | --- | --- | --- | --- |
| T1 | `PlatformDatabase.runAuthorized` | `platform_database.dart:102` | company advisory lock `:105-108` | Every session-principal use case: company check `:98-100`, correlation zone `:101`, account/session/role re-read under lock `:109-156`, action inside the same tx `:157-165` |
| T2 | `createSession` (login) | `auth_store.dart:131` | company lock `:132-135` | Session insert + `auth.login` audit atomically; password/active re-verified under lock `:136-149` |
| T3 | `revokeSession` (logout) | `auth_store.dart:205` | company lock `:220-223` | Revocation + `auth.logout` audit |
| T4 | `MigrationRunner.apply` | `migration_runner.dart:35` | migrations lock `:36-39` | All pending migrations + ledger + grants in one tx |
| T5 | `BootstrapService.bootstrap` | `bootstrap_service.dart:48` | bootstrap lock `:49-52` | One-time admin creation + `platform.bootstrapped` audit |
| T6 | `EventBus.dispatchOnce` | `event_bus.dart:62` | none; `FOR UPDATE SKIP LOCKED` claim (`event_repository.dart:172`) | Outbox claim -> inbox fan-out -> receipt -> markDispatched atomically |
| T7 | plugin `organization(token)` | `plugin_service.dart:238` | company lock via `lockCompany` (`plugin_repository.dart:16-23`, called `plugin_service.dart:307`) | Plugin-token org projection read |
| T8 | plugin `events(token)` | `plugin_service.dart:249` | company lock | Plugin inbox page read |
| T9 | plugin `acknowledge(token)` | `plugin_service.dart:264` | company lock + `FOR UPDATE OF i` (`plugin_repository.dart:268`) | Inbox ack |

`runAuthorized` call sites (28 invocations, 8 files): `shift_application.dart:36`
(one wrapper covering all 13 shift/execution use cases: create `:144`, edit
`:179`, publish `:195`, cancel `:232`, get `:281`, running `:300`, execution
`:314`, blocked `:339`, blockings `:374`, numbers `:404`, execute `:465`, list
`:543`); `employee_application.dart` (`:20,32,40,72,100,133,160,192,217`);
`organization_service.dart` (`:22,57,141,199,259` - the only outbox writer);
`identity_service.dart` (`:19,32,57,120,178`); `plugin_service.dart`
(`:33,60,109,202`); `audit_service.dart:16`; `event_service.dart:28,52`;
`task_template_service.dart:23` (wrapper covering 8 use cases).

Properties verified per entry point: audit writes happen inside the same
transaction (`platform_database.dart:170-187` -> `audit_repository.dart:71-91`);
version guards are SQL predicates (`WHERE version=@version`, e.g.
`shift_repository.dart:132-146,167-181,190-206`; `identity_repository.dart:100-149`;
`employee_repository.dart:63-80`; `task_execution_repository.dart:136-150`);
external side effects do not occur inside transactions (no network calls in any
`runTx` body; the event dispatcher is a separate loop). **No mutation path was
found that executes outside this transaction model.** The only non-transactional
pool statements are read probes and the deliberate autonomous
`recordFailure` (`auth_store.dart:77,81,96,178`; `event_repository.dart:222`).

## 7. Advisory locks / concurrency

Every advisory lock is `pg_advisory_xact_lock(hashtext(<string key>))` -
transaction-scoped, auto-released at commit/rollback (grep `pg_advisory` across
`apps/server`; no session-scoped `pg_advisory_lock`, no `pg_try_advisory_*`, no
advisory locks in migrations):

| # | file:line | Key | Scope | Protected invariant |
| --- | --- | --- | --- | --- |
| L1 | `platform_database.dart:105-108` | `storeos_platform:<schema>:<companyId>` | company | Serializes all authorized writes; protects the last-admin invariant and every check-then-act guard (comment `:103-104`; rights re-read after acquisition `:109-156`) |
| L2 | `plugin_repository.dart:16-23` (`lockCompany`, called `plugin_service.dart:307`) | identical company key | company | Plugin-token reads/acks serialize against admin approve/disable ("Read the token only after that lock to avoid stale approval races", `plugin_service.dart:305-306`) |
| L3 | `auth_store.dart:132-135` | identical company key | company | Login session creation serialized with account mutation; password/active re-verified under lock |
| L4 | `auth_store.dart:220-223` | identical company key (from the session owner's account row `:206-219`) | company | Logout revocation + audit under the same lock |
| L5 | `migration_runner.dart:36-39` | `storeos_migrations:<schema>` | global | Serializes concurrent migration runs |
| L6 | `bootstrap_service.dart:49-52` | `storeos_bootstrap:<schema>` | global | Serializes one-time bootstrap; emptiness checks under lock `:53-61` |

Deadlock analysis: one lock domain per scope; no transaction acquires more than
one advisory lock, so no conflicting advisory-lock ordering was found and
advisory-lock ordering conflicts are impossible. Mutation/critical check-and-act
work proceeds under the company advisory lock; the one transaction that performs
a plain, row-lock-free read before taking its lock (`revokeSession`, owner SELECT
`auth_store.dart:206-216`, company lock `:220-223`) cannot participate in a
lock-order inversion. Row-level locks (`FOR UPDATE` in
`plugin_repository.dart:89,268`, `event_repository.dart:142,172`) are always
acquired after the single advisory lock (or in the lock-free dispatcher T6,
which uses `SKIP LOCKED` and single-row claims), so no lock-order inversion
exists. Supplementary row locks: `plugin_repository.dart:314` `FOR SHARE`.

Company-wide `runAuthorized` serialization (known debt A):

- Correctness properties it currently protects: the last-admin invariant
  (`identity_service.dart:132-141` counts active admins inside the tx); all
  check-then-act patterns without DDL backing - shift overlap detection
  (`workforce_service.dart:91-97`), publication preconditions, cancellation
  precondition scan (`task_instance_service.dart:87-96`), receipt-replay
  identity (`task_execution_service.dart:116-131`), creation-retry comparisons
  (`workforce_service.dart:38-53`); immediate effect of role/account/session
  revocation (re-read under lock, `platform_database.dart:109-156`).
- Capacity evidence: the bounded full-profile measurement (8 concurrent
  employee workers + admin, 96 writes + 95 reads, `docs/development/phase-2-capacity-measurement.md:28-83`)
  completed with integrity proof and contention sampling; results are
  environment-specific observations, not guarantees
  (`phase-2-capacity-measurement.md:17,104-105,178-180`; `docs/HANDOVER.md:225-228`).
- What would have to be re-proven before narrowing the lock: last-admin atomicity,
  authorization/revocation immediacy, overlap protection (see M2 - it would need
  a DDL exclusion constraint first), publication/cancellation/receipt race
  behavior, and a capacity measurement on target hardware
  (`docs/HANDOVER.md:225-228` requires exactly this).
- Does it block a bounded single-site pilot? **No.** It does not block the next
  feature either. Relaxing it for theoretical scalability is explicitly not
  recommended.

## 8. Task state machine

States (final DDL `0011_published_shift_cancellation.sql:57`; DTO
`packages/api_contracts/lib/src/task_execution.dart:83-101`; domain
`apps/server/lib/src/tasks/task_execution.dart:31-34`): `open`, `in_progress`,
`blocked`, `completed`, `cancelled`. State-shape CHECK `task_execution_times`
(`0011:58-68`): `open` => version=1 and no evidence; `in_progress`/`blocked` =>
version>=2, started set; unstarted-cancelled => version=2 exactly with
`cancelled_at/by` set; blocked-origin cancelled => version>=4, started set,
instance `cancelled_at/by` NULL (evidence on the blocking row); `completed` =>
version>=3 and `completed_at>=started_at`.

Version semantics: one aggregate counter `task_instances.version` (+1 per
command, trigger-enforced `0011:78`; guarded UPDATE
`task_execution_repository.dart:136-150` with `StateError` on
`affectedRows != 1`). `expectedVersion` is the pre-command version; evidence rows
(`accepted_version`, `reported_version`, `resolved_version`) store the
post-command version. No second counter exists, so drift is impossible.

Transition table (all writes serialized by the company lock; all execution
commands carry `operationId` receipts in `task_execution_commands`,
`0007:24-31`, replay compared on company+actor+instance+canonical input JSON,
`task_execution_service.dart:109-131`, mismatch => 409 `operation_conflict`):

| # | Transition | Actor/command (permission) | Required old state/version | Result (version) | DB enforcement | Application guard | Audit action |
| --- | --- | --- | --- | --- | --- | --- | --- |
| T0 | materialization | admin publish shift (`workforce.shifts.manage` + `tasks.instances.read`, `shift_application.dart:195-196`) | shift draft; instance absent | `open`, v1 | content snapshot + uniqueness (`0006:29-41`; `0010:32-33`) | pinned published revision, same location (`task_instance_service.dart:15-38`) | `tasks.instance.created` (`task_instance_service.dart:61-75`) |
| T1 | start | employee (`tasks.instances.self.execute`) | `open`, v1, shift window `startsAt <= now < endsAt` | `in_progress`, v2 | trigger branch `0011:82-83`; start fields immutable `0011:88-89` | `task_execution.dart:30-32`; 422 `outside_shift` (`task_execution_service.dart:154-159`); self-visibility (`shift_application.dart:255-270`) | `tasks.instance.started` (`task_execution_service.dart:243-250`) |
| T2 | confirm step | employee | `in_progress`; stepId = next snapshot step of type `confirmation` | v+1, step result at position n | `0007:17-23`, `0008:56-64`; trigger `0011:96-97` | order/type check 422 `invalid_execution` (`task_execution.dart:36-42`; `task_execution_service.dart:148-153`) | `tasks.step.confirmed` |
| T3 | record-number in range | employee | `in_progress`; next step type `number` | v+1 via internal rewrite to `confirm` (`task_execution_service.dart:184`) | attempt DDL `0010:35-101` (see section 9) | value canonicalized at HTTP boundary (`shift_application.dart:438-449`); `acceptsNumber` (`task_execution.dart:14-15`) | `tasks.step.number_recorded` (raw value never audited, `task_execution_service.dart:186-201`) + `tasks.step.confirmed` |
| T4 | record-number out of range | employee | same as T3 | `blocked`, v+1 via rewrite to `block` with fixed reason (`task_execution_service.dart:184-185`) | attempt + blocking linkage `0010:45,70-82` | same as T3 | `tasks.step.number_recorded` (inRange:false) + `tasks.instance.blocked` |
| T5 | block | employee | `in_progress` (any time, also after all steps) | `blocked`, v+1 | `0009:24-29`; one open blocking per instance (`0008:31`); trigger `0011:90-91` | reason 1..500 runes normalized (`api_contracts task_execution.dart:194-205`); stepId derived server-side (`task_execution_service.dart:206-208`) | `tasks.instance.blocked` (no reason in audit) |
| T6 | resume | admin (`tasks.instances.resolve`) | `blocked` | `in_progress`, v+1 | `0009:30-35`; trigger `0011:92-93`; column-scoped runtime grants (`migration_runner.dart:188-198,217-221`) | `checkResume`: employee still active/assigned now, else 422 `employee_unavailable` (`shift_application.dart:496-512`); location scope `:325-330` | `tasks.instance.resumed` |
| T7 | cancel blocked task | admin (`tasks.instances.cancel`) | `blocked` only - from any other state 409 (`task_execution.dart:26-28`) | `cancelled`, v+1 (>=4) | `0011:65-66,86-87,94-95`; exactly one cancellation blocking (`0009:9`) | reason validated as T5; deliberately no employee-link requirement (`task_cancellation_integration_cases.dart:358-416`) | `tasks.instance.cancelled` (with `blockingId`, no reason) |
| T8 | pre-execution cancellation via shift cancellation | admin (`workforce.shifts.manage` + `tasks.instances.read`, `shift_application.dart:232-233`) | shift `published` and every task `open` at v1, else 422 `shift_in_progress` with zero writes (`task_instance_service.dart:87-96`) | `cancelled`, v1->exactly 2 | trigger `0011:84`; CHECK `0011:63-64` | per-task guard `WHERE status='open' AND version=1`, `affectedRows!=1` => 409 (`task_instance_repository.dart:43-55`) | `tasks.instance.cancelled` (with `origin:'shift_cancellation'`, `reason`) |

Terminal/forbidden: no re-open, no exit from `completed`/`cancelled`, no DELETE
(`0011:75-79`); step results and numeric attempts are insert-only (`0008:59`,
`0010:50`); blocking evidence is insert-only apart from exactly one controlled
resolution UPDATE (`0009:22` refuses DELETE; `0009:30-35` permits one
resolution); execution receipts are immutable at runtime-role grant level only,
without an all-role trigger (`migration_runner.dart:177-183`; finding L12);
`blocked->completed` is not representable anywhere (no trigger branch
`0011:90-100`; must resume first, `task_blocking_integration_cases.dart:37-48`).

DB-vs-code deltas (all benign, recorded for precision):
`open->cancelled` is DB-representable but has no task-level HTTP command -
reachable only via T8; resume is DB-unconditional but code-conditional on
current employee validity; the 0007 strict `version==n+3` completion equality
was deliberately relaxed in 0008 to `>=` (DTO uses the matching lower bound,
`api_contracts task_execution.dart:137-141`); the shift start-window rule is
code-only (continuation after shift end intentionally allowed,
`task_execution_test.dart:105-127`). One asymmetry is deliberate legacy
compatibility: `TaskStepResultDto.acceptedVersion` is nullable for pre-0008
receipt JSON replayed verbatim (upgrade tests
`task_blocking_integration_cases.dart:536-659`), while the DB column is NOT NULL
since `0008:13`. The same audit action `tasks.instance.cancelled` carries two
payload shapes (blocked-origin vs shift-origin); consumers branch on
`changes.origin` (tests: `task_cancellation_integration_cases.dart:102-110`;
`shift_cancellation_integration_cases.dart:153-169`).

## 9. Numeric execution invariants

- Exact thousandths scaling, never floating point: wire format decimal string
  regex `^-?[0-9]{1,6}(\.[0-9]{1,3})?$` (`api_contracts task_numbers.dart:3-15`);
  canonicalization at the HTTP boundary (`shift_application.dart:438-449`,
  400 `invalid_number`); storage as scaled int
  `task_numeric_attempts.value_scaled integer CHECK(BETWEEN -999999999 AND 999999999)`
  (`0010:37`; write `task_execution_repository.dart:301-323`).
- Min/max inclusive on both ends, checked twice: application
  `acceptsNumber` (`task_execution.dart:14-15`; boundary unit proofs -2.125/4.5
  accepted, -2.126/4.501 rejected, `task_execution_test.dart:29-32`); database
  independently recomputes `value_scaled BETWEEN minimum*1000 AND maximum*1000`
  and raises on disagreement (`0010:58-59`). Template authoring enforces
  `minimum<=maximum` (`api_contracts task_templates.dart:101-119`; `0010:10-18`).
- Every attempt persists first, then the command is rewritten to `confirm`
  (in-range) or `block` (out-of-range) (`task_execution_service.dart:170-185`).
  Polarity is DDL-enforced: a number-step result must reference an attempt and
  `attempt.in_range` must equal "is a step result" (`0010:70-82`).
- Attempt history immutable: `numeric_attempt_immutable` trigger refuses any
  non-INSERT (`0010:47-63`); INSERT validated under `FOR UPDATE` against
  instance state, step order and `accepted_version=task.version+1`
  (`0010:51-57`); runtime role has SELECT+INSERT only
  (`migration_runner.dart:199-206`); direct-SQL abuse proofs
  (`task_numeric_integration_cases.dart:462-503`).
- Linkage: `UNIQUE(instance_id, accepted_version)` and `CHECK(accepted_version>=3)`
  (`0010:39,41`); cross-checks on company/location/step/actor/timestamp
  (`0010:76-82`); deferred commit-time trigger `numeric_outcome` prevents
  committing an attempt without its outcome at the accepted version
  (`0010:91-101`).
- Receipts/retries: receipt identity uses the canonicalized value
  (`'04.500'` == `'4.5'`, `task_numeric_integration_cases.dart:344-367`);
  tampered value under the same operationId => 409 (`:196-202`); exactly one
  attempt row per accepted command; receipt result bounded 8192 bytes (`0007:28`).
- Audit: `tasks.step.number_recorded` records
  `{operationId, attemptId, stepId, revisionId, version, inRange}` - the raw
  value is deliberately absent (allow-list `audit_repository.dart:28-62`;
  assertion `task_numeric_integration_cases.dart:276-279`).
- Rollback atomicity proven by revoking INSERT on attempts/results/blockings/
  audit/receipts: 503 with version stuck and zero partial evidence
  (`task_numeric_integration_cases.dart:505-574`).

Conclusion: no path was found on which numeric evidence can become inconsistent
after replay, concurrency or cancellation. Cancellation preserves attempts and
outcomes untouched (51 out-of-range attempts survive blocked-origin cancellation,
`task_numeric_integration_cases.dart:390-460`). Residual note (by design):
numeric evidence lives only in `task_numeric_attempts` because audit omits raw
values.

## 10. Shift state machine

States (DDL `0011:17-25`): `draft`, `published`, `cancelled`. State-shape CHECK
couples evidence: draft has none; published has full publication evidence
(`published_at/by`, `publication_version>0`); cancelled requires **both** full
publication and cancellation evidence (`cancelled_at/by`, `cancellation_reason`
1-500 chars, `cancellation_version>0`) - a draft can never become cancelled and
a cancelled shift always retains its publication record.

| Transition | Mechanism | Idempotency/retry | Evidence |
| --- | --- | --- | --- |
| (none) -> draft | `POST /shifts` with client-supplied UUID | creation retry: same id must match `createdBy`+location+normalized `creation_input`, else 409; identical retry returns the original 201 detail | `workforce_service.dart:38-53`; columns `0006:10-11`; test `shift_integration_test.dart:401-413` |
| draft -> draft (edit) | version-guarded UPDATE `WHERE version=@version AND status='draft'` | identical-draft no-op returns current without audit; stale version => 409 `shift_conflict` | `shift_repository.dart:131-146`; `workforce_service.dart:68-82` |
| draft -> published | atomic publication: retry short-circuit, publishability (non-empty selections, `endsAt` after DB now), overlap check, employee eligibility, task materialization with per-instance audits, shift flip `publication_version=@version`, shift audit | retry identity = `status=='published' && publicationVersion==expectedVersion` (actor **not** compared - deliberate per ADR 0011); mismatch => 409 | `workforce_service.dart:84-107`; `shift_repository.dart:155-181`; `shift_application.dart:187-212`; `shift.dart:18-19`; atomicity/rollback tests `shift_integration_test.dart:218-274,426-498` |
| published -> cancelled | P1b.8 coordinator (section 11) | strict retry identity: `cancellationVersion==expectedVersion && cancelledBy==actor && cancellationReason==normalized reason`; mismatch => 409; retry is read-only | `workforce_service.dart:109-138`; `shift_repository.dart:183-206`; tests `shift_cancellation_integration_cases.dart:185-239` |
| published -> published (amendment/republish) | **not supported** - 409; DDL refuses any non-whitelisted UPDATE | - | `shift.dart:12-16`; `0011:34-40`; `shift_integration_test.dart:345-356` |
| draft -> cancelled | **not supported** - 409 (`requireCancellable` demands published); DDL impossible | - | `shift.dart:20-24`; `0011:24-25` |
| cancelled -> anything | **terminal** - trigger refuses UPDATE and DELETE | - | `0011:30-33,40` |
| publish with overlap | 409 `shift_overlap`; strict inequalities allow back-to-back shifts; cancelled shifts free the interval | - | `shift_repository.dart:155-166`; `workforce_service.dart:91-97`; `shift_integration_test.dart:670-711`; ADR 0013:60-61 |

Publication snapshot immutability: selections frozen for published and cancelled
shifts (`0011:44-51`); task content snapshots immutable (`0006:33-38`;
`0011:75-79`); runtime user cannot mutate post-commit
(`shift_integration_test.dart:377-388`). DDL trigger vs application contracts:
consistent everywhere except the overlap invariant, which is application-level
only (finding M2), and contract looseness (ShiftDto does not require publication
evidence non-null for published/cancelled while DDL does - the server can never
emit the illegal shape; noted in L-findings context, no separate ID).

Intentionally NOT supported (citations): amendment of a published shift
(ADR `0013-published-shift-cancellation.md:43-44,48-50`; `docs/roadmap/status.md:48`);
reconciliation after execution begins (ADR 0013:14-17,21-24,66-67; open question
`docs/risks-and-open-questions.md:33`); soft-delete without cancelling instances
(ADR 0013:53-54); integration events for publish/cancel (ADR 0011:17; ADR 0013:72;
test `shift_integration_test.dart:362-367`).

## 11. Cross-module coordination (P1b.8 as reference case)

Owner: `ShiftApplication.cancel` (`shift_application.dart:214-253`), committed
as `19151f6`. Verified anatomy:

- **Single TxSession**: `runAuthorized` opens exactly one `pool.runTx`
  (`platform_database.dart:102`) and passes its `tx` to both module ports
  (`WorkforceService.cancel(tx,...)` `workforce_service.dart:109-116`;
  `TaskInstanceService.cancelForShift(tx,...)` `task_instance_service.dart:79-86`).
  No nested transactions, no second connection.
- **Company lock**: first statement inside the tx (`platform_database.dart:105-108`);
  ADR 0013:26-27 confirms the design.
- **Ordering and preconditions**: reason normalization -> permissions -> read
  shift -> single DB-clock read (`shift_application.dart:234-237`) -> zero-write
  422 gate unless every instance is pristine `open` v1
  (`task_instance_service.dart:87-96`) -> per-task guarded cancel + per-task
  audit -> shift cancel + shift audit. Tasks-before-shift ordering is documented
  (`docs/architecture/module-boundaries.md:81`).
- **Ownership respected**: Tasks writes task state+audit; Workforce writes shift
  state+audit; no foreign tables ("Kein neues Modul, kein Ereignis, keine
  fremden Tabellenzugriffe", module-boundaries.md:81).
- **Audit atomicity**: both modules' audits in the same tx with one shared
  correlation ID (`audit_repository.dart:89`; `correlation.dart:9-12`; test
  `shift_cancellation_integration_cases.dart:140-169`).
- **Rollback proven both directions** by trigger injection: task-side failure
  leaves the shift published with zero audits (`:613-651`); shift-side failure
  after in-tx task cancels rolls everything back byte-identically (`:653-731`).
- **Concurrency**: identical concurrent cancels collapse to one effect
  (`:520-540`); different reasons => [200,409] (`:549-563`); cancel-vs-start
  race has exactly one winner (`:572-611`).

Verdict: **suitable as the reference model** for future cross-module
transactional operations. Bounded caveats recorded as debt/findings, not as
defects of the pattern: company-lock granularity (debt A), row-by-row loops
(bounded by <=10 selections), asymmetric retry identity vs publication
(deliberate per ADR 0011/0013), no shift-level operation-receipt table
(state-derived idempotency instead), `ShiftApplication` facade growth (L10),
hardcoded trigger column whitelists (L10).

## 12. Mutation / idempotency matrix

Global mechanisms: every session-authenticated mutation runs under the company
advisory lock via `runAuthorized` (`platform_database.dart:93-168`); state +
audit (+ events/receipts) commit in one transaction; there is **no** dedup
constraint on `audit_entries` - duplication is prevented solely by
early-return replay paths and version/state guards aborting the tx.

| Operation | expectedVersion | Receipt / retry identity | Actor in retry identity | Payload in retry identity | Retry after lost response | Audit duplication |
| --- | --- | --- | --- | --- | --- | --- |
| Account create (`identity_service.dart:44-108`) | no | client-supplied id = creation key | no | no | 409 `already_exists`; no original-result replay | none on retry (aborts pre-audit) |
| Account update (`:110-167`) | yes | version guard | no | no-op detected by role+isActive equality `:129-131` | 409 `version_conflict`; same-values uncommitted duplicate returns 200 without audit | no-op skips audit |
| Admin password reset (`:169-206`) | yes | version guard; every success bumps version + revokes sessions `:188-194` | no | no | 409 `version_conflict`; replay impossible by construction | single audit per committed change |
| Org setup (`organization_service.dart:50-132`) | no (reads versions in-tx) | one-shot state | no | no | 409 `already_configured` | none on retry |
| Rename company/location (`:134-190,250-308`) | yes | version guard | no | same-name no-op returns current | 409 `version_conflict` | no-op skips audit+event |
| Create location (`:192-248`) | no | client id | no | no | 409 `already_exists` | none on retry |
| Employee create/rename/deactivate (`employee_application.dart:64-153`) | rename/deactivate yes | client id / version guard | no | rename same-name no-op | 409 | rename audits only if version changed `:107-120` |
| Employee link/unlink (`:169-223`; `employee_links.dart:22-97`) | yes (link: employee+account versions) | client link id / version+`revoked_at IS NULL` guard | no | no | 409 `already_linked` / `version_conflict`; sessions revoked exactly once | none on retry |
| Shift create (`workforce_service.dart:38-66`) | no | **de-facto receipt**: `created_by` + `creation_input` columns | **yes** (`:47`) | **yes** (normalized JSON `:49`) | identical retry => original 201 detail; mismatch => 409 `shift_conflict` | retry returns pre-audit |
| Shift edit (`:68-82`) | yes | version+draft guard | no | identical-draft no-op | 409 | no-op skips audit |
| Shift publish (`:84-107`) | yes | **state receipt**: `publication_version` | **no** - version-only retry identity (deliberate, ADR 0011) | via expectedVersion only | exact retry => 200 committed detail, no re-materialization, no new audits | repeat returns pre-audit |
| Shift cancel (`:109-138`) | yes | **state receipt**: cancellation evidence columns | **yes** (`:120`) | **yes** (normalized reason `:121`) | exact retry => 200, zero side effects; any mismatch => 409 | retry returns pre-audit |
| Task execution commands x7 (`task_execution_service.dart:95-280`) | yes (`operationId` + `expectedVersion` required) | **explicit receipt table** `task_execution_commands` (input <=4096B, result <=8192B, `0007:24-31`, `0008:16-17`) | **yes** | **yes** (canonical JSON incl. normalized value/reason) | identical replay => stored original 200 after fresh authorization; reuse with any field mismatch => 409 `operation_conflict` | receipt-hit returns before any write => at-most-once audit per operationId |
| Template create/newDraft/edit/publish (`task_template_service.dart:129-263`) | newDraft/edit/publish yes | publish: `publication_version` state receipt; create: client ids | no | edit identical-content no-op | publish exact retry => 200 no new audit; others 409 | no-op/repeat paths skip audit |
| Event replay (`event_service.dart:45-76`) | no | `FOR UPDATE` state guard; only `dead_letter` replayable | no | no | retry => 409 `invalid_state` (already pending); downstream dedup via `event_receipts` PK + inbox unique | one `event.replayed` per successful requeue |
| Plugin register/approve/disable (`plugin_service.dart:45-235`) | approve/disable yes | row lock `FOR UPDATE`; approve issues a fresh token each success | no | no | register 409 `already_exists`; approve/disable 409; a lost approve response cannot re-issue the lost token (by design) | single audit per committed change |
| Plugin ack (`:260-279`) | no | delivery row lock; pending-only update | token identity scopes grant | no | fully idempotent 204 | no audit by design |
| Login (`auth_service.dart:84-139`) | no | none - each success creates a new session | n/a | n/a | duplicate effect by design (second valid session); limiter throttles failures/concurrency | one `auth.login` per session (1:1, consistent) |
| Logout (`:152-157`) | no | none | token is the identity | n/a | **not idempotent**: retry => 401 | audit only when a live session was revoked |
| Bootstrap CLI (`bootstrap_service.dart:33-125`) | no | `bootstrap_state` singleton row = receipt | no | no | retry => `BootstrapException`, exit 1 | single audit in the one-time tx |

Assessment: the differing conventions are **justified by operation type**, not
accidental. High-frequency employee execution commands need true
original-result receipts (lost responses must not force re-execution or block
work) and have them. Low-frequency admin mutations use optimistic versions with
fail-closed 409 retries plus read-back reconciliation, which the Flutter client
implements consistently (section 22). The two state-receipt patterns (publish
version-only; cancel version+actor+reason) are explicitly designed in ADR
0011/0013. The only asymmetry worth remembering: a different admin replaying a
lost publish response receives the original result with no audit trace of the
replay - accepted design, recorded here for future contract work.

## 13. Authentication / sessions

- Password hashing: Argon2id via `package:cryptography`
  (`password_hasher.dart:4,23-28`), m=19456 KiB, t=2, p=1, 32-byte hash,
  16-byte `Random.secure()` salt, PHC string encoding (`:34-42`), constant-time
  verification (`:100-107`). Login always verifies against a dummy hash when the
  account is missing/inactive (timing equalization, `auth_service.dart:59-61,98-101`).
- Session tokens: 32 random bytes -> 43-char base64url (`auth_service.dart:109-111`);
  only the SHA-256 hex digest is stored (`auth_sessions.token_hash char(64) UNIQUE`,
  `0001_platform_auth.sql:13-21`); TTL default 3600s, env-clamped 60-86400
  (`config.dart:101,140-147`).
- Per-request revalidation: `runAuthorized` re-reads account (active, company,
  location), re-checks the session row (not revoked, not expired vs DB clock) and
  re-reads the role under the company lock (`platform_database.dart:109-156`) -
  disabled accounts and role changes take effect immediately.
- Revocation triggers (all verified): logout (`auth_store.dart:204-245`);
  account disable or role change (`identity_service.dart:142-149`); admin
  password reset (`:188-194`); employee link create (`employee_links.dart:63-64`)
  and revoke (`:86-94`); employee deactivation cascades link revocation
  (`employee_application.dart:139-141`); expiry (DB clock); passive `is_active`
  checks. Revocation semantics match `docs/architecture/security.md` and the
  restore fencing evidence (restored copies have 0 active sessions/tokens and
  runtime CONNECT denied, `backup_restore_fixture.dart:254-263,734-743`).
- Admin password reset is coherent: company-scoped 404 concealment, version
  guard, Argon2id re-hash, all-sessions revocation, audit
  `identity.user.password_reset` with `{version}` only - no password or hash in
  audit or response (`identity_service.dart:169-206`).
- Plugin tokens: issued only on approve, 43-char random, SHA-256 at rest, one
  unrevoked token per plugin (partial unique index `0003:100-111`), returned
  once, never audited; approval revokes prior tokens and pending inbox rows
  (`plugin_service.dart:147-165`); auth path takes the company lock **before**
  reading the token to avoid stale-approval races (`:293-320`).
- Logging: sole stdout writer is `JsonLogger` (`json_logger.dart:7-20`); events
  log requestId/method/path-without-query/status/duration/runtimeType/sqlState
  only (`server_app.dart:90-146`); config errors log env **names**, never values
  (`bin/server.dart:47-72`). No token, password, hash or Authorization header is
  logged anywhere (grep across `apps/server`). Matches
  `docs/architecture/security.md:22`.
- Known limitation - process-local LoginLimiter (`login_limiter.dart:15-17`;
  created per process `auth_service.dart:65`): in-memory maps, resets on
  restart, not shared across processes. Limits: 15-min fixed window, 5 failures
  per username, 30 per remote key, 4 concurrent logins process-wide, 10000-key
  cap (`login_limiter.dart:2-8,22-28`). Remote key = raw socket address
  (`server_app.dart:266-270`), no X-Forwarded-For handling; the documented
  Caddy topology proxies all `/api/*` (`infra/reverse_proxy/Caddyfile`).
  **Safe for**: single-process deployments where clients connect directly
  (loopback/dev, or direct LAN exposure). **Becomes a blocking issue** when the
  documented reverse-proxy TLS deployment is used for a real pilot: all clients
  share one 30-failure bucket (finding M1). Multi-process/horizontal scaling
  would also require shared limiter state - out of the bounded pilot scope.

## 14. RBAC / tenant isolation

Implemented role -> capability matrix (`platform_database.dart:35-76`; DB role
CHECK `0004:6-8`), 20 permissions:

| Role | Permissions |
| --- | --- |
| admin | all 20 |
| auditor | context.read, organization.read, audit.read, events.read |
| employee | context.read, organization.read, people.self.read, workforce.shifts.self.read, tasks.instances.self.read, tasks.instances.self.execute |
| viewer | context.read, organization.read |
| unknown role | none (empty set) |

Route-to-permission mapping was built for all 70 routes (section 20). Results:

- Concealment is consistent: foreign/unknown resources return 404 (`not_found`
  or `employee_unavailable`) across users, plugins, events, shifts, tasks,
  employees, templates, links; 403 is returned only for permission failures
  evaluated before resource lookup (no existence leak), plus
  `requireLocation` mismatch on system/status (`auth_service.dart:159-164`) and
  `origin_forbidden`.
- Self/profile scope: no bypass found. `_self()` re-validates link (unrevoked),
  company, location, employee active + assignment window at call time
  (`shift_application.dart:84-112`); employee-home commands additionally require
  published + own + own-location shift (`:255-270`); resume re-checks current
  employee validity while blocked-task cancel deliberately does not (documented,
  `platform.openapi.json` cancel description).
- Writes under read-flavored permissions (reviewed, justified or recorded):
  plugin ack mutates inbox state under `events.read` (documented design,
  `docs/development/phase-1.md:39`); `audit.read` inserts a self-audit entry per
  read (`audit_service.dart:23-30`, documented); shift publish/cancel
  additionally require the read permission `tasks.instances.read` (no practical
  effect - only admin holds `workforce.shifts.manage`); template **reads**
  require the manage permission (conservative, not a leak).
- Location-scope inconsistency inside the manager path (finding L4): shift
  list/get/execution apply no location predicate
  (`shift_application.dart:262-269,552-558`; `shift_repository.dart:56-74`)
  while blocked/blockings/numbers hard-require
  `actor.locationId == database.locationId` with 404 (`:325-330`). Under the
  reviewed one-company, single-location deployment assumptions the divergence is
  latent and not reachable through the current supported application flow;
  `requireConfiguredLocation` accepts any named company location and additional
  locations are admin-creatable, so this is a deployment convention rather than a
  structural database invariant (finding L4).
- Company predicate: every state-mutating statement in every repository carries
  `company_id` predicates; composite FKs bind `(id, company_id, location_id)`
  tuples (`0004:27-29,47-50`; `0005:9-10,28-29`; `0006:16-17,25-26,39-40`).
  Unscoped pre-validation lookups (finding L5, theoretical in the
  one-company-per-installation model enforced by `config.dart:107-113`):
  `plugin_repository.exists` (`:51-59`), `identity_repository.usernameExists`
  (`:39-48`), `task_template_repository.revisionIdExists` (`:90-98`),
  `task_execution_repository.receipt` (`:60-68`, company compared afterwards in
  `task_execution_service.dart:116-127`). Token-hash-keyed lookups are safe
  (256-bit secret; company checked in-query or immediately after).
- No plausible cross-company read/write path exists in the deployment model:
  the schema hosts exactly one company, `authenticate` rejects principals of any
  other company (`auth_service.dart:141-150`), and `runAuthorized` re-checks
  company inside the lock (`platform_database.dart:98-100,125-128`).

## 15. Audit

Implemented audit actions (complete grep inventory): `platform.bootstrapped`;
`identity.bootstrap_admin_migrated` (migration backfill `0003:22-30`);
`auth.login`, `auth.logout`; `identity.user.created/updated/password_reset`;
`identity.employee.linked/unlinked`; `organization.company.setup`,
`organization.location.setup`, `organization.company.updated`,
`organization.location.created/updated`; `plugin.registered/approved/disabled`;
`event.replayed`; `audit.read`; `people.employee.created/renamed/deactivated`;
`tasks.template.created/revision_created/draft_updated/published`;
`workforce.shift.created/draft_updated/published/cancelled`;
`tasks.instance.created/started/blocked/resumed/completed/cancelled`;
`tasks.step.confirmed`, `tasks.step.number_recorded`.

Conventions verified:

- Naming is consistent hierarchical `<module>.<entity>.<action>` (two
  legacy-shaped platform actions `platform.bootstrapped`, `audit.read` are
  documented exceptions).
- Actor = re-validated account UUID (`platform_database.dart:157-165,180`);
  company = actor company; actor kinds `{user, system, plugin}` whitelisted
  (`audit_repository.dart:25-27`; DB CHECK `0003:4`) - `plugin` is never used:
  plugin-token endpoints write no audit (recorded; consistent with the P1
  plugin contract).
- Correlation ID: zone-scoped per HTTP request, echoed as `x-request-id`,
  re-wrapped by `runAuthorized`, shared by all entries of one transaction
  (`correlation.dart:4-12`; `server_app.dart:41-46,129`; `audit_repository.dart:89`).
- Bounds: 512-code-point scalar limit (`audit_repository.dart:116-123`) and
  4096-byte aggregate limit mirrored in Dart and DDL (`:68-70`; `0003:12-14`).
  Reviewed for current correctness only; the previously accepted LOW polish
  (runes vs UTF-16 units for list items) is not reopened.
- Secret avoidance: no password/token/hash field is whitelisted or written;
  login/logout changes are `{}`; password reset records `{version}` only;
  plugin approve records permissions/subscriptions but never the token; numeric
  raw values are excluded by design (section 9).
- Atomicity: `append(tx,...)` always runs inside the caller's mutation
  transaction; audit failure rolls back the business change (injected-failure
  tests: `postgres_integration_test.dart:331-427`;
  `shift_integration_test.dart:443-498`;
  `shift_cancellation_integration_cases.dart:613-731`;
  `task_numeric_integration_cases.dart:505-574`). Append-only at the DB-privilege
  level (`migration_runner.dart:155-158` REVOKE UPDATE/DELETE/TRUNCATE).
- Failed mutations write **no** audit (everything rolls back). Refusal evidence
  "nach Audit-/Sicherheitsrichtlinie" (`docs/architecture/event-system.md`,
  Audit contract section) is an unimplemented policy-dependent contract -
  tied to the outstanding retention/security-policy decision (section 27), not
  a defect of the current slices.
- Strict idempotent retries produce **no** duplicate audit on any path
  (matrix section 12; tests per row). `audit.read` self-auditing and per-login
  `auth.login` entries multiply by design and are documented
  (`docs/development/phase-1.md:31`; `phase-2-capacity-measurement.md:63`).

## 16. Outbox / domain events

- Producers: only `OrganizationService` emits, via
  `publishOrganizationEvent(tx,...)` inside the mutation transaction
  (`organization_service.dart:108,117,179,236,296`). Whitelist of exactly four
  types: `organization.company.setup`, `organization.company.updated`,
  `organization.location.created`, `organization.location.updated`
  (`event_repository.dart:61-72`; DB restricts aggregate types and 8192-byte
  payloads, `0003:43,61-63`).
- Intentional non-emitters: identity, people, shifts, tasks, templates,
  plugins, auth, audit, replay (grep `publishOrganizationEvent` - 5 call sites,
  all organization). Matches ADR 0011:17, ADR 0013:72 and the module-boundaries
  rule "no events without a concrete consumer"; test proof
  `shift_integration_test.dart:362-367`.
- Events are committed atomically with business state (same tx, same lock).
- Dispatcher: in-process 2s timer (`event_bus.dart:27-51`); claim
  `FOR UPDATE SKIP LOCKED` (`event_repository.dart:163-185`); inbox fan-out +
  receipt + markDispatched in one tx (`event_bus.dart:62-81`); dedup via
  `event_receipts` PK `(event_id, consumer)` and `plugin_inbox UNIQUE(plugin_id,
  event_id) ON CONFLICT DO NOTHING` (`0003:72-77,121`); bounded retries with
  backoff, dead letter at 5 attempts (`event_repository.dart:221-234`); admin
  replay of dead letters only (`event_service.dart:45-76`).
- Consumers: the plugin inbox is the sole consumer (receipt consumer CHECK
  allows only `plugin_inbox`, `0003:74`). At-least-once delivery with
  effectively-once fan-out; **no current consumer requires delivery guarantees
  beyond what is implemented**; ordering after retry/replay is explicitly not
  guaranteed and documented (`docs/architecture/event-system.md`).
- Doc-vs-reality deltas: `event-system.md` names `shift.published.v1`,
  `task.instance_created.v1`, `task.completed.v1` as **examples** - none exist,
  and the doc disclaims them; `module-boundaries.md:52` uses present tense
  ("`shift.published.v1` wird nach Commit ... zugestellt") while `:73` correctly
  states no outbox entry exists until a concrete consumer appears (finding L8).
  `organization.company.setup` is emittable but not subscribable
  (`supportedPluginSubscriptions` excludes it,
  `api_contracts platform_plugins.dart:4-8`), so it always dispatches to zero
  eligible plugins (finding L9).

## 17. Error taxonomy

Full status/code map built from `server_app.dart`, `api_support.dart`,
`platform_database.dart` and all service/route files:

| Status | Codes (producers) |
| --- | --- |
| 400 | `invalid_request` (FormatException catch-all `server_app.dart:65`; Pg 23503/23514/22P02 `:101-103`; login body `:167-171`; `platform_input.dart` field checks), `invalid_json`, `invalid_shift`, `invalid_reason`, `invalid_number`, `invalid_cursor`, `invalid_id`, `invalid_manifest`, `invalid_version`, `invalid_permissions`, `invalid_template_content` |
| 401 | `invalid_credentials` (login only `server_app.dart:68-72`), `unauthorized` (session/plugin) |
| 403 | `forbidden`, `origin_forbidden` |
| 404 | `not_found`, `employee_unavailable` (self-scope concealment); plain-text 404 from the router cascade for unmatched routes (`server_app.dart:55-58`) |
| 405 | `method_not_allowed` (CORS preflight only `:199-202`) |
| 409 | `conflict` (Pg 23505), `already_exists`, `version_conflict`, `last_admin`, `resource_limit`, `already_configured`, `setup_required`, `plugin_limit` (write), `shift_conflict`, `shift_overlap`, `template_conflict`, `operation_conflict`, `execution_conflict`, `inactive_identity`, `already_linked`, `inactive_employee` |
| 413/415 | `body_too_large` (>16384B), `unsupported_media_type` |
| 422 | `shift_not_publishable`, `employee_unavailable` (eligibility), `invalid_selection`, `shift_in_progress`, `invalid_execution`, `outside_shift`, `empty_template` |
| 429 | `rate_limited` |
| 500 | `internal_error` (uncaught errors) |
| 503 | `database_unavailable`, `platform_not_initialized`, `plugin_limit` (read path); `/ready` returns `HealthResponse`, not `ApiError` |

Consistency assessment: validation splits 400 (syntactic) vs 422 (semantic) are
mostly consistent; auth/concealment/conflict semantics are uniform across APIs.
Material inconsistencies (finding M4): `plugin_limit` 503-on-read vs 409-on-write
(`plugin_service.dart:36-40` vs `:65-69`) while every other registry limit uses
409 on both paths; DDL trigger violations (SQLSTATE 23514) map to 400
`invalid_request` (`server_app.dart:101-103`), making a server-invariant breach
indistinguishable from client input error; concurrent duplicate-key races
surface as `conflict` while prechecks yield `already_exists` (same status, two
codes for one user-visible failure); unmatched routes return non-JSON 404s,
violating the otherwise universal `ApiError` contract. Minor deliberate splits
clients must handle: two 401 codes, two 403 codes, `employee_unavailable` as
both 404 (concealment) and 422 (business rule), six cursor formats (all 400
`invalid_cursor`). None of these breaks correctness; they complicate generic
client error handling (M4).

## 18. Migration health (0001-0011)

Runner mechanics (`migration_runner.dart`, read fully): lexicographic ordering
of `^\d{4}_[a-z0-9_]+$` files (`:255-290`); SHA-256 checksums stored in
`storeos_platform.schema_migrations(version, checksum, applied_at)` (`:41-46,285`);
mismatch => `Checksum changed` (`:65-67`); applied-but-unknown =>
`Unknown applied migration` (`:60-64`); applied set must be an exact ordered
prefix of known versions (`:69-79`); the **entire run** (all pending migrations
+ ledger + grants) executes in one transaction under the
`storeos_migrations:<schema>` advisory lock (`:35-39`), `QueryMode.simple`
(`:83`). Runtime GRANTs live in the runner (zero GRANT statements in the SQL
files), are keyed per version and re-executed idempotently on every apply
(`:96-250`), evolving from base 0001 grants through per-slice least-privilege
blocks incl. column-scoped UPDATEs and REVOKE UPDATE/DELETE/TRUNCATE on
append-only tables (audit `:155-158`; instances `:160-176`; receipts
`:177-183`; blockings `:188-198,217-221`; attempts `:199-206`; cancellation
columns `:207-216`).

| Version | Purpose | Major invariant introduced | Upgrade test evidence | Known risk |
| --- | --- | --- | --- | --- |
| 0001 platform_auth | accounts, sessions, bootstrap_state | unique username, session expiry CHECK, bootstrap singleton | populated 0001 -> latest (`postgres_integration_test.dart:106-187`); grant matrix `:36-61` | none |
| 0002 platform_organization | company/location singletons | one company per install, optimistic versions, composite scope keys | fresh + full-chain runs | none |
| 0003 platform_events_plugins | audit, outbox/receipts, plugins | append-only audit (4096B changes), one unrevoked plugin token, honest bootstrap-admin audit backfill | populated 0003 -> latest (`postgres_integration_test.dart:514-604`) | none |
| 0004 employee_identity_and_audit | employees, links, correlation_id | historical correlation stays NULL, role set + `employee`, scope FKs, time-valid links | populated 0004 -> latest (`task_template_integration_test.dart:58`) | none |
| 0005 task_templates | templates + revisions | immutable published content, 8192B content bound | populated 0005 -> 0006+ (`shift_integration_test.dart:778-812`) | none |
| 0006 shifts_and_task_instances | shifts, selections, instances | draft/published evidence coupling, `starts_at<ends_at`, <=10 selections, immutable snapshots | populated 0006 -> 0007 (`task_execution_integration_cases.dart:167,249`) | overlap has no DDL constraint (M2) |
| 0007 task_execution | execution columns, step results, receipts | state/version/timestamp coupling, trigger-insert-only results; runtime-grant-protected receipts (operation_id PK; L12) | populated 0007 -> 0008 (`task_blocking_integration_cases.dart:536,656`) | strict version equality later relaxed in 0008 (deliberate) |
| 0008 task_blocking | blocked state, blockings | blocking/resolution version coupling, `accepted_version` backfill with trigger disabled->re-enabled | populated 0008 -> 0009 (`task_cancellation_integration_cases.dart:490,612`) | backfill window (executed inside the migration tx; tested) |
| 0009 task_cancellation | terminal cancellation of blockings | `resolution_kind IN (resumed,cancelled)`, one cancellation per instance, `protect_task_blocking` trigger | populated 0009 -> 0010/0011 (`task_numeric_integration_cases.dart:46-153`) | none |
| 0010 task_numeric_steps | schema-2 numeric steps | DB content validator `valid_task_content`, immutable attempts, additive-only (old snapshots/receipts never rewritten), unnamed-CHECK replacement via `pg_constraint` scan | populated 0010 -> 0011 (`shift_cancellation_integration_cases.dart:733-867`); full harness 0010->0011 (section 25) | constraint replacement transition - explicitly tested both unit-level and end-to-end |
| 0011 published_shift_cancellation | shift cancellation | three-state shifts CHECK with evidence coupling, column-whitelist cancellation trigger, cancelled terminal, unstarted-cancel task shape (v=2) | same as 0010 row; update/recovery acceptance proves exactly-one-application + idempotency + checksums (`update_recovery_fixture.dart:437-467`) | hardcoded trigger column whitelists (L10) |

Append-only chain verified by git history: `git log --name-status --
apps/server/migrations/` shows only `A` entries, one commit per migration
(`1209f20`, `bfd6898`, `3a8f710`, `925a52f` series through `19151f6`); no
historical migration was ever edited. Runtime enforcement: checksum + prefix
rules above; the update harness additionally re-verifies byte-identical
repository copies of 0001-0010 (`update_recovery_fixture.dart:424-435,1864-1883,2156-2193`).

## 19. Upgrade-path coverage

Evidenced paths (not merely claimed):

| Path | Evidence | Rating |
| --- | --- | --- |
| fresh -> latest (0001-0011) | CI migrate+bootstrap (`ci.yml:97-98`); every integration fixture applies the full directory; exact list asserted (`postgres_integration_test.dart:150-161`) | STRONG |
| runner idempotency (second apply = no-op) | `postgres_integration_test.dart:34-35,582`; `shift_cancellation_integration_cases.dart:812-813`; harness upgrade mode (`update_recovery_fixture.dart:437-467`) | STRONG |
| checksum mismatch refusal | `postgres_integration_test.dart:22-77` (edited copy of 0001, ledger unchanged) | STRONG |
| failed-migration rollback | `postgres_integration_test.dart:79-104` (failing 0002; `accounts` never materialized) | STRONG |
| populated 0001 -> latest | `postgres_integration_test.dart:106-187` | STRONG |
| populated 0003 -> latest | `postgres_integration_test.dart:514-604` | STRONG |
| populated 0004/0005/0006/0007/0008/0009 -> next | `task_template_integration_test.dart:58`; `shift_integration_test.dart:778-812`; `task_execution_integration_cases.dart:167`; `task_blocking_integration_cases.dart:536`; `task_cancellation_integration_cases.dart:490`; `task_numeric_integration_cases.dart:46-153` | STRONG |
| populated 0010 -> 0011 (unit level, legacy in-progress/blocked/cancelled rows) | `shift_cancellation_integration_cases.dart:733-867` (snapshot equality excluding new columns, refusal matrix, raw-SQL rejection) | STRONG |
| 0010 -> 0011 end-to-end with real scripts, restore point, smoke and recovery | update/recovery acceptance (section 25.4; CI job `update-recovery-acceptance`) | STRONG |
| unknown applied migration / non-prefix ledger / invalid filename / empty migration | **ABSENT** - grep of `apps/server/test/*.dart` for `Unknown applied|not a known prefix|Invalid migration|Empty migration` returns nothing; branches `migration_runner.dart:60-64,69-79,274-280` untested | finding L7 |
| every-version-to-latest exhaustive matrix | not evidenced; not demanded - per-boundary populated upgrades plus the harness make the marginal value low | acceptable gap |

## 20. API / contracts / OpenAPI

Comparison method: (1) enumerated every `router.get/post` registration in the
8 HTTP files, unrolling the registration loops (`shift_routes.dart:65,134`);
(2) parsed `packages/api_contracts/platform.openapi.json` programmatically
(paths x methods, parameters, request/response `$ref`s, component schemas);
read `packages/api_contracts/openapi.yaml` fully; (3) normalized shelf `<param>`
to OpenAPI `{param}` and set-compared; (4) compared schemas field-by-field
against the Dart contract DTOs, server serializers and DDL bounds; (5) grepped
all tests/CI for OpenAPI enforcement.

Result: **70 implemented routes = 65 documented in `platform.openapi.json` +
5 inline in `openapi.yaml` - exact 1:1 bijection (70 == 70).** No missing route in the doc
union; no documented-but-unimplemented route; success statuses agree (201 on the
8 create-style routes, 204 on logout+ack, 200 elsewhere; `/ready` 200/503).
Contract DTOs match server responses and DDL bounds field-by-field (identities,
employees incl. `isActive == (assignedUntil == null)`, shifts incl. cancelled
evidence conditionality, execution DTO version invariants, numeric regex,
template bounds, plugin manifest exact-key rules, session/status DTOs).

Drift/gaps (finding M3): neither document is self-contained (yaml `$ref`s 18
platform-API paths into the json - 15 platform + 3 plugin; every json error
response `$ref`s back into the yaml); path-parameter names differ cosmetically (`{id}`/`{taskId}` vs
`<eventId>`/`<task>`); the error contract is under-specified - none of the ~40
concrete error codes is enumerated in either document and per-operation error
statuses are absent (success + `default` only); `Context.permissions` and
`AuditEntry.actorKind` are plain strings in the docs despite fixed catalogs;
OPTIONS preflight is undocumented (conventional). Enforcement: only three
spot-check tests read the OpenAPI files
(`api_contracts/test/task_numbers_test.dart:119-141`;
`shift_contracts_test.dart:206-238`;
`task_cancellation_contracts_test.dart:20-56`); **no test compares the
registered route surface to the OpenAPI paths** (grep `openapi` across all
`*.dart`: zero hits in `apps/server/test`), so a future undocumented route
would pass CI.

## 21. (reserved - see sections 20 and 22)

## 22. Flutter architecture

Layers: `ui/` (7 screens/sections) -> `application/` (5 `ChangeNotifier`
controllers) -> `data/` (`StoreApi`/`PlatformApi` abstractions + HTTP impls).
Controllers talk only to data-layer APIs; no SQL/HTTP details leak upward.
`packages/api_contracts` is a real shared dependency of client **and** server
(`apps/client_flutter/pubspec.yaml:9-19`; `apps/server/pubspec.yaml:10`), so
validation (`blockingReason`, `taskNumber`/`taskNumberText`,
`TaskTemplateContent`, `ShiftDraftInput`) cannot diverge from server rules by
construction. `platform_models.dart` aliases contract DTOs instead of
duplicating them (`:6-10`).

Business rules in widgets: none that should be server/controller-owned. The
client-side state machines (`shift_controller.dart:41-106` canStart/canConfirm/
canRecordNumber/canComplete/canBlock/canResume/canCancel; `:172-191`
canPublish/canCancelShift/canAddRevision) mirror server rules as UX gates; the
server re-enforces everything. Nits (no finding IDs - stylistic): duplicated
reason validation in `_CancelShiftDialog` (`shift_section.dart:631-642`)
instead of calling shared `blockingReason` (controller re-validates at
`shift_controller.dart:693`, so such input is rejected later); duplicated
admin/dead-letter gating (`platform_sections.dart:578-580` vs
`platform_controller.dart:525`); raw-map list storage causing per-build DTO
re-parsing (`shift_controller.dart:19`; `shift_section.dart:488-489`);
`ShiftController` density (858 lines mixing management, lists and execution).

Flow review (busy/validation/empty/conflict/lost-response/session-expired/403):

- Login: busy indicator + disabled button (`login_screen.dart:175-188`);
  proactive expiry timer and 401->session-clear (`session_controller.dart:34-68,206-217`);
  password field cleared before await (`login_screen.dart:35-36`).
- Writes never auto-resend: 409 sets `conflict`/`executionConflict` and locks
  inputs until an explicit user reload/retry (`shift_controller.dart:505-511,764-769`;
  UI `shift_section.dart:214-238,467-482`).
- Lost-response read-back: every mutation reloads and reconciles by stable
  client UUIDs / exact expected outcomes incl. version arithmetic and
  cancellation evidence (`shift_controller.dart:703-737,779-816`;
  `employee_controller.dart:206-234,272-303`; `platform_controller.dart:321-411`;
  `task_template_controller.dart:374-483`); execution commands retain the exact
  pending route/body with `operationId` for explicit replay
  (`shift_controller.dart:381-387,474-491` equivalent UI `shift_section.dart:461-476`).
- Session-expired: epoch guards discard late responses across sessions in every
  controller; app root swaps to LoginScreen and pops dialogs
  (`storeos_app.dart:76-119`).
- 403: permission pre-gates (`_can`/`allowed`) plus mapped server messages
  (`http_platform_api.dart:88`).
- Tokens: memory-only, callback-scoped via `authorized()`; no storage package
  exists (`pubspec.yaml:9-26`; UI states non-persistence,
  `login_screen.dart:206-209`).
- Data layer: route allowlist prevents path injection
  (`http_platform_api.dart:51-60`); 10s timeout and network mapping; error
  messages chosen by status/code, server detail deliberately not surfaced
  (`:79-95`); no silent HTTP-level retries.
- Guided work incl. numeric UI is fully present in the shipping client
  (`shift_section.dart:291-483`), exercised end-to-end by the browser test.

## 23. Test pyramid / risk coverage

Inventory: ~173 pure unit tests (server 32 across 7 files; contracts 36 across
9 files; client 101 across 14 files; design_system 2) -> ~82 real-PostgreSQL
integration tests (12 server files; per-test random schemas inside a dedicated
`STOREOS_TEST_DATABASE`, skip when unset; `_test` suffix guards where present,
e.g. `shift_integration_test.dart:1148-1150`, `employee_integration_test.dart:733-735`;
runtime-privilege tests additionally require `STOREOS_DB_USER`/password file) ->
1 three-phase browser E2E (`numeric_guided_work_test.dart`, phases A/B/C across
API-process replacement and browser rebuild) -> 4 process-level acceptance
harnesses + 5 PowerShell regression checks (3 redaction + backup crypto + dev
setup), all wired into CI (`ci.yml:72-83,97-99,142-246`).

Risk-to-evidence mapping:

| Invariant | Evidence | Rating |
| --- | --- | --- |
| Task state machine + triggers | domain unit (`task_execution_test.dart`), 28 integration cases across 4 case files, DTO contract tests | STRONG |
| Shift state machine incl. cancellation | `shift_test.dart`, `shift_integration_test.dart` (51 tests in one library), `shift_cancellation_integration_cases.dart` (11 incl. raw-SQL rejection `:840-860`) | STRONG |
| Numeric invariants | unit bounds, DB validator tests, replay/canonicalization proofs, rollback-atomicity injection, browser E2E phases | STRONG |
| Idempotency/receipts | per-command replay tests, post-restart replay, cross-command reuse 409, harness receipt replay (`numeric_e2e_fixture.dart:875-943`) | STRONG |
| Concurrency/advisory-lock races | parallel publish/edit/cancel/start/resume/block/record races across 10+ tests (e.g. `shift_integration_test.dart:397,426-438,670-679`; `task_*_integration_cases.dart` race blocks; `postgres_integration_test.dart:189,429`) | STRONG |
| Tenant isolation / RBAC / concealment | role matrix tests, foreign-company template tests, 403-vs-404 assertions, plugin scope tests (`platform_security_integration_test.dart:306`) | STRONG |
| Audit atomicity | injected audit-failure rollback tests on 8 paths | STRONG |
| Migration upgrades | section 19 | STRONG (except L7 branches: ABSENT) |
| Backup/restore + update/recovery | harnesses with CI jobs (section 25) | STRONG |
| Refusal/failure evidence (policy-dependent) | not implemented, not tested | ABSENT (policy gap, section 27) |
| Second-writer/owner-level evidence hardening | no application path; insert-time triggers plus runtime-role grants only for results/blockings/receipts (L11/L12) | by design (not application-reachable) |
| OpenAPI/route consistency | 3 spot-checks only | WEAK (M3) |

Count was not treated as quality: the shift library's 51 tests are one
`main()` with `part` files; the capacity integration test self-skips without
CREATEDB. Both facts are recorded so ratings are not over-read.

## 24. Acceptance harness safety

Common verified properties (per harness, with sources in section 25 references):
run-scoped names with strict regex patterns; fail-closed destructive-operation
fencing (allow-list **and** pattern **and** ownership checks before any drop);
normal `storeos` database only existence-checked, never touched; loopback-only
API binds; secrets from `.local/secrets` files, never args; private manifests
chmod 600 / icacls-protected; sanitized `report.json` as the only retained
artifact, guarded by a dedicated `Assert-*Report` plus a CI-run
`Test-*Redaction` regression; cleanup on success and injected failure; honest
injection semantics (no rollback overclaim).

### 24.1 Numeric guided-work E2E
Schema-level isolation `storeos_e2e_<uuid32>` inside the fixed `*_test`
database (`numeric_e2e_fixture.dart:32,97`); loopback + `_test` URL fencing
(`:1006-1026`; runner re-check `Run-NumericGuidedWork.ps1:196-207`); restricted
runtime role enforced (`:417-434`); schema-drop only when owned, pattern-matched,
ledger-verified and not handed over (`:436-481,316-349`); passwords generated
per run, manifest 0600/icacls, secrets list drives log redaction
(`Run-NumericGuidedWork.ps1:73-76,214-216`; `Write-E2EDiagnostics.ps1:17-29`,
regression `Test-E2EDiagnostics.ps1` in CI `ci.yml:72-74`); durability via real
API-process replacement (prepare/resume) and browser rebuild; receipt replay
asserts zero new effects (`:290-295,875-943`); CI job
`numeric-guided-work-e2e` (`ci.yml:142-188`). Fixed ports 8095/8096/4444
preclude concurrent same-host runs (pre-checked `:232-234`). No drift from the
prior independent review found.

### 24.2 Backup/restore acceptance
Database-level isolation `storeos_backup_accept_<run16>` /
`storeos_restore_bkacc_<run16>[c]` with fixture-side pattern re-validation
(`backup_restore_fixture.dart:36-37,74-77,204-207`); fail-closed drop guard
(`Run-BackupRestoreAcceptance.ps1:104-111`, quoted refusal messages);
restore target fencing proven twice (script `Restore-StoreOS.ps1:19-21,41-42,85-112`
and fixture `:768-777`): runtime CONNECT denied by catalog and by real
connection attempt, 0 sessions/tokens; verification depth: source-unchanged
after backup, restored evidence equality via md5-of-md5 row hashes over 8
tables + 2 sequences (`:685-730`); corruption injection (bit-flip + rewritten
outer manifest hash) must be rejected by authenticated decryption
(`Run-...:273-295`; crypto-level `Test-BackupCrypto.ps1:67-82`); report
redaction guard + CI regression (`ci.yml:75-77`); CI job
`backup-restore-acceptance` (`ci.yml:190-217`). No drift found.

### 24.3 Capacity measurement
`storeos_capacity_<run16>` with pattern enforcement in runner and fixture
(`Run-CapacityMeasurement.ps1:37-38,115,132,190`; `capacity_fixture.dart:48,140-146`);
identical fail-closed drop guard (`Run-...:130-137`); workload bounds validated
twice so no unbounded accidental run; contention sampler is strictly
observational (no privileges, no session termination, no query text retention,
`capacity_fixture.dart:414-507`); integrity injection corrupts the verifier's
expectation against real data and must fail the run (`:701-703`;
`capacity_integration_test.dart:106-129`); report is aggregate-only by
construction (`:509-510`); failure diagnostics **are** masked here
(`Run-...:168-181`) - the drift vs the other two runners is finding L6. CI:
redaction check + real integration test inside `dart test` (`ci.yml:78-80,99`);
full wrapper runs are manual by design (documented).

### 24.4 Update/recovery acceptance
`storeos_update_<run16>` + `storeos_restore_upd_<run16>` with fixture pattern
enforcement (`update_recovery_fixture.dart:46-47,220-223,834-837`); extra hard
guard: runtime user must be exactly `storeos` so the pre-existing restore
fencing applies (`Run-...:204`); source != target proven via `current_database()`
vs catalog (`:944-954`); pre-update DB built from **byte-identical** copies of
repository migrations 0001-0010 with byte comparison (`:2156-2201`); upgrade
asserts exactly `['0011_...']` applied, second run zero, all 11 checksums
matching the repository (`:437-467`); preservation via stable pre-0011
projections (19 projection tables + 2 sequences + access state; the fixture's
17 seeded-count figure is the non-empty subset, `:57-165,469-479`); new
protections proven by three rejected invalid writes with source-unchanged
checks (`:486-519`); smoke serves the upgraded DB with the restricted runtime
role incl. a real P1b.8 cancellation with shared-correlation audit
(`:548-830`); recovery verifies the fenced 0010 restore target and source
independence (`:832-979`); injection semantics are honest in-report
("post-upgrade operational failure, not rollback proof",
`Run-...:22-26,339-344`); report lists explicit `contract.supported` /
`contract.notProven` boundaries incl. restore-point hash with
`artifactStatus: 'deleted-after-run'` (`:356-385`); CI job
`update-recovery-acceptance` (`ci.yml:219-246`). No drift from the independent
review basis found; remote CI green per operator evidence.

## 25. Fixture / harness duplication

Quantification: fixtures total ~6,165 lines (`update_recovery_fixture.dart`
2514; `capacity_fixture.dart` 1442; `backup_restore_fixture.dart` 1108;
`numeric_e2e_fixture.dart` 1101; `serve_smoke.dart` 131); runners ~1,534 lines.
Concrete duplication: byte-identical `_requireRestrictedRole` in 4 fixtures
(`numeric_e2e:417-434`; `backup:1000-1017`; `capacity:1372-1389`;
`update:2385-2402`); `_writePrivateManifest`, `_restrictWindows`, `_password` and
`_runtimePool` in 3 copies each (capacity uses renamed or inline variants),
`_required` in 4, `_serverApp` in 2, and endpoint helpers in multiple copies;
`_Snapshot`/`sameEvidence` machinery duplicated between backup and update;
seed-journey choreography ~60-70% structurally shared across numeric/backup/
capacity; PowerShell: `Import-LocalConfiguration`, `Require-Tool`,
`Resolve-SecretFile`, `Test-LoopbackPort`, `Invoke-ComposeDb`, DB-exists probes,
fail-closed `Remove-*Database`, `New-*Database`, `Invoke-Fixture`, env
capture/restore, sensitive-value collection, report+assert+exit blocks in 3-4
copies; three 37-line `Assert-*Report` functions carrying equivalent safety
logic (same forbidden patterns and secret representations; not byte-identical -
function names and nouns differ) and three near-identical ~45-line
`Test-*Redaction` scripts. Totals: ~450-550 duplicated
Dart lines + ~700-800 duplicated PowerShell lines (~1,200), concentrated in
**safety-critical** helpers.

Disposition: **ACCEPTABLE DUPLICATION** today - each harness is independently
runnable and CI-isolated; every redaction script has its own CI regression; the
destructive guards are semantically equivalent across copies; the harnesses
legitimately differ where it matters (schema- vs database-level isolation,
metrics vs evidence hashing, HTTP vs SQL seeding). A shared abstraction is not
recommended now; expected change frequency does not yet justify it. Drift
signals that would justify consolidation on next touch (finding L6): capacity
masks failure diagnostics while backup/update runners print log tails unmasked
(`Run-CapacityMeasurement.ps1:168-181` vs `Run-BackupRestoreAcceptance.ps1:143-154`,
`Run-UpdateRecoveryAcceptance.ps1:159-170`); result-file write permissions
differ (`_writeJson` plain vs `_writeJsonAtomic` without 0600).

## 26. Technical debt disposition

| Debt | Classification | Consequence | Pilot impact | Reconsideration trigger |
| --- | --- | --- | --- | --- |
| A. Company-wide `runAuthorized` serialization (incl. reads) | RELEVANT BUT DEFER | throughput ceiling; single contention point | none for a bounded single-site pilot (capacity evidence, section 7) | multi-site/larger concurrency, or measured latency complaints on target hardware; narrowing requires re-proving last-admin, revocation immediacy, overlap (M2 first), races, plus target-hardware capacity |
| B. `PluginService`->`OrganizationRepository` shortcut (+ undocumented `IdentityService` instance) | RELEVANT BUT DEFER | plugin/identity modules coupled to organization persistence | none | any change to organization ports/schema; must not be extended to business modules (HANDOVER rule) |
| C. Process-local LoginLimiter | RELEVANT BUT DEFER (escalated to M1 for proxied deployments) | brute-force attribution degrades; shared-bucket lockout DoS behind a proxy | none for loopback/direct single-process operation; blocking decision for a proxied real pilot | adoption of the Caddy TLS topology for a real pilot; multi-process deployment |
| D. In-memory client sessions / pending command state | RELEVANT BUT DEFER | browser refresh requires re-login; unconfirmed retries lost on refresh (read-back reconciliation mitigates) | acceptable for bounded online pilot | device/offline phase (P2 device cache/queue) |
| E. No offline queue | UNRELATED to the bounded online pilot and the next capability | - | none under the stated pilot assumptions | device-offline phase |
| F. Retention/export policy absence (audit/outbox/receipt growth incl. `audit.read`; no employee deletion/export workflow) | RELEVANT BUT DEFER (policy, not code) | unbounded evidence growth; no lawful erasure/export path | blocks a **real-employee-data** pilot until decided (section 27) | first real-employee pilot; storage-pressure warnings; any destructive cleanup implementation |
| G. Fixture/acceptance duplication | RELEVANT BUT DEFER | ~1,200 duplicated safety-critical lines; observed masking/permission drift (L6) | none | next harness change - consolidate then, not before |
| H. Published-shift amendment/reconciliation absence | RELEVANT BUT DEFER | in-flight work cannot be corrected at shift level; cancel+republish is the only correction path (interval freed, ADR 0013:60-61) | none for the bounded pilot; documented product gap (`status.md:48`) | product rules for partially executed work exist; any rescheduling feature |
| I. Prior review LOW findings (audit scalar bound units etc.) | RELEVANT BUT DEFER (accepted polish) | cosmetic | none | touching the same code |
| J. Second-writer/owner-level evidence hardening (L11/L12) | RELEVANT BUT DEFER | results/blockings pair evidence at insert time only and receipts are runtime-grant-protected only; no application path | none | any second writer path, lock narrowing, or evidence-hardening work |
| M2 overlap enforcement | RELEVANT BUT DEFER | see finding M2 | none now | any amendment/rescheduling/republish feature depending on overlap integrity, or any second writer path |
| M3/M4 global API+error-contract cleanup | RELEVANT BUT DEFER **with containment** for the next API-adding slice (section 28) | drift risk on future routes | none | next API-adding slice (containment mandatory); any third-party/plugin SDK consumer work (full cleanup) |

BLOCKING NOW: **none** - no debt item blocks the next feature or the bounded
pilot subject to the listed operator decisions. The health check itself is not
remaining debt; it is completed locally by this report (final confirmation
pending).

## 27. Retention / real employee data

The repository has **not** decided a retention period, and this report does not
invent one. Evidence: `docs/risks-and-open-questions.md:36` lists "Wie lange
bleiben Aufgaben-, Geräte-, Audit- und HR-Daten gespeichert, und wer darf sie
exportieren?" as required **before** "Erster Pilot mit realen Beschäftigtendaten";
R6 (`:14`) frames the audit-vs-minimization tension; `docs/HANDOVER.md:231-232`
records the absence of retention/export jobs and demands policy **before**
destructive cleanup; `docs/roadmap/status.md:37-39` states production use with
real employee data needs operator-specific retention/access/recovery decisions;
ADR 0013 open follow-ups include the retention rule for cancelled shifts
(ADR 0013:74-79). Refusal-evidence policy (`event-system.md` audit contract) is
similarly undecided and unimplemented.

Impact assessment, policy separate from implementation:

- A. Development: **not blocked** - nothing in the current slices needs a
  retention decision.
- B. Synthetic-data pilot: **not blocked** - no real employee data involved.
- C. Real-employee-data pilot: **blocked until decided** - retention/export is
  an operator/product/legal decision and a listed bounded-real-pilot decision
  (section 28). Implementation (cleanup jobs, export workflow) must follow the
  decision, never precede it.

## 28. Bounded pilot readiness

Assumptions reviewed: one company, one site, online operation, self-hosted,
current supported browser/web client, current PostgreSQL/Compose deployment,
no offline guarantee, no HA guarantee.

| Dimension | Assessment | Basis |
| --- | --- | --- |
| Functional readiness | READY | P1b.1-P1b.8 bounded journey DONE with real persistence (`status.md:12-24`); guided work incl. numeric UI ships in the web client (section 22) |
| Security / tenant readiness | READY, subject to M1 disposition if the proxied TLS deployment is used | server-side RBAC + concealment (section 14); Argon2id, hashed tokens, per-request revalidation, no secret logging (section 13); M1 for the Caddy topology |
| Data safety | READY | append-only audit with runtime REVOKE, trigger-immutable evidence/attempts, runtime-grant-protected receipts (L12), atomic audit rollback proofs, least-privilege grants (sections 8/9/15/18) |
| Operational recovery | READY within the documented contract | encrypted backup + isolated restore acceptance, update/recovery acceptance with restore point before migration and fenced recovery - both remotely CI-verified (section 24); replacement activation remains a documented manual operator procedure; no HA claim |
| Observability | ADEQUATE for a bounded pilot | structured JSON logs, request IDs, correlation IDs in audit, readiness endpoint, capacity contention sampling as a harness; no metrics/dashboards (documented boundary, `deployment.md:17`) |
| Device readiness | MATCHES assumption | web runner only; no Android/native acceptance exists and none is claimed (`HANDOVER.md:127-128`) |
| Policy readiness | DECISIONS OUTSTANDING | retention/export, RTO/RPO (`risks-and-open-questions.md:36,39`), supported device/browser list (`:38`), M1 disposition |

**Pilot readiness status (exactly one):**

READY FOR BOUNDED REAL PILOT SUBJECT TO LISTED OPERATOR DECISIONS

Separately: under the reviewed assumptions StoreOS is **unconditionally ready
for a synthetic/internal pilot** (no real employee data, no proxy-dependent
login throttling requirement).

Listed operator decisions for a bounded real pilot:

1. retention/export policy for task, audit and HR data (blocks real-employee
   data use until decided; section 27);
2. RTO/RPO targets per site (`risks-and-open-questions.md:39`);
3. M1 disposition if the documented proxied TLS/Caddy deployment is used
   (accept with direct-exposure or trusted-LAN mitigation, restrict login
   exposure, or schedule the limiter fix before pilot start);
4. supported device/browser list (`risks-and-open-questions.md:38`).

No certification or regulatory compliance is claimed or implied by this report
(consistent with `docs/compliance/overview.md` boundaries and
`HANDOVER.md:243-245`).

## 29. Findings

CRITICAL: **none.** HIGH: **none.** (No destructive data-loss path, no
cross-tenant read/write, no secret compromise, no broken authorization,
transaction, state-machine or idempotency invariant, and no unreliable recovery
claim was found; absence established by the exhaustive inventories in sections
5-20 and the harness reviews in section 24.)

### MEDIUM

**M1 - Login rate-limit identity degrades under the documented reverse-proxy deployment.**
- Evidence: remote key is the raw socket address with no X-Forwarded-For
  handling (`apps/server/lib/src/http/server_app.dart:266-270`); the limiter
  allows 30 failures per remote key per 15 min and 4 concurrent logins
  process-wide (`apps/server/lib/src/application/login_limiter.dart:2-8`); the
  documented LAN TLS topology proxies all `/api/*` through Caddy
  (`infra/reverse_proxy/Caddyfile` `reverse_proxy app:8080`;
  `docs/HANDOVER.md:124-125`); limiter state is process-local
  (`login_limiter.dart:15-17`).
- Consequence: behind the proxy every client shares one 30-failure bucket - any
  actor can lock out all site logins for 15 minutes, and per-IP brute-force
  attribution is void (the per-username 5-failure bucket still works).
- Affected scope: login endpoint under reverse-proxy deployment.
- Pilot impact: none for loopback/direct single-process operation; a decision
  item for a proxied real pilot (section 28, decision 3).
- Recommended disposition: DEFER with an explicit operator decision before a
  proxied real pilot; fix options (trusted-proxy X-Forwarded-For parsing or
  documented exposure restriction) belong to a future slice.
- Reconsideration trigger: enabling the Caddy topology for real users, or any
  multi-process deployment.
- Blocks next feature: NO.

**M2 - Published-shift overlap invariant is application-enforced only.**
- Evidence: overlap detection is a SELECT under the company lock
  (`apps/server/lib/src/workforce/shift_repository.dart:155-166`;
  `workforce_service.dart:91-97`); the only DDL support is a partial index
  (`0006:20`); `protect_published_shift` fires on UPDATE/DELETE only
  (`0011:28-42`), so a direct INSERT with runtime grants could create two
  overlapping published shifts. Several other lifecycle/evidence invariants
  (immutability, state shapes, version increments) additionally have
  trigger/CHECK enforcement; the overlap invariant lacks equivalent DDL-level
  defense (see also L11 for a comparable insert-time-only pairing gap).
- Consequence: under the reviewed single-writer discipline the current
  application behavior is safe; the overlap invariant holds only while all
  writes flow through the lock-serialized application path.
- Affected scope: `shifts` table; publication use case.
- Pilot impact: none (single writer path; does not block the bounded pilot;
  tested race behavior `shift_integration_test.dart:670-679`).
- Recommended disposition: DEFER; close with a DDL exclusion constraint
  (e.g. btree_gist over `(company_id, employee_id, starts_at, ends_at)` for
  `status='published'`) in a future migration **before** any
  amendment/rescheduling feature builds on overlap integrity. Requires its own
  populated-upgrade test.
- Reconsideration trigger: published-shift amendment, rescheduling, series, a
  second writer path, or any narrowing of the company lock (debt A).
- Blocks next feature: NO.

**M3 - API/error contract under-specification without a consistency gate.**
- Evidence: 70 implemented routes match the OpenAPI union 1:1 today
  (70 == 65 + 5; section 20), so the implementation and documentation are
  presently synchronized; but no
  test compares the registered surface to the documents (grep `openapi` across
  all `*.dart`: only 3 spot-check files in `packages/api_contracts/test`, zero
  in `apps/server/test`); ~40 concrete error codes are enumerated nowhere
  (per-operation responses are success + `default $ref` only, e.g.
  `platform.openapi.json:29,54,79`); `openapi.yaml:10-45` re-exports only 18
  platform-API paths (15 platform + 3 plugin); the two documents are mutually
  dependent and neither is
  self-contained; `Context.permissions`/`AuditEntry.actorKind` documented as
  free strings despite fixed catalogs (`platform_database.dart:35-56`;
  `audit_repository.dart:25-27`).
- Consequence: M3 concerns under-specification and insufficient automatic drift
  prevention, not an existing route mismatch (the current bijection is
  70 == 70); future routes or error codes can drift silently through CI, and
  third-party/plugin consumers cannot rely on a documented error contract.
- Affected scope: `packages/api_contracts` documents; all future API work.
- Pilot impact: none for the first-party web client (shared Dart DTOs).
- Recommended disposition: **MEDIUM, deferred as global cleanup - but with a
  mandatory containment requirement**: no standalone remediation cycle is
  required before the next feature; instead any next slice that adds API
  surface must NOT worsen M3 - the new route must ship complete
  request/response/error documentation, its Dart contract and OpenAPI
  representation must match the implementation, its error taxonomy must be
  explicit and tested, and where practical the slice should add a bounded
  reusable route/OpenAPI consistency check. The broader existing
  API/error-contract debt (enumerating all legacy codes, self-contained docs,
  full consistency gate) remains deferred. M3 is explicitly **not** downgraded.
- Reconsideration trigger: the next API-adding slice (containment); any
  external API consumer or plugin SDK work (full cleanup).
- Blocks next feature: NO (containment applies within it).

**M4 - Error-taxonomy inconsistencies across APIs.**
- Evidence: `plugin_limit` maps to 503 on the read path
  (`plugin_service.dart:36-40`) but 409 on the write path (`:65-69`), while
  every other registry limit uses 409 `resource_limit` on both paths
  (`identity_service.dart:35-39,75-79`; `organization_service.dart:38-42,220-224`;
  `people_service.dart:26-30,49-54`); DDL trigger violations (SQLSTATE 23514,
  raised by all immutability triggers, e.g. `0011:40,78,102`) map to 400
  `invalid_request` (`server_app.dart:101-103`), conflating server-invariant
  breaches with client input errors and never yielding 500; concurrent
  duplicate-key races surface as 409 `conflict` (`server_app.dart:100`) while
  prechecks yield 409 `already_exists` (two codes for one user-visible
  failure); unmatched routes return plain-text 404 outside the `ApiError`
  contract (`server_app.dart:55-58`; shelf_router default).
- Consequence: generic client error handling and operational triage are
  complicated; a real invariant bug would appear as a client 400.
- Affected scope: plugins read, all trigger-protected writes, router 404s.
- Pilot impact: none functionally (the first-party client maps by status/code
  defensively, `http_platform_api.dart:79-95`).
- Recommended disposition: DEFER; fold individual corrections into future
  slices touching the same endpoints; the next API slice must not add new
  instances (M3 containment covers documentation of the new route's errors).
- Reconsideration trigger: any external API consumer; any observability/error-
  budget work; next touch of the plugin API.
- Blocks next feature: NO.

### LOW

**L1 - Foreign-repository shortcuts.** `PluginService` uses
`OrganizationRepository` directly (`plugin_service.dart:9,24-25,144,240-244`;
documented debt `HANDOVER.md:229-230`); `IdentityService` repeats the pattern
undocumented (`identity_service.dart:4,11,61`). Consequence: module coupling to
foreign persistence; safe today (same tx, company-scoped, read-only).
Disposition: defer; extend the HANDOVER debt entry to name IdentityService on
next doc touch; never propagate to business modules. Blocks next feature: no.

**L2 - Raw `SELECT clock_timestamp()` in the application/port layer**
(`shift_application.dart:98,236,482,499`; `workforce_service.dart:89`).
Correct DB-clock intent, wrong layer; a `txNow`-style port would remove it.
Disposition: defer; fix opportunistically when the coordinator is next touched.
Blocks next feature: no.

**L3 - Plugin-token expiry uses the app clock while validation uses the DB
clock** (`plugin_service.dart:159` `DateTime.now().toUtc()` vs
`plugin_repository.dart:203` `clock_timestamp()`). Host clock skew could
shorten/extend the 24h validity. The same bounded single-host clock-domain
asymmetry exists for session creation, which computes expiry with the
application clock (`auth_service.dart:112`) while `runAuthorized` validates
against the DB clock (`platform_database.dart:141`). Disposition: defer; align
to the DB clock when plugin/identity code is next touched. Blocks next
feature: no.

**L4 - Admin location-scope inconsistency.** Shift list/get/execution apply no
location predicate (`shift_application.dart:262-269,552-558`) while
blocked/blockings/numbers require `actor.locationId == database.locationId`
with 404 (`:325-330`); OpenAPI describes "same company and configured
location" (`platform.openapi.json:1605`). Latent under today's one-company,
single-location deployment assumptions and not reachable through the current
supported single-company application paths; `requireConfiguredLocation` accepts
any named company location and additional locations are admin-creatable, so this
is a deployment convention rather than a structural invariant. Disposition:
defer; unify when multi-location execution becomes real. Blocks next feature:
no.

**L5 - Unscoped uniqueness/receipt probes** (theoretical cross-tenant existence
oracles if a schema ever hosts multiple companies):
`plugin_repository.dart:51-59`; `identity_repository.dart:39-48`;
`task_template_repository.dart:90-98`; `task_execution_repository.dart:60-68`
(company compared afterwards, `task_execution_service.dart:116-127`). Today the
one-company-per-installation model (`config.dart:107-113`) makes them
unexploitable. Disposition: defer; must be scoped before any multi-company
schema. Blocks next feature: no.

**L6 - Harness safety-code drift.** Failure diagnostics masked only in the
capacity runner (`Run-CapacityMeasurement.ps1:168-181`) vs unmasked log tails in
backup/update runners (`Run-BackupRestoreAcceptance.ps1:143-154`;
`Run-UpdateRecoveryAcceptance.ps1:159-170`), mitigated only by the fixtures'
error-reduction convention; result-file permission inconsistency (`_writeJson`
plain vs `_writeJsonAtomic` without 0600). Disposition: defer; consolidate on
the next harness touch (section 25). Blocks next feature: no.

**L7 - Untested migration-runner refusal branches** (`migration_runner.dart:60-64,69-79,274-280`:
unknown applied migration, non-prefix ledger, invalid filename, empty file).
Search method: grep of `apps/server/test/*.dart` for the exception messages -
zero hits. Reachable only via ledger tampering/renamed files. Disposition: add
cheap unit coverage when migration code is next touched. Blocks next feature: no.

**L8 - `module-boundaries.md` internal event-tense contradiction.** Line 52
states `shift.published.v1` "wird nach Commit ... zugestellt" (present tense)
while line 73 correctly records that no outbox entry exists until a concrete
consumer appears; `event-system.md` example event names do not exist in code
(self-disclaimed). Disposition: documentation precision fix on next touch of
the document. Blocks next feature: no.

**L9 - `organization.company.setup` is emittable but not subscribable**
(whitelist `event_repository.dart:61-72` vs `supportedPluginSubscriptions`
excluding it, `api_contracts platform_plugins.dart:4-8`): setup events always
dispatch to zero eligible plugins. Harmless no-op; dispose when the plugin
subscription catalog is next revised. Blocks next feature: no.

**L10 - Maintenance couplings.** Hardcoded trigger column whitelists
(`0011:35-36,76-77`) mean every future `shifts`/`task_instances` column must be
added to the whitelist arrays or legitimate updates fail; `ShiftApplication`
now hosts 12 use cases (~590 lines, `shift_application.dart:126-588`), accreting
beyond the single-coordinator intent of ADR 0011:13. Disposition: remember in
the next migration/coordinator change; split the facade only with demonstrated
need. Blocks next feature: no.

**L11 - Evidence/version-bump coupling is insert-time only for plain
confirmations and blockings.** Numeric attempts have a deferred commit-time
constraint (`numeric_outcome`, `0010:91-101`) proving a committed attempt is
paired with the matching instance version and outcome. Plain confirmation
results (`0008:56-66`) and blocking evidence (`0009:24-29`) are validated at
INSERT time against `task.version + 1`, but no deferred constraint proves the
corresponding instance version bump actually committed; the runtime role holds
INSERT on these evidence tables (`migration_runner.dart:179-194`). Consequence
under a rogue/second writer that bypasses the application transaction
discipline: trigger-valid evidence can commit without the version bump, causing
later `UNIQUE(instance_id, accepted_version)` conflicts (`0008:14`) or an
unresolved orphan blocking that wedges execution (task-level cancellation
requires `blocked`, `task_execution.dart:26-28`). Scope: no current application
command can produce this (all commands use one transaction under the company
lock); owner-SQL repair remains possible; defense-in-depth/second-writer risk
only, hence LOW. Disposition: does not block the next feature or the bounded
pilot; revisit before any second writer path or lock narrowing. Blocks next
feature: no.

**L12 - Execution receipts lack an all-role immutability trigger.**
`task_execution_commands` (`0007:24-31`; input bound raised in `0008:16-17`) is
protected only by runtime-role grants (`migration_runner.dart:177-183`): unlike
step results, blockings and attempts, no trigger refuses UPDATE/DELETE for every
role, so an owner-level writer could rewrite or delete idempotency receipts.
Scope: runtime/application discipline remains safe and no present application
bug is demonstrated; this is owner/rogue-writer defense-in-depth. Disposition:
does not block the next feature or the bounded pilot; reconsider if the writer
model broadens or evidence-hardening work is undertaken. Blocks next feature:
no.

## 30. Required remediation before next feature

**NONE in production before starting the next feature.**

No standalone remediation cycle is required before the next feature. The next
API-adding feature carries the explicit **M3 containment requirement**
(section 29, M3 disposition): complete route contract, explicit and tested
status/error behavior, matching Dart contract and OpenAPI representation, and
no additional undocumented error-surface drift; where practical a bounded
reusable route/OpenAPI consistency check should be added within that slice.
M1 requires an operator decision only before a proxied real pilot, and M2 only
before overlap-dependent features - neither gates the next feature. The newly
recorded LOW findings L11/L12 (second-writer/owner-level defense-in-depth) do
not change this conclusion.

## 31. Recommended next capability (exactly one)

**Authenticated self-service password change.**

Rationale against the health-check findings: nothing blocks it. The platform
already contains every primitive the slice needs - Argon2id hashing and
constant-time verification (`password_hasher.dart`), the admin-reset reference
flow with version guard, session revocation and secret-free audit
(`identity_service.dart:169-206`), per-request session revalidation under the
company lock (`platform_database.dart:109-156`), and the LoginLimiter used for
login throttling (`login_limiter.dart`). The existing LoginLimiter is wired to
login only (`auth_service.dart:93`); it is not automatically invoked for
verification of a current password, so the slice must explicitly decide
wrong-current-password throttling semantics rather than assuming the login
limiter already covers the operation. It is the smallest
coherent product slice and closes a real operator dependency (employees cannot
change their own passwords today; only an admin reset exists).

Because the slice introduces a new API route, it **must** carry the M3
containment requirement listed in section 30: complete route contract,
explicit status/error behavior (including stale-version, wrong-current-password
and throttling semantics), matching Dart contract and OpenAPI representation,
contract tests, and no additional undocumented error-surface drift. The slice
should also decide its session-revocation semantics explicitly (e.g. revoke all
other sessions vs all sessions) and its audit action name within the existing
`identity.*` conventions. This report deliberately does not design the slice
beyond these boundaries.

No parallel next slices are recommended. M1-M4 and L1-L12 are deferred per
their dispositions and must not be bundled into this slice beyond the M3
containment requirement.

## 32. Documentation corrections applied by this cycle

Only the captured stale-status corrections (section 3) were applied, to exactly
three files after this report was written:

- `docs/HANDOVER.md` - baseline reference `19151f6` -> `512ac64`; "locally
  verified" -> "remotely verified" for the update/recovery acceptance.
- `docs/roadmap/status.md` - assessment baseline -> `512ac64`; the P2
  controlled update/recovery acceptance row moved to the Implemented (DONE)
  table recording independent review APPROVE, commit `512ac64` and remote CI
  verification; the P2 operational-resilience boundary updated from "locally
  verified" to "remotely verified".
- `docs/development/phase-2-update-recovery-acceptance.md` - status block and
  the two "remote CI unverified until pushed" statements updated to record:
  independently reviewed, APPROVE, committed as `512ac64`, remote CI verified.

`docs/README.md`, `docs/architecture/deployment.md` and `docs/roadmap/phases.md`
were verified current and left untouched. No production finding was fixed. This
report records the health check as completed locally with an independent review
performed (CHANGES REQUIRED for report-text precision), corrections applied, a
targeted confirmation review performed which found two remaining report-text
defects, and those defects corrected in this revision; final confirmation is
pending. It does not claim approval or remote verification for itself.

## 33. Acceptance criteria of this health check

All 30 cycle acceptance criteria (baseline verification, clean tree during
evidence collection, module map, transaction/lock inventories, task/shift
lifecycles, numeric invariants, mutation/idempotency matrix, auth/session,
RBAC, tenant scope, audit, outbox, error taxonomy, migrations 0001-0011,
upgrade-path table, route/contract/OpenAPI comparison, Flutter boundaries,
risk-to-test mapping, four harness assessments, duplication disposition, debt
disposition, pilot-readiness conclusion, classified findings with evidence,
exactly one next capability, unchanged production source, docs-only final tree,
update/recovery documentation corrected, no independent-review claim for this
report) are addressed by sections 1-32 and verified in the cycle's final
repository check.
