# Local development

This is the canonical detailed setup and check guide for the supported single-site/Web development environment. Commands below are retained from the existing handover; execute from the repository root unless a package directory is stated. SDK versions are pinned by the repository/CI (Flutter 3.47.5, Dart 3.13.4). Resolve dependencies only when the current task authorizes it; audit tasks can use existing packages with `--no-pub`.

Production operation follows [deployment](../architecture/deployment.md), [Docker](../../infra/docker/README.md), [TLS](../../infra/reverse_proxy/README.md) and [backup/restore](../../infra/backup/README.md). Setup does not establish production readiness or legal compliance.

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
LAN use needs trusted TLS: [Docker](../../infra/docker/README.md),
[local TLS](../../infra/reverse_proxy/README.md).

**Android:** no Android runner/build/device acceptance exists. Do not advertise an APK
command or generate a runner during unrelated work.

Before tests, create/select a dedicated PostgreSQL test database and set
`STOREOS_TEST_DATABASE` to its owner connection URI in the local shell. Never use the
operating database. E2E additionally requires a name ending `_test` and loopback host.
The runtime role needs access. See [server setup](../../apps/server/README.md).

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

Use the [backup runbook](../../infra/backup/README.md) for encrypted DB backup and isolated
restore commands, and the [acceptance runbook](../../infra/backup/acceptance.md) for the
automated restore proof. Restore does not activate a replacement server, recover OS/TLS
secrets or automatically reconcile post-backup account revocations.

## Current verification boundaries

Use [actual status](../roadmap/status.md) for delivered scope and the [2026-10-04 audit](project-health-audit-2026-10-04.md) for checks already performed in this session. Test counts in dated reports describe those runs; they are not new verification after documentation edits.

The current `/ready` implementation checks the early platform migration subset 0001–0004, not every migration required by the current binary. Apply all migrations before starting a new binary; a green readiness response alone is not proof of full schema compatibility. See F08 in [technical debt](technical-debt.md).

Behind a reverse proxy, the login limiter currently keys on the proxy's socket address. Decide and test the M1 mitigation before a proxied real-user pilot; do not assume arbitrary forwarded headers are trusted.

The normal development database must not be used for destructive acceptance fixtures. Each acceptance harness has its own isolated, fenced scope. Restored targets remain fenced until the documented operator activation procedure is completed.

## Configuration, upgrades and daily use

The development scripts parse `.env` without shell evaluation and resolve relative secret paths against the repository. Explicit environment variables take precedence. Direct Dart invocations do not load `.env` automatically. The bootstrap password is a private local file; sessions and pending client commands are memory-only and a page reload requires login.

For upgrades, stop the server, preserve configuration/secrets and take a verified backup, apply new migrations, then update the server and Web client together. Do not bootstrap again or edit applied migrations. Old clients may not understand numeric steps or newer states. See the relevant [phase records](../README.md#slice-contracts-and-evidence) for migration-specific preservation and compatibility rules.

Organization setup precedes profile/template/shift administration. Link an active same-site Account to an Employee and assign the account role separately; linking, unlinking and deactivation revoke affected sessions. Employee Home (**Meine Arbeit**) supports own shifts and guided tasks. Current shift UI uses explicit UTC. Numeric steps allow comma or point input, at most three decimal places and no unit conversion; an out-of-bounds attempt blocks completion until an administrator resolves it and a new valid attempt is submitted. Completed/cancelled evidence remains preserved.

The Compose reference separates restricted runtime `storeos` from migration/bootstrap owner `storeos_owner`; the HTTP process receives no owner secret. Initialization scripts run only on an empty PostgreSQL volume. Editing a secret file does not rotate an existing database password.

Stop processes with Ctrl+C and stop the database without removing its volume. Volume deletion is destructive and is not the ordinary stop procedure. Preserve IDs and secrets across restarts.

The numeric browser runner is `./scripts/e2e/Run-NumericGuidedWork.ps1 -ChromeDriverPath '<matching chromedriver path>'`. It requires a dedicated `*_test` database, explicitly supplied owner/runtime configuration and a matching Chrome/ChromeDriver; it does not load the normal site's configuration. See [numeric verification](phase-1b-7-numeric-verification.md) for isolation, diagnostics and lifecycle boundaries.

Update/recovery acceptance uses `./scripts/update/Run-UpdateRecoveryAcceptance.ps1` and an isolated database. The current fixture probes the migration chain through 0015. See [update/recovery](phase-2-update-recovery-acceptance.md) for exact supported scenarios and failure injection; recovery is an isolated restore point, not a down migration or automatic replacement activation.

Some wrapper commands resolve dependencies unconditionally. Inspect the wrapper before using it in a task that forbids installs; use existing SDK package commands with `--no-pub` where appropriate instead.
