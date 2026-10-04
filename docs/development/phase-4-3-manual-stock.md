# P4.3 — Manual stock foundation

Status: implemented as an uncommitted slice on `main` (independent review and
remote CI pending). Baseline before the slice: committed P4.2 `3bc27d5`.
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
Ambigous adjust responses keep the exact `movementId` for an explicit retry and
never attribute another actor's same-quantity command.

## Verification

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

The slice is uncommitted; independent review and remote CI are pending. The
numeric guided-work browser E2E was not rerun locally. No valuation, receiving,
waste, counting, sales, transfers, suppliers, purchasing or unit conversions
exist, and no stock behavior was added to inventory.
