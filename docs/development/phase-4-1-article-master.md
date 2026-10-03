# P4.1: Company-wide article master foundation

Status (2026-10-03): implemented and verified locally (contracts, real
PostgreSQL, real HTTP, Flutter and the extended update/recovery acceptance);
the change set is uncommitted and independent review plus remote CI are pending.
Baseline at implementation start: `f37dd6b`. Decision record:
[ADR 0015](../adr/0015-company-wide-article-master.md).

## Goal

An authorized administrator can maintain a company-wide article/product master:
create, read, search, edit, deactivate and reactivate articles with an internal
SKU, an optional opaque barcode, a name, an optional description and a unit.
The article keeps its identity and lifecycle; nothing is hard-deleted; every
change and its audit entry commit atomically. This is master data only: no
stock, supplier, purchasing, price, batch/MHD, recipe or HACCP behavior exists.

## Exact scope

- New logical module `apps/server/lib/src/inventory/` owning one aggregate.
- New migration `0013_article_master.sql`: `articles` table, company FK,
  `UNIQUE (id, company_id)`, generated deterministic `sku_key`, uniqueness
  indexes, validation CHECKs and page indexes.
- Minimal runtime grants in `MigrationRunner`.
- Six routes under `/api/v1/platform/articles`, one new capability
  `inventory.articles.manage` (admin only) and the audit actions
  `inventory.article.created/updated/deactivated/reactivated`.
- Shared Dart contracts and OpenAPI documentation with M3 containment tests.
- Flutter section **Artikel** with active-only default list, search,
  "Auch inaktive anzeigen", pagination, create/edit/deactivate/reactivate and
  explicit conflict handling.
- Extended update/recovery acceptance (`0011`, `0012`, `0013`) with an article
  schema/grants probe and a real HTTP article create/read.

Out of scope: stock quantities or ledger, valuation, suppliers, purchasing,
receiving, batches/MHD, waste, recipes/nutrition, prices/tax, categories,
images, location assortment, GTIN validation, unit conversions, events,
plugins, offline writes, M1/M3-global/M4 cleanup, company-lock changes.

## Domain model

`Article` (owner `inventory`, company-wide):

| Field | Rule |
| --- | --- |
| `id` | client-supplied UUID, immutable, never reused |
| `companyId` | from the authenticated principal only, immutable |
| `sku` | required, trimmed, 1-64 chars, no control chars; case-insensitive per company for ASCII letters via a deterministic fold; Unicode compared exactly |
| `barcode` | optional opaque text, trimmed, 1-64 chars, no control chars, leading zeroes preserved; unique per company while non-null |
| `name` | required, 1-120 chars, trimmed, no control chars |
| `description` | optional, 1-2000 chars, trimmed; blank canonicalizes to null; not copied into audit |
| `unit` | required bounded label, 1-32 chars, trimmed, no control chars; no conversion semantics |
| `isActive` | lifecycle flag; deactivation never deletes |
| `version` | starts at 1, increments by exactly one per accepted mutation |
| `createdAt`/`updatedAt` | database clock |

## API contract

`POST /api/v1/platform/articles` — body `{id, sku, barcode, name, description,
unit}` with all keys required and nullable barcode/description. `201` with the
persisted `Article`; duplicate id/SKU/barcode returns `409 already_exists` with
zero writes.

