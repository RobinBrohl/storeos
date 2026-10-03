# P2: Controlled update/recovery acceptance

Status: implemented, independently reviewed with APPROVE, committed to `main` as
`512ac64` and verified by the remote CI job `update-recovery-acceptance`.
Local evidence: two consecutive full runs plus prepare, post-upgrade and
recovery failure injections.

Update (2026-10-03, committed as part of P1b.9 `f37dd6b`): the same runner and
fixture were extended to the current migration chain. It applies exactly
`0011` and `0012`, verifies the amendment evidence columns and the
`shifts_published_no_overlap` exclusion constraint, proves that a raw
overlapping published interval is rejected on the upgraded database, and runs a
real HTTP interval amendment against the upgraded server. Independent review
returned APPROVE and the remote CI run passed; the historical `0010→0011`
evidence above is unchanged.

Update (2026-10-03, committed with P4.1 as `a4aeecd` and corrected by
`d0fcf43`/`d90dd7e`): the same runner and fixture now apply exactly `0011`,
`0012` and `0013`, probe the article table, uniqueness indexes and runtime
grants, and create and read a real HTTP article on the upgraded server. The
historical `0010→0011` and `0010→0012` evidence above is unchanged; remote CI
run 31 on `d90dd7e` passed.

Update (2026-10-03, P4.2 working tree, uncommitted): the same runner and fixture
now apply exactly `0011`–`0014`, additionally probe the
`article_location_assortment` table, its pair/page indexes and runtime grants,
and create and read a real HTTP assortment membership on the upgraded server.
A local acceptance run (`fb710b7ac2c249a9`) passed with intact isolated recovery
fencing and a sanitized report; the historical `0010→0011`, `0010→0012` and
`0010→0013` evidence above is unchanged. Independent review and remote CI for
this extension are pending.

This slice proves the supported single-site update/recovery contract on populated
pre-update data. It is an acceptance and operating-evidence slice: it changes no
product behavior, adds no migration and promises no downgrade.

## Exercised contract

Terminology: **recovery** means restoring the encrypted pre-update restore point
into a NEW isolated database and proving its contents and safety fencing. It does
not mean a database or application downgrade.

Supported and proven by the acceptance:

- offline/quiesced update with a required encrypted PostgreSQL restore point
  created before migration;
- forward-only migration through the production `MigrationRunner`, including
  checksum, unknown-migration and known-prefix validation;
- single-transaction application of all pending migrations;
- preservation of pre-update evidence across the schema change;
- the current application serving an upgraded database;
- isolated recovery of the pre-update database from the restore point;
- recovery fencing: no active sessions, no active plugin tokens, no runtime
  `CONNECT`, and a real rejected runtime connection;
- operator-verifiable, sanitized evidence.

NOT supported and NOT proven by this slice:

- down migrations or any schema downgrade;
- application downgrade;
- restoring over the operating database;
- automated activation of a restored database as production;
- production failover, high availability or zero-downtime updates;
- attachments, TLS certificates, configuration files or external secrets;
- retention or multi-site coordination.

## Scope

In scope:

- `apps/server/tool/update_recovery_fixture.dart`, a run-scoped fixture with four
  modes: `prepare` (apply exactly `0001-0010` from byte-identical repository
  migration copies, bootstrap identity, seed representative 0010 evidence,
  capture stable projections), `upgrade` (apply the real pending `0011` with the
  production runner, verify checksums, idempotency, preservation and the new
  protections), `smoke` (start the current server on the upgraded database with
  the restricted runtime role and run a bounded real HTTP smoke), and `recovery`
  (verify the isolated restore target and the independence of the upgraded
  source);
- `scripts/update/Run-UpdateRecoveryAcceptance.ps1`, which creates the strictly
  named run databases, invokes the real backup and restore scripts, orchestrates
  the fixture modes, supports bounded failure injection, writes a sanitized
  report and cleans up run-owned resources;
- `scripts/update/Assert-UpdateAcceptanceReport.ps1` and
  `scripts/update/Test-UpdateAcceptanceRedaction.ps1`;
- a dedicated CI job and a redaction check in the existing Dart job.

Out of scope: production operator tooling (`Update-StoreOS.ps1`), replacement
activation, online/zero-downtime updates, attachments/TLS/config/secrets backup,
retention, device/offline behavior, product API/UI/permission/audit/event/schema
changes and dependency changes.

## Pre-update schema and seed

