# P4.2: Article–location assortment

Current status (2026-10-04): committed as `3bc27d5`; historical remote CI is
recorded in the prior HANDOVER/status and update/recovery follow-up. No new online
CI verification or independent approval is inferred here. See [actual status](../roadmap/status.md).

Original implementation status (2026-10-03, historical): implemented and verified locally (contracts, real
PostgreSQL, real HTTP, Flutter and the extended `0010→0014` update/recovery
acceptance); the change set is uncommitted and independent review plus remote CI
are pending. Baseline at implementation start: `d90dd7e`. Decision record:
[ADR 0016](../adr/0016-article-location-assortment.md).

## Goal

An authorized administrator can maintain which company articles a location
carries: enable an article at a location, list/search a location's assortment,
read one membership, deactivate it and reactivate it. The article stays
company-wide; the assortment is a location-scoped association. Nothing is
hard-deleted; every change and its audit entry commit atomically. This is
configuration only: no stock, quantity, ledger, valuation, supplier, purchasing,
price or unit-conversion behavior exists.

## Exact scope

- New `inventory` aggregate `ArticleLocationAssortment` (files in
  `apps/server/lib/src/inventory/`).
- New migration `0014_location_assortment.sql`:
  `article_location_assortment` with client UUID, immutable
  `company_id`/`article_id`/`location_id`, `is_active`, version, timestamps,
  `UNIQUE (company_id, article_id, location_id)`, composite FKs to
  `articles(id, company_id)` and `locations(id, company_id)`, and two
  page/filter indexes.
- Explicit runtime grants in `MigrationRunner`: `SELECT, INSERT`, column
  `UPDATE (is_active, version, updated_at)`, `REVOKE DELETE, TRUNCATE`.
- Five routes under
  `/api/v1/platform/locations/<locationId>/assortment`, one management
  capability `inventory.assortment.manage` (admin only) and the audit actions
  `inventory.assortment.created/deactivated/reactivated`.
- Shared Dart contracts and OpenAPI documentation with M3 containment tests.
- Flutter section **Sortiment** with a location selector, active-only default,
  search, "Auch inaktive anzeigen", add-article dialog, deactivate/reactivate,
  pagination and explicit conflict handling.
- Extended update/recovery acceptance (`0011`–`0014`) with an assortment
  schema/grants probe and a real HTTP create/read.

Out of scope: stock quantities or ledger, valuation, suppliers, purchasing,
receiving, batches/MHD, waste, recipes/nutrition, prices/tax, categories,
images, planograms, GTIN validation, unit conversions, events, plugins, offline
writes, M1 / global M3/M4 cleanup, company-lock changes.

## Domain model

`ArticleLocationAssortment` (owner `inventory`, location-scoped):

| Field | Rule |
| --- | --- |
| `id` | client-supplied UUID, immutable, never reused |
| `companyId` | from the authenticated principal only, immutable |
| `articleId` | company article, immutable, composite FK to the article |
| `locationId` | company location from the route, immutable, composite FK |
| `isActive` | membership state; deactivation never deletes |
| `version` | starts at 1, +1 per accepted mutation, JSON-safe maximum |
| `createdAt`/`updatedAt` | database clock |

Exactly one durable row per `(companyId, articleId, locationId)`; an inactive
pair must be reactivated, never recreated. Article identity and ownership stay
unchanged; location ownership stays with `organization`.

## Membership state vs article state

`association.isActive` means "this location is configured to carry this
article". `article.isActive` means "the company article itself is active". They
are independent and both are exposed. Effective operational availability is
`association.isActive && article.isActive`, computed by consumers and never
stored. Article deactivation does not mutate or cascade into assortment rows;
an active membership with a globally inactive article is listed and marked.
A new association and a reactivation require a globally active article
(`409 article_inactive`); deactivation of a membership always remains possible.
Reactivating the article later makes an already-active membership operationally
available again without an assortment write.

## API contract

