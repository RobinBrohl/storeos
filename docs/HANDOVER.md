# StoreOS handover

Start here after [AGENTS.md](../AGENTS.md). Baseline: `19151f6`, status updated 2026-10-01.
The incoming tree was clean. This handover does not authorize the next feature.
[Actual status](roadmap/status.md) and [verification](development/handover-verification.md)
distinguish current evidence from plans.

## Product Summary

StoreOS is a self-hosted operating system for site-based businesses. Its first useful
journey connects company, location, employee, shift, versioned instructions, guided
task execution and auditable completion. Inventory, HACCP, POS, finance and AI are
long-term domains, not current functionality. See [vision](vision.md).

## Core Product Principles

- Integrity, authorization and evidence take priority over convenience.
- Support employees; do not infer attendance or automate sanctions from task activity.
- The site operates without a vendor cloud; operators own data and recovery keys.
- One authoritative writer per aggregate; conflicts never silently overwrite evidence.
- Deliver small complete journeys with real persistence and meaningful tests.

The authoritative priority order is in [product principles](product-principles.md).

## Current Architecture

- **Modular monolith:** one Dart backend and PostgreSQL database per installation.
  Logical modules live under `apps/server/lib/src/`, not as deployed services. Flutter
  controllers call HTTP adapters; routes delegate to application services.
  [Overview](architecture/overview.md), [boundaries](architecture/module-boundaries.md),
  [ADRs 0001–0004](adr/README.md).
- **Scope:** one configured company and local execution location. Organization can
  register other locations; that does not enable distributed execution or replication.
  People owns profiles, Identity owns account links, Workforce owns shifts, and Tasks
  owns revisions, snapshots, attempts and execution receipts.
- **Transactions:** `PlatformDatabase.runAuthorized` rechecks rights/session within a
  company advisory lock and PostgreSQL transaction. `ShiftApplication` coordinates
  ports to publish shifts and task snapshots atomically
  ([ADR 0011](adr/0011-atomare-schichtveroeffentlichung.md)).
- **Audit:** relevant changes and audit commit together. Runtime permissions prohibit
  audit update/delete. Minimal audit fields exclude numeric values and detailed blocking
  reasons; audit reads are separately authorized/logged. This does not protect against
  a privileged database owner or establish legal compliance
  ([ADR 0009](adr/0009-audit-trail.md)).
- **Events:** organization outbox, bounded local dispatcher, consumer receipts,
  retry/dead-letter/replay and persistent plugin inbox. No broker or event sourcing.
  Workforce/Tasks emit no speculative integration events without a consumer.
  [Event system](architecture/event-system.md), [ADR 0008](adr/0008-event-system.md).
- **Plugins:** external clients register a manifest and receive explicit organization/
  event read grants and revocable tokens. No downloaded code, in-process plugins,
  business-module write grants or direct database access.
  [Plugin model](architecture/plugin-system.md), [ADR 0012](adr/0012-phase-1-plattform-und-plugin-api.md).
- **Local-first:** local authentication and data with no mandatory cloud. A disconnected
  client cannot persist offline commands; pending retries are in memory. Enterprise sync,
  device queues and ownership transfer remain future contracts.
  [Offline strategy](architecture/offline-strategy.md), [ownership](architecture/data-ownership.md),
  [ADRs 0005/0006/0010](adr/README.md).

## Current Implementation State

P0 and P1 are complete for their bounded single-site/Web scope. P1b.1–P1b.8 implement
employee identity, templates, atomic shift publication, Employee Home, confirmation/
numeric steps, blocking, administrative resume/cancellation and completion, and
pre-execution published-shift cancellation. The real
browser test runs the numeric journey across a replaced API process and a browser page
boundary, and the fixture replays recorded operation IDs against the restarted server;
the merged slice was subsequently verified by the remote CI job.

P1b acceptance/pilot hardening remains active; P2 has operating foundations, a
remotely verified task-aware backup/restore acceptance, a remotely verified
concurrent-work capacity measurement and a locally verified controlled
update/recovery acceptance, but no device-offline implementation. Only a Flutter Web runner is checked in. Published
shifts can be cancelled while every task instance is still open; editing/cancelling
started shifts and cancelling a blocked task are different operations.
There is no automatic priority engine, timezone-aware recurring calendar, timekeeping,
stock ledger or HACCP module. See [status](roadmap/status.md) before claiming completion.

## Repository Structure