The fixture copies repository migrations `0001-0010` byte-for-byte into a
run-scoped temporary directory, verifies each copy and its checksum, and applies
them through the production `MigrationRunner`. The temporary directory is removed
during cleanup. The current server is deliberately never started against the 0010
database because its queries expect the 0011 cancellation columns.

Because the pre-update database cannot be served by the current code, the seed is
deterministic owner-side SQL against the real 0010 schema. It is minimal but
representative:

| Evidence | Seeded state |
| --- | --- |
| Identity | company, location, bootstrap admin, linked employee account |
| Shifts | one all-open published shift; one published shift with execution history |
| Task instances | `open`, `in_progress`, `blocked`, `completed`, blocked-origin `cancelled` |
| Execution | 2 step results, 2 numeric attempts (accepted and rejected), 2 blockings, 11 command receipts |
| Audit | 13 history entries plus the bootstrap audit entry |
| Access | 1 active session and 1 active plugin token for restore fencing |

## Preservation model

Migration 0011 adds cancellation columns to `shifts` and `task_instances`. The
acceptance therefore hashes an explicit **stable pre-0011 projection** for those
tables (the columns that existed in 0010) and a full projection for unaffected
tables. Immediately after the upgrade it verifies:

- the stable projections and sequence state are identical to the pre-update
  snapshot;
- the six new 0011 columns exist;
- all legacy rows keep NULL cancellation fields;
- the new status/state constraints and shift/instance triggers exist;
- invalid direct writes are rejected and leave no change:
  published-shift cancellation evidence without the transition, a cancellation
  without evidence, and unstarted cancellation evidence on a blocked-origin
  cancelled instance.

Whole-row equality across the schema change is explicitly not claimed.

## Upgrade and HTTP smoke

The upgrade phase asserts that exactly one migration (`0011`) is applied, that a
second runner invocation applies none, and that all stored checksums match the
repository files. Only then does the smoke phase start the current `ServerApp`
against the upgraded source with the restricted runtime role on loopback and
verify:

- `/ready`;
- admin and employee login;
- the migrated evidence shift and all four execution states;
- Employee Home showing the migrated all-open published shift;
- pre-execution cancellation of that shift through the real P1b.8 API, including
  persisted shift/task versions and shared-correlation audit entries.

The smoke mutation is deliberately excluded from the preservation comparison.

## Recovery verification

The runner restores the pre-update restore point with the existing
`infra/backup/Restore-StoreOS.ps1` into a new `storeos_restore_upd_*` database.
The recovery phase verifies:

- exactly `0001-0010` and no 0011 column in the recovered target;
- recovered stable projections and sequence state equal the pre-update snapshot;
- no post-upgrade cancellation effect exists in the target;
- sessions and plugin tokens are revoked, runtime `CONNECT` is denied and a real
  runtime connection is rejected;
- the upgraded source still contains migration 0011 and the smoke cancellation
  evidence, and source/target are distinct databases.

The current server is never started against the recovered 0010 target.

## Assertion of migration atomicity

This acceptance proves successful forward application, preservation,
checksum/prefix behavior and idempotency. It does **not** prove rollback of a
failed migration; the `upgrade` failure injection occurs after the migration has
committed and is reported as a post-upgrade operational failure. Transactional
rollback of failed migration runs is covered by the existing server test
"failed migration rolls back all SQL in that run" in `postgres_integration_test.dart`.

## Commands

```powershell
# Requires the healthy Compose database plus configured .env/secrets.
./scripts/update/Run-UpdateRecoveryAcceptance.ps1
./scripts/update/Run-UpdateRecoveryAcceptance.ps1 -InjectFailureAfter prepare
./scripts/update/Run-UpdateRecoveryAcceptance.ps1 -InjectFailureAfter upgrade
./scripts/update/Run-UpdateRecoveryAcceptance.ps1 -InjectFailureAfter recovery
./scripts/update/Test-UpdateAcceptanceRedaction.ps1
```

The runner uses loopback API port 8099 and refuses to run while it is occupied. It
never starts, stops or recreates the Compose service.

## Report and cleanup

The sanitized report is kept at `.local/update-recovery/<run-id>/report.json`.
It records the run result, failed step, injection description, contract
boundaries, migration ranges and checksums status, preservation and protection
verdicts, smoke and recovery verdicts, the restore-point hash and its deleted
status, and the cleanup verdict. It never contains database URLs, credentials,
tokens, keys, raw rows or decrypted content.

