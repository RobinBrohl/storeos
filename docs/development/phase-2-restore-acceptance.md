# P2: Task-aware encrypted backup/restore acceptance

Status: implemented, independently reviewed, committed to `main` (`b94c8e0`)
and verified by the remote CI job `backup-restore-acceptance`.

## Verbindlicher Umfang

The slice adds an opt-in acceptance that exercises the existing encrypted
backup and isolated restore scripts against an isolated database containing the
bounded employee journey. It is defined by
[historical HANDOVER proposal item 2](handover-snapshot-2026-10-03.md#next-recommended-work)
and the [acceptance runbook](../../infra/backup/acceptance.md).

In scope:

- optional, backward-compatible `-Database` parameter for
  `infra/backup/Backup-StoreOS.ps1` plus an additive `sourceDatabase` manifest
  field;
- an isolated fixture (`apps/server/tool/backup_restore_fixture.dart`) that
  migrates, bootstraps and serves a run-scoped database with the real StoreOS
  API, seeds one shift with three tasks (`in_progress`, `blocked` after a
  rejected numeric attempt, `completed` after an accepted numeric attempt and a
  confirmation), approves one plugin with an active token and leaves one active
  admin session;
- a runner (`scripts/backup/Run-BackupRestoreAcceptance.ps1`) that creates and
  grants the source database, runs the real backup and restore scripts,
  compares source and restored evidence and identity sequences, verifies
  revocation and runtime fencing (catalog plus a real connection attempt),
  rejects a tampered backup, writes a sanitized report and cleans up;
- a sanitized-report guard and its redaction regression test;
- a CI job `backup-restore-acceptance` and the
  `Test-BackupAcceptanceRedaction.ps1` check in the existing `dart` job.

Out of scope: production replacement activation, sync reconciliation, new
backup format or crypto changes, attachment/file/TLS/secret backup, retention
or deletion jobs, product API/UI/permission/audit/event/migration changes.

## Implementierung

`Backup-StoreOS.ps1` accepts an optional `-Database` identifier, validates it
against `^[a-z][a-z0-9_]{0,62}$`, passes it as a positional shell argument to
the unchanged `pg_dump` invocation and records it as `sourceDatabase` in the
manifest. Without `-Database` the command, manifest fields, encryption, key
handling and restore semantics are byte-for-byte unchanged.

The fixture uses the documented owner/runtime-role split: the owner role
migrates, bootstraps and verifies; the restricted runtime role serves the API
and is used for the fencing connection attempt. Evidence is captured as
deterministic per-table row counts and `md5` hashes over `row_to_json` with
explicit ordering, a UTC session time zone and identical column definitions.
Sequences are compared through `last_value`/`is_called`.

The runner treats every destructive action as run-scoped: database names are
generated and pattern-checked, drops require membership in the run's own name
list, and the normal StoreOS database is only checked for existence. Cleanup
runs in `finally`, including after injected failures. The report is rejected if
it contains database URLs, bearer tokens, secret-like keys, private-key markers
or known secret values.

No ADR is required: no production code, schema, permission or event contract
changed. The added PowerShell/Dart tooling uses existing infrastructure.

## Lokaler Prüfnachweis (2026-09-30)

Environment: Windows, PowerShell 7.6.6, Dart 3.13.4, Docker 29.8.0 with Compose
v5.5.1, PostgreSQL 17 Compose service, repository `.env` and `.local/secrets`
preserved. Reports (sanitized) remain under `.local/backup-acceptance/<run-id>/`.

| Check | Result |
| --- | --- |
| Acceptance run 1 (`6f6a1e64f2a44027`) | PASS |
| Acceptance run 2 (`196b430852e748fd`) | PASS |
| Acceptance run 3, final revision (`9028e1b05194484f`) | PASS |
| Acceptance run 4, final revision (`c588a4121ef547d0`) | PASS |
| Injected failure after `prepare`, final revision (`9d80629403a64471`) | expected exit 1; cleanup PASS |
| `scripts/backup/Test-BackupAcceptanceRedaction.ps1` | PASS |
| `infra/backup/Test-BackupCrypto.ps1` | PASS |
| `scripts/dev.ps1 check` with `STOREOS_TEST_DATABASE` | 233 tests PASS (contracts 31, server 92, design system 2, client 108) |
| `scripts/Test-DevSetup.ps1` | PASS |
| `scripts/e2e/Test-E2EDiagnostics.ps1` | PASS |
| Numeric guided-work browser E2E | PASS |

Runs 3 and 4 are two consecutive full runs on the final revision; runs 1 and 2
preceded only a report-label change. All four runs produced identical seeded
evidence and identical source/restore hashes:

| Evidence | Count | Match |
| --- | ---: | --- |
| `shifts` | 1 | yes |
| `task_template_revisions` | 3 | yes |
| `task_instances` | 3 (one `in_progress`, one `blocked`, one `completed`) | yes |
| `task_step_results` | 2 | yes |
| `task_numeric_attempts` | 2 (one accepted, one rejected) | yes |
| `task_blockings` | 1 | yes |
| `task_execution_commands` | 7 | yes |
| `audit_entries` | 31 | yes |

Identity sequences (`audit_entries_id_seq`, `plugin_inbox_id_seq`) matched.
Source access state after restore was unchanged (1 active session, 1 active
plugin token); the restored database had 0 and 0, denied runtime `CONNECT`, and
rejected a real runtime-role connection. A byte-flipped backup with a recomputed
outer manifest checksum was rejected, and its incomplete target was dropped.
Cleanup removed the run's source and restore databases, confirmed the normal
`storeos` database still exists, freed port 8097 and left only `report.json`.

The injected-failure run exited non-zero at `prepare`, dropped the seeded source
database, left no restore database, kept the normal database and port state and
left only its `report.json`.

## Acceptance Criteria

Locally verified:

- wrapper exits 0 on a correctly configured host; non-zero on any failed step;
- seeded journey matches the approved counts and states;
- restored counts, canonical hashes and sequence state equal the source;
- restored sessions/tokens are revoked and runtime access is denied, including a
  real rejected connection;
- source evidence is unchanged and no restore object exists inside the source;
- tampered backup rejected and its target removed;
- successful and injected-failure runs leave no acceptance databases or
  temporary sensitive artifacts;
- report contains no secrets or raw rows;
- existing StoreOS checks remain green;
- CI job added.

Independent review and remote CI execution completed (`b94c8e0`); the
`backup-restore-acceptance` CI job passed on the Linux runner.

## Verbleibende Grenzen

- Restores database evidence only; no attachments, TLS, configuration, plugin
  versions, replacement activation or sync reconciliation.
- Post-backup account revocations/deletions are not re-applied automatically.
- The acceptance depends on Docker Compose and the pinned Dart SDK; it is not a
  product runtime dependency.
- Local Windows evidence plus the executed Linux CI job.
