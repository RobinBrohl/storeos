# P4.3 — Manual stock foundation

Current status (2026-10-04): **DONE/CLOSED**. Foundation `e8ce8c3` and acceptance
correction `f9c8b07` are committed on `main`; independent targeted review **APPROVE**,
**28/28 PASS**, and all five changed-commit CI jobs are green. See the
[final closure](#final-acceptance-closure--2026-10-04) for full commit IDs and evidence.
The dated implementation, failure, pending-review and verification records below
are historical; their earlier ACTIVE/uncommitted statements are superseded by
the final closure without changing the original evidence.
Original implementation baseline: committed P4.2 `3bc27d5`.
Related: [ADR 0017](../adr/0017-manual-stock-foundation.md),
[ADR 0016](../adr/0016-article-location-assortment.md),
[ADR 0015](../adr/0015-company-wide-article-master.md),
[P4.2](phase-4-2-location-assortment.md).

## Scope

The new logical `stock` module provides exactly one stock level per company
article and location, opening of the first recorded quantity, a location-scoped
current-stock list/search, absolute manual corrections, immutable movement
history and the Flutter **Bestand** section. Migration `0015` is additive and
contains the released inventory projection view plus the two stock tables.

Deliberately **not** included: receiving, waste, stocktake/count workflow,
sales, transfers, valuation, prices, suppliers, purchase orders, batch/MHD,
unit catalog, unit conversion, pack sizes, recipes, events/outbox, plugins and
offline queues. `unit` remains an uninterpreted label.

## Ownership and read ports

`stock` owns `StockLevel` and `StockMovement` only. Inventory keeps `Article`
and `ArticleLocationAssortment` unchanged and releases:

- the read-only view `inventory_article_location_projection`
  (`company_id, location_id, article_id, sku, barcode, name, unit,
  article_is_active, assortment_is_active`), which stock may join;
- `InventoryArticlePort.findArticle`, a minimal public Dart port used to
  distinguish an unknown article (404) from a known article without membership
  (409 `not_in_assortment`) and to read the normalized unit for the opening
  snapshot.

Stock never joins inventory base tables. Stock list/search is one complete
stock-level query joined against the view, keyset-paginated over stock level
ids (50 per page, malformed `after` → 400 `invalid_cursor`); there is no
pre-truncated article candidate set, so every matching level remains reachable.

## Data model (migration 0015)

`stock_levels`:

- `id uuid PK`, `company_id`, `location_id`, `article_id`
- immutable `stock_unit` (1–32 chars, trimmed, no control characters)
- `quantity_scaled bigint` `CHECK 0 … 999999999999999`
- `version bigint DEFAULT 1 CHECK > 0` (equals the latest movement version)
- `created_at`, `updated_at`
- `UNIQUE (company_id, location_id, article_id)` (scope; concurrent-open
  backstop), `UNIQUE (id, company_id, location_id, article_id)` (movement
  binding anchor)
- composite FKs to `articles(id, company_id)` and `locations(id, company_id)`
  `ON DELETE RESTRICT`
- index `(company_id, location_id, id)`

`stock_movements`:

- `id uuid PK` (client-generated operation identity for adjustments)
- `stock_level_id`, `company_id`, `location_id`, `article_id`
- `kind text CHECK IN ('opening','adjustment')`
- `delta_scaled` `CHECK ±999999999999999`, `balance_after_scaled`
  `CHECK 0 … 999999999999999`, `balance_version bigint CHECK > 0`
- `recorded_at`, `recorded_by uuid REFERENCES accounts(id)`, nullable `note`
  (1–500 runes, trimmed, no control characters)
- `UNIQUE (stock_level_id, balance_version)` — the history paging order
- full-scope FK `(stock_level_id, company_id, location_id, article_id)` to
  `stock_levels`, so a movement can never claim another scope

The account table has no `(id, company_id)` unique anchor and the Account
aggregate is not altered for this slice; the single-column actor FK plus the
revalidated company lock is the supported binding.

## Ledger and projection invariant

`stock_movements` is authoritative; `stock_levels` is the transactionally
maintained projection. For every supported writer:

```
stock_levels.quantity_scaled == latest movement.balance_after_scaled
                             == SUM(movement.delta_scaled)
stock_levels.version        == latest movement.balance_version
```

Opening creates level v1 and exactly one server-generated opening movement
(`delta == balanceAfter == quantity`, `balance_version = 1`). An adjustment
stores `delta = target − current`, `balanceAfter = target` and the new
`balance_version`. Ordering never uses `recorded_at`.

## Quantity contract

Scale 3, canonical decimal strings only (no JSON floating point):

- target/balance grammar `^[0-9]{1,12}(\.[0-9]{1,3})?$`
- signed delta grammar `^-?[0-9]{1,12}(\.[0-9]{1,3})?$`
- maximum scaled magnitude `999999999999999` (`999999999999.999`), below
  `2^53 - 1`; parsing/formatting use integer arithmetic only
- the P1b.7 six-integer-digit task-measurement bound is deliberately not copied

## Commands and operation identity

Open: `POST /api/v1/platform/locations/{locationId}/stock` with
`{id, articleId, quantity, note}`. `note` is a required key and may be `null`;
a non-null note must be non-blank. The gate requires an existing article
(404), a globally active article (`409 article_inactive`) and an active
assortment membership (`409 not_in_assortment` for absent or inactive); a
duplicate id or pair is `409 already_exists` with zero writes. `stockUnit`
snapshots the current normalized `Article.unit`.

Adjust: `POST .../stock/{levelId}/adjust` with
`{movementId, expectedVersion, quantity, note}`; `note` is required and
non-blank. Before stale-version handling the service looks up `movementId`:

- exact replay (same level/company/location/actor/`expectedVersion`/target/note)
  → 200 with the current authoritative level, no new movement, version bump or
  audit — even after later movements;
- any other reuse → `409 operation_conflict`, zero writes;
- otherwise a matching-version target equal to the current quantity is a no-op
  (no movement, version bump or audit; the movement id stays unused);
- a stale version → `409 stock_conflict`; a real adjustment writes one
  immutable movement and audits `stock.level.adjusted`.

Opening uses the client-generated level id as its operation identity; a lost
response is confirmed by reading the route-scoped level id and matching
`articleId`, not by comparing the current quantity.

## Audit

`stock.level.opened` audits `{articleId, movementId, version}`;
`stock.level.adjusted` audits
`{articleId, movementId, oldVersion, version, changedFields: ['quantity']}`.
Quantity, delta and note are never audited; the ledger is the numerical
evidence. `movementId` was added to the audit allowlist. Audit and business
changes commit in the same authorized transaction.

## API and errors

Five routes (`stock.levels.manage`, admin only, server-side revalidated):

| Route | Statuses |
| --- | --- |
| `GET .../stock` | 200, 400, 401, 403, 404, 500, 503 |
| `POST .../stock` | 201, 400, 401, 403, 404, 409, 413, 415, 500, 503 |
| `GET .../stock/{levelId}` | 200, 400, 401, 403, 404, 500, 503 |
| `POST .../stock/{levelId}/adjust` | 200, 400, 401, 403, 404, 409, 413, 415, 500, 503 |
| `GET .../stock/{levelId}/movements` | 200, 400, 401, 403, 404, 500, 503 |

Semantic 409 codes: `already_exists`, `article_inactive`, `not_in_assortment`,
`stock_conflict`, `operation_conflict`. Contract errors use
`invalid_stock`/`invalid_request`/`invalid_cursor`. Movement history is
`balance_version DESC`, 50 per page; `after` is the decimal balance version.

M3 containment: the five new routes ship complete request/response/error
documentation, matching Dart contracts and OpenAPI schemas, an explicitly
tested error taxonomy (contracts test plus real-PostgreSQL reachability tests),
and no plugin grants. The broader API/error-contract cleanup remains deferred.

## DTO semantics

`StockLevelDto`: `id, locationId, articleId, stockUnit, quantity, version,
createdAt, updatedAt, article {id, sku, barcode, name, unit, isActive},
assortmentIsActive`. No `companyId`, no `openingMovementId` and no stored
`effectiveAvailability`; clients compute `article.isActive &&
assortmentIsActive`. `StockMovementDto`: `id, kind, delta, balanceAfter,
balanceVersion, recordedAt, recordedBy, note`; history inherits the level's
immutable `stockUnit` and carries no unit per movement.

## Runtime grants

- projection view: `SELECT`
- `stock_levels`: `SELECT, INSERT`, `UPDATE (quantity_scaled, version,
  updated_at)`, `REVOKE DELETE, TRUNCATE`
- `stock_movements`: `SELECT, INSERT`, `REVOKE UPDATE, DELETE, TRUNCATE`

## Flutter

A **Bestand** section (gated by `stock.levels.manage`) provides a location
selector, list/search with load-more, quantity plus immutable unit, live
article/assortment activity indicators, an article-unit divergence hint, an
open dialog sourced from the location's active assortment (globally inactive
articles excluded, already-carried articles disabled), an adjust dialog with a
required correction reason, and movement history paged by balance version.
The intended client flow keeps the exact `movementId` for an ambiguous retry and
avoids attributing another actor's same-quantity command. The follow-up below
records the duplicate-submission limitation.