| Path | Responsibility |
| --- | --- |
| `apps/server/bin/` | Explicit server, migration and bootstrap entry points |
| `apps/server/lib/src/` | HTTP/configuration, application coordinators, identity/organization/people/workforce/tasks and platform persistence |
| `apps/server/migrations/` | Append-only SQL history 0001–0011; `MigrationRunner` also applies runtime grants |
| `apps/server/test/`, `tool/` | Unit and real PostgreSQL/HTTP tests; isolated browser fixtures |
| `apps/client_flutter/lib/src/` | App composition, controllers, API adapters, UI |
| `apps/client_flutter/test/`, `integration_test/`, `test_driver/` | Unit/widget tests and Web E2E |
| `packages/api_contracts/` | Shared transport types, `openapi.yaml` and `platform.openapi.json` |
| `packages/design_system/` | Small Flutter theme/components |
| `modules/`, `packages/shared/`, `packages/plugin_sdk/`, `plugins/` | Reserved/documented boundaries, not implemented additional runtimes |
| `infra/`, `compose.yaml` | PostgreSQL/container/TLS setup and encrypted backup/isolated restore |
| `scripts/`, `.github/workflows/ci.yml` | Development, E2E and backup-acceptance wrappers, CI checks |
| `docs/` | Vision, implementation contracts, architecture, roadmap, ADRs and compliance |
| `.local/`, `.env` | Ignored secrets, fixtures/logs/configuration; never commit |

## How to Run StoreOS

Use PowerShell 7.4+, Flutter **3.47.5** / Dart **3.13.4** (matching CI), Docker with
Compose and Linux containers. Run from repository root. Initial downloads require
network access; runtime does not require a vendor service.

```powershell
./scripts/dev.ps1 setup
./scripts/dev.ps1 get
./scripts/dev.ps1 db
./scripts/dev.ps1 migrate
./scripts/dev.ps1 bootstrap
./scripts/dev.ps1 server
```

Bootstrap is **first installation only**, not an upgrade step; it refuses a second
run. Setup preserves existing configuration. Preserve `.env`, scope IDs and private
`.local/secrets/` files. Login uses `STOREOS_BOOTSTRAP_USERNAME` and the configured
password file. Do not copy credentials into prompts/reports. Name the organization
after login. In another terminal:

```powershell
./scripts/dev.ps1 client
```

Open `http://127.0.0.1:8085`; API defaults to 8080, database to 5432. Sessions are
in memory; reopening the app requires login. Stop foreground processes with Ctrl+C;
`docker compose stop db` preserves data. Volume deletion is not normal shutdown.
LAN use needs trusted TLS: [Docker](../infra/docker/README.md),
[local TLS](../infra/reverse_proxy/README.md).

**Android:** no Android runner/build/device acceptance exists. Do not advertise an APK
command or generate a runner during unrelated work.

Before tests, create/select a dedicated PostgreSQL test database and set
`STOREOS_TEST_DATABASE` to its owner connection URI in the local shell. Never use the
operating database. E2E additionally requires a name ending `_test` and loopback host.
The runtime role needs access. See [server setup](../apps/server/README.md).

```powershell
./scripts/dev.ps1 check
./scripts/Test-DevSetup.ps1
./infra/backup/Test-BackupCrypto.ps1
./scripts/backup/Test-BackupAcceptanceRedaction.ps1
# Requires the healthy Compose database plus configured .env/secrets:
./scripts/backup/Run-BackupRestoreAcceptance.ps1
./scripts/capacity/Run-CapacityMeasurement.ps1 -Profile smoke
./scripts/capacity/Run-CapacityMeasurement.ps1 -Profile full
./scripts/capacity/Test-CapacityReportRedaction.ps1
# Requires the healthy Compose database plus configured .env/secrets:
./scripts/update/Run-UpdateRecoveryAcceptance.ps1
./scripts/update/Test-UpdateAcceptanceRedaction.ps1
# Requires the configured server/database and valid bootstrap credentials:
./scripts/dev.ps1 smoke
# Requires explicit STOREOS_TEST_DATABASE, STOREOS_DB_USER,
# STOREOS_DB_PASSWORD_FILE and Chrome-matching ChromeDriver:
./scripts/e2e/Run-NumericGuidedWork.ps1 -ChromeDriverPath '<path-to-chromedriver>'
```

`check` runs all four packages' format checks, analyzers and tests, plus Compose
validation. Without test-database configuration, DB tests are skipped and acceptance
is incomplete. E2E creates a new schema, uses real HTTP, verifies task/audit/receipt
evidence and cleans its own fixture. It runs three browser phases: the worker blocks a
task, the API process is replaced, a fresh page resolves and completes the work, and a
further fresh page verifies the completed state; the fixture then replays the recorded
operation IDs through real HTTP, rejects mismatched reuse and drops the schema.