`GET /api/v1/platform/articles?after&q&active` — company-scoped keyset page
ordered by id, at most 50 items, `nextCursor` is the last article UUID.
`active=true` returns active only, `active=false` inactive only, omitted
returns both. `q` is a literal case-insensitive name/SKU search in which `%`,
`_` and `\` are literal characters. Malformed `after` returns
`400 invalid_cursor`; malformed `q`/`active` returns `400 invalid_request`.

`GET /api/v1/platform/articles/<id>` — own-company `200`, including inactive
articles; unknown or foreign ids `404`.

`POST /api/v1/platform/articles/<id>/edit` — body `{expectedVersion, sku,
barcode, name, description, unit}`; full replacement. Current-version identical
input is a no-op with no version bump and no audit; stale version returns
`409 article_conflict`; SKU/barcode collision with another article returns
`409 already_exists`.

`POST /api/v1/platform/articles/<id>/deactivate` and `.../reactivate` — body
`{expectedVersion}`. Real transitions bump the version and audit; a
current-version request already in the target state is a no-op; stale versions
return `409 article_conflict`. No delete route exists.

Validation/transport errors: `400 invalid_article` for body fields,
`400 invalid_json` for a non-object body, `413 body_too_large`,
`415 unsupported_media_type`, `401 unauthorized`, `403 forbidden`,
`404 not_found`, `500 internal_error`, `503 database_unavailable`. The generic
`409 conflict` code is not reachable through the article path because only the
article uniqueness indexes are mapped, and they are mapped to
`already_exists`.

## Authorization and tenancy

`inventory.articles.manage` is granted to `admin` only; `auditor`, `employee`,
`viewer` and unknown roles receive `403`, anonymous or plugin-style tokens
`401`. Every statement carries `company_id = actor.companyId`; the company
comes from the re-validated session inside `runAuthorized`. Articles have no
location ownership column; another location in the same company can reach the
same article.

## Transaction, concurrency and idempotency

All commands run in one `runAuthorized` transaction under the company advisory
lock; article row and audit commit together, and an injected audit failure
rolls back the whole change. Version guards are SQL predicates. Concurrent
duplicate creates collapse to one row, one audit and one `409 already_exists`;
concurrent edits and lifecycle changes produce exactly one version bump and one
`409 article_conflict` for the loser. Client-supplied UUIDs are the create
reconciliation key; there is no command receipt and no automatic replay. A lost
create response is reconciled by reading the exact article id; a duplicate SKU
from a different id is not treated as a success.

## Audit and events

`inventory.article.created`, `.updated`, `.deactivated`, `.reactivated` are
appended in the same transaction with entity type `article`, the article UUID,
the actor's location as context, and bounded changes (`name`, `sku`, `barcode`,
`unit`, `isActive`, `version`, `changedFields`). Raw description text is never
audited. No domain/outbox event is emitted; `inventory` is a documented
non-emitter.

## Verification (local, 2026-10-03)

- `packages/api_contracts`: 55 tests passed, including SKU fold semantics,
  create/edit/lifecycle input validation, DTO round-trips and OpenAPI
  containment (exact paths, methods, schemas, bounds, status sets and
  `openapi.yaml` references).
- `apps/server`: 161 tests passed against an isolated PostgreSQL test database,
  including the article success/refusal matrix, literal wildcard search,
  `active` semantics, uniqueness, no-op/stale lifecycle, concurrency,
  audit rollback, runtime grants, populated `0012→0013` upgrade, failed
  migration rollback and the extended HTTP smoke.
- `apps/client_flutter`: 148 tests passed, including controller and widget
  coverage for capability gating, active-only default, include-inactive,
  search, create/edit/lifecycle, blank-to-null canonicalization, duplicate
  submit protection, pagination and explicit conflict reload.
- The controlled update/recovery acceptance passed on the extended
  `0010→0013` chain: exactly `0011`, `0012` and `0013` applied once, article
  table/indexes/runtime grants present, a real HTTP article created and read,
  and isolated recovery fencing intact
  (`scripts/update/Run-UpdateRecoveryAcceptance.ps1`, sanitized report under
  `.local/update-recovery/`). An earlier non-injected `recovery-verify` run
  (`d56192352b67442b`) failed transiently and was not reproduced; two
  consecutive complete passing runs followed (`9e60beada9e9456b`,
  `29986f4178694493`). That failure class predates P4.1 (comparable transient
  non-injected `recovery-verify` failures occurred in the accepted 2026-10-01
  runs); root cause was not diagnosed and no P4.1-specific failure was
  identified.
- Formatter and analyzer checks pass in all four packages.
- Independent review and remote CI are pending.

## Boundaries and debt

M1, the global M3/M4 cleanup, L1-L12, fixture duplication, company-lock
granularity, offline behavior and retention/export remain deferred and
untouched. `unit` is a label, not a unit catalog; unit normalization and
conversions are deferred until a concrete stock/receiving/recipe requirement
exists. Categories, supplier references, GTIN validation and location
assortment are open product questions, not part of this slice. This document
does not claim inventory, stock or purchasing functionality.