## Original local verification — 2026-10-03

- contracts: 69 tests (8 stock contract/OpenAPI tests)
- server: 201 real-PostgreSQL tests, including 20 stock integration tests
  (open/adjust/replay/conflict/concurrency/search completeness/deactivation/
  grants/ledger invariants/version bounds/migration 0015 upgrade and failed
  migration rollback)
- Flutter: 181 tests, including 16 stock controller/widget tests
- update/recovery acceptance passes through `0010 → 0015` with populated data,
  stock schema/grants probes, stock HTTP smoke and isolated restore fencing
- `flutter build web --release --no-web-resources-cdn` passes
- `./scripts/dev.ps1 check` passes with `STOREOS_TEST_DATABASE` configured

## Remaining boundaries

At the original local verification, the slice was uncommitted and independent
review/remote CI were pending; this is historical evidence. The
numeric guided-work browser E2E was not rerun locally. No valuation, receiving,
waste, counting, sales, transfers, suppliers, purchasing or unit conversions
exist, and no stock behavior was added to inventory.

## Historical follow-up — 2026-10-04

Commit `e8ce8c3` includes migration 0015 and the server/client implementation.
The intended client retry behavior above is not reliable under duplicate dialog
submission: pending identity can be replaced before the busy guard; dialog failures
lose input and a mock ignores stale-version enforcement. F01/F06/F07 remain open
in [technical debt](technical-debt.md). The strict server replay/version contract
is implemented; no silent ledger overwrite was demonstrated. Earlier local test
and update/recovery outcomes remain the original runs, not independent approval
or current-head remote CI. See [actual status](../roadmap/status.md).

