# ADR 0015: Company-wide article master foundation

Status: Accepted. Scope decided 2026-10-03 as part of the P4.1 article-master
slice.

## Context

The product vision names Produktstamm, Einkauf und Bestand as a later part of
the same platform (`docs/vision.md:13`); the roadmap starts P4 with
"Produktstamm, Einheiten, Lieferanten, Bestellungen, Wareneingang, Chargen/MHD,
Bestands-Ledger und Inventur" (`docs/roadmap/phases.md:61-63`). Until P4.1 the
implementation contains no inventory code, no stock ledger and no product
identity at all.

Two tenancy facts bound the decision: the installation is a single company with
one configured execution location, and `companies` is a singleton table per
schema, so cross-company rows cannot exist. The documented later step for
multiple sites is location assortment, and stock will be location-specific
while the product itself is not.

The following questions had to be answered before the first inventory
aggregate: is an article company-wide or location-owned; which attributes are
required for identity; how is the internal identifier made unique; what does
"unit" mean before a unit catalog exists; and how are lifecycle and deletion
handled without breaking later references.

## Decision

**Ownership.** `inventory` owns one company-wide `Article` aggregate. Articles
carry `company_id` but no `location_id`; the company comes exclusively from the
re-authenticated session principal. A later location assortment is a separate
association, and later stock/receiving records can reference
`(article_id, company_id)` through the existing `UNIQUE (id, company_id)`
anchor without changing this table.

**Minimum aggregate.** `id` (client-supplied UUID), `company_id`, `sku`,
optional `barcode`, `name`, optional `description`, `unit`, `is_active`,
`version`, `created_at`, `updated_at`. No category, price, tax, supplier, stock
quantity, batch/MHD, recipe, nutrition, image, assortment or valuation field is
added without a concrete later requirement.

**SKU policy.** Required, trimmed, 1-64 characters, no control characters;
spaces, punctuation and Unicode are allowed. No retailer-specific charset is
invented. Uniqueness is case-insensitive per company through a deterministic
ASCII-only fold: the database computes
`translate(sku, 'ABCDEFGHIJKLMNOPQRSTUVWXYZ', 'abcdefghijklmnopqrstuvwxyz')`
into a generated `sku_key`, and the shared Dart contract exposes the identical
`articleSkuKey` mapping. Non-ASCII characters compare exactly as entered. No
`citext` or other extension is added.

**Barcode.** Optional opaque text, trimmed, 1-64 characters, no control
characters, stored as text with leading zeroes preserved; unique per company
only while non-null. No GTIN/EAN check-digit validation, type detection or
scanner behavior.

**Unit.** A bounded label (1-32 characters). Examples are not domain-enforced.
A unit catalog, conversions, base/ordering/selling units and dimensional
analysis are deferred until a concrete stock, receiving or recipe requirement
exists.

**Lifecycle.** `is_active` with version-guarded deactivate/reactivate; no delete
route and no application hard-delete path. The runtime role receives
`SELECT, INSERT`, column-scoped `UPDATE` and an explicit
`REVOKE DELETE, TRUNCATE`, so inactive articles stay readable, searchable and
referenceable.

**Authorization.** Exactly one new capability, `inventory.articles.manage`,
granted to `admin` only. Reads are management reads in this slice; no
speculative `inventory.articles.read` exists. Plugin tokens remain rejected.

**Integration.** No domain or outbox event, no plugin grant, no stock behavior.
A `UNIQUE (id, company_id)` anchor is reserved for future company-scoped child
tables.

## Alternatives considered

- **Location-owned articles.** Rejected: product identity is master data shared
  by the company; a later assortment belongs in its own association, and
  location ownership would force a breaking migration or duplicated articles.
- **Hard delete or soft-delete flag with deletion.** Rejected: master data must
  remain referenceable; the non-destructive lifecycle is sufficient.
- **Strict ASCII SKU regex.** Rejected: no repository rule justifies forbidding
  spaces, `+`, `:` or Unicode in internal identifiers; migration compatibility
  matters more than formatting aesthetics.
- **`citext` or locale-sensitive `upper()`.** Rejected: adds an extension or
  collation-dependent semantics; the explicit ASCII-only fold is deterministic
  across collations.
- **Adding category, price, supplier or stock fields now.** Rejected: no
  current requirement or evidence; speculative fields become migration debt.
- **Emitting `article.created` events.** Rejected: no consumer exists (ADR
  0008).

## Consequences

- StoreOS gains its first Product/Bestand master aggregate without claiming any
  inventory, stock or purchasing functionality.
- Future location assortment, stock movements, receiving lines, waste/MHD and
  HACCP linkages can reference the article by `(id, company_id)` without
  altering migration `0013`.
- Unit values are labels, not a standardized unit system; introducing
  conversions later will require a mapping decision and possibly a migration.
- SKU uniqueness is case-insensitive for ASCII letters only; Unicode
  identifiers that differ only by case remain distinct. This is documented and
  tested rather than accidental.
- `inventory` remains a documented non-emitter like workforce and tasks.

## Open questions

- When does a shared unit catalog with conversion factors become required, and
  who owns it (inventory, purchasing or recipes)?
- Which additional master fields (categories, supplier references, GTIN
  validation) are justified by real operator data?
- Which retention/export rule applies to article master data and its audit?
- When does location assortment become necessary, and is it a company or
  location decision?
