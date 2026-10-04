-- P4.3 Manual Stock Foundation.
--
-- This file contains two ownership areas:
--
-- 1. Inventory releases one read-only projection view,
--    inventory_article_location_projection, as its public database port for
--    stock. The view is an intra-inventory join of the inventory-owned tables
--    articles and article_location_assortment; stock may read the view and must
--    never join the inventory base tables directly.
-- 2. The new logical stock module owns stock_levels (transactionally
--    maintained current projection, one row per company article and location)
--    and stock_movements (append-only authoritative ledger). The ledger stores
--    exact scaled integer thousandths; stock_unit snapshots the article unit
--    label at opening so later Article.unit edits cannot reinterpret history.
--    Manual targets are non-negative; a future movement kind that needs
--    negative operational balances must relax the CHECK in a new forward-only
--    migration. Timestamps are evidence only; movement order is
--    balance_version.
CREATE VIEW {{schema}}.inventory_article_location_projection AS
SELECT
  assortment.company_id,
  assortment.location_id,
  assortment.article_id,
  article.sku,
  article.barcode,
  article.name,
  article.unit,
  article.is_active AS article_is_active,
  assortment.is_active AS assortment_is_active
FROM {{schema}}.article_location_assortment AS assortment
JOIN {{schema}}.articles AS article
  ON article.id = assortment.article_id
  AND article.company_id = assortment.company_id;

-- Owned by stock. Current projection of the manual on-hand quantity. The
-- runtime role may update only quantity_scaled, version and updated_at; scope
-- columns, the immutable stock_unit snapshot and created_at stay fixed.
CREATE TABLE {{schema}}.stock_levels (
  id uuid PRIMARY KEY,
  company_id uuid NOT NULL,
  location_id uuid NOT NULL,
  article_id uuid NOT NULL,
  stock_unit text NOT NULL,
  quantity_scaled bigint NOT NULL,
  version bigint NOT NULL DEFAULT 1,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  -- Exactly one durable level per company article and location. This is also
  -- the database backstop for concurrent open requests.
  CONSTRAINT stock_levels_scope_unique UNIQUE (company_id, location_id, article_id),
  -- Full identity anchor used by the movement table to bind each movement to
  -- the exact level scope structurally.
  CONSTRAINT stock_levels_identity_unique
    UNIQUE (id, company_id, location_id, article_id),
  CONSTRAINT stock_levels_article_fk
    FOREIGN KEY (article_id, company_id)
    REFERENCES {{schema}}.articles(id, company_id) ON DELETE RESTRICT,
  CONSTRAINT stock_levels_location_fk
    FOREIGN KEY (location_id, company_id)
    REFERENCES {{schema}}.locations(id, company_id) ON DELETE RESTRICT,
  CONSTRAINT stock_levels_quantity_valid
    CHECK (quantity_scaled BETWEEN 0 AND 999999999999999),
  CONSTRAINT stock_levels_version_valid CHECK (version > 0),
  CONSTRAINT stock_levels_unit_valid CHECK (
    length(stock_unit) BETWEEN 1 AND 32 AND stock_unit = btrim(stock_unit)
    AND stock_unit !~ '[[:cntrl:]]')
);
-- Location-scoped keyset page ordered by level id.
CREATE INDEX stock_levels_location_page
  ON {{schema}}.stock_levels (company_id, location_id, id);

-- Owned by stock. Append-only authoritative movement ledger. The full-scope
-- composite foreign key makes a movement claiming another location, article or
-- company than its level structurally impossible. balance_version is unique
-- and monotone per level, so it is the only ordering key; recorded_at is
-- evidence. Movement rows carry no optimistic version.
CREATE TABLE {{schema}}.stock_movements (
  id uuid PRIMARY KEY,
  stock_level_id uuid NOT NULL,
  company_id uuid NOT NULL,
  location_id uuid NOT NULL,
  article_id uuid NOT NULL,
  kind text NOT NULL,
  delta_scaled bigint NOT NULL,
  balance_after_scaled bigint NOT NULL,
  balance_version bigint NOT NULL,
  recorded_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  recorded_by uuid NOT NULL,
  note text,
  CONSTRAINT stock_movements_level_fk
    FOREIGN KEY (stock_level_id, company_id, location_id, article_id)
    REFERENCES {{schema}}.stock_levels(id, company_id, location_id, article_id)
    ON DELETE RESTRICT,
  -- The account table has no (id, company_id) unique anchor and this slice
  -- must not alter the Account aggregate; the single-column FK plus the
  -- revalidated company lock is the supported binding.
  CONSTRAINT stock_movements_actor_fk
    FOREIGN KEY (recorded_by)
    REFERENCES {{schema}}.accounts(id) ON DELETE RESTRICT,
  CONSTRAINT stock_movements_kind_valid
    CHECK (kind IN ('opening', 'adjustment')),
  CONSTRAINT stock_movements_delta_valid
    CHECK (delta_scaled BETWEEN -999999999999999 AND 999999999999999),
  CONSTRAINT stock_movements_balance_valid
    CHECK (balance_after_scaled BETWEEN 0 AND 999999999999999),
  CONSTRAINT stock_movements_version_valid CHECK (balance_version > 0),
  CONSTRAINT stock_movements_note_valid CHECK (
    note IS NULL OR (length(note) BETWEEN 1 AND 500 AND note = btrim(note)
      AND note !~ '[[:cntrl:]]')),
  -- Movement history order and the per-level version invariant.
  CONSTRAINT stock_movements_level_version_unique
    UNIQUE (stock_level_id, balance_version)
);