## Historical acceptance correction — 2026-10-04

Correction implemented; independent review pending; changed-commit remote CI pending.
P4.3 remains **ACTIVE**. Work stays uncommitted directly on `main`.

Baseline was verified dynamically: clean `main` at
`22b600bb3483cfcf4e114c8303c3ca5e1db63522`, matching the live remote head,
one worktree, no stash, foundation and documentation reconciliation committed,
and migration chain 0001–0015 unchanged. Baseline
[CI run 37192907355](https://github.com/RobinBrohl/storeos/actions/runs/37192907355)
was completed successfully; it does not cover the uncommitted correction.

### Client behavior

- The synchronous submission guard precedes validation and movement-ID allocation.
  A duplicate call cannot clear state, allocate an ID or replace payload.
- Shared quantity/note validation precedes command creation, including 500-rune,
  single-line/control/surrogate and incrementable-version bounds. Invalid input
  sends no request and stays visible with field errors.
- One immutable command binds actor, opaque session identity and epoch, Location, StockLevel,
  movementId, expectedVersion, canonical quantity and normalized note.
- Outcomes distinguish confirmed mutation/replay, confirmed no-op, invalid input,
  unconfirmed, conflict and rejection. Ignored duplicate/context-invalid calls do
  not change the active result. Refresh failure is a separate dimension.
- Only a valid direct response to the submitted identity confirms the command.
  Quantity, version and history-page absence are never reconciliation evidence.
  A transport/HTTP-timeout/5xx/malformed response retains uncertainty for exact retry.
- Exact retries preserve all identity/payload fields. `stock_conflict` proves the
  retained operation was not committed; `operation_conflict` rejects that identity.
  Both clear uncertainty, preserve diagnostic/input context and require explicit
  authoritative reload/new decision. No rebase or automatic ID replacement occurs.
- A successful mutation/replay clears pending tracking before list refresh. A
  failed refresh keeps confirmation, the response level and a reload warning;
  it offers no write retry. Confirmed no-op records no fabricated evidence.
- The dialog retains invalid/failed input, disables duplicate sends, locks an
  uncertain payload, and auto-closes only for confirmation without a refresh
  warning. Refresh warnings require explicit acknowledgement.
- Pending tracking survives dialog close, Stock section remount and failed reads.
  Location switching is blocked until resolution or explicit local abandonment.
  Abandonment neither cancels a server request nor reverses/proves non-commit.
  The initial session-fencing implementation had a replacement-status window;
  independent review R1 rejected its completeness claim. The targeted follow-up
  below adds immediate context publication and independent live-identity checks.

Tracking remains memory-only. Browser reload, logout and client/session replacement
cannot guarantee recovery of an unconfirmed adjustment. This is not durable offline
recovery, a persistent command store or an offline queue.

### Fake, contract and production scope

The fake checks committed replay/actor/scope/payload conflict before new-command
version checks, then no-op or atomic modeled movement/audit effects. Another actor's
write uses that same fake service path. Committed late replay and unused stale retry
are separate regressions; real production semantics remain authoritative.

Only two Stock opening-note OpenAPI descriptions changed: the `note` key is required
and its value may be null. Required keys, nullable behavior, decoder, routes and JSON
shapes remain unchanged. No production server, persisted model, migration, runtime
grant, authorization, audit/event, dependency or lockfile change was made.

### Initial correction verification (before targeted R1–R3 fixes)

- Stock controller/widget suite: **37 passed**, with controlled completers and no
  timing sleeps for held-request/duplicate/session regressions.
- Existing real PostgreSQL Stock suite: **20 passed**, preserving replay, no-op,
  stale conflicts, actor/scope/payload rejection, atomic evidence, grants and
  migration 0015 upgrade/rollback checks.
- Real Flutter controller/HTTP/PostgreSQL journey: **1 client test + 1 fixture test
  passed**. A lost committed response replays after a later write; a never-sent
  stale ID conflicts even after the same target is reached; no-op and confirmed
  mutation with failed refresh retain their correct meanings. Database verification
  found exactly **5 movements, 4 adjustment audits, version 5**, with ledger invariant
  intact. All fixtures used new isolated test databases/roles and cleaned them up.
- Final full `scripts/dev.ps1 check`: **474 passed** (69 contracts, 201 server,
  202 Flutter, 2 design-system), no skipped tests; all four analyzers and
  176-file format checks plus Compose quiet validation pass. Web release build
  passes with `--no-pub --no-web-resources-cdn`. The required check uses existing
  dependencies with Flutter `--no-pub`; no installation or upgrade occurs.
- `git diff --check` passes. Migrations 0001–0015 and dependency/lockfiles are unchanged.

The real journey reuses the existing Stock suite's isolated fixture. With the
documented test database/runtime environment and an installed matching Flutter SDK:

```powershell
cd apps/server
dart test tool/stock_client_journey.dart --reporter expanded
```

It explicitly invokes `apps/client_flutter/test/stock_http_journey.dart`; ordinary
server test discovery does not require a Flutter SDK. No Stock browser harness
already exists. Browser-level Stock E2E, numeric browser E2E, backup/update wrappers
and physical-device acceptance were not run for this correction; the bounded real
controller/HTTP/database journey, widget regressions and Web build provide the
freshly executed client evidence.

## Historical targeted review corrections — 2026-10-04 (R1–R3)

The first independent correction review returned **CHANGES REQUIRED** for R1
(HIGH), R2 (MEDIUM) and R3 (LOW). The following record preserves the fixes and
verification before the final targeted approval and commit recorded below.

R1, R2 and R3 are implemented locally; targeted fix review and changed-commit CI
remain pending. P4.3 remains **ACTIVE**, with no commit or branch change.

- **R1:** Installing a new session publishes its opaque identity immediately,
  before awaiting status. Stock binds every pending command to that identity and
  its epoch, compares the live identity before sending and after async boundaries,
  and ignores old-session outcomes. Replacement discards local pending/diagnostic
  state and requires an authoritative reload; it does not cancel or reverse a
  server operation. Stock opening, adjustment and history dialogs hide old-context
  content and cannot publish stale callbacks into the replacement context.
- **R2:** HTTP 413/415 are definitive body-parser rejections: no uncertain pending
  retry remains, input stays editable, and location selection is not locked.
  Transport/timeout/malformed/5xx uncertainty remains conservative.
- **R3:** Local abandonment uses a separate decision-required state, never a
  server-conflict/rejection label. Its message says the original commit outcome
  remains unknown. New adjustments require an explicit reload/new decision.

The same-account held-status regression failed on the reviewed implementation:
retry returned `unconfirmed` instead of being ignored. Old-result/failure, 413/415
and abandonment regressions also reproduced the review findings before the fixes.
All **54 Stock controller/widget tests** now pass, including held replacement
status for both accounts, original-token assertions, late result/failure fencing,
old-dialog data isolation, stale abandonment confirmation, definitive rejections
and neutral abandonment semantics. This adds 17 cases to the reviewed suite and
extends its existing abandonment test.
No arbitrary timing sleeps are used.

Fresh verification for this follow-up:

- Real PostgreSQL Stock integration suite: **20 passed**.
- Existing real controller/HTTP/PostgreSQL journey: **1 client + 1 fixture test
  passed**, with exactly **5 movements, 4 adjustment audits, version 5** and the
  ledger invariant intact. Production server and journey code were unchanged.
- Final `scripts/dev.ps1 check`: **491 passed** (69 contracts, 201 server,
  219 Flutter, 2 design-system), with no skipped tests. All four analyzers,
  176-file format checks and Compose quiet validation pass. This final check ran
  after the last session-bound callback guard and stale-confirmation regression.
- Final client analysis/full tests and release Web build also pass. Flutter
  analyze/test/build invocations use `--no-pub`; a process-local wrapper supplies
  that flag to the unchanged development script. The Web build uses
  `--no-web-resources-cdn`. No dependency installation or upgrade was performed.
- Both verification runs used new isolated test databases and owner/runtime roles.
  Fixtures, their databases/roles and temporary password files were removed;
  the normal StoreOS database was untouched. Logs remain under ignored
  `.local/p43-r123/`.
- `git diff --check` passes. Migrations 0001–0015, dependency/lockfiles, production
  server behavior, schema and runtime grants remain unchanged.

Browser-level Stock/numeric E2E, backup/update wrappers and physical-device
acceptance were not run for this follow-up. The initial verification above remains
historical evidence for the earlier correction; this follow-up does not establish
independent approval or changed-commit CI.

## Final acceptance closure — 2026-10-04

**P4.3 Manual Stock Foundation: DONE/CLOSED.** No further P4.3 remediation is
required absent regression.

### Accepted review and commit evidence

- Foundation commit: `e8ce8c319e2dd3051b402d252a0666f33b170fa3`.
- Acceptance correction commit: `f9c8b070f870cabbba3ae7b63bf16190b46aad8e`
  (`Harden stock adjustment retry flow`), directly following `22b600b` on `main`.
- Independent pre-commit targeted review: **APPROVE**, **28/28 acceptance criteria
  PASS**; R1 HIGH (session replacement fencing), R2 MEDIUM (HTTP 413/415 definitive
  rejection classification) and R3 LOW (local abandonment wording/state) **CLOSED**.
- Review conclusion: no new actionable findings, no commit blockers, no additional
  architecture work required; correction safe to commit and P4.3 may close after
  changed-commit CI is green.
- Review provenance: the operator supplied the authoritative pre-commit review
  result and identified the reviewed correction as `f9c8b07` in the closure request.
  This documentation pass records that result; it does not perform another review.

The committed diff was checked against the described correction scope. Production
changes are confined to the Flutter session identity, Stock adjustment controller
and Stock dialogs; supporting regressions, the real client journey/fixture and
documentation correspond to that scope. The only OpenAPI changes in that commit
correct two opening-note descriptions (required key, nullable value). There are no
production server, migration, operational script, dependency or lockfile changes in the
correction commit. The baseline checkout is exactly that commit, with no intervening
commit or local change. This is a scope/correspondence check against the supplied
review attestation, not a separate byte-for-byte comparison with a reviewed-tree
artifact, which was not supplied.

### Changed-commit remote CI

[GitHub Actions run 37199144795](https://github.com/RobinBrohl/storeos/actions/runs/37199144795)
was verified remotely as completed/success for
`f9c8b070f870cabbba3ae7b63bf16190b46aad8e`. All five jobs and all their steps succeeded:

| Job | Result |
| --- | --- |
| `dart` — contracts/server, real PostgreSQL migrations and HTTP smoke | SUCCESS |
| `flutter` — design system, Flutter client and Web build | SUCCESS |
| `numeric-guided-work-e2e` — real browser/HTTP/PostgreSQL journey | SUCCESS |
| `backup-restore-acceptance` | SUCCESS |
| `update-recovery-acceptance` | SUCCESS |

F01/F06/F07 and R1/R2/R3 are **CLOSED**, resolved by `f9c8b07`, review APPROVE
and this green CI. Migration chain remains exactly 0001–0015, ending at
`0015_manual_stock.sql`; the correction changes no applied migration.

### Accepted boundaries and next state

Pending adjustment recovery remains memory-only. Browser reload, logout or session
replacement cannot guarantee continued recovery of an uncertain command. Local
abandonment/session replacement neither cancels nor reverses a server operation.
Raw runtime-role SQL remains outside supported-writer semantics under the accepted
threat model; this closure does not expand the database-grant guarantee.

This closes the defined bounded software acceptance slice. Stock browser E2E was
not run locally; no physical-device/accessibility acceptance, production certification
or resolution of all operator decisions is claimed. Remote numeric browser E2E and
backup/update acceptance above do not change the earlier local-run history.
M1/M3/M4 and unrelated live debt retain their existing triggers; M2 remains closed
by migration 0012. This documentation pass reruns no software tests or wrappers.

Next: fresh P4.4 capability selection from the reconciled product vision. No next
capability has been selected or implemented by this closure.