`GET /api/v1/platform/locations/<locationId>/assortment?after&q&active` —
location-scoped keyset page ordered by association id, at most 50 items,
`nextCursor` is the last association UUID. `active` filters membership state
only: `true` active memberships, `false` inactive ones, omitted both; an
`active=true` result may embed a globally inactive article by design. `q` is a
literal case-insensitive article name/SKU search where `%`, `_` and `\` are
literal characters. Malformed `after` returns `400 invalid_cursor`; malformed
`q`/`active` returns `400 invalid_request`; unknown or foreign locations return
`404 not_found`.

`POST /api/v1/platform/locations/<locationId>/assortment` — body exactly
`{id, articleId}`; the server derives the company from the session. `201` with
the persisted membership (version 1, `isActive=true`). Unknown location or
article `404`; duplicate id or existing pair (including an inactive pair)
`409 already_exists` with zero writes; globally inactive article
`409 article_inactive`.

`GET .../assortment/<id>` — own location `200`, including inactive memberships
and globally inactive articles; unknown ids, ids of another location and
unknown or foreign locations `404`.

`POST .../assortment/<id>/deactivate` and `.../reactivate` — body
`{expectedVersion}`. Gate order: locate under company+location, validate the
expected version, then the target-state no-op check, then the article-active
check for reactivation, then the version-predicated mutation and audit. A stale
request therefore never becomes a no-op; a current-version request already in
the target state returns `200` without a version bump or audit; a real
transition bumps the version and audits once. Reactivation of a globally
inactive article returns `409 article_inactive`; deactivation never checks the
article state. There is no delete route.

Per-route reachable statuses: list/get `200, 400, 401, 403, 404, 500, 503`;
create `201, 400, 401, 403, 404, 409, 413, 415, 500, 503`; deactivate/reactivate
`200, 400, 401, 403, 404, 409, 413, 415, 500, 503`. Generic `409 conflict` is
not reachable because only the assortment uniqueness indexes are mapped, and
they map to `already_exists`/`assortment_conflict`.

## Authorization and tenancy

`inventory.assortment.manage` is granted to `admin` only; `auditor`, `employee`,
`viewer` and unknown roles receive `403`, anonymous tokens `401`, plugin tokens
are rejected. Every statement filters `company_id` and `location_id`; the route
location is validated with the company-scoped
`OrganizationService.requireConfiguredLocation`. Associations of another
location or company are `404` without an existence leak.

## Transaction, concurrency and idempotency

All commands run in one `runAuthorized` transaction under the company advisory
lock; membership row and audit commit together, and an injected audit failure
rolls back the whole change. Version guards are SQL predicates; the unique pair
is the database backstop. Concurrent duplicate enables collapse to one row, one
audit and one `409`; two same-target lifecycle commands yield exactly one
version bump and one `409`. A mixed deactivate/reactivate race may legitimately
produce two `200`s (one current-state no-op); only the invariants are asserted:
one real mutation, no lost update, audit count equal to real transitions.

## Lost-response reconciliation

The client UUID is the create reconciliation key: after an ambiguous create the
client reads the exact association id and only confirms when id, article and
location match; a duplicate pair under a different UUID stays
`409 already_exists`. Lifecycle commands reconcile exactly: target state with
`version == expected` is a confirmed no-op, `version == expected + 1` is a
confirmed single mutation, a later version is ambiguous and surfaces an explicit
conflict/reload state. No automatic replay.

## Audit and events

`inventory.assortment.created`, `.deactivated`, `.reactivated` are appended in
the same transaction with entity type `assortment`, the association UUID, the
subject location as location context and bounded changes (`articleId`,
`isActive`, `version`). No article names, SKUs or free text are audited. No
domain or outbox event is emitted; `inventory` remains a documented
non-emitter.

## Original local verification — 2026-10-03

- `packages/api_contracts`: 61 tests passed, including assortment DTO/input
  validation, JSON-safe version boundaries and OpenAPI containment (exact
  paths, methods, statuses, schemas, bounds and `openapi.yaml` references).
- `apps/server`: 181 tests passed against an isolated PostgreSQL test database,
  including the assortment success/refusal matrix, membership-vs-article-state
  independence, multi-location isolation, literal wildcard search, lifecycle
  no-op/stale ordering, version boundaries, authorization, concurrency, audit
  rollback, runtime grants, populated `0013→0014` upgrade, failed `0014`
  rollback.
- `apps/client_flutter`: 165 tests passed, including assortment capability
  gating, location selection, active-only default, include-inactive, article
  inactivity markers, enable/lifecycle, lost-response reconciliation
  (no-op/one-mutation/ambiguous), conflict reload, duplicate submit, pagination
  and the add dialog.
- `packages/design_system`: tests and analyzer pass.
- The controlled update/recovery acceptance passed on the extended
  `0010→0014` chain, including its extended HTTP smoke: exactly `0011`–`0014`
  applied once, article and assortment schema/grants probed, a real HTTP
  assortment created and read, and isolated recovery fencing intact
  (`scripts/update/Run-UpdateRecoveryAcceptance.ps1`, run
  `fb710b7ac2c249a9`, sanitized report under `.local/update-recovery/`).
- Formatter and analyzer checks pass in all four packages.
- `flutter build web --release --no-web-resources-cdn` compiles the shared
  contracts with `dart2js`, pinning the JavaScript-safe version bounds.
- All locally executed previous suites are green; the numeric guided-work
  browser E2E was not run locally and is pending remote CI. The Flutter Web
  release build and the controlled update/recovery acceptance passed locally as
  listed above.
- Independent review and remote CI are pending.

## Original boundaries and debt — 2026-10-03

M1, the global M3/M4 cleanup, L1-L12, fixture duplication, company-lock
granularity, offline behavior and retention/export remain deferred and
untouched. `unit` remains an uninterpreted label. Stock movements, receiving
lines and order lines must later reference `(article_id, location_id)` directly
and must not reference the assortment UUID or depend on its lifecycle. This
document does not claim inventory, stock or purchasing functionality.

## Follow-up — 2026-10-04

The original pending/uncommitted wording in the dated evidence above is preserved.
The slice is now committed, and manual Stock uses its released Inventory projection
under ADR 0017. That does not add stock quantities to Assortment or decide units,
receiving or valuation. Current Stock acceptance remains ACTIVE; see
[P4.3](phase-4-3-manual-stock.md) and [technical debt](technical-debt.md).