When using a separately installed Chrome (including CI's pinned Chrome), set
`CHROME_EXECUTABLE` to that executable. The E2E runner validates the path and forwards
it as `flutter drive --chrome-binary` so WebDriver uses the browser matching the
selected ChromeDriver instead of discovering a different system installation.
On failure, inspect `flutter-drive-a/b/c`, `fixture-prepare`, `fixture-resume` and
`chromedriver` `.stdout.log`/`.stderr.log` in the reported
`.local/e2e-numeric/<run-id>` directory.
The runner prints the last 60 lines of each named process log on failure, masking
known fixture/database credentials, encoded variants and bearer tokens. Raw logs
and the fixture manifest are not uploaded. `scripts/e2e/Test-E2EDiagnostics.ps1`
checks credential redaction and preservation of error details in CI.
A fixture exit failure can mean the expected workflow outcome was not reached;
it does not by itself prove that schema cleanup failed. Keep the fixture manifest
and credentials private.

For reproducible resolution use `dart pub get --enforce-lockfile` in
`packages/api_contracts` and `apps/server`, and `flutter pub get --enforce-lockfile`
in `packages/design_system` and `apps/client_flutter`, as CI does. The convenience
`dev.ps1 get` uses ordinary `pub get`; review lockfile changes.

Optional release-Web check from `apps/client_flutter`:

```powershell
flutter build web --release --no-web-resources-cdn
```

Use the [backup runbook](../infra/backup/README.md) for encrypted DB backup and isolated
restore commands, and the [acceptance runbook](../infra/backup/acceptance.md) for the
automated restore proof. Restore does not activate a replacement server, recover OS/TLS
secrets or automatically reconcile post-backup account revocations.

## Development Workflow

Follow [workflow and English policy](development/workflow.md): clean tree, branch,
one defined slice, targeted reading, implementation, analyzers/tests, diff review,
manual validation, affected docs, commit, then merge only after acceptance.
Existing German filenames and historical documents need no cosmetic migration.

## Definition of Done

The relevant scope needs persistence, validation, server permissions, atomic audit,
required events, tested migrations, meaningful tests, clear error/loading/empty/conflict
states, working UI and affected documentation. Relevant formatters/analyzers/tests
and smoke checks must pass. Explicitly record skipped/unverified checks. A mock-only
screen or placeholder is not completion.

## Important Invariants

- Never use floating point for money. Future stock changes use movement/ledger
  semantics, not silent balance overwrite ([P4](roadmap/phases.md)).
- Numeric task input is an exact decimal string scaled to thousandths; do not round
  or reinterpret stored evidence. Published revisions and task snapshots are immutable.
- Preserve IDs, replay identity, versions and historical evidence. Audit failure must
  roll back the relevant business change.
- Authorize server-side, including replay/history. Client-supplied actor/company/location
  IDs do not grant authority. Plugins never query core tables or bypass audit/permissions.
- Events cannot replace synchronous consistency or create a second task-generation path.
- Follow actual repository SDK/API versions and current official docs where needed.
  Never weaken tests to make a change pass.

## Known Technical Debt

- `runAuthorized` serializes company operations, including reads. A bounded local
  [capacity measurement](development/phase-2-capacity-measurement.md) exists but is not a
  capacity guarantee; repeat it on target hardware before relaxing the lock, and re-prove
  last-admin, authorization/revocation and command-race invariants.
- P1 `PluginService` directly uses `OrganizationRepository` for scoped reads: a remaining
  public-port shortcut. Do not extend that pattern to business modules.
- No automated audit/outbox/receipt retention job or employee deletion/export workflow.
  Set retention policy before implementing destructive cleanup.
- `cupertino_icons` has no source usage but remains a locked direct dependency.
  Optional removal is housekeeping, not a reason for a major upgrade.
- Target-architecture documents contain future capabilities. Directory names and ADR
  proposals are not evidence of implementation; consult status and slice contracts.

## Known Risks

The current limits are one configured company/local execution site, process-local
login rate limits, in-memory client sessions/retries, no device-offline writes and
no native device validation. Administration is capped at 200 locations, 200 accounts
and 100 plugins. Database-owner powers, retention and recovery remain operator concerns;
there is no external security/compliance certification. PostgreSQL/Caddy image tags and
GitHub Action major tags are not digest/commit pinned. The handover does not prove the
remote Ubuntu CI job or actual WAN-disconnection behavior. See [risk register](risks-and-open-questions.md)
and [verification limits](development/handover-verification.md).

## Next Recommended Work

Proposals only; implement one approved scope at a time.

### 1. Durable P1b browser journey across reload and server restart

- **Goal:** close the gap between app-remount evidence and actual process/browser recovery.
- **Exact Scope:** extend the isolated numeric journey with a literal page reload and
  controlled Dart HTTP process restart against the same data; re-login and verify
  unfinished/completed state, attempts, receipts and audit through real UI/API. Run in CI.
- **Out of Scope:** offline queues, session persistence, product features or new task states.
- **Acceptance Criteria:** state survives both boundaries, retry IDs produce no duplicate
  effects, no in-memory fixture substitutes for persisted results, failed recovery fails
  the run, two independent runs clean up their own resources.
- **Required Tests:** real browser/HTTP/DB recovery E2E, replay and authorization
  regressions, existing analyzers and suites.
- **Status (2026-09-30):** implemented on `slice/p1b-durable-e2e-recovery`, merged into
  `main` as `898c2a1` and verified by the remote CI job
  `numeric-guided-work-e2e`. Three consecutive local runs passed with verified cleanup;
  an injected phase-A failure dropped the isolated schema through the cleanup fallback.

### 2. Automate task-aware backup/restore acceptance

- **Goal:** make recovery of the current employee journey reproducible for operators.
- **Exact Scope:** exercise existing backup/restore scripts with isolated active/completed/
  blocked tasks and numeric evidence; compare snapshots, attempts, receipts and audit;
  check session/plugin-token invalidation and denied runtime access to the restore target.
  Produce a sanitized report, cleanup and runbook.
- **Out of Scope:** production replacement activation, sync reconciliation, new backup
  format, attachment storage or retention deletion.
- **Acceptance Criteria:** encrypted restore preserves task evidence; corrupt backups
  fail; source is unchanged; restored access remains fenced; reports contain no secrets.
- **Required Tests:** real PostgreSQL backup/restore, existing crypto tamper tests,
  source-preservation/access checks and regression suites.
- **Status (2026-09-30):** implemented, independently reviewed, committed to `main` as
  `b94c8e0` and verified by the remote CI job `backup-restore-acceptance`. See
  [P2 restore acceptance](development/phase-2-restore-acceptance.md).

### 3. Measure single-site concurrent-work capacity

- **Goal:** establish pilot-sizing evidence before changing locks or deployment.
- **Exact Scope:** a bounded opt-in harness using existing APIs/generated employee tasks;
  measure concurrent read/execute latency, failures and lock contention on a documented
  machine/profile; verify final counts/versions/audit and record the measured envelope.
- **Out of Scope:** lock refactors, new roles, caches, microservices or product dashboards.
- **Acceptance Criteria:** repeatable setup/cleanup, declared data/concurrency, latency/error
  report and no lost/duplicated evidence. Optimizations require a separate scope; timing
  results are measurements, not flaky CI thresholds or promises for larger sites.
- **Required Tests:** small harness smoke, concurrent real HTTP/DB integrity checks,
  existing authorization/race regressions and analyzer checks.
- **Status (2026-09-30):** implemented, independently reviewed, committed to `main` as
  `8a58226` and verified by the remote CI run (including the capacity report redaction
  check). Local evidence: smoke profile, two consecutive full runs with identical
  integrity verdicts, injected integrity and operational failure runs, real-PostgreSQL
  smoke test and report-redaction check. See
  [P2 capacity measurement](development/phase-2-capacity-measurement.md).

### 4. Cancel a published shift before execution starts

- **Goal:** let an administrator retract a wrongly published shift while no work has
  started, without reconciling started work.
- **Exact Scope:** one authorized transaction cancelling the shift and every still-open
  instance with reason, cancellation evidence, audit and strict version-based retry;
  Employee Home exclusion and admin cancelled-state display.
- **Out of Scope:** editing published shifts, partial/per-task cancellation, in-flight
  reconciliation, series, notifications, offline behavior, new capabilities or events.
- **Acceptance Criteria:** every task must still be open or the whole request is refused
  with no writes; state, evidence and audit commit atomically; interval is freed;
  exact retries are side-effect free; other scopes are denied server-side.
- **Required Tests:** real PostgreSQL migration upgrade, success/refusal matrix,
  idempotency, authorization, overlap, concurrency and rollback injection; contract,
  controller/widget and numeric E2E regressions.
- **Status (2026-10-01):** implemented, independently reviewed with fixed findings,
  re-reviewed with APPROVE, committed to `main` as `19151f6` and verified by the
  remote CI job. Local evidence: contract/server/Flutter suites, migration upgrade,
  rollback and lock-contention races, unchanged numeric browser E2E. See
  [P1b.8 shift cancellation](development/phase-1b-8-shift-cancellation.md) and
  [ADR 0013](adr/0013-published-shift-cancellation.md).