Cleanup runs on success and on every injected failure. Only the run's own
strictly named databases may be dropped; the normal StoreOS database is only
checked for existence. The fixture manifest (which holds the generated test
passwords), result files, encrypted restore point, manifest and fixture logs are
removed; only the sanitized report remains.

## Safety boundaries

- Source database: `storeos_update_<16 lowercase hex>`, owned by this run.
- Recovery target: `storeos_restore_upd_<16 lowercase hex>`, owned by this run.
- Every destructive database operation requires both the strict name pattern and
  membership in the run's owned-name set; cleanup fails closed.
- The operating `storeos` database is never an update source, migration target,
  seed target, backup source, restore target, smoke target or cleanup target.
- Another run's or a historical restore database can never be removed.
- `docker compose down -v` is never used.

## Local verification (2026-10-01)

Environment: Windows 11 Pro, Dart 3.13.4, PostgreSQL 17 via the repository Compose
service, repository `.env` and `.local/secrets` preserved. Sanitized reports
remain under `.local/update-recovery/<run-id>/`.

| Check | Result |
| --- | --- |
| Full acceptance run 1 (`c3df0e72f6d849e8`) | PASS |
| Full acceptance run 2 (`1e8b8e7a09c14573`) | PASS |
| Prepare failure injection (`027087826fe04392`) | expected exit 1; cleanup PASS |
| Post-upgrade failure injection (`6fc451ec21c94d83`) | expected exit 1; cleanup PASS |
| Recovery failure injection (`9dc39b1855b643ca`) | expected exit 1; cleanup PASS |
| `scripts/update/Test-UpdateAcceptanceRedaction.ps1` | PASS |
| `infra/backup/Test-BackupCrypto.ps1` | PASS |
| `scripts/backup/Test-BackupAcceptanceRedaction.ps1` | PASS |
| `scripts/e2e/Test-E2EDiagnostics.ps1` | PASS |
| `scripts/backup/Run-BackupRestoreAcceptance.ps1` | PASS |
| `scripts/dev.ps1 check` with isolated `STOREOS_TEST_DATABASE` | PASS |

Both full runs verified the same contract: byte-identical 0010 prefix, encrypted
restore point before 0011, exactly 0011 applied, second migration run applied
zero, stable projections and sequences preserved, new 0011 protections rejecting
invalid writes, current-server smoke including P1b.8 cancellation, recovery at
exactly 0010 with equal pre-update evidence and fencing, upgraded source
unchanged by recovery, and complete cleanup.

## Acceptance criteria

Numbered criteria are tracked in the slice review; locally verified behavior:

1. the wrapper exits 0 on a correctly configured full run;
2. only a run-owned `storeos_update_*` database is prepared and upgraded;
3. the source initially contains exactly `0001-0010` with repository checksums;
4. the declared representative 0010 evidence exists;
5. the encrypted restore point is created before migration 0011;
6. the production runner applies exactly 0011;
7. a second migration run applies zero;
8. `schema_migrations` afterwards is exactly `0001-0011` with matching checksums;
9. stable pre-0011 projections remain identical after migration;
10. new 0011 fields exist with the expected NULL state on legacy rows;
11. invalid writes prove the new 0011 protections are active;
12. the current server starts only on the upgraded 0011 source with the runtime
    role;
13. the real HTTP smoke succeeds, including P1b.8 pre-execution cancellation;
14. the restore point restores into a NEW isolated target at exactly `0001-0010`;
15. the recovered target's canonical pre-update evidence equals the snapshot;
16. the recovered target is fenced according to the existing restore semantics;
17. the current server is never started against the recovered 0010 target;
18. the upgraded source remains at 0011 with its smoke evidence;
19. the normal StoreOS database is never read beyond an existence check;
20. no run-created database, process, listener, temporary migration directory or
    sensitive artifact remains after success or injected failure;
21. the sanitized report contains no secrets or raw rows and states the recovery
    boundary;
22. existing regression checks remain green;
23. the CI job exists and the remote CI job passed.

## Remaining limits

- Restores database evidence only; attachments, TLS, configuration, plugin
  versions, secret recovery and replacement activation are not covered.
- Post-backup account revocations/deletions are not re-applied automatically;
  they remain operator decisions.
- The acceptance depends on Docker Compose and the pinned Dart SDK; it is not a
  product runtime dependency.
- Production updates are still an operator procedure; no `Update-StoreOS.ps1`
  tooling is provided by this slice.
- Local Windows evidence plus the CI job; remote CI verified.
