# 0017 — Manual stock foundation

- Status: Accepted (implemented as the uncommitted P4.3 slice)
- Date: 2026-10-03
- Context slice: P4.3 Manual Stock Foundation
- Related: [ADR 0015](0015-company-wide-article-master.md), [ADR 0016](0016-article-location-assortment.md), [P4.3 contract](../development/phase-4-3-manual-stock.md)

## Context

P4.1 introduced the company-wide article master with a mutable, opaque `unit`
label. P4.2 introduced the per-location assortment membership, whose state is
independent from the global article state. The roadmap requires movement/ledger
semantics for stock and visible corrections, but no stock behavior existed yet.

Two risks framed the design:

1. `Article.unit` is mutable. If stock history referred only to the live article
   unit, a later edit ("kg" → "Stk") would silently reinterpret all historical
   quantities.
2. "Stock" is not inventory configuration. The module-boundary table assigns
   articles and assortments to `inventory` and explicitly excludes stock
   ("Bestände") from inventory ownership.

## Decision

### Module ownership

A new logical `stock` module under `apps/server/lib/src/stock/` owns
`StockLevel` and `StockMovement`. Inventory never owns stock and keeps
`Article`/`ArticleLocationAssortment` unchanged.

### Released inventory read ports

Inventory publishes a read-only projection view,
`inventory_article_location_projection` (company, location, article, sku,
barcode, name, unit, article_is_active, assortment_is_active), built from the
inventory-owned `articles JOIN article_location_assortment`. Stock may join this
released view but never joins inventory base tables directly. A minimal
inventory-owned Dart port (`InventoryArticlePort`) distinguishes an unknown
article (404) from a known article without membership (409
`not_in_assortment`) and provides the normalized unit for the open snapshot.

Stock list/search is one complete stock-level query joined against the view,
keyset-paginated over stock level ids. There is deliberately no pre-truncated
article candidate set; every matching level stays reachable.

### Ledger is authoritative, level is the projection

`stock_movements` is the append-only authoritative evidence. `stock_levels` is
the transactionally maintained current projection. For every supported writer:

```
stock_levels.quantity_scaled == latest movement.balance_after_scaled
                             == SUM(movement.delta_scaled)
stock_levels.version        == latest movement.balance_version
```

Movements store both `delta_scaled` and `balance_after_scaled` deliberately.
Ordering is `balance_version` only; `recorded_at` is evidence, never an ordering
key. The company advisory lock in `runAuthorized` serializes writers, so no
cross-row database trigger is required for the supported writer set.

### Immutable unit snapshot

`StockLevel.stock_unit` copies the current normalized `Article.unit` at opening
and never changes. All movements of the level are interpreted in that unit.
A later `Article.unit` edit changes only the live article projection; the DTO
exposes both `stockUnit` and the live `article.unit`, and a mismatch is visible.
No unit catalog and no unit conversion are introduced. Freezing `Article.unit`
while stock exists was rejected: it would couple the article edit path to stock,
prevent legitimate typo fixes and still leave conversions without a per-history
unit.

### Quantities

Scale is exactly 3 (thousandths). Values are scaled `bigint` thousandths with
the bound `999999999999999` (10^15 − 1, i.e. `999999999999.999`), below
`2^53 - 1`, so shared Dart code may hold the scaled integer on Flutter Web.
Parsing and formatting use integer arithmetic only. The wire format is a
canonical decimal string (targets/balances non-negative, deltas signed). The
P1b.7 task-measurement maximum of six integer digits was deliberately not
copied: gram- and milliliter-based stock exceeds it in ordinary operations.

### Manual targets are non-negative

Opening and adjustment targets are `0 … 999999999999.999`; levels and
movement `balance_after_scaled` carry `CHECK >= 0`. Manually recorded physical
on-hand quantity is non-negative by nature. A future movement kind that needs
negative operational balances must relax the CHECK in a new forward-only
migration; this slice does not pre-enable negative stock.

### Opening and adjustment only

`opening` records the first quantity (level v1, exactly one server-generated
movement, `balance_version = 1`). `adjustment` is an absolute manual correction:
the target is the new on-hand quantity, `delta = target − current` is stored
together with `balanceAfter` and the new `balanceVersion`, and the note is the
required correction reason. No receiving, waste, count, sale, transfer or
valuation semantics exist. Future kinds extend the CHECK additively and add
their own typed, nullable provenance columns.

### Operation identity for adjustments

The client-generated `movementId` is the operation identity and becomes the
movement row id. Before any stale-version handling the service looks up the
movement id: an exact replay (same level, company, location, actor,
`expectedVersion`, target and note) returns 200 with the current authoritative
level and writes nothing, even after later movements. Any reuse with a
different scope, actor or payload returns 409 `operation_conflict` with zero
writes. A matching-version no-op writes no movement, so it consumes no
operation id. A generic receipt table or a task-receipt refactor was rejected
as unnecessary infrastructure.

Opening uses the client-generated level UUID as its operation identity; a lost
response is confirmed by reading the route-scoped level id, not by comparing the
current quantity. No `openingMovementId` is exposed.

### Creation gate and deactivation

Opening requires an existing, globally active article (`409 article_inactive`)
with an active assortment membership at the location (`409 not_in_assortment`
for both absent and inactive membership). Existing levels remain listable,
readable, adjustable and auditable after an article or assortment deactivation,
so remaining stock is never stranded. No cascade and no stock-level active flag
or delete route exist.

### Capability

Exactly one new capability, `stock.levels.manage`, governs list, get, open,
adjust and movement history. It is admin-only initially and is not shared with
inventory capabilities, so future operators can be authorized independently.

## Alternatives considered

- **Freeze `Article.unit` when stock exists** — rejected (coupling, UX, typo
  correction).
- **Task-style receipt table** — rejected (task-coupled schema, generalized
  refactor).
- **Version+target reconciliation without operation identity** — rejected: it
  can falsely attribute another actor's same-quantity command.
- **A pre-truncated article candidate port for search** — rejected: it changes
  search semantics and can permanently hide valid levels.
- **Six-integer-digit quantities (P1b.7 bound)** — rejected as a measurement
  bound, not an inventory bound.
- **Negative balances** — rejected for manual targets; relaxation stays an
  explicit future migration.

## Consequences

- Migration `0015` adds one projection view and two tables; 0001–0014 are
  untouched. Runtime grants keep movements append-only and restrict level
  updates to `quantity_scaled`, `version`, `updated_at`.
- Audit records `{articleId, movementId, version}` (opened) and
  `{articleId, movementId, oldVersion, version, changedFields}` (adjusted); the
  numerical evidence stays in the ledger, and `movementId` was added to the
  audit allowlist.
- The DTO exposes raw live flags (`article.isActive`, `assortmentIsActive`) and
  both unit labels; effective availability is computed by the client.
- `Article.unit` remains mutable and `InventoryArticlePort` becomes inventory's
  documented public Dart read port for foreign modules.

## Open questions

- A standardized unit catalog with conversions remains open
  ([risks](../risks-and-open-questions.md)); the frozen `stock_unit` is the
  historical anchor a later conversion would use.
- A future movement kind needing negative operational balances must define the
  policy and relax the CHECK in a new migration.
- Valuation, receiving, waste, counting, sales and transfers require separate
  slices and ADRs.
